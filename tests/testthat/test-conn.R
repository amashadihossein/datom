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
  expect_match(combined, normalizePath(dir, mustWork = FALSE), fixed = TRUE)
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
                                  min_writer_version = NULL,
                                  schema_version = NULL,
                                  extra = NULL,
                                  env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  datom_dir <- fs::path(dir, ".datom")
  fs::dir_create(datom_dir)

  yaml_content <- list(
    project_name = project_name,
    min_writer_version = min_writer_version,
    storage = list(
      data = list(
        type = "s3",
        root = bucket,
        prefix = prefix,
        region = region
      ),
      max_file_size_gb = 1000
    ),
    repos = list(
      data = list(remote_url = "https://github.com/test/repo.git")
    )
  )

  # Added conditionally, not as a NULL slot: a NULL in the list above round-trips
  # through yaml as `~` and reads back as an explicit NULL, which is a different
  # document from one where the key is simply not there. The absent case is the
  # one every repo written so far is in, so it has to be the real absence.
  if (!is.null(schema_version)) yaml_content$schema_version <- schema_version
  if (!is.null(extra)) yaml_content <- c(yaml_content, extra)

  yaml::write_yaml(yaml_content, fs::path(datom_dir, "project.yaml"))
  dir
}


test_that("developer path reads project.yaml and creates connection", {
  dir <- create_test_datom_repo(project_name = "myproj", bucket = "my-bucket")

  comp <- datom_store_s3(bucket = "my-bucket", prefix = "test-prefix/",
                         access_key = "fake_key",
                         secret_key = "fake_secret", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_fake",
                       data_repo_url = "https://github.com/test/repo.git",
                       validate = FALSE)

  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  conn <- muffle_conn_warnings(datom_get_conn(path = dir, store = store))

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$project_name, "myproj")
  expect_equal(conn$root, "my-bucket")
  expect_equal(conn$role, "developer")
  expect_equal(conn$path, as.character(fs::path_abs(dir)))
})

test_that("developer path carries the repo's declared minimum writer version", {
  # The field is optional and lives in project.yaml. It rides on the connection
  # because that file is already parsed here, which is what lets the write entry
  # check it without an extra read. Absent must stay indistinguishable from "no
  # limit", so both states are asserted.
  comp <- datom_store_s3(bucket = "my-bucket", prefix = "test-prefix/",
                         access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_fake",
                       data_repo_url = "https://github.com/test/repo.git",
                       validate = FALSE)

  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  declared <- create_test_datom_repo(bucket = "my-bucket",
                                     min_writer_version = "9.9.9")
  conn <- muffle_conn_warnings(datom_get_conn(path = declared, store = store))
  expect_identical(conn$min_writer_version, "9.9.9")

  silent <- create_test_datom_repo(bucket = "my-bucket")
  conn <- muffle_conn_warnings(datom_get_conn(path = silent, store = store))
  expect_null(conn$min_writer_version)
})


# --- project.yaml declares its own format --------------------------------------
# The file carries fields a writer must OBEY -- min_writer_version, and mode/set
# for a product repo -- so it needs a way to say "this repo needs a newer datom".
# The reading half cannot be retrofitted into builds already installed, which is
# why it lands before anything starts writing those fields.

conn_schema_store <- function() {
  comp <- datom_store_s3(bucket = "my-bucket", prefix = "test-prefix/",
                         access_key = "k", secret_key = "s", validate = FALSE)
  datom_store(governance = comp, data = comp, github_pat = "ghp_fake",
              data_repo_url = "https://github.com/test/repo.git",
              validate = FALSE)
}

test_that("developer path refuses a project.yaml whose format is too new (AC39a)", {
  store <- conn_schema_store()
  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  dir <- create_test_datom_repo(bucket = "my-bucket",
                                schema_version = .datom_project_schema + 1L)

  err <- expect_error(
    muffle_conn_warnings(datom_get_conn(path = dir, store = store)),
    class = "datom_schema_unsupported"
  )
  msg <- conditionMessage(err)
  # Names the file, so the user knows which document to look at, and points at
  # the upgrade rather than at their credentials.
  expect_match(msg, "project.yaml", fixed = TRUE)
  expect_match(msg, "install_github")
  # Measured against the config's own ceiling, not the repo-wide one.
  expect_match(msg, paste0("supports up to v", .datom_project_schema))
})

test_that("developer path refuses before reading a single field out of the config", {
  # A config this build cannot interpret must not first be mined for a project
  # name or a store cross-check: those produce their own confident errors about
  # the wrong thing. The probe is a config that is too new AND would fail the
  # store cross-check; the format refusal is what has to come back.
  store <- conn_schema_store()
  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  dir <- create_test_datom_repo(bucket = "some-other-bucket",
                                schema_version = .datom_project_schema + 1L)

  expect_error(
    muffle_conn_warnings(datom_get_conn(path = dir, store = store)),
    class = "datom_schema_unsupported"
  )
})

test_that("developer path treats an absent format as v1 and changes nothing (AC39b)", {
  # Every repo written so far is in this state. Not merely "does not abort":
  # no warning and no changed field either, since a silent degradation would be
  # the failure this check exists to remove.
  store <- conn_schema_store()
  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  dir <- create_test_datom_repo(project_name = "silentproj", bucket = "my-bucket")
  cfg <- yaml::read_yaml(fs::path(dir, ".datom", "project.yaml"))
  expect_false("schema_version" %in% names(cfg))

  conn <- muffle_conn_warnings(datom_get_conn(path = dir, store = store))
  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$project_name, "silentproj")

  # And a config declaring the current format behaves identically, so the field's
  # arrival is invisible to everything downstream of it.
  stamped <- create_test_datom_repo(project_name = "silentproj",
                                    bucket = "my-bucket",
                                    schema_version = .datom_project_schema)
  stamped_conn <- muffle_conn_warnings(datom_get_conn(path = stamped, store = store))
  expect_equal(stamped_conn$project_name, conn$project_name)
  expect_equal(stamped_conn$root, conn$root)
})

test_that("developer path still tolerates an unrecognised key in project.yaml (AC39d)", {
  # THE CLAUSE A LATER TIDY-UP BREAKS. project.yaml is hand-edited, so an
  # unrecognised key is as likely a typo or a private note as it is evidence of a
  # newer datom -- which is why the vocabulary check that guards the manifest and
  # per-artifact metadata must NEVER be pointed at this file. Refusing on one
  # would block every write in the repo until somebody found it. Today the
  # tolerance is incidental (the parser ignores keys it does not know); this test
  # is what makes it a decision.
  store <- conn_schema_store()
  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  dir <- create_test_datom_repo(
    bucket = "my-bucket",
    schema_version = .datom_project_schema,
    extra = list(
      a_field_datom_has_never_heard_of = "kept by hand",
      notes = list(owner = "someone", ticket = "ABC-1")
    )
  )

  expect_no_warning(
    conn <- muffle_conn_warnings(datom_get_conn(path = dir, store = store))
  )
  expect_s3_class(conn, "datom_conn")
})

