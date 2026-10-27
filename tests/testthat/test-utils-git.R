# --- Helper: create a temporary git repo with config + initial commit ---------
create_test_repo <- function(name = "Test User", email = "test@example.com",
                            env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  repo <- git2r::init(dir)
  git2r::config(repo, user.name = name, user.email = email)

  # Need at least one commit for branch operations
  writeLines("init", fs::path(dir, "README.md"))
  git2r::add(repo, "README.md")
  git2r::commit(repo, "Initial commit")

  list(path = dir, repo = repo)
}

# Alias — all test repos have an initial commit
create_test_repo_with_commit <- create_test_repo
# =============================================================================
# .datom_check_git2r()
# =============================================================================

test_that(".datom_check_git2r succeeds when git2r is available", {
  skip_if_no_git2r()
  # git2r is installed in dev environment

  expect_true(.datom_check_git2r())
  expect_invisible(.datom_check_git2r())
})

test_that(".datom_check_git2r aborts when git2r is missing", {
  local_mocked_bindings(
    requireNamespace = function(...) FALSE,
    .package = "base"
  )
  expect_error(.datom_check_git2r(), "git2r.*required")
})


# =============================================================================
# .datom_git_author()
# =============================================================================

test_that(".datom_git_author returns name and email from local config", {
  info <- create_test_repo(name = "Jane Doe", email = "jane@lab.org")
  result <- .datom_git_author(info$path)

  expect_type(result, "list")
  expect_equal(result$name, "Jane Doe")
  expect_equal(result$email, "jane@lab.org")
})

test_that(".datom_git_author aborts on non-git directory", {
  skip_if_no_git2r()
  dir <- withr::local_tempdir()
  expect_error(.datom_git_author(dir), "Not a git repository")
})

# These run on a fresh `git2r::init()` repo with nothing in its own config, and
# local_mock_git_global() (helper-git.R) stands in for the host's global config
# and for git's own resolution, so the host's identity never leaks in. No commit
# is needed: the author comes from the signature, not from the log.

test_that(".datom_git_author falls back to the placeholder when no identity is found", {
  skip_if_no_git2r()
  local_mock_git_global(global = list())
  dir <- withr::local_tempdir()
  git2r::init(dir)

  expect_equal(.datom_git_author(dir),
               list(name = "datom", email = "datom@noreply"))
})

test_that(".datom_git_author keeps a global user.email and falls back for user.name", {
  skip_if_no_git2r()
  local_mock_git_global(global = list(user.email = "only@email.com"))
  dir <- withr::local_tempdir()
  git2r::init(dir)

  expect_equal(.datom_git_author(dir),
               list(name = "datom", email = "only@email.com"))
})

test_that(".datom_git_author keeps a repo user.name and falls back for user.email", {
  skip_if_no_git2r()
  local_mock_git_global(global = list())
  dir <- withr::local_tempdir()
  repo <- git2r::init(dir)
  git2r::config(repo, user.name = "Only Name")

  expect_equal(.datom_git_author(dir),
               list(name = "Only Name", email = "datom@noreply"))
})

test_that(".datom_git_author uses a complete global identity", {
  skip_if_no_git2r()
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  dir <- withr::local_tempdir()
  git2r::init(dir)

  expect_equal(.datom_git_author(dir),
               list(name = "Global User", email = "global@cfg.com"))
})

test_that(".datom_git_author returns an identity only git's own resolution sees", {
  skip_if_no_git2r()
  # Neither the repo nor the global file has an identity, but git resolves one
  # anyway -- as it does from ~/.config/git/config or an includeIf include,
  # which git2r::config() does not list.
  local_mock_git_global(global = list())
  local_mocked_bindings(
    default_signature = function(...) {
      structure(list(name = "Xdg Person", email = "xdg@lab.org",
                     when = structure(list(time = 0, offset = 0),
                                      class = "git_time")),
                class = "git_signature")
    },
    .package = "git2r"
  )
  dir <- withr::local_tempdir()
  git2r::init(dir)

  expect_equal(.datom_git_author(dir),
               list(name = "Xdg Person", email = "xdg@lab.org"))
})


# =============================================================================
# .datom_git_signature()
# =============================================================================

test_that(".datom_git_signature returns git's own signature unchanged", {
  skip_if_no_git2r()
  resolved <- structure(
    list(name = "Real Person", email = "real@lab.org",
         when = structure(list(time = 1, offset = 60), class = "git_time")),
    class = "git_signature"
  )
  local_mocked_bindings(default_signature = function(...) resolved,
                        .package = "git2r")
  repo <- git2r::init(withr::local_tempdir())

  sig <- .datom_git_signature(repo)

  expect_identical(sig, resolved)
  expect_false(isTRUE(attr(sig, "fallback")))
})

test_that(".datom_git_signature builds a full git2r signature when git finds none", {
  skip_if_no_git2r()
  local_mock_git_global(global = list())
  repo <- git2r::init(withr::local_tempdir())

  sig <- .datom_git_signature(repo)

  expect_s3_class(sig, "git_signature")
  expect_s3_class(sig$when, "git_time")
  expect_type(sig$when$time, "double")
  expect_type(sig$when$offset, "double")
  expect_equal(sig$name, "datom")
  expect_equal(sig$email, "datom@noreply")
  expect_true(attr(sig, "fallback"))
  expect_true(attr(sig, "both_missing"))
})

test_that(".datom_git_signature flags a half fallback as not both missing", {
  skip_if_no_git2r()
  local_mock_git_global(global = list(user.name = "Me"))
  repo <- git2r::init(withr::local_tempdir())

  sig <- .datom_git_signature(repo)

  expect_equal(sig$name, "Me")
  expect_equal(sig$email, "datom@noreply")
  expect_true(attr(sig, "fallback"))
  expect_false(attr(sig, "both_missing"))
})

test_that(".datom_git_signature counts an empty repo value as missing", {
  skip_if_no_git2r()
  # The repo's empty user.name would win over the global one if it counted.
  local_mock_git_global(global = list(user.name = "Global Name"))
  repo <- git2r::init(withr::local_tempdir())
  git2r::config(repo, user.name = "")

  expect_equal(.datom_git_signature(repo)$name, "Global Name")
})

test_that(".datom_git_signature uses the fallbacks it is given", {
  skip_if_no_git2r()
  local_mock_git_global(global = list())
  repo <- git2r::init(withr::local_tempdir())

  sig <- .datom_git_signature(repo, fallback_name = "CI Bot",
                              fallback_email = "ci@example.com")

  expect_equal(sig$name, "CI Bot")
  expect_equal(sig$email, "ci@example.com")
})


# =============================================================================
# .datom_git_ensure_local_config()
# =============================================================================

# local_mock_git_global() lives in helper-git.R, shared with test-conn.R.

test_that(".datom_git_ensure_local_config sets http.followRedirects and no identity", {
  skip_if_no_git2r()
  # A global identity is present, so a helper that copied it into the repo's
  # own config would have something to copy.
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  repo <- git2r::init(withr::local_tempdir())

  res <- .datom_git_ensure_local_config(repo)

  expect_identical(res, repo)
  cfg <- git2r::config(repo)$local
  expect_null(cfg$user.name)
  expect_null(cfg$user.email)
  # libgit2 lists config keys lower-cased, whatever case they were set in.
  expect_equal(cfg[["http.followredirects"]], "true")
})

