# Decommission a project: tear down all data + remove from gov repo.

#' Decommission a datom Project
#'
#' Permanently removes all storage, git, and governance artefacts for a
#' project.  This is irreversible -- data is deleted from storage and the
#' project is unregistered from the shared governance repo.
#'
#' Teardown order (each step is warn-and-continue on failure so the remaining
#' steps still run):
#'
#' 1. Delete all objects under the data storage namespace.
#' 2. Delete the data GitHub repo via the GitHub REST API. Requires
#'    `GITHUB_PAT` with the `delete_repo` scope; skipped with a warning if
#'    the PAT is unavailable or the local clone has no GitHub remote.
#' 3. Remove the local data clone directory (`conn$path`).
#' 4. Unregister the project from the governance repo (git commit + push).
#'    Skipped with a warning when `conn$gov_local_path` is `NULL`.
#' 5. Delete the project folder from governance storage
#'    (`projects/{project_name}/`). Skipped when there is no governance client.
#'
#' @param conn A `datom_conn` object (developer role required).
#' @param confirm Character string.  Must equal `conn$project_name` exactly.
#'   No interactive prompts -- this must be supplied explicitly to prevent
#'   accidental decommissioning in scripts.
#' @return Invisible `TRUE` on success.
#' @export
datom_decommission <- function(conn, confirm = NULL) {
  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object.")
  }
  if (conn$role != "developer") {
    cli::cli_abort(
      c(
        "Decommission requires a developer connection.",
        "i" = "Current role: {.val {conn$role}}"
      )
    )
  }

  project_name <- conn$project_name

  if (!identical(confirm, project_name)) {
    cli::cli_abort(
      c(
        "Confirmation does not match the project name.",
        "i" = "Pass {.code confirm = \"{project_name}\"} to proceed."
      )
    )
  }

  cli::cli_h2("Decommissioning {.val {project_name}}")

  # ---- 1. Delete data storage ------------------------------------------------
  cli::cli_alert_info("Deleting data storage objects...")
  tryCatch(
    {
      .datom_storage_delete_prefix(conn, NULL)
      cli::cli_alert_success("Data storage objects deleted.")
    },
    error = function(e) {
      cli::cli_alert_danger("Data storage deletion failed: {conditionMessage(e)}")
      cli::cli_alert_info("Continuing with remaining teardown steps...")
    }
  )

  # ---- 2. Delete data GitHub repo -------------------------------------------
  tryCatch(
    {
      # Read the GitHub remote URL from the local clone
      repo_url <- tryCatch(
        {
          repo <- git2r::repository(conn$path)
          git2r::remote_url(repo, "origin")
        },
        error = function(e) NULL
      )

      if (is.null(repo_url) || !grepl("github\\.com", repo_url, ignore.case = TRUE)) {
        cli::cli_alert_info("No GitHub remote found -- skipping repo deletion.")
      } else {
        # Parse "owner/repo" from the URL (handles HTTPS and SSH)
        repo_full <- sub(
          ".*github\\.com[:/]([^/]+/[^/]+?)(\\.git)?$",
          "\\1",
          repo_url,
          perl = TRUE
        )
        pat <- Sys.getenv("GITHUB_PAT")
        if (!nzchar(pat)) {
          cli::cli_alert_warning(
            "GITHUB_PAT not set. Delete {.val {repo_full}} manually."
          )
        } else {
          cli::cli_alert_info("Deleting GitHub repo {.val {repo_full}}...")
          tryCatch(
            {
              .datom_delete_github_repo(repo_full, pat)
              cli::cli_alert_success("Deleted GitHub repo {.val {repo_full}}.")
            },
            error = function(e) {
              cli::cli_alert_danger(
                "GitHub repo deletion failed: {conditionMessage(e)}"
              )
              cli::cli_alert_info("Delete {.val {repo_full}} manually.")
            }
          )
        }
      }
    },
    error = function(e) {
      cli::cli_alert_danger("GitHub repo deletion step failed: {conditionMessage(e)}")
      cli::cli_alert_info("Continuing with remaining teardown steps...")
    }
  )

  # ---- 3. Remove local data clone -------------------------------------------
  if (!is.null(conn$path) && fs::dir_exists(conn$path)) {
    cli::cli_alert_info("Removing local clone {.path {conn$path}}...")
    tryCatch(
      {
        fs::dir_delete(conn$path)
        cli::cli_alert_success("Removed local clone.")
      },
      error = function(e) {
        cli::cli_alert_danger("Failed to remove local clone: {conditionMessage(e)}")
      }
    )
  }

  # ---- 4. Gov unregister (git commit + push) --------------------------------
  if (!is.null(conn$gov_local_path)) {
    cli::cli_alert_info("Unregistering {.val {project_name}} from gov repo...")
    tryCatch(
      {
        .datom_gov_unregister_project(conn, project_name)
      },
      error = function(e) {
        cli::cli_alert_danger("Gov unregister failed: {conditionMessage(e)}")
        cli::cli_alert_info(
          "Project may still appear in gov repo. Clean up {.path {conn$gov_local_path}} manually."
        )
      }
    )
  } else {
    cli::cli_alert_warning(
      "No gov_local_path on connection -- skipping gov unregister."
    )
  }

  # ---- 5. Delete gov storage project folder ---------------------------------
  if (!is.null(conn$gov_client) || conn$backend == "local") {
    gov_conn <- .datom_gov_conn(conn)
    proj_prefix <- paste0("projects/", project_name)
    cli::cli_alert_info("Deleting gov storage prefix {.path {proj_prefix}}...")
    tryCatch(
      {
        .datom_storage_delete_prefix(gov_conn, proj_prefix)
        cli::cli_alert_success("Deleted gov storage prefix.")
      },
      error = function(e) {
        cli::cli_alert_danger("Gov storage deletion failed: {conditionMessage(e)}")
      }
    )
  } else {
    cli::cli_alert_info("No gov client -- skipping gov storage deletion.")
  }

  cli::cli_alert_success("Decommissioned {.val {project_name}}.")
  invisible(TRUE)
}