test_that("developer path uses reader role when store is reader", {
  dir <- create_test_datom_repo(project_name = "myproj", bucket = "my-bucket")

  comp <- datom_store_s3(bucket = "my-bucket", prefix = "test-prefix/",
                         access_key = "fake_key",
                         secret_key = "fake_secret", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, validate = FALSE)

  local_mocked_bindings(.datom_s3_client = function(...) mock_s3_client())

  conn <- muffle_conn_warnings(datom_get_conn(path = dir, store = store))

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

  conn <- muffle_conn_warnings(datom_get_conn(path = dir, store = store))
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

  conn <- muffle_conn_warnings(datom_get_conn(path = dir, store = store))
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

test_that("developer path cross-checks prefix mismatch (#74 H)", {
  # Same bucket, different prefix -- e.g. two projects in one bucket. The
  # wrong-prefix store must be rejected, not silently operate on the other
  # project's namespace.
  dir <- create_test_datom_repo(project_name = "myproj", bucket = "shared-bucket",
                                prefix = "project-a/")
  comp <- datom_store_s3(bucket = "shared-bucket", prefix = "project-b/",
                         access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://github.com/test/repo.git",
                       validate = FALSE)

  expect_error(datom_get_conn(path = dir, store = store), "prefix")
})

test_that("developer path prefix check treats NULL and empty as equal (#74 H)", {
  # yaml records an empty prefix (round-trips as empty); the store has no
  # prefix (NULL). Normalization must make these compare equal. Local backend
  # keeps the test off the network.
  store_dir <- as.character(fs::path_norm(withr::local_tempdir()))
  dir <- withr::local_tempdir()
  datom_dir <- fs::path(dir, ".datom")
  fs::dir_create(datom_dir)
  yaml::write_yaml(
    list(
      project_name = "noprefix",
      storage = list(
        data = list(type = "local", root = store_dir, prefix = ""),
        max_file_size_gb = 1000
      ),
      repos = list(data = list(remote_url = "https://github.com/test/repo.git"))
    ),
    fs::path(datom_dir, "project.yaml")
  )
  data_comp <- datom_store_local(path = store_dir, validate = FALSE)
  store <- datom_store(governance = NULL, data = data_comp,
                       github_pat = "ghp_x", validate = FALSE)

  expect_no_error(datom_get_conn(path = dir, store = store))
})


# =============================================================================
# datom_get_conn() — developer path: governance.json four-state matrix
# =============================================================================

# Helper: local-backend repo with project.yaml; optionally writes governance.json.
setup_gov_matrix_env <- function(write_gov_json = FALSE, env = parent.frame()) {
  store_dir <- as.character(fs::path_norm(withr::local_tempdir(.local_envir = env)))
  work_dir  <- withr::local_tempdir(.local_envir = env)
  fs::dir_create(fs::path(work_dir, ".datom"))
  yaml::write_yaml(
    list(
      project_name = "govtest",
      storage = list(
        data = list(type = "local", root = store_dir),
        max_file_size_gb = 1000
      ),
      repos = list(data = list(remote_url = "https://github.com/test/r.git"))
    ),
    fs::path(work_dir, ".datom", "project.yaml")
  )
  if (write_gov_json) {
    gov_json <- list(
      gov_repo_url = "https://github.com/acme/gov.git",
      gov_storage  = list(type = "local", root = as.character(store_dir)),
      attached_at  = "2026-05-23T00:00:00Z"
    )
    jsonlite::write_json(gov_json, fs::path(work_dir, ".datom", "governance.json"),
                         auto_unbox = TRUE, pretty = TRUE)
  }
  list(work_dir = work_dir, store_dir = store_dir)
}

test_that("four-state matrix [no gov.json + no store$gov]: proceeds as no-gov", {
  env <- setup_gov_matrix_env(write_gov_json = FALSE)
  data_comp <- datom_store_local(path = env$store_dir, validate = FALSE)
  store <- datom_store(governance = NULL, data = data_comp,
                       github_pat = "ghp_fake", validate = FALSE)
  conn <- datom_get_conn(path = env$work_dir, store = store)
  expect_s3_class(conn, "datom_conn")
  expect_null(conn$gov_root)
})

test_that("four-state matrix [no gov.json + store$gov set]: warns, treats as no-gov", {
  env <- setup_gov_matrix_env(write_gov_json = FALSE)
  gov_comp  <- datom_store_local(path = env$store_dir, validate = FALSE)
  data_comp <- datom_store_local(path = env$store_dir, validate = FALSE)
  store <- datom_store(governance = gov_comp, data = data_comp,
                       github_pat = "ghp_fake", validate = FALSE)
  expect_warning(
    conn <- muffle_conn_warnings(
      datom_get_conn(path = env$work_dir, store = store),
      pattern = "Could not resolve ref\\.json"
    ),
    "no governance attached"
  )
  # gov fields absent on resulting conn
  expect_null(conn$gov_root)
})

test_that("four-state matrix [gov.json present + no store$gov]: aborts with clear message", {
  env <- setup_gov_matrix_env(write_gov_json = TRUE)
  data_comp <- datom_store_local(path = env$store_dir, validate = FALSE)
  store <- datom_store(governance = NULL, data = data_comp,
                       github_pat = "ghp_fake", validate = FALSE)
  expect_error(
    datom_get_conn(path = env$work_dir, store = store),
    "gov-attached"
  )
})

test_that("four-state matrix [gov.json present + store$gov set]: proceeds with gov fields", {
  env <- setup_gov_matrix_env(write_gov_json = TRUE)
  gov_comp  <- datom_store_local(path = env$store_dir, validate = FALSE)
  data_comp <- datom_store_local(path = env$store_dir, validate = FALSE)
  # No gov_repo_url on store -> cross-check is skipped; gov_local_path=NULL -> no ref resolution
  store <- datom_store(governance = gov_comp, data = data_comp,
                       github_pat = "ghp_fake", validate = FALSE)
  conn <- muffle_conn_warnings(datom_get_conn(path = env$work_dir, store = store))
  expect_s3_class(conn, "datom_conn")
  expect_false(is.null(conn$gov_root))
  expect_equal(conn$gov_root, as.character(env$store_dir))
})

test_that("four-state matrix [gov.json present + store$gov set + URL mismatch]: aborts", {
  env <- setup_gov_matrix_env(write_gov_json = TRUE)
  gov_comp  <- datom_store_local(path = env$store_dir, validate = FALSE)
  data_comp <- datom_store_local(path = env$store_dir, validate = FALSE)
  store <- datom_store(governance = gov_comp, data = data_comp,
                       gov_repo_url = "https://github.com/other/gov.git",
                       github_pat = "ghp_fake", validate = FALSE)
  expect_error(
    datom_get_conn(path = env$work_dir, store = store),
    "mismatch"
  )
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

  conn <- muffle_conn_warnings(datom_get_conn(store = store, project_name = "myproj"))

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

  conn <- muffle_conn_warnings(datom_get_conn(store = store, project_name = "myproj"))
  expect_equal(conn$region, "ap-southeast-1")
})


# =============================================================================
# datom_get_conn() — reader path: Style B (data-first) gov-discovery probe
# =============================================================================

# Local-backend helper: data store dir with optional governance.json mirror
# pre-staged at .metadata/governance.json.
setup_reader_probe_env <- function(write_gov_json = FALSE, env = parent.frame()) {
  store_dir <- as.character(fs::path_norm(withr::local_tempdir(.local_envir = env)))
  # Mirror lives at {root}/datom/.metadata/governance.json
  meta_dir <- fs::path(store_dir, "datom", ".metadata")
  fs::dir_create(meta_dir)
  if (write_gov_json) {
    gov_json <- list(
      gov_repo_url = "https://github.com/acme/gov.git",
      gov_storage  = list(type = "local", root = store_dir),
      attached_at  = "2026-05-23T00:00:00Z"
    )
    jsonlite::write_json(gov_json, fs::path(meta_dir, "governance.json"),
                         auto_unbox = TRUE, pretty = TRUE)
  }
  store_dir
}

test_that("reader Style B [no-gov data store, no gov.json mirror]: no warning, conn built", {
  store_dir <- setup_reader_probe_env(write_gov_json = FALSE)
  data_comp <- datom_store_local(path = store_dir, validate = FALSE)
  store <- datom_store(governance = NULL, data = data_comp, validate = FALSE)
  expect_no_warning(
    conn <- datom_get_conn(store = store, project_name = "p")
  )
  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$root, store_dir)
  expect_null(conn$gov_root)
})

test_that("reader Style B [no-gov data store, gov.json mirror present]: warns, conn built", {
  store_dir <- setup_reader_probe_env(write_gov_json = TRUE)
  data_comp <- datom_store_local(path = store_dir, validate = FALSE)
  store <- datom_store(governance = NULL, data = data_comp, validate = FALSE)
  expect_warning(
    conn <- datom_get_conn(store = store, project_name = "p"),
    "governance attached"
  )
  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$root, store_dir)
  expect_null(conn$gov_root)
})

