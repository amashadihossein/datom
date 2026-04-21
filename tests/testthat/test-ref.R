# --- .datom_create_ref() -------------------------------------------------------

test_that("creates ref with current data location", {
  data_store <- datom_store_s3(
    bucket = "study-bucket", prefix = "trial/", region = "us-east-1",
    access_key = "AK", secret_key = "SK", validate = FALSE
  )

  ref <- .datom_create_ref(data_store)

  expect_equal(ref$current$root, "study-bucket")
  expect_equal(ref$current$prefix, "trial/")
  expect_equal(ref$current$region, "us-east-1")
  expect_equal(ref$previous, list())
})

test_that("creates ref with NULL prefix", {
  data_store <- datom_store_s3(
    bucket = "my-bucket", prefix = NULL, region = "eu-west-1",
    access_key = "AK", secret_key = "SK", validate = FALSE
  )

  ref <- .datom_create_ref(data_store)

  expect_equal(ref$current$root, "my-bucket")
  expect_null(ref$current$prefix)
  expect_equal(ref$current$region, "eu-west-1")
})

test_that("creates ref with local store component", {
  data_store <- datom_store_local(
    path = "/data/store", prefix = "proj/", validate = FALSE
  )

  ref <- .datom_create_ref(data_store)

  expect_match(ref$current$root, "data/store")
  expect_equal(ref$current$prefix, "proj/")
  expect_null(ref$current$region)
})


# --- .datom_resolve_ref() -----------------------------------------------------

test_that("resolves current data location from ref.json", {
  ref_data <- list(
    current = list(
      root = "data-bucket",
      prefix = "proj/",
      region = "us-west-2"
    ),
    previous = list()
  )

  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) ref_data
  )

  result <- .datom_resolve_ref(gov_conn)

  expect_equal(result$root, "data-bucket")
  expect_equal(result$prefix, "proj/")
  expect_equal(result$region, "us-west-2")
})

test_that("resolves with NULL prefix in ref", {
  ref_data <- list(
    current = list(
      root = "data-bucket",
      region = "us-east-1"
    ),
    previous = list()
  )

  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) ref_data
  )

  result <- .datom_resolve_ref(gov_conn)

  expect_equal(result$root, "data-bucket")
  expect_null(result$prefix)
  expect_equal(result$region, "us-east-1")
})

test_that("resolves with missing region defaults to us-east-1", {
  ref_data <- list(
    current = list(root = "data-bucket", prefix = "p/"),
    previous = list()
  )

  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) ref_data
  )

  result <- .datom_resolve_ref(gov_conn)

  expect_equal(result$region, "us-east-1")
})

test_that("emits warning when previous migration entries exist", {
  ref_data <- list(
    current = list(root = "new-bucket", prefix = "p/", region = "us-east-1"),
    previous = list(
      list(
        root = "old-bucket",
        prefix = "old/",
        region = "us-east-1",
        migrated_at = "2026-01-15T00:00:00Z",
        sunset_at = "2026-04-15T00:00:00Z"
      )
    )
  )

  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) ref_data
  )

  expect_warning(
    result <- .datom_resolve_ref(gov_conn),
    "migrated"
  )

  expect_equal(result$root, "new-bucket")
})

test_that("warning includes sunset date", {
  ref_data <- list(
    current = list(root = "new-bucket", prefix = "p/", region = "us-east-1"),
    previous = list(
      list(root = "old-bucket", sunset_at = "2026-06-01")
    )
  )

  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) ref_data
  )

  expect_warning(
    .datom_resolve_ref(gov_conn),
    "2026-06-01"
  )
})

test_that("no warning when previous is empty list", {
  ref_data <- list(
    current = list(root = "bucket", prefix = "p/", region = "us-east-1"),
    previous = list()
  )

  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) ref_data
  )

  expect_no_warning(
    .datom_resolve_ref(gov_conn)
  )
})

test_that("errors when ref.json is unreadable", {
  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      cli::cli_abort("Network error")
    }
  )

  expect_error(
    .datom_resolve_ref(gov_conn),
    "ref\\.json"
  )
})

test_that("errors when current.root is missing", {
  ref_data <- list(
    current = list(prefix = "p/"),
    previous = list()
  )

  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) ref_data
  )

  expect_error(
    .datom_resolve_ref(gov_conn),
    "current\\.root"
  )
})

test_that("errors when current is NULL", {
  ref_data <- list(previous = list())

  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) ref_data
  )

  expect_error(
    .datom_resolve_ref(gov_conn),
    "current\\.root"
  )
})

