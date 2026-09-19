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

write_project_yaml <- function(path, extra_storage = NULL, schema_version = NULL) {
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
  # Added conditionally rather than as a NULL slot: a NULL round-trips through
  # yaml as `~` and reads back as an explicit NULL, which is a different document
  # from one where the key is simply absent. Absent is the state every repo
  # written before the field existed is in, and every other test here relies on
  # it, so it has to be the real absence.
  if (!is.null(schema_version)) cfg$schema_version <- schema_version
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

test_that("datom_repo_set_data_store() refuses a config format it cannot read", {
  # This verb is the only writer of project.yaml besides datom_init_repo(), and it
  # does not merely write: it merges a `storage$data` block into the document on
  # this build's assumptions, then commits and pushes, so a shape this build
  # cannot read would be edited wrongly and then distributed to everyone sharing
  # the repo. A format that reparented those keys gets a stale block beside the
  # real one.
  #
  # The connection-time gate does not cover this. It ran on the file as it was
  # when the connection opened, and a hand edit or a pull since then replaces it
  # -- which is not contrived here, because this is the storage-migration verb,
  # called exactly when somebody is reorganising storage by hand.
  #
  # No git repo and no push stub are needed: the refusal happens before the merge,
  # so nothing reaches the commit.
  withr::with_tempdir({
    repo_path <- fs::dir_create("repo")
    write_project_yaml(repo_path, schema_version = .datom_project_schema + 1L)
    yaml_path <- fs::path(repo_path, ".datom", "project.yaml")
    before <- readLines(yaml_path, warn = FALSE)

    conn      <- make_dev_conn(repo_path)
    new_store <- datom_store_local(fs::dir_create("new-store"), validate = FALSE)

    err <- expect_error(
      datom_repo_set_data_store(conn, new_store),
      class = "datom_schema_unsupported"
    )
    msg <- conditionMessage(err)
    expect_match(msg, "project.yaml", fixed = TRUE)
    # Worded for a write, because a write is what was stopped.
    expect_match(msg, "cannot write")
    expect_match(msg, paste0("supports up to v", .datom_project_schema))

    # And the file is byte-identical: the refusal is a door, not a rollback.
    expect_identical(readLines(yaml_path, warn = FALSE), before)
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


# === The sanctioned git-mutation surface ======================================
#
# datom_repo_commit() / datom_repo_push() exist so a downstream package can put
# its own content in the data repo without importing git2r. Nothing is mocked
# here: every claim is about what git ends up holding -- which file is in the
# commit's tree, whether the remote moved -- and a mock of the commit or the push
# would be asserting that the wrapper called the function the wrapper calls.
#
# The one fixture note worth carrying: the remote is a bare repo on disk, and its
# branch is read by name rather than through HEAD, because `git2r::init()` honours
# init.defaultBranch and the two repos need not agree about what that name is.

local_git_verb_conn <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)

  repo_dir <- fs::path(root, "repo")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, bare_dir))

  git2r::init(bare_dir, bare = TRUE)
  repo <- seed_git_repo(repo_dir)
  writeLines("init", fs::path(repo_dir, "README.md"))
  writeLines("secret.txt", fs::path(repo_dir, ".gitignore"))
  writeLines("delete me", fs::path(repo_dir, "drop.txt"))
  git2r::add(repo, c("README.md", ".gitignore", "drop.txt"))
  git2r::commit(repo, "Initial commit")
  git2r::remote_add(repo, name = "origin", url = as.character(bare_dir))
  git2r::push(repo, name = "origin", refspec = test_head_refspec(repo),
              set_upstream = TRUE)

  list(
    conn = make_dev_conn(repo_dir),
    repo = repo,
    repo_dir = repo_dir,
    bare = git2r::repository(bare_dir),
    branch = test_head_branch(repo)
  )
}

rv_head <- function(repo) {
  as.character(git2r::revparse_single(repo, "HEAD")$sha)
}

# The remote's tip for a named branch. Read by branch name, never via the bare
# repo's HEAD, which points at whatever init.defaultBranch said.
rv_remote_head <- function(fx) {
  branches <- git2r::branches(fx$bare, flags = "local")
  b <- branches[[fx$branch]]
  if (is.null(b)) return(NA_character_)
  as.character(git2r::branch_target(b))
}

rv_tree_paths <- function(repo, rev = "HEAD") {
  commit <- git2r::revparse_single(repo, rev)
  entries <- git2r::ls_tree(repo = repo, tree = git2r::tree(commit))
  paste0(entries$path, entries$name)
}

rv_tree_content <- function(repo, path, rev = "HEAD") {
  commit <- git2r::revparse_single(repo, rev)
  entries <- git2r::ls_tree(repo = repo, tree = git2r::tree(commit))
  row <- entries[paste0(entries$path, entries$name) == path, , drop = FALSE]
  if (nrow(row) != 1L) {
    stop("rv_tree_content(): expected one entry at ", path, ", found ", nrow(row),
         call. = FALSE)
  }
  git2r::content(git2r::lookup(repo, row$sha[[1L]]))
}


# --- datom_repo_commit(): staging semantics (AC17) ----------------------------

test_that("datom_repo_commit(paths = NULL) stages tracked, untracked and deleted, minus gitignored", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()

  writeLines("changed", fs::path(fx$repo_dir, "README.md"))   # tracked, modified
  writeLines("new", fs::path(fx$repo_dir, "new.txt"))         # untracked
  writeLines("shh", fs::path(fx$repo_dir, "secret.txt"))      # gitignored
  fs::file_delete(fs::path(fx$repo_dir, "drop.txt"))          # tracked, deleted

  # The deletion is here for a reason: the flag an author reaches for to make
  # deletions work (`staged_deletions = TRUE`) sets git2r::add(force = TRUE),
  # which also stages gitignored files. Both halves are asserted in one commit so
  # that shortcut cannot pass.
  sha <- suppressMessages(datom_repo_commit(fx$conn, "Human commit", push = FALSE))

  paths <- rv_tree_paths(fx$repo)
  expect_identical(rv_tree_content(fx$repo, "README.md"), "changed")
  expect_true("new.txt" %in% paths)
  expect_false("secret.txt" %in% paths)
  expect_false("drop.txt" %in% paths)
  expect_true(".gitignore" %in% paths)   # still tracked; the ignore rule still applies
  expect_identical(sha, rv_head(fx$repo))

  # Nothing left behind: the ignored file is not staged either, which a tree
  # assertion alone cannot see.
  status <- git2r::status(fx$repo)
  expect_length(unlist(status$staged, use.names = FALSE), 0L)
})

