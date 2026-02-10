# Tests for S3 utility functions
# Phase 2, Chunk 1: S3 client + write JSON

# --- .tbit_s3_client() --------------------------------------------------------

test_that("creates client when env vars are set", {
  withr::local_envvar(
    TBIT_TEST_ACCESS_KEY_ID = "fake-access-key",
    TBIT_TEST_SECRET_ACCESS_KEY = "fake-secret-key"
  )

  # Mock paws.storage::s3 to avoid real AWS calls
  mock_s3 <- mockery::mock("mock-s3-client")
  mockery::stub(.tbit_s3_client, "paws.storage::s3", mock_s3)

  creds <- list(
    access_key_env = "TBIT_TEST_ACCESS_KEY_ID",
    secret_key_env = "TBIT_TEST_SECRET_ACCESS_KEY"
  )

  result <- .tbit_s3_client(creds, region = "us-west-2")

  expect_equal(result, "mock-s3-client")
  mockery::expect_called(mock_s3, 1)

  # Verify correct config passed to paws
  call_args <- mockery::mock_args(mock_s3)[[1]]
  config <- call_args$config
  expect_equal(config$credentials$creds$access_key_id, "fake-access-key")
  expect_equal(config$credentials$creds$secret_access_key, "fake-secret-key")
  expect_equal(config$region, "us-west-2")
})

test_that("uses default region us-east-1", {
  withr::local_envvar(
    TBIT_TEST_ACCESS_KEY_ID = "key",
    TBIT_TEST_SECRET_ACCESS_KEY = "secret"
  )

  mock_s3 <- mockery::mock("client")
  mockery::stub(.tbit_s3_client, "paws.storage::s3", mock_s3)

  creds <- list(
    access_key_env = "TBIT_TEST_ACCESS_KEY_ID",
    secret_key_env = "TBIT_TEST_SECRET_ACCESS_KEY"
  )

  .tbit_s3_client(creds)

  call_args <- mockery::mock_args(mock_s3)[[1]]
  expect_equal(call_args$config$region, "us-east-1")
})

test_that("errors when credentials list is malformed", {
  expect_error(.tbit_s3_client(list()), "access_key_env")
  expect_error(.tbit_s3_client(list(access_key_env = "X")), "secret_key_env")
  expect_error(.tbit_s3_client("not a list"), "access_key_env")
  expect_error(.tbit_s3_client(NULL), "access_key_env")
})

test_that("errors when access key env var is not set", {
  withr::local_envvar(
    TBIT_MISSING_KEY = NA  # ensure unset
  )

  creds <- list(
    access_key_env = "TBIT_MISSING_KEY",
    secret_key_env = "TBIT_TEST_SECRET"
  )

  expect_error(.tbit_s3_client(creds), "TBIT_MISSING_KEY")
})

test_that("errors when secret key env var is not set", {
  withr::local_envvar(
    TBIT_TEST_ACCESS = "key",
    TBIT_MISSING_SECRET = NA
  )

  creds <- list(
    access_key_env = "TBIT_TEST_ACCESS",
    secret_key_env = "TBIT_MISSING_SECRET"
  )

  expect_error(.tbit_s3_client(creds), "TBIT_MISSING_SECRET")
})

test_that("errors when access key env var is empty string", {
  withr::local_envvar(
    TBIT_EMPTY_KEY = "",
    TBIT_TEST_SECRET = "secret"
  )

  creds <- list(
    access_key_env = "TBIT_EMPTY_KEY",
    secret_key_env = "TBIT_TEST_SECRET"
  )

  expect_error(.tbit_s3_client(creds), "TBIT_EMPTY_KEY")
})

test_that("errors when secret key env var is empty string", {
  withr::local_envvar(
    TBIT_TEST_ACCESS = "key",
    TBIT_EMPTY_SECRET = ""
  )

  creds <- list(
    access_key_env = "TBIT_TEST_ACCESS",
    secret_key_env = "TBIT_EMPTY_SECRET"
  )

  expect_error(.tbit_s3_client(creds), "TBIT_EMPTY_SECRET")
})


# --- .tbit_s3_write_json() ----------------------------------------------------

test_that("serializes data and calls put_object with correct args", {
  mock_put <- mockery::mock(list(ETag = "\"abc123\""))
  mock_client <- list(put_object = mock_put)

  data <- list(name = "customers", version = 1L)

  result <- .tbit_s3_write_json(mock_client, "my-bucket", "tbit/.metadata/test.json", data)

  expect_true(result)
  mockery::expect_called(mock_put, 1)

  call_args <- mockery::mock_args(mock_put)[[1]]
  expect_equal(call_args$Bucket, "my-bucket")
  expect_equal(call_args$Key, "tbit/.metadata/test.json")
  expect_equal(call_args$ContentType, "application/json")

  # Verify body is valid JSON that round-trips
  body_json <- rawToChar(call_args$Body)
  parsed <- jsonlite::fromJSON(body_json)
  expect_equal(parsed$name, "customers")
  expect_equal(parsed$version, 1L)
})

test_that("auto-unboxes scalar values in JSON", {
  mock_put <- mockery::mock(list())
  mock_client <- list(put_object = mock_put)

  .tbit_s3_write_json(mock_client, "b", "k", list(scalar = "one"))

  body_json <- rawToChar(mockery::mock_args(mock_put)[[1]]$Body)
  # Should be "one" not ["one"]
  expect_false(grepl("\\[", body_json))
})

test_that("handles nested lists correctly", {
  mock_put <- mockery::mock(list())
  mock_client <- list(put_object = mock_put)

  data <- list(
    table = "customers",
    columns = list(
      list(name = "id", type = "integer"),
      list(name = "name", type = "character")
    )
  )

  .tbit_s3_write_json(mock_client, "b", "k", data)

  body_json <- rawToChar(mockery::mock_args(mock_put)[[1]]$Body)
  parsed <- jsonlite::fromJSON(body_json, simplifyDataFrame = FALSE)
  expect_equal(parsed$table, "customers")
  expect_length(parsed$columns, 2)
})

test_that("wraps S3 errors with context", {
  mock_put <- mockery::mock(stop("AccessDenied: 403"))
  mock_client <- list(put_object = mock_put)

  expect_error(
    .tbit_s3_write_json(mock_client, "my-bucket", "some/key.json", list(a = 1)),
    "Failed to write JSON"
  )
})

test_that("error message includes bucket and key", {
  mock_put <- mockery::mock(stop("timeout"))
  mock_client <- list(put_object = mock_put)

  tryCatch(
    .tbit_s3_write_json(mock_client, "test-bucket", "path/file.json", list()),
    error = function(e) {
      msg <- conditionMessage(e)
      expect_true(grepl("test-bucket", msg))
      expect_true(grepl("path/file.json", msg))
    }
  )
})
