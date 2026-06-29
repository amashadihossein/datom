# Lineage validation helpers

#' Validate Source Lineage Consistency
#'
#' Checks that a table's declared `source_lineage` matches the union of its
#' parents' `source_lineage` fields. Detects missing entries (in the computed
#' union but absent from declared), extra entries (declared but not in the
#' union), and wrong-version entries (matching project+table but different
#' `version_sha`).
#'
#' datom validates schema shape only at write time. This function provides
#' on-demand semantic checking, suitable for CI runs, audits, or pre-publication
#' gates.
#'
#' Tables without `parents` return `status = "unchecked"` -- there is no union
#' to compare against. Tables where any parent's metadata is unreachable return
#' `status = "error"`.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param name Table name.
#' @param version Optional metadata_sha (datom version). If NULL, checks
#'   the current version.
#'
#' @return A list with:
#'   \describe{
#'     \item{status}{One of `"ok"`, `"mismatch"`, `"unchecked"`, `"error"`.}
#'     \item{missing}{List of entries in the computed union but absent from declared.}
#'     \item{extra}{List of entries declared but absent from the computed union.}
#'     \item{wrong_version}{List of entries where project+table match but
#'       `version_sha` differs. Each element has `declared` and `computed` sub-lists.}
#'     \item{message}{Human-readable summary string.}
#'   }
#' @export
#'
#' @examples
#' \dontrun{
#' tmp <- tempfile("datom_lineage_val_")
#' store <- datom_store(
#'   data = datom_store_local(path = file.path(tmp, "storage")),
#'   github_pat = "ghp_examplePATforDemoPurposesOnly1234",
#'   data_repo_url = "https://github.com/example/my-project",
#'   validate = FALSE
#' )
#' datom_init_repo(
#'   path = file.path(tmp, "repo"),
#'   project_name = "example_project",
#'   store = store
#' )
#' conn <- datom_get_conn(path = file.path(tmp, "repo"), store = store)
#' datom_write(conn, data = datom_example_data("dm"), name = "dm")
#' datom_validate_lineage(conn, "dm")
#' unlink(tmp, recursive = TRUE)
#' }
datom_validate_lineage <- function(conn, name, version = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  .datom_validate_name(name)

  if (!is.null(version)) {
    if (!is.character(version) || length(version) != 1L || !nzchar(version)) {
      cli::cli_abort("{.arg version} must be a single non-empty string or NULL.")
    }
  }

  # --- Read subject metadata ---
  metadata_key <- if (is.null(version)) {
    paste0(name, "/.metadata/metadata.json")
  } else {
    paste0(name, "/.metadata/", version, ".json")
  }

  metadata <- tryCatch(
    .datom_storage_read_json(conn, metadata_key),
    error = function(e) {
      cli::cli_abort(c(
        "Could not read metadata for table {.val {name}}.",
        "i" = "Underlying error: {conditionMessage(e)}"
      ))
    }
  )

  parents <- metadata$parents
  declared_sl <- metadata$source_lineage %||% list()

  # --- No parents: nothing to check ---
  if (is.null(parents) || length(parents) == 0L) {
    cli::cli_alert_info("Table {.val {name}} has no parents -- source_lineage cannot be verified.")
    return(invisible(.datom_lineage_result("unchecked",
      msg = paste0("Table '", name, "' has no parents -- source_lineage cannot be verified.")
    )))
  }

  # --- Fetch each parent's source_lineage ---
  parent_lineages <- tryCatch(
    purrr::map(parents, function(p) {
      p_name <- p$table %||% ""
      p_version <- p$version %||% NULL
      if (!nzchar(p_name)) {
        cli::cli_abort("A parent entry is missing the {.field table} field.")
      }
      p_key <- if (is.null(p_version) || !nzchar(p_version)) {
        paste0(p_name, "/.metadata/metadata.json")
      } else {
        paste0(p_name, "/.metadata/", p_version, ".json")
      }
      p_meta <- tryCatch(
        .datom_storage_read_json(conn, p_key),
        error = function(e) {
          cli::cli_abort(c(
            "Could not read metadata for parent table {.val {p_name}}.",
            "i" = "Underlying error: {conditionMessage(e)}"
          ))
        }
      )
      p_meta$source_lineage %||% list()
    }),
    error = function(e) {
      return(structure(list(message = conditionMessage(e)), class = "datom_lineage_fetch_error"))
    }
  )

  if (inherits(parent_lineages, "datom_lineage_fetch_error")) {
    msg <- parent_lineages$message
    cli::cli_alert_danger("Could not fetch parent metadata: {msg}")
    return(invisible(.datom_lineage_result("error", msg = msg)))
  }

  # --- Compute union ---
  computed_union <- .datom_lineage_union(parent_lineages)

  # --- Compare declared vs computed ---
  delta <- .datom_lineage_diff(declared_sl, computed_union)

  if (length(delta$missing) == 0L && length(delta$extra) == 0L &&
      length(delta$wrong_version) == 0L) {
    cli::cli_alert_success("source_lineage for {.val {name}} is consistent with parents.")
    return(invisible(.datom_lineage_result("ok",
      msg = paste0("source_lineage for '", name, "' is consistent with parents.")
    )))
  }

  # --- Report mismatches ---
  cli::cli_alert_warning("source_lineage mismatch for {.val {name}}:")

  if (length(delta$missing) > 0L) {
    cli::cli_alert_danger(
      "{length(delta$missing)} missing entr{?y/ies} (in computed union, absent from declared)."
    )
  }
  if (length(delta$extra) > 0L) {
    cli::cli_alert_danger(
      "{length(delta$extra)} extra entr{?y/ies} (declared but not in computed union)."
    )
  }
  if (length(delta$wrong_version) > 0L) {
    cli::cli_alert_danger(
      "{length(delta$wrong_version)} wrong-version entr{?y/ies} (project+table match, version_sha differs)."
    )
  }

  msg <- paste0(
    "source_lineage mismatch: ",
    length(delta$missing), " missing, ",
    length(delta$extra), " extra, ",
    length(delta$wrong_version), " wrong-version"
  )
  invisible(.datom_lineage_result("mismatch", delta = delta, msg = msg))
}


