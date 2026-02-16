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


# --- .tbit_build_metadata() ---------------------------------------------------

test_that("builds metadata with auto-computed fields", {
  df <- data.frame(id = 1:3, name = c("a", "b", "c"))
  result <- .tbit_build_metadata(df, data_sha = "abc123")

  expect_equal(result$data_sha, "abc123")
  expect_equal(result$nrow, 3)
  expect_equal(result$ncol, 2)
  expect_equal(result$colnames, c("id", "name"))
  expect_true(nzchar(result$created_at))
  expect_true(nzchar(result$tbit_version))
})

test_that("includes custom metadata", {
  df <- data.frame(x = 1)
  result <- .tbit_build_metadata(df, "sha", custom = list(desc = "test", tags = list("a")))

  expect_equal(result$custom$desc, "test")
  expect_equal(result$custom$tags, list("a"))
})

test_that("errors when custom is not a named list", {
  df <- data.frame(x = 1)
  expect_error(.tbit_build_metadata(df, "sha", custom = "not_list"), "metadata")
  expect_error(.tbit_build_metadata(df, "sha", custom = list(1, 2)), "metadata")
})

test_that("metadata with no custom has no custom field", {
  df <- data.frame(x = 1)
  result <- .tbit_build_metadata(df, "sha")

  expect_null(result$custom)
})


# --- .tbit_has_changes() ------------------------------------------------------

test_that("returns 'full' when table is new (no metadata in S3)", {
  local_mocked_bindings(
    .tbit_s3_exists = function(conn, s3_key) FALSE
  )

  conn <- mock_tbit_conn(list())
  result <- .tbit_has_changes(conn, "new_table", "sha1", "meta_sha1")

  expect_equal(result, "full")
})

test_that("returns 'none' when metadata_sha matches", {
  current_meta <- list(data_sha = "sha1", nrow = 10L, ncol = 3L)
  current_meta_sha <- .tbit_compute_metadata_sha(current_meta)

  local_mocked_bindings(
    .tbit_s3_exists = function(conn, s3_key) TRUE,
    .tbit_s3_read_json = function(conn, s3_key) current_meta
  )

  conn <- mock_tbit_conn(list())
  result <- .tbit_has_changes(conn, "tbl", "sha1", current_meta_sha)

  expect_equal(result, "none")
})

test_that("returns 'metadata_only' when data same but metadata different", {
  current_meta <- list(data_sha = "sha1", nrow = 10L, ncol = 3L)

  # New metadata has different nrow but same data_sha
  new_meta <- list(data_sha = "sha1", nrow = 20L, ncol = 3L)
  new_meta_sha <- .tbit_compute_metadata_sha(new_meta)

  local_mocked_bindings(
    .tbit_s3_exists = function(conn, s3_key) TRUE,
    .tbit_s3_read_json = function(conn, s3_key) current_meta
  )

  conn <- mock_tbit_conn(list())
  result <- .tbit_has_changes(conn, "tbl", "sha1", new_meta_sha)

  expect_equal(result, "metadata_only")
})

test_that("returns 'full' when data changed", {
  current_meta <- list(data_sha = "sha_old", nrow = 10L, ncol = 3L)

  new_meta <- list(data_sha = "sha_new", nrow = 10L, ncol = 3L)
  new_meta_sha <- .tbit_compute_metadata_sha(new_meta)

  local_mocked_bindings(
    .tbit_s3_exists = function(conn, s3_key) TRUE,
    .tbit_s3_read_json = function(conn, s3_key) current_meta
  )

  conn <- mock_tbit_conn(list())
  result <- .tbit_has_changes(conn, "tbl", "sha_new", new_meta_sha)

  expect_equal(result, "full")
})

test_that("checks correct S3 key for metadata", {
  captured_key <- NULL
  local_mocked_bindings(
    .tbit_s3_exists = function(conn, s3_key) {
      captured_key <<- s3_key
      FALSE
    }
  )

  conn <- mock_tbit_conn(list())
  .tbit_has_changes(conn, "customers", "sha1", "meta_sha1")

  expect_equal(captured_key, "customers/.metadata/metadata.json")
})


# --- .tbit_write_metadata() ---------------------------------------------------