test_that(".datom_git_ensure_local_config keeps an http.followRedirects value already in the repo", {
  skip_if_no_git2r()
  local_mock_git_global(global = list())
  repo <- git2r::init(withr::local_tempdir())
  git2r::config(repo, "http.followRedirects" = "false")

  .datom_git_ensure_local_config(repo)

  # libgit2 lists config keys lower-cased, whatever case they were set in.
  expect_equal(git2r::config(repo)$local[["http.followredirects"]], "false")
})


# --- the placeholder-identity note ---------------------------------------------
#
# The note comes from .datom_git_signature(), at the first commit, merge or
# version-history entry that falls back. Every block here starts from a session
# that has not shown it (`local_identity_notice_state(shown = FALSE)`); setup.R
# pre-marks it as shown for the rest of the suite, which would otherwise hide
# whether the note fires. One cli line is one message condition, so these count
# messages only as "some" or "none", never an exact number.

# All the text the call printed, colour and link codes stripped.
identity_notice_text <- function(expr) {
  cli::ansi_strip(paste(testthat::capture_messages(expr), collapse = ""))
}

test_that(".datom_git_signature says so when no identity is found", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list())
  repo <- git2r::init(withr::local_tempdir())

  text <- identity_notice_text(.datom_git_signature(repo))

  expect_match(text, "attributed to the placeholder `datom <datom@noreply>`", fixed = TRUE)
})

test_that(".datom_git_signature says so when only user.name is missing", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list(user.email = "me@lab.org"))
  repo <- git2r::init(withr::local_tempdir())

  text <- identity_notice_text(.datom_git_signature(repo))

  # Half of it is the user's own, so it is not called the placeholder.
  expect_match(text, "attributed to this identity: `datom <me@lab.org>`", fixed = TRUE)
  expect_no_match(text, "placeholder", fixed = TRUE)
})

test_that(".datom_git_signature says so when only user.email is missing", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list(user.name = "Me"))
  repo <- git2r::init(withr::local_tempdir())

  text <- identity_notice_text(.datom_git_signature(repo))

  expect_match(text, "attributed to this identity: `Me <datom@noreply>`", fixed = TRUE)
  expect_no_match(text, "placeholder", fixed = TRUE)
})

test_that(".datom_git_signature says nothing when git resolves an identity", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  repo <- git2r::init(withr::local_tempdir())

  expect_no_message(.datom_git_signature(repo))
  expect_false(isTRUE(.datom_session$git_identity_notice_shown))
})

test_that(".datom_git_signature says nothing when the config gives a complete identity git did not resolve", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  # git's own resolution fails, so the signature is built by hand, but both
  # halves come from the global config: nothing is a fallback.
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  local_mocked_bindings(
    default_signature = function(...) stop("no identity"),
    .package = "git2r"
  )
  repo <- git2r::init(withr::local_tempdir())

  expect_no_message(sig <- .datom_git_signature(repo))
  expect_equal(sig$name, "Global User")
  expect_false(isTRUE(.datom_session$git_identity_notice_shown))
})

test_that(".datom_git_signature says so only once per session", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list())
  repo1 <- git2r::init(withr::local_tempdir())
  repo2 <- git2r::init(withr::local_tempdir())

  first <- identity_notice_text(.datom_git_signature(repo1))
  second <- testthat::capture_messages(.datom_git_signature(repo2))

  expect_match(first, "placeholder", fixed = TRUE)
  expect_length(second, 0)
})

test_that(".datom_git_signature: a real identity does not use up the one-time note", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)

  local({
    local_mock_git_global(global = list(user.name  = "Global User",
                                        user.email = "global@cfg.com"))
    repo <- git2r::init(withr::local_tempdir())
    expect_no_message(.datom_git_signature(repo))
  })

  local({
    local_mock_git_global(global = list())
    repo <- git2r::init(withr::local_tempdir())
    text <- identity_notice_text(.datom_git_signature(repo))
    expect_match(text, "placeholder", fixed = TRUE)
  })
})

test_that(".datom_git_signature's note is a message, not a warning", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list())
  repo <- git2r::init(withr::local_tempdir())

  expect_no_warning(suppressMessages(.datom_git_signature(repo)))
  expect_true(.datom_session$git_identity_notice_shown)
})

test_that(".datom_git_signature's note gives the global fix only, as a git2r command", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list())
  repo <- git2r::init(withr::local_tempdir())
  path <- as.character(fs::path_tidy(git2r::workdir(repo)))

  text <- identity_notice_text(.datom_git_signature(repo))

  # git found no identity at any config level, not just the global file.
  expect_match(text, "No complete git identity found.", fixed = TRUE)
  expect_match(text, paste0(
    "Set a global identity and datom uses it from the next commit, ",
    "in every repo. In R:"
  ), fixed = TRUE)
  expect_match(text, paste0(
    'git2r::config(global = TRUE, ',
    'user.name = "Your Name", user.email = "you@example.com")'
  ), fixed = TRUE)
  # No per-repo fix: datom saves no identity in the repo, so there is nothing
  # there for a global identity to be overridden by.
  expect_no_match(text, "git2r::repository(", fixed = TRUE)
  expect_no_match(text, path, fixed = TRUE)
  # git2r commands only: datom does not need command-line git.
  expect_no_match(text, "git config", fixed = TRUE)
  expect_no_match(text, "git -C", fixed = TRUE)
})

test_that(".datom_git_signature: the note's R fix sets a global identity", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list())
  repo <- git2r::init(withr::local_tempdir())

  text <- identity_notice_text(.datom_git_signature(repo))

  # Run the command exactly as the note printed it, not a hand-written copy,
  # against a stand-in that records the call instead of writing the host's
  # real global config.
  lines <- trimws(strsplit(text, "\n", fixed = TRUE)[[1]])
  fix <- lines[startsWith(lines, "git2r::config(")]
  expect_length(fix, 1)
  captured <- NULL
  local_mocked_bindings(
    config = function(...) {
      captured <<- list(...)
      invisible(NULL)
    },
    .package = "git2r"
  )
  eval(parse(text = fix))

  expect_equal(captured, list(global = TRUE, user.name = "Your Name",
                              user.email = "you@example.com"))
})

test_that(".datom_git_signature's note names the fallback actually applied", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list())
  repo <- git2r::init(withr::local_tempdir())

  text <- identity_notice_text(
    .datom_git_signature(repo, fallback_name = "CI Bot",
                         fallback_email = "ci@example.com")
  )

  expect_match(text, "CI Bot <ci@example.com>", fixed = TRUE)
  expect_false(grepl("datom@noreply", text, fixed = TRUE))
})

test_that(".datom_git_commit gives the note at commit time and still commits", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list())
  dir <- withr::local_tempdir()
  repo <- git2r::init(dir)
  writeLines("data", fs::path(dir, "table.json"))

  # The flag is fresh, so the note path really runs inside the commit.
  text <- identity_notice_text(
    expect_no_error(sha <- .datom_git_commit(dir, "table.json", "Add table"))
  )

  expect_match(text, "attributed to the placeholder `datom <datom@noreply>`", fixed = TRUE)
  expect_equal(git2r::lookup(repo, sha)$author$name, "datom")
})


