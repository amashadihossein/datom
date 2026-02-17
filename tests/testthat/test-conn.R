# Tests for tbit_conn S3 class (Phase 4, Chunk 2)

# --- Helper: create a mock S3 client -----------------------------------------
mock_s3_client <- function() {
  list(
    put_object = function(...) NULL,
    get_object = function(...) NULL,
    head_object = function(...) NULL
  )
}


# =============================================================================
# new_tbit_conn()
# =============================================================================

test_that("creates a reader connection with required fields", {
  conn <- new_tbit_conn(
    project_name = "clinical_data",
    bucket = "my-bucket",
    prefix = "project-alpha/",
    region = "us-east-1",
    s3_client = mock_s3_client(),
    role = "reader"
  )

  expect_s3_class(conn, "tbit_conn")
  expect_equal(conn$project_name, "clinical_data")
  expect_equal(conn$bucket, "my-bucket")
  expect_equal(conn$prefix, "project-alpha/")
  expect_equal(conn$region, "us-east-1")
  expect_equal(conn$role, "reader")
  expect_null(conn$path)
})

test_that("creates a developer connection with path", {
  dir <- withr::local_tempdir()

  conn <- new_tbit_conn(
    project_name = "clinical_data",
    bucket = "my-bucket",
    region = "us-east-1",
    s3_client = mock_s3_client(),
    path = dir,
    role = "developer"
  )

  expect_s3_class(conn, "tbit_conn")
  expect_equal(conn$role, "developer")
  expect_equal(conn$path, dir)
})

test_that("prefix defaults to NULL", {
  conn <- new_tbit_conn(
    project_name = "proj",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client(),
    role = "reader"
  )

  expect_null(conn$prefix)
})

test_that("developer requires path", {
  expect_error(
    new_tbit_conn(
      project_name = "proj",
      bucket = "b",
      region = "us-east-1",
      s3_client = mock_s3_client(),
      role = "developer"
    ),
    "path"
  )
})

test_that("aborts on empty project_name", {
  expect_error(
    new_tbit_conn(
      project_name = "",
      bucket = "b",
      region = "us-east-1",
      s3_client = mock_s3_client()
    ),
    "project_name"
  )
})

test_that("aborts on NA project_name", {
  expect_error(
    new_tbit_conn(
      project_name = NA_character_,
      bucket = "b",
      region = "us-east-1",
      s3_client = mock_s3_client()
    ),
    "project_name"
  )
})

test_that("aborts on empty bucket", {
  expect_error(
    new_tbit_conn(
      project_name = "p",
      bucket = "",
      region = "us-east-1",
      s3_client = mock_s3_client()
    ),
    "bucket"
  )
})

test_that("aborts on empty region", {
  expect_error(
    new_tbit_conn(
      project_name = "p",
      bucket = "b",
      region = "",
      s3_client = mock_s3_client()
    ),
    "region"
  )
})

test_that("aborts on non-string prefix", {
  expect_error(
    new_tbit_conn(
      project_name = "p",
      bucket = "b",
      prefix = 123,
      region = "us-east-1",
      s3_client = mock_s3_client()
    ),
    "prefix"
  )
})

test_that("aborts on non-string path", {
  expect_error(
    new_tbit_conn(
      project_name = "p",
      bucket = "b",
      region = "us-east-1",
      s3_client = mock_s3_client(),
      path = 123,
      role = "developer"
    ),
    "path"
  )
})

