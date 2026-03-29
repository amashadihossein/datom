# Tests for datom_conn S3 class (Phase 4, Chunk 2)

# --- Helper: create a mock S3 client -----------------------------------------
mock_s3_client <- function() {
  list(
    put_object = function(...) NULL,
    get_object = function(...) NULL,
    head_object = function(...) NULL
  )
}


# =============================================================================
# new_datom_conn()
# =============================================================================

test_that("creates a reader connection with required fields", {
  conn <- new_datom_conn(
    project_name = "clinical_data",
    bucket = "my-bucket",
    prefix = "project-alpha/",
    region = "us-east-1",
    s3_client = mock_s3_client(),
    role = "reader"
  )

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$project_name, "clinical_data")
  expect_equal(conn$bucket, "my-bucket")
  expect_equal(conn$prefix, "project-alpha/")
  expect_equal(conn$region, "us-east-1")
  expect_equal(conn$role, "reader")
  expect_null(conn$path)
})

test_that("creates a developer connection with path", {
  dir <- withr::local_tempdir()

  conn <- new_datom_conn(
    project_name = "clinical_data",
    bucket = "my-bucket",
    region = "us-east-1",
    s3_client = mock_s3_client(),
    path = dir,
    role = "developer"
  )

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$role, "developer")
  expect_equal(conn$path, dir)
})

