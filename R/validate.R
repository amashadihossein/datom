#' Check if Path is a Valid tbit Repository
#'
#' Validates tbit repository structure. Used internally and by dpbuild.
#'
#' @param path Path to evaluate.
#' @param checks Which checks to perform. Any combination of "all", "git",
#'   "tbit", "renv".
#' @param verbose If TRUE, prints which tests passed/failed.
#'
#' @return TRUE or FALSE.
#' @export
is_valid_tbit_repo <- function(path,
                               checks = c("all", "git", "tbit", "renv"),
                               verbose = FALSE) {
  checks <- match.arg(
    arg = checks,
    choices = c("all", "git", "tbit", "renv"),
    several.ok = TRUE
  )

  dx <- tbit_repository_check(path = path)

  if (!"all" %in% checks) {
    if (!"git" %in% checks) {
      dx <- dx[setdiff(names(dx), "git_initialized")]
    }
    if (!"tbit" %in% checks) {
      dx <- dx[setdiff(names(dx), c("tbit_initialized", "tbit_routing", "tbit_manifest"))]
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


#' Check tbit Repository Structure
#'
#' Returns detailed check results for each component.
#'
#' @param path Path to evaluate.
#'
#' @return List of TRUE/FALSE per check.
#' @keywords internal
tbit_repository_check <- function(path) {
  path <- fs::path_abs(path)

  list(
    git_initialized = fs::dir_exists(fs::path(path, ".git")),
    tbit_initialized = fs::file_exists(fs::path(path, ".tbit", "project.yaml")),
    tbit_routing = fs::file_exists(fs::path(path, ".tbit", "routing.json")),
    tbit_manifest = fs::file_exists(fs::path(path, ".tbit", "manifest.json")),
    renv_initialized = fs::dir_exists(fs::path(path, "renv"))
  )
}


#' Validate Git-Storage Consistency
#'
#' Checks that git metadata matches S3 storage.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param fix If TRUE, attempts to fix inconsistencies.
#'
#' @return Validation results.
#' @export
tbit_validate <- function(conn, fix = FALSE) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}
