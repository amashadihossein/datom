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