test_that("role defaults to reader", {
  conn <- new_tbit_conn(
    project_name = "p",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  expect_equal(conn$role, "reader")
})

test_that("aborts on invalid role", {
  expect_error(
    new_tbit_conn(
      project_name = "p",
      bucket = "b",
      region = "us-east-1",
      s3_client = mock_s3_client(),
      role = "admin"
    ),
    "reader.*developer"
  )
})


# =============================================================================
# is_tbit_conn()
# =============================================================================

test_that("is_tbit_conn returns TRUE for tbit_conn objects", {
  conn <- new_tbit_conn(
    project_name = "p",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  expect_true(is_tbit_conn(conn))
})

test_that("is_tbit_conn returns FALSE for other objects", {
  expect_false(is_tbit_conn(list(a = 1)))
  expect_false(is_tbit_conn("string"))
  expect_false(is_tbit_conn(42))
  expect_false(is_tbit_conn(NULL))
})


# =============================================================================
# print.tbit_conn()
# =============================================================================

test_that("print.tbit_conn outputs key fields", {
  conn <- new_tbit_conn(
    project_name = "clinical_data",
    bucket = "my-bucket",
    prefix = "proj/",
    region = "us-east-1",
    s3_client = mock_s3_client(),
    role = "reader"
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_match(combined, "clinical_data")
  expect_match(combined, "reader")
  expect_match(combined, "my-bucket")
  expect_match(combined, "proj/")
})

test_that("print.tbit_conn shows path for developer", {
  dir <- withr::local_tempdir()

  conn <- new_tbit_conn(
    project_name = "proj",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client(),
    path = dir,
    role = "developer"
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_match(combined, "developer")
  expect_match(combined, dir, fixed = TRUE)
})

test_that("print.tbit_conn omits prefix when NULL", {
  conn <- new_tbit_conn(
    project_name = "proj",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_no_match(combined, "Prefix")
})

test_that("print.tbit_conn returns x invisibly", {
  conn <- new_tbit_conn(
    project_name = "proj",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  expect_invisible(print(conn))

  result <- withVisible(print(conn))
  expect_false(result$visible)
  expect_s3_class(result$value, "tbit_conn")
})

test_that("print.tbit_conn does not expose s3_client details", {
  conn <- new_tbit_conn(
    project_name = "proj",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_no_match(combined, "put_object")
  expect_no_match(combined, "get_object")
})


# =============================================================================
# tbit_get_conn() — dispatch
# =============================================================================

test_that("aborts when no arguments provided", {
  expect_error(tbit_get_conn(), "path.*bucket")
})

test_that("aborts when both path and bucket provided", {
  expect_error(
    tbit_get_conn(path = "some/path", bucket = "b", project_name = "p"),
    "not both"
  )
})

test_that("aborts when both path and project_name provided", {
  expect_error(
    tbit_get_conn(path = "some/path", project_name = "p"),
    "not both"
  )
})


# =============================================================================
# tbit_get_conn() — developer path (from project.yaml)
# =============================================================================

# --- Helper: create a temp repo with .tbit/project.yaml ----------------------
create_test_tbit_repo <- function(project_name = "testproj",
                                  bucket = "test-bucket",
                                  prefix = "test-prefix/",
                                  region = "us-east-1",
                                  env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  tbit_dir <- fs::path(dir, ".tbit")
  fs::dir_create(tbit_dir)

  yaml_content <- list(
    project_name = project_name,
    storage = list(
      type = "s3",
      bucket = bucket,
      prefix = prefix,
      region = region,
      credentials = list(
        access_key_env = paste0("TBIT_", toupper(project_name), "_ACCESS_KEY_ID"),
        secret_key_env = paste0("TBIT_", toupper(project_name), "_SECRET_ACCESS_KEY")
      )
    )
  )

  yaml::write_yaml(yaml_content, fs::path(tbit_dir, "project.yaml"))
  dir
}


test_that("developer path reads project.yaml and creates connection", {
  dir <- create_test_tbit_repo(project_name = "myproj", bucket = "my-bucket")

  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "fake_key",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = "ghp_fake"
  )

  mockery::stub(tbit_get_conn, ".tbit_s3_client", mock_s3_client)

  conn <- tbit_get_conn(path = dir)

  expect_s3_class(conn, "tbit_conn")
  expect_equal(conn$project_name, "myproj")
  expect_equal(conn$bucket, "my-bucket")
  expect_equal(conn$role, "developer")
  expect_equal(conn$path, as.character(fs::path_abs(dir)))
})

test_that("developer path falls back to reader role without GITHUB_PAT", {
  dir <- create_test_tbit_repo(project_name = "myproj", bucket = "my-bucket")

  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "fake_key",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = NA
  )

  mockery::stub(tbit_get_conn, ".tbit_s3_client", mock_s3_client)

  conn <- tbit_get_conn(path = dir)

  expect_s3_class(conn, "tbit_conn")
  expect_equal(conn$role, "reader")
  expect_null(conn$path)
})

test_that("developer path reads prefix from project.yaml", {
  dir <- create_test_tbit_repo(prefix = "alpha/beta/")

  withr::local_envvar(
    TBIT_TESTPROJ_ACCESS_KEY_ID = "k",
    TBIT_TESTPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )

  mockery::stub(tbit_get_conn, ".tbit_s3_client", mock_s3_client)

  conn <- tbit_get_conn(path = dir)
  expect_equal(conn$prefix, "alpha/beta/")
})

test_that("developer path reads region from project.yaml", {
  dir <- create_test_tbit_repo(region = "eu-west-1")

  withr::local_envvar(
    TBIT_TESTPROJ_ACCESS_KEY_ID = "k",
    TBIT_TESTPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )

  mockery::stub(tbit_get_conn, ".tbit_s3_client", mock_s3_client)

  conn <- tbit_get_conn(path = dir)
  expect_equal(conn$region, "eu-west-1")
})

test_that("developer path aborts when project.yaml is missing", {
  dir <- withr::local_tempdir()

  expect_error(tbit_get_conn(path = dir), "No tbit config")
})

test_that("developer path aborts when project_name missing from yaml", {
  dir <- withr::local_tempdir()
  tbit_dir <- fs::path(dir, ".tbit")
  fs::dir_create(tbit_dir)
  yaml::write_yaml(
    list(storage = list(bucket = "b")),
    fs::path(tbit_dir, "project.yaml")
  )

  expect_error(tbit_get_conn(path = dir), "project_name")
})

test_that("developer path aborts when storage section missing from yaml", {
  dir <- withr::local_tempdir()
  tbit_dir <- fs::path(dir, ".tbit")
  fs::dir_create(tbit_dir)
  yaml::write_yaml(
    list(project_name = "p"),
    fs::path(tbit_dir, "project.yaml")
  )

  expect_error(tbit_get_conn(path = dir), "storage")
})

test_that("developer path aborts when bucket missing from yaml", {
  dir <- withr::local_tempdir()
  tbit_dir <- fs::path(dir, ".tbit")
  fs::dir_create(tbit_dir)
  yaml::write_yaml(
    list(project_name = "p", storage = list(region = "us-east-1")),
    fs::path(tbit_dir, "project.yaml")
  )

  expect_error(tbit_get_conn(path = dir), "bucket")
})

test_that("developer path aborts when credentials missing", {
  dir <- create_test_tbit_repo(project_name = "myproj")

  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = NA,
    TBIT_MYPROJ_SECRET_ACCESS_KEY = NA,
    GITHUB_PAT = NA
  )

  expect_error(tbit_get_conn(path = dir), "ACCESS_KEY_ID")
})


# =============================================================================
# tbit_get_conn() — reader path (direct params)
# =============================================================================

test_that("reader path creates connection from direct params", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "fake_key",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "fake_secret"
  )

  mockery::stub(tbit_get_conn, ".tbit_s3_client", mock_s3_client)

  conn <- tbit_get_conn(bucket = "reader-bucket", project_name = "myproj")

  expect_s3_class(conn, "tbit_conn")
  expect_equal(conn$bucket, "reader-bucket")
  expect_equal(conn$project_name, "myproj")
  expect_equal(conn$role, "reader")
  expect_null(conn$path)
  expect_null(conn$prefix)
})

test_that("reader path accepts prefix", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "k",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "s"
  )

  mockery::stub(tbit_get_conn, ".tbit_s3_client", mock_s3_client)

  conn <- tbit_get_conn(bucket = "b", prefix = "data/", project_name = "myproj")

  expect_equal(conn$prefix, "data/")
})

