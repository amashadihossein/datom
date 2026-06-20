# Tests for datom_repo_set_data_store() and datom_repo_delete() (R/repo.R)

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


# === datom_repo_delete() ======================================================

make_clone_conn <- function(path, gov_root = NULL, data_repo_url = NULL,
                            github_pat = NULL) {
  structure(
    list(
      project_name   = "TEST_PROJECT",
      backend        = "local",
      root           = as.character(path),
      prefix         = NULL,
      region         = NULL,
      client         = NULL,
      path           = as.character(path),
      role           = "developer",
      endpoint       = NULL,
      gov_root       = gov_root,
      gov_client     = NULL,
      gov_local_path = NULL,
      github_pat     = github_pat,
      data_repo_url  = data_repo_url,
      github_api_url = NULL
    ),
    class = "datom_conn"
  )
}

test_that("datom_repo_delete() errors on non-conn", {
  expect_error(datom_repo_delete("x", "X"), "datom_conn")
  expect_error(datom_repo_delete(NULL, "X"), "datom_conn")
})

test_that("datom_repo_delete() errors on reader role", {
  conn <- structure(
    list(role = "reader", project_name = "P", gov_root = NULL),
    class = "datom_conn"
  )
  expect_error(datom_repo_delete(conn, "P"), "developer")
})

test_that("datom_repo_delete() errors when confirm does not match", {
  conn <- structure(
    list(role = "developer", project_name = "MY_PROJECT", gov_root = NULL),
    class = "datom_conn"
  )
  expect_error(datom_repo_delete(conn, "wrong"), "Confirmation does not match")
  expect_error(datom_repo_delete(conn, NULL),    "Confirmation does not match")
})

test_that("datom_repo_delete() errors on gov-attached conn without force flag", {
  conn <- structure(
    list(role = "developer", project_name = "MY_PROJECT", gov_root = "gov-bucket"),
    class = "datom_conn"
  )
  expect_error(
    datom_repo_delete(conn, "MY_PROJECT"),
    "gov_decommission"
  )
})

test_that("datom_repo_delete() proceeds on gov-attached conn with force_gov_attached = TRUE", {
  withr::with_tempdir({
    clone_dir <- fs::dir_create("clone")
    conn <- make_clone_conn(clone_dir, gov_root = "gov-bucket",
                            data_repo_url = NULL)

    # data_repo_url = NULL triggers the warn-and-continue branch
    result <- datom_repo_delete(conn, "TEST_PROJECT", force_gov_attached = TRUE)
    expect_true(result)
    # clone removed despite gov being attached
    expect_false(fs::dir_exists(clone_dir))
  })
})

test_that("datom_repo_delete() removes local clone directory", {
  withr::with_tempdir({
    clone_dir <- fs::dir_create("clone")
    conn <- make_clone_conn(clone_dir, data_repo_url = NULL)

    expect_true(fs::dir_exists(clone_dir))
    datom_repo_delete(conn, "TEST_PROJECT")
    expect_false(fs::dir_exists(clone_dir))
  })
})

test_that("datom_repo_delete() skips clone removal when path is NULL", {
  conn <- make_clone_conn(withr::local_tempdir(), data_repo_url = NULL)
  conn$path <- NULL
  # Should not error; clone removal simply skipped
  expect_true(datom_repo_delete(conn, "TEST_PROJECT"))
})

test_that("datom_repo_delete() skips GitHub deletion for non-GitHub URL", {
  withr::with_tempdir({
    clone_dir <- fs::dir_create("clone")
    conn <- make_clone_conn(
      clone_dir,
      data_repo_url = "https://gitlab.com/org/repo.git",
      github_pat    = "fake-pat"
    )
    # Should not call .datom_delete_github_repo -- no mock needed
    result <- datom_repo_delete(conn, "TEST_PROJECT")
    expect_true(result)
    expect_false(fs::dir_exists(clone_dir))
  })
})

test_that("datom_repo_delete() warns and continues when no PAT provided", {
  withr::with_tempdir({
    clone_dir <- fs::dir_create("clone")
    conn <- make_clone_conn(
      clone_dir,
      data_repo_url = "https://github.com/org/repo.git",
      github_pat    = NULL  # no PAT
    )
    # Should warn about missing PAT but still remove clone
    expect_no_error(datom_repo_delete(conn, "TEST_PROJECT"))
    expect_false(fs::dir_exists(clone_dir))
  })
})