# =============================================================================
# .datom_git_drop_placeholder_identity()
# =============================================================================
#
# Older datom saved `datom <datom@noreply>` into a repo's own config when it
# found no identity. .datom_git_signature() removes each half that is exactly
# that placeholder, before git resolves an identity. Every test runs on a fresh
# `git2r::init()` repo with the values set in its own config, under
# local_mock_git_global(), so the host's real config is never read or written.

# A fresh repo whose own config holds `values` (a named list of config keys).
repo_with_local_config <- function(values, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  repo <- git2r::init(dir)
  do.call(git2r::config, c(list(repo), values))
  list(path = dir, repo = repo)
}

# Commit one new file through datom: the author, and every message printed.
commit_capturing_messages <- function(info) {
  writeLines("data", fs::path(info$path, "table.json"))
  sha <- NULL
  msgs <- cli::ansi_strip(testthat::capture_messages(
    sha <- .datom_git_commit(info$path, "table.json", "Add table")
  ))
  author <- git2r::lookup(info$repo, sha)$author
  list(name = author$name, email = author$email, msgs = msgs)
}

removal_line <- "datom had saved in this repo's own git config"

test_that("placeholder in the repo's config is removed and the commit uses the global identity", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  info <- repo_with_local_config(list(user.name = "datom",
                                      user.email = "datom@noreply"))
  path <- as.character(fs::path_tidy(git2r::workdir(info$repo)))

  res <- commit_capturing_messages(info)

  expect_equal(res$name, "Global User")
  expect_equal(res$email, "global@cfg.com")
  local_cfg <- git2r::config(info$repo)$local
  expect_null(local_cfg$user.name)
  expect_null(local_cfg$user.email)
  removed <- res$msgs[grepl(removal_line, res$msgs, fixed = TRUE)]
  expect_length(removed, 1)
  expect_match(removed, "Removed the placeholder git identity", fixed = TRUE)
  expect_match(removed, path, fixed = TRUE)
  expect_match(removed, "Commits now use the identity git finds.", fixed = TRUE)
  expect_false(any(grepl("No complete git identity", res$msgs, fixed = TRUE)))
  # The removal line does not use up the once-per-session identity note.
  expect_false(isTRUE(.datom_session$git_identity_notice_shown))
})

test_that("placeholder removed with no global identity: removal line, then the note, then a placeholder commit", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list())
  info <- repo_with_local_config(list(user.name = "datom",
                                      user.email = "datom@noreply"))

  res <- commit_capturing_messages(info)

  expect_equal(res$name, "datom")
  expect_equal(res$email, "datom@noreply")
  local_cfg <- git2r::config(info$repo)$local
  expect_null(local_cfg$user.name)
  expect_null(local_cfg$user.email)
  removed_at <- which(grepl(removal_line, res$msgs, fixed = TRUE))
  note_at <- which(grepl("No complete git identity", res$msgs, fixed = TRUE))
  expect_length(removed_at, 1)
  expect_length(note_at, 1)
  expect_lt(removed_at, note_at)
})

test_that("only a placeholder user.name is removed; a real repo email is kept", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list(user.name = "Global Name"))
  info <- repo_with_local_config(list(user.name = "datom",
                                      user.email = "me@lab.org"))

  res <- commit_capturing_messages(info)

  local_cfg <- git2r::config(info$repo)$local
  expect_null(local_cfg$user.name)
  expect_equal(local_cfg$user.email, "me@lab.org")
  expect_equal(res$name, "Global Name")
  expect_equal(res$email, "me@lab.org")
  removed <- res$msgs[grepl(removal_line, res$msgs, fixed = TRUE)]
  expect_length(removed, 1)
  expect_match(removed, "Removed the placeholder git user.name", fixed = TRUE)
})

test_that("only a placeholder user.email is removed; a real repo name is kept", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list(user.email = "global@lab.org"))
  info <- repo_with_local_config(list(user.name = "Local Name",
                                      user.email = "datom@noreply"))

  res <- commit_capturing_messages(info)

  local_cfg <- git2r::config(info$repo)$local
  expect_equal(local_cfg$user.name, "Local Name")
  expect_null(local_cfg$user.email)
  expect_equal(res$name, "Local Name")
  expect_equal(res$email, "global@lab.org")
  removed <- res$msgs[grepl(removal_line, res$msgs, fixed = TRUE)]
  expect_length(removed, 1)
  expect_match(removed, "Removed the placeholder git user.email", fixed = TRUE)
})

test_that("a real identity in the repo's config is untouched and nothing is said", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  info <- repo_with_local_config(list(user.name = "Local Person",
                                      user.email = "local@lab.org"))

  expect_no_message(sig <- .datom_git_signature(info$repo))

  local_cfg <- git2r::config(info$repo)$local
  expect_equal(local_cfg$user.name, "Local Person")
  expect_equal(local_cfg$user.email, "local@lab.org")
  expect_equal(sig$name, "Local Person")
})

test_that("values close to the placeholder are untouched", {
  skip_if_no_git2r()
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  near_misses <- list(
    list(user.name = "Datom",  user.email = "datom@noreply.com"),
    list(user.name = "datom ", user.email = "Datom@noreply")
  )

  purrr::walk(near_misses, function(values) {
    info <- repo_with_local_config(values)
    expect_no_message(.datom_git_drop_placeholder_identity(info$repo))
    local_cfg <- git2r::config(info$repo)$local
    expect_identical(local_cfg$user.name, values$user.name)
    expect_identical(local_cfg$user.email, values$user.email)
  })
})

test_that("removing the placeholder leaves every other key in the repo's config", {
  skip_if_no_git2r()
  local_mock_git_global(global = list())
  info <- repo_with_local_config(list(user.name = "datom",
                                      user.email = "datom@noreply",
                                      "http.followRedirects" = "true"))
  git2r::remote_add(info$repo, "origin", "https://example.com/org/repo.git")
  before <- git2r::config(info$repo)$local

  suppressMessages(.datom_git_drop_placeholder_identity(info$repo))

  after <- git2r::config(info$repo)$local
  expect_identical(after,
                   before[setdiff(names(before), c("user.name", "user.email"))])
  # libgit2 lists config keys lower-cased, whatever case they were set in.
  expect_equal(after[["http.followredirects"]], "true")
  expect_equal(git2r::remote_url(info$repo, "origin"),
               "https://example.com/org/repo.git")
})

test_that("nothing to remove: no message and no change", {
  skip_if_no_git2r()
  local_mock_git_global(global = list())
  repo <- git2r::init(withr::local_tempdir())
  before <- git2r::config(repo)$local

  expect_no_message(res <- .datom_git_drop_placeholder_identity(repo))

  expect_identical(res, character(0))
  expect_identical(git2r::config(repo)$local, before)
})

test_that("only the repo's own config level is read: a global placeholder is left alone", {
  skip_if_no_git2r()
  repo <- git2r::init(withr::local_tempdir())
  # Every git2r::config() call sees the placeholder at the global level only,
  # and none at the repo's own level.
  local_mocked_bindings(
    config = function(...) {
      list(global = list(user.name = "datom", user.email = "datom@noreply"),
           local = list())
    },
    .package = "git2r"
  )

  expect_no_warning(
    expect_no_message(res <- .datom_git_drop_placeholder_identity(repo))
  )

  expect_identical(res, character(0))
})

