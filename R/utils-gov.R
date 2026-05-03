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
      "i" = "Run {.fn datom_init_gov} to initialise the governance repo first."
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


# --- GOV_SEAM: write helpers --------------------------------------------------
#
# All functions below are marked GOV_SEAM. They define the port surface that a
# future companion package (datomaccess / datomanager) will take over. datom
# keeps them here for now so gov writes are self-contained R functions. Gov
# reads (.datom_resolve_ref, dispatch reads) are NOT seam-marked -- datom
# always owns those.
#
# Every helper accepts a `datom_conn` object. Git ops use `conn$gov_local_path`;
# storage ops route through `.datom_conn_for(conn, "gov")`.


# GOV_SEAM: low-level commit on the gov clone (pull first for safety).
#' Stage Files and Commit on the Gov Clone
#'
#' Pulls first (fetch + merge) to avoid diverged histories, then stages
#' `paths` relative to the gov clone root and creates a commit.
#'
#' @param conn A `datom_conn` with `gov_local_path` set.
#' @param paths Character vector of file paths **relative** to the gov clone
#'   root (e.g., `"projects/my-study/dispatch.json"`).
#' @param msg Commit message string.
#' @param staged_deletions If `TRUE`, paths represent deleted files; skip the
#'   existence check and stage with `force = TRUE`. Default `FALSE`.
#' @return Commit SHA as a string.
#' @keywords internal
.datom_gov_commit <- function(conn, paths, msg, staged_deletions = FALSE) {
  # GOV_SEAM: companion package will call this to write gov state.
  gov_path <- conn$gov_local_path
  if (is.null(gov_path)) {
    cli::cli_abort("Cannot commit to gov clone: {.arg conn} has no {.field gov_local_path}.")
  }
  .datom_git_pull(gov_path)
  .datom_git_commit(gov_path, paths, msg, staged_deletions = staged_deletions)
}


# GOV_SEAM: push the gov clone to its remote.
#' Push the Gov Clone to Remote
#'
#' Pushes the current branch of the gov clone to its remote.
#'
#' @param conn A `datom_conn` with `gov_local_path` set.
#' @return Invisible TRUE.
#' @keywords internal
.datom_gov_push <- function(conn) {
  # GOV_SEAM: companion package will call this after gov commits.
  gov_path <- conn$gov_local_path
  if (is.null(gov_path)) {
    cli::cli_abort("Cannot push gov clone: {.arg conn} has no {.field gov_local_path}.")
  }
  .datom_git_push(gov_path)
}


# GOV_SEAM: pull the gov clone from remote.
#' Pull the Gov Clone from Remote
#'
#' Fetches and merges upstream changes into the gov clone.
#'
#' @param conn A `datom_conn` with `gov_local_path` set.
#' @return Invisible TRUE.
#' @keywords internal
.datom_gov_pull <- function(conn) {
  # GOV_SEAM: companion package will call this before reading gov state.
  gov_path <- conn$gov_local_path
  if (is.null(gov_path)) {
    cli::cli_abort("Cannot pull gov clone: {.arg conn} has no {.field gov_local_path}.")
  }
  .datom_git_pull(gov_path)
}


# GOV_SEAM: write dispatch.json to gov clone + storage.
#' Write dispatch.json to Gov Clone and Storage
#'
#' Writes `projects/{project_name}/dispatch.json` to the local gov clone,
#' commits (with a pull-first), pushes, then mirrors to gov storage.
#'
#' @param conn A `datom_conn` with `gov_local_path` and gov storage fields.
#' @param project_name Project name string.
#' @param dispatch An R list representing the dispatch configuration.
#' @return Invisible TRUE.
#' @keywords internal
.datom_gov_write_dispatch <- function(conn, project_name, dispatch) {
  # GOV_SEAM: companion package takes over routing updates.
  gov_path <- conn$gov_local_path
  if (is.null(gov_path)) {
    cli::cli_abort("Cannot write dispatch: {.arg conn} has no {.field gov_local_path}.")
  }

  project_dir <- .datom_gov_project_path(gov_path, project_name)
  fs::dir_create(project_dir)

  file_path <- fs::path(project_dir, "dispatch.json")
  jsonlite::write_json(dispatch, file_path, auto_unbox = TRUE, pretty = TRUE)

  rel_path <- fs::path("projects", project_name, "dispatch.json")
  .datom_gov_commit(conn, as.character(rel_path),
                     glue::glue("Update dispatch for {project_name}"))
  .datom_gov_push(conn)

  # Mirror to gov storage
  gov_conn <- .datom_conn_for(conn, "gov")
  .datom_storage_write_json(gov_conn, glue::glue("projects/{project_name}/dispatch.json"),
                             dispatch)

  invisible(TRUE)
}


