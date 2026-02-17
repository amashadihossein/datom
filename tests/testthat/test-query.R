# Tests for query operations
# Phase 5, Chunk 6

# --- tbit_list() --------------------------------------------------------------

test_that("rejects non-tbit_conn", {
  expect_error(tbit_list("not_conn"), "tbit_conn")
})

test_that("returns empty data frame when manifest has no tables", {
  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      list(updated_at = "2026-01-01", tables = list(), summary = list())
    }
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_list(conn)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true("name" %in% names(result))
})

test_that("returns data frame with one row per table", {
  manifest <- list(
    tables = list(
      customers = list(
        current_version = "v1",
        current_data_sha = "sha1",
        last_updated = "2026-01-01"
      ),
      orders = list(
        current_version = "v2",
        current_data_sha = "sha2",
        last_updated = "2026-01-02"
      )
    )
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_list(conn)

  expect_equal(nrow(result), 2)
  expect_equal(sort(result$name), c("customers", "orders"))
  expect_equal(result$current_version[result$name == "customers"], "v1")
  expect_equal(result$current_data_sha[result$name == "orders"], "sha2")
})

test_that("filters tables by glob pattern", {
  manifest <- list(
    tables = list(
      customer_us = list(current_version = "v1", last_updated = "2026-01-01"),
      customer_eu = list(current_version = "v2", last_updated = "2026-01-02"),
      orders = list(current_version = "v3", last_updated = "2026-01-03")
    )
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_list(conn, pattern = "customer_*")

  expect_equal(nrow(result), 2)
  expect_true(all(grepl("^customer_", result$name)))
})

test_that("returns empty data frame when pattern matches nothing", {
  manifest <- list(
    tables = list(
      customers = list(current_version = "v1", last_updated = "2026-01-01")
    )
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_list(conn, pattern = "zzz_*")

  expect_equal(nrow(result), 0)
})

test_that("includes version_count when include_versions = TRUE", {
  manifest <- list(
    tables = list(
      customers = list(
        current_version = "v1",
        last_updated = "2026-01-01",
        version_count = 15L
      )
    )
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_tbit_conn(list())

  result_no <- tbit_list(conn, include_versions = FALSE)
  expect_false("version_count" %in% names(result_no))

  result_yes <- tbit_list(conn, include_versions = TRUE)
  expect_true("version_count" %in% names(result_yes))
  expect_equal(result_yes$version_count, 15L)
})

test_that("reads correct S3 key for manifest", {
  captured_key <- NULL
  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      captured_key <<- s3_key
      list(tables = list())
    }
  )

  conn <- mock_tbit_conn(list())
  tbit_list(conn)

  expect_equal(captured_key, ".metadata/manifest.json")
})

test_that("errors when manifest cannot be read from S3", {
  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) stop("NoSuchKey")
  )

  conn <- mock_tbit_conn(list())
  expect_error(tbit_list(conn), "manifest")
})

test_that("handles missing fields gracefully with NA", {
  manifest <- list(
    tables = list(
      sparse = list()
    )
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_list(conn)

  expect_equal(nrow(result), 1)
  expect_equal(result$name, "sparse")
  expect_true(is.na(result$current_version))
  expect_true(is.na(result$last_updated))
})


# --- tbit_history() -----------------------------------------------------------

test_that("rejects non-tbit_conn", {
  expect_error(tbit_history("not_conn", "t"), "tbit_conn")
})

test_that("validates table name", {
  conn <- mock_tbit_conn(list())
  expect_error(tbit_history(conn, ""), "must not be empty")
})

test_that("rejects invalid n", {
  conn <- mock_tbit_conn(list())
  expect_error(tbit_history(conn, "tbl", n = 0), "positive")
  expect_error(tbit_history(conn, "tbl", n = -1), "positive")
  expect_error(tbit_history(conn, "tbl", n = "x"), "positive")
})

test_that("returns data frame with version history", {
  history <- list(
    list(
      version = "meta_sha_1",
      data_sha = "data_sha_1",
      timestamp = "2026-01-15T10:00:00Z",
      author = "jane@co.com",
      commit_message = "Initial load"
    ),
    list(
      version = "meta_sha_2",
      data_sha = "data_sha_2",
      timestamp = "2026-01-14T10:00:00Z",
      author = "john@co.com",
      commit_message = "Fix data"
    )
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) history
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_history(conn, "customers")

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 2)
  expect_equal(result$version[1], "meta_sha_1")
  expect_equal(result$data_sha[2], "data_sha_2")
  expect_equal(result$author[1], "jane@co.com")
  expect_equal(result$commit_message[2], "Fix data")
})

test_that("limits results to n entries", {
  history <- list(
    list(version = "v1", data_sha = "s1", timestamp = "t1"),
    list(version = "v2", data_sha = "s2", timestamp = "t2"),
    list(version = "v3", data_sha = "s3", timestamp = "t3")
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) history
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_history(conn, "tbl", n = 2)

  expect_equal(nrow(result), 2)
  expect_equal(result$version, c("v1", "v2"))
})

test_that("returns empty data frame for empty history", {
  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) list()
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_history(conn, "tbl")

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true("version" %in% names(result))
})