test_that("reader Style A [gov store supplied]: skips data-first probe", {
  store_dir <- setup_reader_probe_env(write_gov_json = TRUE)
  data_comp <- datom_store_local(path = store_dir, validate = FALSE)
  gov_comp  <- datom_store_local(path = store_dir, validate = FALSE)
  # gov-first: no warning about data-first bypass even when gov.json mirror exists.
  # Suppress the unrelated ref-resolution warning (no projects/p/ref.json in this
  # synthetic local store) by checking that no "governance attached, but you
  # connected with data-store credentials only" warning is emitted.
  warnings_seen <- character(0)
  withCallingHandlers(
    conn <- datom_get_conn(store = datom_store(governance = gov_comp, data = data_comp, validate = FALSE),
                            project_name = "p"),
    warning = function(w) {
      warnings_seen <<- c(warnings_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_false(any(grepl("data-store credentials only", warnings_seen)))
  expect_s3_class(conn, "datom_conn")
})


# =============================================================================
# datom_get_conn() — reader path: datom_store_s3_creds bootstrap (Chunk 6)
# =============================================================================

# Helper: set up a local gov store with projects/p/ref.json staged at the
# correct path for local-backend resolution.
setup_creds_ref_env <- function(
    data_root  = NULL,
    data_prefix = NULL,
    data_region = "eu-west-1",
    env = parent.frame()
) {
  gov_store_dir <- as.character(fs::path_norm(withr::local_tempdir(.local_envir = env)))
  # ref.json lives at {gov_root}/datom/projects/p/ref.json
  ref_dir <- fs::path(gov_store_dir, "datom", "projects", "p")
  fs::dir_create(ref_dir)
  effective_data_root <- data_root %||% as.character(
    fs::path_norm(withr::local_tempdir(.local_envir = env))
  )
  ref_content <- list(
    current = list(
      type   = "local",
      root   = effective_data_root,
      prefix = data_prefix,
      region = data_region
    ),
    previous = list()
  )
  jsonlite::write_json(ref_content, fs::path(ref_dir, "ref.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null")
  list(gov_store_dir = gov_store_dir, data_root = effective_data_root)
}

test_that("reader creds-only: conn has root/prefix/region from ref.json", {
  env <- setup_creds_ref_env(data_prefix = "proj/", data_region = "eu-west-1")
  gov_comp   <- datom_store_local(path = env$gov_store_dir, validate = FALSE)
  creds_comp <- datom_store_s3_creds(access_key = "AKIA", secret_key = "sec")
  store <- datom_store(governance = gov_comp, data = creds_comp, validate = FALSE)

  local_mocked_bindings(
    .datom_s3_client = function(...) mock_s3_client()
  )

  conn <- datom_get_conn(store = store, project_name = "p")

  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$root, env$data_root)
  expect_equal(conn$prefix, "proj/")
  expect_equal(conn$region, "eu-west-1")
  expect_equal(conn$backend, "s3")
})

test_that("reader creds-only: hard abort when ref.json is absent", {
  gov_store_dir <- as.character(fs::path_norm(withr::local_tempdir()))
  # Create gov root directory structure but no ref.json
  fs::dir_create(fs::path(gov_store_dir, "datom", "projects", "p"))
  gov_comp   <- datom_store_local(path = gov_store_dir, validate = FALSE)
  creds_comp <- datom_store_s3_creds(access_key = "AKIA", secret_key = "sec")
  store <- datom_store(governance = gov_comp, data = creds_comp, validate = FALSE)

  expect_error(
    muffle_conn_warnings(datom_get_conn(store = store, project_name = "p")),
    "datom_store_s3_creds.*no location|no location.*datom_store_s3_creds|ref.json could not"
  )
})

test_that("reader creds-only: region defaults to us-east-1 when absent from ref", {
  gov_store_dir <- as.character(fs::path_norm(withr::local_tempdir()))
  data_root <- as.character(fs::path_norm(withr::local_tempdir()))
  ref_dir <- fs::path(gov_store_dir, "datom", "projects", "p")
  fs::dir_create(ref_dir)
  # ref.json with no region field
  jsonlite::write_json(
    list(current = list(type = "local", root = data_root, prefix = NULL), previous = list()),
    fs::path(ref_dir, "ref.json"), auto_unbox = TRUE, null = "null"
  )
  gov_comp   <- datom_store_local(path = gov_store_dir, validate = FALSE)
  creds_comp <- datom_store_s3_creds(access_key = "AKIA", secret_key = "sec")
  store <- datom_store(governance = gov_comp, data = creds_comp, validate = FALSE)

  local_mocked_bindings(
    .datom_s3_client = function(...) mock_s3_client()
  )

  conn <- datom_get_conn(store = store, project_name = "p")
  expect_equal(conn$region, "us-east-1")
})

test_that("reader fully-specified store: unchanged behavior (no regression)", {
  # A normal datom_store_local data component still works as before.
  env <- setup_creds_ref_env()
  data_comp <- datom_store_local(path = env$data_root, validate = FALSE)
  gov_comp  <- datom_store_local(path = env$gov_store_dir, validate = FALSE)
  store <- datom_store(governance = gov_comp, data = data_comp, validate = FALSE)
  conn <- datom_get_conn(store = store, project_name = "p")
  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$root, env$data_root)
})


# =============================================================================
# datom_get_conn() — developer path: datom_store_s3_creds bootstrap (Chunk 6)
# =============================================================================

setup_creds_dev_env <- function(data_prefix = NULL, data_region = "ap-southeast-1",
                                env = parent.frame()) {
  gov_store_dir <- as.character(fs::path_norm(withr::local_tempdir(.local_envir = env)))
  data_root     <- as.character(fs::path_norm(withr::local_tempdir(.local_envir = env)))
  work_dir      <- withr::local_tempdir(.local_envir = env)
  fs::dir_create(fs::path(work_dir, ".datom"))

  # Stage ref.json in gov store
  ref_dir <- fs::path(gov_store_dir, "datom", "projects", "p")
  fs::dir_create(ref_dir)
  jsonlite::write_json(
    list(
      current = list(type = "local", root = data_root, prefix = data_prefix,
                     region = data_region),
      previous = list()
    ),
    fs::path(ref_dir, "ref.json"), auto_unbox = TRUE, null = "null", pretty = TRUE
  )

  # Stage ref.json in gov clone too (developer reads from clone when available)
  gov_clone_dir <- as.character(fs::path_norm(withr::local_tempdir(.local_envir = env)))
  clone_ref_dir <- fs::path(gov_clone_dir, "projects", "p")
  fs::dir_create(clone_ref_dir)
  jsonlite::write_json(
    list(
      current = list(type = "local", root = data_root, prefix = data_prefix,
                     region = data_region),
      previous = list()
    ),
    fs::path(clone_ref_dir, "ref.json"), auto_unbox = TRUE, null = "null", pretty = TRUE
  )

  # Stage governance.json in work_dir so gov detection triggers
  gov_json <- list(
    gov_repo_url = "https://github.com/acme/gov.git",
    gov_storage  = list(type = "local", root = gov_store_dir),
    attached_at  = "2026-05-23T00:00:00Z"
  )
  jsonlite::write_json(gov_json, fs::path(work_dir, ".datom", "governance.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  # project.yaml with data root (will be cross-checked only when data_root is non-NULL)
  yaml::write_yaml(
    list(
      project_name = "p",
      storage = list(
        data = list(type = "local", root = data_root),
        max_file_size_gb = 1000
      ),
      repos = list(data = list(remote_url = "https://github.com/test/r.git"))
    ),
    fs::path(work_dir, ".datom", "project.yaml")
  )

  list(work_dir = work_dir, gov_clone_dir = gov_clone_dir,
       gov_store_dir = gov_store_dir, data_root = data_root)
}

test_that("developer creds-only: conn has root/prefix/region from ref.json", {
  env <- setup_creds_dev_env(data_prefix = "myproj/", data_region = "ap-southeast-1")
  gov_comp   <- datom_store_local(path = env$gov_store_dir, validate = FALSE)
  creds_comp <- datom_store_s3_creds(access_key = "AKIA", secret_key = "sec")
  store <- datom_store(governance = gov_comp, data = creds_comp,
                       gov_local_path = env$gov_clone_dir,
                       github_pat = "ghp_fake", validate = FALSE)

  local_mocked_bindings(
    .datom_s3_client = function(...) mock_s3_client()
  )

  conn <- datom_get_conn(path = env$work_dir, store = store)
  expect_s3_class(conn, "datom_conn")
  expect_equal(conn$root, env$data_root)
  expect_equal(conn$prefix, "myproj/")
  expect_equal(conn$region, "ap-southeast-1")
  expect_equal(conn$backend, "s3")
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
  # governance coordinates are NOT stored in project.yaml (live in governance.json)
  expect_null(cfg$storage$governance)
  expect_null(cfg$repos$governance)
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
  # governance.json not written when store$gov_repo_url is absent
  gov_json_path <- fs::path(env$work_dir, ".datom", "governance.json")
  expect_false(fs::file_exists(gov_json_path))
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
  expect_equal(manifest$summary$total_sets, 0)
  # A repo declares its format from the moment it is created, so none exists in
  # a state that declares nothing -- not even before its first artifact.
  expect_equal(manifest$schema_version, 2L)
  expect_true("artifacts" %in% names(manifest))
  expect_null(manifest$tables)
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

test_that("datom_init_repo stamps project.yaml's own format, on the written file (AC39c)", {
  # Asserted on the file rather than on the in-memory config, because the one
  # thing this clause is about is what yaml::write_yaml() did with an integer: a
  # value that round-trips as a string would fail the checker as corrupt.
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$schema_version, .datom_project_schema)
  expect_length(cfg$schema_version, 1L)
  expect_true(is.numeric(cfg$schema_version))

  # And the stamped value survives its own checker, which is the round trip that
  # matters: a repo this build creates must be one this build can open.
  expect_equal(
    .datom_check_project_schema(cfg, "project.yaml"),
    .datom_project_schema
  )
})

test_that("datom_init_repo stamps the config's number, not the repo-wide one", {
  # The two constants are different numbers on purpose. Stamping the repo-wide
  # ceiling here would tie this file's declared shape to every manifest and
  # metadata bump, and a build one bump behind would then lose the whole
  # developer path on a config whose shape never changed.
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  manifest <- jsonlite::read_json(fs::path(env$work_dir, ".datom", "manifest.json"))

  expect_equal(cfg$schema_version, .datom_project_schema)
  expect_equal(manifest$schema_version, .datom_supported_schema)
})

test_that("project.yaml's key set is pinned to its declared format", {
  # TRIPWIRE, and it forces a DECISION rather than mandating a bump. The one real
  # hole in giving this file its own number is a FORGOTTEN bump: a shape change
  # shipped with the number unmoved is silently misread by an older build. This
  # test goes red whenever the keys datom_init_repo() writes change.
  #
  # WHAT TO DO WHEN IT FIRES. An addition is reader-safe -- an older build never
  # asks for a key it does not know -- so the usual answer is to extend the list
  # below and leave .datom_project_schema alone. The worked case is `mode` and
  # `set` for a product repo: the correct response to those is no bump, because an
  # older build's misreading of `mode` is a silent no-op rather than a wrong write.
  # THE STANDARD THIS TEST HAS TO MEET, which is wider than any one key: it must
  # exercise EVERY path that writes project.yaml, and adding such a path means
  # adding a case here. It only sees the creation path it calls, so a key written
  # conditionally -- for a product repo, say -- is invisible to it, and the guard
  # then looks like a guard while saying nothing about exactly the addition it was
  # written for. Two paths write this file today: this one and
  # datom_repo_set_data_store(), which read-modify-writes and so preserves keys by
  # construction -- tested anyway, because a refactor to rebuilding the document
  # would drop most of them with nothing else failing.
  #
  # Move the number when a key is RENAMED, MOVED
  # to a different parent, REMOVED, or changes meaning or type -- the cases where
  # an older build reads the file and gets a wrong answer rather than a missing
  # one.
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))

  expected_keys <- c(
    "project_name", "project_description", "created_at", "datom_version",
    "schema_version", "storage", "repos", "sync", "renv"
  )
  expect_setequal(names(cfg), expected_keys)
  expect_equal(.datom_project_schema, 1L)
})

test_that("a product repo's project.yaml key set is pinned too", {
  # THE SECOND CASE THE RULE ABOVE REQUIRES. `mode` and `set` are written only for
  # a product repo, so the ordinary-init test cannot see them -- it would stay green
  # through any change to them, which is the guard looking like a guard while saying
  # nothing about the addition it was written for.
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store, mode = "product", set = "study001-adam")

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))

  expected_keys <- c(
    "project_name", "project_description", "created_at", "datom_version",
    "schema_version", "storage", "repos", "sync", "renv", "mode", "set"
  )
  expect_setequal(names(cfg), expected_keys)
  # Adding these two keys is an addition, so the declared format does NOT move --
  # an older build never asks for a key it does not know, and its misreading of
  # `mode` is a silent no-op rather than a wrong write.
  expect_equal(cfg$schema_version, .datom_project_schema)
  expect_equal(.datom_project_schema, 1L)
})

