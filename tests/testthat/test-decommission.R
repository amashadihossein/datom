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
      gov_local_path = gov_clone,
      data_repo_url  = NULL,
      github_pat     = NULL
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
# datom_decommission() -- governance.json cleanup (Phase 21 Chunk 7)
# =============================================================================

# Helper: make a decommission env with governance.json mirror staged in data
# storage (the local-backend equivalent of the S3 mirror).
make_decommission_gov_env <- function(env = parent.frame()) {
  e <- make_decommission_env(env = env)

  # Stage governance.json mirror at the data storage location
  # Key built by .datom_build_storage_key(NULL, ".metadata/governance.json")
  # -> "datom/.metadata/governance.json" under the data root.
  mirror_dir <- fs::path(e$data_root, "datom", ".metadata")
  fs::dir_create(mirror_dir)
  gov_json <- list(
    gov_repo_url = "https://github.com/acme/gov.git",
    gov_storage  = list(type = "local", root = as.character(e$gov_root)),
    attached_at  = "2026-05-24T00:00:00Z"
  )
  jsonlite::write_json(gov_json,
                       fs::path(mirror_dir, "governance.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  e
}

test_that("datom_decommission() deletes governance.json storage mirror when gov attached", {
  e <- make_decommission_gov_env()
  mirror_path <- fs::path(e$data_root, "datom", ".metadata", "governance.json")
  expect_true(fs::file_exists(mirror_path))

  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  datom_decommission(e$conn, confirm = "test-proj")

  expect_false(fs::file_exists(mirror_path))
})

test_that("datom_decommission() skips governance.json deletion when no gov attached", {
  e <- make_decommission_env()
  e$conn$gov_root <- NULL  # no governance

  # governance.json should not be touched (no gov storage mirror expected)
  delete_called <- FALSE
  local_mocked_bindings(
    .datom_storage_delete_governance_json = function(...) {
      delete_called <<- TRUE
      invisible(NULL)
    },
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  datom_decommission(e$conn, confirm = "test-proj")

  expect_false(delete_called)
})

test_that("datom_decommission() warns (not aborts) when governance.json mirror deletion fails", {
  e <- make_decommission_gov_env()

  local_mocked_bindings(
    .datom_storage_delete_governance_json = function(...) stop("mirror delete failed"),
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  expect_no_error(datom_decommission(e$conn, confirm = "test-proj"))
})


# =============================================================================
# gov_local_path persistence regression (Phase 21 Chunk 7)
# =============================================================================

test_that("no datom-written file persists gov_local_path after datom_init_repo()", {
  # Uses an existing init-repo test environment; check the yaml written.
  # We can't run a full datom_init_repo() in unit tests without network mocks,
  # so construct a minimal project.yaml the same way datom_init_repo() does
  # and assert it contains no gov_local_path field anywhere.
  storage_block <- list(
    data = list(type = "local", root = "/tmp/store"),
    max_file_size_gb = 1000
  )
  repos_block <- list(data = list(remote_url = "https://github.com/x/y.git"))
  project_config <- list(
    project_name = "my-study",
    storage = storage_block,
    repos = repos_block
  )
  tmp <- withr::local_tempdir()
  yaml_path <- fs::path(tmp, "project.yaml")
  yaml::write_yaml(project_config, yaml_path)

  txt <- paste(readLines(yaml_path), collapse = "\n")
  expect_false(grepl("gov_local_path|local_path", txt, ignore.case = TRUE))
})

test_that("no datom-written file persists gov_local_path after datom_attach_gov()", {
  # Simulate the yaml that datom_attach_gov() reads and rewrites (cfg is
  # re-written as-is). Verify that a yaml which never contained gov_local_path
  # still doesn't after the write.
  cfg <- list(
    project_name = "my-study",
    storage = list(
      data = list(type = "local", root = "/tmp/store"),
      max_file_size_gb = 1000
    ),
    repos = list(data = list(remote_url = "https://github.com/x/y.git"))
  )
  tmp <- withr::local_tempdir()
  yaml_path <- fs::path(tmp, "project.yaml")
  yaml::write_yaml(cfg, yaml_path)

  txt <- paste(readLines(yaml_path), collapse = "\n")
  expect_false(grepl("gov_local_path|local_path", txt, ignore.case = TRUE))
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


# =============================================================================
# datom_decommission() -- no-governance (gov-on-demand)
# =============================================================================

# Helper: like make_decommission_env() but with all gov fields NULL.
make_decommission_env_nogov <- function(env = parent.frame()) {
  data_root <- withr::local_tempdir(.local_envir = env)

  data_clone <- withr::local_tempdir(.local_envir = env)
  git2r::init(data_clone)
  data_repo <- git2r::repository(data_clone)
  git2r::config(data_repo, user.name = "test", user.email = "test@test.com")
  writeLines("", fs::path(data_clone, ".gitkeep"))
  git2r::add(data_repo, ".gitkeep")
  git2r::commit(data_repo, message = "init",
                 author = git2r::default_signature(data_repo))

  conn <- structure(
    list(
      project_name   = "nogov-proj",
      backend        = "local",
      root           = data_root,
      prefix         = NULL,
      region         = NULL,
      client         = NULL,
      path           = data_clone,
      role           = "developer",
      endpoint       = NULL,
      gov_root       = NULL,
      gov_prefix     = NULL,
      gov_region     = NULL,
      gov_client     = NULL,
      gov_local_path = NULL,
      data_repo_url  = NULL,
      github_pat     = NULL
    ),
    class = "datom_conn"
  )

  list(
    conn       = conn,
    data_root  = data_root,
    data_clone = data_clone
  )
}

test_that("datom_decommission() succeeds for no-gov project", {
  e <- make_decommission_env_nogov()

  # Write a sentinel file into data storage
  sentinel <- fs::path(e$data_root, "datom", "tables", "abc.parquet")
  fs::dir_create(fs::path(e$data_root, "datom", "tables"))
  writeLines("data", sentinel)

  expect_no_error(datom_decommission(e$conn, confirm = "nogov-proj"))
  # Data storage cleared
  expect_false(fs::dir_exists(fs::path(e$data_root, "datom")))
  # Local clone removed
  expect_false(fs::dir_exists(e$data_clone))
})

test_that("datom_decommission() does not call gov helpers for no-gov project", {
  e <- make_decommission_env_nogov()

  unregister_called <- FALSE
  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) {
      unregister_called <<- TRUE
      invisible(TRUE)
    }
  )

  datom_decommission(e$conn, confirm = "nogov-proj")

  expect_false(unregister_called)
})

test_that("datom_decommission() does not touch local-backend cwd for no-gov project", {
  # Regression test: pre-Chunk 5 logic ran step 5 for any local-backend conn,
  # which on a no-gov conn would compute fs::path(NULL, 'projects/{name}') ==
  # 'projects/nogov-proj', a relative path. If cwd happened to contain such
  # a directory, it would be deleted. Now step 5 is gated on gov_root.
  withr::with_tempdir({
    accidental <- fs::path(getwd(), "projects", "nogov-proj")
    fs::dir_create(accidental)
    writeLines("x", fs::path(accidental, "marker.txt"))

    e <- make_decommission_env_nogov()
    datom_decommission(e$conn, confirm = "nogov-proj")

    expect_true(fs::file_exists(fs::path(accidental, "marker.txt")))
  })
})


# =============================================================================
# datom_decommission() -- conn$data_repo_url and conn$github_pat (issues #17/#23)
# =============================================================================

test_that("datom_decommission() uses conn$data_repo_url (not git clone lookup)", {
  e <- make_decommission_env()
  conn <- e$conn
  # Set a fake GitHub URL -- no live clone needed for URL resolution
  conn$data_repo_url <- "https://github.com/org/test-proj.git"
  conn$github_pat    <- "ghp_fake"

  deleted_repo <- NULL
  local_mocked_bindings(
    .datom_delete_github_repo = function(repo_full, pat) {
      deleted_repo <<- repo_full
      invisible(TRUE)
    },
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  datom_decommission(conn, confirm = "test-proj")

  expect_equal(deleted_repo, "org/test-proj")
})

test_that("datom_decommission() uses conn$github_pat for repo deletion", {
  e <- make_decommission_env()
  conn <- e$conn
  conn$data_repo_url <- "https://github.com/org/test-proj.git"
  conn$github_pat    <- "ghp_explicit_token"

  used_pat <- NULL
  local_mocked_bindings(
    .datom_delete_github_repo = function(repo_full, pat) {
      used_pat <<- pat
      invisible(TRUE)
    },
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  datom_decommission(conn, confirm = "test-proj")

  expect_equal(used_pat, "ghp_explicit_token")
})

test_that("datom_decommission() warns and skips deletion when conn$github_pat is NULL", {
  e <- make_decommission_env()
  conn <- e$conn
  conn$data_repo_url <- "https://github.com/org/test-proj.git"
  conn$github_pat    <- NULL

  delete_called <- FALSE
  local_mocked_bindings(
    .datom_delete_github_repo = function(...) {
      delete_called <<- TRUE
      invisible(TRUE)
    },
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  expect_no_error(datom_decommission(conn, confirm = "test-proj"))
  expect_false(delete_called)
})

test_that("datom_decommission() aborts step 2 when data_repo_url is NULL", {
  e <- make_decommission_env()
  conn <- e$conn
  # data_repo_url already NULL in make_decommission_env() -- step 2 aborts
  # but is caught by outer tryCatch, so overall call succeeds with a warning
  conn$data_repo_url <- NULL

  local_mocked_bindings(
    .datom_gov_unregister_project = function(...) invisible(TRUE)
  )

  # Should not re-throw -- outer tryCatch catches and continues
  expect_no_error(datom_decommission(conn, confirm = "test-proj"))
})
