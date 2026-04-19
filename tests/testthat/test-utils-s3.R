# Tests for S3 utility functions
# Phase 2, Chunks 1-4: client, write/read JSON, upload, download, exists, redirect

# --- .datom_s3_client() --------------------------------------------------------

test_that("creates client with access_key and secret_key", {
  mock_s3 <- mockery::mock("mock-s3-client")
  mockery::stub(.datom_s3_client, "paws.storage::s3", mock_s3)

  result <- .datom_s3_client("fake-access-key", "fake-secret-key", region = "us-west-2")

  expect_equal(result, "mock-s3-client")
  mockery::expect_called(mock_s3, 1)

  call_args <- mockery::mock_args(mock_s3)[[1]]
  config <- call_args$config
  expect_equal(config$credentials$creds$access_key_id, "fake-access-key")
  expect_equal(config$credentials$creds$secret_access_key, "fake-secret-key")
  expect_equal(config$region, "us-west-2")
})

test_that("uses default region us-east-1", {
  mock_s3 <- mockery::mock("client")
  mockery::stub(.datom_s3_client, "paws.storage::s3", mock_s3)

  .datom_s3_client("key", "secret")

  call_args <- mockery::mock_args(mock_s3)[[1]]
  expect_equal(call_args$config$region, "us-east-1")
})

test_that("errors when access_key is invalid", {
  expect_error(.datom_s3_client("", "secret"), "access_key")
  expect_error(.datom_s3_client(NULL, "secret"), "access_key")
  expect_error(.datom_s3_client(NA_character_, "secret"), "access_key")
  expect_error(.datom_s3_client(123, "secret"), "access_key")
})

test_that("errors when secret_key is invalid", {
  expect_error(.datom_s3_client("key", ""), "secret_key")
  expect_error(.datom_s3_client("key", NULL), "secret_key")
  expect_error(.datom_s3_client("key", NA_character_), "secret_key")
  expect_error(.datom_s3_client("key", 123), "secret_key")
})

test_that("passes session_token to paws config", {
  mock_s3 <- mockery::mock("client")
  mockery::stub(.datom_s3_client, "paws.storage::s3", mock_s3)

  .datom_s3_client("key", "secret", session_token = "tok123")

  call_args <- mockery::mock_args(mock_s3)[[1]]
  expect_equal(call_args$config$credentials$creds$session_token, "tok123")
})

test_that("passes endpoint to paws config", {
  mock_s3 <- mockery::mock("client")
  mockery::stub(.datom_s3_client, "paws.storage::s3", mock_s3)

  .datom_s3_client("key", "secret", endpoint = "https://custom.endpoint.com")

  call_args <- mockery::mock_args(mock_s3)[[1]]
  expect_equal(call_args$config$endpoint, "https://custom.endpoint.com")
})


# --- .datom_s3_write_json() ----------------------------------------------------

test_that("serializes data and calls put_object with correct args", {
  mock_put <- mockery::mock(list(ETag = "\"abc123\""))
  mock_client <- list(put_object = mock_put)
  conn <- mock_datom_conn(mock_client, bucket = "my-bucket", prefix = "proj")

  data <- list(name = "customers", version = 1L)

  result <- .datom_s3_write_json(conn, ".metadata/test.json", data)

  expect_true(result)
  mockery::expect_called(mock_put, 1)

  call_args <- mockery::mock_args(mock_put)[[1]]
  expect_equal(call_args$Bucket, "my-bucket")
  expect_equal(call_args$Key, "proj/datom/.metadata/test.json")
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
  conn <- mock_datom_conn(mock_client)

  .datom_s3_write_json(conn, "k.json", list(scalar = "one"))

  body_json <- rawToChar(mockery::mock_args(mock_put)[[1]]$Body)
  # Should be "one" not ["one"]
  expect_false(grepl("\\[", body_json))
})

