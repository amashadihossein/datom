# Tests for R/utils-gov.R (Phase 15, Chunks 2 & 3)

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


# =============================================================================
# GOV_SEAM write helpers — shared setup
# =============================================================================

# Helper: make a bare remote + clone and a mock conn pointing at the clone
make_gov_env <- function(env = parent.frame()) {
  bare_dir <- withr::local_tempdir(.local_envir = env)
  git2r::init(bare_dir, bare = TRUE)

  clone_dir <- withr::local_tempdir(.local_envir = env)
  git2r::clone(bare_dir, clone_dir)

  # Seed an initial commit so the clone has a branch to push to
  dummy <- fs::path(clone_dir, ".gitkeep")
  writeLines("", dummy)
  repo <- git2r::repository(clone_dir)
  git2r::config(repo, user.name = "test", user.email = "test@test.com")
  git2r::add(repo, ".gitkeep")
  git2r::commit(repo, message = "init", author = git2r::default_signature(repo))
  git2r::push(repo, name = "origin",
               refspec = "refs/heads/master",
               credentials = NULL)

  # A minimal conn object
  conn <- structure(
    list(
      project_name = "test-project",
      backend = "local",
      root = withr::local_tempdir(.local_envir = env),
      prefix = NULL,
      region = NULL,
      client = NULL,
      path = withr::local_tempdir(.local_envir = env),
      role = "developer",
      endpoint = NULL,
      gov_root = withr::local_tempdir(.local_envir = env),
      gov_prefix = NULL,
      gov_region = NULL,
      gov_client = NULL,
      gov_local_path = clone_dir
    ),
    class = "datom_conn"
  )

  list(bare_dir = bare_dir, clone_dir = clone_dir, conn = conn)
}


# =============================================================================
# .datom_gov_commit() / .datom_gov_push() / .datom_gov_pull()
# =============================================================================

test_that(".datom_gov_commit() creates a commit on the gov clone", {
  env <- make_gov_env()

  fs::dir_create(fs::path(env$clone_dir, "projects", "proj"))
  writeLines("{}", fs::path(env$clone_dir, "projects", "proj", "dispatch.json"))

  sha <- .datom_gov_commit(env$conn, "projects/proj/dispatch.json", "test commit")

  expect_type(sha, "character")
  expect_equal(nchar(sha), 40L)
  repo <- git2r::repository(env$clone_dir)
  log <- git2r::commits(repo)
  expect_match(log[[1]]$message, "test commit")
})

test_that(".datom_gov_commit() aborts when conn has no gov_local_path", {
  conn <- structure(list(gov_local_path = NULL), class = "datom_conn")
  expect_error(.datom_gov_commit(conn, "a.json", "msg"), "gov_local_path")
})

test_that(".datom_gov_push() pushes to the bare remote", {
  env <- make_gov_env()

  # Write + commit a file on clone
  fs::dir_create(fs::path(env$clone_dir, "projects", "p"))
  writeLines("{}", fs::path(env$clone_dir, "projects", "p", "ref.json"))
  repo <- git2r::repository(env$clone_dir)
  git2r::add(repo, "projects/p/ref.json")
  git2r::commit(repo, message = "add ref", author = git2r::default_signature(repo))

  expect_no_error(.datom_gov_push(env$conn))

  bare_repo <- git2r::repository(env$bare_dir)
  bare_log <- git2r::commits(bare_repo)
  expect_match(bare_log[[1]]$message, "add ref")
})

test_that(".datom_gov_push() aborts when conn has no gov_local_path", {
  conn <- structure(list(gov_local_path = NULL), class = "datom_conn")
  expect_error(.datom_gov_push(conn), "gov_local_path")
})

test_that(".datom_gov_pull() succeeds on an up-to-date clone", {
  env <- make_gov_env()
  expect_no_error(.datom_gov_pull(env$conn))
})

test_that(".datom_gov_pull() aborts when conn has no gov_local_path", {
  conn <- structure(list(gov_local_path = NULL), class = "datom_conn")
  expect_error(.datom_gov_pull(conn), "gov_local_path")
})


