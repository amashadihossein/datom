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
.datom_check_git2r <- function() {
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
#' Returns a `git2r::cred_user_pass` object when the remote URL is HTTPS and a
#' PAT has been supplied. Returns NULL for SSH remotes or when `pat` is absent.
#'
#' The PAT must be supplied explicitly -- datom does not read environment
#' variables internally. Callers obtain the PAT from `conn$github_pat`, which
#' is populated at conn-construction time from `store$github_pat`.
#'
#' @param remote_url Character remote URL.
#' @param pat GitHub personal access token. NULL (default) means no
#'   authentication; git2r will attempt unauthenticated or SSH access.
#' @return A `git2r::cred_user_pass` object or NULL.
#' @keywords internal
.datom_git_credentials <- function(remote_url, pat = NULL) {
  if (!grepl("^https://", remote_url, ignore.case = TRUE)) return(NULL)
  if (is.null(pat) || !nzchar(pat)) return(NULL)
  git2r::cred_user_pass(username = "git", password = pat)
}


# --- Read-only queries --------------------------------------------------------

#' Resolve the Git Signature for a Commit or Merge
#'
#' Returns the identity datom passes explicitly to every commit and merge it
#' makes in `repo`, so git2r never has to resolve one itself and fail on a
#' host with no git identity.
#'
#' When git resolves a complete identity -- `git2r::default_signature()`
#' reads every config level, including `~/.config/git/config`, the system
#' config and `includeIf` includes -- that signature is returned unchanged,
#' so commits are exactly what git itself would make.
#'
#' Otherwise a signature is built by hand, timestamped now. Each half is read
#' from the repo's own config, then the global config, with an empty value
#' counted as missing, and a half still missing is replaced by the fallback.
#' So a host with only a global `user.email` commits as
#' `fallback_name <that email>`. Half an identity that comes only from
#' `~/.config/git/config` or an `includeIf` include is not seen here, because
#' `git2r::config()` lists only the repo and global levels.
#'
#' Nothing is written to any git config, so a global identity set later is
#' used from the next commit on, in every repo.
#'
#' When a half is the fallback, a console note says so, the first time in an
#' R session (see [.datom_notify_identity_fallback()]). A signature git
#' resolved, or one complete from the repo and global config, uses up no
#' note.
#'
#' @param repo A `git2r::repository` handle.
#' @param fallback_name,fallback_email Values for a missing `user.name` or
#'   `user.email`.
#' @return A `git_signature`. A hand-built one carries two attributes:
#'   `fallback` (`TRUE`: at least one half is the fallback value) and
#'   `both_missing` (`TRUE`: both halves are). A signature git resolved
#'   carries neither, so `isTRUE(attr(sig, "fallback"))` is `FALSE` for it.
#' @keywords internal
.datom_git_signature <- function(repo,
                                 fallback_name  = "datom",
                                 fallback_email = "datom@noreply") {
  .datom_check_git2r()

  # libgit2 refuses a missing or empty name or email, so this fails for those too.
  resolved <- tryCatch(git2r::default_signature(repo), error = function(e) NULL)
  if (!is.null(resolved)) return(resolved)

  # The global level is read without the repo handle: git2r::config(repo)
  # lists it too, but this is the same file, read the same way.
  local_cfg  <- git2r::config(repo)$local %||% list()
  global_cfg <- git2r::config()$global %||% list()
  pick <- function(key) {
    values <- c(local_cfg[[key]] %||% "", global_cfg[[key]] %||% "")
    values[nzchar(values)][1]
  }
  name  <- pick("user.name")
  email <- pick("user.email")

  # git2r's own shape for a signature: offset is minutes east of UTC. R
  # documents gmtoff as possibly NA where the platform does not know it;
  # libgit2 needs a number, and UTC is then the honest guess.
  now <- Sys.time()
  offset <- as.POSIXlt(now)$gmtoff
  if (is.null(offset) || is.na(offset)) offset <- 0
  sig <- structure(
    list(
      name  = if (is.na(name)) fallback_name else name,
      email = if (is.na(email)) fallback_email else email,
      when  = structure(
        list(time = as.numeric(now), offset = offset / 60),
        class = "git_time"
      )
    ),
    class = "git_signature"
  )
  attr(sig, "fallback") <- is.na(name) || is.na(email)
  attr(sig, "both_missing") <- is.na(name) && is.na(email)

  if (attr(sig, "fallback")) {
    .datom_notify_identity_fallback(sig$name, sig$email, attr(sig, "both_missing"))
  }
  sig
}


#' Get the Author datom Records for a Version
#'
#' The name and email of the signature datom commits with in this repo (see
#' [.datom_git_signature()]), so the `author` in `version_history.json` is
#' the commit's author. Never fails for a missing identity: a missing half
#' is the fallback value, as in the commit.
#'
#' @param path Repository path.
#' @return Named list with `name` and `email`.
#' @keywords internal
.datom_git_author <- function(path) {
  .datom_check_git2r()

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  sig <- .datom_git_signature(repo)
  list(name = sig$name, email = sig$email)
}


#' Set Up a Repo's Own Git Config for datom
#'
#' Sets `http.followRedirects` on the **local** config of `repo`, keeping a
#' value already there. Called on every repo datom creates or clones.
#'
#' Writes no `user.name` or `user.email`: datom works out the identity at
#' commit time instead (see [.datom_git_signature()]), so a repo's own config
#' never holds an identity that would override the user's global one.
#'
#' @param repo A `git2r::repository` handle.
#' @return Invisible `repo`.
#' @keywords internal
.datom_git_ensure_local_config <- function(repo) {
  .datom_check_git2r()

  # git2r's fetch reads http.followRedirects from local config; if the key is
  # absent (fresh clone or init) it throws "config value not found". Set it
  # explicitly so fetch/push never hits this, keeping any value already there.
  # libgit2 lists config keys lower-cased, so read it back in lower case.
  local_cfg <- git2r::config(repo)$local %||% list()
  if (is.null(local_cfg[["http.followredirects"]])) {
    git2r::config(repo, "http.followRedirects" = "true")
  }

  invisible(repo)
}


# datom's only session state: notices already shown in this R session. A
# one-shot flag, not a cache -- nothing here is ever invalidated. The binding
# is locked in the namespace but the environment's contents are not, so mutate
# it with assign(envir =); `.datom_session$x <- v` also works, but rebinds a
# local copy of the name.
.datom_session <- new.env(parent = emptyenv())


#' Announce the Placeholder Git Identity
#'
#' Prints a short console note saying datom commits will carry a placeholder
#' git identity, and how to replace it. Called by [.datom_git_signature()]
#' when it falls back, so the note comes at the commit, merge or
#' version-history entry that needs the identity. Shown at most once per R
#' session. A call made with a real identity never uses up the notice, but a
#' note that was emitted and hidden -- for example under `suppressMessages()`,
#' or in a knitr chunk with `message = FALSE` -- still counts as shown.
#'
#' The fix is a global identity: datom saves no identity in a repo's own git
#' config, so a global one is used from the next commit on, in every repo.
#' The command is a git2r call only, never a shell `git` command: datom does
#' not need command-line git, so a user may not have it installed. It is
#' printed with [cli::cli_verbatim()], so cli does not wrap it at console
#' width and it stays copy-pasteable.
#'
#' An ordinary `cli` message, not a warning condition: nothing is wrong, the
#' commits work, and the note must not trip `options(warn = 2)` or `tryCatch()`
#' handlers that watch for warnings.
#'
#' @param name,email The identity datom is about to commit with (the
#'   effective values, so a partial fallback shows the real half).
#' @param both_missing `TRUE` when neither half was found, so the whole
#'   identity is the placeholder; `FALSE` when one half is the user's own, and
#'   the note calls it "this identity" rather than "the placeholder".
#' @return Invisible `TRUE` when the note was shown, `FALSE` when it had
#'   already been shown this session.
#' @keywords internal
.datom_notify_identity_fallback <- function(name, email, both_missing) {
  if (isTRUE(.datom_session$git_identity_notice_shown)) return(invisible(FALSE))
  assign("git_identity_notice_shown", TRUE, envir = .datom_session)

  # Built first: `{.code {name} <{email}>}` styles each value separately and
  # splits the placeholder into two code spans.
  identity <- paste0(name, " <", email, ">")
  what <- if (isTRUE(both_missing)) "the placeholder" else "this identity:"

  cli::cli_alert_warning(paste0(
    "No complete git identity found. datom commits will be attributed ",
    "to {what} {.code {identity}}."
  ))
  cli::cli_alert_info(paste0(
    "Set a global identity and datom uses it from the next commit, in every ",
    "repo. In R:"
  ))
  cli::cli_verbatim(paste0(
    '  git2r::config(global = TRUE, ',
    'user.name = "Your Name", user.email = "you@example.com")'
  ))

  invisible(TRUE)
}


#' Get Current Branch
#'
#' Returns the name of the currently checked-out branch.
#' Aborts on detached HEAD (datom requires a branch).
#'
#' @param path Repository path.
#' @return Branch name as a string.
#' @keywords internal
.datom_git_branch <- function(path) {
  .datom_check_git2r()

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
      "HEAD is detached \u2014 datom requires a branch.",
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
#' @param staged_deletions If `TRUE`, skip the file-existence check and use
#'   `git2r::add(force = TRUE)` so deletions can be staged. Default `FALSE`.
#' @return Commit SHA as a string.
#' @keywords internal
.datom_git_commit <- function(path, files, message, staged_deletions = FALSE) {
  .datom_check_git2r()

  if (length(files) == 0L) {
    cli::cli_abort("No files specified to commit.")
  }

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  # Verify all files exist relative to repo root (skip when staging deletions)
  if (!isTRUE(staged_deletions)) {
    full_paths <- fs::path(path, files)
    missing <- files[!fs::file_exists(full_paths)]
    if (length(missing) > 0L) {
      cli::cli_abort(c(
        "Cannot stage \u2014 files do not exist:",
        purrr::set_names(missing, rep("x", length(missing)))
      ))
    }
  }

  # Stage
  tryCatch(
    if (isTRUE(staged_deletions)) {
      git2r::add(repo, files, force = TRUE)
    } else {
      git2r::add(repo, files)
    },
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

  # Commit with an explicit signature: left NULL, git2r resolves one itself
  # and fails on a host with no git identity.
  sig <- .datom_git_signature(repo)
  commit_obj <- tryCatch(
    git2r::commit(repo, message = message, author = sig, committer = sig),
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
#' @param pat GitHub personal access token. Passed directly to
#'   `.datom_git_credentials()`. NULL means unauthenticated.
#' @return Invisible TRUE on success.
#' @keywords internal
.datom_git_push <- function(path, pat = NULL, pull_first = TRUE) {
  .datom_check_git2r()

  # Callers that know the remote is empty (first push, wiped remote) pass
  # pull_first = FALSE to skip the pre-push sync entirely.
  if (isTRUE(pull_first)) {
    .datom_git_pull(path, pat = pat)
  }

  .datom_check_git2r()

  repo <- git2r::repository(path)
  remote_name <- git2r::remotes(repo)[[1L]]
  branch_name <- .datom_git_branch(path)
  remote_url <- git2r::remote_url(repo, remote_name)
  cred <- .datom_git_credentials(remote_url, pat = pat)

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

  # git2r::push() does not set upstream tracking. Without it, .datom_git_pull()
  # and .datom_check_git_current() no-op (their branch_get_upstream() is NULL),
  # so on the initializing developer's machine datom_pull() silently does
  # nothing and the stale-state guard always passes. Set upstream after a
  # successful push. Fetch first so the remote-tracking ref exists. Any failure
  # here is warn-only -- it must not fail the push that already succeeded.
  upstream <- tryCatch(
    git2r::branch_get_upstream(git2r::repository_head(repo)),
    error = function(e) NULL
  )
  if (is.null(upstream)) {
    tryCatch({
      git2r::fetch(repo, name = remote_name, credentials = cred)
      git2r::branch_set_upstream(
        git2r::repository_head(repo),
        paste0(remote_name, "/", branch_name)
      )
    }, error = function(e) {
      cli::cli_warn(c(
        "Pushed to {.val {remote_name}} but could not set upstream tracking.",
        "i" = "Underlying error: {conditionMessage(e)}",
        "i" = "Set it manually with {.code git branch --set-upstream-to}."
      ))
    })
  }

  invisible(TRUE)
}


#' Pull from Remote (Fetch + Merge)
#'
#' Fetches from the remote and merges upstream changes into the current
#' branch. Aborts on merge conflicts - user must resolve manually.
#' This is the primary defense against diverged histories.
#'
#' @param path Repository path.
#' @param pat GitHub personal access token. Passed directly to
#'   `.datom_git_credentials()`. NULL means unauthenticated.
#' @return Invisible TRUE on success.
#' @keywords internal
.datom_git_pull <- function(path, pat = NULL) {
  .datom_check_git2r()

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

  # Build credentials for HTTPS remotes
  remote_url <- git2r::remote_url(repo, remote_name)
  cred <- .datom_git_credentials(remote_url, pat = pat)

  # Fetch from remote
  tryCatch(
    git2r::fetch(repo, name = remote_name, credentials = cred),
    error = function(e) {
      cli::cli_abort(c(
        "Failed to fetch from remote {.val {remote_name}}.",
        "x" = e$message,
        "i" = "Check your credentials and remote access."
      ))
    }
  )

  # Check if upstream branch exists
  upstream_ref <- tryCatch(
    git2r::branch_get_upstream(git2r::repository_head(repo)),
    error = function(e) NULL
  )

  if (!is.null(upstream_ref)) {
    # Merge upstream into current branch (merge expects the branch name
    # string). git2r asks for a merger signature even when already up to
    # date, so pass one rather than let it fail on a host with no identity.
    sig <- .datom_git_signature(repo)
    merge_result <- tryCatch(
      git2r::merge(repo, upstream_ref$name, merger = sig),
      error = function(e) {
        cli::cli_abort(c(
          "Failed to merge upstream changes.",
          "x" = e$message
        ))
      }
    )

    if (isTRUE(merge_result$conflicts)) {
      # Do NOT tell the caller to pull -- the pull is what produced this.
      # Conflicts here are almost always in datom's own generated JSON
      # (`version_history.json`, `.datom/manifest.json`), which a re-run
      # rebuilds from the data, so keeping the remote side is the safe
      # resolution rather than a hand-merge of hashes.
      cli::cli_abort(c(
        "Merge conflict detected \u2014 manual resolution required.",
        "i" = "See the conflicting files with {.code git status}.",
        "i" = paste(
          "For datom's own files ({.file version_history.json},",
          "{.file .datom/manifest.json}), keep the remote version",
          "({.code git checkout --theirs <file>}) and re-run your write --",
          "it rebuilds your side from the data."
        ),
        "i" = "For your own files, resolve by hand, then commit and re-run.",
        "i" = "Nothing has been written to storage, so no version is half-published."
      ))
    }
  }

  invisible(TRUE)
}


#' Check Local Branch is Current with Remote
#'
#' Fetches from the remote and compares local HEAD SHA against the upstream
#' HEAD SHA. If the local branch is behind, aborts with a clear message
#' telling the developer to pull first.
#'
#' Does NOT auto-pull - lets the developer decide how to resolve.
#'
#' If the fetch fails (offline, unreachable remote), this warns and returns
#' `TRUE` without comparing anything: the cached remote-tracking refs may be
#' arbitrarily stale, so acting on them would abort an offline developer for
#' being behind a remote they cannot reach. The backstop is
#' `.datom_git_push()`, which pulls and aborts if the push is rejected, so a
#' write cannot land on storage from a stale base.
#'
#' @param path Repository path.
#' @param pat GitHub personal access token. Passed to
#'   `.datom_git_credentials()`. NULL means unauthenticated.
#' @return Invisible `TRUE` if the local branch is up to date.
#' @keywords internal
.datom_check_git_current <- function(path, pat = NULL) {
  .datom_check_git2r()

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  remotes <- git2r::remotes(repo)
  if (length(remotes) == 0L) return(invisible(TRUE))

  remote_name <- remotes[[1L]]
  remote_url <- git2r::remote_url(repo, remote_name)
  cred <- .datom_git_credentials(remote_url, pat = pat)

  # Fetch to update remote refs (cheap -- no merge)
  #
  # The fetch outcome is captured and acted on OUTSIDE the handler. A bare
  # `return()` inside the error function returns from the handler, not from
  # this function, so execution would continue and compare HEAD against
  # whatever the last successful fetch cached -- aborting an offline user for
  # being "behind" a remote they cannot reach.
  fetched <- tryCatch(
    {
      git2r::fetch(repo, name = remote_name, credentials = cred)
      TRUE
    },
    error = function(e) {
      # Network errors should not block offline work
      cli::cli_alert_warning("Could not fetch from remote: {conditionMessage(e)}")
      FALSE
    }
  )

  # Cached upstream refs may be arbitrarily stale, so they are not compared
  if (!fetched) return(invisible(TRUE))

  # Check if upstream branch exists
  upstream_ref <- tryCatch(
    git2r::branch_get_upstream(git2r::repository_head(repo)),
    error = function(e) NULL
  )

  if (is.null(upstream_ref)) return(invisible(TRUE))

  # Compare SHAs
  local_sha <- as.character(git2r::revparse_single(repo, "HEAD")$sha)
  upstream_sha <- as.character(git2r::branch_target(upstream_ref))

  if (identical(local_sha, upstream_sha)) return(invisible(TRUE))

  # Are we behind? Check if upstream commit is an ancestor of local HEAD
  # If local is strictly behind (upstream has commits we don't have)
  branch_name <- .datom_git_branch(path)

  # Count how far behind we are via log
  behind <- tryCatch({
    ahead_behind <- git2r::ahead_behind(
      git2r::revparse_single(repo, "HEAD"),
      git2r::revparse_single(repo, upstream_ref$name)
    )
    ahead_behind[[2]]  # behind count
  }, error = function(e) NA_integer_)

  if (is.na(behind) || behind > 0L) {
    behind_msg <- if (is.na(behind)) "an unknown number of" else behind
    cli::cli_abort(c(
      "Local git branch {.val {branch_name}} is behind remote by {behind_msg} commit{?s}.",
      "i" = "Run {.fn datom_pull} or {.code git pull} to update before syncing."
    ))
  }

  invisible(TRUE)
}


#' Validate Git Remote Reachability
#'
#' Checks that the data git remote URL is reachable and that credentials work.
#' Called at conn-construction time in `.datom_get_conn_developer()` alongside
#' `.datom_check_data_reachable()`.
#'
#' Failure behaviour:
#' - No `data_repo_url`: returns invisibly (structural pass, no network needed).
#' - HTTPS, auth failure (HTTP 401/403): hard abort pointing to `github_pat`.
#' - HTTPS, URL not found (HTTP 404): hard abort.
#' - HTTPS, network error (timeout/DNS): warn-only (offline-tolerant).
#' - SSH, any error: warn-only (cannot reliably distinguish "no agent" from
#'   "offline").
#' - SSH, success: invisible TRUE.
#'
#' @param conn A `datom_conn` object. Uses `conn$data_repo_url` and
#'   `conn$github_pat`.
#' @return Invisible TRUE on success. Warns on network error (offline use ok).
#' @keywords internal
.datom_check_git_reachable <- function(conn) {
  .datom_check_git2r()

  remote_url <- conn$data_repo_url
  if (is.null(remote_url) || !nzchar(remote_url)) return(invisible(TRUE))

  is_https <- grepl("^https://", remote_url, ignore.case = TRUE)
  cred <- .datom_git_credentials(remote_url, pat = conn$github_pat)

  tryCatch({
    git2r::remote_ls(remote_url, credentials = cred)
    invisible(TRUE)
  }, error = function(e) {
    msg <- conditionMessage(e)

    if (!is_https) {
      # SSH: cannot distinguish auth failure from no agent / offline -> warn
      cli::cli_warn(c(
        "Could not verify git remote reachability for {.url {remote_url}}.",
        "i" = "Underlying error: {msg}",
        "i" = "Proceeding anyway -- operations may fail if the remote is unreachable."
      ))
      return(invisible(TRUE))
    }

    # HTTPS: classify by error message content
    if (grepl("401|403|unauthorized|forbidden|authentication required|access denied",
              msg, ignore.case = TRUE)) {
      cli::cli_abort(c(
        "Git remote authentication failed for {.url {remote_url}}.",
        "x" = msg,
        "i" = "Check the PAT supplied to {.fn datom_store}({.arg github_pat} = ...)."
      ), parent = e)
    } else if (grepl("404|not found|repository not found", msg, ignore.case = TRUE)) {
      cli::cli_abort(c(
        "Git remote {.url {remote_url}} was not found.",
        "x" = msg,
        "i" = "Check that the repository exists and the URL is correct."
      ), parent = e)
    } else {
      # Network error (timeout, DNS failure, etc.) -- warn, don't block offline use
      cli::cli_warn(c(
        "Could not verify git remote reachability.",
        "i" = "Underlying error: {msg}",
        "i" = "Proceeding anyway -- operations may fail if the remote is unreachable."
      ))
      invisible(TRUE)
    }
  })
}
