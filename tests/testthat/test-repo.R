# Tests for datom_repo_set_data_store() (R/repo.R)
# Phase 22, Chunk 4

# --- helpers ------------------------------------------------------------------

make_dev_conn <- function(path, gov_root = NULL) {
  structure(
    list(
      project_name  = "TEST_PROJECT",
      backend       = "local",
      root          = as.character(path),
      prefix        = "proj",
      region        = NULL,
      client        = NULL,
      path          = as.character(path),
      role          = "developer",
      endpoint      = NULL,
      gov_root      = gov_root,
      gov_client    = NULL,
      gov_local_path = NULL,
      github_pat    = NULL,
      data_repo_url = NULL
    ),
    class = "datom_conn"
  )
}

seed_git_repo <- function(path) {
  .datom_check_git2r()
  repo <- git2r::init(path)
  git2r::config(repo, user.name = "Test User", user.email = "test@example.com")
  repo
}

write_project_yaml <- function(path, extra_storage = NULL) {
  cfg <- list(
    project_name = "TEST_PROJECT",
    datom_version = "0.1.0",
    storage = c(
      list(
        data = list(
          type   = "local",
          root   = as.character(fs::path(path, "data-store")),
          prefix = "proj"
        )
      ),
      extra_storage %||% list()
    ),
    repos = list(data = list(remote_url = "https://example.com/repo.git"))
  )
  fs::dir_create(fs::path(path, ".datom"))
  yaml::write_yaml(cfg, fs::path(path, ".datom", "project.yaml"))
}


# === Input validation =========================================================

test_that("datom_repo_set_data_store() errors on non-conn", {
  store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
  expect_error(datom_repo_set_data_store("not-conn", store), "datom_conn")
  expect_error(datom_repo_set_data_store(NULL, store),       "datom_conn")
})

test_that("datom_repo_set_data_store() errors on reader role", {
  conn <- structure(
    list(role = "reader", path = "/tmp", project_name = "X", gov_root = NULL),
    class = "datom_conn"
  )
  store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
  expect_error(datom_repo_set_data_store(conn, store), "developer")
})

test_that("datom_repo_set_data_store() errors when conn has no path", {
  conn <- structure(
    list(role = "developer", path = NULL, project_name = "X", gov_root = NULL),
    class = "datom_conn"
  )
  store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
  expect_error(datom_repo_set_data_store(conn, store), "path")
})

test_that("datom_repo_set_data_store() errors on invalid new_store", {
  withr::with_tempdir({
    conn <- make_dev_conn(getwd())
    expect_error(datom_repo_set_data_store(conn, list(type = "s3")), "datom_store_s3")
    expect_error(datom_repo_set_data_store(conn, "not-a-store"),     "datom_store_s3")
  })
})

test_that("datom_repo_set_data_store() errors when project.yaml missing", {
  withr::with_tempdir({
    # .datom dir does not exist
    conn  <- make_dev_conn(getwd())
    store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
    expect_error(datom_repo_set_data_store(conn, store), "project.yaml")
  })
})


# === Core behaviour: local store replacement ==================================

test_that("datom_repo_set_data_store() rewrites storage.data with local store", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)
    write_project_yaml(repo_path)

    # Stage + commit initial project.yaml so git status is clean
    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    new_dir   <- fs::dir_create("new-store")
    new_store <- datom_store_local(new_dir, prefix = "new-prefix", validate = FALSE)
    conn      <- make_dev_conn(repo_path)

    # Stub push so it doesn't need a real remote
    mockery::stub(datom_repo_set_data_store, ".datom_git_push", invisible(TRUE))

    sha <- datom_repo_set_data_store(conn, new_store)

    expect_type(sha, "character")
    expect_true(nzchar(sha))

    # Read back yaml and verify only storage.data changed
    updated <- yaml::read_yaml(fs::path(repo_path, ".datom", "project.yaml"))
    expect_equal(updated$storage$data$type,   "local")
    expect_equal(updated$storage$data$root,   new_store$path)  # abs path from datom_store_local
    expect_equal(updated$storage$data$prefix, "new-prefix")
    # Other top-level fields untouched
    expect_equal(updated$project_name, "TEST_PROJECT")
    expect_equal(updated$repos$data$remote_url, "https://example.com/repo.git")
  })
})