# --- Internal helpers ----------------------------------------------------------

#' Build a lineage validation result list
#' @noRd
.datom_lineage_result <- function(status,
                                  delta = list(missing = list(), extra = list(),
                                               wrong_version = list()),
                                  msg = "") {
  list(
    status        = status,
    missing       = delta$missing %||% list(),
    extra         = delta$extra %||% list(),
    wrong_version = delta$wrong_version %||% list(),
    message       = msg
  )
}


#' Union and deduplicate source_lineage lists
#'
#' Takes a list of source_lineage lists and returns a single deduplicated list.
#' Dedup key is (project, table, version_sha). In case of project+table
#' collision with differing version_sha, all variants are kept (the caller's
#' diff logic will flag them).
#'
#' @param lineage_lists List of source_lineage lists (each itself a list of entries).
#' @return Deduplicated list of source_lineage entries.
#' @keywords internal
.datom_lineage_union <- function(lineage_lists) {
  all_entries <- purrr::flatten(lineage_lists)
  if (length(all_entries) == 0L) return(list())

  keys <- purrr::map_chr(all_entries, function(e) {
    paste(e$project %||% "", e$table %||% "", e$version_sha %||% "", sep = "\t")
  })

  all_entries[!duplicated(keys)]
}


#' Compute diff between declared and computed source_lineage
#'
#' @param declared List of declared source_lineage entries.
#' @param computed List of computed (union) source_lineage entries.
#' @return List with `missing`, `extra`, `wrong_version` elements.
#' @keywords internal
.datom_lineage_diff <- function(declared, computed) {
  key3 <- function(e) paste(e$project %||% "", e$table %||% "", e$version_sha %||% "", sep = "\t")
  key2 <- function(e) paste(e$project %||% "", e$table %||% "", sep = "\t")

  declared_keys3 <- purrr::map_chr(declared, key3)
  computed_keys3 <- purrr::map_chr(computed, key3)
  declared_keys2 <- purrr::map_chr(declared, key2)
  computed_keys2 <- purrr::map_chr(computed, key2)

  # Wrong-version: project+table in both, but version_sha differs
  wrong_version_pairs <- purrr::keep(
    purrr::map(seq_along(declared), function(i) {
      dk2 <- declared_keys2[[i]]
      if (dk2 %in% computed_keys2 && !declared_keys3[[i]] %in% computed_keys3) {
        j <- which(computed_keys2 == dk2)[[1]]
        list(declared = declared[[i]], computed = computed[[j]])
      } else {
        NULL
      }
    }),
    Negate(is.null)
  )

  # Entries in computed that are fully absent from declared (not even a version match)
  missing <- purrr::keep(
    seq_along(computed),
    function(i) {
      !computed_keys3[[i]] %in% declared_keys3 &&
        !computed_keys2[[i]] %in% declared_keys2
    }
  )
  missing <- computed[missing]

  # Entries in declared that are fully absent from computed (not even a version match)
  extra <- purrr::keep(
    seq_along(declared),
    function(i) {
      !declared_keys3[[i]] %in% computed_keys3 &&
        !declared_keys2[[i]] %in% computed_keys2
    }
  )
  extra <- declared[extra]

  list(missing = missing, extra = extra, wrong_version = wrong_version_pairs)
}
