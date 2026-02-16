# Tests for read/write infrastructure
# Phase 5: tbit_read(), tbit_write(), and supporting internals


# --- tbit_read() --------------------------------------------------------------

test_that("reads current version end-to-end", {
  test_df <- data.frame(id = 1:5, val = letters[1:5])

  metadata <- list(data_sha = "sha_current", nrow = 5L, ncol = 2L)
  history <- list(
    list(version = "meta_v1", data_sha = "sha_current")
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      if (grepl("metadata.json$", s3_key)) metadata else history
    },
    .tbit_s3_download = function(conn, s3_key, local_path) {
      arrow::write_parquet(test_df, local_path)
      invisible(TRUE)
    }
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_read(conn, "customers")

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 5)
  expect_equal(result$id, 1:5)
})

test_that("reads specific version end-to-end", {
  df_v1 <- data.frame(x = 1:3)
  df_v2 <- data.frame(x = 10:12)

  metadata <- list(data_sha = "sha_v2")
  history <- list(
    list(version = "meta_v1", data_sha = "sha_v1"),
    list(version = "meta_v2", data_sha = "sha_v2")
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      if (grepl("metadata.json$", s3_key)) metadata else history
    },
    .tbit_s3_download = function(conn, s3_key, local_path) {
      # Should request sha_v1 since we asked for meta_v1
      if (grepl("sha_v1", s3_key)) {
        arrow::write_parquet(df_v1, local_path)
      } else {
        arrow::write_parquet(df_v2, local_path)
      }
      invisible(TRUE)
    }
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_read(conn, "customers", version = "meta_v1")

  expect_equal(result$x, 1:3)
})

test_that("errors when conn is not tbit_conn", {
  expect_error(tbit_read(list(), "tbl"), "tbit_conn")
  expect_error(tbit_read("not_conn", "tbl"), "tbit_conn")
})

test_that("validates table name", {
  conn <- mock_tbit_conn(list())
  expect_error(tbit_read(conn, ""), "must not be empty")
  expect_error(tbit_read(conn, "bad name!"), class = "rlang_error")
})

test_that("errors when version not found", {
  metadata <- list(data_sha = "sha_current")
  history <- list(
    list(version = "meta_v1", data_sha = "sha_v1")
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      if (grepl("metadata.json$", s3_key)) metadata else history
    }
  )

  conn <- mock_tbit_conn(list())
  expect_error(tbit_read(conn, "tbl", version = "nonexistent"), "not found")
})

test_that("propagates S3 errors from metadata read", {
  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      cli::cli_abort("Failed to read JSON from S3.")
    }
  )

  conn <- mock_tbit_conn(list())
  expect_error(tbit_read(conn, "customers"), "Failed to read JSON")
})

test_that("propagates S3 errors from parquet download", {
  metadata <- list(data_sha = "sha1")
  history <- list(list(version = "v1", data_sha = "sha1"))

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      if (grepl("metadata.json$", s3_key)) metadata else history
    },
    .tbit_s3_download = function(conn, s3_key, local_path) {
      cli::cli_abort("Failed to download file from S3.")
    }
  )

  conn <- mock_tbit_conn(list())
  expect_error(tbit_read(conn, "tbl"), "Failed to download")
})


# --- .tbit_read_metadata() ----------------------------------------------------

test_that("reads both metadata.json and version_history.json from S3", {
  metadata <- list(data_sha = "abc123", nrow = 10L, ncol = 3L)
  history <- list(
    list(version = "v1", data_sha = "abc123", timestamp = "2026-01-01")
  )

  call_keys <- character()
  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      call_keys <<- c(call_keys, s3_key)
      if (grepl("metadata.json$", s3_key)) metadata else history
    }
  )

  conn <- mock_tbit_conn(list())
  result <- .tbit_read_metadata(conn, "customers")

  expect_type(result, "list")
  expect_named(result, c("current", "history"))
  expect_equal(result$current$data_sha, "abc123")
  expect_length(result$history, 1)

  # Verify correct S3 keys were used
  expect_equal(call_keys[1], "customers/.metadata/metadata.json")
  expect_equal(call_keys[2], "customers/.metadata/version_history.json")
})

test_that("validates table name", {
  conn <- mock_tbit_conn(list())

  expect_error(.tbit_read_metadata(conn, ""), "must not be empty")
  expect_error(.tbit_read_metadata(conn, "bad name!"), class = "rlang_error")
})

test_that("propagates S3 errors", {
  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      cli::cli_abort("Failed to read JSON from S3.")
    }
  )

  conn <- mock_tbit_conn(list())
  expect_error(.tbit_read_metadata(conn, "customers"), "Failed to read JSON")
})


# --- .tbit_resolve_version() --------------------------------------------------

test_that("NULL version returns current data_sha", {
  metadata_list <- list(
    current = list(data_sha = "sha_current"),
    history = list()
  )

  result <- .tbit_resolve_version(metadata_list, version = NULL, name = "tbl")
  expect_equal(result, "sha_current")
})

test_that("errors when current metadata has no data_sha", {
  metadata_list <- list(
    current = list(nrow = 10),
    history = list()
  )

  expect_error(
    .tbit_resolve_version(metadata_list, version = NULL, name = "tbl"),
    "data_sha"
  )
})

test_that("errors when current data_sha is empty string", {
  metadata_list <- list(
    current = list(data_sha = ""),
    history = list()
  )

  expect_error(
    .tbit_resolve_version(metadata_list, version = NULL, name = "tbl"),
    "data_sha"
  )
})

