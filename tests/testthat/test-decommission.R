# Tests for R/decommission.R (Phase 15, Chunk 8)

# Helper: make a local-backend conn wired to temp dirs + a bare gov remote
make_decommission_env <- function(env = parent.frame()) {
  # Data storage root
  data_root <- withr::local_tempdir(.local_envir = env)

  # Local data clone (acts as the git repo)
  data_clone <- withr::local_tempdir(.local_envir = env)
  git2r::init(data_clone)
  data_repo <- git2r::repository(data_clone)
  git2r::config(data_repo, user.name = "test", user.email = "test@test.com")
  writeLines("", fs::path(data_clone, ".gitkeep"))
  git2r::add(data_repo, ".gitkeep")
  git2r::commit(data_repo, message = "init", author = git2r::default_signature(data_repo))

  # Gov bare remote + clone
  gov_bare <- withr::local_tempdir(.local_envir = env)
  git2r::init(gov_bare, bare = TRUE)

  gov_clone <- withr::local_tempdir(.local_envir = env)
  git2r::clone(gov_bare, gov_clone)
  gov_repo <- git2r::repository(gov_clone)
  git2r::config(gov_repo, user.name = "test", user.email = "test@test.com")
  writeLines("", fs::path(gov_clone, ".gitkeep"))
  git2r::add(gov_repo, ".gitkeep")
  git2r::commit(gov_repo, message = "init", author = git2r::default_signature(gov_repo))
  git2r::push(gov_repo, name = "origin",
               refspec = "refs/heads/master",
               credentials = NULL)

  # Gov storage root
  gov_root <- withr::local_tempdir(.local_envir = env)

  conn <- structure(
    list(
      project_name   = "test-proj",
      backend        = "local",
      root           = data_root,
      prefix         = NULL,
      region         = NULL,
      client         = NULL,
      path           = data_clone,
      role           = "developer",
      endpoint       = NULL,
      gov_root       = gov_root,
      gov_prefix     = NULL,
      gov_region     = NULL,
      gov_client     = NULL,
      gov_local_path = gov_clone
    ),
    class = "datom_conn"
  )

  list(
    conn      = conn,
    data_root = data_root,
    data_clone = data_clone,
    gov_clone = gov_clone,
    gov_root  = gov_root
  )
}

# =============================================================================
# datom_decommission() -- validation
# =============================================================================

test_that("datom_decommission() aborts on non-datom_conn input", {
  expect_error(datom_decommission(list()), "datom_conn")
})

test_that("datom_decommission() aborts for reader role", {
  conn <- structure(
    list(project_name = "p", role = "reader", backend = "local"),
    class = "datom_conn"
  )
  expect_error(datom_decommission(conn, confirm = "p"), "developer")
})

test_that("datom_decommission() aborts when confirm is NULL", {
  conn <- structure(
    list(project_name = "p", role = "developer", backend = "local"),
    class = "datom_conn"
  )
  expect_error(datom_decommission(conn, confirm = NULL), "Confirmation does not match")
})

test_that("datom_decommission() aborts when confirm is wrong string", {
  conn <- structure(
    list(project_name = "my-project", role = "developer", backend = "local"),
    class = "datom_conn"
  )
  expect_error(datom_decommission(conn, confirm = "wrong"), "Confirmation does not match")
})

test_that("datom_decommission() aborts when confirm differs by case", {
  conn <- structure(
    list(project_name = "My-Project", role = "developer", backend = "local"),
    class = "datom_conn"
  )
  expect_error(datom_decommission(conn, confirm = "my-project"), "Confirmation does not match")
})


# =============================================================================
# datom_decommission() -- storage deletion (local backend)
# =============================================================================

test_that("datom_decommission() deletes data storage objects", {
  e <- make_decommission_env()
  conn <- e$conn

  # Write a sentinel file into the data storage namespace
  sentinel <- fs::path(e$data_root, "datom", "tables", "abc.parquet")
  fs::dir_create(fs::path(e$data_root, "datom", "tables"))
  writeLines("data", sentinel)
  expect_true(fs::file_exists(sentinel))

  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  datom_decommission(conn, confirm = "test-proj")

  expect_false(fs::dir_exists(fs::path(e$data_root, "datom")))
})

test_that("datom_decommission() removes local data clone directory", {
  e <- make_decommission_env()
  conn <- e$conn

  expect_true(fs::dir_exists(e$data_clone))

  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  datom_decommission(conn, confirm = "test-proj")

  expect_false(fs::dir_exists(e$data_clone))
})


# =============================================================================
# datom_decommission() -- gov integration
# =============================================================================

test_that("datom_decommission() calls .datom_gov_unregister_project", {
  e <- make_decommission_env()
  conn <- e$conn

  called_with <- NULL
  local_mocked_bindings(
    .datom_gov_unregister_project = function(conn, project_name) {
      called_with <<- project_name
      invisible(TRUE)
    }
  )

  datom_decommission(conn, confirm = "test-proj")

  expect_equal(called_with, "test-proj")
})