test_that("reads from correct key", {
  gov_conn <- mock_datom_conn("gov-client", root = "gov-bucket", prefix = "gov")

  captured_key <- NULL
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      captured_key <<- key
      list(
        current = list(root = "b", prefix = "p/", region = "us-east-1"),
        previous = list()
      )
    }
  )

  .datom_resolve_ref(gov_conn)

  expect_equal(captured_key, ".metadata/ref.json")
})


# =============================================================================
# Phase 13: .datom_resolve_data_location()
# =============================================================================

# Helper: make a composite store with mock S3 clients
make_test_store <- function(gov_bucket = "gov-bucket", gov_prefix = "gov/",
                             data_bucket = "data-bucket", data_prefix = "data/",
                             role = "reader") {
  gov_comp <- datom_store_s3(
    bucket = gov_bucket, prefix = gov_prefix, region = "us-east-1",
    access_key = "AK", secret_key = "SK", validate = FALSE
  )
  data_comp <- datom_store_s3(
    bucket = data_bucket, prefix = data_prefix, region = "us-east-1",
    access_key = "AK", secret_key = "SK", validate = FALSE
  )
  pat <- if (role == "developer") "ghp_fake" else NULL
  datom_store(governance = gov_comp, data = data_comp,
              github_pat = pat, validate = FALSE)
}

test_that("returns NULL when no governance store present", {
  data_comp <- datom_store_s3(
    bucket = "b", access_key = "AK", secret_key = "SK", validate = FALSE
  )
  store <- structure(
    list(governance = NULL, data = data_comp, role = "reader"),
    class = "datom_store"
  )

  result <- .datom_resolve_data_location(store, role = "reader")
  expect_null(result)
})

test_that("returns ref location when no migration (S3)", {
  store <- make_test_store(
    gov_bucket = "gov-bucket",
    data_bucket = "data-bucket", data_prefix = "data/"
  )

  ref_data <- list(
    current = list(root = "data-bucket", prefix = "data/", region = "us-east-1"),
    previous = list()
  )

  local_mocked_bindings(
    .datom_s3_client = function(...) list(),
    .datom_resolve_ref = function(gov_conn) list(root = "data-bucket", prefix = "data/", region = "us-east-1")
  )

  result <- .datom_resolve_data_location(store, role = "reader")
  expect_equal(result$root, "data-bucket")
  expect_equal(result$prefix, "data/")
})

test_that("reader: warns on migration mismatch", {
  store <- make_test_store(
    data_bucket = "old-bucket", data_prefix = "old/"
  )

  local_mocked_bindings(
    .datom_s3_client = function(...) list(),
    .datom_resolve_ref = function(gov_conn) list(root = "new-bucket", prefix = "new/", region = "us-east-1")
  )

  expect_warning(
    result <- .datom_resolve_data_location(store, role = "reader"),
    "migrated"
  )
  expect_equal(result$root, "new-bucket")
})

test_that("warns with store root in migration warning", {
  store <- make_test_store(
    data_bucket = "old-bucket", data_prefix = "old/"
  )

  local_mocked_bindings(
    .datom_s3_client = function(...) list(),
    .datom_resolve_ref = function(gov_conn) list(root = "new-bucket", prefix = "new/", region = "us-east-1")
  )

  expect_warning(
    .datom_resolve_data_location(store, role = "reader"),
    "old-bucket"
  )
})

test_that("developer: auto-pulls and succeeds when project.yaml agrees after pull", {
  dir <- withr::local_tempdir()
  datom_dir <- fs::path(dir, ".datom")
  fs::dir_create(datom_dir)
  yaml::write_yaml(
    list(
      project_name = "p",
      storage = list(
        data = list(type = "s3", root = "new-bucket", prefix = "new/", region = "us-east-1")
      )
    ),
    fs::path(datom_dir, "project.yaml")
  )

  store <- make_test_store(
    data_bucket = "old-bucket", data_prefix = "old/",
    role = "developer"
  )

  local_mocked_bindings(
    .datom_s3_client = function(...) list(),
    .datom_resolve_ref = function(gov_conn) list(root = "new-bucket", prefix = "new/", region = "us-east-1"),
    .datom_git_pull = function(path) invisible(NULL)
  )

  # Should succeed without error or warning (project.yaml already matches ref)
  result <- expect_no_warning(
    .datom_resolve_data_location(store, role = "developer", path = as.character(dir))
  )
  expect_equal(result$root, "new-bucket")
})