test_that("a second call after a removal says nothing", {
  skip_if_no_git2r()
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  info <- repo_with_local_config(list(user.name = "datom",
                                      user.email = "datom@noreply"))

  first <- cli::ansi_strip(testthat::capture_messages(
    .datom_git_signature(info$repo)
  ))

  expect_true(any(grepl(removal_line, first, fixed = TRUE)))
  expect_no_message(.datom_git_signature(info$repo))
})

test_that("a removal that fails is a warning, and the commit still goes ahead", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = FALSE)
  real_config <- git2r::config
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  info <- repo_with_local_config(list(user.name = "datom",
                                      user.email = "datom@noreply"))
  # Only a call that deletes a key (`key = NULL`) fails; reads still work.
  local_mocked_bindings(
    config = function(...) {
      args <- list(...)
      if (length(args) > 1 && any(purrr::map_lgl(args[-1], is.null))) {
        stop("config file is locked")
      }
      if (length(args) > 0 && inherits(args[[1]], "git_repository")) {
        return(do.call(real_config, args))
      }
      list(global = list(user.name = "Global User",
                         user.email = "global@cfg.com"),
           local = list())
    },
    .package = "git2r"
  )
  writeLines("data", fs::path(info$path, "table.json"))

  msgs <- testthat::capture_messages(
    expect_warning(
      sha <- .datom_git_commit(info$path, "table.json", "Add table"),
      "Could not finish removing the placeholder git identity"
    )
  )

  # The placeholder is still in the repo's config, so git commits as it.
  expect_equal(git2r::lookup(info$repo, sha)$author$name, "datom")
  expect_false(any(grepl("Removed the placeholder", msgs, fixed = TRUE)))
})

test_that("the removal line shows even after the identity note has been shown", {
  skip_if_no_git2r()
  local_identity_notice_state(shown = TRUE)
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))
  info <- repo_with_local_config(list(user.name = "datom",
                                      user.email = "datom@noreply"))

  msgs <- cli::ansi_strip(testthat::capture_messages(
    .datom_git_signature(info$repo)
  ))

  expect_true(any(grepl(removal_line, msgs, fixed = TRUE)))
})


# =============================================================================
# .datom_git_branch()
# =============================================================================

test_that(".datom_git_branch returns branch name", {
  info <- create_test_repo()
  result <- .datom_git_branch(info$path)

  expect_type(result, "character")
  expect_length(result, 1)
  # The default branch name comes from git's init.defaultBranch, so it varies by
  # machine. Compare against the repo's own HEAD, never a literal -- and this
  # way the assertion checks the branch is the *right* one, not merely a
  # plausible name.
  expect_equal(result, test_head_branch(info$repo))
})

test_that(".datom_git_branch aborts on non-git directory", {
  skip_if_no_git2r()
  dir <- withr::local_tempdir()
  expect_error(.datom_git_branch(dir), "Not a git repository")
})

test_that(".datom_git_branch aborts on repo with no commits", {
  dir <- withr::local_tempdir()
  git2r::init(dir)
  expect_error(.datom_git_branch(dir), "no commits")
})

test_that(".datom_git_branch returns correct name after branch switch", {
  info <- create_test_repo()
  git2r::branch_create(git2r::last_commit(info$repo), name = "feature-x")
  git2r::checkout(info$repo, branch = "feature-x")

  expect_equal(.datom_git_branch(info$path), "feature-x")
})

test_that(".datom_git_branch aborts on detached HEAD", {
  info <- create_test_repo()

  # Create a second commit
  writeLines("v2", fs::path(info$path, "README.md"))
  git2r::add(info$repo, "README.md")
  commit2 <- git2r::commit(info$repo, "Second commit")

  # Detach HEAD by checking out the first commit
  first_commit <- git2r::commits(info$repo)[[2]]
  git2r::checkout(first_commit)

  expect_error(.datom_git_branch(info$path), "detached")
})


# =============================================================================
# .datom_git_commit()
# =============================================================================

test_that(".datom_git_commit stages and commits files, returns SHA", {
  info <- create_test_repo_with_commit()
  writeLines("data", file.path(info$path, "table.json"))

  sha <- .datom_git_commit(info$path, "table.json", "Add table")

  expect_type(sha, "character")
  expect_equal(nchar(sha), 40L)

  # Verify commit is in log
  log <- git2r::commits(info$repo)
  expect_equal(log[[1]]$sha, sha)
  expect_equal(log[[1]]$message, "Add table")
})

test_that(".datom_git_commit handles multiple files", {
  info <- create_test_repo_with_commit()
  writeLines("a", file.path(info$path, "file_a.txt"))
  writeLines("b", file.path(info$path, "file_b.txt"))

  sha <- .datom_git_commit(info$path, c("file_a.txt", "file_b.txt"), "Add two files")

  expect_type(sha, "character")
  # Verify nothing left unstaged/untracked for these files
  status <- git2r::status(info$repo)
  untracked <- unlist(status$untracked, use.names = FALSE)
  expect_false("file_a.txt" %in% untracked)
  expect_false("file_b.txt" %in% untracked)
})

test_that(".datom_git_commit handles files in subdirectories", {
  info <- create_test_repo_with_commit()
  fs::dir_create(file.path(info$path, "customers"))
  writeLines("{}", file.path(info$path, "customers", "metadata.json"))

  sha <- .datom_git_commit(info$path, "customers/metadata.json", "Add metadata")

  expect_type(sha, "character")
  expect_equal(nchar(sha), 40L)
})

test_that(".datom_git_commit errors on empty files vector", {
  info <- create_test_repo_with_commit()
  expect_error(.datom_git_commit(info$path, character(0), "Nothing"), "No files")
})

test_that(".datom_git_commit errors on non-existent files", {
  info <- create_test_repo_with_commit()
  expect_error(
    .datom_git_commit(info$path, "ghost.txt", "Nope"),
    "do not exist"
  )
})

test_that(".datom_git_commit returns HEAD SHA when files are unchanged", {
  info <- create_test_repo_with_commit()
  # README.md is already committed and unchanged — should return HEAD SHA
  result <- .datom_git_commit(info$path, "README.md", "No change")
  head_sha <- as.character(git2r::revparse_single(info$repo, "HEAD")$sha)
  expect_equal(result, head_sha)
})

test_that(".datom_git_commit errors on non-git directory", {
  skip_if_no_git2r()
  dir <- withr::local_tempdir()
  writeLines("x", file.path(dir, "file.txt"))
  expect_error(.datom_git_commit(dir, "file.txt", "Nope"), "Not a git repository")
})

test_that(".datom_git_commit uses author from git config", {
  info <- create_test_repo_with_commit()
  git2r::config(info$repo, user.name = "Committer X", user.email = "cx@lab.org")
  writeLines("new", file.path(info$path, "new.txt"))

  sha <- .datom_git_commit(info$path, "new.txt", "New file")

  commit_obj <- git2r::lookup(info$repo, sha)
  expect_equal(commit_obj$author$name, "Committer X")
  expect_equal(commit_obj$author$email, "cx@lab.org")
})

# --- commits on a repo with no identity of its own ------------------------------
#
# A fresh `git2r::init()` repo with nothing in its own config, under
# local_mock_git_global() (helper-git.R). With `global = list()` that is a host
# with no git identity at all, on any machine: git2r's own signature lookup
# fails, exactly as it does on a CI runner.