# =============================================================================
# .datom_gov_register_project()
# =============================================================================

test_that(".datom_gov_register_project() creates files and commits", {
  env <- make_gov_env()

  dispatch <- list(methods = list(r = list(default = "datom::datom_read")))
  ref <- list(current = list(root = "my-bucket", prefix = "proj/", region = "us-east-1"),
               previous = list())

  local_mocked_bindings(
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_gov_conn = function(conn) conn
  )

  .datom_gov_register_project(env$conn, "my-study", dispatch, ref)

  project_dir <- fs::path(env$clone_dir, "projects", "my-study")
  expect_true(fs::file_exists(fs::path(project_dir, "dispatch.json")))
  expect_true(fs::file_exists(fs::path(project_dir, "ref.json")))
  expect_true(fs::file_exists(fs::path(project_dir, "migration_history.json")))

  repo <- git2r::repository(env$clone_dir)
  log <- git2r::commits(repo)
  expect_match(log[[1]]$message, "Register project my-study")
})

test_that(".datom_gov_register_project() migration_history.json is empty array", {
  env <- make_gov_env()

  local_mocked_bindings(
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_gov_conn = function(conn) conn
  )

  .datom_gov_register_project(
    env$conn, "proj",
    dispatch = list(methods = list()),
    ref = list(current = list(root = "b", prefix = NULL, region = "us-east-1"), previous = list())
  )

  history_file <- fs::path(env$clone_dir, "projects", "proj", "migration_history.json")
  history <- jsonlite::read_json(history_file)
  expect_equal(length(history), 0L)
})

test_that(".datom_gov_register_project() aborts when project already registered", {
  env <- make_gov_env()
  fs::dir_create(fs::path(env$clone_dir, "projects", "already-there"))

  local_mocked_bindings(
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_gov_conn = function(conn) conn
  )

  expect_error(
    .datom_gov_register_project(
      env$conn, "already-there",
      dispatch = list(), ref = list()
    ),
    "already registered"
  )
})

test_that(".datom_gov_register_project() writes all three files to gov storage", {
  env <- make_gov_env()
  keys_written <- character()

  local_mocked_bindings(
    .datom_storage_write_json = function(conn, key, data) {
      keys_written <<- c(keys_written, key)
      invisible(TRUE)
    },
    .datom_gov_conn = function(conn) conn
  )

  .datom_gov_register_project(
    env$conn, "my-proj",
    dispatch = list(methods = list()),
    ref = list(current = list(root = "b", prefix = NULL, region = "us-east-1"), previous = list())
  )

  expect_true("projects/my-proj/dispatch.json" %in% keys_written)
  expect_true("projects/my-proj/ref.json" %in% keys_written)
  expect_true("projects/my-proj/migration_history.json" %in% keys_written)
})


# =============================================================================
# .datom_gov_unregister_project()
# =============================================================================

test_that(".datom_gov_unregister_project() removes project dir and commits", {
  env <- make_gov_env()

  # First register so there's something to remove
  local_mocked_bindings(
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_gov_conn = function(conn) conn
  )
  .datom_gov_register_project(
    env$conn, "my-proj",
    dispatch = list(methods = list()),
    ref = list(current = list(root = "b", prefix = NULL, region = "us-east-1"), previous = list())
  )

  expect_true(fs::dir_exists(fs::path(env$clone_dir, "projects", "my-proj")))

  .datom_gov_unregister_project(env$conn, "my-proj")

  expect_false(fs::dir_exists(fs::path(env$clone_dir, "projects", "my-proj")))

  repo <- git2r::repository(env$clone_dir)
  log <- git2r::commits(repo)
  expect_match(log[[1]]$message, "Unregister project my-proj")
})

test_that(".datom_gov_unregister_project() aborts when project not registered", {
  env <- make_gov_env()
  expect_error(
    .datom_gov_unregister_project(env$conn, "nonexistent"),
    "not registered"
  )
})


# =============================================================================
# .datom_gov_record_migration()
# =============================================================================