test_that("writes metadata.json and version_history.json to git repo", {
  withr::with_tempdir({
    # Set up a minimal git repo for git author
    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test User", user.email = "test@test.com")

    conn <- mock_tbit_conn(list())
    conn$path <- getwd()

    metadata <- list(
      data_sha = "sha1",
      nrow = 5L,
      ncol = 2L,
      colnames = c("id", "val"),
      created_at = "2026-01-01T00:00:00Z",
      tbit_version = "0.0.1"
    )
    meta_sha <- .tbit_compute_metadata_sha(metadata)

    # Mock S3 writes — just capture calls
    s3_keys <- character()
    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) {
        s3_keys <<- c(s3_keys, s3_key)
        invisible(TRUE)
      }
    )

    result <- .tbit_write_metadata(conn, "customers", metadata, meta_sha, message = "Add data")

    # Git files written
    expect_true(fs::file_exists("customers/metadata.json"))
    expect_true(fs::file_exists("customers/version_history.json"))

    # metadata.json content
    written_meta <- jsonlite::read_json("customers/metadata.json")
    expect_equal(written_meta$data_sha, "sha1")
    expect_equal(written_meta$nrow, 5L)

    # version_history.json content
    history <- jsonlite::read_json("customers/version_history.json")
    expect_length(history, 1)
    expect_equal(history[[1]]$version, meta_sha)
    expect_equal(history[[1]]$data_sha, "sha1")
    expect_equal(history[[1]]$commit_message, "Add data")
    expect_equal(history[[1]]$author$name, "Test User")
    expect_equal(history[[1]]$author$email, "test@test.com")
  })
})

test_that("appends to existing version_history.json", {
  withr::with_tempdir({
    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")

    conn <- mock_tbit_conn(list())
    conn$path <- getwd()

    # Pre-populate history
    fs::dir_create("tbl")
    existing_history <- list(
      list(version = "old_sha", data_sha = "old_data", timestamp = "2025-12-01")
    )
    jsonlite::write_json(existing_history, "tbl/version_history.json",
                         auto_unbox = TRUE, pretty = TRUE)

    metadata <- list(data_sha = "new_data", nrow = 10L, created_at = "2026-01-01T00:00:00Z")
    meta_sha <- .tbit_compute_metadata_sha(metadata)

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) invisible(TRUE)
    )

    .tbit_write_metadata(conn, "tbl", metadata, meta_sha)

    history <- jsonlite::read_json("tbl/version_history.json")
    expect_length(history, 2)
    # New entry is prepended (most recent first)
    expect_equal(history[[1]]$version, meta_sha)
    expect_equal(history[[2]]$version, "old_sha")
  })
})

test_that("writes versioned metadata snapshot to S3", {
  withr::with_tempdir({
    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")

    conn <- mock_tbit_conn(list())
    conn$path <- getwd()

    metadata <- list(data_sha = "sha1", nrow = 5L, created_at = "2026-01-01T00:00:00Z")
    meta_sha <- .tbit_compute_metadata_sha(metadata)

    s3_keys <- character()
    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) {
        s3_keys <<- c(s3_keys, s3_key)
        invisible(TRUE)
      }
    )

    result <- .tbit_write_metadata(conn, "tbl", metadata, meta_sha)

    # Should write 3 S3 keys: metadata.json, version_history.json, {meta_sha}.json
    expect_length(s3_keys, 3)
    expect_true(any(grepl("metadata.json$", s3_keys)))
    expect_true(any(grepl("version_history.json$", s3_keys)))
    expect_true(any(grepl(paste0(meta_sha, ".json$"), s3_keys)))
  })
})

test_that("uses default commit message when none provided", {
  withr::with_tempdir({
    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")

    conn <- mock_tbit_conn(list())
    conn$path <- getwd()

    metadata <- list(data_sha = "sha1", nrow = 5L, created_at = "2026-01-01T00:00:00Z")
    meta_sha <- .tbit_compute_metadata_sha(metadata)

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) invisible(TRUE)
    )

    .tbit_write_metadata(conn, "my_table", metadata, meta_sha)

    history <- jsonlite::read_json("my_table/version_history.json")
    expect_equal(history[[1]]$commit_message, "Update my_table")
  })
})

test_that("returns metadata_sha and paths", {
  withr::with_tempdir({
    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")

    conn <- mock_tbit_conn(list())
    conn$path <- getwd()

    metadata <- list(data_sha = "sha1", nrow = 5L, created_at = "2026-01-01T00:00:00Z")
    meta_sha <- .tbit_compute_metadata_sha(metadata)

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) invisible(TRUE)
    )

    result <- .tbit_write_metadata(conn, "tbl", metadata, meta_sha)

    expect_equal(result$metadata_sha, meta_sha)
    expect_length(result$git_paths, 2)
    expect_length(result$s3_keys, 3)
  })
})