test_that("prefix defaults to NULL", {
  conn <- new_datom_conn(
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
    new_datom_conn(
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
    new_datom_conn(
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
    new_datom_conn(
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
    new_datom_conn(
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
    new_datom_conn(
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
    new_datom_conn(
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
    new_datom_conn(
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
  conn <- new_datom_conn(
    project_name = "p",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  expect_equal(conn$role, "reader")
})

test_that("aborts on invalid role", {
  expect_error(
    new_datom_conn(
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
# is_datom_conn()
# =============================================================================

test_that("is_datom_conn returns TRUE for datom_conn objects", {
  conn <- new_datom_conn(
    project_name = "p",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  expect_true(is_datom_conn(conn))
})

test_that("is_datom_conn returns FALSE for other objects", {
  expect_false(is_datom_conn(list(a = 1)))
  expect_false(is_datom_conn("string"))
  expect_false(is_datom_conn(42))
  expect_false(is_datom_conn(NULL))
})


# =============================================================================
# print.datom_conn()
# =============================================================================

test_that("print.datom_conn outputs key fields", {
  conn <- new_datom_conn(
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

test_that("print.datom_conn shows path for developer", {
  dir <- withr::local_tempdir()

  conn <- new_datom_conn(
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

test_that("print.datom_conn omits prefix when NULL", {
  conn <- new_datom_conn(
    project_name = "proj",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_no_match(combined, "Prefix")
})

test_that("print.datom_conn returns x invisibly", {
  conn <- new_datom_conn(
    project_name = "proj",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  expect_invisible(print(conn))

  result <- withVisible(print(conn))
  expect_false(result$visible)
  expect_s3_class(result$value, "datom_conn")
})

test_that("print.datom_conn does not expose s3_client details", {
  conn <- new_datom_conn(
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
# datom_get_conn() — dispatch
# =============================================================================

test_that("aborts when no arguments provided", {
  expect_error(datom_get_conn(), "path.*bucket")
})

test_that("aborts when both path and bucket provided", {
  expect_error(
    datom_get_conn(path = "some/path", bucket = "b", project_name = "p"),
    "not both"
  )
})

test_that("aborts when both path and project_name provided", {
  expect_error(
    datom_get_conn(path = "some/path", project_name = "p"),
    "not both"
  )
})


# =============================================================================
# datom_get_conn() — developer path (from project.yaml)
# =============================================================================

# --- Helper: create a temp repo with .datom/project.yaml ----------------------
create_test_datom_repo <- function(project_name = "testproj",
                                  bucket = "test-bucket",
                                  prefix = "test-prefix/",
                                  region = "us-east-1",
                                  env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  datom_dir <- fs::path(dir, ".datom")
  fs::dir_create(datom_dir)

  yaml_content <- list(
    project_name = project_name,
    storage = list(
      type = "s3",
      bucket = bucket,
      prefix = prefix,
      region = region,
      credentials = list(
        access_key_env = paste0("DATOM_", toupper(project_name), "_ACCESS_KEY_ID"),
        secret_key_env = paste0("DATOM_", toupper(project_name), "_SECRET_ACCESS_KEY")
      )
    )
  )

  yaml::write_yaml(yaml_content, fs::path(datom_dir, "project.yaml"))
  dir
}


test_that("developer path reads project.yaml and creates connection", {
  dir <- create_test_datom_repo(project_name = "myproj", bucket = "my-bucket")

  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "fake_key",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = "ghp_fake"
  )

  mockery::stub(datom_get_conn, ".datom_s3_client", mock_s3_client)

  conn <- datom_get_conn(path = dir)

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$project_name, "myproj")
  expect_equal(conn$bucket, "my-bucket")
  expect_equal(conn$role, "developer")
  expect_equal(conn$path, as.character(fs::path_abs(dir)))
})

test_that("developer path falls back to reader role without GITHUB_PAT", {
  dir <- create_test_datom_repo(project_name = "myproj", bucket = "my-bucket")

  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "fake_key",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = NA
  )

  mockery::stub(datom_get_conn, ".datom_s3_client", mock_s3_client)

  conn <- datom_get_conn(path = dir)

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$role, "reader")
  expect_null(conn$path)
})

test_that("developer path reads prefix from project.yaml", {
  dir <- create_test_datom_repo(prefix = "alpha/beta/")

  withr::local_envvar(
    DATOM_TESTPROJ_ACCESS_KEY_ID = "k",
    DATOM_TESTPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )

  mockery::stub(datom_get_conn, ".datom_s3_client", mock_s3_client)

  conn <- datom_get_conn(path = dir)
  expect_equal(conn$prefix, "alpha/beta/")
})

test_that("developer path reads region from project.yaml", {
  dir <- create_test_datom_repo(region = "eu-west-1")

  withr::local_envvar(
    DATOM_TESTPROJ_ACCESS_KEY_ID = "k",
    DATOM_TESTPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )

  mockery::stub(datom_get_conn, ".datom_s3_client", mock_s3_client)

  conn <- datom_get_conn(path = dir)
  expect_equal(conn$region, "eu-west-1")
})

test_that("developer path aborts when project.yaml is missing", {
  dir <- withr::local_tempdir()

  expect_error(datom_get_conn(path = dir), "No datom config")
})

test_that("developer path aborts when project_name missing from yaml", {
  dir <- withr::local_tempdir()
  datom_dir <- fs::path(dir, ".datom")
  fs::dir_create(datom_dir)
  yaml::write_yaml(
    list(storage = list(bucket = "b")),
    fs::path(datom_dir, "project.yaml")
  )

  expect_error(datom_get_conn(path = dir), "project_name")
})

test_that("developer path aborts when storage section missing from yaml", {
  dir <- withr::local_tempdir()
  datom_dir <- fs::path(dir, ".datom")
  fs::dir_create(datom_dir)
  yaml::write_yaml(
    list(project_name = "p"),
    fs::path(datom_dir, "project.yaml")
  )

  expect_error(datom_get_conn(path = dir), "storage")
})

test_that("developer path aborts when bucket missing from yaml", {
  dir <- withr::local_tempdir()
  datom_dir <- fs::path(dir, ".datom")
  fs::dir_create(datom_dir)
  yaml::write_yaml(
    list(project_name = "p", storage = list(region = "us-east-1")),
    fs::path(datom_dir, "project.yaml")
  )

  expect_error(datom_get_conn(path = dir), "bucket")
})

test_that("developer path aborts when credentials missing", {
  dir <- create_test_datom_repo(project_name = "myproj")

  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = NA,
    DATOM_MYPROJ_SECRET_ACCESS_KEY = NA,
    GITHUB_PAT = NA
  )

  expect_error(datom_get_conn(path = dir), "ACCESS_KEY_ID")
})


# =============================================================================
# datom_get_conn() — reader path (direct params)
# =============================================================================

test_that("reader path creates connection from direct params", {
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "fake_key",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "fake_secret"
  )

  mockery::stub(datom_get_conn, ".datom_s3_client", mock_s3_client)

  conn <- datom_get_conn(bucket = "reader-bucket", project_name = "myproj")

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$bucket, "reader-bucket")
  expect_equal(conn$project_name, "myproj")
  expect_equal(conn$role, "reader")
  expect_null(conn$path)
  expect_null(conn$prefix)
})

test_that("reader path accepts prefix", {
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "k",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "s"
  )

  mockery::stub(datom_get_conn, ".datom_s3_client", mock_s3_client)

  conn <- datom_get_conn(bucket = "b", prefix = "data/", project_name = "myproj")

  expect_equal(conn$prefix, "data/")
})

test_that("reader path aborts when bucket is missing", {
  expect_error(
    datom_get_conn(project_name = "myproj"),
    "bucket.*required"
  )
})

test_that("reader path aborts when project_name is missing", {
  expect_error(
    datom_get_conn(bucket = "b"),
    "project_name.*required"
  )
})

test_that("reader path aborts when credentials missing", {
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = NA,
    DATOM_MYPROJ_SECRET_ACCESS_KEY = NA
  )

  expect_error(
    datom_get_conn(bucket = "b", project_name = "myproj"),
    "ACCESS_KEY_ID"
  )
})

test_that("reader path uses AWS_DEFAULT_REGION env var", {
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "k",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "s",
    AWS_DEFAULT_REGION = "ap-southeast-1"
  )

  mockery::stub(datom_get_conn, ".datom_s3_client", mock_s3_client)

  conn <- datom_get_conn(bucket = "b", project_name = "myproj")

  expect_equal(conn$region, "ap-southeast-1")
})


# =============================================================================
# datom_init_repo()
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
    DATOM_TESTPROJ_ACCESS_KEY_ID = "fake_key",
    DATOM_TESTPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = "ghp_fake"
  )

  # Stub S3 operations (datom_init_repo now pushes to S3 after git)
  local_mocked_bindings(
    .datom_s3_client = function(...) list(put_object = function(...) list()),
    .datom_s3_write_json = function(...) invisible(TRUE),
    .datom_s3_exists = function(...) FALSE,
    .env = env
  )

  list(bare_dir = bare_dir, work_dir = work_dir)
}


# --- Input validation ---------------------------------------------------------

test_that("datom_init_repo aborts on invalid project_name", {
  expect_error(datom_init_repo(project_name = "", remote_url = "x", bucket = "b"),
               "name")
})

test_that("datom_init_repo aborts on invalid remote_url", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "k",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )
  expect_error(datom_init_repo(path = dir, project_name = "myproj",
                               remote_url = "", bucket = "b"),
               "remote_url")
})

test_that("datom_init_repo aborts on invalid bucket", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "k",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )
  expect_error(datom_init_repo(path = dir, project_name = "myproj",
                               remote_url = "https://github.com/x/y.git",
                               bucket = ""),
               "bucket")
})

test_that("datom_init_repo aborts on invalid prefix", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "k",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )
  expect_error(datom_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b",
                               prefix = 123),
               "prefix")
})

test_that("datom_init_repo aborts on invalid max_file_size_gb", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "k",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )
  expect_error(datom_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b",
                               max_file_size_gb = -1),
               "max_file_size_gb")
  expect_error(datom_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b",
                               max_file_size_gb = "big"),
               "max_file_size_gb")
})

test_that("datom_init_repo aborts when credentials are missing", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = NA,
    DATOM_MYPROJ_SECRET_ACCESS_KEY = NA,
    GITHUB_PAT = NA
  )
  expect_error(datom_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b"),
               "ACCESS_KEY_ID")
})

