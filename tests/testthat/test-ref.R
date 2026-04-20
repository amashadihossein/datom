# --- .datom_create_ref() -------------------------------------------------------

test_that("creates ref with current data location", {
  data_store <- list(
    bucket = "study-bucket",
    prefix = "trial/",
    region = "us-east-1"
  )

  ref <- .datom_create_ref(data_store)

  expect_equal(ref$current$root, "study-bucket")
  expect_equal(ref$current$prefix, "trial/")
  expect_equal(ref$current$region, "us-east-1")
  expect_equal(ref$previous, list())
})

test_that("creates ref with NULL prefix", {
  data_store <- list(
    bucket = "my-bucket",
    prefix = NULL,
    region = "eu-west-1"
  )

  ref <- .datom_create_ref(data_store)

  expect_equal(ref$current$root, "my-bucket")
  expect_null(ref$current$prefix)
  expect_equal(ref$current$region, "eu-west-1")
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