test_that("reader path aborts when bucket is missing", {
  expect_error(
    tbit_get_conn(project_name = "myproj"),
    "bucket.*required"
  )
})

test_that("reader path aborts when project_name is missing", {
  expect_error(
    tbit_get_conn(bucket = "b"),
    "project_name.*required"
  )
})

test_that("reader path aborts when credentials missing", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = NA,
    TBIT_MYPROJ_SECRET_ACCESS_KEY = NA
  )

  expect_error(
    tbit_get_conn(bucket = "b", project_name = "myproj"),
    "ACCESS_KEY_ID"
  )
})

test_that("reader path uses AWS_DEFAULT_REGION env var", {
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "k",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "s",
    AWS_DEFAULT_REGION = "ap-southeast-1"
  )

  mockery::stub(tbit_get_conn, ".tbit_s3_client", mock_s3_client)

  conn <- tbit_get_conn(bucket = "b", project_name = "myproj")

  expect_equal(conn$region, "ap-southeast-1")
})


# =============================================================================
# tbit_init_repo()
# =============================================================================

# --- Helper: create a bare repo as remote + a working dir --------------------
setup_init_env <- function(env = parent.frame()) {
  # Bare repo to act as "remote" for push

  bare_dir <- withr::local_tempdir(.local_envir = env)
  git2r::init(bare_dir, bare = TRUE)

  # Working directory (not yet a git repo)
  work_dir <- withr::local_tempdir(.local_envir = env)

  # Set git config globally for this test (commit needs author info)
  withr::local_envvar(
    .local_envir = env,
    TBIT_TESTPROJ_ACCESS_KEY_ID = "fake_key",
    TBIT_TESTPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = "ghp_fake"
  )

  list(bare_dir = bare_dir, work_dir = work_dir)
}