test_that("datom_init_repo aborts when GITHUB_PAT is missing", {
  dir <- withr::local_tempdir()
  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "k",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = NA
  )
  expect_error(datom_init_repo(path = dir, project_name = "myproj",
                               remote_url = "url", bucket = "b"),
               "GITHUB_PAT")
})

test_that("datom_init_repo aborts if .datom already exists", {
  env <- setup_init_env()
  fs::dir_create(fs::path(env$work_dir, ".datom"))
  yaml::write_yaml(list(project_name = "x"),
                    fs::path(env$work_dir, ".datom", "project.yaml"))

  expect_error(datom_init_repo(path = env$work_dir, project_name = "testproj",
                               remote_url = env$bare_dir, bucket = "b"),
               "already exists")
})


# --- Happy path ---------------------------------------------------------------

test_that("datom_init_repo creates .datom directory", {
  env <- setup_init_env()

  result <- datom_init_repo(
    path = env$work_dir,
    project_name = "testproj",
    remote_url = env$bare_dir,
    bucket = "my-bucket"
  )

  expect_true(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})

test_that("datom_init_repo creates input_files directory", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  expect_true(fs::dir_exists(fs::path(env$work_dir, "input_files")))
})

test_that("datom_init_repo creates project.yaml with correct fields", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "my-bucket",
                  prefix = "data/", region = "eu-west-1",
                  max_file_size_gb = 500)

  yaml_path <- fs::path(env$work_dir, ".datom", "project.yaml")
  expect_true(fs::file_exists(yaml_path))

  cfg <- yaml::read_yaml(yaml_path)
  expect_equal(cfg$project_name, "testproj")
  expect_equal(cfg$storage$type, "s3")
  expect_equal(cfg$storage$bucket, "my-bucket")
  expect_equal(cfg$storage$prefix, "data/")
  expect_equal(cfg$storage$region, "eu-west-1")
  expect_equal(cfg$storage$max_file_size_gb, 500)
  expect_equal(cfg$storage$credentials$access_key_env,
               "DATOM_TESTPROJ_ACCESS_KEY_ID")
  expect_equal(cfg$storage$credentials$secret_key_env,
               "DATOM_TESTPROJ_SECRET_ACCESS_KEY")
})

