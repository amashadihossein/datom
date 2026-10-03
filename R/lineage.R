# Lineage helpers

#' Union and Deduplicate source_lineage Lists
#'
#' Takes a list of zero or more `source_lineage` lists and returns their
#' deduplicated union. Each entry is a list with `project`, `table`, and
#' `version_sha`. Deduplication uses the composite key
#' `paste(project, table, version_sha, sep = "\t")`, so each distinct entry
#' appears exactly once and retained entries are returned unchanged.
#'
#' `NULL` members are tolerated (a parent may carry `source_lineage = NULL`)
#' and treated as an empty contribution. Empty input, or a list containing
#' only empty lineage lists, returns an empty list.
#'
#' This helper is the building block of the composable lineage recompute
#' recipe. To check that a derived table's recorded `source_lineage` matches
#' its parents, read each parent through a connection scoped to that parent's
#' project and union their lineages:
#'
#' \preformatted{
#' # conn_c is scoped to the derived table's project.
#' parents <- datom_get_parents(conn_c, "c")
#'
#' # One connection per project, keyed by each parent's `source`. Never
#' # reach across project stores with a single connection.
#' conns <- list(project_a = conn_a, project_b = conn_b)
#'
#' # Read each parent's lineage through its own project connection.
#' parent_sls <- lapply(parents, function(p) {
#'   datom_get_lineage(conns[[p$source]], p$table, version = p$version,
#'                     depth = "source")
#' })
#'
#' recomputed <- datom_lineage_union(parent_sls)
#' recorded   <- datom_get_lineage(conn_c, "c", depth = "source")
#' identical(recomputed, recorded)
#' }
#'
#' @param lineages A list of `source_lineage` lists (each itself a list of
#'   entries with `project`, `table`, `version_sha`). `NULL` members are
#'   treated as empty.
#' @return A deduplicated list of `source_lineage` entries, or an empty list
#'   when there is nothing to union.
#' @export
#'
#' @examples
#' sl1 <- list(list(project = "p", table = "t", version_sha = "a"))
#' sl2 <- list(list(project = "p", table = "t", version_sha = "a"))
#' datom_lineage_union(list(sl1, sl2))
datom_lineage_union <- function(lineages) {
  lineages <- purrr::compact(lineages)
  all_entries <- purrr::flatten(lineages)
  if (length(all_entries) == 0L) return(list())

  keys <- purrr::map_chr(all_entries, function(e) {
    paste(e$project %||% "", e$table %||% "",
          e$version_sha %||% "", sep = "\t")
  })

  all_entries[!duplicated(keys)]
}


#' Union and deduplicate source_lineage lists (internal wrapper)
#'
#' Thin wrapper retained for existing internal callers. Delegates to the
#' exported [datom_lineage_union()].
#'
#' @param lineage_lists List of source_lineage lists (each a list of entries).
#' @return Deduplicated list of source_lineage entries.
#' @keywords internal
.datom_lineage_union <- function(lineage_lists) {
  datom_lineage_union(lineage_lists)
}


# --- Parent constructor --------------------------------------------------

