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
    root = "my-bucket",
    prefix = "project-alpha/",
    region = "us-east-1",
    client = mock_s3_client(),
    role = "reader"
  )

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$project_name, "clinical_data")
  expect_equal(conn$root, "my-bucket")
  expect_equal(conn$prefix, "project-alpha/")
  expect_equal(conn$region, "us-east-1")
  expect_equal(conn$role, "reader")
  expect_null(conn$path)
})

test_that("creates a developer connection with path", {
  dir <- withr::local_tempdir()

  conn <- new_datom_conn(
    project_name = "clinical_data",
    root = "my-bucket",
    region = "us-east-1",
    client = mock_s3_client(),
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
    root = "b",
    region = "us-east-1",
    client = mock_s3_client(),
    role = "reader"
  )

  expect_null(conn$prefix)
})

test_that("developer requires path", {
  expect_error(
    new_datom_conn(
      project_name = "proj",
      root = "b",
      region = "us-east-1",
      client = mock_s3_client(),
      role = "developer"
    ),
    "path"
  )
})

test_that("aborts on empty project_name", {
  expect_error(
    new_datom_conn(
      project_name = "",
      root = "b",
      region = "us-east-1",
      client = mock_s3_client()
    ),
    "project_name"
  )
})

test_that("aborts on NA project_name", {
  expect_error(
    new_datom_conn(
      project_name = NA_character_,
      root = "b",
      region = "us-east-1",
      client = mock_s3_client()
    ),
    "project_name"
  )
})

test_that("aborts on empty root", {
  expect_error(
    new_datom_conn(
      project_name = "p",
      root = "",
      region = "us-east-1",
      client = mock_s3_client()
    ),
    "root"
  )
})

test_that("aborts on empty region", {
  expect_error(
    new_datom_conn(
      project_name = "p",
      root = "b",
      region = "",
      client = mock_s3_client()
    ),
    "region"
  )
})

test_that("aborts on non-string prefix", {
  expect_error(
    new_datom_conn(
      project_name = "p",
      root = "b",
      prefix = 123,
      region = "us-east-1",
      client = mock_s3_client()
    ),
    "prefix"
  )
})

test_that("aborts on non-string path", {
  expect_error(
    new_datom_conn(
      project_name = "p",
      root = "b",
      region = "us-east-1",
      client = mock_s3_client(),
      path = 123,
      role = "developer"
    ),
    "path"
  )
})

test_that("role defaults to reader", {
  conn <- new_datom_conn(
    project_name = "p",
    root = "b",
    region = "us-east-1",
    client = mock_s3_client()
  )

  expect_equal(conn$role, "reader")
})

test_that("aborts on invalid role", {
  expect_error(
    new_datom_conn(
      project_name = "p",
      root = "b",
      region = "us-east-1",
      client = mock_s3_client(),
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
    root = "b",
    region = "us-east-1",
    client = mock_s3_client()
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
    root = "my-bucket",
    prefix = "proj/",
    region = "us-east-1",
    client = mock_s3_client(),
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
    root = "b",
    region = "us-east-1",
    client = mock_s3_client(),
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
    root = "b",
    region = "us-east-1",
    client = mock_s3_client()
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_no_match(combined, "Prefix")
})

test_that("print.datom_conn shows 'Governance: not attached' when gov_root is NULL", {
  conn <- new_datom_conn(
    project_name = "proj",
    root = "b",
    region = "us-east-1",
    client = mock_s3_client()
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_match(combined, "Governance: not attached", fixed = TRUE)
  expect_no_match(combined, "Gov root")
})

test_that("print.datom_conn shows gov fields and not the not-attached line when gov_root is set", {
  conn <- new_datom_conn(
    project_name = "proj",
    root = "b",
    region = "us-east-1",
    client = mock_s3_client(),
    gov_root = "gov-bucket",
    gov_prefix = "g/"
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_match(combined, "Gov root", fixed = TRUE)
  expect_no_match(combined, "Governance: not attached", fixed = TRUE)
})

test_that("print.datom_conn returns x invisibly", {
  conn <- new_datom_conn(
    project_name = "proj",
    root = "b",
    region = "us-east-1",
    client = mock_s3_client()
  )

  expect_invisible(print(conn))

  result <- withVisible(print(conn))
  expect_false(result$visible)
  expect_s3_class(result$value, "datom_conn")
})

test_that("print.datom_conn does not expose client details", {
  conn <- new_datom_conn(
    project_name = "proj",
    root = "b",
    region = "us-east-1",
    client = mock_s3_client()
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_no_match(combined, "put_object")
  expect_no_match(combined, "get_object")
})


# =============================================================================
# datom_get_conn() — dispatch
# =============================================================================

test_that("aborts when store is NULL", {
  expect_error(datom_get_conn(), "store.*required")
})

test_that("aborts when store is not a datom_store", {
  expect_error(
    datom_get_conn(store = list(a = 1), project_name = "p"),
    "datom_store"
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
      governance = list(
        type = "s3",
        root = bucket,
        prefix = prefix,
        region = region
      ),
      data = list(
        type = "s3",
        root = bucket,
        prefix = prefix,
        region = region
      ),
      max_file_size_gb = 1000
    ),
    repos = list(
      data = list(remote_url = "https://github.com/test/repo.git"),
      governance = list(remote_url = NULL, local_path = NULL)
    )
  )

  yaml::write_yaml(yaml_content, fs::path(datom_dir, "project.yaml"))
  dir
}


test_that("developer path reads project.yaml and creates connection", {
  dir <- create_test_datom_repo(project_name = "myproj", bucket = "my-bucket")

  comp <- datom_store_s3(bucket = "my-bucket", access_key = "fake_key",
                         secret_key = "fake_secret", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_fake",
                       data_repo_url = "https://github.com/test/repo.git",
                       validate = FALSE)

  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  conn <- datom_get_conn(path = dir, store = store)

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$project_name, "myproj")
  expect_equal(conn$root, "my-bucket")
  expect_equal(conn$role, "developer")
  expect_equal(conn$path, as.character(fs::path_abs(dir)))
})

test_that("developer path uses reader role when store is reader", {
  dir <- create_test_datom_repo(project_name = "myproj", bucket = "my-bucket")

  comp <- datom_store_s3(bucket = "my-bucket", access_key = "fake_key",
                         secret_key = "fake_secret", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  conn <- datom_get_conn(path = dir, store = store)

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$role, "reader")
  expect_null(conn$path)
})

test_that("developer path uses prefix from store", {
  dir <- create_test_datom_repo(prefix = "alpha/beta/")

  comp <- datom_store_s3(bucket = "test-bucket", prefix = "alpha/beta/",
                         access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://github.com/test/repo.git",
                       validate = FALSE)

  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  conn <- datom_get_conn(path = dir, store = store)
  expect_equal(conn$prefix, "alpha/beta/")
})

test_that("developer path uses region from store", {
  dir <- create_test_datom_repo(region = "eu-west-1")

  comp <- datom_store_s3(bucket = "test-bucket", prefix = "test-prefix/",
                         region = "eu-west-1", access_key = "k",
                         secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://github.com/test/repo.git",
                       validate = FALSE)

  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  conn <- datom_get_conn(path = dir, store = store)
  expect_equal(conn$region, "eu-west-1")
})

test_that("developer path aborts when project.yaml is missing", {
  dir <- withr::local_tempdir()
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  expect_error(datom_get_conn(path = dir, store = store), "No datom config")
})

test_that("developer path aborts when project_name missing from yaml", {
  dir <- withr::local_tempdir()
  datom_dir <- fs::path(dir, ".datom")
  fs::dir_create(datom_dir)
  yaml::write_yaml(
    list(storage = list(root = "b")),
    fs::path(datom_dir, "project.yaml")
  )
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  expect_error(datom_get_conn(path = dir, store = store), "project_name")
})

test_that("developer path cross-checks root mismatch", {
  dir <- create_test_datom_repo(project_name = "myproj", bucket = "yaml-bucket")
  comp <- datom_store_s3(bucket = "different-bucket", access_key = "k",
                         secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://github.com/test/repo.git",
                       validate = FALSE)

  expect_error(datom_get_conn(path = dir, store = store), "mismatch")
})


# =============================================================================
# datom_get_conn() — reader path (store + project_name)
# =============================================================================

test_that("reader path creates connection from store", {
  comp <- datom_store_s3(bucket = "reader-bucket", prefix = "data/",
                         access_key = "fake_key", secret_key = "fake_secret",
                         validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  local_mocked_bindings(
    .datom_s3_client = function(...) mock_s3_client()
  )

  conn <- datom_get_conn(store = store, project_name = "myproj")

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$root, "reader-bucket")
  expect_equal(conn$prefix, "data/")
  expect_equal(conn$project_name, "myproj")
  expect_equal(conn$role, "reader")
  expect_null(conn$path)
})

test_that("reader path aborts when project_name is missing", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s",
                         validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)
  expect_error(
    datom_get_conn(store = store),
    "project_name.*required"
  )
})

test_that("reader path uses region from store", {
  comp <- datom_store_s3(bucket = "b", region = "ap-southeast-1",
                         access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  local_mocked_bindings(
    .datom_s3_client = function(...) mock_s3_client()
  )

  conn <- datom_get_conn(store = store, project_name = "myproj")
  expect_equal(conn$region, "ap-southeast-1")
})


# =============================================================================
# datom_init_repo()
# =============================================================================

# --- Helper: create a bare repo as remote + a working dir --------------------
setup_init_env <- function(env = parent.frame()) {
  bare_dir <- withr::local_tempdir(.local_envir = env)
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- withr::local_tempdir(.local_envir = env)

  comp <- datom_store_s3(
    bucket = "test-bucket", prefix = "proj/",
    access_key = "AKIAEXAMPLE", secret_key = "secretkey",
    validate = FALSE
  )
  store <- datom_store(
    governance = comp, data = comp,
    github_pat = "ghp_fake",
    data_repo_url = bare_dir,
    validate = FALSE
  )

  local_mocked_bindings(
    .datom_s3_client = function(...) list(put_object = function(...) list()),
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_storage_exists = function(...) FALSE,
    .env = env
  )

  list(bare_dir = bare_dir, work_dir = work_dir, store = store)
}


# --- Input validation ---------------------------------------------------------

test_that("datom_init_repo aborts on invalid project_name", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://github.com/x/y.git", validate = FALSE)
  expect_error(datom_init_repo(project_name = "", store = store), "name")
})

test_that("datom_init_repo rejects non-store object", {
  expect_error(
    datom_init_repo(path = withr::local_tempdir(), project_name = "p",
                    store = list(bucket = "b")),
    "datom_store"
  )
})

test_that("datom_init_repo rejects reader store", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  reader_store <- datom_store(governance = comp, data = comp, validate = FALSE)
  expect_error(
    datom_init_repo(path = withr::local_tempdir(), project_name = "p",
                    store = reader_store),
    "developer"
  )
})

test_that("datom_init_repo rejects create_repo with data_repo_url", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://github.com/x/y.git", validate = FALSE)
  expect_error(
    datom_init_repo(path = withr::local_tempdir(), project_name = "p",
                    store = store, create_repo = TRUE),
    "mutually exclusive"
  )
})