test_that("datom_repo_delete() calls .datom_delete_github_repo with correct args", {
  withr::with_tempdir({
    clone_dir <- fs::dir_create("clone")
    conn <- make_clone_conn(
      clone_dir,
      data_repo_url = "https://github.com/org/my-repo.git",
      github_pat    = "fake-pat-value"
    )

    mock_delete <- mockery::mock(invisible(TRUE))
    mockery::stub(datom_repo_delete, ".datom_delete_github_repo", mock_delete)

    datom_repo_delete(conn, "TEST_PROJECT")

    mockery::expect_called(mock_delete, 1L)
    call_args <- mockery::mock_args(mock_delete)[[1]]
    expect_equal(call_args[[1]], "org/my-repo")
    expect_equal(call_args[[2]], "fake-pat-value")
  })
})

test_that("datom_repo_delete() returns TRUE invisibly", {
  withr::with_tempdir({
    clone_dir <- fs::dir_create("clone")
    conn <- make_clone_conn(clone_dir, data_repo_url = NULL)

    result <- withVisible(datom_repo_delete(conn, "TEST_PROJECT"))
    expect_true(result$value)
    expect_false(result$visible)
  })
})


# === datom_repo_delete() property batteries ===================================

# A developer conn that never reaches side effects: the confirm/gov guards run
# before any clone/GitHub work, so a minimal structure is sufficient here.
guard_conn <- function(gov_root = NULL, project_name = "TEST_PROJECT") {
  structure(
    list(role = "developer", project_name = project_name, gov_root = gov_root),
    class = "datom_conn"
  )
}

test_that("datom_repo_delete() confirm guard rejects every mismatch", {
  # Feature: gov-seam-liftout, Property 1: datom_repo_delete confirm guard --
  # any confirm value not identical to conn$project_name must abort before
  # touching the repo.
  conn <- guard_conn()
  # Use a named list so NULL / NA / zero-length entries survive iteration.
  mismatches <- list(
    wrong_word   = "wrong",
    empty        = "",
    lowercase    = "test_project",
    trailing_ws  = "TEST_PROJECT ",
    truncated    = "TEST_PROJEC",
    na           = NA_character_,
    null         = NULL,
    zero_length  = character(0),
    multi        = c("TEST_PROJECT", "TEST_PROJECT")
  )
  for (nm in names(mismatches)) {
    expect_error(
      datom_repo_delete(conn, mismatches[[nm]]),
      "Confirmation does not match",
      info = paste0("confirm battery case: ", nm)
    )
  }
})

test_that("datom_repo_delete() governance guard refuses governed conns", {
  # Feature: gov-seam-liftout, Property 2: datom_repo_delete governance guard --
  # a non-NULL gov_root without force_gov_attached must abort and point at
  # gov_decommission, regardless of the gov_root value.
  gov_roots <- c("gov-bucket", "another-gov", "s3://org/gov", "/local/gov/path")
  for (gr in gov_roots) {
    conn <- guard_conn(gov_root = gr)
    expect_error(
      datom_repo_delete(conn, "TEST_PROJECT"),
      "gov_decommission",
      info = paste0("governance battery case: ", gr)
    )
  }
  # Converse: a NULL gov_root must NOT trip the governance guard.
  conn_solo <- guard_conn(gov_root = NULL)
  conn_solo$path <- NULL  # skip clone removal so the call completes cleanly
  conn_solo$data_repo_url <- NULL
  expect_no_error(datom_repo_delete(conn_solo, "TEST_PROJECT"))
})


# === datom_repo_attach_governance() ===========================================

# Developer conn with a distinct data-store root (so the storage mirror lands
# outside the git clone) and a local data backend.
make_attach_conn <- function(clone_path, store_root) {
  structure(
    list(
      project_name   = "TEST_PROJECT",
      backend        = "local",
      root           = as.character(store_root),
      prefix         = "proj",
      region         = NULL,
      client         = NULL,
      path           = as.character(clone_path),
      role           = "developer",
      endpoint       = NULL,
      gov_root       = NULL,
      gov_client     = NULL,
      gov_local_path = NULL,
      github_pat     = NULL,
      data_repo_url  = NULL,
      github_api_url = NULL
    ),
    class = "datom_conn"
  )
}

test_that("datom_repo_attach_governance() errors on non-conn", {
  store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
  expect_error(
    datom_repo_attach_governance("x", "https://example.com/gov.git", store),
    "datom_conn"
  )
})

test_that("datom_repo_attach_governance() errors on reader role", {
  conn <- structure(
    list(role = "reader", path = "/tmp", project_name = "X"),
    class = "datom_conn"
  )
  store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
  expect_error(
    datom_repo_attach_governance(conn, "https://example.com/gov.git", store),
    "developer"
  )
})

test_that("datom_repo_attach_governance() errors when conn has no path", {
  conn <- structure(
    list(role = "developer", path = NULL, project_name = "X"),
    class = "datom_conn"
  )
  store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
  expect_error(
    datom_repo_attach_governance(conn, "https://example.com/gov.git", store),
    "path"
  )
})