#' Name an Input for a Table You Are About to Write
#'
#' Use before [datom_write()] when the table you are writing was made from other
#' datom tables. Each call names one input -- one table at one exact version --
#' and returns a note that [datom_write()] saves with the new table, so its
#' [lineage][datom-package] records what it was made from. For several inputs,
#' make one call each and pass them together as a list to `parents`. If the
#' inputs are members of a set, pass the set as `x` and name several tables at
#' once; each gets the version the set pins.
#'
#' The parent's data fingerprint is read from the parent's own saved record; you
#' cannot supply it, so a lineage entry cannot claim data the parent never had.
#' The record is plain data with no connection inside, so it can be saved and
#' reused.
#'
#' Same-project and cross-project parents are declared identically -- the
#' only difference is which connection is passed. `source` is always derived
#' from the connection's `project_name`.
#'
#' @section Taking the version from a set:
#' When the inputs of a derivation are members of a set, pass the set as `x`
#' instead of a `version`: each `table` is looked up among the set's members and
#' declared at the version the set pins. That keeps the parents a derived table
#' records in step with the set it is derived through, without looking each
#' version up by hand.
#'
#' The member is chosen exactly as [datom_fetch_member()] chooses it. A name
#' held by two members -- a current table beside a locked baseline, say -- stops
#' and lists both; narrow with `tags`. A member that is itself a set stops too,
#' since only a table can be a parent.
#'
#' With `x`, `table` may name several tables and the result is **always a
#' list** of parent records, even for one table, so it can be passed straight to
#' the `parents` argument of [datom_write()]. Without `x` the result is one
#' record, as it always was.
#'
#' @param conn A `datom_conn` scoped to the parent's project store, from
#'   [datom_get_conn()].
#' @param table Parent table name (single non-empty validated string). With `x`,
#'   a character vector of one or more member names.
#' @param version Parent version (metadata_sha; single non-empty string).
#'   Exactly one of `version` and `x` is required.
#' @param x Optional `datom_set` from [datom_get_set()] (or one being built)
#'   whose members supply the versions. Exactly one of `version` and `x` is
#'   required.
#' @param tags Optional named list of labels narrowing a member name the set
#'   holds more than once, e.g. `list(type = "input")`. Only with `x`.
#' @return Without `x`, a list with exactly `source`, `table`, `version`,
#'   `data_sha`, and `source_lineage`. `source` is the project the parent's own
#'   metadata says it belongs to, falling back to the project manifest and then
#'   to the connection's name (see `.datom_declared_project()`) -- **not** simply
#'   the name on `conn`, which on a reader connection is an unverified label and
#'   which `source` cannot afford, since it is part of the declaring table's
#'   version. `source_lineage` is `NULL` when the snapshot carries none. With
#'   `x`, an unnamed list of such records, one per `table`, in the order given.
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
#'
#'   # Resolve a parent declaration to pass to the parents argument of
#'   # datom_write.
#'   print(datom_parent(conn, "dm", datom_history(conn, "dm")$version[1]))
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_parent <- function(conn, table, version = NULL, x = NULL, tags = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort(
      "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}."
    )
  }

  # Both or neither is refused rather than resolved by precedence: with both,
  # one of them would be silently ignored, and the parent recorded -- which is
  # part of the declaring table's version -- might not be the one intended.
  if (is.null(version) == is.null(x)) {
    cli::cli_abort(
      c(
        "Give exactly one of {.arg version} and {.arg x}.",
        "i" = "{.arg version} declares the parent at a version you name; \\
               {.arg x} takes the version from a set's member of that name."
      ),
      class = "datom_parent_version_or_set"
    )
  }

  if (is.null(x)) {
    if (!is.null(tags)) {
      cli::cli_abort(
        c(
          "{.arg tags} narrows a set's members, and no set was given.",
          "i" = "Pass the set as {.arg x}, or drop {.arg tags}."
        ),
        class = "datom_parent_tags_without_set"
      )
    }
    return(.datom_parent_record(conn, table, version))
  }

  .datom_parents_from_set(conn, table, x, tags)
}