test_that("developer: errors when project.yaml still disagrees after pull", {
  dir <- withr::local_tempdir()
  datom_dir <- fs::path(dir, ".datom")
  fs::dir_create(datom_dir)
  # project.yaml points to stale bucket (won't change after pull mock)
  yaml::write_yaml(
    list(
      project_name = "p",
      storage = list(
        data = list(type = "s3", root = "stale-bucket", prefix = "data/", region = "us-east-1")
      )
    ),
    fs::path(datom_dir, "project.yaml")
  )

  store <- make_test_store(
    data_bucket = "old-bucket", data_prefix = "data/",
    role = "developer"
  )

  local_mocked_bindings(
    .datom_s3_client = function(...) list(),
    .datom_resolve_ref = function(gov_conn) list(root = "new-bucket", prefix = "data/", region = "us-east-1"),
    .datom_git_pull = function(path) invisible(NULL)
  )

  expect_error(
    .datom_resolve_data_location(store, role = "developer", path = as.character(dir)),
    "disagree after git pull"
  )
})

test_that("warns (not errors) when ref.json is unreadable at conn time", {
  store <- make_test_store(data_bucket = "data-bucket", data_prefix = "data/")

  local_mocked_bindings(
    .datom_s3_client = function(...) list(),
    .datom_resolve_ref = function(gov_conn) cli::cli_abort("Network timeout")
  )

  expect_warning(
    result <- .datom_resolve_data_location(store, role = "reader"),
    "Could not resolve ref[.]json"
  )
  expect_null(result)
})


# =============================================================================
# Phase 13: .datom_check_ref_current() (write-time guard)
# =============================================================================

test_that("skips check when no gov_root (legacy conn)", {
  conn <- new_datom_conn(
    project_name = "p", root = "b", region = "us-east-1",
    client = NULL, role = "reader", backend = "local"
  )
  expect_no_error(.datom_check_ref_current(conn))
})

test_that("passes when ref matches conn location", {
  conn <- new_datom_conn(
    project_name = "p", root = "data-bucket", prefix = "data/",
    region = "us-east-1", client = NULL, role = "reader",
    gov_root = "gov-bucket", gov_prefix = "gov/", gov_region = "us-east-1",
    gov_client = NULL, backend = "local"
  )

  local_mocked_bindings(
    .datom_resolve_ref = function(gov_conn) list(root = "data-bucket", prefix = "data/", region = "us-east-1")
  )

  expect_no_error(.datom_check_ref_current(conn))
})

test_that("errors when ref root differs from conn root", {
  conn <- new_datom_conn(
    project_name = "p", root = "old-bucket", prefix = "data/",
    region = "us-east-1", client = NULL, role = "reader",
    gov_root = "gov-bucket", gov_prefix = "gov/", gov_region = "us-east-1",
    gov_client = NULL, backend = "local"
  )

  local_mocked_bindings(
    .datom_resolve_ref = function(gov_conn) list(root = "new-bucket", prefix = "data/", region = "us-east-1")
  )

  expect_error(
    .datom_check_ref_current(conn),
    "Data location changed"
  )
})

test_that("errors when ref prefix differs from conn prefix", {
  conn <- new_datom_conn(
    project_name = "p", root = "data-bucket", prefix = "old/",
    region = "us-east-1", client = NULL, role = "reader",
    gov_root = "gov-bucket", gov_prefix = "gov/", gov_region = "us-east-1",
    gov_client = NULL, backend = "local"
  )

  local_mocked_bindings(
    .datom_resolve_ref = function(gov_conn) list(root = "data-bucket", prefix = "new/", region = "us-east-1")
  )

  expect_error(
    .datom_check_ref_current(conn),
    "Data location changed"
  )
})

test_that("errors on any ref failure at write time", {
  conn <- new_datom_conn(
    project_name = "p", root = "data-bucket", prefix = "data/",
    region = "us-east-1", client = NULL, role = "reader",
    gov_root = "gov-bucket", gov_prefix = "gov/", gov_region = "us-east-1",
    gov_client = NULL, backend = "local"
  )

  local_mocked_bindings(
    .datom_resolve_ref = function(gov_conn) cli::cli_abort("Network error")
  )

  expect_error(
    .datom_check_ref_current(conn),
    "Cannot write"
  )
})

test_that("error message on write-time ref failure mentions orphaned data", {
  conn <- new_datom_conn(
    project_name = "p", root = "data-bucket", prefix = "data/",
    region = "us-east-1", client = NULL, role = "reader",
    gov_root = "gov-bucket", gov_prefix = "gov/", gov_region = "us-east-1",
    gov_client = NULL, backend = "local"
  )

  local_mocked_bindings(
    .datom_resolve_ref = function(gov_conn) cli::cli_abort("timeout")
  )

  expect_error(
    .datom_check_ref_current(conn),
    "orphaning"
  )
})
