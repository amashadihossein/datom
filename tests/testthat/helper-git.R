# Test helpers for git fixtures -- loaded automatically by testthat.

#' Current Branch of a Fixture Repo
#'
#' `git2r::init()` honours git's `init.defaultBranch` setting, so the first
#' branch of a freshly created repo is named whatever the machine's git
#' configuration says -- `master` on some, `main` on others. Never hardcode
#' either name in a fixture or an assertion: read it from the repo.
#'
#' @param repo A `git_repository` with at least one commit.
#' @return The branch name, e.g. `"main"`.
test_head_branch <- function(repo) {
  head <- git2r::repository_head(repo)
  # Without this guard a commit-less repo yields NULL, and the refspec built
  # from it becomes the string "refs/heads/", which libgit2 rejects with a
  # message that names nothing.
  if (is.null(head) || !git2r::is_branch(head)) {
    stop("test_head_branch(): fixture repo has no checked-out branch ",
         "(no commits yet, or detached HEAD) -- commit before pushing.",
         call. = FALSE)
  }
  head$name
}

#' Push Refspec for a Fixture Repo's Current Branch
#'
#' @param repo A `git_repository` with at least one commit.
#' @return A refspec string, e.g. `"refs/heads/main"`.
test_head_refspec <- function(repo) {
  paste0("refs/heads/", test_head_branch(repo))
}

#' Skip a Test When git2r Is Not Installed
#'
#' git2r is a suggested package. A test that calls `git2r::` itself skips on
#' its own when git2r is missing, because testthat treats a missing-package
#' error as a skip on CRAN. A test that reaches git only through datom does
#' not: datom's own check stops with an ordinary error, which testthat
#' reports as a failure. Call this first in any such test, or in a fixture
#' whose every user needs git.
skip_if_no_git2r <- function() {
  testthat::skip_if_not_installed("git2r")
}

#' Set the "placeholder git identity notice already shown" Flag for One Test
#'
#' datom prints its placeholder-identity note once per R session, tracked in
#' `.datom_session`. `setup.R` pre-marks the note as shown so a host with no
#' global git identity does not print it inside whichever unrelated test first
#' falls back. A test that checks the note itself calls this with
#' `shown = FALSE` so it starts from a session that has not seen it, and the
#' prior state (including "unset") is restored when the test ends, so no test
#' depends on the order of the others.
#'
#' @param shown `TRUE` or `FALSE`: the value to hold for the rest of the test.
#' @param env Frame whose exit restores the prior state.
local_identity_notice_state <- function(shown, env = parent.frame()) {
  key <- "git_identity_notice_shown"
  had_key <- exists(key, envir = .datom_session, inherits = FALSE)
  prior <- if (had_key) get(key, envir = .datom_session, inherits = FALSE)

  assign(key, shown, envir = .datom_session)
  withr::defer(
    if (had_key) {
      assign(key, prior, envir = .datom_session)
    } else {
      rm(list = key, envir = .datom_session)
    },
    envir = env
  )
  invisible(NULL)
}

# Mock git2r::config so the global section is empty (or set to a
# stubbed value), while passthrough calls (with a repo handle) continue to
# hit the real git2r::config. libgit2 ignores HOME / XDG_CONFIG_HOME on
# some platforms, so env-based isolation is unreliable; mocking is.
#
# `signature = "simulate"` (the default) also mocks git2r::default_signature,
# which datom asks first and which reads the host's real config at every
# level. Unmocked, it would resolve this host's own identity whenever the host
# has one, and the fallback tests would see no fallback. The stand-in follows
# git's order without reading the host: the repo's own complete identity
# (resolved by the real function, since local wins), else the mocked global
# when both halves are non-empty, else the error libgit2 raises.
# `signature = "real"` leaves default_signature unmocked, for tests that set
# the repo's own identity and so do not depend on the host.
local_mock_git_global <- function(global = list(),
                                  signature = c("simulate", "real"),
                                  env = parent.frame()) {
  signature <- match.arg(signature)
  real_config <- git2r::config  # capture BEFORE rebinding
  real_signature <- git2r::default_signature
  testthat::local_mocked_bindings(
    config = function(...) {
      args <- list(...)
      if (length(args) > 0 && inherits(args[[1]], "git_repository")) {
        return(do.call(real_config, args))
      }
      list(global = global, local = list())
    },
    .package = "git2r",
    .env = env
  )
  if (signature == "real") return(invisible(NULL))

  testthat::local_mocked_bindings(
    default_signature = function(repo, ...) {
      local <- real_config(repo)$local %||% list()
      local_complete <- nzchar(local$user.name %||% "") &&
        nzchar(local$user.email %||% "")
      if (local_complete) return(real_signature(repo))
      global_complete <- nzchar(global$user.name %||% "") &&
        nzchar(global$user.email %||% "")
      if (!global_complete) stop("config value 'user.name' was not found")
      structure(list(name = global$user.name, email = global$user.email),
                class = "git_signature")
    },
    .package = "git2r",
    .env = env
  )
}
