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
#'   `table_count`, `set_count`, `total_versions`, `last_updated`, `remote_url`.
#'   `table_count` counts tables only and `set_count` counts sets;
#'   `total_versions` stays tables-only, so no counter changed meaning.
#'   `remote_url` is `NULL` for readers (no local data clone).
#'
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
#'   print(datom_summary(conn))
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_summary <- function(conn) {
  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  # .datom_read_manifest() returns IO failures and throws schema refusals, so an
  # unreadable manifest is this function's decision while a too-new one is not.
  read <- .datom_read_manifest(conn, "storage")

  if (!read$ok) {
    cli::cli_abort(c(
      "Could not read manifest from data store.",
      "i" = "The repository may not be initialized or manifest is missing.",
      "i" = "Underlying error: {conditionMessage(read$error)}"
    ))
  }

  manifest <- read$manifest

  # Counted from the artifact list rather than read off the summary block, and
  # filtered on kind: table_count keeps its current tables-only meaning and
  # set_count is the new number beside it. No fallback for an entry with no
  # kind -- the reader has already converted an older document, which types
  # every entry, so an untyped entry should show up as a visibly wrong count
  # rather than a roughly-right one.
  artifacts <- manifest$artifacts %||% list()
  table_count <- length(purrr::keep(artifacts, ~ identical(.x$kind, "table")))
  set_count <- length(purrr::keep(artifacts, ~ identical(.x$kind, "set")))
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
      set_count      = as.integer(set_count),
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
#'   print(datom_summary(conn))
#'
#'   unlink(tmp, recursive = TRUE)
#' }
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
  cli::cli_li("Sets:       {.val {x$set_count %||% 0L}}")
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