test_that("datom_decommission() skips gov unregister when gov_local_path is NULL", {
  e <- make_decommission_env()
  conn <- e$conn
  conn$gov_local_path <- NULL

  unregister_called <- FALSE
  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) {
      unregister_called <<- TRUE
      invisible(TRUE)
    }
  )

  # Should succeed with a warning, not abort
  expect_no_error(datom_decommission(conn, confirm = "test-proj"))
  expect_false(unregister_called)
})

test_that("datom_decommission() deletes gov storage prefix", {
  e <- make_decommission_env()
  conn <- e$conn

  # Write a file in gov storage under projects/test-proj/
  proj_storage <- fs::path(e$gov_root, "datom", "projects", "test-proj")
  fs::dir_create(proj_storage)
  writeLines("{}", fs::path(proj_storage, "ref.json"))
  expect_true(fs::file_exists(fs::path(proj_storage, "ref.json")))

  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  datom_decommission(conn, confirm = "test-proj")

  expect_false(fs::dir_exists(proj_storage))
})

test_that("datom_decommission() leaves other projects in gov storage intact", {
  e <- make_decommission_env()
  conn <- e$conn

  # Write files for two projects in gov storage
  other_storage <- fs::path(e$gov_root, "datom", "projects", "other-proj")
  fs::dir_create(other_storage)
  writeLines("{}", fs::path(other_storage, "ref.json"))

  proj_storage <- fs::path(e$gov_root, "datom", "projects", "test-proj")
  fs::dir_create(proj_storage)
  writeLines("{}", fs::path(proj_storage, "ref.json"))

  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  datom_decommission(conn, confirm = "test-proj")

  # other-proj untouched
  expect_true(fs::file_exists(fs::path(other_storage, "ref.json")))
  # test-proj gone
  expect_false(fs::dir_exists(proj_storage))
})

test_that("datom_decommission() warns (not aborts) when gov unregister fails", {
  e <- make_decommission_env()
  conn <- e$conn

  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) {
      stop("gov push failed")
    }
  )

  # Should not throw; warns and continues
  expect_no_error(datom_decommission(conn, confirm = "test-proj"))
})

test_that("datom_decommission() returns invisible TRUE on success", {
  e <- make_decommission_env()

  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  result <- datom_decommission(e$conn, confirm = "test-proj")
  expect_true(result)
})


# =============================================================================
# .datom_local_delete_prefix()
# =============================================================================

test_that(".datom_local_delete_prefix() removes directory for given prefix_key", {
  root <- withr::local_tempdir()
  conn <- structure(
    list(backend = "local", root = root, prefix = "proj"),
    class = "datom_conn"
  )

  dir_path <- fs::path(root, "proj", "datom", "tables")
  fs::dir_create(dir_path)
  writeLines("x", fs::path(dir_path, "abc.parquet"))

  .datom_local_delete_prefix(conn, "tables")

  expect_false(fs::dir_exists(dir_path))
})

test_that(".datom_local_delete_prefix() is a no-op when directory missing", {
  root <- withr::local_tempdir()
  conn <- structure(
    list(backend = "local", root = root, prefix = "proj"),
    class = "datom_conn"
  )
  expect_no_error(.datom_local_delete_prefix(conn, "nonexistent"))
})

test_that(".datom_local_delete_prefix() with NULL prefix_key removes datom namespace root", {
  root <- withr::local_tempdir()
  conn <- structure(
    list(backend = "local", root = root, prefix = "proj"),
    class = "datom_conn"
  )

  # Create files inside the namespace
  ns <- fs::path(root, "proj", "datom")
  fs::dir_create(fs::path(ns, "tables"))
  writeLines("x", fs::path(ns, "tables", "f.parquet"))

  .datom_local_delete_prefix(conn, NULL)

  expect_false(fs::dir_exists(ns))
})

test_that(".datom_local_delete_prefix() with NULL prefix_key and no prefix on conn", {
  root <- withr::local_tempdir()
  conn <- structure(
    list(backend = "local", root = root, prefix = NULL),
    class = "datom_conn"
  )

  ns <- fs::path(root, "datom")
  fs::dir_create(fs::path(ns, "tables"))
  writeLines("x", fs::path(ns, "tables", "f.parquet"))

  .datom_local_delete_prefix(conn, NULL)

  expect_false(fs::dir_exists(ns))
})


# =============================================================================
# .datom_storage_delete_prefix() -- dispatch
# =============================================================================

test_that(".datom_storage_delete_prefix() dispatches to local backend", {
  root <- withr::local_tempdir()
  conn <- structure(
    list(backend = "local", root = root, prefix = "p"),
    class = "datom_conn"
  )

  dir_path <- fs::path(root, "p", "datom", "things")
  fs::dir_create(dir_path)
  writeLines("x", fs::path(dir_path, "f.txt"))

  .datom_storage_delete_prefix(conn, "things")
  expect_false(fs::dir_exists(dir_path))
})

test_that(".datom_storage_delete_prefix() aborts on unsupported backend", {
  conn <- structure(
    list(backend = "gcs", root = "bucket", prefix = NULL),
    class = "datom_conn"
  )
  expect_error(.datom_storage_delete_prefix(conn, "key"), "Unsupported storage backend")
})