test_that("the store-pointer verb preserves every key in project.yaml", {
  # THE THIRD CASE THE RULE REQUIRES, and the reason it is not hypothetical: this
  # verb is the only writer of this file besides init. It read-modify-writes, so it
  # preserves keys by construction -- which is exactly why it is tested, because a
  # refactor to rebuilding the document from the connection would drop most of them
  # with nothing else failing.
  skip_if_not_installed("git2r")
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store, mode = "product", set = "product-a")

  yaml_path <- fs::path(env$work_dir, ".datom", "project.yaml")
  before <- names(yaml::read_yaml(yaml_path))

  new_store <- datom_store_local(withr::local_tempdir(), validate = FALSE)
  conn <- structure(
    list(project_name = "testproj", role = "developer",
         path = as.character(env$work_dir), gov_root = NULL, github_pat = NULL),
    class = "datom_conn"
  )
  local_mocked_bindings(.datom_git_push = function(...) invisible(TRUE))

  datom_repo_set_data_store(conn, new_store)

  expect_setequal(names(yaml::read_yaml(yaml_path)), before)
})

test_that("datom_init_repo declares mode and set only when asked", {
  # Absent IS "ordinary data repo" to every reader of this file, so there is no
  # `mode: standard` line for that state. And the keys must be genuinely absent
  # rather than written as yaml `~`: a NULL in a list() constructor is a present
  # element, which would read back as a declared empty value.
  env <- setup_init_env()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_false("mode" %in% names(cfg))
  expect_false("set" %in% names(cfg))

  # And what it writes for a product repo is exactly what the set-write gate
  # reads, which is the whole point of writing it.
  env2 <- setup_init_env()
  datom_init_repo(path = env2$work_dir, project_name = "testproj",
                  store = env2$store, mode = "product", set = "product-a")
  cfg2 <- yaml::read_yaml(fs::path(env2$work_dir, ".datom", "project.yaml"))
  expect_identical(cfg2$mode, "product")
  expect_identical(cfg2$set, "product-a")
})