#' Declare Parents at the Versions a Set Pins
#'
#' The `x =` route of [datom_parent()]. Each name is resolved by
#' [.datom_find_member()], the resolver [datom_fetch_member()] uses for a name,
#' so the two verbs cannot pick different members for the same name and labels.
#' Tag validation is the same call with the same remedy, for the same reason.
#'
#' @param conn A `datom_conn` scoped to the parents' project.
#' @param table Character vector of member names.
#' @param x A `datom_set`.
#' @param tags Optional label filter.
#' @return An unnamed list of parent records, one per `table`.
#' @keywords internal
.datom_parents_from_set <- function(conn, table, x, tags) {
  members <- .datom_set_members(x)

  if (!is.null(tags)) {
    .datom_validate_tag_map(
      tags, "tags",
      remedy = "Narrow by labels a member carries, e.g. \\
                {.code list(type = \"input\")}."
    )
  }

  if (!is.character(table) || length(table) == 0L || anyNA(table)) {
    cli::cli_abort(
      c(
        "{.arg table} must be one or more member names.",
        "i" = "For example: {.code table = c(\"dm\", \"lb\")}."
      )
    )
  }

  # lapply rather than purrr::map: the resolver's conditions (an ambiguous name,
  # a member that is not a table) must reach the caller with their own class,
  # and purrr re-signals a mapped function's error as its own.
  lapply(table, function(name) {
    .datom_validate_name(name)
    record <- .datom_find_member(members, name, tags)
    id <- .datom_member_id(record)

    if (!identical(id$kind, "table")) {
      cli::cli_abort(
        c(
          "Member {.val {name}} is a {id$kind}, and only a table can be a \\
           parent.",
          "i" = "A set is cited as a member of another set, not declared as \\
                 a table's parent."
        ),
        class = "datom_parent_not_a_table"
      )
    }

    .datom_parent_record(conn, name, id$version)
  })
}


#' Resolve One Parent Record From Its Versioned Snapshot
#'
#' The body of [datom_parent()] for one table at one named version, shared by
#' both of its routes so a parent declared by version and one declared from a
#' set are read, checked and shaped by the same code.
#'
#' @param conn A `datom_conn` scoped to the parent's project.
#' @param table Parent table name.
#' @param version Parent version.
#' @return One parent record.
#' @keywords internal
.datom_parent_record <- function(conn, table, version) {

  .datom_validate_name(table)

  if (!is.character(version) || length(version) != 1L ||
      is.na(version) || !nzchar(version)) {
    cli::cli_abort("{.arg version} must be a single non-empty string.")
  }
  # version is spliced into a storage key; reject path-traversal / non-hex.
  .datom_validate_sha(version, arg = "version")

  key <- .datom_artifact_snapshot_key(table, version)

  snap <- tryCatch(
    .datom_storage_read_json(conn, key),
    error = function(e) {
      cli::cli_abort(c(
        paste0("Parent {.val {table}@{version}} not found in ",
               "project {.val {conn$project_name}}."),
        "i" = "Underlying error: {conditionMessage(e)}"
      ))
    }
  )

  # Refuse a snapshot written by a build whose format this one does not know,
  # before reading anything out of it. Both fields taken below are durable: the
  # `data_sha` becomes a storage address and the `source_lineage` is unioned
  # into the lineage of whatever table declares this parent, so a half-understood
  # document is copied forward rather than merely misread once.
  #
  # Deliberately OUTSIDE the handler above, which would otherwise reword the
  # refusal as "parent not found". Same pairing as `datom_member()` and
  # `.datom_rebuild_manifest_entry()`.
  .datom_check_schema_version(snap, key)

  data_sha <- snap$data_sha %||% ""
  if (!is.character(data_sha) || length(data_sha) != 1L ||
      is.na(data_sha) || !nzchar(data_sha)) {
    cli::cli_abort(c(
      paste0("Parent snapshot for {.val {table}@{version}} is ",
             "missing {.field data_sha}."),
      "i" = paste0("The snapshot at {.val {key}} in project ",
                   "{.val {conn$project_name}} has no {.field data_sha}.")
    ))
  }

  source_lineage <- snap$source_lineage %||% NULL

  list(
    # NOT `conn$project_name`. The same one-line defect a member had, and worse
    # here: `parents` is part of the declaring table's identity, so an unverified
    # label read off a reader connection would change a VERSION rather than only a
    # citation. See `.datom_declared_project()`.
    source         = .datom_declared_project(conn, snap, "parent"),
    table          = table,
    version        = version,
    data_sha       = data_sha,
    source_lineage = source_lineage
  )
}
