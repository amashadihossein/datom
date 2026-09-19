#' Check if Path is a Valid datom Repository
#'
#' Validates datom repository structure. Used internally and by dpbuild.
#'
#' @param path Path to evaluate.
#' @param checks Which checks to perform. Any combination of "all", "git",
#'   "datom", "renv".
#' @param verbose If TRUE, prints which tests passed/failed.
#'
#' @return TRUE or FALSE.
#' @export
#'
#' @examples
#' # A plain directory is not a valid datom repository.
#' tmp <- tempfile("datom_valid_")
#' dir.create(tmp)
#' is_valid_datom_repo(tmp)
#' unlink(tmp, recursive = TRUE)
is_valid_datom_repo <- function(path,
                               checks = c("all", "git", "datom", "renv"),
                               verbose = FALSE) {
  checks <- match.arg(
    arg = checks,
    choices = c("all", "git", "datom", "renv"),
    several.ok = TRUE
  )

  dx <- datom_repository_check(path = path)

  if (!"all" %in% checks) {
    if (!"git" %in% checks) {
      dx <- dx[setdiff(names(dx), "git_initialized")]
    }
    if (!"datom" %in% checks) {
      dx <- dx[setdiff(names(dx), c("datom_initialized", "datom_manifest"))]
    }
    if (!"renv" %in% checks) {
      dx <- dx[setdiff(names(dx), "renv_initialized")]
    }
  }

  if (verbose) {
    purrr::iwalk(dx, function(val, name) {
      if (isTRUE(val)) {
        cli::cli_alert_success("{name}")
      } else {
        cli::cli_alert_danger("{name}")
      }
    })
  }

  all(vapply(dx, isTRUE, logical(1)))
}


#' Check datom Repository Structure
#'
#' Returns detailed check results for each component.
#'
#' @param path Path to evaluate.
#'
#' @return List of TRUE/FALSE per check.
#' @keywords internal
datom_repository_check <- function(path) {
  path <- fs::path_abs(path)

  list(
    git_initialized = fs::dir_exists(fs::path(path, ".git")),
    datom_initialized = fs::file_exists(fs::path(path, ".datom", "project.yaml")),
    datom_manifest = fs::file_exists(fs::path(path, ".datom", "manifest.json")),
    renv_initialized = fs::dir_exists(fs::path(path, "renv"))
  )
}