test_that("datom_init_repo creates routing.json", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  routing_path <- fs::path(env$work_dir, ".datom", "routing.json")
  expect_true(fs::file_exists(routing_path))

  routing <- jsonlite::read_json(routing_path)
  expect_equal(routing$methods$r$default, "datom::datom_read")
  expect_equal(routing$methods$python$default, "datom.read")
})

test_that("datom_init_repo creates manifest.json", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  manifest_path <- fs::path(env$work_dir, ".datom", "manifest.json")
  expect_true(fs::file_exists(manifest_path))

  manifest <- jsonlite::read_json(manifest_path)
  expect_equal(manifest$summary$total_tables, 0)
  expect_equal(manifest$summary$total_size_bytes, 0)
  expect_equal(manifest$summary$total_versions, 0)
})

test_that("datom_init_repo creates .gitignore with input_files/", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  gitignore <- readLines(fs::path(env$work_dir, ".gitignore"))
  expect_true("input_files/" %in% gitignore)
  expect_true(".DS_Store" %in% gitignore)
  expect_true("*.parquet" %in% gitignore)
})

test_that("datom_init_repo initializes git with remote", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  expect_true(fs::dir_exists(fs::path(env$work_dir, ".git")))

  repo <- git2r::repository(env$work_dir)
  remotes <- git2r::remotes(repo)
  expect_true("origin" %in% remotes)
  expect_equal(git2r::remote_url(repo, remote = "origin"), env$bare_dir)
})

test_that("datom_init_repo makes initial commit", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  repo <- git2r::repository(env$work_dir)
  log <- git2r::commits(repo)
  expect_length(log, 1)
  expect_match(log[[1]]$message, "Initialize datom repository")
})

test_that("datom_init_repo pushes to remote", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  # Verify bare repo has the commit
  bare_repo <- git2r::repository(env$bare_dir)
  bare_log <- git2r::commits(bare_repo)
  expect_length(bare_log, 1)
  expect_match(bare_log[[1]]$message, "Initialize datom repository")
})

test_that("datom_init_repo returns invisible TRUE", {
  env <- setup_init_env()

  result <- datom_init_repo(path = env$work_dir, project_name = "testproj",
                            remote_url = env$bare_dir, bucket = "b")

  expect_true(result)
  expect_invisible(datom_init_repo(
    path = withr::local_tempdir(),
    project_name = "testproj",
    remote_url = env$bare_dir,
    bucket = "b"
  ))
})

test_that("datom_init_repo uses AWS_DEFAULT_REGION fallback", {
  env <- setup_init_env()
  withr::local_envvar(AWS_DEFAULT_REGION = "ap-northeast-1")

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$storage$region, "ap-northeast-1")
})

test_that("datom_init_repo defaults region to us-east-1", {
  env <- setup_init_env()
  withr::local_envvar(AWS_DEFAULT_REGION = NA)

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$storage$region, "us-east-1")
})

test_that("datom_init_repo handles prefix = NULL", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  # YAML writes NULL as missing key
  expect_true(is.null(cfg$storage$prefix))
})

test_that("datom_init_repo normalizes project_name for cred env vars", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- withr::local_tempdir()

  withr::local_envvar(
    DATOM_MY_DATA_ACCESS_KEY_ID = "k",
    DATOM_MY_DATA_SECRET_ACCESS_KEY = "s",
    GITHUB_PAT = "ghp_x"
  )

  datom_init_repo(path = work_dir, project_name = "my-data",
                  remote_url = bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$storage$credentials$access_key_env,
               "DATOM_MY_DATA_ACCESS_KEY_ID")
  expect_equal(cfg$storage$credentials$secret_key_env,
               "DATOM_MY_DATA_SECRET_ACCESS_KEY")
})

test_that("datom_init_repo passes is_valid_datom_repo checks", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  # Should pass git + datom checks (not renv — we don't init renv)
  expect_true(is_valid_datom_repo(env$work_dir, checks = c("git", "datom")))
})

test_that("datom_init_repo committed files are tracked in git", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  repo <- git2r::repository(env$work_dir)
  status <- git2r::status(repo)
  # All staged files should have been committed — nothing left

  expect_length(status$staged, 0)
  expect_length(status$unstaged, 0)
})