test_that("datom_repo_commit(paths = ) stages exactly those paths", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()

  writeLines("a", fs::path(fx$repo_dir, "a.txt"))
  writeLines("b", fs::path(fx$repo_dir, "b.txt"))

  suppressMessages(datom_repo_commit(fx$conn, "Just a", paths = "a.txt", push = FALSE))

  paths <- rv_tree_paths(fx$repo)
  expect_true("a.txt" %in% paths)
  expect_false("b.txt" %in% paths)
  expect_true("b.txt" %in% unlist(git2r::status(fx$repo)$untracked, use.names = FALSE))
})

test_that("datom_repo_commit() refuses a reader conn", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()
  fx$conn$role <- "reader"

  expect_error(datom_repo_commit(fx$conn, "nope"), "developer connection")
})

test_that("datom_repo_commit() validates message, paths and push", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()

  expect_error(datom_repo_commit(fx$conn, ""), "non-empty character")
  expect_error(datom_repo_commit(fx$conn, c("a", "b")), "non-empty character")
  expect_error(datom_repo_commit(fx$conn, "m", paths = character()), "character vector")
  expect_error(datom_repo_commit(fx$conn, "m", paths = 1L), "character vector")
  expect_error(datom_repo_commit(fx$conn, "m", push = NA), "TRUE")
})


# --- datom_repo_commit(): idempotence and the push qualification (AC17) -------

test_that("datom_repo_commit() on a clean tree creates no commit and is not an error", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()
  before <- rv_head(fx$repo)

  expect_message(
    datom_repo_commit(fx$conn, "Nothing here", push = FALSE),
    "Nothing to commit"
  )

  # Separate call rather than wrapping the one above: expect_message() returns
  # the condition, so withVisible() around it would inspect the message object
  # instead of the verb's return value. A second no-op is free.
  result <- withVisible(
    suppressMessages(datom_repo_commit(fx$conn, "Nothing here", push = FALSE))
  )

  expect_null(result$value)
  expect_false(result$visible)
  expect_identical(rv_head(fx$repo), before)
})

test_that("datom_repo_commit(push = FALSE) leaves the remote untouched", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()
  remote_before <- rv_remote_head(fx)

  writeLines("x", fs::path(fx$repo_dir, "x.txt"))
  sha <- suppressMessages(datom_repo_commit(fx$conn, "Local only", push = FALSE))

  expect_identical(rv_head(fx$repo), sha)
  expect_identical(rv_remote_head(fx), remote_before)
  expect_false(identical(rv_remote_head(fx), sha))
})

test_that("a clean tree with push = TRUE still pushes when the branch is ahead", {
  skip_if_not_installed("git2r")

  # The R15.5 qualification, and the failure it prevents is silent: if the no-op
  # path returned before pushing, one failed push would leave the remote behind
  # forever, because every later call finds a clean tree and returns early.
  fx <- local_git_verb_conn()

  writeLines("x", fs::path(fx$repo_dir, "x.txt"))
  sha <- suppressMessages(datom_repo_commit(fx$conn, "Local only", push = FALSE))
  expect_false(identical(rv_remote_head(fx), sha))

  head_before <- rv_head(fx$repo)
  result <- suppressMessages(datom_repo_commit(fx$conn, "Nothing to commit now"))

  expect_null(result)                              # no commit was created
  expect_identical(rv_head(fx$repo), head_before)  # ... and none appeared
  expect_identical(rv_remote_head(fx), sha)        # ... but the push happened
})

