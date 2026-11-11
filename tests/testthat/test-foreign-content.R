# A datom repo routinely holds content datom does not own -- a build package's
# code, its environment lockfile, its own working files -- because the product
# repo is the joint repo. Two guarantees follow, and both were true by accident
# of implementation before they were true on purpose (R14.1, R14.2). These tests
# are what make a later refactor that breaks either one fail here rather than in
# somebody's repo.
#
# Why each test is shaped the way it is, since three cheaper spellings all pass
# while defending nothing:
#
#   * The commit-isolation test reads the REAL commit tree. There is already a
#     test that mocks `.datom_git_commit()` and inspects the file list it was
#     handed (`test-read-write.R`, "datom_write commits manifest.json"); adding
#     an exclusion assertion there would stay green through exactly the add-all
#     refactor this guards against, because the mock replaces the function whose
#     file list IS the guarantee. So: real git, real write, and the commit's tree
#     read back with git2r.
#   * The working-tree half is asserted separately. A write that "helpfully"
#     cleaned the tree would leave the commit correct and the developer's edit
#     gone, so excluded-from-the-commit and still-dirty are two claims.
#   * The foreign directory is named `dp/`, which is NOT one of the seven names
#     `.datom_validate_tables()` drops by hardcoded name. A test using `R/` or
#     `renv/` passes through that list and would stay green if the
#     `metadata.json` filter -- the mechanism R14.2 actually rests on -- were
#     deleted.
#
# Tolerance has two mechanisms on two surfaces and neither implies the other:
# artifact discovery filters directories on the presence of `metadata.json`,
# while the repo-level checks walk an explicit list of files datom expects and so
# never enumerate the repo at all. A refactor of the second into a directory walk
# would satisfy the first test and break R14.2.


# --- fixture ------------------------------------------------------------------

#' Real product project carrying foreign content: git repo + bare remote +
#' local store + product config + a tracked code file datom does not own.
#'
#' Same shape and same reason as `local_set_project()` in `test-write-set.R`;
#' duplicated because testthat does not share definitions between test files.
#' `R/foo.R` is committed here so a later edit to it is an uncommitted change to
#' a TRACKED file, which is the state AC16 describes.
local_foreign_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)

  repo_dir <- fs::path(root, "repo")
  store_dir <- fs::path(root, "store")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, store_dir, bare_dir))

  git2r::init(bare_dir, bare = TRUE)
  repo <- git2r::init(repo_dir)
  git2r::config(repo, user.name = "Foreign Test", user.email = "foreign@test.com")
  writeLines("init", fs::path(repo_dir, "README.md"))
  fs::dir_create(fs::path(repo_dir, "R"))
  writeLines("original", fs::path(repo_dir, "R", "foo.R"))
  git2r::add(repo, c("README.md", "R/foo.R"))
  git2r::commit(repo, "Initial commit")
  git2r::remote_add(repo, name = "origin", url = as.character(bare_dir))
  git2r::push(repo, name = "origin", refspec = test_head_refspec(repo),
              set_upstream = TRUE)

  conn <- mock_datom_conn(list(), root = as.character(store_dir),
                          prefix = "proj")
  conn$backend <- "local"
  conn$role <- "developer"
  conn$path <- as.character(repo_dir)
  conn$project_name <- "foreign-project"

  write_product_config(repo_dir, "foreign-project", "product-a")

  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir, repo = repo)
}

# Every path in a commit's tree, recursively, as repo-relative strings.
fc_tree_paths <- function(repo, commit) {
  entries <- git2r::ls_tree(repo = repo, tree = git2r::tree(commit))
  paste0(entries$path, entries$name)
}

# The bytes a commit holds at one path -- not just whether the path is present.
# The path IS in the tree (it was committed earlier); the claim is that the
# WORKING-TREE EDIT to it is not.
fc_tree_content <- function(repo, commit, path) {
  entries <- git2r::ls_tree(repo = repo, tree = git2r::tree(commit))
  row <- entries[paste0(entries$path, entries$name) == path, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop("fc_tree_content(): expected exactly one tree entry at ", path,
         ", found ", nrow(row), call. = FALSE)
  }
  # writeLines() ends lines with \r\n on Windows, and git2r::content() splits on
  # \n only, so a fixture line comes back as "edited\r" there -- unless git's
  # core.autocrlf is set, as on GitHub's Windows runners but not on CRAN's or
  # win-builder's. These tests assert which version was committed, not its line
  # endings, so drop the \r.
  sub("\r$", "", git2r::content(git2r::lookup(repo, row$sha[[1L]])))
}