test_that("datom_init_repo errors when no data_repo_url and create_repo is FALSE", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       validate = FALSE)
  expect_error(
    datom_init_repo(path = withr::local_tempdir(), project_name = "p",
                    store = store),
    "No remote URL"
  )
})

test_that("datom_init_repo aborts on invalid max_file_size_gb", {
  env <- setup_init_env()
  expect_error(datom_init_repo(path = env$work_dir, project_name = "testproj",
                               store = env$store, max_file_size_gb = -1),
               "max_file_size_gb")
  env2 <- setup_init_env()
  expect_error(datom_init_repo(path = env2$work_dir, project_name = "testproj",
                               store = env2$store, max_file_size_gb = "big"),
               "max_file_size_gb")
})

test_that("datom_init_repo aborts if .datom already exists", {
  env <- setup_init_env()
  fs::dir_create(fs::path(env$work_dir, ".datom"))
  yaml::write_yaml(list(project_name = "x"),
                    fs::path(env$work_dir, ".datom", "project.yaml"))

  expect_error(datom_init_repo(path = env$work_dir, project_name = "testproj",
                               store = env$store),
               "already exists")
})


# --- Happy path ---------------------------------------------------------------

test_that("datom_init_repo creates .datom directory", {
  env <- setup_init_env()

  result <- datom_init_repo(
    path = env$work_dir,
    project_name = "testproj",
    store = env$store
  )

  expect_true(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})

test_that("datom_init_repo creates input_files directory", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  expect_true(fs::dir_exists(fs::path(env$work_dir, "input_files")))
})

test_that("datom_init_repo creates project.yaml with correct fields", {
  env <- setup_init_env()

  gov <- datom_store_s3(bucket = "gov-bucket", prefix = "gov/", region = "eu-west-1",
                        access_key = "AKIAEXAMPLE", secret_key = "secretkey", validate = FALSE)
  dat <- datom_store_s3(bucket = "my-bucket", prefix = "data/", region = "eu-west-1",
                        access_key = "AKIAEXAMPLE", secret_key = "secretkey", validate = FALSE)
  store <- datom_store(governance = gov, data = dat, github_pat = "ghp_fake",
                       data_repo_url = env$bare_dir, validate = FALSE)

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = store, max_file_size_gb = 500)

  yaml_path <- fs::path(env$work_dir, ".datom", "project.yaml")
  expect_true(fs::file_exists(yaml_path))

  cfg <- yaml::read_yaml(yaml_path)
  expect_equal(cfg$project_name, "testproj")
  expect_equal(cfg$storage$governance$type, "s3")
  expect_equal(cfg$storage$governance$root, "gov-bucket")
  expect_equal(cfg$storage$governance$prefix, "gov/")
  expect_equal(cfg$storage$governance$region, "eu-west-1")
  expect_equal(cfg$storage$data$type, "s3")
  expect_equal(cfg$storage$data$root, "my-bucket")
  expect_equal(cfg$storage$data$prefix, "data/")
  expect_equal(cfg$storage$data$region, "eu-west-1")
  expect_equal(cfg$storage$max_file_size_gb, 500)
  expect_equal(cfg$repos$data$remote_url, env$bare_dir)
  # No top-level storage$type, storage$root, or storage$credentials
  expect_null(cfg$storage$type)
  expect_null(cfg$storage$root)
  expect_null(cfg$storage$credentials)
})

test_that("datom_init_repo does NOT create dispatch.json in data clone (lives in gov repo)", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  # dispatch.json moved to gov repo (projects/{name}/dispatch.json);
  # it must NOT be in the data clone.
  dispatch_path <- fs::path(env$work_dir, ".datom", "dispatch.json")
  expect_false(fs::file_exists(dispatch_path))
})

test_that("datom_init_repo creates manifest.json", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

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
                  store = env$store)

  gitignore <- readLines(fs::path(env$work_dir, ".gitignore"))
  expect_true("input_files/" %in% gitignore)
  expect_true(".DS_Store" %in% gitignore)
  expect_true("*.parquet" %in% gitignore)
})

test_that("datom_init_repo initializes git with remote", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  expect_true(fs::dir_exists(fs::path(env$work_dir, ".git")))

  repo <- git2r::repository(env$work_dir)
  remotes <- git2r::remotes(repo)
  expect_true("origin" %in% remotes)
  expect_equal(git2r::remote_url(repo, remote = "origin"), env$bare_dir)
})

test_that("datom_init_repo makes initial commit", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  repo <- git2r::repository(env$work_dir)
  log <- git2r::commits(repo)
  expect_length(log, 1)
  expect_match(log[[1]]$message, "Initialize datom repository")
})

test_that("datom_init_repo pushes to remote", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  # Verify bare repo has the commit
  bare_repo <- git2r::repository(env$bare_dir)
  bare_log <- git2r::commits(bare_repo)
  expect_length(bare_log, 1)
  expect_match(bare_log[[1]]$message, "Initialize datom repository")
})

test_that("datom_init_repo returns invisible TRUE", {
  env <- setup_init_env()

  result <- datom_init_repo(path = env$work_dir, project_name = "testproj",
                            store = env$store)

  expect_true(result)

  # Use an independent env (fresh bare + work_dir) so the second push
  # is FF on its own remote. Reusing env$store would push an unrelated
  # history to the same bare, which libgit2 rejects on Linux.
  env2 <- setup_init_env()
  expect_invisible(datom_init_repo(
    path = env2$work_dir,
    project_name = "testproj",
    store = env2$store
  ))
})