test_that("handles nested lists correctly", {
  mock_put <- mockery::mock(list())
  mock_client <- list(put_object = mock_put)
  conn <- mock_datom_conn(mock_client)

  data <- list(
    table = "customers",
    columns = list(
      list(name = "id", type = "integer"),
      list(name = "name", type = "character")
    )
  )

  .datom_s3_write_json(conn, "k.json", data)

  body_json <- rawToChar(mockery::mock_args(mock_put)[[1]]$Body)
  parsed <- jsonlite::fromJSON(body_json, simplifyDataFrame = FALSE)
  expect_equal(parsed$table, "customers")
  expect_length(parsed$columns, 2)
})

test_that("wraps S3 errors with context", {
  mock_put <- mockery::mock(stop("AccessDenied: 403"))
  mock_client <- list(put_object = mock_put)
  conn <- mock_datom_conn(mock_client, bucket = "my-bucket")

  expect_error(
    .datom_s3_write_json(conn, "some/key.json", list(a = 1)),
    "Failed to write JSON"
  )
})

test_that("error message includes bucket and key", {
  mock_put <- mockery::mock(stop("timeout"))
  mock_client <- list(put_object = mock_put)
  conn <- mock_datom_conn(mock_client, bucket = "test-bucket")

  tryCatch(
    .datom_s3_write_json(conn, "path/file.json", list()),
    error = function(e) {
      msg <- conditionMessage(e)
      expect_true(grepl("test-bucket", msg))
      expect_true(grepl("path/file.json", msg))
    }
  )
})


# --- .datom_s3_upload() --------------------------------------------------------

test_that("uploads file with correct put_object args", {
  withr::with_tempdir({
    path <- "test_data.parquet"
    writeBin(charToRaw("fake parquet content"), path)

    mock_put <- mockery::mock(list(ETag = "\"abc\""))
    mock_client <- list(put_object = mock_put)
    conn <- mock_datom_conn(mock_client, bucket = "my-bucket", prefix = "proj")

    result <- .datom_s3_upload(conn, path, "customers/abc.parquet")

    expect_true(result)
    mockery::expect_called(mock_put, 1)

    args <- mockery::mock_args(mock_put)[[1]]
    expect_equal(args$Bucket, "my-bucket")
    expect_equal(args$Key, "proj/datom/customers/abc.parquet")
    expect_equal(args$Body, charToRaw("fake parquet content"))
  })
})

test_that("errors when local file does not exist", {
  conn <- mock_datom_conn(list(put_object = mockery::mock()))

  expect_error(
    .datom_s3_upload(conn, "nonexistent.parquet", "k"),
    "File not found"
  )
})