fc_head_commit <- function(repo) {
  git2r::revparse_single(repo, "HEAD")
}


# --- R14.1: machine-moment commits stage only datom-owned paths ---------------

test_that("a write's commit excludes an uncommitted edit to foreign code (AC16)", {
  skip_if_not_installed("git2r")
  skip_if_not_installed("arrow")

  fx <- local_foreign_project()
  foo <- fs::path(fx$repo_dir, "R", "foo.R")

  # A human edit in flight while the machine commits, which is the normal state
  # of a product repo mid-build rather than an exotic one.
  writeLines("edited", foo)

  suppressMessages(
    datom_write(fx$conn, data = data.frame(id = 1:3, val = letters[1:3]),
                name = "dm")
  )

  commit <- fc_head_commit(fx$repo)

  # The write's own files are there, so this is not vacuously passing on a
  # commit that staged nothing.
  expect_true(".datom/manifest.json" %in% fc_tree_paths(fx$repo, commit))
  expect_true("dm/metadata.json" %in% fc_tree_paths(fx$repo, commit))

  # The change is not in the tree: the committed blob still holds the version
  # from before the edit.
  expect_identical(fc_tree_content(fx$repo, commit, "R/foo.R"), "original")

  # And the edit is still in the working tree, unstaged. A write that cleaned it
  # up would satisfy the assertion above while losing the developer's work.
  status <- git2r::status(fx$repo)
  expect_true("R/foo.R" %in% unlist(status$unstaged, use.names = FALSE))
  expect_identical(readLines(foo), "edited")
})

test_that("a write leaves an untracked foreign file untracked (AC16)", {
  skip_if_not_installed("git2r")
  skip_if_not_installed("arrow")

  fx <- local_foreign_project()

  # Untracked rather than modified: `git add .` sweeps these in too, so the
  # add-all refactor R14.1 guards against shows up here as well.
  fs::dir_create(fs::path(fx$repo_dir, "dp"))
  writeLines("scratch", fs::path(fx$repo_dir, "dp", "notes.txt"))

  suppressMessages(
    datom_write(fx$conn, data = data.frame(id = 1:3), name = "dm")
  )

  expect_false("dp/notes.txt" %in% fc_tree_paths(fx$repo, fc_head_commit(fx$repo)))

  # git2r reports an untracked DIRECTORY rather than recursing into it, so the
  # entry to look for is `dp/`, not the file inside it.
  status <- git2r::status(fx$repo)
  expect_true("dp/" %in% unlist(status$untracked, use.names = FALSE))
  # Nothing left staged either: a staged-but-uncommitted foreign path is the
  # same defect one step earlier.
  expect_length(unlist(status$staged, use.names = FALSE), 0L)
})


# --- R14.2: datom operations tolerate non-datom paths -------------------------

test_that("a foreign directory without metadata.json is not a datom artifact (R14.2)", {
  skip_if_not_installed("git2r")
  skip_if_not_installed("arrow")

  fx <- local_foreign_project()

  suppressMessages(
    datom_write(fx$conn, data = data.frame(id = 1:3), name = "dm")
  )

  # `dp/` is deliberately not one of the seven names dropped by the hardcoded
  # exclusion list, so this exercises the `metadata.json` filter itself. It does
  # hold JSON, so a discovery rule that keyed off "contains any JSON" would be
  # caught here too.
  fs::dir_create(fs::path(fx$repo_dir, "dp", "config"))
  jsonlite::write_json(list(target = "adsl"),
                       fs::path(fx$repo_dir, "dp", "config", "build.json"))

  result <- suppressMessages(datom_validate(fx$conn))

  expect_true("dm" %in% result$tables$table)
  expect_false("dp" %in% result$tables$table)
  expect_true(result$valid)
})

test_that("a foreign file at the repo root is invisible to the repo-level checks (R14.2)", {
  skip_if_not_installed("git2r")
  skip_if_not_installed("arrow")

  fx <- local_foreign_project()

  suppressMessages(
    datom_write(fx$conn, data = data.frame(id = 1:3), name = "dm")
  )

  writeLines("all:", fs::path(fx$repo_dir, "Makefile"))
  writeLines("dpbuild", fs::path(fx$repo_dir, "DESCRIPTION"))

  result <- suppressMessages(datom_validate(fx$conn))

  # The repo-level half checks an explicit list of files datom expects, so a
  # foreign path is structurally invisible to it rather than filtered out of it.
  # Asserting the whole set, not just the absence of these two: a refactor into
  # a directory walk is what R14.2 forbids here, and it would surface every
  # foreign file at once.
  expect_setequal(result$repo_files$file, "manifest.json")
  expect_true(result$valid)
})