test_that("datom_repo_set_data_store() storage.governance is untouched", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)

    # Write a project.yaml that includes a governance block
    cfg <- list(
      project_name = "GOV_PROJECT",
      datom_version = "0.1.0",
      storage = list(
        data = list(
          type   = "local",
          root   = "/old/path",
          prefix = "old-prefix"
        ),
        governance = list(
          type   = "s3",
          bucket = "gov-bucket",
          prefix = "gov-prefix",
          region = "us-east-1"
        )
      ),
      repos = list(data = list(remote_url = "https://example.com/repo.git"))
    )
    fs::dir_create(fs::path(repo_path, ".datom"))
    yaml::write_yaml(cfg, fs::path(repo_path, ".datom", "project.yaml"))

    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    new_dir   <- fs::dir_create("new-store")
    new_store <- datom_store_local(new_dir, validate = FALSE)
    conn      <- make_dev_conn(repo_path, gov_root = "gov-bucket")

    mockery::stub(datom_repo_set_data_store, ".datom_git_push", invisible(TRUE))

    datom_repo_set_data_store(conn, new_store)

    updated <- yaml::read_yaml(fs::path(repo_path, ".datom", "project.yaml"))

    # storage.data changed
    expect_equal(updated$storage$data$root, new_store$path)  # abs path from datom_store_local

    # storage.governance COMPLETELY UNTOUCHED
    gov <- updated$storage$governance
    expect_equal(gov$type,   "s3")
    expect_equal(gov$bucket, "gov-bucket")
    expect_equal(gov$prefix, "gov-prefix")
    expect_equal(gov$region, "us-east-1")
  })
})

test_that("datom_repo_set_data_store() sets correct fields for s3 store", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)
    write_project_yaml(repo_path)

    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    new_store <- datom_store_s3(
      bucket     = "new-bucket",
      prefix     = "new-prefix",
      region     = "eu-west-1",
      access_key = "FAKE_KEY",
      secret_key = "FAKE_SECRET",
      validate   = FALSE
    )
    conn <- make_dev_conn(repo_path)

    mockery::stub(datom_repo_set_data_store, ".datom_git_push", invisible(TRUE))

    datom_repo_set_data_store(conn, new_store)

    updated <- yaml::read_yaml(fs::path(repo_path, ".datom", "project.yaml"))
    expect_equal(updated$storage$data$type,   "s3")
    expect_equal(updated$storage$data$root,   "new-bucket")
    expect_equal(updated$storage$data$prefix, "new-prefix")
    expect_equal(updated$storage$data$region, "eu-west-1")
    # region absent on local -- make sure it isn't present from a prior s3 write
    # by checking it's actually set here
    expect_false(is.null(updated$storage$data$region))
  })
})

test_that("datom_repo_set_data_store() local store has no region field", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)
    write_project_yaml(repo_path)

    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    new_dir   <- fs::dir_create("new-store")
    new_store <- datom_store_local(new_dir, validate = FALSE)
    conn      <- make_dev_conn(repo_path)

    mockery::stub(datom_repo_set_data_store, ".datom_git_push", invisible(TRUE))

    datom_repo_set_data_store(conn, new_store)

    updated <- yaml::read_yaml(fs::path(repo_path, ".datom", "project.yaml"))
    expect_null(updated$storage$data$region)
  })
})

test_that("datom_repo_set_data_store() uses custom commit message when provided", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)
    write_project_yaml(repo_path)

    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    new_dir   <- fs::dir_create("new-store")
    new_store <- datom_store_local(new_dir, validate = FALSE)
    conn      <- make_dev_conn(repo_path)

    mockery::stub(datom_repo_set_data_store, ".datom_git_push", invisible(TRUE))

    datom_repo_set_data_store(conn, new_store, message = "migrate to new backend")

    repo_obj <- git2r::repository(repo_path)
    last_msg <- git2r::commits(repo_obj, n = 1)[[1]]$message
    expect_equal(last_msg, "migrate to new backend")
  })
})

test_that("datom_repo_set_data_store() returns SHA invisibly", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)
    write_project_yaml(repo_path)

    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    new_dir   <- fs::dir_create("new-store")
    new_store <- datom_store_local(new_dir, validate = FALSE)
    conn      <- make_dev_conn(repo_path)

    mockery::stub(datom_repo_set_data_store, ".datom_git_push", invisible(TRUE))

    result <- withVisible(datom_repo_set_data_store(conn, new_store))
    expect_false(result$visible)
    expect_type(result$value, "character")
    expect_true(nzchar(result$value))
  })
})