test_that("datom_repo_attach_governance() errors on empty gov_repo_url", {
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    write_project_yaml(repo_path)
    conn  <- make_attach_conn(repo_path, fs::dir_create("store"))
    store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
    expect_error(datom_repo_attach_governance(conn, "", store), "non-empty")
    expect_error(
      datom_repo_attach_governance(conn, c("a", "b"), store),
      "non-empty"
    )
  })
})

test_that("datom_repo_attach_governance() errors on invalid gov_store", {
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    write_project_yaml(repo_path)
    conn <- make_attach_conn(repo_path, fs::dir_create("store"))
    expect_error(
      datom_repo_attach_governance(conn, "https://example.com/gov.git",
                                   list(type = "s3")),
      "datom_store_s3"
    )
  })
})

test_that("datom_repo_attach_governance() errors when project.yaml missing", {
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")  # no .datom/project.yaml
    conn  <- make_attach_conn(repo_path, fs::dir_create("store"))
    store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
    expect_error(
      datom_repo_attach_governance(conn, "https://example.com/gov.git", store),
      "project.yaml"
    )
  })
})

test_that("datom_repo_attach_governance() writes git copy + storage mirror", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)
    write_project_yaml(repo_path)

    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    store_root <- fs::dir_create("data-store")
    conn       <- make_attach_conn(repo_path, store_root)
    gov_store  <- datom_store_local(fs::dir_create("gov-store"),
                                    prefix = "org-gov", validate = FALSE)

    mockery::stub(datom_repo_attach_governance, ".datom_git_push", invisible(TRUE))

    sha <- datom_repo_attach_governance(
      conn, "https://example.com/gov.git", gov_store
    )

    expect_type(sha, "character")
    expect_true(nzchar(sha))

    # Git-canonical copy written + readable
    git_json <- .datom_read_governance_json_local(repo_path)
    expect_false(is.null(git_json))
    expect_equal(git_json$gov_repo_url, "https://example.com/gov.git")
    expect_equal(git_json$gov_storage$type, "local")

    # Storage mirror written + readable
    mirror <- .datom_storage_read_governance_json(conn)
    expect_false(is.null(mirror))
    expect_equal(mirror$gov_repo_url, "https://example.com/gov.git")
  })
})

test_that("datom_repo_attach_governance() uses default commit message", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)
    write_project_yaml(repo_path)

    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    conn      <- make_attach_conn(repo_path, fs::dir_create("data-store"))
    gov_store <- datom_store_local(fs::dir_create("gov-store"), validate = FALSE)

    mockery::stub(datom_repo_attach_governance, ".datom_git_push", invisible(TRUE))

    datom_repo_attach_governance(conn, "https://example.com/gov.git", gov_store)

    last_msg <- git2r::commits(git2r::repository(repo_path), n = 1)[[1]]$message
    expect_equal(last_msg, "Attach governance: TEST_PROJECT")
  })
})

test_that("datom_repo_attach_governance() warns but succeeds when mirror fails", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)
    write_project_yaml(repo_path)

    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    conn      <- make_attach_conn(repo_path, fs::dir_create("data-store"))
    gov_store <- datom_store_local(fs::dir_create("gov-store"), validate = FALSE)

    mockery::stub(datom_repo_attach_governance, ".datom_git_push", invisible(TRUE))
    mockery::stub(
      datom_repo_attach_governance,
      ".datom_storage_write_governance_json",
      function(...) stop("simulated storage failure")
    )

    expect_warning(
      datom_repo_attach_governance(conn, "https://example.com/gov.git", gov_store),
      "storage upload failed"
    )

    # Git-canonical copy still present despite mirror failure
    expect_false(is.null(.datom_read_governance_json_local(repo_path)))
  })
})

test_that("datom_repo_attach_governance() returns SHA invisibly", {
  skip_if_not_installed("git2r")
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    seed_git_repo(repo_path)
    write_project_yaml(repo_path)

    repo <- git2r::repository(repo_path)
    git2r::add(repo, ".datom/project.yaml")
    git2r::commit(repo, message = "init")

    conn      <- make_attach_conn(repo_path, fs::dir_create("data-store"))
    gov_store <- datom_store_local(fs::dir_create("gov-store"), validate = FALSE)

    mockery::stub(datom_repo_attach_governance, ".datom_git_push", invisible(TRUE))

    result <- withVisible(
      datom_repo_attach_governance(conn, "https://example.com/gov.git", gov_store)
    )
    expect_false(result$visible)
    expect_type(result$value, "character")
  })
})