test_that("a clean tree with push = TRUE and nothing ahead does not push", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()

  writeLines("x", fs::path(fx$repo_dir, "x.txt"))
  sha <- suppressMessages(datom_repo_commit(fx$conn, "Pushed"))
  expect_identical(rv_remote_head(fx), sha)

  expect_message(
    datom_repo_commit(fx$conn, "Again"),
    "Remote already has every commit"
  )
  expect_identical(rv_remote_head(fx), sha)
})

test_that("datom_repo_commit() commits and pushes in one call", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()

  writeLines("x", fs::path(fx$repo_dir, "x.txt"))
  sha <- suppressMessages(datom_repo_commit(fx$conn, "Add x"))

  expect_identical(rv_head(fx$repo), sha)
  expect_identical(rv_remote_head(fx), sha)
})


# --- The guards both verbs assert (R15.7, R15.8) ------------------------------

test_that("datom_repo_commit() refuses a detached HEAD even with push = FALSE", {
  skip_if_not_installed("git2r")

  # The guard lives in `.datom_git_branch()` and is reached only from
  # `.datom_git_push()`, so `push = FALSE` is exactly the case that would slip
  # through if it were inherited rather than asserted. A commit onto a detached
  # HEAD succeeds, prints a SHA, and is unreachable once the branch is checked
  # out again -- with no push to reveal it.
  fx <- local_git_verb_conn()
  git2r::checkout(git2r::revparse_single(fx$repo, "HEAD"))
  expect_true(git2r::is_detached(fx$repo))

  writeLines("x", fs::path(fx$repo_dir, "x.txt"))
  head_before <- rv_head(fx$repo)

  expect_error(
    datom_repo_commit(fx$conn, "On a detached head", push = FALSE),
    "detached"
  )
  expect_identical(rv_head(fx$repo), head_before)
})

test_that("datom_repo_push() refuses a detached HEAD, by the guard it inherits", {
  skip_if_not_installed("git2r")

  # Inherited rather than asserted, and that asymmetry with the commit verb was
  # settled by probe: adding an explicit assert here reddened nothing. The
  # nothing-to-push early return needs an ahead count, the count needs an upstream
  # tracking ref, and a detached HEAD has none -- so this verb always reaches
  # `.datom_git_push()`, which checks. The commit verb has no such backstop with
  # `push = FALSE`, which is where the explicit assert earns its line.
  fx <- local_git_verb_conn()
  git2r::checkout(git2r::revparse_single(fx$repo, "HEAD"))

  expect_error(datom_repo_push(fx$conn), "detached")
})

test_that("both verbs refuse a repo with no remote, naming the recourse", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()
  git2r::remote_remove(fx$repo, "origin")

  # Classed rather than text-matched: `.datom_git_push()` would otherwise fail
  # here with R's own subscript-out-of-bounds error from `remotes(repo)[[1L]]`.
  expect_error(datom_repo_push(fx$conn), class = "datom_no_git_remote")
  expect_error(datom_repo_commit(fx$conn, "m"), class = "datom_no_git_remote")

  # push = FALSE is a local operation and stays legal without a remote.
  writeLines("x", fs::path(fx$repo_dir, "x.txt"))
  expect_type(
    suppressMessages(datom_repo_commit(fx$conn, "Local", push = FALSE)),
    "character"
  )
})


# --- datom_repo_push() convergence (AC21) ------------------------------------

test_that("datom_repo_push() advances the remote and is a no-op the second time", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()

  writeLines("x", fs::path(fx$repo_dir, "x.txt"))
  sha <- suppressMessages(datom_repo_commit(fx$conn, "Commit only", push = FALSE))
  expect_false(identical(rv_remote_head(fx), sha))

  result <- withVisible(suppressMessages(datom_repo_push(fx$conn)))
  expect_true(result$value)
  expect_false(result$visible)
  expect_identical(rv_remote_head(fx), sha)

  # Convergent, not imperative: nothing to push is information, not an error.
  expect_message(datom_repo_push(fx$conn), "Nothing to push")
  expect_identical(rv_remote_head(fx), sha)
})

test_that("datom_repo_push() refuses a reader conn and a conn with no clone", {
  skip_if_not_installed("git2r")

  fx <- local_git_verb_conn()

  reader <- fx$conn
  reader$role <- "reader"
  expect_error(datom_repo_push(reader), "developer connection")

  pathless <- fx$conn
  pathless$path <- NULL
  expect_error(datom_repo_push(pathless), "no local repo")

  expect_error(datom_repo_push("not-a-conn"), "datom_conn")
})