test_that(".datom_gov_record_migration() appends event to migration_history.json", {
  env <- make_gov_env()

  local_mocked_bindings(
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_gov_conn = function(conn) conn
  )

  # Register project first
  .datom_gov_register_project(
    env$conn, "my-proj",
    dispatch = list(methods = list()),
    ref = list(current = list(root = "b", prefix = NULL, region = "us-east-1"), previous = list())
  )

  event <- list(event_type = "data_migration", details = list(from = "old-bucket"))
  .datom_gov_record_migration(env$conn, "my-proj", event)

  history_file <- fs::path(env$clone_dir, "projects", "my-proj", "migration_history.json")
  history <- jsonlite::read_json(history_file, simplifyVector = FALSE)
  expect_equal(length(history), 1L)
  expect_equal(history[[1]]$event_type, "data_migration")
})

test_that(".datom_gov_record_migration() auto-adds occurred_at", {
  env <- make_gov_env()

  local_mocked_bindings(
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_gov_conn = function(conn) conn
  )

  .datom_gov_register_project(
    env$conn, "my-proj",
    dispatch = list(methods = list()),
    ref = list(current = list(root = "b", prefix = NULL, region = "us-east-1"), previous = list())
  )

  event <- list(event_type = "test")
  .datom_gov_record_migration(env$conn, "my-proj", event)

  history_file <- fs::path(env$clone_dir, "projects", "my-proj", "migration_history.json")
  history <- jsonlite::read_json(history_file, simplifyVector = FALSE)
  expect_false(is.null(history[[1]]$occurred_at))
})

test_that(".datom_gov_record_migration() prepends (most recent first)", {
  env <- make_gov_env()

  local_mocked_bindings(
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_gov_conn = function(conn) conn
  )

  .datom_gov_register_project(
    env$conn, "p",
    dispatch = list(methods = list()),
    ref = list(current = list(root = "b", prefix = NULL, region = "us-east-1"), previous = list())
  )

  .datom_gov_record_migration(env$conn, "p", list(event_type = "first"))
  .datom_gov_record_migration(env$conn, "p", list(event_type = "second"))

  history_file <- fs::path(env$clone_dir, "projects", "p", "migration_history.json")
  history <- jsonlite::read_json(history_file, simplifyVector = FALSE)
  expect_equal(history[[1]]$event_type, "second")
  expect_equal(history[[2]]$event_type, "first")
})


# =============================================================================
# .datom_gov_destroy()
# =============================================================================

test_that(".datom_gov_destroy() removes local gov clone when no projects", {
  clone_dir <- withr::local_tempdir()
  git2r::init(clone_dir)

  result <- .datom_gov_destroy(clone_dir)

  expect_false(fs::dir_exists(clone_dir))
  expect_equal(result, character(0))
})

test_that(".datom_gov_destroy() aborts when projects registered and force = FALSE", {
  clone_dir <- withr::local_tempdir()
  git2r::init(clone_dir)
  fs::dir_create(fs::path(clone_dir, "projects", "my-study"))

  expect_error(
    .datom_gov_destroy(clone_dir, force = FALSE),
    "registered"
  )
  expect_true(fs::dir_exists(clone_dir))
})

test_that(".datom_gov_destroy() succeeds with registered projects when force = TRUE", {
  clone_dir <- withr::local_tempdir()
  git2r::init(clone_dir)
  fs::dir_create(fs::path(clone_dir, "projects", "my-study"))

  result <- .datom_gov_destroy(clone_dir, force = TRUE)

  expect_false(fs::dir_exists(clone_dir))
  expect_equal(result, "my-study")
})

test_that(".datom_gov_destroy() returns registered project names", {
  clone_dir <- withr::local_tempdir()
  git2r::init(clone_dir)
  fs::dir_create(fs::path(clone_dir, "projects", "proj-a"))
  fs::dir_create(fs::path(clone_dir, "projects", "proj-b"))

  result <- .datom_gov_destroy(clone_dir, force = TRUE)

  expect_setequal(result, c("proj-a", "proj-b"))
})

test_that(".datom_gov_destroy() is a no-op when clone does not exist", {
  result <- .datom_gov_destroy("/nonexistent/gov-clone")
  expect_equal(result, character(0))
})
