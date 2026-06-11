# Tests for datom_storage_list() and datom_storage_delete_prefix()
# Chunk 1 of Phase 22: Storage Extension API

# --- Local conn helper --------------------------------------------------------

make_local_storage_conn <- function(root, prefix = "proj") {
  structure(
    list(
      project_name = "test-project",
      backend      = "local",
      root         = as.character(root),
      prefix       = prefix,
      client       = NULL,
      path         = NULL,
      role         = "developer",
      region       = NULL,
      gov_root     = NULL
    ),
    class = "datom_conn"
  )
}


# === datom_storage_list() =====================================================

test_that("datom_storage_list() errors on non-conn", {
  expect_error(datom_storage_list("not-a-conn"), "datom_conn")
  expect_error(datom_storage_list(list()), "datom_conn")
  expect_error(datom_storage_list(NULL), "datom_conn")
})

test_that("datom_storage_list() returns keys from S3 backend", {
  expected_keys <- c(
    "proj/datom/demo/abc123.parquet",
    "proj/datom/.metadata/manifest.json"
  )
  mock_list <- mockery::mock(
    list(
      Contents  = purrr::map(expected_keys, ~ list(Key = .x)),
      IsTruncated = FALSE
    )
  )
  conn <- mock_datom_conn(
    list(list_objects_v2 = mock_list),
    root   = "my-bucket",
    prefix = "proj"
  )

  result <- datom_storage_list(conn)

  expect_equal(result, expected_keys)
  mockery::expect_called(mock_list, 1)
  # Verify the full datom namespace prefix was passed (not a sub-path)
  call_args <- mockery::mock_args(mock_list)[[1]]
  expect_equal(call_args$Prefix, "proj/datom/")
})

test_that("datom_storage_list() returns empty vector when namespace is empty", {
  mock_list <- mockery::mock(
    list(Contents = list(), IsTruncated = FALSE)
  )
  conn <- mock_datom_conn(list(list_objects_v2 = mock_list))

  result <- datom_storage_list(conn)

  expect_equal(result, character(0))
})

test_that("datom_storage_list() works with NULL prefix on S3", {
  mock_list <- mockery::mock(
    list(Contents = list(), IsTruncated = FALSE)
  )
  conn <- mock_datom_conn(list(list_objects_v2 = mock_list), prefix = NULL)

  datom_storage_list(conn)

  call_args <- mockery::mock_args(mock_list)[[1]]
  # No prefix component -- should start with datom/
  expect_equal(call_args$Prefix, "datom/")
})

test_that("datom_storage_list() returns keys from local backend", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")

    # Seed a few objects in the datom namespace
    fs::dir_create("proj/datom/demographics")
    fs::dir_create("proj/datom/.metadata")
    writeLines("data", "proj/datom/demographics/abc.parquet")
    writeLines("meta", "proj/datom/.metadata/manifest.json")

    result <- datom_storage_list(conn)

    expect_true(is.character(result))
    expect_length(result, 2L)
    expect_true(any(grepl("demographics/abc.parquet", result, fixed = TRUE)))
    expect_true(any(grepl(".metadata/manifest.json", result, fixed = TRUE)))
  })
})

test_that("datom_storage_list() returns empty vector for empty local namespace", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")
    # datom dir does not exist yet
    result <- datom_storage_list(conn)
    expect_equal(result, character(0))
  })
})


# === datom_storage_delete_prefix() ===========================================

test_that("datom_storage_delete_prefix() errors on non-conn", {
  expect_error(datom_storage_delete_prefix("not-a-conn"), "datom_conn")
  expect_error(datom_storage_delete_prefix(NULL), "datom_conn")
})

test_that("datom_storage_delete_prefix() passes NULL prefix_key to internal", {
  # Stub the internal so we can inspect the args without needing a real S3 client
  mock_internal <- mockery::mock(invisible(0L))
  mockery::stub(datom_storage_delete_prefix, ".datom_storage_delete_prefix", mock_internal)

  conn <- mock_datom_conn(list(), root = "my-bucket")
  datom_storage_delete_prefix(conn)

  mockery::expect_called(mock_internal, 1)
  call_args <- mockery::mock_args(mock_internal)[[1]]
  expect_null(call_args[[2]])  # prefix_key = NULL
})

test_that("datom_storage_delete_prefix() passes specific prefix_key to internal", {
  mock_internal <- mockery::mock(invisible(3L))
  mockery::stub(datom_storage_delete_prefix, ".datom_storage_delete_prefix", mock_internal)

  conn <- mock_datom_conn(list(), root = "my-bucket")
  datom_storage_delete_prefix(conn, prefix_key = "demographics")

  call_args <- mockery::mock_args(mock_internal)[[1]]
  expect_equal(call_args[[2]], "demographics")
})

test_that("datom_storage_delete_prefix() returns internal result invisibly", {
  mock_internal <- mockery::mock(invisible(5L))
  mockery::stub(datom_storage_delete_prefix, ".datom_storage_delete_prefix", mock_internal)

  conn <- mock_datom_conn(list())
  result <- withVisible(datom_storage_delete_prefix(conn, "table1"))

  expect_equal(result$value, 5L)
  expect_false(result$visible)
})

test_that("datom_storage_delete_prefix() deletes files on local backend", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")

    # Seed files across two tables
    fs::dir_create("proj/datom/table1")
    fs::dir_create("proj/datom/table2")
    writeLines("a", "proj/datom/table1/v1.parquet")
    writeLines("b", "proj/datom/table1/v2.parquet")
    writeLines("c", "proj/datom/table2/v1.parquet")

    # Delete only table1
    n <- datom_storage_delete_prefix(conn, prefix_key = "table1")

    expect_equal(n, 1L)  # local backend: 1L = directory removed
    expect_false(fs::dir_exists("proj/datom/table1"))
    expect_true(fs::dir_exists("proj/datom/table2"))
  })
})

test_that("datom_storage_delete_prefix(prefix_key = NULL) removes entire namespace on local", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")

    fs::dir_create("proj/datom/table1")
    fs::dir_create("proj/datom/.metadata")
    writeLines("a", "proj/datom/table1/v1.parquet")
    writeLines("m", "proj/datom/.metadata/manifest.json")

    n <- datom_storage_delete_prefix(conn)

    expect_equal(n, 1L)  # local backend: 1L = directory removed
    expect_false(fs::dir_exists("proj/datom"))
  })
})

test_that("datom_storage_delete_prefix() returns 0L when prefix does not exist", {
  withr::with_tempdir({
    conn <- make_local_storage_conn(getwd(), prefix = "proj")
    n <- datom_storage_delete_prefix(conn, prefix_key = "nonexistent")
    expect_equal(n, 0L)
  })
})
