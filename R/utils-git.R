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


# --- Repo addresses -----------------------------------------------------------

#' Classify a Git Repo Address
#'
#' Sorts a data repo address into the kinds datom treats differently, using
#' git's own rules for telling a path from a URL:
#'
#' - `"folder"`: a `file://` URL or a plain path -- relative, absolute, a
#'   Windows drive path (`C:\...`, `C:/...`: a single letter before the colon
#'   is a drive, as in git) or a UNC share (`\\server\share`, `//server/share`).
#' - `"https"`: an `https://` URL.
#' - `"ssh"`: an `ssh://` (or `git+ssh://`, `ssh+git://`) URL, or the scp-like
#'   form `user@host:path` / `host:path`, which git reads as SSH whenever a
#'   colon comes before the first slash.
#' - `"other"`: any other `scheme://` URL (`http://`, `git://`, ...).
#'
#' Pure string work: no network and no file system, so a reader-only session
#' (no git2r) can call it.
#'
#' @param url A single non-empty string.
#' @return One of `"folder"`, `"https"`, `"ssh"`, `"other"`.
#' @keywords internal
.datom_git_address_kind <- function(url) {
  if (grepl("^file://", url, ignore.case = TRUE)) return("folder")
  if (grepl("^https://", url, ignore.case = TRUE)) return("https")
  if (grepl("^(ssh|git\\+ssh|ssh\\+git)://", url, ignore.case = TRUE)) return("ssh")
  if (grepl("^[A-Za-z][A-Za-z0-9+.-]*://", url)) return("other")
  # Before the scp-like test: "C:\data" has a colon before any slash.
  if (grepl("^[A-Za-z]:", url)) return("folder")
  if (grepl("^\\\\\\\\|^//", url)) return("folder")
  if (grepl("^[^/\\\\]+:", url)) return("ssh")
  "folder"
}


#' Local Path Behind a Folder Address
#'
#' Strips `file://` (and a `localhost` host) from a folder address and decodes
#' it, as git does, so it can be handed to the file system. `file:///C:/x`
#' becomes `C:/x`; a plain path is returned unchanged.
#'
#' @param url A folder address (see [.datom_git_address_kind()]).
#' @return A path string.
#' @keywords internal
.datom_folder_address_path <- function(url) {
  if (!grepl("^file://", url, ignore.case = TRUE)) return(url)
  path <- sub("^file://", "", url, ignore.case = TRUE)
  path <- sub("^localhost(?=/)", "", path, ignore.case = TRUE, perl = TRUE)
  path <- utils::URLdecode(path)
  if (grepl("^/[A-Za-z]:", path)) path <- substring(path, 2L)
  path
}


#' Absolute Path datom Records as a Folder Remote
#'
#' `file://` removed (and decoded, as git does), `~` expanded, made absolute,
#' forward slashes. git is always given this, never the address as typed, so
#' what datom checks is what git pushes to: git cannot push to a
#' `file://C:\...` address, and does not expand `~`.
#'
#' @param url A folder address (see [.datom_git_address_kind()]).
#' @return An absolute path string.
#' @keywords internal
.datom_folder_remote_path <- function(url) {
  as.character(fs::path_abs(fs::path_expand(.datom_folder_address_path(url))))
}