test_that("datom_init_repo sets renv to FALSE in project.yaml", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_false(cfg$renv)
})

test_that("datom_init_repo stores datom_version in project.yaml", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$datom_version,
               as.character(utils::packageVersion("datom")))
})

test_that("datom_init_repo creates README.md", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  readme_path <- fs::path(env$work_dir, "README.md")
  expect_true(fs::file_exists(readme_path))
})

test_that("datom_init_repo README.md contains project name", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "my-bucket",
                  prefix = "study/")

  readme <- readLines(fs::path(env$work_dir, "README.md"))
  readme_text <- paste(readme, collapse = "\n")

  expect_match(readme_text, "# testproj", fixed = TRUE)
  expect_match(readme_text, "my-bucket", fixed = TRUE)
  expect_match(readme_text, "study/", fixed = TRUE)
  expect_match(readme_text, "DATOM_TESTPROJ_ACCESS_KEY_ID", fixed = TRUE)
})

test_that("datom_init_repo commits README.md to git", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  repo <- git2r::repository(env$work_dir)
  status <- git2r::status(repo)
  # README.md should be committed, not untracked
  untracked <- unlist(status$untracked)
  expect_false("README.md" %in% untracked)
})


# --- Rollback on failure ------------------------------------------------------

test_that("datom_init_repo cleans up .datom on git push failure", {
  env <- setup_init_env()

  local_mocked_bindings(.datom_git_push = function(...) stop("push failed"))

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # .datom/ should be cleaned up since it didn't exist before

  expect_false(fs::dir_exists(fs::path(env$work_dir, ".datom")))
  expect_false(fs::dir_exists(fs::path(env$work_dir, "input_files")))
  expect_false(fs::file_exists(fs::path(env$work_dir, ".gitignore")))
  expect_false(fs::dir_exists(fs::path(env$work_dir, ".git")))
})

test_that("datom_init_repo cleans up on git commit failure", {
  env <- setup_init_env()

  local_mocked_bindings(.datom_git_push = function(...) invisible(TRUE))

  # Mock git2r::commit to fail
  mockery::stub(datom_init_repo, "git2r::commit", function(...) stop("commit failed"))

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "commit failed"
  )

  expect_false(fs::dir_exists(fs::path(env$work_dir, ".datom")))
  expect_false(fs::dir_exists(fs::path(env$work_dir, "input_files")))
})

test_that("datom_init_repo does NOT delete pre-existing .datom on failure", {
  env <- setup_init_env()

  # Pre-create .datom/ with some content (simulates partial prior state)
  datom_dir <- fs::path(env$work_dir, ".datom")
  fs::dir_create(datom_dir)
  writeLines("existing", fs::path(datom_dir, "existing_file.txt"))

  local_mocked_bindings(.datom_git_push = function(...) stop("push failed"))

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # .datom/ should NOT be deleted because it pre-existed
  expect_true(fs::dir_exists(datom_dir))
  expect_true(fs::file_exists(fs::path(datom_dir, "existing_file.txt")))
})

test_that("datom_init_repo does NOT delete pre-existing input_files on failure", {
  env <- setup_init_env()

  # Pre-create input_files/
  input_dir <- fs::path(env$work_dir, "input_files")
  fs::dir_create(input_dir)
  writeLines("data", fs::path(input_dir, "data.csv"))

  local_mocked_bindings(.datom_git_push = function(...) stop("push failed"))

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # input_files/ should NOT be deleted
  expect_true(fs::dir_exists(input_dir))
  expect_true(fs::file_exists(fs::path(input_dir, "data.csv")))
})

test_that("datom_init_repo does NOT delete pre-existing .gitignore on failure", {
  env <- setup_init_env()

  # Pre-create .gitignore
  gitignore <- fs::path(env$work_dir, ".gitignore")
  writeLines("*.log", gitignore)

  local_mocked_bindings(.datom_git_push = function(...) stop("push failed"))

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # .gitignore should NOT be deleted
  expect_true(fs::file_exists(gitignore))
})

test_that("datom_init_repo does NOT delete pre-existing .git on failure", {
  env <- setup_init_env()

  # Pre-create a git repo
  git2r::init(env$work_dir)

  local_mocked_bindings(.datom_git_push = function(...) stop("push failed"))

  # git2r::remote_add will fail because we call init again, but let's mock
  # further down — the git_dir existed check is what matters
  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b")
  )

  # .git/ should NOT be deleted
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".git")))
})