test_that("datom_status reports foreign dirty files as git state, not as a datom defect (R14.2)", {
  skip_if_not_installed("git2r")
  skip_if_not_installed("arrow")

  fx <- local_foreign_project()

  suppressMessages(
    datom_write(fx$conn, data = data.frame(id = 1:3), name = "dm")
  )

  writeLines("edited", fs::path(fx$repo_dir, "R", "foo.R"))
  fs::dir_create(fs::path(fx$repo_dir, "dp"))
  writeLines("scratch", fs::path(fx$repo_dir, "dp", "notes.txt"))

  status <- suppressMessages(datom_status(fx$conn))

  # Honest reporting of the repository is wanted: these really are uncommitted
  # changes. What R14.2 forbids is calling them a datom problem.
  expect_true("R/foo.R" %in% status$git$uncommitted)
  # `dp/` rather than the file inside it: git2r does not recurse into an
  # untracked directory, and this reports what git reports.
  expect_true("dp/" %in% status$git$uncommitted)

  # The artifact count is unaffected, and `datom_validate()` -- the verb that
  # does classify defects -- still reports a clean repo.
  expect_identical(status$tables$count, 1L)
  expect_true(suppressMessages(datom_validate(fx$conn))$valid)
})



# --- A commit of everything stops on a write that never committed (#155) ------
#
# Until #155 this test pinned the opposite: `datom_repo_commit(paths = NULL)`
# committed datom's files left by a write that stopped before its commit, beside
# the human's edit, and the repair then published what it could. That committed a
# version nobody published, half written. Now the commit stops before staging
# anything (requirements R3.5, D9), the human's edit stays as it was, and after
# `datom_validate(fix = TRUE)` puts datom's files back the same commit goes ahead
# with the human's edit only. The fixture is the same half-failed write.

test_that("datom_repo_commit(paths = NULL) stops on datom's own uncommitted files, and commits the human's edit after the repair", {
  skip_if_not_installed("git2r")
  skip_if_not_installed("arrow")

  fx <- local_foreign_project()

  # A write that got as far as the local metadata and no further: datom files
  # that git has never seen and storage has never received.
  meta <- list(
    schema_version = 2L, kind = "table", data_sha = strrep("a", 64L),
    hash_algo = "datom-cv1", table_type = "derived", nrow = 3L, ncol = 1L,
    colnames = "id", created_at = "2026-01-01T00:00:00Z",
    datom_version = "0.1.2", project = "foreign-project"
  )
  metadata_sha <- .datom_compute_metadata_sha(meta)
  suppressMessages(
    .datom_write_metadata_local(fx$conn, "dm", meta, metadata_sha)
  )

  # Both halves of the fixture, asserted before the verb runs.
  untracked_before <- unlist(git2r::status(fx$repo)$untracked, use.names = FALSE)
  expect_true("dm/" %in% untracked_before || "dm/metadata.json" %in% untracked_before)
  writeLines("edited", fs::path(fx$repo_dir, "R", "foo.R"))
  expect_true("R/foo.R" %in% unlist(git2r::status(fx$repo)$unstaged, use.names = FALSE))
  head_before <- fc_head_commit(fx$repo)

  expect_error(
    suppressMessages(datom_repo_commit(fx$conn, "Human commit", push = FALSE)),
    class = "datom_unfinished_work"
  )

  # Nothing staged, nothing committed, both halves as they were.
  expect_identical(fc_head_commit(fx$repo)$sha, head_before$sha)
  expect_length(unlist(git2r::status(fx$repo)$staged, use.names = FALSE), 0L)
  expect_true(fs::file_exists(fs::path(fx$repo_dir, "dm", "metadata.json")))
  expect_identical(readLines(fs::path(fx$repo_dir, "R", "foo.R")), "edited")

  # The way out the stop names: the repair discards the write's files and leaves
  # the human's edit alone.
  suppressWarnings(suppressMessages(datom_validate(fx$conn, fix = TRUE)))
  expect_false(fs::dir_exists(fs::path(fx$repo_dir, "dm")))
  expect_identical(readLines(fs::path(fx$repo_dir, "R", "foo.R")), "edited")

  suppressMessages(datom_repo_commit(fx$conn, "Human commit", push = FALSE))

  commit <- fc_head_commit(fx$repo)
  paths <- fc_tree_paths(fx$repo, commit)
  expect_false("dm/metadata.json" %in% paths)
  expect_false("dm/version_history.json" %in% paths)
  expect_identical(fc_tree_content(fx$repo, commit, "R/foo.R"), "edited")
})