test_that("reads correct S3 key for version history", {
  captured_key <- NULL
  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      captured_key <<- s3_key
      list()
    }
  )

  conn <- mock_tbit_conn(list())
  tbit_history(conn, "ADSL")

  expect_equal(captured_key, "ADSL/.metadata/version_history.json")
})

test_that("errors when version history cannot be read from S3", {
  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) stop("NoSuchKey")
  )

  conn <- mock_tbit_conn(list())
  expect_error(tbit_history(conn, "ghost"), "No version history")
})

test_that("handles author as list (name + email)", {
  history <- list(
    list(
      version = "v1",
      data_sha = "s1",
      timestamp = "2026-01-01",
      author = list(name = "Jane Doe", email = "jane@co.com"),
      commit_message = "Update"
    )
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) history
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_history(conn, "tbl")

  expect_equal(result$author, "Jane Doe <jane@co.com>")
})

test_that("handles missing fields with NA", {
  history <- list(
    list(version = "v1")
  )

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) history
  )

  conn <- mock_tbit_conn(list())
  result <- tbit_history(conn, "tbl")

  expect_equal(nrow(result), 1)
  expect_equal(result$version, "v1")
  expect_true(is.na(result$data_sha))
  expect_true(is.na(result$author))
})


# --- tbit_status() ------------------------------------------------------------

test_that("tbit_status rejects non-tbit_conn", {
  expect_error(tbit_status("not_conn"), "tbit_conn")
})

test_that("tbit_status returns connection info for reader", {
  conn <- mock_tbit_conn(list())
  conn$role <- "reader"

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) {
      list(tables = list(a = list(), b = list()))
    }
  )

  result <- tbit_status(conn)

  expect_equal(result$connection$project_name, "test-project")
  expect_equal(result$connection$role, "reader")
  expect_equal(result$tables$count, 2)
  expect_true(result$tables$available)
  expect_false(result$connection$has_path)
})

test_that("tbit_status handles S3 manifest read failure", {
  conn <- mock_tbit_conn(list())

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) stop("S3 error")
  )

  result <- tbit_status(conn)

  expect_false(result$tables$available)
  expect_equal(result$tables$count, 0)
})

test_that("tbit_status shows git info for developer", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    local_mocked_bindings(
      .tbit_s3_read_json = function(conn, s3_key) list(tables = list()),
      .tbit_status_git = function(path) {
        list(uncommitted = c("R/foo.R"), branch = "main")
      }
    )

    result <- tbit_status(conn)

    expect_equal(result$git$branch, "main")
    expect_equal(result$git$uncommitted, "R/foo.R")
  })
})

test_that("tbit_status shows clean git when no changes", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    local_mocked_bindings(
      .tbit_s3_read_json = function(conn, s3_key) list(tables = list()),
      .tbit_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- tbit_status(conn)

    expect_equal(length(result$git$uncommitted), 0)
  })
})

test_that("tbit_status shows input_files sync state", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id\n1", "input_files/new_tbl.csv")
    writeLines("id\n2", "input_files/existing.csv")

    # Manifest has existing with matching SHA
    existing_sha <- .tbit_compute_file_sha("input_files/existing.csv")
    fs::dir_create(".tbit")
    jsonlite::write_json(list(
      tables = list(
        existing = list(original_file_sha = existing_sha)
      )
    ), ".tbit/manifest.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .tbit_s3_read_json = function(conn, s3_key) list(tables = list()),
      .tbit_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- tbit_status(conn)

    expect_equal(result$input_files$n_total, 2)
    expect_equal(result$input_files$n_new, 1)
    expect_equal(result$input_files$n_unchanged, 1)
    expect_equal(result$input_files$n_changed, 0)
  })
})

test_that("tbit_status omits input_files when dir missing", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    local_mocked_bindings(
      .tbit_s3_read_json = function(conn, s3_key) list(tables = list()),
      .tbit_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- tbit_status(conn)

    expect_null(result$input_files)
  })
})

test_that("tbit_status detects changed input files", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id\n99", "input_files/orders.csv")

    fs::dir_create(".tbit")
    jsonlite::write_json(list(
      tables = list(orders = list(original_file_sha = "old_sha"))
    ), ".tbit/manifest.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .tbit_s3_read_json = function(conn, s3_key) list(tables = list()),
      .tbit_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- tbit_status(conn)

    expect_equal(result$input_files$n_changed, 1)
    expect_equal(result$input_files$n_new, 0)
  })
})

test_that("tbit_status returns correct structure", {
  conn <- mock_tbit_conn(list())

  local_mocked_bindings(
    .tbit_s3_read_json = function(conn, s3_key) list(tables = list())
  )

  result <- tbit_status(conn)

  expect_type(result, "list")
  expect_true("connection" %in% names(result))
  expect_true("tables" %in% names(result))
  expect_equal(result$connection$bucket, "test-bucket")
})

test_that("tbit_status handles empty input_files dir", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")

    local_mocked_bindings(
      .tbit_s3_read_json = function(conn, s3_key) list(tables = list()),
      .tbit_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- tbit_status(conn)

    expect_equal(result$input_files$n_total, 0)
  })
})