test_that("datom_init_repo handles prefix = NULL in store", {
  env <- setup_init_env()

  comp <- datom_store_s3(bucket = "test-bucket", prefix = NULL,
                         access_key = "AKIAEXAMPLE", secret_key = "secretkey",
                         validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_fake",
                       data_repo_url = env$bare_dir, validate = FALSE)

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = store)

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  # YAML writes NULL as missing key
  expect_true(is.null(cfg$storage$data$prefix))
})

test_that("datom_init_repo stores project_name in config for hyphenated names", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- withr::local_tempdir()

  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = bare_dir, validate = FALSE)

  local_mocked_bindings(
    .datom_s3_client = function(...) list(put_object = function(...) list()),
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_storage_exists = function(...) FALSE
  )

  datom_init_repo(path = work_dir, project_name = "my-data", store = store)

  cfg <- yaml::read_yaml(fs::path(work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$project_name, "my-data")
  expect_equal(cfg$repos$data$remote_url, bare_dir)
})

test_that("datom_init_repo passes is_valid_datom_repo checks", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  # Should pass git + datom checks (not renv — we don't init renv)
  expect_true(is_valid_datom_repo(env$work_dir, checks = c("git", "datom")))
})

test_that("datom_init_repo committed files are tracked in git", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  repo <- git2r::repository(env$work_dir)
  status <- git2r::status(repo)
  # All staged files should have been committed — nothing left

  expect_length(status$staged, 0)
  expect_length(status$unstaged, 0)
})

test_that("datom_init_repo sets renv to FALSE in project.yaml", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_false(cfg$renv)
})

test_that("datom_init_repo stores datom_version in project.yaml", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$datom_version,
               as.character(utils::packageVersion("datom")))
})

test_that("datom_init_repo creates README.md", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  readme_path <- fs::path(env$work_dir, "README.md")
  expect_true(fs::file_exists(readme_path))
})

test_that("datom_init_repo README.md contains project name", {
  env <- setup_init_env()

  comp <- datom_store_s3(bucket = "my-bucket", prefix = "study/",
                         access_key = "AKIAEXAMPLE", secret_key = "secretkey",
                         validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_fake",
                       data_repo_url = env$bare_dir, validate = FALSE)

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = store)

  readme <- readLines(fs::path(env$work_dir, "README.md"))
  readme_text <- paste(readme, collapse = "\n")

  expect_match(readme_text, "# testproj", fixed = TRUE)
  expect_match(readme_text, "my-bucket", fixed = TRUE)
  expect_match(readme_text, "study/", fixed = TRUE)
  expect_match(readme_text, "datom_get_conn", fixed = TRUE)
})

test_that("datom_init_repo commits README.md to git", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  repo <- git2r::repository(env$work_dir)
  status <- git2r::status(repo)
  # README.md should be committed, not untracked
  untracked <- unlist(status$untracked)
  expect_false("README.md" %in% untracked)
})


# --- No-governance (gov-on-demand) --------------------------------------------

# Helper: setup_init_env equivalent for a no-gov store.
setup_init_env_nogov <- function(env = parent.frame()) {
  bare_dir <- withr::local_tempdir(.local_envir = env)
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- withr::local_tempdir(.local_envir = env)

  dat <- datom_store_s3(
    bucket = "data-bucket", prefix = "data/",
    access_key = "AKIAEXAMPLE", secret_key = "secretkey",
    validate = FALSE
  )
  store <- datom_store(
    governance = NULL, data = dat,
    github_pat = "ghp_fake",
    data_repo_url = bare_dir,
    validate = FALSE
  )

  local_mocked_bindings(
    .datom_s3_client = function(...) list(put_object = function(...) list()),
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_storage_exists = function(...) FALSE,
    .env = env
  )

  list(bare_dir = bare_dir, work_dir = work_dir, store = store)
}

test_that("datom_init_repo succeeds with no-gov store", {
  env <- setup_init_env_nogov()

  result <- datom_init_repo(
    path = env$work_dir,
    project_name = "nogov-proj",
    store = env$store
  )

  expect_true(result)
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".datom")))
  expect_true(fs::file_exists(fs::path(env$work_dir, ".datom", "project.yaml")))
  expect_true(fs::file_exists(fs::path(env$work_dir, ".datom", "manifest.json")))
})

test_that("datom_init_repo no-gov omits storage.governance from project.yaml", {
  env <- setup_init_env_nogov()

  datom_init_repo(path = env$work_dir, project_name = "nogov-proj",
                  store = env$store)

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))

  # storage.governance must be absent (gov-on-demand: not yet attached)
  expect_null(cfg$storage$governance)
  # storage.data still present
  expect_equal(cfg$storage$data$type, "s3")
  expect_equal(cfg$storage$data$root, "data-bucket")
})

test_that("datom_init_repo no-gov omits repos.governance from project.yaml", {
  env <- setup_init_env_nogov()

  datom_init_repo(path = env$work_dir, project_name = "nogov-proj",
                  store = env$store)

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))

  # repos.governance must be absent
  expect_null(cfg$repos$governance)
  # repos.data still present
  expect_equal(cfg$repos$data$remote_url, env$bare_dir)
})

test_that("datom_init_repo no-gov does not create gov clone", {
  env <- setup_init_env_nogov()

  # Capture sibling dir count before init
  parent <- fs::path_dir(env$work_dir)
  before <- fs::dir_ls(parent, all = TRUE)

  datom_init_repo(path = env$work_dir, project_name = "nogov-proj",
                  store = env$store)

  after <- fs::dir_ls(parent, all = TRUE)
  # No new sibling directories (gov clone would be one)
  expect_setequal(before, after)
})

test_that("datom_init_repo no-gov skips .datom_gov_register_project", {
  env <- setup_init_env_nogov()

  register_called <- FALSE
  local_mocked_bindings(
    .datom_gov_register_project = function(...) {
      register_called <<- TRUE
      invisible(TRUE)
    }
  )

  datom_init_repo(path = env$work_dir, project_name = "nogov-proj",
                  store = env$store)

  expect_false(register_called)
})

test_that("datom_init_repo no-gov still pushes data repo to remote", {
  env <- setup_init_env_nogov()

  datom_init_repo(path = env$work_dir, project_name = "nogov-proj",
                  store = env$store)

  bare_repo <- git2r::repository(env$bare_dir)
  bare_log <- git2r::commits(bare_repo)
  expect_length(bare_log, 1)
  expect_match(bare_log[[1]]$message, "Initialize datom repository")
})

# --- No-gov datom_get_conn() shape -------------------------------------------

test_that("datom_get_conn developer path returns conn with all gov fields NULL for no-gov project", {
  env <- setup_init_env_nogov()

  datom_init_repo(path = env$work_dir, project_name = "nogov-proj",
                  store = env$store)

  conn <- datom_get_conn(path = env$work_dir, store = env$store)

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$project_name, "nogov-proj")
  expect_equal(conn$role, "developer")
  expect_equal(conn$root, "data-bucket")
  # All governance fields must be NULL
  expect_null(conn$gov_root)
  expect_null(conn$gov_prefix)
  expect_null(conn$gov_region)
  expect_null(conn$gov_client)
  expect_null(conn$gov_local_path)
})

test_that("datom_get_conn reader path returns conn with all gov fields NULL for no-gov store", {
  data_comp <- datom_store_s3(
    bucket = "data-bucket", prefix = "data/",
    access_key = "AKIAEXAMPLE", secret_key = "secretkey",
    validate = FALSE
  )
  store <- datom_store(
    governance = NULL,
    data = data_comp,
    data_repo_url = "https://github.com/example/repo.git",
    validate = FALSE
  )

  local_mocked_bindings(
    .datom_s3_client = function(...) mock_s3_client(),
    .datom_check_data_reachable = function(...) invisible(TRUE)
  )

  conn <- datom_get_conn(store = store, project_name = "nogov-proj")

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$role, "reader")
  expect_equal(conn$root, "data-bucket")
  expect_null(conn$gov_root)
  expect_null(conn$gov_prefix)
  expect_null(conn$gov_region)
  expect_null(conn$gov_client)
  expect_null(conn$gov_local_path)
})

