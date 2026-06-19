# Gov-clone read-side helpers
# These helpers manage the local governance repo clone: existence check,
# open, and initialise (clone-or-reuse). Write-side helpers are in Chunk 3.
#
# All helpers accept a resolved `gov_local_path` (absolute string).
# Path resolution (.datom_resolve_gov_local_path) lives in R/store.R.


# --- Existence + open ---------------------------------------------------------

#' Check Whether a Gov Clone Exists
#'
#' Returns `TRUE` if `gov_local_path` is a directory that looks like a git
#' repository (contains a `.git` folder). Does **not** validate the remote URL.
#'
#' @param gov_local_path Absolute path to the governance clone directory.
#' @return Logical scalar.
#' @keywords internal
.datom_gov_clone_exists <- function(gov_local_path) {
  is.character(gov_local_path) &&
    length(gov_local_path) == 1L &&
    fs::dir_exists(gov_local_path) &&
    fs::dir_exists(fs::path(gov_local_path, ".git"))
}


#' Open an Existing Gov Clone
#'
#' Returns a `git2r` repository handle for the gov clone at `gov_local_path`.
#' Aborts if the path is not a valid git repository.
#'
#' @param gov_local_path Absolute path to the governance clone directory.
#' @return A `git2r::repository` object.
#' @keywords internal
.datom_gov_clone_open <- function(gov_local_path) {
  .datom_check_git2r()

  if (!.datom_gov_clone_exists(gov_local_path)) {
    cli::cli_abort(c(
      "Gov clone not found at {.path {gov_local_path}}.",
      "i" = "Use the datomanager package to initialise the governance repository first."
    ))
  }

  tryCatch(
    git2r::repository(gov_local_path),
    error = function(e) {
      cli::cli_abort(c(
        "Failed to open git repository at {.path {gov_local_path}}.",
        "x" = conditionMessage(e)
      ))
    }
  )
}


# --- Clone or reuse -----------------------------------------------------------

#' Initialise Gov Clone (Clone If Missing, Reuse If Present)
#'
#' Ensures a valid gov clone exists at `gov_local_path`:
#'
#' - If the path does **not** exist: clones `gov_repo_url` into `gov_local_path`.
#' - If the path exists and is a git repo with matching remote URL: reuses it
#'   silently (idempotent).
#' - If the path exists with a **different** remote URL: hard abort (collision).
#' - If the path exists but is **not** a git repo: hard abort.
#'
#' @param gov_repo_url GitHub URL of the governance repo
#'   (e.g., `"https://github.com/org/acme-gov.git"`).
#' @param gov_local_path Absolute path where the gov clone should live.
#' @return Invisible `gov_local_path` (character).
#' @keywords internal
.datom_gov_clone_init <- function(gov_repo_url, gov_local_path) {
  .datom_check_git2r()

  if (!.datom_gov_clone_exists(gov_local_path)) {
    # Path either doesn't exist or isn't a git repo
    if (fs::dir_exists(gov_local_path) && length(fs::dir_ls(gov_local_path)) > 0L) {
      cli::cli_abort(c(
        "{.path {gov_local_path}} exists but is not a git repository.",
        "i" = "Remove or rename the directory, then retry."
      ))
    }

    cli::cli_alert_info("Cloning gov repo to {.path {gov_local_path}}...")

    cred <- .datom_git_credentials(gov_repo_url)
    tryCatch(
      git2r::clone(gov_repo_url, gov_local_path, credentials = cred),
      error = function(e) {
        cli::cli_abort(c(
          "Failed to clone governance repo {.url {gov_repo_url}}.",
          "x" = conditionMessage(e)
        ))
      }
    )

    # Ensure the fresh clone has a local git identity so subsequent gov
    # commits succeed even when the host (e.g. CI) has no global git config.
    .datom_git_ensure_local_identity(git2r::repository(gov_local_path))

    cli::cli_alert_success("Cloned gov repo to {.path {gov_local_path}}.")
    return(invisible(gov_local_path))
  }

  # Path exists and is a git repo -- validate remote URL matches
  .datom_gov_validate_remote(gov_local_path, gov_repo_url)

  invisible(gov_local_path)
}


# --- Remote URL validation ----------------------------------------------------

