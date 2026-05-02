# Project summary helper for managers/auditors.

#' Summarize a datom Project
#'
#' Returns a compact, role-aware overview of a datom project: its name,
#' backend, table/version totals, last write time, and (for developers) the
#' git remote URL. Reads `.metadata/manifest.json` from the data store.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#'
#' @return A `datom_summary` S3 object (a list with class `"datom_summary"`)
#'   containing: `project_name`, `role`, `backend`, `root`, `prefix`,
#'   `table_count`, `total_versions`, `last_updated`, `remote_url`.
#'   `remote_url` is `NULL` for readers (no local data clone).
#'
#' @export
datom_summary <- function(conn) {
  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  manifest <- tryCatch(
    .datom_storage_read_json(conn, ".metadata/manifest.json"),
    error = function(e) {
      cli::cli_abort(c(
        "Could not read manifest from data store.",
        "i" = "The repository may not be initialized or manifest is missing.",
        "i" = "Underlying error: {conditionMessage(e)}"
      ))
    }
  )

  table_count <- length(manifest$tables %||% list())
  total_versions <- manifest$summary$total_versions %||% 0L
  last_updated <- manifest$updated_at %||% NA_character_

  remote_url <- .datom_summary_remote_url(conn)

  structure(
    list(
      project_name   = conn$project_name,
      role           = conn$role,
      backend        = conn$backend,
      root           = conn$root,
      prefix         = conn$prefix,
      table_count    = as.integer(table_count),
      total_versions = as.integer(total_versions),
      last_updated   = last_updated,
      remote_url     = remote_url
    ),
    class = "datom_summary"
  )
}

#' Print a datom_summary
#'
#' @param x A `datom_summary` object.
#' @param ... Ignored.
#' @return Invisible `x`.
#' @export
print.datom_summary <- function(x, ...) {
  backend_label <- c(s3 = "S3", local = "local")[x$backend] %||% x$backend
  location <- x$root
  if (!is.null(x$prefix) && !is.na(x$prefix) && nzchar(x$prefix)) {
    location <- paste0(x$root, "/", x$prefix)
  }

  cli::cli_h3("datom project summary")
  cli::cli_ul()
  cli::cli_li("Project:    {.val {x$project_name}}")
  cli::cli_li("Role:       {.val {x$role}}")
  cli::cli_li("Backend:    {backend_label} -- {.val {location}}")
  cli::cli_li("Tables:     {.val {x$table_count}} ({x$total_versions} version{?s} total)")
  cli::cli_li("Last write: {.val {x$last_updated}}")

  if (!is.null(x$remote_url)) {
    cli::cli_li("Remote:     {.val {x$remote_url}}")
  } else if (identical(x$role, "reader")) {
    cli::cli_li("Remote:     {.emph <not visible to readers>}")
  }

  cli::cli_end()
  invisible(x)
}

# Internal: extract data git remote URL when a local clone is available.
# Returns NULL for readers (no $path) or when the remote can't be read.
.datom_summary_remote_url <- function(conn) {
  if (is.null(conn$path)) return(NULL)
  if (!nzchar(conn$path)) return(NULL)

  tryCatch(
    suppressWarnings({
      repo <- git2r::repository(conn$path)
      url <- git2r::remote_url(repo, "origin")
      if (length(url) == 0L || !nzchar(url)) return(NULL)
      url
    }),
    error = function(e) NULL
  )
}