test_that("datom_init_repo refuses a product repo that names no set", {
  # A product repo with no set passes the set-write mode check and then fails its
  # name check on every write -- a repo that looks initialised and is not. Caught
  # at the call that could have got it right.
  env <- setup_init_env()

  err <- expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    store = env$store, mode = "product"),
    "must name the set"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "datom_write_set")
  expect_false(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})

test_that("datom_init_repo refuses a set name without the product mode", {
  env <- setup_init_env()

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    store = env$store, set = "product-a"),
    "without"
  )
})

test_that("datom_init_repo refuses a mode it does not recognise", {
  # A typo must not become a repo that quietly behaves as an ordinary one.
  env <- setup_init_env()

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    store = env$store, mode = "prodcut", set = "s"),
    "must be"
  )
})

test_that("datom_init_repo validates a set name through the shared validator", {
  # The same function the set-write gate calls, so the two cannot disagree about
  # what a legal name is -- otherwise init accepts a name no write can use.
  # A space is legal in a datom name, so the probe has to be a name the shared
  # validator actually rejects -- one that does not start with a letter.
  env <- setup_init_env()

  expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    store = env$store, mode = "product", set = "9lives"),
    "must start with a letter"
  )

  env2 <- setup_init_env()
  expect_error(
    datom_init_repo(path = env2$work_dir, project_name = "testproj",
                    store = env2$store, mode = "product", set = "bad/name"),
    "may only contain"
  )
})