test_that("datom_init_repo success does not trigger cleanup", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  remote_url = env$bare_dir, bucket = "b")

  # Everything should still be there
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".datom")))
  expect_true(fs::dir_exists(fs::path(env$work_dir, "input_files")))
  expect_true(fs::file_exists(fs::path(env$work_dir, ".gitignore")))
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".git")))
})

test_that("datom_init_repo cleans up parent directory when it was newly created", {
  env <- setup_init_env()

  # Use a sub-path that doesn't exist yet (realistic: user says path = "my_proj")
  new_path <- fs::path(env$work_dir, "study_001_data")
  expect_false(fs::dir_exists(new_path))

  local_mocked_bindings(.datom_git_push = function(...) stop("push failed"))

  expect_error(
    datom_init_repo(path = new_path, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # The parent directory itself should also be removed
  expect_false(fs::dir_exists(new_path))
})

test_that("datom_init_repo does NOT remove pre-existing parent dir on failure", {
  env <- setup_init_env()

  # work_dir already exists (from setup_init_env)
  expect_true(fs::dir_exists(env$work_dir))

  local_mocked_bindings(.datom_git_push = function(...) stop("push failed"))

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    remote_url = env$bare_dir, bucket = "b"),
    "push failed"
  )

  # Parent dir should remain because it pre-existed
  expect_true(fs::dir_exists(env$work_dir))
})

test_that("datom_init_repo pushes routing.json and manifest.json to S3", {
  env <- setup_init_env()

  s3_keys_written <- character()

  # Override the S3 stubs from setup_init_env to capture writes
  local_mocked_bindings(
    .datom_s3_write_json = function(conn, s3_key, data) {
      s3_keys_written <<- c(s3_keys_written, s3_key)
      invisible(TRUE)
    }
  )

  datom_init_repo(
    path = env$work_dir,
    project_name = "testproj",
    remote_url = env$bare_dir,
    bucket = "my-bucket"
  )

  expect_true(".metadata/routing.json" %in% s3_keys_written)
  expect_true(".metadata/manifest.json" %in% s3_keys_written)
})

test_that("datom_init_repo succeeds even if S3 upload fails", {
  env <- setup_init_env()

  # Override to make S3 fail
  local_mocked_bindings(
    .datom_s3_client = function(...) stop("S3 unavailable")
  )

  # Should succeed (git push worked, S3 failure is just a warning)
  expect_no_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      remote_url = env$bare_dir,
      bucket = "my-bucket"
    )
  )

  # Files should still be created locally
  expect_true(fs::file_exists(fs::path(env$work_dir, ".datom", "routing.json")))
  expect_true(fs::file_exists(fs::path(env$work_dir, ".datom", "manifest.json")))
})


# --- S3 namespace safety check (Phase 7) -------------------------------------

test_that("datom_init_repo aborts when S3 namespace is occupied", {
  env <- setup_init_env()

  # Override .datom_s3_exists to report namespace is occupied
  local_mocked_bindings(
    .datom_s3_exists = function(conn, s3_key) {
      grepl("manifest\\.json", s3_key)
    },
    .datom_s3_read_json = function(conn, s3_key) {
      list(project_name = "EXISTING_PROJECT", tables = list())
    }
  )

  expect_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      remote_url = env$bare_dir,
      bucket = "b"
    ),
    "already occupied"
  )

  # Nothing should have been created
  expect_false(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})

test_that("datom_init_repo proceeds when .force = TRUE despite occupied namespace", {
  env <- setup_init_env()

  # Override .datom_s3_exists to report namespace is occupied
  local_mocked_bindings(
    .datom_s3_exists = function(conn, s3_key) {
      grepl("manifest\\.json", s3_key)
    },
    .datom_s3_read_json = function(conn, s3_key) {
      list(project_name = "EXISTING_PROJECT", tables = list())
    },
    .datom_s3_write_json = function(...) invisible(TRUE)
  )

  result <- datom_init_repo(
    path = env$work_dir,
    project_name = "testproj",
    remote_url = env$bare_dir,
    bucket = "b",
    .force = TRUE
  )

  expect_true(result)
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})

test_that("datom_init_repo manifest.json includes project_name", {
  env <- setup_init_env()

  datom_init_repo(
    path = env$work_dir,
    project_name = "testproj",
    remote_url = env$bare_dir,
    bucket = "b"
  )

  manifest <- jsonlite::read_json(
    fs::path(env$work_dir, ".datom", "manifest.json")
  )
  expect_equal(manifest$project_name, "testproj")
})