#' Refuse a Repo Address datom Cannot Write Through
#'
#' The address half of the writer rule in [datom_store()]: a folder needs no
#' credential, an `https://` address needs `github_pat`, and every other kind
#' is refused. Runs before any token check, clone, write or push.
#'
#' SSH is refused with or without a token: pushing over SSH would use the keys
#' of the user's SSH agent, which is datom finding a credential on its own.
#' Support for an explicitly supplied SSH key belongs to pluggable git hosts,
#' and lifting this refusal then breaks no caller.
#'
#' @param url The repo address, or `NULL`.
#' @param pat The GitHub token, or `NULL`.
#' @param arg Argument name used in messages.
#' @return Invisible `TRUE`; aborts otherwise.
#' @keywords internal
.datom_check_repo_address <- function(url, pat, arg = "data_repo_url") {
  if (is.null(url)) return(invisible(TRUE))

  kind <- .datom_git_address_kind(url)

  if (kind == "folder") return(invisible(TRUE))

  if (kind == "https") {
    if (!is.null(pat)) return(invisible(TRUE))
    cli::cli_abort(c(
      "{.arg {arg}} {.val {url}} is a web address, which needs {.arg github_pat}.",
      "i" = "Pass {.arg github_pat} to write to it.",
      "i" = "To write without a token, use a folder address instead: the path to a bare git repo.",
      "i" = "To read only, leave {.arg {arg}} out."
    ))
  }

  if (kind == "ssh") {
    cli::cli_abort(c(
      "SSH repo addresses are not supported yet: {.val {url}}.",
      "i" = "Use an {.code https://} address with {.arg github_pat}, or a folder address.",
      "i" = "datom does not push with your SSH agent's keys, because it never picks up a credential on its own."
    ))
  }

  cli::cli_abort(c(
    "{.arg {arg}} {.val {url}} is not an address datom can write to.",
    "i" = "Use an {.code https://} address with {.arg github_pat}, or a folder address.",
    "i" = "datom sends a token only over {.code https://}."
  ))
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
#' No identity is written to any git config, so a global identity set later
#' is used from the next commit on, in every repo. The one config change is
#' removal: datom's own placeholder, if an older datom saved it in the repo's
#' config, is removed first (see [.datom_git_drop_placeholder_identity()]).
#'
#' When a half is the fallback, a console note says so, the first time in an
#' R session (see [.datom_notify_identity_fallback()]). A signature git
#' resolved, or one complete from the repo and global config, uses up no
#' note.
#'
#' With `cleanup = FALSE` nothing is removed, and a placeholder value in the
#' repo's own config is instead counted as missing, the way it would be once
#' removed. git is then not asked, since it would report the placeholder as a
#' real identity. [datom_get_conn()] uses this to give the note before the
#' first commit without changing any config.
#'
#' @param repo A `git2r::repository` handle.
#' @param fallback_name,fallback_email Values for a missing `user.name` or
#'   `user.email`.
#' @param cleanup `TRUE` (commits and merges): remove datom's old placeholder
#'   from the repo's own config first. `FALSE`: read only.
#' @return A `git_signature`. A hand-built one carries two attributes:
#'   `fallback` (`TRUE`: at least one half is the fallback value) and
#'   `both_missing` (`TRUE`: both halves are). A signature git resolved
#'   carries neither, so `isTRUE(attr(sig, "fallback"))` is `FALSE` for it.
#' @keywords internal
.datom_git_signature <- function(repo,
                                 fallback_name  = "datom",
                                 fallback_email = "datom@noreply",
                                 cleanup = TRUE) {
  .datom_check_git2r()

  # First, before git resolves anything: a repo whose own config holds only
  # the placeholder older datom saved there then picks up the real identity
  # on this same call.
  if (cleanup) .datom_git_drop_placeholder_identity(repo)

  local_cfg <- git2r::config(repo)$local %||% list()
  # Read only: count each placeholder half as missing, as cleanup would leave
  # it, and skip git, which would return the placeholder as the identity.
  stale <- if (cleanup) character(0) else .datom_git_placeholder_keys(local_cfg)
  local_cfg[stale] <- NULL

  # libgit2 refuses a missing or empty name or email, so this fails for those too.
  resolved <- if (length(stale) == 0L) {
    tryCatch(git2r::default_signature(repo), error = function(e) NULL)
  }
  if (!is.null(resolved)) return(resolved)

  # The global level is read without the repo handle: git2r::config(repo)
  # lists it too, but this is the same file, read the same way.
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


#' Which Keys in a Repo's Own Git Config Hold datom's Placeholder
#'
#' @param local_cfg The repo's own config level, as `git2r::config(repo)$local`.
#' @return Character vector of `user.name` / `user.email`, each present when its
#'   value is exactly datom's placeholder for that key.
#' @noRd
.datom_git_placeholder_keys <- function(local_cfg) {
  placeholder <- c(user.name = "datom", user.email = "datom@noreply")
  # Both keys are lower-case already, which is how libgit2 lists them.
  is_placeholder <- purrr::map_lgl(names(placeholder), function(key) {
    identical(local_cfg[[key]], placeholder[[key]])
  })
  names(placeholder)[is_placeholder]
}


#' Remove datom's Placeholder Identity from a Repo's Own Git Config
#'
#' Older datom saved `user.name = "datom"` and `user.email = "datom@noreply"`
#' into the **local** config of every repo it set up when it found no
#' identity, and a repo-level value overrides the user's global one. This
#' removes each key whose value is exactly datom's placeholder for that key,
#' independently: a repo with `datom <me@lab.org>` loses `user.name` and keeps
#' the real email. The match is exact and case-sensitive, and only the repo's
#' own config level is read, so a real identity saved in the repo -- by the
#' user or by older datom copying the global one -- and every other key are
#' left alone.
#'
#' Called first in [.datom_git_signature()], so it runs just before a repo's
#' next commit, merge or version-history author. When something was removed,
#' one line says what and from which repo; a second call has nothing to
#' remove and says nothing. This line is separate from the once-per-session
#' identity note. A removal that fails is a warning, never an error: the
#' commit goes on with whatever identity git then resolves.
#'
#' @param repo A `git2r::repository` handle.
#' @return Invisible character vector of the keys removed (empty if none).
#' @keywords internal
.datom_git_drop_placeholder_identity <- function(repo) {
  .datom_check_git2r()

  remove <- .datom_git_placeholder_keys(git2r::config(repo)$local %||% list())
  if (length(remove) == 0L) return(invisible(character(0)))

  path <- as.character(fs::path_tidy(git2r::workdir(repo)))
  # git2r::config(repo, key = NULL) deletes a key, and errors if it is absent;
  # only keys just read from the repo's config get here.
  removed <- tryCatch(
    {
      do.call(git2r::config,
              c(list(repo), purrr::set_names(vector("list", length(remove)), remove)))
      TRUE
    },
    # git2r deletes the keys one after another, so a failure on the second
    # can follow a successful first: the wording must not claim nothing went.
    error = function(e) {
      cli::cli_warn(c(
        "Could not finish removing the placeholder git identity datom had saved in this repo's own git config ({.path {path}}).",
        "x" = conditionMessage(e),
        "i" = "Part of it may already be gone. Commits go on with the identity git resolves."
      ))
      FALSE
    }
  )
  if (!removed) return(invisible(character(0)))

  what <- if (length(remove) == 2L) {
    "the placeholder git identity"
  } else {
    paste0("the placeholder git ", remove)
  }
  cli::cli_alert_info(paste0(
    "Removed {what} datom had saved in this repo's own git config ",
    "({.path {path}}). Commits now use the identity git finds."
  ))
  invisible(remove)
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
#' Pulls first ([.datom_git_pull()], which stops on a merge conflict or when it
#' cannot bring the clone up to date), then pushes.
#'
#' **A push git refuses because the remote holds commits the clone lacks says
#' so**, and names `datom_pull(conn)` as the way out, instead of the credentials
#' advice other push failures get. The pull just before the push normally rules
#' this out; it remains on a branch with no upstream, where the pull merges
#' nothing, and in the seconds between the pull and the push. With no upstream
#' the message first says how to set one, because `datom_pull()` merges nothing
#' until there is one. libgit2 says "non-fastforwardable" when it has fetched the
#' remote's commit and "not present locally" when it has not, so both are
#' matched.
#'
#' @param path Repository path.
#' @param pat GitHub personal access token. Passed directly to
#'   `.datom_git_credentials()`. NULL means unauthenticated.
#' @param pull_first Pull before pushing (default). Callers that know the
#'   remote is empty (the first push, a wiped remote) pass `FALSE`.
#' @param data_file_stored `TRUE` when the caller is a write whose data file is
#'   already in storage, so a stop here says the file may be there unnamed.
#' @return Invisibly, `TRUE` when the pull before the push moved HEAD (it
#'   brought in commits the clone lacked), `FALSE` otherwise. A write uses it to
#'   decide whether the manifest it uploads may name a teammate's version that
#'   storage does not hold yet ([.datom_publish_artifacts()]).
#' @keywords internal
.datom_git_push <- function(path, pat = NULL, pull_first = TRUE,
                            data_file_stored = FALSE) {
  .datom_check_git2r()

  pulled_in <- FALSE
  if (isTRUE(pull_first)) {
    pulled_in <- .datom_git_pull(path, pat = pat, in_push = TRUE,
                                 data_file_stored = data_file_stored)
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
      if (grepl("non-fastforwardable|not present locally", conditionMessage(e))) {
        .datom_stop_push_rejected(repo, remote_name, branch_name, e,
                                  data_file_stored)
      }
      cli::cli_abort(c(
        "Failed to push to remote {.val {remote_name}}.",
        "x" = e$message,
        "i" = "Check your credentials and remote access."
      ))
    }
  )

  # git2r::push() does not set upstream tracking. Without it, .datom_git_pull()
  # merges nothing and .datom_git_ahead() cannot count (their
  # branch_get_upstream() is NULL), so on the initializing developer's machine
  # datom_pull() silently does nothing and every write pushes before it checks.
  # Set upstream after a successful push. Fetch first so the remote-tracking ref
  # exists. Any failure here is warn-only -- it must not fail the push that
  # already succeeded.
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

  invisible(isTRUE(pulled_in))
}


#' Stop on a Push git Refused Because the Clone Is Behind
#'
#' Called from [.datom_git_push()] when libgit2 refuses the push because the
#' remote branch holds commits the clone lacks. The way out is to pull and
#' re-run. On a branch with no upstream [datom_pull()] merges nothing, so the
#' message first says how to set one; the remote branch exists (the refusal says
#' so) and the pull inside the push has just fetched it, so the command works.
#'
#' @param repo A `git2r::repository` handle.
#' @param remote_name,branch_name The remote and branch being pushed.
#' @param e The condition git2r raised.
#' @param data_file_stored See [.datom_git_push()].
#' @return Does not return.
#' @keywords internal
.datom_stop_push_rejected <- function(repo, remote_name, branch_name, e,
                                      data_file_stored = FALSE) {
  msg <- conditionMessage(e)
  upstream <- tryCatch(
    git2r::branch_get_upstream(git2r::repository_head(repo)),
    error = function(e) NULL
  )
  way_out <- if (is.null(upstream)) {
    c(
      "i" = "This branch tracks no remote branch, so set one first: \\
             {.code git branch --set-upstream-to={remote_name}/{branch_name}}.",
      "i" = "Then run {.code datom_pull(conn)} to bring the clone up to date, \\
             and re-run."
    )
  } else {
    c("i" = "Run {.code datom_pull(conn)} to bring the clone up to date, then re-run.")
  }

  cli::cli_abort(
    c(
      "The remote {.val {remote_name}} has commits this clone does not, so git \\
       refused the push.",
      "x" = "{msg}",
      "i" = "Nothing was pushed or published.",
      .datom_data_file_note(data_file_stored),
      way_out
    ),
    class = "datom_push_rejected"
  )
}


#' Pull from Remote (Fetch, and Merge Only When Behind)
#'
#' The pull every write makes before it writes to the git remote or to storage
#' (requirements R3.7), and the one [datom_pull()], the push commands and the
#' migration pull make. Owned by the commands, not by heal: removing heal would
#' leave it in place.
#'
#' In order:
#'
#' 1. **The merge check** ([.datom_check_merge()]): a merge in progress stops
#'    the command before anything changes, unless it is one datom can finish
#'    (only the manifest left in conflict), which it then finishes.
#' 2. **Fetch.** A failure stops the command with a message saying the remote
#'    could not be reached; nothing has changed.
#' 3. **Merge only if the clone is behind**: HEAD does not contain the upstream
#'    tip just fetched. A clone level with the remote, or ahead of it, merges
#'    nothing. With no upstream branch nothing is merged, as before: a new code
#'    branch never has one, and on the project's branch heal pushes before it
#'    publishes, which git refuses when the clone is behind.
#' 4. **A conflict only in `.datom/manifest.json` is resolved**
#'    ([.datom_resolve_manifest_conflict()]): every write rewrites the
#'    manifest's timestamp and summary, so two clones writing different
#'    artifacts conflict there and nowhere else. The manifest is derived from
#'    the artifacts' own files, so it is rebuilt from them and the merge
#'    committed. Any other conflict stops the command, leaving the merge in
#'    progress, with the merge check's message (it lists the conflicted files
#'    and says how to finish) ending "No version is published."
#' 5. **It confirms it caught up**: HEAD must contain the tip. git2r's merge
#'    silently does nothing when the user's own uncommitted or untracked files
#'    are in the way of the incoming commits -- no error, no `MERGE_HEAD`, and
#'    `conflicts = NULL` in its result -- so this is decided by commit, never by
#'    `git2r::merge()`'s return fields. Otherwise it stops with the
#'    `git stash -u` recipe.
#'
#' Whether HEAD moved is returned for [.datom_pull_before_write()], which runs
#' the format check on every artifact after a merge. A fast-forward counts:
#' git2r returns `sha = NA` for one, so its return fields cannot say.
#'
#' @param path Repository path.
#' @param pat GitHub personal access token. Passed directly to
#'   `.datom_git_credentials()`. NULL means unauthenticated.
#' @param in_push `TRUE` for the pull inside [.datom_git_push()]: a stop then
#'   says nothing was pushed or published, rather than that datom changed
#'   nothing (the caller may already have committed).
#' @param data_file_stored `TRUE` when the caller is a write whose data file is
#'   already in storage; a stop then says the file may be there, unnamed.
#' @param reset The artifacts heal's reset put back just before this pull, so
#'   a stop says datom put them back rather than that it changed nothing.
#' @param finish_merge See [datom_pull()]; passed to the merge check.
#' @return Invisibly, `TRUE` when HEAD moved (a merge or a fast-forward),
#'   `FALSE` otherwise.
#' @keywords internal
.datom_git_pull <- function(path, pat = NULL, in_push = FALSE,
                            data_file_stored = FALSE, reset = character(),
                            finish_merge = FALSE) {
  .datom_check_git2r()

  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  # Before the fetch: a merge in progress is the user's or an interrupted pull's,
  # and nothing below may touch the clone while it lasts.
  .datom_check_merge(path, finish_merge = finish_merge)

  remotes <- git2r::remotes(repo)
  if (length(remotes) == 0L) {
    cli::cli_abort(c(
      "No remote configured.",
      "i" = "Add a remote with {.code git remote add origin <url>}"
    ))
  }

  remote_name <- remotes[[1L]]
  remote_url <- git2r::remote_url(repo, remote_name)
  cred <- .datom_git_credentials(remote_url, pat = pat)

  # Acted on outside the handler, so the stop is raised from this function.
  fetched <- tryCatch(
    {
      git2r::fetch(repo, name = remote_name, credentials = cred)
      NULL
    },
    error = function(e) e
  )
  if (!is.null(fetched)) {
    .datom_stop_fetch_failed(remote_name, fetched, in_push, data_file_stored,
                             reset = reset)
  }

  upstream_ref <- tryCatch(
    git2r::branch_get_upstream(git2r::repository_head(repo)),
    error = function(e) NULL
  )
  if (is.null(upstream_ref)) return(invisible(FALSE))

  tip <- git2r::branch_target(upstream_ref)
  head_before <- .datom_git_head_sha(repo)

  # Level with the remote or ahead of it: nothing to merge, so no merge runs.
  if (.datom_git_contains(repo, head_before, tip)) return(invisible(FALSE))

  merge_result <- .datom_git_merge_upstream(repo, upstream_ref)

  if (isTRUE(merge_result$conflicts)) {
    if (identical(.datom_git_conflicted(repo), ".datom/manifest.json")) {
      .datom_resolve_manifest_conflict(path, data_file_stored = data_file_stored)
    } else {
      .datom_stop_merge_conflict(path, after_pull = TRUE,
                                 data_file_stored = data_file_stored)
    }
  }

  # Decided by commit: merge() returns conflicts = NULL both when it succeeded
  # and when the user's files stopped it from doing anything.
  head_after <- .datom_git_head_sha(repo)
  if (!.datom_git_contains(repo, head_after, tip)) {
    .datom_stop_pull_blocked(in_push, data_file_stored, path, reset = reset)
  }

  invisible(!identical(head_before, head_after))
}


#' Merge the Upstream Branch Into the Current One
#'
#' The one call to `git2r::merge()` in the pull, in its own function so a test
#' can count it: the pull merges only when the clone is behind.
#'
#' git2r asks for a merger signature even when already up to date, so one is
#' passed rather than letting it fail on a host with no git identity.
#'
#' @param repo A `git2r::repository` handle.
#' @param upstream_ref The branch's upstream, from `git2r::branch_get_upstream()`.
#' @return `git2r::merge()`'s result.
#' @keywords internal
.datom_git_merge_upstream <- function(repo, upstream_ref) {
  sig <- .datom_git_signature(repo)
  tryCatch(
    git2r::merge(repo, upstream_ref$name, merger = sig),
    error = function(e) {
      msg <- conditionMessage(e)
      cli::cli_abort(c(
        "Failed to merge upstream changes.",
        "x" = "{msg}"
      ))
    }
  )
}


#' Does Commit A Contain Commit B
#'
#' `TRUE` when A is B or descends from it. The one test behind three decisions:
#' the merge check's "is this a merge of the remote branch" (the upstream tip
#' contains `MERGE_HEAD`), and the pull's "is the clone behind" (HEAD does not
#' contain the tip) and "did it catch up" (HEAD contains the tip).
#'
#' Equality is tested first because `git2r::descendant_of()` is `FALSE` for a
#' commit and itself. A commit that cannot be looked up, or a missing one, gives
#' `FALSE`: every caller then stops or merges, never skips a step.
#'
#' @param repo A `git2r::repository` handle.
#' @param a,b Commit SHAs, or `NA`.
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.datom_git_contains <- function(repo, a, b) {
  if (length(a) != 1L || length(b) != 1L || is.na(a) || is.na(b)) return(FALSE)
  if (identical(a, b)) return(TRUE)
  isTRUE(tryCatch(
    git2r::descendant_of(git2r::lookup(repo, a), git2r::lookup(repo, b)),
    error = function(e) FALSE
  ))
}


#' The SHA HEAD Points At
#'
#' @param repo A `git2r::repository` handle.
#' @return The SHA, or `NA_character_` in a repo with no commits.
#' @keywords internal
.datom_git_head_sha <- function(repo) {
  tryCatch(
    as.character(git2r::revparse_single(repo, "HEAD")$sha),
    error = function(e) NA_character_
  )
}


#' A File as Committed in HEAD
#'
#' Reads one file's content from a commit rather than from the working tree,
#' so a caller can compare the two. `head` names the commit: `"HEAD"` by
#' default, or another head such as `"MERGE_HEAD"`.
#'
#' @param path Repository path.
#' @param rel The file's path relative to the repo root, with forward slashes.
#' @param head The commit to read from.
#' @return The file's content as one string, or `NULL` when the commit does not
#'   hold the file, or `path` is not a git repo.
#' @keywords internal
.datom_git_head_file <- function(path, rel, head = "HEAD") {
  repo <- tryCatch(git2r::repository(path), error = function(e) NULL)
  if (is.null(repo)) return(NULL)

  obj <- tryCatch(
    git2r::revparse_single(repo, paste0(head, ":", rel)),
    error = function(e) NULL
  )
  if (is.null(obj) || !git2r::is_blob(obj)) return(NULL)

  git2r::content(obj, split = FALSE)
}


#' What a Stop in the Pull Says Has Happened
#'
#' At the start of a command nothing has changed yet, unless heal's reset has
#' just put back the command's own unfinished files, which the line above the
#' stop reported. Inside a push the caller may already have committed (and a
#' write has stored its data file), so the honest statement is narrower.
#'
#' @param in_push,reset See [.datom_git_pull()].
#' @return One sentence.
#' @keywords internal
.datom_pull_outcome <- function(in_push, reset = character()) {
  if (isTRUE(in_push)) return("Nothing was pushed or published.")
  if (length(reset) == 0L) return("datom changed nothing.")
  cli::format_inline(
    "datom put back the unfinished files of {.val {reset}} (above) and changed \\
     nothing else."
  )
}


#' The Line a Write's Stop Adds Once Its Data File Is Stored
#'
#' A write stores its data file before anything in the clone changes, so a stop
#' at its push leaves that file in storage with no version naming it.
#'
#' @param data_file_stored See [.datom_git_push()].
#' @return A named character vector of one cli bullet, or `character()`.
#' @keywords internal
.datom_data_file_note <- function(data_file_stored) {
  if (!isTRUE(data_file_stored)) return(character())
  c("i" = "This write's data file may already be in storage, unnamed until the \\
           write finishes.")
}


#' Stop When the Fetch Fails
#'
#' A failed fetch stops the command before it changes anything (design DD1):
#' the remote cannot be compared with, so nothing that depends on it is decided.
#'
#' @param remote_name The remote.
#' @param e The condition git2r raised.
#' @param in_push,data_file_stored,reset See [.datom_git_pull()].
#' @return Does not return.
#' @keywords internal
.datom_stop_fetch_failed <- function(remote_name, e, in_push, data_file_stored,
                                     reset = character()) {
  msg <- conditionMessage(e)
  outcome <- .datom_pull_outcome(in_push, reset)
  cli::cli_abort(
    c(
      "Could not fetch from the git remote {.val {remote_name}}.",
      "x" = "{msg}",
      "i" = "{outcome}",
      .datom_data_file_note(data_file_stored),
      "i" = "Check your connection, credentials and remote access, then re-run."
    ),
    class = "datom_fetch_failed"
  )
}


#' Stop When the Pull Could Not Catch Up
#'
#' Local changes are in the way of the commits the pull brings in. Which way
#' out the message gives depends on whose changes they are, and only datom's
#' own files are looked at, and only on this rare path:
#'
#' - **datom's own uncommitted files** (an unfinished write): the message names
#'   the artifact and says to re-run that write, which puts its files back and
#'   finishes, or `datom_validate(fix = TRUE)`. The stash recipe would be wrong
#'   here: `git stash pop` brings the write's manifest row back on top of the
#'   incoming manifest and leaves conflict markers in `.datom/manifest.json`,
#'   which only hand-merging datom's JSON clears (review of task 4a, traced).
#'   The artifacts are told apart as heal's reset tells them apart
#'   ([.datom_unfinished_owners()]), so both name the same ones. If the user's
#'   own files are in the way too, the re-run's own pull stops next with the
#'   stash recipe.
#' - **Only the user's own files**: the `git stash -u` recipe, traced
#'   (`research/dirty_pull_probe.R`): `-u`, because a plain `git stash` leaves
#'   an untracked file in the way; and "resolve anything `git stash pop`
#'   reports", because pop can report a conflict or refuse to restore an
#'   untracked file, keeping the stash, and a set write listing such a file in
#'   `include_paths` would otherwise commit conflict markers. The files are not
#'   named: that would mean comparing the clone's changes with what the incoming
#'   commits touch, for a rare case, and the recipe works without knowing which
#'   file blocks.
#'
#' @param in_push,data_file_stored,reset See [.datom_git_pull()].
#' @param path Repository path, to look for datom's own uncommitted files.
#' @return Does not return.
#' @keywords internal
.datom_stop_pull_blocked <- function(in_push, data_file_stored, path,
                                     reset = character()) {
  clone <- list(path = path)
  unfinished <- .datom_unfinished_files(clone)
  if (length(unfinished) > 0L) {
    .datom_stop_unfinished_work(
      .datom_uncommitted_items(.datom_unfinished_owners(clone, unfinished)),
      c("i" = .datom_pull_outcome(in_push), .datom_data_file_note(data_file_stored)),
      lead = "Could not bring the clone up to date: local changes are in the \\
              way of the incoming commits, among them unfinished work this \\
              command does not finish.",
      class = "datom_pull_blocked"
    )
  }

  outcome <- .datom_pull_outcome(in_push, reset)
  cli::cli_abort(
    c(
      "Could not bring the clone up to date: local changes are in the way of \\
       the incoming commits (see {.code git status}).",
      "i" = "{outcome}",
      .datom_data_file_note(data_file_stored),
      "i" = "Set them aside with {.code git stash -u}, run \\
             {.code datom_pull(conn)}, bring them back with \\
             {.code git stash pop}, resolve anything {.code git stash pop} \\
             reports, then re-run."
    ),
    class = "datom_pull_blocked"
  )
}


#' What Is at a Folder Repo Address
#'
#' Looks at the folder a folder address points to, without changing anything.
#' Shared by the connection-time check ([.datom_check_folder_remote()]) and by
#' [datom_init_repo()], which decide differently on the same answers.
#'
#' The folder is opened as a git repo only at that exact path, never by walking
#' up to a parent repo, so a plain folder inside some other repo reads as
#' `"not_git"`.
#'
#' @param path Local path (see [.datom_folder_address_path()]).
#' @return One of:
#'   - `"absent"`: nothing there, parent folder exists;
#'   - `"no_parent"`: nothing there, parent folder missing too;
#'   - `"empty_dir"`: an empty folder;
#'   - `"not_git"`: a file, or a folder with content that is not a git repo;
#'   - `"not_bare"`: a git repo with a working tree;
#'   - `"empty_bare"`: a bare git repo with no commits;
#'   - `"bare_with_history"`: a bare git repo with commits.
#' @keywords internal
.datom_folder_remote_state <- function(path) {
  if (!fs::dir_exists(path)) {
    if (fs::file_exists(path)) return("not_git")
    return(if (fs::dir_exists(dirname(path))) "absent" else "no_parent")
  }

  # discover = FALSE: git2r's default walks up to a parent repo.
  repo <- tryCatch(git2r::repository(path, discover = FALSE), error = function(e) NULL)
  if (is.null(repo)) {
    if (length(fs::dir_ls(path, all = TRUE)) == 0L) return("empty_dir")
    return("not_git")
  }

  if (!git2r::is_bare(repo)) return("not_bare")
  if (git2r::is_empty(repo)) "empty_bare" else "bare_with_history"
}


#' Check a Folder Address for a New Project
#'
#' The folder half of [datom_init_repo()]: decides from what is at the folder
#' whether init can go ahead, and whether it must create the bare repo. Changes
#' nothing; init creates the repo just before its first push, so a refusal
#' anywhere before that leaves the folder as it was.
#'
#' | At the folder | `create = TRUE` | `create = FALSE` |
#' |---|---|---|
#' | Nothing, or an empty folder; parent exists | Create the bare repo | Stop: no repo; suggest `create_repo = TRUE` |
#' | Parent folder missing | Stop (parents are never created) | Stop |
#' | Empty bare repo | Reuse | Use |
#' | Bare repo with history | Stop: already has content | Stop: a new project needs an empty repo |
#' | Git repo with a working tree, or not a git repo | Stop | Stop |
#'
#' Whatever will be written to -- the folder, or its parent when the folder is
#' to be created -- must be writable.
#'
#' Every folder address is recorded as a plain absolute path
#' ([.datom_folder_remote_path()]), never as typed: a relative remote in git
#' config would be resolved against whatever folder git later runs in, git
#' cannot push to `file://C:\...`, and it does not expand `~`.
#'
#' @param url The store's folder address.
#' @param create `create_repo` from [datom_init_repo()].
#' @return A list: `url` and `path` (both the absolute path to record and
#'   check), `create` (`TRUE` when init must create the bare repo), `existed`
#'   (`TRUE` when the folder was already there).
#' @keywords internal
.datom_init_folder_remote <- function(url, create) {
  path <- .datom_folder_remote_path(url)
  state <- .datom_folder_remote_state(path)

  result <- function(needs_create) {
    target <- if (needs_create && state == "absent") dirname(path) else path
    if (!.datom_folder_writable(target)) {
      cli::cli_abort(c(
        "Cannot write to {.path {target}}.",
        "i" = "The project's git repo goes there. Check the folder's permissions."
      ))
    }
    list(
      url = path,
      path = path,
      create = needs_create,
      existed = state != "absent"
    )
  }

  switch(state,
    absent = ,
    empty_dir = {
      if (create) return(result(TRUE))
      cli::cli_abort(c(
        "There is no git repo at {.path {path}}.",
        "i" = "Set {.code create_repo = TRUE} to create a bare git repo there."
      ))
    },
    no_parent = cli::cli_abort(c(
      "The folder {.path {dirname(path)}} does not exist.",
      "i" = "datom never creates parent folders for a repo address, so check the path for a typo."
    )),
    empty_bare = {
      if (create) cli::cli_alert_info("Reusing empty bare git repo {.path {path}}.")
      result(FALSE)
    },
    bare_with_history = cli::cli_abort(c(
      "The git repo at {.path {path}} already has content.",
      "x" = "A new project needs an empty repo.",
      "i" = "To work on the project already in it, use {.fn datom_clone}."
    )),
    not_bare = cli::cli_abort(c(
      "The git repo at {.path {path}} has a working tree; datom needs a bare repo.",
      "i" = "Point {.arg data_repo_url} at an empty or missing folder and set {.code create_repo = TRUE}."
    )),
    not_git = cli::cli_abort(c(
      "{.path {path}} is not a git repo.",
      "i" = "Point {.arg data_repo_url} at an empty or missing folder and set {.code create_repo = TRUE}."
    ))
  )
}


#' Undo a Folder Remote That datom_init_repo() Created
#'
#' Removes the bare repo, or empties the folder when the caller had made it
#' beforehand -- but only while it holds no history. Once someone else has
#' pushed to it (two inits racing on one shared drive, where this call's push
#' was refused because the other got there first), it is theirs and is left in
#' place with a message.
#'
#' @param folder_remote The list from [.datom_init_folder_remote()]; uses
#'   `path` and `existed`.
#' @return Invisible `TRUE` when something was removed, `FALSE` otherwise.
#' @keywords internal
.datom_undo_folder_remote <- function(folder_remote) {
  path <- folder_remote$path
  if (!fs::dir_exists(path)) return(invisible(FALSE))

  if (.datom_folder_remote_state(path) == "bare_with_history") {
    cli::cli_alert_warning(
      "Left the git repo at {.path {path}} in place: it now has history this call did not write."
    )
    return(invisible(FALSE))
  }

  if (isTRUE(folder_remote$existed)) {
    purrr::walk(fs::dir_ls(path, all = TRUE), function(p) {
      if (fs::is_dir(p)) fs::dir_delete(p) else fs::file_delete(p)
    })
  } else {
    fs::dir_delete(path)
  }
  invisible(TRUE)
}


#' Is a Folder Writable
#'
#' @param path An existing folder.
#' @return `TRUE` or `FALSE`. On Windows, R's write test for a folder can
#'   report a read-only folder as writable; a push then fails instead.
#' @keywords internal
.datom_folder_writable <- function(path) {
  isTRUE(unname(file.access(path, mode = 2L)) == 0L)
}


#' Check a Folder Remote at Connection Time
#'
#' The folder branch of [.datom_check_git_reachable()]. A folder can be
#' checked fully and offline, so unlike a web address every problem stops
#' the connection: the folder is missing, it is not a git repo, it is a repo
#' with a working tree rather than a bare one, or it cannot be written to.
#'
#' @param remote_url The clone's remote, a folder address.
#' @return Invisible `TRUE`; aborts otherwise.
#' @keywords internal
.datom_check_folder_remote <- function(remote_url) {
  path <- .datom_folder_address_path(remote_url)
  state <- .datom_folder_remote_state(path)

  if (state %in% c("absent", "no_parent")) {
    cli::cli_abort(c(
      "The git remote folder {.path {path}} does not exist.",
      "i" = "This clone pushes to that folder. Check that it has not been moved or deleted, and that its drive or share is available."
    ))
  }

  if (state %in% c("empty_dir", "not_git")) {
    cli::cli_abort(c(
      "The git remote folder {.path {path}} is not a git repo.",
      "i" = "This clone pushes to that folder, which should hold a bare git repo."
    ))
  }

  if (state == "not_bare") {
    cli::cli_abort(c(
      "The git remote folder {.path {path}} has a working tree; datom pushes only to a bare repo.",
      "i" = "Point this clone at a bare repo with {.code git2r::remote_set_url(git2r::repository(<clone>), \"origin\", <bare repo>)}."
    ))
  }

  if (!.datom_folder_writable(path)) {
    cli::cli_abort(c(
      "The git remote folder {.path {path}} cannot be written to.",
      "i" = "Writing a table pushes to that folder. Check its permissions."
    ))
  }

  invisible(TRUE)
}


#' Validate Git Remote Reachability
#'
#' Checks that the data git remote is reachable and that credentials work.
#' Called at conn-construction time in `.datom_get_conn_developer()` alongside
#' `.datom_check_data_reachable()`. The remote is the clone's own `origin`,
#' not the store's `data_repo_url`, so this is where a clone made before
#' datom refused SSH is caught.
#'
#' Failure behaviour, by the kind of address ([.datom_git_address_kind()]):
#' - No `data_repo_url`: returns invisibly (structural pass, no network needed).
#' - Folder, developer: hard abort if the folder is missing, is not a git repo,
#'   is not bare, or is not writable ([.datom_check_folder_remote()]). No
#'   network.
#' - SSH or another non-https scheme, developer: hard abort, as in
#'   [datom_store()]: datom does not push with the SSH agent's keys, and sends
#'   a token only over https.
#' - Folder, SSH or other, reader: returns invisibly. A reader never pushes.
#' - HTTPS, auth failure (HTTP 401/403): hard abort pointing to `github_pat`.
#' - HTTPS, URL not found (HTTP 404): hard abort.
#' - HTTPS, network error (timeout/DNS): warn-only (offline-tolerant).
#'
#' @param conn A `datom_conn` object. Uses `conn$data_repo_url` and
#'   `conn$github_pat`.
#' @return Invisible TRUE on success. Warns on network error (offline use ok).
#' @keywords internal
.datom_check_git_reachable <- function(conn) {
  .datom_check_git2r()

  remote_url <- conn$data_repo_url
  if (is.null(remote_url) || !nzchar(remote_url)) return(invisible(TRUE))

  kind <- .datom_git_address_kind(remote_url)

  # A reader built on a clone never pushes, so what the clone pushes to is not
  # its concern: only a developer is stopped for a folder or SSH remote.
  if (kind != "https" && !identical(conn$role, "developer")) return(invisible(TRUE))

  if (kind == "folder") return(.datom_check_folder_remote(remote_url))

  if (kind != "https") {
    what <- if (kind == "ssh") "an SSH address" else "not an https:// address"
    cli::cli_abort(c(
      "This clone's git remote {.val {remote_url}} is {what}, which datom does not support.",
      "i" = "datom does not push with your SSH agent's keys, and sends a token only over {.code https://}.",
      "i" = "Point the clone at an {.code https://} address or a folder, e.g. {.code git2r::remote_set_url(git2r::repository(path), \"origin\", url)}."
    ))
  }

  cred <- .datom_git_credentials(remote_url, pat = conn$github_pat)

  tryCatch({
    git2r::remote_ls(remote_url, credentials = cred)
    invisible(TRUE)
  }, error = function(e) {
    msg <- conditionMessage(e)

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