test_that("a product repo's namespace is checked on a local store and cannot be forced (AC22)", {
  # Two widenings of one condition, both scoped to product repos. Ordinary repos
  # keep the s3-only scope and the .force override exactly as they had them: the
  # blast-radius argument is about a product sitting on top of data it did not
  # produce, since teardown and prefix-delete operate on a whole namespace.
  bare <- withr::local_tempdir()
  git2r::init(bare, bare = TRUE)
  store_dir <- withr::local_tempdir()
  local_store <- datom_store_local(store_dir, prefix = "proj", validate = FALSE)
  store <- datom_store(data = local_store, github_pat = "ghp_fake",
                       data_repo_url = bare, validate = FALSE)

  local_mocked_bindings(
    .datom_storage_exists = function(conn, key) grepl("manifest\\.json", key),
    .datom_storage_read_json = function(conn, key) list(project_name = "SOURCE_STUDY"),
    .datom_storage_write_json = function(...) invisible(TRUE)
  )

  # Local backend: an ordinary repo is not checked at all, so this is the widening.
  product_dir <- withr::local_tempdir()
  err <- expect_error(
    datom_init_repo(path = product_dir, project_name = "testproj", store = store,
                    mode = "product", set = "product-a"),
    class = "datom_namespace_occupied"
  )
  expect_match(conditionMessage(err), "SOURCE_STUDY")

  # .force does not buy a product repo its way in. It is refused at the argument
  # check, before the namespace is even looked at -- see the test below for why
  # that rather than silently dropping it.
  forced_dir <- withr::local_tempdir()
  expect_error(
    datom_init_repo(path = forced_dir, project_name = "testproj", store = store,
                    mode = "product", set = "product-a", .force = TRUE),
    "does not apply"
  )

  # An ordinary local repo is unaffected: no check, so an occupied namespace does
  # not stop it. Recorded rather than fixed -- closing it is a behaviour change for
  # every local repo and its own decision.
  ordinary_dir <- withr::local_tempdir()
  expect_no_error(
    datom_init_repo(path = ordinary_dir, project_name = "testproj", store = store)
  )
})