test_that("datom_init_repo warns but continues when S3 connectivity fails during namespace check", {
  env <- setup_init_env()

  # .datom_s3_client will work but .datom_s3_exists will fail with network error
  local_mocked_bindings(
    .datom_s3_exists = function(conn, s3_key) stop("Network error"),
    .datom_s3_write_json = function(...) invisible(TRUE)
  )

  # Should succeed — connectivity failure during namespace check is a warning, not fatal
  expect_no_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      remote_url = env$bare_dir,
      bucket = "b"
    )
  )

  expect_true(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})


# =============================================================================
# endpoint parameter (Phase 8, Chunk 3)
# =============================================================================

test_that("new_datom_conn stores endpoint when provided", {
  conn <- new_datom_conn(
    project_name = "p",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client(),
    endpoint = "https://my-access-point.s3-accesspoint.us-east-1.amazonaws.com"
  )

  expect_equal(
    conn$endpoint,
    "https://my-access-point.s3-accesspoint.us-east-1.amazonaws.com"
  )
})

test_that("new_datom_conn endpoint defaults to NULL", {
  conn <- new_datom_conn(
    project_name = "p",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  expect_null(conn$endpoint)
})

test_that("print.datom_conn shows endpoint when non-NULL", {
  conn <- new_datom_conn(
    project_name = "proj",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client(),
    endpoint = "https://custom-endpoint.example.com"
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_match(combined, "Endpoint")
  expect_match(combined, "custom-endpoint.example.com", fixed = TRUE)
})

test_that("print.datom_conn omits endpoint when NULL", {
  conn <- new_datom_conn(
    project_name = "proj",
    bucket = "b",
    region = "us-east-1",
    s3_client = mock_s3_client()
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_no_match(combined, "Endpoint")
})

test_that(".datom_s3_client passes endpoint to paws config", {
  skip_if_not_installed("paws.storage")

  withr::local_envvar(
    DATOM_PROJ_ACCESS_KEY_ID = "test-key",
    DATOM_PROJ_SECRET_ACCESS_KEY = "test-secret"
  )

  creds <- list(
    access_key_env = "DATOM_PROJ_ACCESS_KEY_ID",
    secret_key_env = "DATOM_PROJ_SECRET_ACCESS_KEY"
  )

  # With endpoint
  client <- .datom_s3_client(
    creds,
    region = "us-east-1",
    endpoint = "https://custom.s3.endpoint.com"
  )
  expect_true(is.list(client))

  # Without endpoint (default NULL) — should still create valid client

  client_default <- .datom_s3_client(creds, region = "us-east-1")
  expect_true(is.list(client_default))
})

test_that("datom_get_conn forwards endpoint to developer path", {
  dir <- create_test_datom_repo(project_name = "myproj")

  withr::local_envvar(
    DATOM_MYPROJ_ACCESS_KEY_ID = "fake_key",
    DATOM_MYPROJ_SECRET_ACCESS_KEY = "fake_secret",
    GITHUB_PAT = "ghp_fake"
  )

  captured_endpoint <- NULL
  local_mocked_bindings(
    .datom_s3_client = function(credentials, region = "us-east-1",
                                endpoint = NULL) {
      captured_endpoint <<- endpoint
      mock_s3_client()
    }
  )

  conn <- datom_get_conn(
    path = dir,
    endpoint = "https://my-endpoint.com"
  )

  expect_equal(conn$endpoint, "https://my-endpoint.com")
  expect_equal(captured_endpoint, "https://my-endpoint.com")
})

test_that("datom_get_conn forwards endpoint to reader path", {
  withr::local_envvar(
    DATOM_PROJ_ACCESS_KEY_ID = "fake_key",
    DATOM_PROJ_SECRET_ACCESS_KEY = "fake_secret"
  )

  captured_endpoint <- NULL
  local_mocked_bindings(
    .datom_s3_client = function(credentials, region = "us-east-1",
                                endpoint = NULL) {
      captured_endpoint <<- endpoint
      mock_s3_client()
    }
  )

  conn <- datom_get_conn(
    bucket = "b",
    project_name = "proj",
    endpoint = "https://reader-endpoint.com"
  )

  expect_equal(conn$endpoint, "https://reader-endpoint.com")
  expect_equal(captured_endpoint, "https://reader-endpoint.com")
})

test_that("datom_get_conn endpoint defaults to NULL when not specified", {
  withr::local_envvar(
    DATOM_PROJ_ACCESS_KEY_ID = "fake_key",
    DATOM_PROJ_SECRET_ACCESS_KEY = "fake_secret"
  )

  captured_endpoint <- "sentinel"
  local_mocked_bindings(
    .datom_s3_client = function(credentials, region = "us-east-1",
                                endpoint = NULL) {
      captured_endpoint <<- endpoint
      mock_s3_client()
    }
  )

  conn <- datom_get_conn(bucket = "b", project_name = "proj")

  expect_null(conn$endpoint)
  expect_null(captured_endpoint)
})

test_that("mock_datom_conn includes endpoint field as NULL", {
  conn <- mock_datom_conn(mock_s3_client())
  expect_true("endpoint" %in% names(conn))
  expect_null(conn$endpoint)
})


# --- datom_clone() -------------------------------------------------------------

test_that("datom_clone rejects empty remote_url", {
  expect_error(datom_clone(remote_url = "", path = "x"), "remote_url")
})

test_that("datom_clone rejects NA remote_url", {
  expect_error(datom_clone(remote_url = NA_character_, path = "x"), "remote_url")
})

test_that("datom_clone rejects empty path", {
  expect_error(datom_clone(remote_url = "https://x.git", path = ""), "path")
})

test_that("datom_clone rejects non-empty target directory", {
  withr::with_tempdir({
    fs::dir_create("existing")
    writeLines("file", fs::path("existing", "README.md"))
    expect_error(
      datom_clone(remote_url = "https://x.git", path = "existing"),
      "not empty"
    )
  })
})

test_that("datom_clone aborts if cloned repo is not a datom repo", {
  withr::with_tempdir({
    # Create a bare git repo without .datom/project.yaml
    bare_dir <- withr::local_tempdir()
    bare_repo <- git2r::init(bare_dir, bare = TRUE)

    # Create a working repo and push to bare
    work_dir <- withr::local_tempdir()
    work_repo <- git2r::init(work_dir)
    git2r::config(work_repo, user.name = "Test", user.email = "test@test.com")
    writeLines("init", fs::path(work_dir, "README.md"))
    git2r::add(work_repo, "README.md")
    git2r::commit(work_repo, "Initial commit")
    git2r::remote_add(work_repo, name = "origin", url = bare_dir)
    git2r::push(work_repo, name = "origin",
                refspec = "refs/heads/master", set_upstream = TRUE)

    expect_error(
      datom_clone(remote_url = bare_dir, path = "clone_target"),
      "not a datom repository"
    )
  })
})

test_that("datom_clone clones and returns a datom_conn", {
  withr::with_tempdir({
    # Set up env vars needed by datom_get_conn
    withr::local_envvar(
      GITHUB_PAT = "fake-pat",
      DATOM_MYPROJ_ACCESS_KEY_ID = "fakekey",
      DATOM_MYPROJ_SECRET_ACCESS_KEY = "fakesecret"
    )

    # Create a bare repo with datom structure
    bare_dir <- withr::local_tempdir()
    git2r::init(bare_dir, bare = TRUE)

    work_dir <- withr::local_tempdir()
    work_repo <- git2r::init(work_dir)
    git2r::config(work_repo, user.name = "Test", user.email = "test@test.com")

    # Create .datom/project.yaml
    fs::dir_create(fs::path(work_dir, ".datom"))
    yaml::write_yaml(
      list(
        project_name = "MYPROJ",
        storage = list(
          bucket = "test-bucket",
          prefix = NULL,
          region = "us-east-1",
          credentials = list(
            access_key_env = "DATOM_MYPROJ_ACCESS_KEY_ID",
            secret_key_env = "DATOM_MYPROJ_SECRET_ACCESS_KEY"
          )
        )
      ),
      fs::path(work_dir, ".datom", "project.yaml")
    )

    git2r::add(work_repo, ".datom/project.yaml")
    git2r::commit(work_repo, "Init datom")
    git2r::remote_add(work_repo, name = "origin", url = bare_dir)
    git2r::push(work_repo, name = "origin",
                refspec = "refs/heads/master", set_upstream = TRUE)

    # Mock the S3 client creation
    local_mocked_bindings(
      .datom_s3_client = function(...) list(fake = TRUE)
    )

    conn <- datom_clone(remote_url = bare_dir, path = "clone_target")

    expect_s3_class(conn, "datom_conn")
    expect_equal(conn$project_name, "MYPROJ")
    expect_equal(conn$bucket, "test-bucket")
    expect_true(fs::dir_exists("clone_target/.datom"))
    expect_true(fs::file_exists("clone_target/.datom/project.yaml"))
  })
})

test_that("datom_clone aborts on clone failure", {
  withr::with_tempdir({
    expect_error(
      datom_clone(remote_url = "https://example.com/no-such-repo.git",
                 path = "target"),
      "Failed to clone"
    )
  })
})