# GOV_SEAM: write ref.json to gov clone + storage.
#' Write ref.json to Gov Clone and Storage
#'
#' Writes `projects/{project_name}/ref.json` to the local gov clone,
#' commits, pushes, then mirrors to gov storage.
#'
#' @param conn A `datom_conn` with `gov_local_path` and gov storage fields.
#' @param project_name Project name string.
#' @param ref An R list representing the ref content (from `.datom_create_ref()`).
#' @return Invisible TRUE.
#' @keywords internal
.datom_gov_write_ref <- function(conn, project_name, ref) {
  # GOV_SEAM: companion package takes over data-location pointer updates.
  gov_path <- conn$gov_local_path
  if (is.null(gov_path)) {
    cli::cli_abort("Cannot write ref: {.arg conn} has no {.field gov_local_path}.")
  }

  project_dir <- .datom_gov_project_path(gov_path, project_name)
  fs::dir_create(project_dir)

  file_path <- fs::path(project_dir, "ref.json")
  jsonlite::write_json(ref, file_path, auto_unbox = TRUE, pretty = TRUE)

  rel_path <- fs::path("projects", project_name, "ref.json")
  .datom_gov_commit(conn, as.character(rel_path),
                     glue::glue("Update ref for {project_name}"))
  .datom_gov_push(conn)

  # Mirror to gov storage
  gov_conn <- .datom_conn_for(conn, "gov")
  .datom_storage_write_json(gov_conn, glue::glue("projects/{project_name}/ref.json"), ref)

  invisible(TRUE)
}