# Commit one new file through datom and return the commit's author.
commit_author_on_fresh_repo <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  repo <- git2r::init(dir)
  writeLines("data", fs::path(dir, "table.json"))
  sha <- .datom_git_commit(dir, "table.json", "Add table")
  author <- git2r::lookup(repo, sha)$author
  list(name = author$name, email = author$email,
       local = git2r::config(repo)$local %||% list())
}

test_that(".datom_git_commit commits as the placeholder when no identity is found", {
  skip_if_no_git2r()
  local_mock_git_global(global = list())

  res <- commit_author_on_fresh_repo()

  expect_equal(res$name, "datom")
  expect_equal(res$email, "datom@noreply")
})

test_that(".datom_git_commit commits as a global identity when there is one", {
  skip_if_no_git2r()
  local_mock_git_global(global = list(user.name  = "Global User",
                                      user.email = "global@cfg.com"))

  res <- commit_author_on_fresh_repo()

  expect_equal(res$name, "Global User")
  expect_equal(res$email, "global@cfg.com")
})

test_that(".datom_git_commit keeps a global user.email when user.name is missing", {
  skip_if_no_git2r()
  local_mock_git_global(global = list(user.email = "me@lab.org"))

  res <- commit_author_on_fresh_repo()

  expect_equal(res$name, "datom")
  expect_equal(res$email, "me@lab.org")
})

test_that(".datom_git_commit keeps a global user.name when user.email is missing", {
  skip_if_no_git2r()
  local_mock_git_global(global = list(user.name = "Me"))

  res <- commit_author_on_fresh_repo()

  expect_equal(res$name, "Me")
  expect_equal(res$email, "datom@noreply")
})

test_that(".datom_git_commit writes no identity to the repo's own config", {
  skip_if_no_git2r()
  local_mock_git_global(global = list())

  res <- commit_author_on_fresh_repo()

  expect_null(res$local$user.name)
  expect_null(res$local$user.email)
})

test_that(".datom_git_commit can update an existing file", {
  info <- create_test_repo_with_commit()
  # Modify README.md (already tracked)
  writeLines("updated", file.path(info$path, "README.md"))

  sha <- .datom_git_commit(info$path, "README.md", "Update readme")

  expect_type(sha, "character")
  log <- git2r::commits(info$repo)
  expect_equal(log[[1]]$message, "Update readme")
})


# =============================================================================
# .datom_git_push()
# =============================================================================

# --- Helper: create a repo pair (working + bare remote) -----------------------
create_repo_with_remote <- function(name = "Test User", email = "test@example.com",
                                    env = parent.frame()) {
  # Create a bare repo to act as "remote"
  bare_dir <- withr::local_tempdir(.local_envir = env)
  bare_repo <- git2r::init(bare_dir, bare = TRUE)

  # Create working repo
  work_dir <- withr::local_tempdir(.local_envir = env)
  work_repo <- git2r::init(work_dir)
  git2r::config(work_repo, user.name = name, user.email = email)

  # Initial commit in working repo
  writeLines("init", fs::path(work_dir, "README.md"))
  git2r::add(work_repo, "README.md")
  git2r::commit(work_repo, "Initial commit")

  # Add bare repo as remote "origin"
  git2r::remote_add(work_repo, name = "origin", url = bare_dir)

  # Push initial commit to set up tracking
  git2r::push(work_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(work_repo)$name}"),
              set_upstream = TRUE)

  list(
    work_path = work_dir,
    work_repo = work_repo,
    bare_path = bare_dir,
    bare_repo = bare_repo
  )
}


test_that(".datom_git_push pushes commits to remote", {
  info <- create_repo_with_remote()

  # Make a new commit in working repo
  writeLines("new data", fs::path(info$work_path, "data.json"))
  git2r::add(info$work_repo, "data.json")
  git2r::commit(info$work_repo, "Add data")

  result <- .datom_git_push(info$work_path)

  expect_true(result)
  expect_invisible(.datom_git_push(info$work_path))


  # Verify bare remote received the commit
  bare_log <- git2r::commits(info$bare_repo)
  expect_equal(bare_log[[1]]$message, "Add data")
})

test_that(".datom_git_push is idempotent (no-op when nothing to push)", {
  info <- create_repo_with_remote()

  # Nothing new to push — should succeed silently
  expect_no_error(.datom_git_push(info$work_path))
})