test_that("resolves specific version from history", {
  metadata_list <- list(
    current = list(data_sha = "sha_v2"),
    history = list(
      list(version = "meta_sha_v1", data_sha = "sha_v1"),
      list(version = "meta_sha_v2", data_sha = "sha_v2")
    )
  )

  result <- .tbit_resolve_version(metadata_list, version = "meta_sha_v1", name = "tbl")
  expect_equal(result, "sha_v1")
})

test_that("resolves latest version from history", {
  metadata_list <- list(
    current = list(data_sha = "sha_v2"),
    history = list(
      list(version = "meta_sha_v1", data_sha = "sha_v1"),
      list(version = "meta_sha_v2", data_sha = "sha_v2")
    )
  )

  result <- .tbit_resolve_version(metadata_list, version = "meta_sha_v2", name = "tbl")
  expect_equal(result, "sha_v2")
})

test_that("errors when version not found in history", {
  metadata_list <- list(
    current = list(data_sha = "sha_current"),
    history = list(
      list(version = "meta_sha_v1", data_sha = "sha_v1")
    )
  )

  expect_error(
    .tbit_resolve_version(metadata_list, version = "nonexistent", name = "tbl"),
    "not found"
  )
})

test_that("errors when history is empty and version requested", {
  metadata_list <- list(
    current = list(data_sha = "sha_current"),
    history = list()
  )

  expect_error(
    .tbit_resolve_version(metadata_list, version = "some_sha", name = "tbl"),
    "No version history"
  )
})

test_that("errors when version is empty string", {
  metadata_list <- list(
    current = list(data_sha = "x"),
    history = list()
  )

  expect_error(
    .tbit_resolve_version(metadata_list, version = "", name = "tbl"),
    "non-empty"
  )
})

test_that("errors when version is non-character", {
  metadata_list <- list(
    current = list(data_sha = "x"),
    history = list()
  )

  expect_error(
    .tbit_resolve_version(metadata_list, version = 123, name = "tbl"),
    "non-empty string"
  )
})

test_that("errors when resolved data_sha is NULL in history entry", {
  metadata_list <- list(
    current = list(data_sha = "sha_current"),
    history = list(
      list(version = "v1")
      # no data_sha field
    )
  )

  expect_error(
    .tbit_resolve_version(metadata_list, version = "v1", name = "tbl"),
    "data_sha"
  )
})

test_that("errors when resolved data_sha is empty in history entry", {
  metadata_list <- list(
    current = list(data_sha = "sha_current"),
    history = list(
      list(version = "v1", data_sha = "")
    )
  )

  expect_error(
    .tbit_resolve_version(metadata_list, version = "v1", name = "tbl"),
    "data_sha"
  )
})

test_that("handles multiple versions with same data_sha", {
  metadata_list <- list(
    current = list(data_sha = "sha_shared"),
    history = list(
      list(version = "meta_v1", data_sha = "sha_shared"),
      list(version = "meta_v2", data_sha = "sha_shared")
    )
  )

  # Both should resolve to same data_sha
  expect_equal(
    .tbit_resolve_version(metadata_list, version = "meta_v1", name = "tbl"),
    "sha_shared"
  )
  expect_equal(
    .tbit_resolve_version(metadata_list, version = "meta_v2", name = "tbl"),
    "sha_shared"
  )
})


# --- .tbit_read_parquet() -----------------------------------------------------

test_that("downloads parquet from S3 and reads as data frame", {
  # Create a real parquet file to serve as mock download
  test_df <- data.frame(id = 1:3, name = c("a", "b", "c"))

  local_mocked_bindings(
    .tbit_s3_download = function(conn, s3_key, local_path) {
      # Verify correct key construction
      expect_equal(s3_key, "customers/abc123.parquet")
      arrow::write_parquet(test_df, local_path)
      invisible(TRUE)
    }
  )

  conn <- mock_tbit_conn(list())
  result <- .tbit_read_parquet(conn, "customers", "abc123")

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 3)
  expect_equal(ncol(result), 2)
  expect_equal(result$id, 1:3)
  expect_equal(result$name, c("a", "b", "c"))
})

test_that("validates table name", {
  conn <- mock_tbit_conn(list())
  expect_error(.tbit_read_parquet(conn, "", "sha"), "must not be empty")
})

test_that("validates data_sha is non-empty string", {
  conn <- mock_tbit_conn(list())

  expect_error(.tbit_read_parquet(conn, "tbl", ""), "non-empty")
  expect_error(.tbit_read_parquet(conn, "tbl", NULL), "non-empty")
  expect_error(.tbit_read_parquet(conn, "tbl", 123), "non-empty")
})

test_that("propagates S3 download errors", {
  local_mocked_bindings(
    .tbit_s3_download = function(conn, s3_key, local_path) {
      cli::cli_abort("Failed to download file from S3.")
    }
  )

  conn <- mock_tbit_conn(list())
  expect_error(.tbit_read_parquet(conn, "customers", "abc"), "Failed to download")
})

test_that("constructs correct S3 key for nested table names", {
  test_df <- data.frame(x = 1)

  captured_key <- NULL
  local_mocked_bindings(
    .tbit_s3_download = function(conn, s3_key, local_path) {
      captured_key <<- s3_key
      arrow::write_parquet(test_df, local_path)
      invisible(TRUE)
    }
  )

  conn <- mock_tbit_conn(list())
  .tbit_read_parquet(conn, "ADSL", "sha256hash")

  expect_equal(captured_key, "ADSL/sha256hash.parquet")
})