test_that(".datom_check_ref_current is a no-op on a no-gov conn", {
  env <- setup_init_env_nogov()

  datom_init_repo(path = env$work_dir, project_name = "nogov-proj",
                  store = env$store)

  conn <- datom_get_conn(path = env$work_dir, store = env$store)

  # Tamper with conn$root to simulate a stale conn after a hypothetical
  # migration. Without gov, there is nothing to compare against, so the
  # guard short-circuits and returns invisibly.
  conn$root <- "tampered-bucket"
  expect_silent(result <- .datom_check_ref_current(conn))
  expect_true(result)
})


# --- Rollback on failure ------------------------------------------------------

test_that("datom_init_repo cleans up .datom on git push failure", {
  env <- setup_init_env()

  local_mocked_bindings(.datom_git_push = function(...) stop("push failed"))

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    store = env$store),
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
                    store = env$store),
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
                    store = env$store),
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
                    store = env$store),
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
                    store = env$store),
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
                    store = env$store)
  )

  # .git/ should NOT be deleted
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".git")))
})

test_that("datom_init_repo success does not trigger cleanup", {
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

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
                    store = env$store),
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
                    store = env$store),
    "push failed"
  )

  # Parent dir should remain because it pre-existed
  expect_true(fs::dir_exists(env$work_dir))
})

test_that("datom_init_repo pushes manifest.json to data storage", {
  env <- setup_init_env()

  s3_keys_written <- character()

  # Override the S3 stubs from setup_init_env to capture writes
  local_mocked_bindings(
    .datom_storage_write_json = function(conn, s3_key, data) {
      s3_keys_written <<- c(s3_keys_written, s3_key)
      invisible(TRUE)
    }
  )

  datom_init_repo(
    path = env$work_dir,
    project_name = "testproj",
    store = env$store
  )

  # manifest goes to data storage; dispatch/ref go to gov repo (git) not here
  expect_true(".metadata/manifest.json" %in% s3_keys_written)
  # dispatch and ref are registered in gov repo, not written to S3 directly
  # by datom_init_repo when no gov_local_path is set
  expect_false(".metadata/dispatch.json" %in% s3_keys_written)
  expect_false(".metadata/ref.json" %in% s3_keys_written)
})

test_that("datom_init_repo aborts but preserves local clone if storage fails after git push", {
  env <- setup_init_env()

  # Storage client fails when build_init_conn is called (post-push)
  local_mocked_bindings(
    .datom_s3_client = function(...) stop("S3 unavailable")
  )

  # Post-push storage failure aborts (no more silent partial-success)
  expect_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      store = env$store
    ),
    "S3 unavailable"
  )

  # Local clone is intact -- git push succeeded, we don't roll back local
  # files post-push so the user can retry sync_manifest after fixing creds.
  expect_true(fs::file_exists(fs::path(env$work_dir, ".datom", "manifest.json")))
  expect_true(fs::dir_exists(fs::path(env$work_dir, ".git")))
})


# --- Governance-first ordering (Phase 15, Chunk 5) ---------------------------

# Helper: extends setup_init_env() with a bare gov repo + gov_repo_url
setup_init_env_with_gov <- function(env = parent.frame()) {
  base <- setup_init_env(env = env)

  gov_bare <- withr::local_tempdir(.local_envir = env)
  git2r::init(gov_bare, bare = TRUE)
  gov_local <- withr::local_tempdir(.local_envir = env)
  # Remove so .datom_gov_clone_init clones fresh
  fs::dir_delete(gov_local)

  store <- datom_store(
    governance = base$store$governance,
    data = base$store$data,
    github_pat = "ghp_fake",
    data_repo_url = base$bare_dir,
    gov_repo_url = gov_bare,
    gov_local_path = gov_local,
    validate = FALSE
  )

  c(base[c("bare_dir", "work_dir")],
    list(gov_bare = gov_bare, gov_local = gov_local, store = store))
}

test_that("datom_init_repo aborts and rolls back gov clone if pre-push step fails", {
  env <- setup_init_env_with_gov()

  # Storage namespace check: simulate occupied bucket so init aborts BEFORE
  # any git work or push.
  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) grepl("manifest\\.json", s3_key),
    .datom_storage_read_json = function(conn, s3_key) {
      list(project_name = "EXISTING_PROJECT", tables = list())
    }
  )

  # Gov clone did not exist before this call -- create_here flag should fire.
  expect_false(fs::dir_exists(env$gov_local))

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    store = env$store),
    "already occupied"
  )

  # Gov clone should be rolled back (we created it; init aborted pre-push).
  expect_false(fs::dir_exists(env$gov_local))
  # Data clone also rolled back.
  expect_false(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})

test_that("datom_init_repo does NOT roll back a pre-existing gov clone on failure", {
  env <- setup_init_env_with_gov()

  # Pre-clone the gov repo so it exists before datom_init_repo runs
  .datom_gov_clone_init(env$gov_bare, env$gov_local)
  expect_true(fs::dir_exists(fs::path(env$gov_local, ".git")))

  # Force a pre-push failure
  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) grepl("manifest\\.json", s3_key),
    .datom_storage_read_json = function(conn, s3_key) {
      list(project_name = "EXISTING_PROJECT", tables = list())
    }
  )

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    store = env$store),
    "already occupied"
  )

  # Gov clone preserved -- it existed before our call.
  expect_true(fs::dir_exists(fs::path(env$gov_local, ".git")))
})

test_that("datom_init_repo with gov_repo_url clones gov repo before data work", {
  env <- setup_init_env_with_gov()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  # Gov repo was cloned to gov_local_path
  expect_true(fs::dir_exists(fs::path(env$gov_local, ".git")))
})

test_that("datom_init_repo registers project in gov repo", {
  env <- setup_init_env_with_gov()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  proj_dir <- fs::path(env$gov_local, "projects", "testproj")
  expect_true(fs::file_exists(fs::path(proj_dir, "dispatch.json")))
  expect_true(fs::file_exists(fs::path(proj_dir, "ref.json")))
})

test_that("datom_init_repo aborts when gov project namespace already exists", {
  env <- setup_init_env_with_gov()

  # Pre-clone gov and create a project dir to simulate collision
  .datom_gov_clone_init(env$gov_bare, env$gov_local)
  fs::dir_create(fs::path(env$gov_local, "projects", "testproj"))

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    store = env$store),
    "already"
  )

  # Data clone should not have been created
  expect_false(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})


# --- S3 namespace safety check (Phase 7) -------------------------------------

test_that("datom_init_repo aborts when S3 namespace is occupied", {
  env <- setup_init_env()

  # Override .datom_storage_exists to report namespace is occupied
  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) {
      grepl("manifest\\.json", s3_key)
    },
    .datom_storage_read_json = function(conn, s3_key) {
      list(project_name = "EXISTING_PROJECT", tables = list())
    }
  )

  expect_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      store = env$store
    ),
    "already occupied"
  )

  # Nothing should have been created
  expect_false(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})

test_that("datom_init_repo proceeds when .force = TRUE despite occupied namespace", {
  env <- setup_init_env()

  # Override .datom_storage_exists to report namespace is occupied
  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) {
      grepl("manifest\\.json", s3_key)
    },
    .datom_storage_read_json = function(conn, s3_key) {
      list(project_name = "EXISTING_PROJECT", tables = list())
    },
    .datom_storage_write_json = function(...) invisible(TRUE)
  )

  result <- datom_init_repo(
    path = env$work_dir,
    project_name = "testproj",
    store = env$store,
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
    store = env$store
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
    .datom_storage_exists = function(conn, s3_key) stop("Network error"),
    .datom_storage_write_json = function(...) invisible(TRUE)
  )

  # Should succeed — connectivity failure during namespace check is a warning, not fatal
  expect_no_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      store = env$store
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
    root = "b",
    region = "us-east-1",
    client = mock_s3_client(),
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
    root = "b",
    region = "us-east-1",
    client = mock_s3_client()
  )

  expect_null(conn$endpoint)
})

test_that("print.datom_conn shows endpoint when non-NULL", {
  conn <- new_datom_conn(
    project_name = "proj",
    root = "b",
    region = "us-east-1",
    client = mock_s3_client(),
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
    root = "b",
    region = "us-east-1",
    client = mock_s3_client()
  )

  output <- cli::cli_fmt(print(conn))
  combined <- paste(output, collapse = " ")

  expect_no_match(combined, "Endpoint")
})