# GOV_SEAM: register a new project in the shared gov repo.
#' Register a Project in the Gov Repo
#'
#' Creates `projects/{project_name}/` in the gov clone with initial
#' `dispatch.json`, `ref.json`, and `migration_history.json`. Commits all
#' three in a single commit, pushes, then mirrors each file to gov storage.
#'
#' Aborts if the project folder already exists (namespace collision).
#'
#' @param conn A `datom_conn` with `gov_local_path` and gov storage fields.
#' @param project_name Project name string.
#' @param dispatch Initial dispatch list.
#' @param ref Initial ref list (from `.datom_create_ref()`).
#' @return Invisible TRUE.
#' @keywords internal
.datom_gov_register_project <- function(conn, project_name, dispatch, ref) {
  # GOV_SEAM: companion package takes over project registration (init → register).
  gov_path <- conn$gov_local_path
  if (is.null(gov_path)) {
    cli::cli_abort("Cannot register project: {.arg conn} has no {.field gov_local_path}.")
  }

  project_dir <- .datom_gov_project_path(gov_path, project_name)
  if (fs::dir_exists(project_dir)) {
    cli::cli_abort(c(
      "Project {.val {project_name}} is already registered in the gov repo.",
      "i" = "Found at: {.path {project_dir}}",
      "i" = "Use a different project name or decommission the existing project first."
    ))
  }

  fs::dir_create(project_dir)

  # Write all three files
  jsonlite::write_json(dispatch, fs::path(project_dir, "dispatch.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  jsonlite::write_json(ref, fs::path(project_dir, "ref.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  migration_history <- list()
  jsonlite::write_json(migration_history, fs::path(project_dir, "migration_history.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  rel_paths <- as.character(fs::path("projects", project_name,
                                     c("dispatch.json", "ref.json", "migration_history.json")))
  .datom_gov_commit(conn, rel_paths, glue::glue("Register project {project_name}"))
  .datom_gov_push(conn)

  # Mirror to gov storage
  gov_conn <- .datom_conn_for(conn, "gov")
  .datom_storage_write_json(gov_conn, glue::glue("projects/{project_name}/dispatch.json"),
                             dispatch)
  .datom_storage_write_json(gov_conn, glue::glue("projects/{project_name}/ref.json"), ref)
  .datom_storage_write_json(gov_conn, glue::glue("projects/{project_name}/migration_history.json"),
                             migration_history)

  cli::cli_alert_success("Registered project {.val {project_name}} in gov repo.")
  invisible(TRUE)
}


# GOV_SEAM: remove a project from the shared gov repo.
#' Unregister a Project from the Gov Repo
#'
#' Deletes `projects/{project_name}/` from the gov clone, commits the
#' deletions, and pushes. Does not delete gov storage files (caller
#' is responsible for cleaning up storage, typically via `datom_decommission()`).
#'
#' @param conn A `datom_conn` with `gov_local_path` set.
#' @param project_name Project name string.
#' @return Invisible TRUE.
#' @keywords internal
.datom_gov_unregister_project <- function(conn, project_name) {
  # GOV_SEAM: companion package takes over project lifecycle management.
  gov_path <- conn$gov_local_path
  if (is.null(gov_path)) {
    cli::cli_abort("Cannot unregister project: {.arg conn} has no {.field gov_local_path}.")
  }

  project_dir <- .datom_gov_project_path(gov_path, project_name)
  if (!fs::dir_exists(project_dir)) {
    cli::cli_abort(c(
      "Project {.val {project_name}} is not registered in the gov repo.",
      "i" = "Expected at: {.path {project_dir}}"
    ))
  }

  # Collect tracked files before deletion (for git staging)
  tracked_files <- as.character(
    fs::dir_ls(project_dir, recurse = TRUE, type = "file")
  )
  rel_paths <- as.character(fs::path_rel(tracked_files, gov_path))

  # Delete the project directory, then commit the staged deletions via the
  # standard gov-commit helper.
  fs::dir_delete(project_dir)
  .datom_gov_commit(
    conn,
    paths = rel_paths,
    msg = glue::glue("Unregister project {project_name}"),
    staged_deletions = TRUE
  )
  .datom_gov_push(conn)

  cli::cli_alert_success("Unregistered project {.val {project_name}} from gov repo.")
  invisible(TRUE)
}


# GOV_SEAM: append a migration event to migration_history.json.
#' Record a Migration Event in Gov Repo
#'
#' Appends `event` to `projects/{project_name}/migration_history.json` in the
#' gov clone, commits, pushes, and mirrors to gov storage.
#' Creates the file with an empty array if it does not exist.
#'
#' @param conn A `datom_conn` with `gov_local_path` and gov storage fields.
#' @param project_name Project name string.
#' @param event A named list describing the migration event. Typically
#'   includes `event_type`, `occurred_at`, and `details`.
#' @return Invisible TRUE.
#' @keywords internal
.datom_gov_record_migration <- function(conn, project_name, event) {
  # GOV_SEAM: companion package takes over migration audit trail management.
  gov_path <- conn$gov_local_path
  if (is.null(gov_path)) {
    cli::cli_abort("Cannot record migration: {.arg conn} has no {.field gov_local_path}.")
  }

  project_dir <- .datom_gov_project_path(gov_path, project_name)
  history_file <- fs::path(project_dir, "migration_history.json")

  # Read existing history or start fresh
  history <- if (fs::file_exists(history_file)) {
    jsonlite::read_json(history_file, simplifyVector = FALSE)
  } else {
    list()
  }

  # Ensure occurred_at is present
  if (is.null(event$occurred_at)) {
    event$occurred_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }

  history <- c(list(event), history)   # prepend (most recent first)

  fs::dir_create(project_dir)
  jsonlite::write_json(history, history_file, auto_unbox = TRUE, pretty = TRUE)

  rel_path <- as.character(fs::path("projects", project_name, "migration_history.json"))
  summary <- event$event_type %||% "event"
  .datom_gov_commit(conn, rel_path,
                     glue::glue("Record migration for {project_name}: {summary}"))
  .datom_gov_push(conn)

  # Mirror to gov storage
  gov_conn <- .datom_conn_for(conn, "gov")
  .datom_storage_write_json(gov_conn, glue::glue("projects/{project_name}/migration_history.json"),
                             history)

  invisible(TRUE)
}


# GOV_SEAM: guard + entry point for tearing down the whole gov repo.
#' Destroy the Gov Repo (Guard + Local Clone Removal)
#'
#' Refuses to proceed if any projects are still registered in the gov clone,
#' unless `force = TRUE`. When clear (or forced), removes the local gov clone
#' directory. GitHub repo and storage deletion are handled by the caller
#' (e.g., sandbox teardown via `gh` CLI and storage backend tools).
#'
#' **`GOV_SEAM:`** The companion package will eventually own the full gov
#' lifecycle (init -> register -> destroy) and expose a user-facing
#' `gov_decommission()`. In Phase 15, only the dev sandbox calls this.
#'
#' @param gov_local_path Absolute path to the local gov clone.
#' @param force Logical. If `TRUE`, destroy even when projects are registered.
#' @return Named character vector of registered project names (invisible), so
#'   the caller can clean up projects first if needed.
#' @keywords internal
.datom_gov_destroy <- function(gov_local_path, force = FALSE) {
  # GOV_SEAM: companion package owns the full gov lifecycle.
  cli::cli_inform(c(
    "i" = "Destroying local gov clone only -- caller is responsible for storage and GitHub repo deletion.",
    "i" = "For project-scoped teardown see {.fn datom_decommission}."
  ))
  if (!.datom_gov_clone_exists(gov_local_path)) {
    cli::cli_alert_info("Gov clone not found at {.path {gov_local_path}} -- nothing to destroy.")
    return(invisible(character(0)))
  }

  projects_dir <- fs::path(gov_local_path, "projects")
  registered <- if (fs::dir_exists(projects_dir)) {
    dirs <- fs::dir_ls(projects_dir, type = "directory")
    basename(dirs)
  } else {
    character(0)
  }

  if (length(registered) > 0L && !force) {
    cli::cli_abort(c(
      "Gov repo still has {length(registered)} registered project{?s}: {.val {registered}}.",
      "i" = "Decommission all projects first, or pass {.code force = TRUE}."
    ))
  }

  if (length(registered) > 0L) {
    cli::cli_alert_warning(
      "Destroying gov clone with {length(registered)} registered project{?s}: {.val {registered}}."
    )
  }

  fs::dir_delete(gov_local_path)
  cli::cli_alert_success("Removed local gov clone at {.path {gov_local_path}}.")

  invisible(registered)
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