#' Validate Git-Storage Consistency
#'
#' Checks that git metadata matches S3 storage for all tables and repo-level
#' files. Reports mismatches as a structured result.
#'
#' @section What is checked per artifact:
#' Both kinds of artifact are checked, and the payload check branches on kind: a
#' table's payload is a parquet object, a set's is a JSON document at
#' `{name}/{data_sha}.json`. A **set** is checked further, because a payload
#' whose members have gone is a citation that no longer resolves:
#'
#' * every member's pinned version must still exist in this project's storage.
#'   **One level deep only** -- a member that is itself a set is confirmed to
#'   exist and its own member list is never opened, so the cost of validating a
#'   set never depends on the tree beneath it. Validating an inner set is a
#'   separate call against that set's own project.
#' * a member recorded as belonging to **another project** is checked as a
#'   well-formed pointer only. This connection sees one namespace, so an
#'   existence check there would report every cross-project member as rotten.
#' * the set must record the hash of its stored payload, without which no reader
#'   can verify it.
#'
#' Statuses reported in the `tables` frame: `metadata_missing_s3`,
#' `history_missing_s3`, `data_missing_s3`, `members_unresolvable`,
#' `document_sha_missing`, and `kind_unsupported` for an artifact whose metadata
#' declares a kind this version of datom does not know -- reported rather than
#' fatal, with that row's payload left unchecked.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param fix If `TRUE`, attempts to fix inconsistencies by syncing data-side
#'   metadata (manifest + per-artifact metadata) to storage, and by restoring a
#'   **set's** payload when storage has lost it -- git holds `{name}/set.json`,
#'   so those bytes are recoverable. A restore happens only when the stored
#'   object is absent and only when the clone's bytes hash to the
#'   `document_sha` already recorded; a stored payload is never overwritten and
#'   its recorded hash is never recomputed.
#'
#'   A missing **table** payload (`data_missing_s3`) cannot be repaired: the
#'   parquet bytes are never in the clone. Those tables are named in a warning
#'   and need [datom_write()] re-run with the source data.
#'
#' @return A list with:
#'   \describe{
#'     \item{valid}{Logical — `TRUE` if everything is consistent.}
#'     \item{repo_files}{Data frame of repo-level file checks.}
#'     \item{tables}{Data frame of per-artifact checks, one row per artifact of
#'       either kind, with a `kind` column. Named `tables` for compatibility.}
#'     \item{fixed}{Logical — `TRUE` if `fix = TRUE` was applied.}
#'   }
#' @export
#'
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   datom_write(conn, data = datom_example_data("dm"), name = "dm")
#'   datom_validate(conn)
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_validate <- function(conn, fix = FALSE) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Validation requires {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Validation requires a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # --- Repo-level file checks ---
  repo_file_checks <- .datom_validate_repo_files(conn)

  # --- Project identity check ---
  project_name_ok <- .datom_validate_project_name(conn)

  # --- Per-table checks ---
  table_checks <- .datom_validate_tables(conn)

  if (is.null(conn$gov_root)) {
    cli::cli_alert_info(
      "No governance attached -- skipping dispatch/ref/migration_history checks."
    )
  }

  all_repo_ok <- nrow(repo_file_checks) == 0L ||
    all(repo_file_checks$status == "ok")
  all_tables_ok <- nrow(table_checks) == 0L ||
    all(table_checks$status == "ok")
  is_valid <- all_repo_ok && all_tables_ok && project_name_ok

  if (is_valid) {
    cli::cli_alert_success("All checks passed. Git and S3 are consistent.")
  } else {
    n_repo_issues <- sum(repo_file_checks$status != "ok")
    n_table_issues <- sum(table_checks$status != "ok")
    cli::cli_alert_warning(
      "Found {n_repo_issues + n_table_issues} issue{?s}: {n_repo_issues} repo-level, {n_table_issues} table-level."
    )
  }

  fixed <- FALSE

  if (!is_valid && isTRUE(fix)) {
    # The repair syncs metadata documents only. A missing payload cannot be
    # reconstructed from the clone -- the parquet bytes never existed there --
    # so those findings survive the fix and must be named rather than implied
    # by a second validate run.
    unfixable <- .datom_validate_unfixable_tables(table_checks)

    cli::cli_alert_info("Attempting to fix by syncing metadata to S3...")
    tryCatch({
      .datom_sync_data_metadata(conn, .confirm = FALSE)
      fixed <- TRUE
      cli::cli_alert_success(
        "Metadata synced. Re-run {.fn datom_validate} to verify."
      )
      if (length(unfixable) > 0L) {
        cli::cli_alert_warning(
          "Data still missing from storage for {length(unfixable)} table{?s}: {.val {unfixable}}."
        )
        cli::cli_bullets(c(
          "i" = "Syncing metadata does not fix this -- the parquet bytes are not in the git clone.",
          "i" = "Re-run {.fn datom_write} with the source data to upload them."
        ))
      }
    }, error = function(e) {
      cli::cli_alert_danger("Fix failed: {conditionMessage(e)}")
    })
  }

  invisible(list(
    valid = is_valid,
    repo_files = repo_file_checks,
    tables = table_checks,
    fixed = fixed
  ))
}