# --- Input validation ---------------------------------------------------------

test_that("tbit_init_repo aborts on invalid project_name", {
  expect_error(tbit_init_repo(project_name = "", remote_url = "x", bucket = "b"),
               "name")
})

test_that("tbit_init_repo aborts on invalid remote_url", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "k",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )
  expect_error(tbit_init_repo(path = dir, project_name = "myproj",
                               remote_url = "", bucket = "b"),
               "remote_url")
})

test_that("tbit_init_repo aborts on invalid bucket", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "k",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )
  expect_error(tbit_init_repo(path = dir, project_name = "myproj",
                               remote_url = "https://github.com/x/y.git",
                               bucket = ""),
               "bucket")
})

test_that("tbit_init_repo aborts on invalid prefix", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "k",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )
  expect_error(tbit_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b",
                               prefix = 123),
               "prefix")
})

test_that("tbit_init_repo aborts on invalid max_file_size_gb", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "k",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )
  expect_error(tbit_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b",
                               max_file_size_gb = -1),
               "max_file_size_gb")
  expect_error(tbit_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b",
                               max_file_size_gb = "big"),
               "max_file_size_gb")
})

test_that("tbit_init_repo aborts when credentials are missing", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = NA,
    TBIT_MYPROJ_SECRET_ACCESS_KEY = NA,
    GITHUB_PAT = NA
  )
  expect_error(tbit_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b"),
               "ACCESS_KEY_ID")
})

test_that("tbit_init_repo aborts when GITHUB_PAT is missing", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    TBIT_MYPROJ_ACCESS_KEY_ID = "k",
    TBIT_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = NA
  )
  expect_error(tbit_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b"),
               "GITHUB_PAT")
})

test_that("tbit_init_repo aborts if .tbit already exists", {
  env <- setup_init_env()
  fs::dir_create(fs::path(env$work_dir, ".tbit"))
  yaml::write_yaml(list(project_name = "x"),
                    fs::path(env$work_dir, ".tbit", "project.yaml"))

  expect_error(tbit_init_repo(path = env$work_dir, project_name = "testproj",
                               remote_url = env$bare_dir, bucket = "b"),
               "already exists")
})


# --- Happy path ---------------------------------------------------------------

test_that("tbit_init_repo creates .tbit directory", {
  env <- setup_init_env()

  result <- tbit_init_repo(
    path = env$work_dir,
    project_name = "testproj",
    remote_url = env$bare_dir,
    bucket = "my-bucket"
  )

  expect_true(fs::dir_exists(fs::path(env$work_dir, ".tbit")))
})

test_that("tbit_init_repo creates input_files directory", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  expect_true(fs::dir_exists(fs::path(env$work_dir, "input_files")))
})

test_that("tbit_init_repo creates project.yaml with correct fields", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "my-bucket",
                  prefix = "data/", region = "eu-west-1",
                  max_file_size_gb = 500)

  yaml_path <- fs::path(env$work_dir, ".tbit", "project.yaml")
  expect_true(fs::file_exists(yaml_path))

  cfg <- yaml::read_yaml(yaml_path)
  expect_equal(cfg$project_name, "testproj")
  expect_equal(cfg$storage$type, "s3")
  expect_equal(cfg$storage$bucket, "my-bucket")
  expect_equal(cfg$storage$prefix, "data/")
  expect_equal(cfg$storage$region, "eu-west-1")
  expect_equal(cfg$storage$max_file_size_gb, 500)
  expect_equal(cfg$storage$credentials$access_key_env,
               "TBIT_TESTPROJ_ACCESS_KEY_ID")
  expect_equal(cfg$storage$credentials$secret_key_env,
               "TBIT_TESTPROJ_SECRET_ACCESS_KEY")
})