test_that(".datom_s3_client passes endpoint to paws config", {
  skip_if_not_installed("paws.storage")

  mock_s3 <- mockery::mock("client1", "client2")
  mockery::stub(.datom_s3_client, "paws.storage::s3", mock_s3)

  # With endpoint
  .datom_s3_client("test-key", "test-secret",
    region = "us-east-1",
    endpoint = "https://custom.s3.endpoint.com"
  )

  call_args <- mockery::mock_args(mock_s3)[[1]]
  expect_equal(call_args$config$endpoint, "https://custom.s3.endpoint.com")

  # Without endpoint
  .datom_s3_client("test-key", "test-secret", region = "us-east-1")
  call_args2 <- mockery::mock_args(mock_s3)[[2]]
  expect_null(call_args2$config$endpoint)
})

test_that("datom_get_conn forwards endpoint to developer path", {
  dir <- create_test_datom_repo(project_name = "myproj")

  comp <- datom_store_s3(bucket = "test-bucket", prefix = "test-prefix/",
                         access_key = "fake_key", secret_key = "fake_secret",
                         validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_fake",
                       data_repo_url = "https://github.com/test/repo.git",
                       validate = FALSE)

  captured_endpoint <- NULL
  local_mocked_bindings(
    .datom_s3_client = function(access_key, secret_key, region = "us-east-1",
                                endpoint = NULL, session_token = NULL) {
      captured_endpoint <<- endpoint
      mock_s3_client()
    }
  )

  conn <- datom_get_conn(
    path = dir,
    store = store,
    endpoint = "https://my-endpoint.com"
  )

  expect_equal(conn$endpoint, "https://my-endpoint.com")
  expect_equal(captured_endpoint, "https://my-endpoint.com")
})

test_that("datom_get_conn forwards endpoint to reader path", {
  comp <- datom_store_s3(bucket = "b", access_key = "fake_key",
                         secret_key = "fake_secret", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  captured_endpoint <- NULL
  local_mocked_bindings(
    .datom_s3_client = function(access_key, secret_key, region = "us-east-1",
                                endpoint = NULL, session_token = NULL) {
      captured_endpoint <<- endpoint
      mock_s3_client()
    }
  )

  conn <- datom_get_conn(
    store = store,
    project_name = "proj",
    endpoint = "https://reader-endpoint.com"
  )

  expect_equal(conn$endpoint, "https://reader-endpoint.com")
  expect_equal(captured_endpoint, "https://reader-endpoint.com")
})

test_that("datom_get_conn endpoint defaults to NULL when not specified", {
  comp <- datom_store_s3(bucket = "b", access_key = "fake_key",
                         secret_key = "fake_secret", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  captured_endpoint <- "sentinel"
  local_mocked_bindings(
    .datom_s3_client = function(access_key, secret_key, region = "us-east-1",
                                endpoint = NULL, session_token = NULL) {
      captured_endpoint <<- endpoint
      mock_s3_client()
    }
  )

  conn <- datom_get_conn(store = store, project_name = "proj")

  expect_null(conn$endpoint)
  expect_null(captured_endpoint)
})

test_that("mock_datom_conn includes endpoint field as NULL", {
  conn <- mock_datom_conn(mock_s3_client())
  expect_true("endpoint" %in% names(conn))
  expect_null(conn$endpoint)
})


# --- datom_clone() -------------------------------------------------------------

test_that("datom_clone rejects non-store object", {
  expect_error(datom_clone(path = "x", store = list(a = 1)), "datom_store")
})

test_that("datom_clone rejects reader store", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)
  expect_error(datom_clone(path = "x", store = store), "developer")
})

test_that("datom_clone rejects store without data_repo_url", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x", validate = FALSE)
  expect_error(datom_clone(path = "x", store = store), "data_repo_url")
})

test_that("datom_clone rejects empty path", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://x.git", validate = FALSE)
  expect_error(datom_clone(path = "", store = store), "path")
})

test_that("datom_clone rejects non-empty target directory", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://x.git", validate = FALSE)
  withr::with_tempdir({
    fs::dir_create("existing")
    writeLines("file", fs::path("existing", "README.md"))
    expect_error(
      datom_clone(path = "existing", store = store),
      "not empty"
    )
  })
})

test_that("datom_clone aborts if cloned repo is not a datom repo", {
  withr::with_tempdir({
    bare_dir <- withr::local_tempdir()
    git2r::init(bare_dir, bare = TRUE)

    work_dir <- withr::local_tempdir()
    work_repo <- git2r::init(work_dir)
    git2r::config(work_repo, user.name = "Test", user.email = "test@test.com")
    writeLines("init", fs::path(work_dir, "README.md"))
    git2r::add(work_repo, "README.md")
    git2r::commit(work_repo, "Initial commit")
    git2r::remote_add(work_repo, name = "origin", url = bare_dir)
    git2r::push(work_repo, name = "origin",
                refspec = "refs/heads/master", set_upstream = TRUE)

    comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
    store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                         data_repo_url = bare_dir, validate = FALSE)

    expect_error(
      datom_clone(path = "clone_target", store = store),
      "not a datom repository"
    )
  })
})

test_that("datom_clone clones and returns a datom_conn", {
  withr::with_tempdir({
    bare_dir <- withr::local_tempdir()
    git2r::init(bare_dir, bare = TRUE)

    work_dir <- withr::local_tempdir()
    work_repo <- git2r::init(work_dir)
    git2r::config(work_repo, user.name = "Test", user.email = "test@test.com")

    fs::dir_create(fs::path(work_dir, ".datom"))
    yaml::write_yaml(
      list(
        project_name = "MYPROJ",
        storage = list(
          data = list(
            type = "s3",
            root = "test-bucket",
            region = "us-east-1"
          ),
          governance = list(
            type = "s3",
            root = "test-bucket",
            region = "us-east-1"
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

    comp <- datom_store_s3(bucket = "test-bucket", access_key = "fakekey",
                           secret_key = "fakesecret", validate = FALSE)
    store <- datom_store(governance = comp, data = comp, github_pat = "fake-pat",
                         data_repo_url = bare_dir, validate = FALSE)

    local_mocked_bindings(
      .datom_s3_client = function(...) list(fake = TRUE)
    )

    conn <- datom_clone(path = "clone_target", store = store)

    expect_s3_class(conn, "datom_conn")
    expect_equal(conn$project_name, "MYPROJ")
    expect_equal(conn$root, "test-bucket")
    expect_true(fs::dir_exists("clone_target/.datom"))
    expect_true(fs::file_exists("clone_target/.datom/project.yaml"))
  })
})

test_that("datom_clone aborts on clone failure", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://example.com/no-such-repo.git",
                       validate = FALSE)
  withr::with_tempdir({
    expect_error(
      datom_clone(path = "target", store = store),
      "Failed to clone"
    )
  })
})

# --- datom_clone() gov-repo two-repo semantics (Phase 15, Chunk 6) -----------

# Shared helper: make a committed datom-style bare repo
.make_bare_datom_repo <- function() {
  bare_dir <- tempfile("bare_"); dir.create(bare_dir)
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- tempfile("work_"); dir.create(work_dir)
  work_repo <- git2r::init(work_dir)
  git2r::config(work_repo, user.name = "Test", user.email = "t@t.com")
  fs::dir_create(fs::path(work_dir, ".datom"))
  yaml::write_yaml(
    list(project_name = "PROJ",
         storage = list(
           data = list(type = "s3", root = "b", region = "us-east-1"),
           governance = list(type = "s3", root = "b", region = "us-east-1")
         )),
    fs::path(work_dir, ".datom", "project.yaml")
  )
  git2r::add(work_repo, ".datom/project.yaml")
  git2r::commit(work_repo, "Init")
  git2r::remote_add(work_repo, "origin", bare_dir)
  git2r::push(work_repo, "origin", "refs/heads/master", set_upstream = TRUE)
  list(bare = bare_dir, work = work_dir)
}

test_that("datom_clone with gov_repo_url also clones gov repo", {
  withr::with_tempdir({
    data_repos <- .make_bare_datom_repo()

    gov_bare <- tempfile("gov_bare_"); dir.create(gov_bare)
    git2r::init(gov_bare, bare = TRUE)
    gov_local <- tempfile("gov_local_")  # does not exist yet

    comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s",
                           validate = FALSE)
    store <- datom_store(governance = comp, data = comp,
                         github_pat = "ghp_x",
                         data_repo_url = data_repos$bare,
                         gov_repo_url = gov_bare,
                         gov_local_path = gov_local,
                         validate = FALSE)

    local_mocked_bindings(
      .datom_s3_client = function(...) list(fake = TRUE)
    )

    datom_clone(path = "clone_target", store = store)

    expect_true(fs::dir_exists(fs::path(gov_local, ".git")))
  })
})

test_that("datom_clone reuses existing gov clone with matching URL", {
  withr::with_tempdir({
    data_repos <- .make_bare_datom_repo()

    gov_bare <- tempfile("gov_bare_"); dir.create(gov_bare)
    git2r::init(gov_bare, bare = TRUE)
    gov_local <- tempfile("gov_local_"); dir.create(gov_local)
    # Pre-clone gov
    git2r::clone(gov_bare, gov_local)

    comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s",
                           validate = FALSE)
    store <- datom_store(governance = comp, data = comp,
                         github_pat = "ghp_x",
                         data_repo_url = data_repos$bare,
                         gov_repo_url = gov_bare,
                         gov_local_path = gov_local,
                         validate = FALSE)

    local_mocked_bindings(
      .datom_s3_client = function(...) list(fake = TRUE)
    )

    # Should not error (idempotent)
    expect_no_error(datom_clone(path = "clone_target", store = store))
  })
})

