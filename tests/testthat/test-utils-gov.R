# Tests for R/utils-gov.R (Phase 15, Chunk 2)

# =============================================================================
# .datom_gov_clone_exists()
# =============================================================================

test_that(".datom_gov_clone_exists() returns FALSE for non-existent path", {
  expect_false(.datom_gov_clone_exists("/nonexistent/path/xyz"))
})

test_that(".datom_gov_clone_exists() returns FALSE for directory without .git", {
  dir <- withr::local_tempdir()
  expect_false(.datom_gov_clone_exists(dir))
})

test_that(".datom_gov_clone_exists() returns TRUE for a git repo", {
  dir <- withr::local_tempdir()
  git2r::init(dir)
  expect_true(.datom_gov_clone_exists(dir))
})

test_that(".datom_gov_clone_exists() returns FALSE for NULL or non-string", {
  expect_false(.datom_gov_clone_exists(NULL))
  expect_false(.datom_gov_clone_exists(123))
  expect_false(.datom_gov_clone_exists(c("a", "b")))
})


# =============================================================================
# .datom_gov_clone_open()
# =============================================================================

test_that(".datom_gov_clone_open() opens a valid git repo", {
  dir <- withr::local_tempdir()
  git2r::init(dir)
  repo <- .datom_gov_clone_open(dir)
  expect_true(inherits(repo, "git_repository"))
})

test_that(".datom_gov_clone_open() aborts when path is not a git repo", {
  dir <- withr::local_tempdir()
  expect_error(
    .datom_gov_clone_open(dir),
    "Gov clone not found"
  )
})

test_that(".datom_gov_clone_open() aborts when path does not exist", {
  expect_error(
    .datom_gov_clone_open("/nonexistent/path"),
    "Gov clone not found"
  )
})


# =============================================================================
# .datom_gov_validate_remote()
# =============================================================================

test_that(".datom_gov_validate_remote() passes when remote matches", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  clone_dir <- withr::local_tempdir()
  git2r::clone(bare_dir, clone_dir)

  expect_invisible(.datom_gov_validate_remote(clone_dir, bare_dir))
})

test_that(".datom_gov_validate_remote() passes when .git suffix difference", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  clone_dir <- withr::local_tempdir()
  git2r::clone(bare_dir, clone_dir)

  # Adding .git to the expected URL should still match (normalisation)
  expected_with_git <- paste0(bare_dir, ".git")

  # git2r sets the remote to bare_dir exactly, so .git-suffix is stripped on
  # the expected side during normalisation. This test validates the strip logic.
  # When they'd match after stripping, no error should be raised.
  # (bare_dir without .git == paste0(bare_dir, ".git") stripped == bare_dir)
  # So both sides normalise to bare_dir.
  expect_error(
    .datom_gov_validate_remote(clone_dir, expected_with_git),
    NA   # expect NO error
  )
})

test_that(".datom_gov_validate_remote() aborts on remote URL mismatch", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  clone_dir <- withr::local_tempdir()
  git2r::clone(bare_dir, clone_dir)

  expect_error(
    .datom_gov_validate_remote(clone_dir, "https://github.com/org/other-repo.git"),
    "different remote URL"
  )
})

test_that(".datom_gov_validate_remote() aborts when no remote configured", {
  dir <- withr::local_tempdir()
  git2r::init(dir)
  # No remote added
  expect_error(
    .datom_gov_validate_remote(dir, "https://github.com/org/gov.git"),
    "no remote"
  )
})


# =============================================================================
# .datom_gov_clone_init()
# =============================================================================

test_that(".datom_gov_clone_init() clones when path does not exist", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  # Use a non-existent subdirectory as target
  clone_dir <- fs::path(withr::local_tempdir(), "gov-clone")
  expect_false(fs::dir_exists(clone_dir))

  result <- .datom_gov_clone_init(bare_dir, clone_dir)

  expect_true(fs::dir_exists(clone_dir))
  expect_true(.datom_gov_clone_exists(clone_dir))
  expect_equal(as.character(result), as.character(clone_dir))
})

test_that(".datom_gov_clone_init() is idempotent when clone already exists with matching URL", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  clone_dir <- withr::local_tempdir()
  git2r::clone(bare_dir, clone_dir)

  # Second call should succeed silently
  expect_no_error(.datom_gov_clone_init(bare_dir, clone_dir))
})

test_that(".datom_gov_clone_init() aborts when path exists with different remote URL", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  clone_dir <- withr::local_tempdir()
  git2r::clone(bare_dir, clone_dir)

  expect_error(
    .datom_gov_clone_init("https://github.com/other/repo.git", clone_dir),
    "different remote URL"
  )
})

test_that(".datom_gov_clone_init() aborts when path exists but is not a git repo", {
  non_git_dir <- withr::local_tempdir()
  # Create a non-empty non-git directory
  writeLines("something", fs::path(non_git_dir, "file.txt"))

  expect_error(
    .datom_gov_clone_init("https://github.com/org/gov.git", non_git_dir),
    "not a git repository"
  )
})

test_that(".datom_gov_clone_init() returns invisible gov_local_path", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)

  clone_dir <- withr::local_tempdir()
  git2r::clone(bare_dir, clone_dir)

  result <- withVisible(.datom_gov_clone_init(bare_dir, clone_dir))
  expect_false(result$visible)
  expect_equal(as.character(result$value), as.character(clone_dir))
})


# =============================================================================
# .datom_gov_project_path()
# =============================================================================

test_that(".datom_gov_project_path() returns correct path", {
  result <- .datom_gov_project_path("/gov/clone", "clinical-data")
  expect_equal(as.character(result), "/gov/clone/projects/clinical-data")
})

test_that(".datom_gov_project_path() handles project names with underscores", {
  result <- .datom_gov_project_path("/gov", "my_study_001")
  expect_equal(as.character(result), "/gov/projects/my_study_001")
})


# =============================================================================
# new_datom_conn() — gov_local_path field
# =============================================================================

test_that("new_datom_conn() stores gov_local_path when provided", {
  dir <- withr::local_tempdir()
  conn <- new_datom_conn(
    project_name = "proj",
    root = "bucket",
    region = "us-east-1",
    client = list(),
    path = dir,
    role = "developer",
    gov_local_path = "/gov/acme-gov"
  )
  expect_equal(conn$gov_local_path, "/gov/acme-gov")
})

test_that("new_datom_conn() gov_local_path defaults to NULL", {
  conn <- new_datom_conn(
    project_name = "proj",
    root = "bucket",
    region = "us-east-1",
    client = list(),
    role = "reader"
  )
  expect_null(conn$gov_local_path)
})

test_that("new_datom_conn() aborts on invalid gov_local_path types", {
  for (bad in list(123, NA_character_, "", c("a", "b"))) {
    expect_error(
      new_datom_conn(
        project_name = "proj",
        root = "bucket",
        region = "us-east-1",
        client = list(),
        role = "reader",
        gov_local_path = bad
      ),
      "gov_local_path"
    )
  }
})