test_that("tbit_init_repo creates routing.json", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  routing_path <- fs::path(env$work_dir, ".tbit", "routing.json")
  expect_true(fs::file_exists(routing_path))

  routing <- jsonlite::read_json(routing_path)
  expect_equal(routing$methods$r$default, "tbit::tbit_read")
  expect_equal(routing$methods$python$default, "tbit.read")
})

test_that("tbit_init_repo creates manifest.json", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  manifest_path <- fs::path(env$work_dir, ".tbit", "manifest.json")
  expect_true(fs::file_exists(manifest_path))

  manifest <- jsonlite::read_json(manifest_path)
  expect_equal(manifest$summary$total_tables, 0)
  expect_equal(manifest$summary$total_size_bytes, 0)
  expect_equal(manifest$summary$total_versions, 0)
})

test_that("tbit_init_repo creates .gitignore with input_files/", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  gitignore <- readLines(fs::path(env$work_dir, ".gitignore"))
  expect_true("input_files/" %in% gitignore)
  expect_true(".DS_Store" %in% gitignore)
  expect_true("*.parquet" %in% gitignore)
})

test_that("tbit_init_repo initializes git with remote", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  expect_true(fs::dir_exists(fs::path(env$work_dir, ".git")))

  repo <- git2r::repository(env$work_dir)
  remotes <- git2r::remotes(repo)
  expect_true("origin" %in% remotes)
  expect_equal(git2r::remote_url(repo, remote = "origin"), env$bare_dir)
})

test_that("tbit_init_repo makes initial commit", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  repo <- git2r::repository(env$work_dir)
  log <- git2r::commits(repo)
  expect_length(log, 1)
  expect_match(log[[1]]$message, "Initialize tbit repository")
})

test_that("tbit_init_repo pushes to remote", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  # Verify bare repo has the commit
  bare_repo <- git2r::repository(env$bare_dir)
  bare_log <- git2r::commits(bare_repo)
  expect_length(bare_log, 1)
  expect_match(bare_log[[1]]$message, "Initialize tbit repository")
})

test_that("tbit_init_repo returns invisible TRUE", {
  env <- setup_init_env()

  result <- tbit_init_repo(path = env$work_dir, project_name = "testproj",
                            remote_url = env$bare_dir, bucket = "b")

  expect_true(result)
  expect_invisible(tbit_init_repo(
    path = withr::local_tempdir(),
    project_name = "testproj",
    remote_url = env$bare_dir,
    bucket = "b"
  ))
})

test_that("tbit_init_repo uses AWS_DEFAULT_REGION fallback", {
  env <- setup_init_env()
  withr::local_envvar(AWS_DEFAULT_REGION = "ap-northeast-1")

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".tbit", "project.yaml"))
  expect_equal(cfg$storage$region, "ap-northeast-1")
})

test_that("tbit_init_repo defaults region to us-east-1", {
  env <- setup_init_env()
  withr::local_envvar(AWS_DEFAULT_REGION = NA)

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".tbit", "project.yaml"))
  expect_equal(cfg$storage$region, "us-east-1")
})

test_that("tbit_init_repo handles prefix = NULL", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".tbit", "project.yaml"))
  # YAML writes NULL as missing key
  expect_true(is.null(cfg$storage$prefix))
})

test_that("tbit_init_repo normalizes project_name for cred env vars", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- withr::local_tempdir()

  withr::local_envvar(
    TBIT_MY_DATA_ACCESS_KEY_ID = "k",
    TBIT_MY_DATA_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )

  tbit_init_repo(path = work_dir, project_name = "my-data",
                  remote_url = bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(work_dir, ".tbit", "project.yaml"))
  expect_equal(cfg$storage$credentials$access_key_env,
               "TBIT_MY_DATA_ACCESS_KEY_ID")
  expect_equal(cfg$storage$credentials$secret_key_env,
               "TBIT_MY_DATA_SECRET_ACCESS_KEY")
})

test_that("tbit_init_repo passes is_valid_tbit_repo checks", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  # Should pass git + tbit checks (not renv — we don't init renv)
  expect_true(is_valid_tbit_repo(env$work_dir, checks = c("git", "tbit")))
})

