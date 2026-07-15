# Lineage helpers

#' Union and deduplicate source_lineage lists
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

#' Declare a parent for lineage
#'
#' Resolves a parent table against a single project connection and returns a
#' pure-data lineage record. The parent's authoritative `data_sha` and its
#' `source_lineage` are read from the parent's own versioned metadata
#' snapshot at `{table}/.metadata/{version}.json`; a caller cannot supply or
#' override `data_sha` (there is no `data_sha` parameter). The returned
#' record retains no live connection and is serializable as plain data.
#'
#' Same-project and cross-project parents are declared identically -- the
#' only difference is which connection is passed. `source` is always derived
#' from the connection's `project_name`.
#'
#' @param conn A `datom_conn` scoped to the parent's project store, from
#'   [datom_get_conn()].
#' @param table Parent table name (single non-empty validated string).
#' @param version Parent version (metadata_sha; single non-empty string).
#' @return A list with exactly `source`, `table`, `version`, `data_sha`, and
#'   `source_lineage`. `source` is the parent connection's `project_name`;
#'   `source_lineage` is `NULL` when the snapshot carries none.
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- datom_get_conn(path = "path/to/repo", store = store)
#' p <- datom_parent(conn, "dm", "v_dm_9f3")
#' }
datom_parent <- function(conn, table, version) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort(
      "{.arg conn} must be a {.cls datom_conn} from {.fn datom_get_conn}."
    )
  }

  .datom_validate_name(table)

  if (!is.character(version) || length(version) != 1L ||
      is.na(version) || !nzchar(version)) {
    cli::cli_abort("{.arg version} must be a single non-empty string.")
  }
  # version is spliced into a storage key; reject path-traversal / non-hex.
  .datom_validate_sha(version, arg = "version")

  key <- paste0(table, "/.metadata/", version, ".json")

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
    source         = conn$project_name,
    table          = table,
    version        = version,
    data_sha       = data_sha,
    source_lineage = source_lineage
  )
}