test_that("datom_clone aborts when existing gov clone has uncommitted changes", {
  withr::with_tempdir({
    data_repos <- .make_bare_datom_repo()

    gov_bare <- tempfile("gov_bare_"); dir.create(gov_bare)
    git2r::init(gov_bare, bare = TRUE)
    gov_local <- tempfile("gov_local_"); dir.create(gov_local)
    git2r::clone(gov_bare, gov_local)

    # Leave an unstaged change in the gov clone
    writeLines("dirty", fs::path(gov_local, "dirty.txt"))
    gov_repo <- git2r::repository(gov_local)
    git2r::add(gov_repo, "dirty.txt")  # staged change

    comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s",
                           validate = FALSE)
    store <- datom_store(governance = comp, data = comp,
                         github_pat = "ghp_x",
                         data_repo_url = data_repos$bare,
                         gov_repo_url = gov_bare,
                         gov_local_path = gov_local,
                         validate = FALSE)

    expect_error(
      datom_clone(path = "clone_target", store = store),
      "uncommitted"
    )
  })
})

test_that("datom_clone aborts when existing gov clone has different remote URL", {
  withr::with_tempdir({
    data_repos <- .make_bare_datom_repo()

    gov_bare <- tempfile("gov_bare_"); dir.create(gov_bare)
    git2r::init(gov_bare, bare = TRUE)
    gov_local <- tempfile("gov_local_"); dir.create(gov_local)
    git2r::clone(gov_bare, gov_local)

    comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s",
                           validate = FALSE)
    store <- datom_store(governance = comp, data = comp,
                         github_pat = "ghp_x",
                         data_repo_url = data_repos$bare,
                         gov_repo_url = "https://github.com/other/different-gov.git",
                         gov_local_path = gov_local,
                         validate = FALSE)

    expect_error(
      datom_clone(path = "clone_target", store = store),
      "different remote URL"
    )
  })
})


# ==============================================================================
# Local backend connection tests (Phase 12, Chunk 4)
# ==============================================================================

test_that("new_datom_conn works with backend = 'local' and NULL region", {
  conn <- new_datom_conn(
    project_name = "test_proj",
    root = "/data/store",
    prefix = "proj/",
    region = NULL,
    client = NULL,
    role = "reader",
    backend = "local"
  )

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$backend, "local")
  expect_equal(conn$root, "/data/store")
  expect_null(conn$region)
  expect_null(conn$client)
})

test_that("new_datom_conn with backend = 's3' rejects NULL region", {
  expect_error(
    new_datom_conn(
      project_name = "p", root = "b", region = NULL,
      client = mock_s3_client(), backend = "s3"
    ),
    "region"
  )
})

test_that(".datom_build_init_conn creates local conn from local store", {
  local_store <- datom_store_local(path = "/data/store", prefix = "proj/", validate = FALSE)

  conn <- .datom_build_init_conn(
    "test_proj", local_store, NULL, "reader",
    gov_store = local_store
  )

  expect_equal(conn$backend, "local")
  expect_match(conn$root, "data/store")
  expect_null(conn$client)
  expect_match(conn$gov_root, "data/store")
  expect_null(conn$gov_client)
})

test_that(".datom_build_init_conn creates s3 conn from s3 store", {
  s3_store <- datom_store_s3(
    bucket = "b", prefix = "p/", region = "us-east-1",
    access_key = "AK", secret_key = "SK", validate = FALSE
  )

  local_mocked_bindings(
    .datom_s3_client = function(...) list(put_object = function(...) list())
  )

  conn <- .datom_build_init_conn(
    "test_proj", s3_store, NULL, "reader",
    gov_store = s3_store
  )

  expect_equal(conn$backend, "s3")
  expect_equal(conn$root, "b")
  expect_false(is.null(conn$client))
})

test_that(".datom_store_backend returns correct backend", {
  s3 <- datom_store_s3(bucket = "b", access_key = "a", secret_key = "s", validate = FALSE)
  local <- datom_store_local(path = "/tmp/x", validate = FALSE)

  expect_equal(.datom_store_backend(s3), "s3")
  expect_equal(.datom_store_backend(local), "local")
})

test_that(".datom_store_root returns correct root", {
  s3 <- datom_store_s3(bucket = "my-bucket", access_key = "a", secret_key = "s", validate = FALSE)
  local <- datom_store_local(path = "/data/store", validate = FALSE)

  expect_equal(.datom_store_root(s3), "my-bucket")
  expect_match(.datom_store_root(local), "data/store")
})

test_that(".datom_store_region returns correct region", {
  s3 <- datom_store_s3(bucket = "b", region = "eu-west-1", access_key = "a", secret_key = "s", validate = FALSE)
  local <- datom_store_local(path = "/tmp/x", validate = FALSE)

  expect_equal(.datom_store_region(s3), "eu-west-1")
  expect_null(.datom_store_region(local))
})

test_that("print.datom_conn shows backend", {
  conn <- new_datom_conn(
    project_name = "p", root = "/data", region = NULL,
    client = NULL, role = "reader", backend = "local"
  )
  out <- capture.output(print(conn), type = "message")
  combined <- paste(out, collapse = "\n")
  expect_match(combined, "local")
})

# --- Local init_repo setup helper -------------------------------------------

setup_local_init_env <- function(env = parent.frame()) {
  bare_dir <- withr::local_tempdir(.local_envir = env)
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- withr::local_tempdir(.local_envir = env)
  store_dir <- withr::local_tempdir(.local_envir = env)

  comp <- datom_store_local(path = store_dir, prefix = "proj/", validate = TRUE)
  store <- datom_store(
    governance = comp, data = comp,
    github_pat = "ghp_fake",
    data_repo_url = bare_dir,
    validate = FALSE
  )

  list(bare_dir = bare_dir, work_dir = work_dir, store_dir = store_dir, store = store)
}

test_that("datom_init_repo works with local stores", {
  env <- setup_local_init_env()

  datom_init_repo(
    path = env$work_dir,
    project_name = "local_test",
    store = env$store
  )

  # Check files created in data clone
  expect_true(fs::file_exists(fs::path(env$work_dir, ".datom", "project.yaml")))
  expect_true(fs::file_exists(fs::path(env$work_dir, ".datom", "manifest.json")))
  # dispatch.json and ref.json now live in gov repo, NOT in data clone
  expect_false(fs::file_exists(fs::path(env$work_dir, ".datom", "ref.json")))
  expect_false(fs::file_exists(fs::path(env$work_dir, ".datom", "dispatch.json")))

  # Check project.yaml has local backend
  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$storage$data$type, "local")
  expect_equal(cfg$storage$governance$type, "local")
  expect_null(cfg$storage$data$region)

  # Check manifest was pushed to data storage
  store_base <- fs::path(env$store_dir, "proj/", "datom")
  expect_true(fs::file_exists(fs::path(store_base, ".metadata", "manifest.json")))
  # dispatch/ref are NOT in storage .metadata/ -- they go to gov repo (no gov_repo_url set here)
  expect_false(fs::file_exists(fs::path(store_base, ".metadata", "dispatch.json")))
  expect_false(fs::file_exists(fs::path(store_base, ".metadata", "ref.json")))
})