#' Findings the Metadata Sync Cannot Repair
#'
#' `fix = TRUE` syncs metadata documents from the git clone to storage. A missing
#' **table** payload (`data_missing_s3`) is outside that reach: the parquet bytes
#' live only in storage and in whatever session serialized them, never in the
#' clone. Naming those tables is what stops the fix from reading as complete.
#'
#' **A set with the same finding is deliberately not named here**, because for a
#' set the claim is false: git holds `{name}/set.json`, so the sync restores the
#' payload from the clone. Naming it would send the owner to re-run a write that
#' detects no change and does nothing.
#'
#' @param table_checks The per-artifact check data frame from
#'   `.datom_validate_tables()`. Its name column is `table`, not `name`, and it
#'   carries a `kind` column.
#' @return Character vector of table names whose payload is missing from
#'   storage. Empty when there are none.
#' @noRd
.datom_validate_unfixable_tables <- function(table_checks) {
  if (is.null(table_checks) || nrow(table_checks) == 0L) return(character())

  # Deliberately no is-the-column-there guard: a renamed column should error
  # here rather than return an empty vector, which would silently reinstate the
  # overclaiming "fix applied" this helper exists to prevent.
  #
  # Match whole tokens, never a substring: "metadata_missing_s3" CONTAINS
  # "data_missing_s3", so a grepl() would report every metadata-only finding as
  # unrepairable -- the opposite of true, since those are exactly what the sync
  # does fix.
  has_missing_data <- purrr::map_lgl(table_checks$status, function(status) {
    "data_missing_s3" %in% trimws(strsplit(status, ",", fixed = TRUE)[[1L]])
  })

  # Same no-guard stance as above: the `kind` column must be there, so a frame
  # built without it errors rather than quietly naming a set as unrepairable.
  is_set <- !is.na(table_checks$kind) & table_checks$kind == "set"

  as.character(table_checks$table[has_missing_data & !is_set])
}


#' Validate project_name consistency between local manifest and connection
#'
#' Reads the local `.datom/manifest.json` and checks that its `project_name`
#' field matches `conn$project_name`. A mismatch indicates a namespace collision
#' (two projects sharing the same S3 bucket + prefix).
#'
#' @param conn A `datom_conn` object.
#' @return `TRUE` if consistent or no project_name in manifest (legacy
#'   repos without project tracking). `FALSE` on mismatch (with a warning).
#' @noRd
.datom_validate_project_name <- function(conn) {
  manifest_path <- fs::path(conn$path, ".datom", "manifest.json")

  if (!fs::file_exists(manifest_path)) return(TRUE)

  manifest <- tryCatch(
    jsonlite::read_json(manifest_path),
    error = function(e) return(TRUE)
  )

  manifest_project <- manifest$project_name
  if (is.null(manifest_project)) return(TRUE)  # legacy manifest without project_name

  if (!identical(manifest_project, conn$project_name)) {
    cli::cli_alert_danger(
      "Project name mismatch: manifest says {.val {manifest_project}} but connection says {.val {conn$project_name}}."
    )
    cli::cli_alert_info(
      "This may indicate a namespace collision. Check bucket/prefix configuration."
    )
    return(FALSE)
  }

  TRUE
}