test_that("datom_init_repo refuses .force on a product repo rather than dropping it", {
  # REFUSED, NOT IGNORED, and the argument is the same one that refuses a version
  # supplied beside a member record which already carries one: ignoring an
  # argument reports success for an action nobody asked for. Here the caller
  # requested a namespace takeover, would not have got one, and would never have
  # been told -- so next time they would rely on an override that does not exist.
  #
  # It fires at the argument check, before the namespace is consulted, so it does
  # not depend on the namespace being occupied.
  env <- setup_init_env()

  err <- expect_error(
    datom_init_repo(path = env$work_dir, project_name = "testproj",
                    store = env$store, mode = "product", set = "product-a",
                    .force = TRUE),
    "does not apply"
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  # Says why there is no override, not merely that there is none.
  expect_match(msg, "teardown")
  expect_false(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})

test_that("an occupied-namespace refusal advises .force only where .force works", {
  # THE CIRCLE THIS CLOSES. The refusal's recourse used to end with "pass
  # .force = TRUE to override" whatever the caller's policy was -- so a product
  # repo meeting an occupied namespace was routed into a flag that changes
  # nothing there. Same shape as the message that said "S3" to a local store: the
  # checker cannot know its caller's policy, so the caller declares it.
  local_mocked_bindings(
    .datom_storage_exists = function(conn, key) TRUE,
    .datom_storage_read_json = function(conn, key) list(project_name = "OTHER")
  )
  conn <- mock_datom_conn(list())

  ordinary <- expect_error(.datom_check_namespace_free(conn),
                           class = "datom_namespace_occupied")
  expect_match(cli::ansi_strip(conditionMessage(ordinary)), ".force = TRUE",
               fixed = TRUE)

  product <- expect_error(
    .datom_check_namespace_free(conn, overridable = FALSE),
    class = "datom_namespace_occupied"
  )
  msg <- cli::ansi_strip(conditionMessage(product))
  expect_no_match(msg, ".force", fixed = TRUE)
  # And still says what DOES work, plus why the override is absent.
  expect_match(msg, "prefix")
  expect_match(msg, "teardown")
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
  # No new sibling directories (gov clone would be one). unname() because
  # fs::dir_ls() returns a named vector and expect_setequal() ignores names.
  expect_setequal(unname(before), unname(after))
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


# --- Init is data-only: gov store arg is ignored (R4) ------------------------

# Helper: extends setup_init_env() with a bare gov repo + gov_repo_url on the
# store. datom_init_repo must ignore the gov component and produce a solo project.
setup_init_env_with_gov <- function(env = parent.frame()) {
  base <- setup_init_env(env = env)

  gov_bare <- withr::local_tempdir(.local_envir = env)
  git2r::init(gov_bare, bare = TRUE)
  gov_local <- withr::local_tempdir(.local_envir = env)
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

test_that("datom_init_repo ignores a gov store arg and initializes a solo project", {
  env <- setup_init_env_with_gov()

  datom_init_repo(path = env$work_dir, project_name = "testproj",
                  store = env$store)

  # No gov clone created (init does no gov interaction)
  expect_false(fs::dir_exists(env$gov_local))

  # project.yaml carries no governance coordinates
  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_null(cfg$storage$governance)
  expect_null(cfg$repos$governance)

  # No governance.json written -> project is not gov-attached
  expect_false(fs::file_exists(fs::path(env$work_dir, ".datom", "governance.json")))

  # No project registered in the gov repo
  expect_false(fs::dir_exists(fs::path(env$gov_local, "projects", "testproj")))
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

test_that("datom_init_repo passes session_token to the namespace-check client (#74 B)", {
  bare_dir <- withr::local_tempdir()
  git2r::init(bare_dir, bare = TRUE)
  work_dir <- withr::local_tempdir()

  comp <- datom_store_s3(
    bucket = "test-bucket", prefix = "proj/",
    access_key = "AKIAEXAMPLE", secret_key = "secretkey",
    session_token = "FQoGZXIvYXdzToken",
    validate = FALSE
  )
  store <- datom_store(
    governance = comp, data = comp,
    github_pat = "ghp_fake", data_repo_url = bare_dir,
    validate = FALSE
  )

  captured_token <- "unset"
  local_mocked_bindings(
    .datom_s3_client = function(access_key, secret_key, region = "us-east-1",
                                endpoint = NULL, session_token = NULL) {
      captured_token <<- session_token
      list(put_object = function(...) list())
    },
    .datom_storage_write_json = function(...) invisible(TRUE),
    # Report the namespace occupied so init aborts right after the check
    # client is built -- the STS credentials must reach that client.
    .datom_storage_exists = function(conn, s3_key) grepl("manifest\\.json", s3_key),
    .datom_storage_read_json = function(conn, s3_key) {
      list(project_name = "EXISTING_PROJECT", tables = list())
    }
  )

  expect_error(
    datom_init_repo(path = work_dir, project_name = "testproj", store = store),
    "already occupied"
  )
  expect_equal(captured_token, "FQoGZXIvYXdzToken")
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

test_that("datom_init_repo does not swallow an unrecognised namespace-check failure", {
  # THE HAZARD THE CONDITION CLASS ALONE DOES NOT CLOSE, and it lives here because
  # the caller is what used to swallow. This wrapped the whole check in a handler
  # that re-raised only what it recognised by message text and downgraded
  # everything else to a warning -- so any abort added inside the check later
  # became a warning, and init carried on, with nothing failing to say so.
  #
  # The store-unreachable tolerance is now scoped to the one storage call inside
  # the check (see the test below, which still passes), so a failure for any other
  # reason reaches the user.
  env <- setup_init_env()

  local_mocked_bindings(
    .datom_check_namespace_free = function(conn, ...) {
      cli::cli_abort("a refusal this build did not anticipate")
    }
  )

  expect_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      store = env$store
    ),
    "did not anticipate"
  )
})

test_that("datom_init_repo dispatches the occupied refusal on its class, not its text", {
  # The refusal must survive a reword of its own message. Six tests grep the
  # phrase "already occupied", which is why the old text-matched re-raise was
  # noisy rather than silent -- but noise in the suite is not a design, and the
  # coupling is what this removes.
  env <- setup_init_env()

  local_mocked_bindings(
    .datom_check_namespace_free = function(conn, ...) {
      cli::cli_abort("wording nobody greps for",
                     class = "datom_namespace_occupied")
    }
  )

  expect_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      store = env$store
    ),
    class = "datom_namespace_occupied"
  )
})

test_that("datom_init_repo refuses when storage connectivity fails during the namespace check", {
  # BEHAVIOUR CHANGE, deliberate and loud. This used to warn and continue, which
  # read as a graceful degradation and was not one: it did not defer the occupancy
  # check, it removed it. Traced end to end -- init went on to push the git repo,
  # then aborted at the manifest upload, and the recovery that abort pointed at
  # performs no occupancy check of any kind. So the tolerance never produced a
  # working offline init, because storage is required to finish one; its only
  # reachable effect was getting past the check, with a manifest written over
  # another project's as the outcome.
  #
  # Refusing at the check costs nothing that worked before and names the real
  # problem at the moment it is known, instead of surfacing later as an unrelated
  # upload failure.
  env <- setup_init_env()

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) stop("Network error"),
    .datom_storage_write_json = function(...) invisible(TRUE)
  )

  expect_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      store = env$store
    ),
    class = "datom_namespace_unverified"
  )

  # And it refuses before anything local is created, like the occupied refusal.
  expect_false(fs::dir_exists(fs::path(env$work_dir, ".datom")))
})

test_that("datom_init_repo's manifest-upload recovery names a verb that can do it", {
  # The hint used to say datom_sync_manifest(), which scans `input_files/` and
  # returns a data frame of statuses -- it writes nothing to storage, so the
  # advice could not work. The verb that mirrors metadata is internal and is
  # reached through datom_validate(fix = TRUE).
  env <- setup_init_env()

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) FALSE,
    .datom_storage_write_json = function(...) stop("storage gone")
  )

  err <- expect_error(
    datom_init_repo(
      path = env$work_dir,
      project_name = "testproj",
      store = env$store
    ),
    "manifest upload failed"
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "datom_validate", fixed = TRUE)
  expect_no_match(msg, "datom_sync_manifest", fixed = TRUE)
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

  conn <- muffle_conn_warnings(datom_get_conn(
    path = dir,
    store = store,
    endpoint = "https://my-endpoint.com"
  ))

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

  conn <- muffle_conn_warnings(datom_get_conn(
    store = store,
    project_name = "proj",
    endpoint = "https://reader-endpoint.com"
  ))

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

  conn <- muffle_conn_warnings(datom_get_conn(store = store, project_name = "proj"))

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
                refspec = test_head_refspec(work_repo), set_upstream = TRUE)

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
                refspec = test_head_refspec(work_repo), set_upstream = TRUE)

    comp <- datom_store_s3(bucket = "test-bucket", access_key = "fakekey",
                           secret_key = "fakesecret", validate = FALSE)
    store <- datom_store(governance = comp, data = comp, github_pat = "fake-pat",
                         data_repo_url = bare_dir, validate = FALSE)

    local_mocked_bindings(
      .datom_s3_client = function(...) list(fake = TRUE)
    )

    conn <- muffle_conn_warnings(datom_clone(path = "clone_target", store = store))

    expect_s3_class(conn, "datom_conn")
    expect_equal(conn$project_name, "MYPROJ")
    expect_equal(conn$root, "test-bucket")
    expect_true(fs::dir_exists("clone_target/.datom"))
    expect_true(fs::file_exists("clone_target/.datom/project.yaml"))
  })
})

test_that("datom_clone sets a local git identity on the fresh clone (#74 E)", {
  withr::with_tempdir({
    # Point HOME/XDG at empty dirs so there is no global git identity --
    # mimics a CI runner / fresh box. Without the local-identity fix the
    # first datom_write() commit would fail in git2r::commit().
    empty_home <- withr::local_tempdir()
    withr::local_envvar(
      HOME = empty_home,
      XDG_CONFIG_HOME = empty_home
    )

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
          data = list(type = "s3", root = "test-bucket", region = "us-east-1")
        )
      ),
      fs::path(work_dir, ".datom", "project.yaml")
    )
    git2r::add(work_repo, ".datom/project.yaml")
    git2r::commit(work_repo, "Init datom")
    git2r::remote_add(work_repo, name = "origin", url = bare_dir)
    git2r::push(work_repo, name = "origin",
                refspec = test_head_refspec(work_repo), set_upstream = TRUE)

    comp <- datom_store_s3(bucket = "test-bucket", access_key = "fakekey",
                           secret_key = "fakesecret", validate = FALSE)
    store <- datom_store(governance = comp, data = comp, github_pat = "fake-pat",
                         data_repo_url = bare_dir, validate = FALSE)

    local_mocked_bindings(.datom_s3_client = function(...) list(fake = TRUE))

    muffle_conn_warnings(datom_clone(path = "clone_target", store = store))

    cloned_repo <- git2r::repository("clone_target")
    local_cfg <- git2r::config(cloned_repo)$local
    expect_true(!is.null(local_cfg$user.name) && nzchar(local_cfg$user.name))
    expect_true(!is.null(local_cfg$user.email) && nzchar(local_cfg$user.email))
  })
})