test_that("datom_get_conn works with local stores after init", {
  env <- setup_local_init_env()

  datom_init_repo(
    path = env$work_dir,
    project_name = "local_conn_test",
    store = env$store
  )

  conn <- datom_get_conn(path = env$work_dir, store = env$store)

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$backend, "local")
  expect_equal(conn$project_name, "local_conn_test")
  expect_equal(conn$role, "developer")
  expect_null(conn$client)
})


# =============================================================================
# Phase 13: .datom_check_data_reachable()
# =============================================================================

test_that("S3: aborts with actionable error on 403 without migration", {
  conn <- new_datom_conn(
    project_name = "p", root = "my-bucket", region = "us-east-1",
    client = list(head_bucket = function(Bucket) stop("403 Forbidden AccessDenied")),
    role = "reader"
  )

  expect_error(
    .datom_check_data_reachable(conn, migrated = FALSE),
    "unreachable"
  )
})

test_that("S3: aborts with migration-specific message on 403 after migration", {
  conn <- new_datom_conn(
    project_name = "p", root = "new-bucket", region = "us-east-1",
    client = list(head_bucket = function(Bucket) stop("403 Forbidden AccessDenied")),
    role = "reader"
  )

  expect_error(
    .datom_check_data_reachable(conn, migrated = TRUE),
    "credentials"
  )
})

test_that("S3: warns (not errors) on non-403 network error", {
  conn <- new_datom_conn(
    project_name = "p", root = "my-bucket", region = "us-east-1",
    client = list(head_bucket = function(Bucket) stop("Connection timeout")),
    role = "reader"
  )

  expect_warning(
    .datom_check_data_reachable(conn, migrated = FALSE),
    "reachability"
  )
})

test_that("S3: skips check when client has no head_bucket (mock client)", {
  conn <- new_datom_conn(
    project_name = "p", root = "my-bucket", region = "us-east-1",
    client = list(put_object = function(...) NULL),
    role = "reader"
  )

  expect_no_error(.datom_check_data_reachable(conn))
})

test_that("local: aborts when root directory does not exist", {
  conn <- new_datom_conn(
    project_name = "p", root = "/nonexistent/path/xyz",
    client = NULL, role = "reader", backend = "local"
  )

  expect_error(
    .datom_check_data_reachable(conn, migrated = FALSE),
    "does not exist"
  )
})

test_that("local: aborts with migration message when dir missing after migration", {
  conn <- new_datom_conn(
    project_name = "p", root = "/nonexistent/path/xyz",
    client = NULL, role = "reader", backend = "local"
  )

  expect_error(
    .datom_check_data_reachable(conn, migrated = TRUE),
    "migrated"
  )
})

test_that("local: passes when root directory exists", {
  dir <- withr::local_tempdir()
  conn <- new_datom_conn(
    project_name = "p", root = as.character(dir),
    client = NULL, role = "reader", backend = "local"
  )

  expect_no_error(.datom_check_data_reachable(conn))
})


# =============================================================================
# datom_init_gov()
# =============================================================================

# Helper: bare + clone setup for datom_init_gov tests
setup_gov_init_env <- function(env = parent.frame()) {
  bare_dir <- withr::local_tempdir(.local_envir = env)
  git2r::init(bare_dir, bare = TRUE)

  gov_dir  <- withr::local_tempdir(.local_envir = env)

  gov_store <- datom_store_local(
    path = withr::local_tempdir(.local_envir = env),
    validate = FALSE
  )

  list(bare_dir = bare_dir, gov_dir = gov_dir, gov_store = gov_store)
}

# --- Validation ---------------------------------------------------------------

test_that("datom_init_gov aborts on non-store-component gov_store", {
  expect_error(
    datom_init_gov(gov_store = list(path = "/tmp"),
                   gov_repo_url = "https://example.com/gov.git"),
    "datom_store_s3"
  )
})

test_that("datom_init_gov aborts when both create_repo and gov_repo_url are given", {
  gov_store <- datom_store_local(path = withr::local_tempdir(), validate = FALSE)
  expect_error(
    datom_init_gov(gov_store = gov_store,
                   gov_repo_url = "https://github.com/org/gov.git",
                   create_repo = TRUE,
                   repo_name = "gov",
                   github_pat = "ghp_fake"),
    "mutually exclusive"
  )
})

test_that("datom_init_gov aborts when create_repo = TRUE and repo_name is NULL", {
  gov_store <- datom_store_local(path = withr::local_tempdir(), validate = FALSE)
  expect_error(
    datom_init_gov(gov_store = gov_store,
                   create_repo = TRUE,
                   github_pat = "ghp_fake"),
    "repo_name"
  )
})

test_that("datom_init_gov aborts when create_repo = TRUE and github_pat is NULL", {
  gov_store <- datom_store_local(path = withr::local_tempdir(), validate = FALSE)
  expect_error(
    datom_init_gov(gov_store = gov_store,
                   create_repo = TRUE,
                   repo_name = "gov"),
    "github_pat"
  )
})

test_that("datom_init_gov aborts when no gov_repo_url and create_repo is FALSE", {
  gov_store <- datom_store_local(path = withr::local_tempdir(), validate = FALSE)
  expect_error(
    datom_init_gov(gov_store = gov_store),
    "No governance repo URL"
  )
})

# --- Happy path (local backend, bare repo as remote) -------------------------

test_that("datom_init_gov seeds skeleton and returns gov_repo_url", {
  env <- setup_gov_init_env()

  result <- datom_init_gov(
    gov_store     = env$gov_store,
    gov_repo_url  = env$bare_dir,
    gov_local_path = env$gov_dir
  )

  expect_equal(result, env$bare_dir)
  expect_true(fs::file_exists(fs::path(env$gov_dir, "README.md")))
  expect_true(fs::file_exists(fs::path(env$gov_dir, "projects", ".gitkeep")))

  # Commit should exist
  repo <- git2r::repository(env$gov_dir)
  commits <- git2r::commits(repo)
  expect_length(commits, 1L)
  expect_equal(commits[[1L]]$message, "Initialize governance repository")
})

# --- Idempotence --------------------------------------------------------------

test_that("datom_init_gov is idempotent: returns silently when already initialised", {
  env <- setup_gov_init_env()

  # First call
  datom_init_gov(
    gov_store      = env$gov_store,
    gov_repo_url   = env$bare_dir,
    gov_local_path = env$gov_dir
  )

  repo_before <- git2r::repository(env$gov_dir)
  commits_before <- git2r::commits(repo_before)

  # Second call -- should not add more commits
  result <- datom_init_gov(
    gov_store      = env$gov_store,
    gov_repo_url   = env$bare_dir,
    gov_local_path = env$gov_dir
  )

  expect_equal(result, env$bare_dir)
  commits_after <- git2r::commits(git2r::repository(env$gov_dir))
  expect_equal(length(commits_after), length(commits_before))
})

# --- create_repo path (mocked) -----------------------------------------------

test_that("datom_init_gov with create_repo = TRUE calls .datom_create_github_repo", {
  env <- setup_gov_init_env()

  local_mocked_bindings(
    .datom_create_github_repo = function(repo_name, pat, org = NULL, private = TRUE) {
      env$bare_dir  # return local bare dir as fake clone URL
    }
  )

  result <- datom_init_gov(
    gov_store      = env$gov_store,
    gov_local_path = env$gov_dir,
    create_repo    = TRUE,
    repo_name      = "acme-gov",
    github_pat     = "ghp_fake"
  )

  expect_equal(result, env$bare_dir)
  expect_true(fs::file_exists(fs::path(env$gov_dir, "projects", ".gitkeep")))
})


# =============================================================================
# datom_attach_gov()
# =============================================================================

