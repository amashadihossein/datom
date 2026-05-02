# Portfolio listing: registered projects across the governance repo.

#' List Projects Registered in the Governance Repo
#'
#' Returns a data frame with one row per project registered in the shared
#' governance repo. Useful for managers and auditors who need to see the
#' portfolio without having to clone every data repo.
#'
#' Accepts either a `datom_conn` (typically the developer's existing
#' connection -- reads the local gov clone) or a `datom_store` (lets a caller
#' enumerate the portfolio before connecting to any specific project).
#'
#' Read path:
#' * If a local gov clone is available (developer or any caller whose
#'   `gov_local_path` exists on disk), `projects/` is listed from disk and
#'   each `ref.json` is read locally. No network calls.
#' * Otherwise the gov storage client is used: `projects/` is listed and
#'   each `projects/{name}/ref.json` is fetched.
#'
#' Corrupt registry entries (missing `ref.json`, unreadable JSON) emit a
#' warning and are skipped -- one bad project does not take down the listing.
#'
#' @param x A `datom_conn` or a `datom_store` with a governance component.
#'
#' @return A data frame, sorted by `name`, with columns:
#'   `name` (character), `data_backend` (character),
#'   `data_root` (character), `data_prefix` (character; NA when absent),
#'   `registered_at` (character ISO8601 from clone mtime; NA on storage path).
#'
#' @export
datom_projects <- function(x) {
  ctx <- .datom_projects_resolve_input(x)
  gov_conn       <- ctx$gov_conn
  gov_local_path <- ctx$gov_local_path

  names <- .datom_gov_list_projects(gov_conn, gov_local_path)

  if (length(names) == 0L) {
    return(.datom_projects_empty_df())
  }

  rows <- purrr::map(names, function(nm) {
    .datom_projects_row(nm, gov_conn, gov_local_path)
  })
  rows <- purrr::compact(rows)

  if (length(rows) == 0L) {
    return(.datom_projects_empty_df())
  }

  result <- do.call(rbind, rows)
  result <- result[order(result$name), , drop = FALSE]
  rownames(result) <- NULL
  result
}


# Resolve input to a (gov_conn, gov_local_path) pair.
# datom_conn -> use .datom_gov_conn() and conn$gov_local_path.
# datom_store -> build a transient gov-resolve conn; no clone available.
.datom_projects_resolve_input <- function(x) {
  if (inherits(x, "datom_conn")) {
    if (is.null(x$gov_root)) {
      cli::cli_abort(c(
        "{.arg x} is a {.cls datom_conn} without a governance store.",
        "i" = "Rebuild the connection with a store that has {.arg gov_repo_url} set."
      ))
    }
    return(list(
      gov_conn       = .datom_gov_conn(x),
      gov_local_path = x$gov_local_path
    ))
  }

  if (inherits(x, "datom_store")) {
    if (is.null(x$governance)) {
      cli::cli_abort(c(
        "{.arg x} is a {.cls datom_store} without a governance component.",
        "i" = "Rebuild the store with {.arg gov_repo_url} (and gov storage fields) set."
      ))
    }
    return(list(
      gov_conn       = .datom_build_gov_resolve_conn(x),
      gov_local_path = NULL
    ))
  }

  cli::cli_abort(
    "{.arg x} must be a {.cls datom_conn} or {.cls datom_store}."
  )
}


# Build one row of the projects data frame, or NULL on unrecoverable read.
.datom_projects_row <- function(project_name, gov_conn, gov_local_path) {
  use_clone <- !is.null(gov_local_path) &&
    .datom_gov_clone_exists(gov_local_path)

  if (isTRUE(use_clone)) {
    ref_path <- fs::path(gov_local_path, "projects", project_name, "ref.json")
    if (!fs::file_exists(ref_path)) {
      cli::cli_warn("Skipping {.val {project_name}}: ref.json not found at {.path {ref_path}}.")
      return(NULL)
    }
    ref <- tryCatch(
      jsonlite::read_json(ref_path, simplifyVector = FALSE),
      error = function(e) {
        cli::cli_warn("Skipping {.val {project_name}}: failed to parse ref.json ({conditionMessage(e)}).")
        NULL
      }
    )
    if (is.null(ref)) return(NULL)
    registered_at <- format(fs::file_info(ref_path)$modification_time,
                             "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  } else {
    storage_key <- glue::glue("projects/{project_name}/ref.json")
    ref <- tryCatch(
      .datom_storage_read_json(gov_conn, storage_key),
      error = function(e) {
        cli::cli_warn("Skipping {.val {project_name}}: failed to read ref.json from storage ({conditionMessage(e)}).")
        NULL
      }
    )
    if (is.null(ref)) return(NULL)
    registered_at <- NA_character_
  }

  current <- ref$current %||% list()

  data.frame(
    name          = project_name,
    data_backend  = .scalar_or_na(current$type),
    data_root     = .scalar_or_na(current$root),
    data_prefix   = .scalar_or_na(current$prefix),
    registered_at = registered_at %||% NA_character_,
    stringsAsFactors = FALSE
  )
}


# Coerce a possibly-NULL / possibly-empty / possibly-list value coming from
# JSON parsing into a length-1 character. Empty list (`[]` in JSON) and
# missing keys both become NA. List-wrapped scalars (from
# `simplifyVector = FALSE`) are unwrapped.
.scalar_or_na <- function(x) {
  if (is.null(x)) return(NA_character_)
  if (is.list(x) && length(x) == 0L) return(NA_character_)
  if (is.list(x) && length(x) == 1L) x <- x[[1L]]
  if (length(x) == 0L) return(NA_character_)
  if (is.na(x)) return(NA_character_)
  as.character(x)[[1L]]
}


.datom_projects_empty_df <- function() {
  data.frame(
    name          = character(),
    data_backend  = character(),
    data_root     = character(),
    data_prefix   = character(),
    registered_at = character(),
    stringsAsFactors = FALSE
  )
}