test_that("tbit_init_repo committed files are tracked in git", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  repo <- git2r::repository(env$work_dir)
  status <- git2r::status(repo)
  # All staged files should have been committed — nothing left

  expect_length(status$staged, 0)
  expect_length(status$unstaged, 0)
})

test_that("tbit_init_repo sets renv to FALSE in project.yaml", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".tbit", "project.yaml"))
  expect_false(cfg$renv)
})

test_that("tbit_init_repo stores tbit_version in project.yaml", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".tbit", "project.yaml"))
  expect_equal(cfg$tbit_version,
               as.character(utils::packageVersion("tbit")))
})


# --- Rollback on failure ------------------------------------------------------

test_that("tbit_init_repo cleans up .tbit on git push failure", {
  env <- setup_init_env()

  local_mocked_bindings(.tbit_git_push = function(...) stop("push failed"))

  expect_error(
    tbit_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # .tbit/ should be cleaned up since it didn't exist before

  expect_false(fs::dir_exists(fs::path(env$work_dir, ".tbit")))
  expect_false(fs::dir_exists(fs::path(env$work_dir, "input_files")))
  expect_false(fs::file_exists(fs::path(env$work_dir, ".gitignore")))
  expect_false(fs::dir_exists(fs::path(env$work_dir, ".git")))
})

test_that("tbit_init_repo cleans up on git commit failure", {
  env <- setup_init_env()

  local_mocked_bindings(.tbit_git_push = function(...) invisible(TRUE))

  # Mock git2r::commit to fail
  mockery::stub(tbit_init_repo, "git2r::commit", function(...) stop("commit failed"))

  expect_error(
    tbit_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "commit failed"
  )

  expect_false(fs::dir_exists(fs::path(env$work_dir, ".tbit")))
  expect_false(fs::dir_exists(fs::path(env$work_dir, "input_files")))
})

test_that("tbit_init_repo does NOT delete pre-existing .tbit on failure", {
  env <- setup_init_env()

  # Pre-create .tbit/ with some content (simulates partial prior state)
  tbit_dir <- fs::path(env$work_dir, ".tbit")
  fs::dir_create(tbit_dir)
  writeLines("existing", fs::path(tbit_dir, "existing_file.txt"))

  local_mocked_bindings(.tbit_git_push = function(...) stop("push failed"))

  expect_error(
    tbit_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # .tbit/ should NOT be deleted because it pre-existed
  expect_true(fs::dir_exists(tbit_dir))
  expect_true(fs::file_exists(fs::path(tbit_dir, "existing_file.txt")))
})

test_that("tbit_init_repo does NOT delete pre-existing input_files on failure", {
  env <- setup_init_env()

  # Pre-create input_files/
  input_dir <- fs::path(env$work_dir, "input_files")
  fs::dir_create(input_dir)
  writeLines("data", fs::path(input_dir, "data.csv"))

  local_mocked_bindings(.tbit_git_push = function(...) stop("push failed"))

  expect_error(
    tbit_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # input_files/ should NOT be deleted
  expect_true(fs::dir_exists(input_dir))
  expect_true(fs::file_exists(fs::path(input_dir, "data.csv")))
})

test_that("tbit_init_repo does NOT delete pre-existing .gitignore on failure", {
  env <- setup_init_env()

  # Pre-create .gitignore
  gitignore <- fs::path(env$work_dir, ".gitignore")
  writeLines("*.log", gitignore)

  local_mocked_bindings(.tbit_git_push = function(...) stop("push failed"))

  expect_error(
    tbit_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # .gitignore should NOT be deleted
  expect_true(fs::file_exists(gitignore))
})

test_that("tbit_init_repo does NOT delete pre-existing .git on failure", {
  env <- setup_init_env()

  # Pre-create a git repo
  git2r::init(env$work_dir)

  local_mocked_bindings(.tbit_git_push = function(...) stop("push failed"))

  # git2r::remote_add will fail because we call init again, but let's mock
  # further down — the git_dir existed check is what matters
  expect_error(
    tbit_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b")
  )

  # .git/ should NOT be deleted
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".git")))
})

test_that("tbit_init_repo success does not trigger cleanup", {
  env <- setup_init_env()

  tbit_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  # Everything should still be there
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".tbit")))
  expect_true(fs::dir_exists(fs::path(env$work_dir, "input_files")))
  expect_true(fs::file_exists(fs::path(env$work_dir, ".gitignore")))
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".git")))
})
