# Tests for S3 utility functions
# Phase 2, Chunks 1-2: S3 client, write JSON, upload, download, exists

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


# --- .tbit_s3_upload() --------------------------------------------------------

test_that("uploads file with correct put_object args", {
  withr::with_tempdir({
    path <- "test_data.parquet"
    writeBin(charToRaw("fake parquet content"), path)

    mock_put <- mockery::mock(list(ETag = "\"abc\""))
    mock_client <- list(put_object = mock_put)

    result <- .tbit_s3_upload(mock_client, "my-bucket", path, "tbit/customers/abc.parquet")

    expect_true(result)
    mockery::expect_called(mock_put, 1)

    args <- mockery::mock_args(mock_put)[[1]]
    expect_equal(args$Bucket, "my-bucket")
    expect_equal(args$Key, "tbit/customers/abc.parquet")
    expect_equal(args$Body, charToRaw("fake parquet content"))
  })
})

test_that("errors when local file does not exist", {
  mock_client <- list(put_object = mockery::mock())

  expect_error(
    .tbit_s3_upload(mock_client, "b", "nonexistent.parquet", "k"),
    "File not found"
  )
})

test_that("wraps S3 upload errors with context", {
  withr::with_tempdir({
    path <- "data.parquet"
    writeBin(charToRaw("content"), path)

    mock_put <- mockery::mock(stop("AccessDenied"))
    mock_client <- list(put_object = mock_put)

    expect_error(
      .tbit_s3_upload(mock_client, "my-bucket", path, "some/key"),
      "Failed to upload"
    )
  })
})

test_that("upload error includes bucket, key, and local path", {
  withr::with_tempdir({
    path <- "data.parquet"
    writeBin(charToRaw("content"), path)

    mock_put <- mockery::mock(stop("timeout"))
    mock_client <- list(put_object = mock_put)

    tryCatch(
      .tbit_s3_upload(mock_client, "test-bucket", path, "tbit/key.parquet"),
      error = function(e) {
        msg <- conditionMessage(e)
        expect_true(grepl("test-bucket", msg))
        expect_true(grepl("tbit/key.parquet", msg))
      }
    )
  })
})


# --- .tbit_s3_download() ------------------------------------------------------

test_that("downloads file and writes to local path", {
  withr::with_tempdir({
    mock_get <- mockery::mock(list(Body = charToRaw("parquet bytes")))
    mock_client <- list(get_object = mock_get)

    dest <- fs::path("output", "data.parquet")

    result <- .tbit_s3_download(mock_client, "my-bucket", "tbit/abc.parquet", dest)

    expect_true(result)
    expect_true(fs::file_exists(dest))
    expect_equal(readBin(dest, what = "raw", n = 100), charToRaw("parquet bytes"))

    args <- mockery::mock_args(mock_get)[[1]]
    expect_equal(args$Bucket, "my-bucket")
    expect_equal(args$Key, "tbit/abc.parquet")
  })
})

test_that("creates parent directories automatically", {
  withr::with_tempdir({
    mock_get <- mockery::mock(list(Body = charToRaw("data")))
    mock_client <- list(get_object = mock_get)

    dest <- fs::path("deep", "nested", "dir", "file.parquet")

    .tbit_s3_download(mock_client, "b", "k", dest)

    expect_true(fs::dir_exists(fs::path("deep", "nested", "dir")))
    expect_true(fs::file_exists(dest))
  })
})

test_that("wraps S3 download errors with context", {
  withr::with_tempdir({
    mock_get <- mockery::mock(stop("NoSuchKey"))
    mock_client <- list(get_object = mock_get)

    expect_error(
      .tbit_s3_download(mock_client, "my-bucket", "missing/key", "out.parquet"),
      "Failed to download"
    )
  })
})

test_that("download error includes bucket and key", {
  withr::with_tempdir({
    mock_get <- mockery::mock(stop("AccessDenied"))
    mock_client <- list(get_object = mock_get)

    tryCatch(
      .tbit_s3_download(mock_client, "test-bucket", "tbit/path.parquet", "out.parquet"),
      error = function(e) {
        msg <- conditionMessage(e)
        expect_true(grepl("test-bucket", msg))
        expect_true(grepl("tbit/path.parquet", msg))
      }
    )
  })
})


# --- .tbit_s3_exists() --------------------------------------------------------

test_that("returns TRUE when object exists", {
  mock_head <- mockery::mock(list(ContentLength = 1024))
  mock_client <- list(head_object = mock_head)

  result <- .tbit_s3_exists(mock_client, "my-bucket", "tbit/abc.parquet")

  expect_true(result)
  mockery::expect_called(mock_head, 1)

  args <- mockery::mock_args(mock_head)[[1]]
  expect_equal(args$Bucket, "my-bucket")
  expect_equal(args$Key, "tbit/abc.parquet")
})

test_that("returns FALSE on 404", {
  mock_head <- mockery::mock(stop("404 Not Found"))
  mock_client <- list(head_object = mock_head)

  expect_false(.tbit_s3_exists(mock_client, "b", "missing/key"))
})

test_that("returns FALSE on NoSuchKey", {
  mock_head <- mockery::mock(stop("NoSuchKey"))
  mock_client <- list(head_object = mock_head)

  expect_false(.tbit_s3_exists(mock_client, "b", "missing/key"))
})

test_that("re-throws 403 errors", {
  mock_head <- mockery::mock(stop("AccessDenied: 403 Forbidden"))
  mock_client <- list(head_object = mock_head)

  expect_error(
    .tbit_s3_exists(mock_client, "b", "forbidden/key"),
    "Failed to check"
  )
})

test_that("re-throws network errors", {
  mock_head <- mockery::mock(stop("Connection timed out"))
  mock_client <- list(head_object = mock_head)

  expect_error(
    .tbit_s3_exists(mock_client, "b", "k"),
    "Failed to check"
  )
})