# Helper: build a no-gov initialised project + bare gov repo + gov_store_local.
# Returns a list with: conn (developer, no gov), gov_bare, gov_dir, gov_store,
# work_dir, bare_dir.
setup_attach_env <- function(env = parent.frame()) {
  # --- Data side: init a no-gov project --------------------------------------
  bare_dir <- withr::local_tempdir(.local_envir = env)
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- withr::local_tempdir(.local_envir = env)

  data_store <- datom_store_local(
    path = withr::local_tempdir(.local_envir = env),
    validate = FALSE
  )
  store <- datom_store(
    governance    = NULL,
    data          = data_store,
    github_pat    = "ghp_fake",
    data_repo_url = bare_dir,
    validate      = FALSE
  )

  # Mock gov-irrelevant storage during init
  local_mocked_bindings(
    .datom_storage_write_json = function(...) invisible(TRUE),
    .datom_storage_exists     = function(...) FALSE,
    .env = env
  )

  datom_init_repo(path = work_dir, project_name = "attach-proj", store = store)

  # Build a developer conn that mirrors what datom_init_repo() would yield:
  # local data backend, no gov fields.
  conn <- new_datom_conn(
    project_name = "attach-proj",
    backend      = "local",
    root         = data_store$path,
    prefix       = NULL,
    region       = "us-east-1",
    client       = NULL,
    path         = work_dir,
    role         = "developer"
  )

  # --- Gov side: bare gov repo + gov_store_local + clone target -------------
  gov_bare <- withr::local_tempdir(.local_envir = env)
  git2r::init(gov_bare, bare = TRUE)
  gov_dir <- withr::local_tempdir(.local_envir = env)
  # gov_dir was created by withr; .datom_gov_clone_init expects empty/missing.
  fs::dir_delete(gov_dir)

  gov_store <- datom_store_local(
    path = withr::local_tempdir(.local_envir = env),
    validate = FALSE
  )

  list(
    bare_dir  = bare_dir,
    work_dir  = work_dir,
    conn      = conn,
    gov_bare  = gov_bare,
    gov_dir   = gov_dir,
    gov_store = gov_store
  )
}

# --- Validation ---------------------------------------------------------------

test_that("datom_attach_gov rejects non-conn input", {
  gov_store <- datom_store_local(path = withr::local_tempdir(), validate = FALSE)
  expect_error(
    datom_attach_gov(conn = list(), gov_store = gov_store,
                     gov_repo_url = "https://example.com/gov.git"),
    "datom_conn"
  )
})

test_that("datom_attach_gov rejects reader connections", {
  reader <- new_datom_conn(
    project_name = "p", backend = "local",
    root = "/tmp", client = NULL, role = "reader"
  )
  gov_store <- datom_store_local(path = withr::local_tempdir(), validate = FALSE)
  expect_error(
    datom_attach_gov(conn = reader, gov_store = gov_store,
                     gov_repo_url = "https://example.com/gov.git"),
    "developer connection"
  )
})

test_that("datom_attach_gov rejects non-store-component gov_store", {
  env <- setup_attach_env()
  expect_error(
    datom_attach_gov(conn = env$conn, gov_store = list(path = "/tmp"),
                     gov_repo_url = env$gov_bare),
    "datom_store_s3"
  )
})

test_that("datom_attach_gov aborts when both create_repo and gov_repo_url given", {
  env <- setup_attach_env()
  expect_error(
    datom_attach_gov(conn = env$conn, gov_store = env$gov_store,
                     gov_repo_url = env$gov_bare,
                     create_repo = TRUE, repo_name = "gov"),
    "mutually exclusive"
  )
})

test_that("datom_attach_gov aborts when neither create_repo nor gov_repo_url", {
  env <- setup_attach_env()
  expect_error(
    datom_attach_gov(conn = env$conn, gov_store = env$gov_store),
    "No governance repo URL"
  )
})

# --- Happy path ---------------------------------------------------------------

test_that("datom_attach_gov attaches gov, updates project.yaml, returns fresh conn", {
  env <- setup_attach_env()

  result <- datom_attach_gov(
    conn           = env$conn,
    gov_store      = env$gov_store,
    gov_repo_url   = env$gov_bare,
    gov_local_path = env$gov_dir
  )

  # Returned conn has gov fields populated
  expect_s3_class(result, "datom_conn")
  expect_equal(result$gov_root, env$gov_store$path)
  expect_equal(result$gov_local_path, as.character(fs::path_abs(env$gov_dir)))

  # project.yaml updated
  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$storage$governance$type, "local")
  expect_equal(cfg$storage$governance$root, env$gov_store$path)
  expect_equal(cfg$repos$governance$remote_url, env$gov_bare)

  # storage block ordering: governance before data
  expect_equal(names(cfg$storage)[1], "governance")
  expect_equal(names(cfg$storage)[2], "data")

  # gov clone has projects/{name}/ with the three JSON files
  proj_dir <- fs::path(env$gov_dir, "projects", "attach-proj")
  expect_true(fs::dir_exists(proj_dir))
  expect_true(fs::file_exists(fs::path(proj_dir, "dispatch.json")))
  expect_true(fs::file_exists(fs::path(proj_dir, "ref.json")))
  expect_true(fs::file_exists(fs::path(proj_dir, "migration_history.json")))

  # data repo has a new commit
  data_repo <- git2r::repository(env$work_dir)
  msgs <- vapply(git2r::commits(data_repo), function(c) c$message, character(1L))
  expect_true(any(grepl("Attach governance: attach-proj", msgs)))
})

# --- Idempotency --------------------------------------------------------------

test_that("datom_attach_gov is idempotent: second call no-ops with matching URL", {
  env <- setup_attach_env()

  first <- datom_attach_gov(
    conn = env$conn, gov_store = env$gov_store,
    gov_repo_url = env$gov_bare, gov_local_path = env$gov_dir
  )

  data_repo <- git2r::repository(env$work_dir)
  commits_before <- length(git2r::commits(data_repo))

  # Second call -- pass the freshly returned conn
  second <- datom_attach_gov(
    conn = first, gov_store = env$gov_store,
    gov_repo_url = env$gov_bare, gov_local_path = env$gov_dir
  )

  commits_after <- length(git2r::commits(data_repo))
  expect_equal(commits_after, commits_before)
  expect_identical(second$gov_root, first$gov_root)
})

test_that("datom_attach_gov errors on URL mismatch when already attached", {
  env <- setup_attach_env()

  first <- datom_attach_gov(
    conn = env$conn, gov_store = env$gov_store,
    gov_repo_url = env$gov_bare, gov_local_path = env$gov_dir
  )

  expect_error(
    datom_attach_gov(
      conn = first, gov_store = env$gov_store,
      gov_repo_url = "https://example.com/different-gov.git",
      gov_local_path = env$gov_dir
    ),
    "different gov repo"
  )
})


# --- .datom_conn_for(scope) accessor ------------------------------------------

test_that(".datom_conn_for(conn, 'data') returns conn unchanged", {
  conn <- structure(
    list(project_name = "p", backend = "s3", root = "data-bucket",
         prefix = "data/", client = list(tag = "data-client"),
         gov_root = "gov-bucket", gov_prefix = "gov/",
         gov_client = list(tag = "gov-client")),
    class = "datom_conn"
  )
  expect_identical(.datom_conn_for(conn, "data"), conn)
})

test_that(".datom_conn_for(conn) defaults to scope = 'data'", {
  conn <- structure(list(root = "r", gov_root = "g"), class = "datom_conn")
  expect_identical(.datom_conn_for(conn), conn)
})

test_that(".datom_conn_for(conn, 'gov') swaps in governance fields", {
  conn <- structure(
    list(project_name = "p", backend = "s3",
         root = "data-bucket", prefix = "data/", region = "us-east-1",
         client = list(tag = "data-client"),
         gov_root = "gov-bucket", gov_prefix = "gov/", gov_region = "us-west-2",
         gov_client = list(tag = "gov-client"),
         path = NULL, role = "developer", endpoint = NULL),
    class = "datom_conn"
  )

  gov <- .datom_conn_for(conn, "gov")

  expect_s3_class(gov, "datom_conn")
  expect_equal(gov$root, "gov-bucket")
  expect_equal(gov$prefix, "gov/")
  expect_equal(gov$region, "us-west-2")
  expect_equal(gov$client$tag, "gov-client")
  expect_equal(gov$project_name, "p")
})

test_that(".datom_conn_for(conn, 'gov') passes through NULL gov fields without abort", {
  # Pure refactor: the accessor is a shape transform, not a guard.
  # Gov-only commands (datom_sync_dispatch, datom_pull_gov) own the
  # user-facing "no governance attached" error -- see Chunk 7.
  conn <- structure(
    list(project_name = "p", backend = "local", root = "/tmp/r",
         gov_root = NULL, gov_prefix = NULL, gov_client = NULL),
    class = "datom_conn"
  )
  gov <- .datom_conn_for(conn, "gov")
  expect_s3_class(gov, "datom_conn")
  expect_null(gov$root)
  expect_null(gov$client)
})

test_that(".datom_conn_for rejects unknown scope", {
  conn <- structure(list(root = "r"), class = "datom_conn")
  expect_error(.datom_conn_for(conn, "bogus"))
})