test_that("wraps S3 upload errors with context", {
  withr::with_tempdir({
    path <- "data.parquet"
    writeBin(charToRaw("content"), path)

    mock_put <- mockery::mock(stop("AccessDenied"))
    mock_client <- list(put_object = mock_put)
    conn <- mock_datom_conn(mock_client, bucket = "my-bucket")

    expect_error(
      .datom_s3_upload(conn, path, "some/key"),
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
    conn <- mock_datom_conn(mock_client, bucket = "test-bucket", prefix = "proj")

    tryCatch(
      .datom_s3_upload(conn, path, "key.parquet"),
      error = function(e) {
        msg <- conditionMessage(e)
        expect_true(grepl("test-bucket", msg))
        expect_true(grepl("key.parquet", msg))
      }
    )
  })
})


# --- .datom_s3_download() ------------------------------------------------------

test_that("downloads file and writes to local path", {
  withr::with_tempdir({
    mock_get <- mockery::mock(list(Body = charToRaw("parquet bytes")))
    mock_client <- list(get_object = mock_get)
    conn <- mock_datom_conn(mock_client, bucket = "my-bucket", prefix = "proj")

    dest <- fs::path("output", "data.parquet")

    result <- .datom_s3_download(conn, "abc.parquet", dest)

    expect_true(result)
    expect_true(fs::file_exists(dest))
    expect_equal(readBin(dest, what = "raw", n = 100), charToRaw("parquet bytes"))

    args <- mockery::mock_args(mock_get)[[1]]
    expect_equal(args$Bucket, "my-bucket")
    expect_equal(args$Key, "proj/datom/abc.parquet")
  })
})

test_that("creates parent directories automatically", {
  withr::with_tempdir({
    mock_get <- mockery::mock(list(Body = charToRaw("data")))
    mock_client <- list(get_object = mock_get)
    conn <- mock_datom_conn(mock_client)

    dest <- fs::path("deep", "nested", "dir", "file.parquet")

    .datom_s3_download(conn, "k", dest)

    expect_true(fs::dir_exists(fs::path("deep", "nested", "dir")))
    expect_true(fs::file_exists(dest))
  })
})

test_that("wraps S3 download errors with context", {
  withr::with_tempdir({
    mock_get <- mockery::mock(stop("NoSuchKey"))
    mock_client <- list(get_object = mock_get)
    conn <- mock_datom_conn(mock_client, bucket = "my-bucket")

    expect_error(
      .datom_s3_download(conn, "missing/key", "out.parquet"),
      "Failed to download"
    )
  })
})

test_that("download error includes bucket and key", {
  withr::with_tempdir({
    mock_get <- mockery::mock(stop("AccessDenied"))
    mock_client <- list(get_object = mock_get)
    conn <- mock_datom_conn(mock_client, bucket = "test-bucket", prefix = "proj")

    tryCatch(
      .datom_s3_download(conn, "path.parquet", "out.parquet"),
      error = function(e) {
        msg <- conditionMessage(e)
        expect_true(grepl("test-bucket", msg))
        expect_true(grepl("path.parquet", msg))
      }
    )
  })
})


# --- .datom_s3_exists() --------------------------------------------------------

test_that("returns TRUE when object exists", {
  mock_head <- mockery::mock(list(ContentLength = 1024))
  mock_client <- list(head_object = mock_head)
  conn <- mock_datom_conn(mock_client, bucket = "my-bucket", prefix = "proj")

  result <- .datom_s3_exists(conn, "abc.parquet")

  expect_true(result)
  mockery::expect_called(mock_head, 1)

  args <- mockery::mock_args(mock_head)[[1]]
  expect_equal(args$Bucket, "my-bucket")
  expect_equal(args$Key, "proj/datom/abc.parquet")
})

test_that("returns FALSE on 404", {
  mock_head <- mockery::mock(stop("404 Not Found"))
  mock_client <- list(head_object = mock_head)
  conn <- mock_datom_conn(mock_client)

  expect_false(.datom_s3_exists(conn, "missing/key"))
})

test_that("returns FALSE on NoSuchKey", {
  mock_head <- mockery::mock(stop("NoSuchKey"))
  mock_client <- list(head_object = mock_head)
  conn <- mock_datom_conn(mock_client)

  expect_false(.datom_s3_exists(conn, "missing/key"))
})

test_that("re-throws 403 errors", {
  mock_head <- mockery::mock(stop("AccessDenied: 403 Forbidden"))
  mock_client <- list(head_object = mock_head)
  conn <- mock_datom_conn(mock_client)

  expect_error(
    .datom_s3_exists(conn, "forbidden/key"),
    "Failed to check"
  )
})

test_that("re-throws network errors", {
  mock_head <- mockery::mock(stop("Connection timed out"))
  mock_client <- list(head_object = mock_head)
  conn <- mock_datom_conn(mock_client)

  expect_error(
    .datom_s3_exists(conn, "k"),
    "Failed to check"
  )
})


# --- .datom_s3_read_json() -----------------------------------------------------

test_that("reads and parses valid JSON", {
  json <- jsonlite::toJSON(list(name = "customers", version = 1L), auto_unbox = TRUE)
  mock_get <- mockery::mock(list(Body = charToRaw(json)))
  mock_client <- list(get_object = mock_get)
  conn <- mock_datom_conn(mock_client, bucket = "my-bucket", prefix = "proj")

  result <- .datom_s3_read_json(conn, ".metadata/test.json")

  expect_type(result, "list")
  expect_equal(result$name, "customers")
  expect_equal(result$version, 1L)

  args <- mockery::mock_args(mock_get)[[1]]
  expect_equal(args$Bucket, "my-bucket")
  expect_equal(args$Key, "proj/datom/.metadata/test.json")
})

test_that("handles nested JSON structures", {
  data <- list(
    table = "customers",
    columns = list(
      list(name = "id", type = "integer"),
      list(name = "name", type = "character")
    )
  )
  json <- jsonlite::toJSON(data, auto_unbox = TRUE)
  mock_get <- mockery::mock(list(Body = charToRaw(json)))
  mock_client <- list(get_object = mock_get)
  conn <- mock_datom_conn(mock_client)

  result <- .datom_s3_read_json(conn, "k.json")

  expect_equal(result$table, "customers")
  expect_length(result$columns, 2)
  expect_equal(result$columns[[1]]$name, "id")
})

test_that("handles arrays correctly with simplifyVector = FALSE", {
  json <- '{"tags": ["a", "b", "c"]}'
  mock_get <- mockery::mock(list(Body = charToRaw(json)))
  mock_client <- list(get_object = mock_get)
  conn <- mock_datom_conn(mock_client)

  result <- .datom_s3_read_json(conn, "k.json")

  # simplifyVector = FALSE keeps arrays as lists
  expect_type(result$tags, "list")
  expect_equal(result$tags[[1]], "a")
  expect_length(result$tags, 3)
})

test_that("round-trips with .datom_s3_write_json", {
  original <- list(
    name = "ADSL",
    sha = "abc123",
    metadata = list(rows = 100L, cols = 5L)
  )

  # Capture what write_json would send
  mock_put <- mockery::mock(list())
  write_client <- list(put_object = mock_put)
  write_conn <- mock_datom_conn(write_client)
  .datom_s3_write_json(write_conn, "k.json", original)
  written_raw <- mockery::mock_args(mock_put)[[1]]$Body

  # Feed that to read_json
  mock_get <- mockery::mock(list(Body = written_raw))
  read_client <- list(get_object = mock_get)
  read_conn <- mock_datom_conn(read_client)
  result <- .datom_s3_read_json(read_conn, "k.json")

  expect_equal(result$name, original$name)
  expect_equal(result$sha, original$sha)
  expect_equal(result$metadata$rows, original$metadata$rows)
})

test_that("wraps S3 errors with context", {
  mock_get <- mockery::mock(stop("NoSuchKey: key not found"))
  mock_client <- list(get_object = mock_get)
  conn <- mock_datom_conn(mock_client, bucket = "my-bucket")

  expect_error(
    .datom_s3_read_json(conn, "missing/key.json"),
    "Failed to read JSON"
  )
})

test_that("wraps JSON parse errors with context", {
  mock_get <- mockery::mock(list(Body = charToRaw("not valid json {{{")))
  mock_client <- list(get_object = mock_get)
  conn <- mock_datom_conn(mock_client, bucket = "my-bucket")

  expect_error(
    .datom_s3_read_json(conn, "bad.json"),
    "Failed to parse JSON"
  )
})

test_that("error message includes bucket and key on S3 failure", {
  mock_get <- mockery::mock(stop("AccessDenied"))
  mock_client <- list(get_object = mock_get)
  conn <- mock_datom_conn(mock_client, bucket = "test-bucket")

  tryCatch(
    .datom_s3_read_json(conn, "secret/file.json"),
    error = function(e) {
      msg <- conditionMessage(e)
      expect_true(grepl("test-bucket", msg))
      expect_true(grepl("secret/file.json", msg))
    }
  )
})

test_that("error message includes bucket and key on parse failure", {
  mock_get <- mockery::mock(list(Body = charToRaw("garbage")))
  mock_client <- list(get_object = mock_get)
  conn <- mock_datom_conn(mock_client, bucket = "test-bucket")

  tryCatch(
    .datom_s3_read_json(conn, "corrupt.json"),
    error = function(e) {
      msg <- conditionMessage(e)
      expect_true(grepl("test-bucket", msg))
      expect_true(grepl("corrupt.json", msg))
    }
  )
})