#' Validate repo-level files exist on S3
#' @noRd
.datom_validate_repo_files <- function(conn) {
  repo_path <- conn$path
  project_name <- conn$project_name
  has_gov <- !is.null(conn$gov_root)

  # Manifest (data side) is always checked.
  files_to_check <- list(
    list(
      local = as.character(fs::path(repo_path, ".datom", "manifest.json")),
      s3_key = ".metadata/manifest.json",
      name = "manifest.json",
      target_conn = conn
    )
  )

  # Governance files (dispatch / ref / migration_history) only exist when
  # the project has been gov-attached. For no-gov projects they are
  # genuinely absent; skipping keeps the validator from reporting false
  # negatives.
  if (has_gov) {
    gov_conn <- .datom_conn_for(conn, "gov")
    gov_local_path <- conn$gov_local_path

    proj_key <- function(name) {
      fs::path("projects", project_name, name)
    }

    gov_local <- function(name) {
      if (is.null(gov_local_path) || !nzchar(gov_local_path)) {
        return(NA_character_)
      }
      as.character(fs::path(gov_local_path, "projects", project_name, name))
    }

    files_to_check <- c(
      list(
        list(
          local = gov_local("dispatch.json"),
          s3_key = as.character(proj_key("dispatch.json")),
          name = "dispatch.json",
          target_conn = gov_conn
        ),
        list(
          local = gov_local("ref.json"),
          s3_key = as.character(proj_key("ref.json")),
          name = "ref.json",
          target_conn = gov_conn
        ),
        list(
          local = gov_local("migration_history.json"),
          s3_key = as.character(proj_key("migration_history.json")),
          name = "migration_history.json",
          target_conn = gov_conn
        )
      ),
      files_to_check
    )
  }

  rows <- purrr::map(files_to_check, function(fc) {
    if (is.na(fc$local)) {
      # No local clone available (e.g. reader): skip local check
      return(NULL)
    }
    local_exists <- fs::file_exists(fc$local)

    if (!local_exists) {
      # File not in clone -- skip
      return(NULL)
    }

    s3_exists <- .datom_storage_exists(fc$target_conn, fc$s3_key)

    status <- if (s3_exists) "ok" else "missing_s3"

    data.frame(
      file = fc$name,
      local = TRUE,
      s3 = s3_exists,
      status = status,
      stringsAsFactors = FALSE
    )
  })

  rows <- purrr::compact(rows)

  if (length(rows) == 0L) {
    return(data.frame(
      file = character(), local = logical(),
      s3 = logical(), status = character(),
      stringsAsFactors = FALSE
    ))
  }

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}


#' Validate per-table metadata consistency
#' @noRd
.datom_validate_tables <- function(conn) {
  repo_path <- conn$path

  # Discover tables (directories with metadata.json)
  all_dirs <- fs::dir_ls(repo_path, type = "directory")
  all_dirs <- all_dirs[!grepl("^\\.", fs::path_file(all_dirs))]
  all_dirs <- all_dirs[!fs::path_file(all_dirs) %in%
    c("input_files", "renv", "man", "R", "tests", "vignettes", "src")]

  table_dirs <- all_dirs[purrr::map_lgl(all_dirs, function(d) {
    fs::file_exists(fs::path(d, "metadata.json"))
  })]

  table_names <- fs::path_file(table_dirs)

  if (length(table_names) == 0L) {
    # Every column a populated result carries, `kind` included: a zero-row frame
    # missing one makes a caller that reads it fail only when the repo is empty.
    return(data.frame(
      table = character(),
      kind = character(),
      metadata_local = logical(),
      metadata_s3 = logical(),
      history_local = logical(),
      history_s3 = logical(),
      data_s3 = logical(),
      status = character(),
      stringsAsFactors = FALSE
    ))
  }

  rows <- purrr::map(table_names, function(tbl) {
    .datom_validate_one_table(conn, tbl)
  })

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}