test_that("datom_clone aborts on clone failure", {
  comp <- datom_store_s3(bucket = "b", access_key = "k", secret_key = "s", validate = FALSE)
  store <- datom_store(governance = comp, data = comp, github_pat = "ghp_x",
                       data_repo_url = "https://example.com/no-such-repo.git",
                       validate = FALSE)
  withr::with_tempdir({
    # Simulate the clone failure locally -- stub git2r::clone so no real network
    # connection is attempted (previously libgit2 actually dialed example.com).
    mockery::stub(datom_clone, "git2r::clone",
                  function(...) stop("simulated clone failure"))
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
  git2r::push(work_repo, "origin", test_head_refspec(work_repo), set_upstream = TRUE)
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

    muffle_conn_warnings(datom_clone(path = "clone_target", store = store))

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
    expect_no_error(muffle_conn_warnings(datom_clone(path = "clone_target", store = store)))
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

  # Check project.yaml has local backend; no governance block (lives in governance.json)
  cfg <- yaml::read_yaml(fs::path(env$work_dir, ".datom", "project.yaml"))
  expect_equal(cfg$storage$data$type, "local")
  expect_null(cfg$storage$governance)
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

  conn <- muffle_conn_warnings(datom_get_conn(path = env$work_dir, store = env$store))

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
         gov_backend = "local", gov_client = list(tag = "gov-client"),
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
  # backend comes from gov_backend (gov store), independent of data backend
  expect_equal(gov$backend, "local")
})

test_that(".datom_conn_for(conn, 'gov') passes through NULL gov fields without abort", {
  # Pure shape transform, not a guard. Gov-only commands own the user-facing
  # "no governance attached" error before reaching this accessor.
  conn <- structure(
    list(project_name = "p", backend = "local", root = "/tmp/r",
         gov_root = NULL, gov_prefix = NULL, gov_backend = NULL,
         gov_client = NULL),
    class = "datom_conn"
  )
  gov <- .datom_conn_for(conn, "gov")
  expect_s3_class(gov, "datom_conn")
  expect_null(gov$root)
  expect_null(gov$client)
  expect_null(gov$backend)
})

test_that(".datom_conn_for rejects unknown scope", {
  conn <- structure(list(root = "r"), class = "datom_conn")
  expect_error(.datom_conn_for(conn, "bogus"))
})


# --- gov_backend field + C6 conn interface ------------------------------------

test_that("new_datom_conn carries gov_backend (NULL by default)", {
  conn <- new_datom_conn(
    project_name = "p",
    root = "b",
    region = "us-east-1",
    client = mock_s3_client()
  )
  expect_true("gov_backend" %in% names(conn))
  expect_null(conn$gov_backend)
})

test_that("new_datom_conn sets gov_backend when supplied", {
  conn <- new_datom_conn(
    project_name = "p",
    root = "b",
    region = "us-east-1",
    client = mock_s3_client(),
    gov_root = "gov-bucket",
    gov_backend = "local"
  )
  expect_equal(conn$gov_backend, "local")
})

test_that("Property 4: all twelve C6 fields present on every conn produced by new_datom_conn", {
  # Feature: gov-seam-liftout, Property 4: Twelve conn fields present on all conns.
  # Battery over solo/governed x data backend x gov backend; loop asserts every
  # conn produced by new_datom_conn carries all twelve fields as named entries
  # (gov-scoped fields MAY be NULL on solo).
  c6_fields <- c(
    "gov_local_path", "gov_root", "gov_prefix", "gov_region", "gov_backend",
    "gov_client", "github_pat", "project_name", "backend", "root", "prefix",
    "region"
  )

  configs <- list(
    # solo, data on s3
    list(root = "b", region = "us-east-1", client = mock_s3_client(),
         backend = "s3"),
    # solo, data on local
    list(root = "/tmp/d", region = "us-east-1", client = NULL,
         backend = "local"),
    # governed, data s3 / gov s3
    list(root = "b", region = "us-east-1", client = mock_s3_client(),
         backend = "s3", gov_root = "g", gov_backend = "s3",
         gov_client = mock_s3_client(), github_pat = "ghp_x"),
    # governed, data s3 / gov local (mixed backend)
    list(root = "b", region = "us-east-1", client = mock_s3_client(),
         backend = "s3", gov_root = "/tmp/g", gov_backend = "local",
         github_pat = "ghp_x"),
    # governed, data local / gov s3 (mixed backend)
    list(root = "/tmp/d", region = "us-east-1", client = NULL,
         backend = "local", gov_root = "g", gov_backend = "s3",
         gov_client = mock_s3_client(), github_pat = "ghp_x")
  )

  purrr::walk(configs, function(cfg) {
    conn <- do.call(new_datom_conn, c(list(project_name = "p"), cfg))
    purrr::walk(c6_fields, function(f) {
      expect_true(f %in% names(conn),
                  info = paste("missing field:", f))
    })
  })
})

test_that("Property 5: .datom_conn_for(conn,'gov')$backend == gov_backend, independent of data backend", {
  # Feature: gov-seam-liftout, Property 5: Gov-scoped backend resolution.
  # Battery over all data x gov backend combinations; gov sub-conn backend must
  # equal gov_backend regardless of the data backend.
  combos <- expand.grid(
    data_backend = c("s3", "local"),
    gov_backend  = c("s3", "local"),
    stringsAsFactors = FALSE
  )

  purrr::pwalk(combos, function(data_backend, gov_backend) {
    conn <- structure(
      list(
        project_name = "p",
        backend      = data_backend,
        root         = "data",
        prefix       = NULL,
        region       = "us-east-1",
        client       = NULL,
        path         = NULL,
        role         = "developer",
        endpoint     = NULL,
        gov_root     = "gov",
        gov_prefix   = NULL,
        gov_region   = "us-east-1",
        gov_backend  = gov_backend,
        gov_client   = NULL
      ),
      class = "datom_conn"
    )
    gov <- .datom_conn_for(conn, "gov")
    expect_equal(gov$backend, gov_backend,
                 info = paste("data:", data_backend, "gov:", gov_backend))
  })
})