#' Validate Gov Clone Remote URL
#'
#' Reads the first configured remote from the gov clone and compares it against
#' `expected_url`. Aborts if they differ. This prevents silently reusing a
#' clone that points at a different governance repo.
#'
#' URL comparison is normalised: trailing `.git` is stripped from both sides
#' before comparison so `https://github.com/org/acme-gov` and
#' `https://github.com/org/acme-gov.git` are treated as equivalent.
#'
#' @param gov_local_path Absolute path to the governance clone directory.
#' @param expected_url Expected remote URL (from `store$gov_repo_url`).
#' @return Invisible TRUE.
#' @keywords internal
.datom_gov_validate_remote <- function(gov_local_path, expected_url) {
  .datom_check_git2r()

  repo <- .datom_gov_clone_open(gov_local_path)

  remotes <- git2r::remotes(repo)
  if (length(remotes) == 0L) {
    cli::cli_abort(c(
      "Gov clone at {.path {gov_local_path}} has no remote configured.",
      "i" = "Add a remote or re-clone the governance repo."
    ))
  }

  actual_url <- git2r::remote_url(repo, remotes[[1L]])

  # Normalise: strip trailing .git for comparison
  .strip_git <- function(u) sub("\\.git$", "", u)
  if (!identical(.strip_git(actual_url), .strip_git(expected_url))) {
    cli::cli_abort(c(
      "Gov clone at {.path {gov_local_path}} has a different remote URL.",
      "x" = "Expected: {.url {expected_url}}",
      "x" = "  Actual: {.url {actual_url}}",
      "i" = "Remove {.path {gov_local_path}} and re-run, or update {.arg gov_local_path}."
    ))
  }

  invisible(TRUE)
}


# --- Read helpers (no GOV_SEAM: pure reads, safe to keep in datom) -----------

#' List Registered Project Names
#'
#' Returns the set of project names registered in the governance repo. When a
#' local gov clone is available, lists directories under
#' `{gov_local_path}/projects/` (offline-friendly, reflects last
#' `datom_pull_gov()`). Otherwise lists keys under `projects/` via the gov
#' storage client and extracts unique top-level segments.
#'
#' Skips entries that don't contain a `ref.json` (corrupt registry rows).
#'
#' @param gov_conn A gov-scoped `datom_conn` (from `.datom_conn_for(conn, "gov")` or
#'   `.datom_build_gov_resolve_conn()`).
#' @param gov_local_path Optional absolute path to a local gov clone. When
#'   provided and the clone exists, the filesystem path is preferred.
#' @return Character vector of project names (sorted, may be empty).
#' @keywords internal
.datom_gov_list_projects <- function(gov_conn, gov_local_path = NULL) {
  if (!is.null(gov_local_path) && .datom_gov_clone_exists(gov_local_path)) {
    projects_dir <- fs::path(gov_local_path, "projects")
    if (!fs::dir_exists(projects_dir)) return(character(0))

    dirs <- fs::dir_ls(projects_dir, type = "directory")
    names <- as.character(fs::path_file(dirs))

    # Skip entries lacking ref.json
    keep <- purrr::map_lgl(names, function(nm) {
      fs::file_exists(fs::path(projects_dir, nm, "ref.json"))
    })
    return(sort(names[keep]))
  }

  # Storage path: list keys under "projects/" and extract unique top-level
  # segments that have a ref.json child.
  keys <- tryCatch(
    .datom_storage_list_objects(gov_conn, "projects"),
    error = function(e) {
      cli::cli_abort(c(
        "Failed to list projects from governance store.",
        "x" = "Root: {.val {gov_conn$root}}",
        "i" = "Underlying error: {conditionMessage(e)}"
      ), parent = e)
    }
  )

  if (length(keys) == 0L) return(character(0))

  # Each key looks like "{gov_prefix}/datom/projects/{name}/ref.json".
  # Extract the segment immediately after "projects/".
  matches <- regmatches(keys, regexpr("projects/[^/]+/ref\\.json$", keys))
  names <- sub("^projects/([^/]+)/ref\\.json$", "\\1", matches)
  sort(unique(names))
}


# --- Project-scoped path helper -----------------------------------------------

#' Build Project-Scoped Path Within Gov Clone
#'
#' Returns `{gov_local_path}/projects/{project_name}/`. This is where
#' `dispatch.json`, `ref.json`, and `migration_history.json` live for a given
#' project in the shared governance repo.
#'
#' @param gov_local_path Absolute path to the governance clone directory.
#' @param project_name Project name string.
#' @return An `fs_path` character scalar.
#' @keywords internal
.datom_gov_project_path <- function(gov_local_path, project_name) {
  fs::path(gov_local_path, "projects", project_name)
}