#' Validate one artifact's git-storage consistency
#'
#' Named for tables for the same reason the frame's column is `table` and the
#' result's field is `tables`: those names are what callers already read. It
#' handles both kinds.
#' @noRd
.datom_validate_one_table <- function(conn, name) {
  repo_path <- conn$path

  # Local checks
  metadata_local <- fs::file_exists(fs::path(repo_path, name, "metadata.json"))
  history_local <- fs::file_exists(fs::path(repo_path, name, "version_history.json"))

  # S3 checks
  metadata_s3 <- .datom_storage_exists(conn, .datom_artifact_meta_key(name, "metadata"))
  history_s3 <- .datom_storage_exists(
    conn, .datom_artifact_meta_key(name, "version_history")
  )

  meta <- if (metadata_local) {
    tryCatch(
      jsonlite::read_json(
        fs::path(repo_path, name, "metadata.json"),
        simplifyVector = TRUE
      ),
      error = function(e) NULL
    )
  }

  kind <- .datom_declared_artifact_kind(meta)

  # The payload's address depends on the kind -- `.parquet` for a table,
  # `.json` for a set -- and this decision was previously hardcoded to
  # "table", so every set reported its payload missing.
  #
  # The key builder validates `data_sha`, which came off a file, so a
  # hand-edited value must leave the payload unchecked rather than abort the
  # run: same tolerance the previous tryCatch gave it.
  payload_key <- if (!is.na(kind) && .datom_is_text_scalar(meta$data_sha)) {
    tryCatch(
      .datom_artifact_payload_key(name, meta$data_sha, kind),
      error = function(e) NULL
    )
  }

  # NA, not FALSE, when the kind is unknown: nothing was checked, and FALSE
  # would report a missing payload this build cannot even address.
  data_s3 <- if (is.na(kind)) {
    NA
  } else {
    !is.null(payload_key) && .datom_storage_exists(conn, payload_key)
  }

  # Determine status
  issues <- character()
  if (metadata_local && !metadata_s3) issues <- c(issues, "metadata_missing_s3")
  if (history_local && !history_s3) issues <- c(issues, "history_missing_s3")
  if (isFALSE(data_s3)) issues <- c(issues, "data_missing_s3")

  if (is.na(kind)) {
    cli::cli_alert_warning(
      "{.val {name}} declares an artifact kind this version of datom does not \\
       know, so its stored payload was not checked."
    )
    cli::cli_alert_info(
      "It may have been written by a newer datom -- upgrade datom and re-run \\
       {.fn datom_validate}."
    )
    issues <- c(issues, "kind_unsupported")
  }

  if (identical(kind, "set")) {
    issues <- c(
      issues,
      .datom_validate_set(conn, name, meta, payload_key, data_s3)
    )
  }

  status <- if (length(issues) == 0L) "ok" else paste(issues, collapse = ",")

  data.frame(
    table = name,
    kind = kind,
    metadata_local = metadata_local,
    metadata_s3 = metadata_s3,
    history_local = history_local,
    history_s3 = history_s3,
    data_s3 = data_s3,
    status = status,
    stringsAsFactors = FALSE
  )
}


#' The Kind an Artifact's Own Metadata Declares
#'
#' `NA` rather than an abort for a kind this build has never heard of. The
#' payload-key builder refuses such a value outright, so without this the whole
#' validation run would stop on one artifact written by a newer datom -- and a
#' validator that cannot finish reports nothing about the artifacts it never
#' reached. Reads limp.
#'
#' An absent `kind` reads as `"table"`, because every document written before the
#' field existed describes one. So does a document that could not be read at all:
#' the caller reports the missing payload for it exactly as before.
#'
#' @param meta A parsed `metadata.json`, or `NULL` when there is none.
#' @return `"table"`, `"set"`, or `NA_character_`.
#' @noRd
.datom_declared_artifact_kind <- function(meta) {
  if (!is.list(meta)) return("table")

  kind <- meta$kind %||% "table"
  if (!.datom_is_text_scalar(kind) || !kind %in% .datom_artifact_kinds) {
    return(NA_character_)
  }

  kind
}


