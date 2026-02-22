# Internal git operations
# Wraps git2r for commit, push, branch, and author operations.
# git2r is in Suggests -- data readers don't need it.


# --- Runtime check -----------------------------------------------------------

#' Check git2r Availability
#'
#' Aborts with a helpful message if git2r is not installed.
#'
#' @return Invisible TRUE if available.
#' @keywords internal
.tbit_check_git2r <- function() {
  if (!requireNamespace("git2r", quietly = TRUE)) {
    cli::cli_abort(c(
      "Package {.pkg git2r} is required for git operations.",
      "i" = "Install with {.code install.packages(\"git2r\")}"
    ))
  }
  invisible(TRUE)
}


#' Build Git Credentials for HTTPS Remotes
#'
#' Returns a `git2r::cred_user_pass` object using `GITHUB_PAT` if the remote
#' URL is HTTPS. Returns NULL for SSH remotes or when no PAT is available.
#'
#' @param remote_url Character remote URL.
#' @return A `git2r::cred_user_pass` object or NULL.
#' @keywords internal
.tbit_git_credentials <- function(remote_url) {
  if (!grepl("^https://", remote_url, ignore.case = TRUE)) return(NULL)

  pat <- Sys.getenv("GITHUB_PAT", unset = "")
  if (!nzchar(pat)) pat <- Sys.getenv("GITHUB_TOKEN", unset = "")
  if (!nzchar(pat)) return(NULL)

  git2r::cred_user_pass(username = "git", password = pat)
}


# --- Read-only queries --------------------------------------------------------

#' Get Author Info from Git Config
#'
#' Reads user.name and user.email from the repository's git config.
#'
#' @param path Repository path.
#' @return Named list with `name` and `email`.
#' @keywords internal
.tbit_git_author <- function(path) {
  .tbit_check_git2r()

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  cfg <- git2r::config(repo)
  local_cfg <- cfg$local %||% list()
  global_cfg <- cfg$global %||% list()

  name <- local_cfg$user.name %||% global_cfg$user.name %||% NA_character_
  email <- local_cfg$user.email %||% global_cfg$user.email %||% NA_character_

  if (is.na(name) || is.na(email)) {
    missing <- c()
    if (is.na(name)) missing <- c(missing, "user.name")
    if (is.na(email)) missing <- c(missing, "user.email")
    cli::cli_abort(c(
      "Git config incomplete: {.field {missing}} not set.",
      "i" = "Set with {.code git config --global user.name \"Your Name\"}"
    ))
  }

  list(name = name, email = email)
}


#' Get Current Branch
#'
#' Returns the name of the currently checked-out branch.
#' Aborts on detached HEAD (tbit requires a branch).
#'
#' @param path Repository path.
#' @return Branch name as a string.
#' @keywords internal
.tbit_git_branch <- function(path) {
  .tbit_check_git2r()

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  if (git2r::is_empty(repo)) {
    cli::cli_abort(c(
      "Cannot determine branch \u2014 repository has no commits.",
      "i" = "Create an initial commit first."
    ))
  }

  head_ref <- tryCatch(
    git2r::repository_head(repo),
    error = function(e) {
      cli::cli_abort(c(
        "Cannot determine branch.",
        "x" = e$message
      ))
    }
  )

  if (!git2r::is_branch(head_ref)) {
    cli::cli_abort(c(
      "HEAD is detached \u2014 tbit requires a branch.",
      "i" = "Check out a branch with {.code git checkout <branch>}"
    ))
  }

  head_ref$name
}


# --- Write operations (Chunks 2-3) -------------------------------------------

#' Commit Changes
#'
#' Stages the specified files and creates a commit.
#'
#' @param path Repository path.
#' @param files Character vector of files to add (relative to repo root).
#' @param message Commit message.
#' @return Commit SHA as a string.
#' @keywords internal
.tbit_git_commit <- function(path, files, message) {
  .tbit_check_git2r()

  if (length(files) == 0L) {
    cli::cli_abort("No files specified to commit.")
  }

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  # Verify all files exist relative to repo root
  full_paths <- fs::path(path, files)
  missing <- files[!fs::file_exists(full_paths)]
  if (length(missing) > 0L) {
    cli::cli_abort(c(
      "Cannot stage \u2014 files do not exist:",
      purrr::set_names(missing, rep("x", length(missing)))
    ))
  }

  # Stage
  tryCatch(
    git2r::add(repo, files),
    error = function(e) {
      cli::cli_abort("Failed to stage files: {e$message}")
    }
  )

  # Check there's actually something staged
  status <- git2r::status(repo, staged = TRUE, unstaged = FALSE, untracked = FALSE)
  staged_files <- unlist(status$staged, use.names = FALSE)
  if (length(staged_files) == 0L) {
    # Nothing to commit — files are already committed (e.g., re-run after
    # partial failure). Return the current HEAD SHA for idempotency.
    head_commit <- git2r::revparse_single(repo, "HEAD")
    return(as.character(head_commit$sha))
  }

  # Commit
  commit_obj <- tryCatch(
    git2r::commit(repo, message = message),
    error = function(e) {
      cli::cli_abort("Failed to commit: {e$message}")
    }
  )

  as.character(commit_obj$sha)
}


#' Push to Remote
#'
#' Pulls (fetch + merge) first to detect conflicts, then pushes.
#' Aborts on merge conflicts -- user must resolve manually per spec.
#'
#' @param path Repository path.
#' @return Invisible TRUE on success.
#' @keywords internal
.tbit_git_push <- function(path) {
  .tbit_check_git2r()

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  # Verify remote exists
  remotes <- git2r::remotes(repo)
  if (length(remotes) == 0L) {
    cli::cli_abort(c(
      "No remote configured.",
      "i" = "Add a remote with {.code git remote add origin <url>}"
    ))
  }

  remote_name <- remotes[[1L]]

  # Get current branch
  branch_name <- .tbit_git_branch(path)

  # Build credentials for HTTPS remotes
  remote_url <- git2r::remote_url(repo, remote_name)
  cred <- .tbit_git_credentials(remote_url)

  # Fetch from remote
  tryCatch(
    git2r::fetch(repo, name = remote_name, credentials = cred),
    error = function(e) {
      cli::cli_abort(c(
        "Failed to fetch from remote {.val {remote_name}}.",
        "x" = e$message
      ))
    }
  )

  # Check if upstream branch exists
  upstream_ref <- tryCatch(
    git2r::branch_get_upstream(git2r::repository_head(repo)),
    error = function(e) NULL
  )

  if (!is.null(upstream_ref)) {
    # Merge upstream into current branch (merge expects the branch name string)
    merge_result <- tryCatch(
      git2r::merge(repo, upstream_ref$name),
      error = function(e) {
        cli::cli_abort(c(
          "Failed to merge upstream changes.",
          "x" = e$message
        ))
      }
    )

    if (isTRUE(merge_result$conflicts)) {
      cli::cli_abort(c(
        "Merge conflict detected \u2014 manual resolution required.",
        "i" = "Pull latest changes, resolve conflicts, and re-run.",
        "i" = "Use {.code git status} to see conflicting files."
      ))
    }
  }

  # Push
  tryCatch(
    git2r::push(repo, name = remote_name, refspec = glue::glue("refs/heads/{branch_name}"),
                credentials = cred),
    error = function(e) {
      cli::cli_abort(c(
        "Failed to push to remote {.val {remote_name}}.",
        "x" = e$message,
        "i" = "Check your credentials and remote access."
      ))
    }
  )

  invisible(TRUE)
}