test_that(".datom_git_push fetches and merges upstream changes", {
  info <- create_repo_with_remote()

  # Simulate another user by cloning the bare repo
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  # Other user commits + pushes
  writeLines("other work", fs::path(other_dir, "other.txt"))
  git2r::add(other_repo, "other.txt")
  git2r::commit(other_repo, "Other user commit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Original user makes a non-conflicting commit
  writeLines("my work", fs::path(info$work_path, "mine.txt"))
  git2r::add(info$work_repo, "mine.txt")
  git2r::commit(info$work_repo, "My commit")

  # Push should fetch, merge, then push
  expect_no_error(.datom_git_push(info$work_path))

  # Both commits should be in remote
  bare_log <- git2r::commits(info$bare_repo)
  messages <- purrr::map_chr(bare_log, ~ .x$message)
  expect_true("Other user commit" %in% messages)
  expect_true("My commit" %in% messages)
})

test_that(".datom_git_push aborts on merge conflict", {
  info <- create_repo_with_remote()

  # Simulate another user modifying README.md
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  writeLines("other version", fs::path(other_dir, "README.md"))
  git2r::add(other_repo, "README.md")
  git2r::commit(other_repo, "Other edit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Original user modifies the same file differently
  writeLines("my version", fs::path(info$work_path, "README.md"))
  git2r::add(info$work_repo, "README.md")
  git2r::commit(info$work_repo, "My conflicting edit")

  # Should abort with conflict message
  expect_error(.datom_git_push(info$work_path), "conflict|merge", ignore.case = TRUE)
})

test_that(".datom_git_push aborts when no remote configured", {
  info <- create_test_repo()

  expect_error(.datom_git_push(info$path), "No remote")
})

test_that(".datom_git_push aborts on non-git directory", {
  skip_if_no_git2r()
  dir <- withr::local_tempdir()
  expect_error(.datom_git_push(dir), "Not a git repository")
})

test_that(".datom_git_push returns invisible TRUE", {
  info <- create_repo_with_remote()

  writeLines("more", fs::path(info$work_path, "extra.txt"))
  git2r::add(info$work_repo, "extra.txt")
  git2r::commit(info$work_repo, "Extra commit")

  result <- .datom_git_push(info$work_path)
  expect_true(result)
})


# =============================================================================
# .datom_git_credentials()
# =============================================================================

test_that(".datom_git_credentials returns cred_user_pass for HTTPS with explicit PAT", {
  cred <- .datom_git_credentials("https://github.com/org/repo.git", pat = "ghp_testtoken123")
  expect_s3_class(cred, "cred_user_pass")
})

test_that(".datom_git_credentials returns NULL for HTTPS when no PAT supplied", {
  cred <- .datom_git_credentials("https://github.com/org/repo.git", pat = NULL)
  expect_null(cred)
})

test_that(".datom_git_credentials returns NULL for HTTPS when PAT is empty string", {
  cred <- .datom_git_credentials("https://github.com/org/repo.git", pat = "")
  expect_null(cred)
})

test_that(".datom_git_credentials returns NULL for SSH remotes", {
  cred <- .datom_git_credentials("git@github.com:org/repo.git", pat = "ghp_testtoken123")
  expect_null(cred)
})

test_that(".datom_git_credentials returns NULL when no PAT is set", {
  cred <- .datom_git_credentials("https://github.com/org/repo.git")
  expect_null(cred)
})


# =============================================================================
# .datom_git_pull()
# =============================================================================

test_that(".datom_git_pull fetches and merges upstream changes", {
  info <- create_repo_with_remote()

  # Simulate another user by cloning the bare repo
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  # Other user commits + pushes
  writeLines("upstream work", fs::path(other_dir, "upstream.txt"))
  git2r::add(other_repo, "upstream.txt")
  git2r::commit(other_repo, "Upstream commit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Pull should bring in the upstream commit
  result <- .datom_git_pull(info$work_path)

  expect_true(result)
  expect_true(fs::file_exists(fs::path(info$work_path, "upstream.txt")))

  log <- git2r::commits(info$work_repo)
  messages <- purrr::map_chr(log, ~ .x$message)
  expect_true("Upstream commit" %in% messages)
})

test_that(".datom_git_pull is no-op when already up to date", {
  info <- create_repo_with_remote()

  # Nothing upstream — should succeed silently
  expect_no_error(.datom_git_pull(info$work_path))
  expect_true(.datom_git_pull(info$work_path))
})

test_that(".datom_git_pull aborts on merge conflict", {
  info <- create_repo_with_remote()

  # Simulate another user modifying README.md
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  writeLines("other version of readme", fs::path(other_dir, "README.md"))
  git2r::add(other_repo, "README.md")
  git2r::commit(other_repo, "Other edit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Local user modifies the same file differently
  writeLines("my conflicting version", fs::path(info$work_path, "README.md"))
  git2r::add(info$work_repo, "README.md")
  git2r::commit(info$work_repo, "My conflicting edit")

  expect_error(.datom_git_pull(info$work_path), "conflict|merge", ignore.case = TRUE)
})

test_that(".datom_git_pull conflict message gives an actionable recourse", {
  info <- create_repo_with_remote()

  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir, progress = FALSE)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")
  writeLines("their version", fs::path(other_dir, "README.md"))
  git2r::add(other_repo, "README.md")
  git2r::commit(other_repo, "Their edit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  writeLines("my conflicting version", fs::path(info$work_path, "README.md"))
  git2r::add(info$work_repo, "README.md")
  git2r::commit(info$work_repo, "My conflicting edit")

  err <- tryCatch(.datom_git_pull(info$work_path), error = function(e) e)
  msg <- paste(cli::ansi_strip(conditionMessage(err)), collapse = " ")

  # Names the tool that shows the damage and the resolution for datom's own
  # generated files, which is the case an operator actually hits
  expect_match(msg, "git status")
  expect_match(msg, "--theirs")
  expect_match(msg, "version_history.json")

  # Must NOT tell the caller to pull -- the pull is what produced this
  expect_no_match(msg, "Pull latest changes")
})

test_that(".datom_git_pull aborts when no remote configured", {
  info <- create_test_repo()

  expect_error(.datom_git_pull(info$path), "No remote")
})

test_that(".datom_git_push with pull_first=FALSE succeeds on empty remote", {
  # Simulate datom_init_repo: init local repo, add a
  # brand-new bare remote, then push. Callers pass pull_first = FALSE
  # because they already know the remote has no refs.
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  work_dir <- withr::local_tempdir()
  work_repo <- git2r::init(work_dir)
  git2r::config(work_repo, user.name = "Test User", user.email = "test@example.com")
  git2r::remote_add(work_repo, name = "origin", url = bare_dir)

  writeLines("init", fs::path(work_dir, "README.md"))
  git2r::add(work_repo, "README.md")
  git2r::commit(work_repo, "Initial commit")

  # pull_first = FALSE: skip pre-push pull, push directly to empty remote
  expect_no_error(.datom_git_push(work_dir, pull_first = FALSE))

  # Verify the commit landed on the remote
  remote_refs <- git2r::remote_ls(bare_dir)
  expect_true(length(remote_refs) > 0L)
})

test_that(".datom_git_push sets upstream tracking on first push (#74 F)", {
  # Mirrors datom_init_repo: init, add empty remote, first push. git2r::push()
  # does not set upstream, so without the fix branch_get_upstream() stays NULL
  # and datom_pull()/.datom_check_git_current() would silently no-op.
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  work_dir <- withr::local_tempdir()
  work_repo <- git2r::init(work_dir)
  git2r::config(work_repo, user.name = "Test User", user.email = "test@example.com")
  git2r::remote_add(work_repo, name = "origin", url = bare_dir)

  writeLines("init", fs::path(work_dir, "README.md"))
  git2r::add(work_repo, "README.md")
  git2r::commit(work_repo, "Initial commit")

  # Precondition: no upstream before the datom push
  before <- tryCatch(
    git2r::branch_get_upstream(git2r::repository_head(work_repo)),
    error = function(e) NULL
  )
  expect_null(before)

  .datom_git_push(work_dir, pull_first = FALSE)

  # Upstream tracking is now set to origin/<branch>
  after <- git2r::branch_get_upstream(git2r::repository_head(work_repo))
  expect_false(is.null(after))
  branch_name <- git2r::repository_head(work_repo)$name
  expect_equal(after$name, paste0("origin/", branch_name))
})

test_that(".datom_git_push upstream failure does not fail the push (#74 F)", {
  # If setting upstream fails, the push (already succeeded) must still return.
  info <- create_repo_with_remote()
  writeLines("more", fs::path(info$work_path, "data.json"))
  git2r::add(info$work_repo, "data.json")
  git2r::commit(info$work_repo, "Add data")

  mockery::stub(.datom_git_push, "git2r::branch_get_upstream",
                function(...) NULL)
  mockery::stub(.datom_git_push, "git2r::branch_set_upstream",
                function(...) stop("simulated upstream failure"))

  expect_warning(
    result <- .datom_git_push(info$work_path),
    "could not set upstream"
  )
  expect_true(result)
})

test_that(".datom_git_pull succeeds with no identity when already up to date", {
  skip_if_no_git2r()
  # git2r asks for a merger signature even when there is nothing to merge, so
  # a host with no git identity fails here unless datom passes one.
  local_mock_git_global(global = list())

  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- withr::local_tempdir()
  work_repo <- git2r::init(work_dir)
  # As datom's own repo setup does; not an identity.
  git2r::config(work_repo, "http.followRedirects" = "true")
  git2r::remote_add(work_repo, name = "origin", url = bare_dir)
  writeLines("init", fs::path(work_dir, "README.md"))
  .datom_git_commit(work_dir, "README.md", "Initial commit")
  git2r::push(work_repo, name = "origin", refspec = test_head_refspec(work_repo),
              set_upstream = TRUE)

  expect_true(.datom_git_pull(work_dir))
})

test_that(".datom_git_pull aborts on non-git directory", {
  skip_if_no_git2r()
  dir <- withr::local_tempdir()
  expect_error(.datom_git_pull(dir), "Not a git repository")
})

test_that(".datom_git_pull returns invisible TRUE", {
  info <- create_repo_with_remote()
  result <- .datom_git_pull(info$work_path)
  expect_true(result)
  expect_invisible(.datom_git_pull(info$work_path))
})


# =============================================================================
# .datom_check_git_current()
# =============================================================================

test_that(".datom_check_git_current passes when up to date", {
  info <- create_repo_with_remote()

  # No upstream changes — should pass silently
  result <- .datom_check_git_current(info$work_path)
  expect_true(result)
  expect_invisible(.datom_check_git_current(info$work_path))
})

test_that(".datom_check_git_current aborts when behind remote", {
  info <- create_repo_with_remote()

  # Simulate another user pushing a commit
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  writeLines("new upstream data", fs::path(other_dir, "new_file.txt"))
  git2r::add(other_repo, "new_file.txt")
  git2r::commit(other_repo, "New upstream commit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Local repo is now behind — should abort
  expect_error(.datom_check_git_current(info$work_path), "behind remote")
})

test_that(".datom_check_git_current error message suggests datom_pull", {
  info <- create_repo_with_remote()

  # Push upstream commit
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")
  writeLines("data", fs::path(other_dir, "upstream.txt"))
  git2r::add(other_repo, "upstream.txt")
  git2r::commit(other_repo, "Upstream")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  expect_error(.datom_check_git_current(info$work_path), "datom_pull")
})

test_that(".datom_check_git_current passes when no remote configured", {
  info <- create_test_repo()

  # No remote = can't be behind → passes
  result <- .datom_check_git_current(info$path)
  expect_true(result)
})

test_that(".datom_check_git_current passes when no upstream branch", {
  info <- create_repo_with_remote()

  # Create a new local-only branch with no upstream
  git2r::branch_create(git2r::last_commit(info$work_repo), "feature-branch")
  git2r::checkout(info$work_repo, "feature-branch")

  result <- .datom_check_git_current(info$work_path)
  expect_true(result)
})

test_that(".datom_check_git_current passes when ahead of remote", {
  info <- create_repo_with_remote()

  # Make a local commit that hasn't been pushed
  writeLines("local only", fs::path(info$work_path, "local.txt"))
  git2r::add(info$work_repo, "local.txt")
  git2r::commit(info$work_repo, "Local commit")

  # Ahead, not behind — should pass
  result <- .datom_check_git_current(info$work_path)
  expect_true(result)
})

test_that(".datom_check_git_current tolerates network errors gracefully", {
  info <- create_test_repo()

  # A remote must exist so the fetch code path is reached, but the fetch itself
  # is stubbed to raise a network-like error. This exercises the graceful
  # error handling WITHOUT any real egress (previously this dialed out to
  # invalid.example.com, tripping a real DNS lookup during R CMD check).
  git2r::remote_add(info$repo, name = "origin", url = "https://invalid.example.com/repo.git")
  mockery::stub(
    .datom_check_git_current, "git2r::fetch",
    function(...) stop("simulated network failure")
  )

  # Network error should warn but not abort
  expect_no_error(.datom_check_git_current(info$path))
})

test_that(".datom_check_git_current proceeds when fetch fails and cached refs are ahead", {
  info <- create_repo_with_remote()

  # Another user pushes, so the remote genuinely moves ahead
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir, progress = FALSE)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")
  writeLines("upstream", fs::path(other_dir, "upstream.txt"))
  git2r::add(other_repo, "upstream.txt")
  git2r::commit(other_repo, "Upstream commit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Fetch once while the remote is reachable, so the remote-tracking ref is
  # CACHED AHEAD of local HEAD
  git2r::fetch(info$work_repo, name = "origin")

  # Now the remote becomes unreachable (offline). No mocking: the URL points at
  # a path that does not exist, so git2r::fetch() raises for real.
  git2r::remote_set_url(info$work_repo, "origin",
                        fs::path(withr::local_tempdir(), "unreachable"))

  # Warns about the fetch, then returns -- it must NOT abort on the stale
  # cached refs, which is what an offline developer would otherwise hit
  expect_message(
    expect_true(.datom_check_git_current(info$work_path)),
    "Could not fetch from remote"
  )
})

test_that(".datom_check_git_current proceeds when fetch fails and cached refs are level", {
  info <- create_repo_with_remote()

  # Upstream exists and is level with local; only the fetch is broken
  git2r::remote_set_url(info$work_repo, "origin",
                        fs::path(withr::local_tempdir(), "unreachable"))

  # Passes today for the wrong reason (nothing unfavourable to compare against);
  # this pins it as deliberate rather than accidental
  expect_message(
    expect_true(.datom_check_git_current(info$work_path)),
    "Could not fetch from remote"
  )
})

test_that(".datom_check_git_current aborts on non-git directory", {
  skip_if_no_git2r()
  dir <- withr::local_tempdir()
  expect_error(.datom_check_git_current(dir), "Not a git repository")
})


# =============================================================================
# .datom_check_git_reachable()
# =============================================================================

test_that(".datom_check_git_reachable returns invisible TRUE when data_repo_url is NULL", {
  skip_if_no_git2r()
  conn <- new_datom_conn(
    project_name = "p", root = "/tmp", client = NULL,
    role = "reader", backend = "local"
  )
  expect_true(.datom_check_git_reachable(conn))
  expect_invisible(.datom_check_git_reachable(conn))
})

test_that(".datom_check_git_reachable returns invisible TRUE for reachable local bare repo", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  conn <- new_datom_conn(
    project_name = "p", root = "/tmp", client = NULL,
    role = "reader", backend = "local",
    data_repo_url = bare_dir
  )
  expect_no_error(.datom_check_git_reachable(conn))
  expect_invisible(.datom_check_git_reachable(conn))
})

test_that(".datom_check_git_reachable aborts on HTTPS 401 auth failure", {
  dir <- withr::local_tempdir()
  conn <- new_datom_conn(
    project_name = "p", root = dir, client = NULL,
    role = "developer", path = dir, backend = "local",
    data_repo_url = "https://github.com/test/repo.git",
    github_pat = "bad-pat"
  )
  local_mocked_bindings(
    remote_ls = function(...) stop("request failed with status code: 401"),
    .package = "git2r"
  )
  expect_error(.datom_check_git_reachable(conn), "github_pat")
})

test_that(".datom_check_git_reachable aborts on HTTPS 403 auth failure", {
  dir <- withr::local_tempdir()
  conn <- new_datom_conn(
    project_name = "p", root = dir, client = NULL,
    role = "developer", path = dir, backend = "local",
    data_repo_url = "https://github.com/test/repo.git",
    github_pat = "bad-pat"
  )
  local_mocked_bindings(
    remote_ls = function(...) stop("request failed with status code: 403"),
    .package = "git2r"
  )
  expect_error(.datom_check_git_reachable(conn), "github_pat")
})

test_that(".datom_check_git_reachable abort message points to datom_store github_pat arg", {
  dir <- withr::local_tempdir()
  conn <- new_datom_conn(
    project_name = "p", root = dir, client = NULL,
    role = "developer", path = dir, backend = "local",
    data_repo_url = "https://github.com/test/repo.git",
    github_pat = "bad-pat"
  )
  local_mocked_bindings(
    remote_ls = function(...) stop("request failed with status code: 401"),
    .package = "git2r"
  )
  expect_error(.datom_check_git_reachable(conn), "datom_store")
})

test_that(".datom_check_git_reachable aborts on HTTPS 404 not found", {
  dir <- withr::local_tempdir()
  conn <- new_datom_conn(
    project_name = "p", root = dir, client = NULL,
    role = "developer", path = dir, backend = "local",
    data_repo_url = "https://github.com/test/nonexistent.git",
    github_pat = "some-pat"
  )
  local_mocked_bindings(
    remote_ls = function(...) stop("repository not found"),
    .package = "git2r"
  )
  expect_error(.datom_check_git_reachable(conn), "not found")
})

test_that(".datom_check_git_reachable warns (not errors) on HTTPS network timeout", {
  dir <- withr::local_tempdir()
  conn <- new_datom_conn(
    project_name = "p", root = dir, client = NULL,
    role = "developer", path = dir, backend = "local",
    data_repo_url = "https://github.com/test/repo.git",
    github_pat = "some-pat"
  )
  local_mocked_bindings(
    remote_ls = function(...) stop("Could not resolve host: github.com"),
    .package = "git2r"
  )
  expect_warning(.datom_check_git_reachable(conn), "reachability")
})

test_that(".datom_check_git_reachable conn returned on HTTPS network timeout", {
  # Warn-only: function must not abort so the caller can return the conn
  dir <- withr::local_tempdir()
  conn <- new_datom_conn(
    project_name = "p", root = dir, client = NULL,
    role = "developer", path = dir, backend = "local",
    data_repo_url = "https://github.com/test/repo.git",
    github_pat = "some-pat"
  )
  local_mocked_bindings(
    remote_ls = function(...) stop("Connection timed out"),
    .package = "git2r"
  )
  expect_no_error(withCallingHandlers(
    .datom_check_git_reachable(conn),
    warning = function(w) invokeRestart("muffleWarning")
  ))
})

# Before #134 an SSH remote was tried with the SSH agent and only warned on
# failure. A developer is now stopped before git is asked anything.
dev_conn_with_remote <- function(remote_url, role = "developer") {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  new_datom_conn(
    project_name = "p", root = dir, client = NULL,
    role = role, path = if (role == "developer") dir, backend = "local",
    data_repo_url = remote_url
  )
}

test_that(".datom_check_git_reachable stops a developer on an SSH remote without asking git (#134)", {
  skip_if_no_git2r()
  local_mocked_bindings(
    remote_ls = function(...) stop("git asked"),
    .package = "git2r"
  )
  for (url in c("git@github.com:test/repo.git", "ssh://git@host/test/repo.git")) {
    expect_error(.datom_check_git_reachable(dev_conn_with_remote(url)),
                 "is an SSH address, which datom does not support")
  }
})

test_that(".datom_check_git_reachable stops a developer on a non-https scheme (#134)", {
  skip_if_no_git2r()
  local_mocked_bindings(
    remote_ls = function(...) stop("git asked"),
    .package = "git2r"
  )
  expect_error(
    .datom_check_git_reachable(dev_conn_with_remote("http://example.com/repo.git")),
    "not an https:// address"
  )
})

test_that(".datom_check_git_reachable lets a reader through on SSH and folder remotes (#134)", {
  skip_if_no_git2r()
  local_mocked_bindings(
    remote_ls = function(...) stop("git asked"),
    .package = "git2r"
  )
  missing <- file.path(withr::local_tempdir(), "gone.git")
  for (url in c("git@github.com:test/repo.git", missing)) {
    expect_invisible(.datom_check_git_reachable(dev_conn_with_remote(url, role = "reader")))
  }
})

test_that(".datom_check_git_reachable passes a developer on a writable bare folder remote (#134)", {
  skip_if_no_git2r()
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)
  expect_invisible(.datom_check_git_reachable(dev_conn_with_remote(bare_dir)))
  expect_invisible(.datom_check_git_reachable(
    dev_conn_with_remote(paste0("file://", bare_dir))
  ))
})

test_that(".datom_check_git_reachable stops a developer whose folder remote is missing (#134)", {
  skip_if_no_git2r()
  gone <- file.path(withr::local_tempdir(), "gone.git")
  expect_error(.datom_check_git_reachable(dev_conn_with_remote(gone)),
               "does not exist")
  expect_error(
    .datom_check_git_reachable(dev_conn_with_remote(file.path(gone, "deeper.git"))),
    "does not exist"
  )
})

test_that(".datom_check_git_reachable stops a developer whose folder remote is not a git repo (#134)", {
  skip_if_no_git2r()
  plain <- withr::local_tempdir()
  writeLines("x", file.path(plain, "notes.txt"))
  expect_error(.datom_check_git_reachable(dev_conn_with_remote(plain)),
               "is not a git repo")

  empty <- withr::local_tempdir()
  expect_error(.datom_check_git_reachable(dev_conn_with_remote(empty)),
               "is not a git repo")
})

test_that(".datom_check_git_reachable stops a developer whose folder remote is read-only (#134)", {
  skip_if_no_git2r()
  skip_on_os("windows") # file.access() cannot see a read-only folder there
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)
  Sys.chmod(bare_dir, mode = "0555")
  withr::defer(Sys.chmod(bare_dir, mode = "0755"))
  skip_if(file.access(bare_dir, 2L) == 0L, "running as a user who can write anyway (root)")

  expect_error(.datom_check_git_reachable(dev_conn_with_remote(bare_dir)),
               "cannot be written to")
})

# --- .datom_folder_remote_state() (#134) --------------------------------------

test_that(".datom_folder_remote_state() tells every folder state apart", {
  skip_if_no_git2r()
  root <- withr::local_tempdir()

  expect_identical(.datom_folder_remote_state(file.path(root, "new.git")), "absent")
  expect_identical(.datom_folder_remote_state(file.path(root, "no", "new.git")), "no_parent")

  dir.create(file.path(root, "empty"))
  expect_identical(.datom_folder_remote_state(file.path(root, "empty")), "empty_dir")

  dir.create(file.path(root, "plain"))
  writeLines("x", file.path(root, "plain", "f.txt"))
  expect_identical(.datom_folder_remote_state(file.path(root, "plain")), "not_git")
  expect_identical(.datom_folder_remote_state(file.path(root, "plain", "f.txt")), "not_git")

  work <- file.path(root, "work")
  dir.create(work)
  git2r::init(work)
  expect_identical(.datom_folder_remote_state(work), "not_bare")

  # A plain folder inside a repo is not that repo.
  dir.create(file.path(work, "sub"))
  writeLines("x", file.path(work, "sub", "f.txt"))
  expect_identical(.datom_folder_remote_state(file.path(work, "sub")), "not_git")

  bare <- file.path(root, "bare.git")
  dir.create(bare)
  git2r::init(bare, bare = TRUE)
  expect_identical(.datom_folder_remote_state(bare), "empty_bare")

  # Give the bare repo a commit by pushing one from a working repo.
  src <- file.path(root, "src")
  dir.create(src)
  repo <- git2r::init(src)
  git2r::config(repo, user.name = "Test", user.email = "test@test.com")
  writeLines("x", file.path(src, "f.txt"))
  git2r::add(repo, "f.txt")
  git2r::commit(repo, "first")
  git2r::remote_add(repo, name = "origin", url = bare)
  git2r::push(repo, name = "origin", refspec = test_head_refspec(repo))
  expect_identical(.datom_folder_remote_state(bare), "bare_with_history")
})