#' Check a Set's Payload Beyond Its Existence
#'
#' Two findings, deliberately separate from each other and from a missing
#' payload, because the three call for different actions: a payload that is not
#' in storage, a payload whose members no longer resolve, and a set that records
#' no payload hash.
#'
#' **A set with no recorded `document_sha` is reported rather than tolerated.**
#' A reader refuses such a version before it parses anything, and the message it
#' gives says to run this verb -- so reporting `ok` here would send the user in a
#' circle.
#'
#' @param conn A `datom_conn` object.
#' @param name The set's name.
#' @param meta The set's `metadata.json` from the clone.
#' @param payload_key Relative storage key of the payload, or `NULL` when one
#'   could not be built.
#' @param payload_present What the existence check found: `TRUE`, `FALSE`, or
#'   `NA`.
#' @return Character vector of status codes, empty when nothing is wrong.
#' @noRd
.datom_validate_set <- function(conn, name, meta, payload_key, payload_present) {
  issues <- character()

  if (!.datom_is_text_scalar(meta$document_sha)) {
    cli::cli_alert_danger(
      "Set {.val {name}} records no {.field document_sha}, so its stored \\
       payload cannot be verified on read."
    )
    issues <- c(issues, "document_sha_missing")
  }

  # Nothing to list members from. The absence is already reported as
  # `data_missing_s3`, so this is a skip with a finding attached rather than a
  # silent one.
  if (!isTRUE(payload_present) || is.null(payload_key)) return(issues)

  members <- tryCatch(
    .datom_storage_read_json(conn, payload_key)$members,
    error = function(e) NULL
  )

  # Mirrors the reader's own guard in `.datom_read_set_members()`: a NAMED list
  # is a JSON object where an array of records belongs.
  usable <- is.list(members) &&
    (length(members) == 0L || is.null(names(members)))

  if (!usable) {
    cli::cli_alert_danger(
      "The stored payload for set {.val {name}} does not list members."
    )
    return(c(issues, "members_unresolvable"))
  }

  unresolved <- .datom_unresolved_members(
    conn, name, members, .datom_set_project(meta, conn)
  )

  if (length(unresolved) == 0L) return(issues)

  cli::cli_alert_danger(
    "Set {.val {name}} has {length(unresolved)} member{?s} that do not \\
     resolve: {.val {unresolved}}."
  )
  cli::cli_alert_info(
    "A set is a citation, so a member that no longer resolves is a claim this \\
     project can no longer honour."
  )

  c(issues, "members_unresolvable")
}


#' Which of a Set's Members Do Not Resolve
#'
#' A member pins a version, and a version is a stored metadata snapshot, so
#' "resolves" means that snapshot is in storage -- the same address
#' [datom_member()] reads when it builds the pointer. Nothing here opens a
#' member's own payload: for a same-project member, that artifact has a row of
#' its own in the same result.
#'
#' **One level, and one level only.** A member that is itself a set is confirmed
#' to exist and its member list is never opened, so the number of storage reads
#' depends on this set's own member count and never on the tree beneath it.
#' Validating an inner set is a separate call against that set's own project.
#'
#' **A member of another project is checked as a well-formed pointer only.**
#' Access in datom is per project and this connection sees one namespace, so an
#' existence check there would report every cross-project member as rotten. The
#' comparison is against the project the **set's own metadata** records, not the
#' name on the connection: a connection's project name is a label nobody
#' verified, so comparing against it would misclassify members on a connection
#' opened with a different label.
#'
#' @param conn A `datom_conn` object.
#' @param name The set's name, for the malformed-record messages.
#' @param members The payload's parsed member list.
#' @param project The project the set's own metadata records.
#' @return Character vector labelling each member that did not resolve, empty
#'   when they all did.
#' @noRd
.datom_unresolved_members <- function(conn, name, members, project) {
  labels <- purrr::map_chr(seq_along(members), function(i) {
    at <- sprintf("members[[%d]]", i)

    # The reader's own normalizer, so the validator's idea of a usable member
    # record cannot drift from what a read will accept.
    record <- tryCatch(
      .datom_read_set_member(members[[i]], at, name),
      error = function(e) NULL
    )
    if (is.null(record)) return(at)

    id <- record$id
    if (!identical(id$project, project)) return(NA_character_)

    # `version` came off a stored document and is spliced into a key, so a value
    # the guard refuses counts as unresolvable rather than aborting the run.
    key <- tryCatch(
      .datom_artifact_snapshot_key(id$name, id$version),
      error = function(e) NULL
    )
    if (!is.null(key) && .datom_storage_exists(conn, key)) return(NA_character_)

    paste0(id$name, "@", substr(id$version, 1L, 8L))
  })

  labels[!is.na(labels)]
}
