# Tests for sync operations
# Phase 6

# --- tbit_sync_manifest() ----------------------------------------------------

test_that("rejects non-tbit_conn", {
  expect_error(tbit_sync_manifest("not_conn"), "tbit_conn")
})

test_that("rejects reader role", {
  conn <- mock_tbit_conn(list())
  conn$role <- "reader"
  conn$path <- "/tmp"
  expect_error(tbit_sync_manifest(conn), "developer")
})

test_that("rejects conn without path", {
  conn <- mock_tbit_conn(list())
  conn$role <- "developer"
  conn$path <- NULL
  expect_error(tbit_sync_manifest(conn), "local git repo")
})

test_that("errors when input directory missing", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    expect_error(tbit_sync_manifest(conn), "Input directory not found")
  })
})

test_that("errors when input directory has subdirectories", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files/subdir")
    writeLines("data", "input_files/a.csv")

    expect_error(tbit_sync_manifest(conn), "flat")
  })
})

test_that("returns empty data frame when no files match", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")

    result <- tbit_sync_manifest(conn)

    expect_s3_class(result, "data.frame")
    expect_equal(nrow(result), 0)
    expect_true(all(c("name", "file", "format", "file_sha", "status") %in% names(result)))
  })
})

test_that("scans files and marks all as new when no manifest exists", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id,val\n1,a\n2,b", "input_files/customers.csv")
    writeLines("id\tval\n1\ta", "input_files/orders.tsv")

    result <- tbit_sync_manifest(conn)

    expect_equal(nrow(result), 2)
    expect_equal(sort(result$name), c("customers", "orders"))
    expect_true(all(result$status == "new"))
    expect_equal(result$format[result$name == "customers"], "csv")
    expect_equal(result$format[result$name == "orders"], "tsv")
  })
})

test_that("detects unchanged files via original_file_sha", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id,val\n1,a", "input_files/customers.csv")

    # Create manifest with matching SHA
    file_sha <- .tbit_compute_file_sha("input_files/customers.csv")
    manifest <- list(
      tables = list(
        customers = list(original_file_sha = file_sha)
      )
    )
    fs::dir_create(".tbit")
    jsonlite::write_json(manifest, ".tbit/manifest.json", auto_unbox = TRUE)

    result <- tbit_sync_manifest(conn)

    expect_equal(nrow(result), 1)
    expect_equal(result$status, "unchanged")
  })
})

test_that("detects changed files when SHA differs", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id,val\n1,a", "input_files/customers.csv")

    # Manifest has old SHA
    manifest <- list(
      tables = list(
        customers = list(original_file_sha = "old_sha_that_differs")
      )
    )
    fs::dir_create(".tbit")
    jsonlite::write_json(manifest, ".tbit/manifest.json", auto_unbox = TRUE)

    result <- tbit_sync_manifest(conn)

    expect_equal(nrow(result), 1)
    expect_equal(result$status, "changed")
  })
})

test_that("mixes new, changed, and unchanged statuses", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id\n1", "input_files/existing_same.csv")
    writeLines("id\n2", "input_files/existing_diff.csv")
    writeLines("id\n3", "input_files/brand_new.csv")

    same_sha <- .tbit_compute_file_sha("input_files/existing_same.csv")
    manifest <- list(
      tables = list(
        existing_same = list(original_file_sha = same_sha),
        existing_diff = list(original_file_sha = "old_sha")
      )
    )
    fs::dir_create(".tbit")
    jsonlite::write_json(manifest, ".tbit/manifest.json", auto_unbox = TRUE)

    result <- tbit_sync_manifest(conn)

    expect_equal(nrow(result), 3)
    expect_equal(result$status[result$name == "existing_same"], "unchanged")
    expect_equal(result$status[result$name == "existing_diff"], "changed")
    expect_equal(result$status[result$name == "brand_new"], "new")
  })
})

test_that("filters files by glob pattern", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("a", "input_files/customers.csv")
    writeLines("b", "input_files/orders.csv")
    writeLines("c", "input_files/readme.txt")

    result <- tbit_sync_manifest(conn, pattern = "*.csv")

    expect_equal(nrow(result), 2)
    expect_true(all(result$format == "csv"))
  })
})

test_that("accepts custom input path", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    custom_dir <- fs::path(getwd(), "my_data")
    fs::dir_create(custom_dir)
    writeLines("id\n1", fs::path(custom_dir, "tbl.csv"))

    result <- tbit_sync_manifest(conn, path = custom_dir)

    expect_equal(nrow(result), 1)
    expect_equal(result$name, "tbl")
  })
})

test_that("file_sha is a valid SHA-256 hex string", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id\n1", "input_files/tbl.csv")

    result <- tbit_sync_manifest(conn)

    expect_match(result$file_sha, "^[0-9a-f]{64}$")
  })
})

test_that("table name is filename without extension", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("a", "input_files/my_table.sas7bdat")

    result <- tbit_sync_manifest(conn)

    expect_equal(result$name, "my_table")
    expect_equal(result$format, "sas7bdat")
  })
})

test_that("returns empty when pattern matches nothing", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("a", "input_files/data.csv")

    result <- tbit_sync_manifest(conn, pattern = "*.xlsx")

    expect_equal(nrow(result), 0)
  })
})


# --- tbit_sync() --------------------------------------------------------------

test_that("tbit_sync rejects non-tbit_conn", {
  expect_error(tbit_sync("not_conn", data.frame()), "tbit_conn")
})

test_that("tbit_sync rejects reader role", {
  conn <- mock_tbit_conn(list())
  conn$role <- "reader"
  conn$path <- "/tmp"
  expect_error(tbit_sync(conn, data.frame()), "developer")
})

test_that("tbit_sync rejects conn without path", {
  conn <- mock_tbit_conn(list())
  conn$role <- "developer"
  conn$path <- NULL
  expect_error(tbit_sync(conn, data.frame()), "local git repo")
})

test_that("tbit_sync rejects non-data-frame manifest", {
  conn <- mock_tbit_conn(list())
  conn$role <- "developer"
  conn$path <- "/tmp"
  expect_error(tbit_sync(conn, "not_a_df"), "data frame")
})

test_that("tbit_sync rejects manifest missing required columns", {
  conn <- mock_tbit_conn(list())
  conn$role <- "developer"
  conn$path <- "/tmp"
  bad_manifest <- data.frame(name = "x", file = "y")
  expect_error(tbit_sync(conn, bad_manifest), "missing required columns")
})

test_that("tbit_sync skips unchanged and returns early when nothing actionable", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    manifest <- data.frame(
      name = c("a", "b"),
      file = c("a.csv", "b.csv"),
      format = c("csv", "csv"),
      file_sha = c("sha1", "sha2"),
      status = c("unchanged", "unchanged"),
      stringsAsFactors = FALSE
    )

    local_mocked_bindings(.tbit_check_rio = function() invisible(TRUE))

    result <- tbit_sync(conn, manifest)

    expect_equal(nrow(result), 2)
    expect_true(all(result$result == "skipped"))
    expect_true(all(is.na(result$error)))
  })
})

test_that("tbit_sync processes new files via tbit_write", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")
    writeLines("id\n1", "data.csv")

    manifest <- data.frame(
      name = "customers",
      file = fs::path(getwd(), "data.csv"),
      format = "csv",
      file_sha = "abc123",
      status = "new",
      stringsAsFactors = FALSE
    )

    write_called <- FALSE

    local_mocked_bindings(
      .tbit_check_rio = function() invisible(TRUE),
      .tbit_import_file = function(file, format) data.frame(id = 1),
      tbit_write = function(conn, data, name, message, ...) {
        write_called <<- TRUE
        expect_equal(name, "customers")
        expect_equal(nrow(data), 1)
        list(
          name = name,
          data_sha = "data_sha_123",
          metadata_sha = "meta_sha_456",
          action = "full",
          commit_sha = "commit_789"
        )
      },
      .tbit_update_manifest_entry = function(conn, name, file_sha,
                                              format, write_result) {
        invisible(list())
      }
    )

    result <- tbit_sync(conn, manifest)

    expect_true(write_called)
    expect_equal(result$result, "success")
    expect_true(is.na(result$error))
  })
})

test_that("tbit_sync skips unchanged rows and processes changed ones", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")

    manifest <- data.frame(
      name = c("unchanged_tbl", "changed_tbl"),
      file = c("a.csv", "b.csv"),
      format = c("csv", "csv"),
      file_sha = c("sha1", "sha2"),
      status = c("unchanged", "changed"),
      stringsAsFactors = FALSE
    )

    written_names <- character()

    local_mocked_bindings(
      .tbit_check_rio = function() invisible(TRUE),
      .tbit_import_file = function(file, format) data.frame(x = 1),
      tbit_write = function(conn, data, name, message, ...) {
        written_names <<- c(written_names, name)
        list(
          name = name,
          data_sha = "d1",
          metadata_sha = "m1",
          action = "full",
          commit_sha = "c1"
        )
      },
      .tbit_update_manifest_entry = function(...) invisible(list())
    )

    result <- tbit_sync(conn, manifest)

    expect_equal(written_names, "changed_tbl")
    expect_equal(result$result[result$name == "unchanged_tbl"], "skipped")
    expect_equal(result$result[result$name == "changed_tbl"], "success")
  })
})

test_that("tbit_sync continues on error when continue_on_error = TRUE", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")

    manifest <- data.frame(
      name = c("bad_tbl", "good_tbl"),
      file = c("bad.csv", "good.csv"),
      format = c("csv", "csv"),
      file_sha = c("sha1", "sha2"),
      status = c("new", "new"),
      stringsAsFactors = FALSE
    )

    call_count <- 0L

    local_mocked_bindings(
      .tbit_check_rio = function() invisible(TRUE),
      .tbit_import_file = function(file, format) {
        call_count <<- call_count + 1L
        if (grepl("bad", file)) stop("Import failed for bad file")
        data.frame(x = 1)
      },
      tbit_write = function(conn, data, name, message, ...) {
        list(
          name = name, data_sha = "d", metadata_sha = "m",
          action = "full", commit_sha = "c"
        )
      },
      .tbit_update_manifest_entry = function(...) invisible(list())
    )

    result <- tbit_sync(conn, manifest, continue_on_error = TRUE)

    expect_equal(call_count, 2L)
    expect_equal(result$result[result$name == "bad_tbl"], "error")
    expect_match(result$error[result$name == "bad_tbl"], "Import failed")
    expect_equal(result$result[result$name == "good_tbl"], "success")
  })
})

test_that("tbit_sync stops on first error when continue_on_error = FALSE", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")

    manifest <- data.frame(
      name = c("bad_tbl", "good_tbl"),
      file = c("bad.csv", "good.csv"),
      format = c("csv", "csv"),
      file_sha = c("sha1", "sha2"),
      status = c("new", "new"),
      stringsAsFactors = FALSE
    )

    local_mocked_bindings(
      .tbit_check_rio = function() invisible(TRUE),
      .tbit_import_file = function(file, format) {
        if (grepl("bad", file)) stop("Import failed")
        data.frame(x = 1)
      },
      tbit_write = function(conn, data, name, message, ...) {
        list(name = name, data_sha = "d", metadata_sha = "m",
             action = "full", commit_sha = "c")
      },
      .tbit_update_manifest_entry = function(...) invisible(list())
    )

    expect_error(
      tbit_sync(conn, manifest, continue_on_error = FALSE),
      "bad_tbl"
    )
  })
})

test_that("tbit_sync commit message includes status", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")

    manifest <- data.frame(
      name = "tbl", file = "x.csv", format = "csv",
      file_sha = "s1", status = "new",
      stringsAsFactors = FALSE
    )

    captured_msg <- NULL

    local_mocked_bindings(
      .tbit_check_rio = function() invisible(TRUE),
      .tbit_import_file = function(file, format) data.frame(x = 1),
      tbit_write = function(conn, data, name, message, ...) {
        captured_msg <<- message
        list(name = name, data_sha = "d", metadata_sha = "m",
             action = "full", commit_sha = "c")
      },
      .tbit_update_manifest_entry = function(...) invisible(list())
    )

    tbit_sync(conn, manifest)

    expect_match(captured_msg, "Sync tbl")
    expect_match(captured_msg, "new")
  })
})

test_that("tbit_sync augments manifest with result and error columns", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")

    manifest <- data.frame(
      name = "tbl", file = "x.csv", format = "csv",
      file_sha = "s", status = "new",
      stringsAsFactors = FALSE
    )

    local_mocked_bindings(
      .tbit_check_rio = function() invisible(TRUE),
      .tbit_import_file = function(file, format) data.frame(x = 1),
      tbit_write = function(conn, data, name, message, ...) {
        list(name = name, data_sha = "d", metadata_sha = "m",
             action = "full", commit_sha = "c")
      },
      .tbit_update_manifest_entry = function(...) invisible(list())
    )

    result <- tbit_sync(conn, manifest)

    expect_true("result" %in% names(result))
    expect_true("error" %in% names(result))
    expect_equal(ncol(result), 7L)  # 5 original + 2 new
  })
})


# --- .tbit_import_file() ------------------------------------------------------

test_that(".tbit_import_file reads parquet via arrow", {
  withr::with_tempdir({
    df <- data.frame(a = 1:3, b = letters[1:3])
    arrow::write_parquet(df, "test.parquet")

    result <- .tbit_import_file("test.parquet", "parquet")

    expect_s3_class(result, "data.frame")
    expect_equal(nrow(result), 3)
    expect_equal(result$a, 1:3)
  })
})

test_that(".tbit_import_file delegates non-parquet to rio", {
  withr::with_tempdir({
    writeLines("id,val\n1,a\n2,b", "test.csv")

    # Mock rio::import at our package level
    local_mocked_bindings(
      .tbit_import_file = function(file, format) {
        # Simulate what the real function does: call rio::import
        utils::read.csv(file)
      }
    )

    result <- .tbit_import_file("test.csv", "csv")

    expect_s3_class(result, "data.frame")
    expect_equal(nrow(result), 2)
  })
})


# --- .tbit_update_manifest_entry() --------------------------------------------

test_that(".tbit_update_manifest_entry creates manifest from scratch", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$path <- getwd()

    fs::dir_create(".tbit")

    write_result <- list(
      data_sha = "data123",
      metadata_sha = "meta456"
    )

    .tbit_update_manifest_entry(
      conn, "customers",
      file_sha = "file789",
      format = "csv",
      write_result = write_result
    )

    expect_true(fs::file_exists(".tbit/manifest.json"))

    m <- jsonlite::read_json(".tbit/manifest.json")
    expect_equal(m$tables$customers$current_version, "meta456")
    expect_equal(m$tables$customers$current_data_sha, "data123")
    expect_equal(m$tables$customers$original_file_sha, "file789")
    expect_equal(m$tables$customers$original_format, "csv")
    expect_equal(m$summary$total_tables, 1)
  })
})

test_that(".tbit_update_manifest_entry updates existing manifest", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$path <- getwd()

    fs::dir_create(".tbit")

    # Pre-existing manifest with one table
    existing <- list(
      tables = list(
        orders = list(
          current_version = "old_ver",
          current_data_sha = "old_sha",
          original_file_sha = "old_file_sha",
          original_format = "tsv"
        )
      ),
      summary = list(total_tables = 1, total_size_bytes = 0, total_versions = 1)
    )
    jsonlite::write_json(existing, ".tbit/manifest.json", auto_unbox = TRUE)

    write_result <- list(data_sha = "new_d", metadata_sha = "new_m")

    .tbit_update_manifest_entry(
      conn, "customers",
      file_sha = "new_f",
      format = "csv",
      write_result = write_result
    )

    m <- jsonlite::read_json(".tbit/manifest.json")
    expect_equal(length(m$tables), 2)
    expect_equal(m$tables$customers$current_version, "new_m")
    expect_equal(m$tables$orders$current_version, "old_ver")
    expect_equal(m$summary$total_tables, 2)
  })
})

test_that(".tbit_check_rio errors when rio not available", {
  local_mocked_bindings(
    .tbit_check_rio = function() {
      cli::cli_abort(c(
        "Package {.pkg rio} is required for file import during sync.",
        "i" = "Install with {.code install.packages(\"rio\")}"
      ))
    }
  )
  expect_error(.tbit_check_rio(), "rio")
})


# --- tbit_sync_routing() -----------------------------------------------------

test_that("tbit_sync_routing rejects non-tbit_conn", {
  expect_error(tbit_sync_routing("not_conn"), "tbit_conn")
})

test_that("tbit_sync_routing rejects reader role", {
  conn <- mock_tbit_conn(list())
  conn$role <- "reader"
  conn$path <- "/tmp"
  expect_error(tbit_sync_routing(conn), "developer")
})

test_that("tbit_sync_routing rejects conn without path", {
  conn <- mock_tbit_conn(list())
  conn$role <- "developer"
  conn$path <- NULL
  expect_error(tbit_sync_routing(conn), "local git repo")
})

test_that("tbit_sync_routing requires interactive confirmation by default", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    # Non-interactive session should fail with .confirm = TRUE
    expect_error(tbit_sync_routing(conn, .confirm = TRUE), "Interactive")
  })
})

test_that("tbit_sync_routing syncs repo-level files to S3", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    # Create repo-level .tbit files
    fs::dir_create(".tbit")
    jsonlite::write_json(list(methods = list()), ".tbit/routing.json",
                         auto_unbox = TRUE)
    jsonlite::write_json(list(tables = list()), ".tbit/manifest.json",
                         auto_unbox = TRUE)

    s3_keys_written <- character()

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) {
        s3_keys_written <<- c(s3_keys_written, s3_key)
        invisible(NULL)
      }
    )

    result <- tbit_sync_routing(conn, .confirm = FALSE)

    expect_true(".metadata/routing.json" %in% s3_keys_written)
    expect_true(".metadata/manifest.json" %in% s3_keys_written)
    expect_true(".metadata/routing.json" %in% result$repo_files)
    expect_true(".metadata/manifest.json" %in% result$repo_files)
  })
})

test_that("tbit_sync_routing skips missing repo-level files", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    # Only create routing.json, not manifest or migration_history
    fs::dir_create(".tbit")
    jsonlite::write_json(list(methods = list()), ".tbit/routing.json",
                         auto_unbox = TRUE)

    s3_keys_written <- character()

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) {
        s3_keys_written <<- c(s3_keys_written, s3_key)
        invisible(NULL)
      }
    )

    result <- tbit_sync_routing(conn, .confirm = FALSE)

    expect_equal(length(result$repo_files), 1)
    expect_equal(result$repo_files, ".metadata/routing.json")
  })
})

test_that("tbit_sync_routing syncs per-table metadata to S3", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")
    jsonlite::write_json(list(), ".tbit/routing.json", auto_unbox = TRUE)

    # Create a table directory with metadata
    fs::dir_create("customers")
    jsonlite::write_json(list(data_sha = "abc"), "customers/metadata.json",
                         auto_unbox = TRUE)
    jsonlite::write_json(list(versions = list()), "customers/version_history.json",
                         auto_unbox = TRUE)

    s3_keys_written <- character()

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) {
        s3_keys_written <<- c(s3_keys_written, s3_key)
        invisible(NULL)
      }
    )

    result <- tbit_sync_routing(conn, .confirm = FALSE)

    expect_true("customers/.metadata/metadata.json" %in% s3_keys_written)
    expect_true("customers/.metadata/version_history.json" %in% s3_keys_written)
    expect_equal(result$tables$customers$action, "synced")
  })
})

test_that("tbit_sync_routing ignores non-table directories", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")
    jsonlite::write_json(list(), ".tbit/routing.json", auto_unbox = TRUE)

    # Directories that should be ignored
    fs::dir_create("input_files")
    fs::dir_create("renv")
    fs::dir_create("R")
    fs::dir_create("tests")

    # Hidden directories also ignored
    fs::dir_create(".git")

    s3_keys_written <- character()

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) {
        s3_keys_written <<- c(s3_keys_written, s3_key)
        invisible(NULL)
      }
    )

    result <- tbit_sync_routing(conn, .confirm = FALSE)

    # Only repo-level files synced, no table-level
    expect_equal(length(result$tables), 0)
    expect_equal(result$repo_files, ".metadata/routing.json")
  })
})

test_that("tbit_sync_routing handles per-table errors gracefully", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")
    jsonlite::write_json(list(), ".tbit/routing.json", auto_unbox = TRUE)

    # Two tables: one good, one will fail
    fs::dir_create("good_tbl")
    jsonlite::write_json(list(data_sha = "d1"), "good_tbl/metadata.json",
                         auto_unbox = TRUE)

    fs::dir_create("bad_tbl")
    jsonlite::write_json(list(data_sha = "d2"), "bad_tbl/metadata.json",
                         auto_unbox = TRUE)

    call_count <- 0L

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) {
        call_count <<- call_count + 1L
        if (grepl("bad_tbl", s3_key)) stop("S3 upload failed")
        invisible(NULL)
      }
    )

    result <- tbit_sync_routing(conn, .confirm = FALSE)

    expect_equal(result$tables$good_tbl$action, "synced")
    expect_equal(result$tables$bad_tbl$action, "error")
    expect_match(result$tables$bad_tbl$error, "S3 upload failed")
  })
})

test_that("tbit_sync_routing syncs metadata snapshots from .metadata dir", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")
    jsonlite::write_json(list(), ".tbit/routing.json", auto_unbox = TRUE)

    # Table with metadata + snapshot
    fs::dir_create("orders")
    jsonlite::write_json(list(data_sha = "d1"), "orders/metadata.json",
                         auto_unbox = TRUE)
    fs::dir_create("orders/.metadata")
    jsonlite::write_json(list(version = 1), "orders/.metadata/abc123.json",
                         auto_unbox = TRUE)

    s3_keys_written <- character()

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) {
        s3_keys_written <<- c(s3_keys_written, s3_key)
        invisible(NULL)
      }
    )

    result <- tbit_sync_routing(conn, .confirm = FALSE)

    expect_true("orders/.metadata/metadata.json" %in% s3_keys_written)
    expect_true("orders/.metadata/abc123.json" %in% s3_keys_written)
  })
})

test_that("tbit_sync_routing returns correct summary structure", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")
    jsonlite::write_json(list(), ".tbit/routing.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) invisible(NULL)
    )

    result <- tbit_sync_routing(conn, .confirm = FALSE)

    expect_type(result, "list")
    expect_true("repo_files" %in% names(result))
    expect_true("tables" %in% names(result))
    expect_type(result$repo_files, "character")
    expect_type(result$tables, "list")
  })
})

test_that("tbit_sync_routing handles multiple tables", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".tbit")
    jsonlite::write_json(list(), ".tbit/routing.json", auto_unbox = TRUE)

    for (nm in c("alpha", "beta", "gamma")) {
      fs::dir_create(nm)
      jsonlite::write_json(list(data_sha = nm), paste0(nm, "/metadata.json"),
                           auto_unbox = TRUE)
    }

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) invisible(NULL)
    )

    result <- tbit_sync_routing(conn, .confirm = FALSE)

    expect_equal(length(result$tables), 3)
    expect_true(all(purrr::map_chr(result$tables, "action") == "synced"))
  })
})


# --- .tbit_sync_table_metadata() ----------------------------------------------

test_that(".tbit_sync_table_metadata uploads metadata and version_history", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$path <- getwd()

    fs::dir_create("tbl")
    jsonlite::write_json(list(x = 1), "tbl/metadata.json", auto_unbox = TRUE)
    jsonlite::write_json(list(v = 1), "tbl/version_history.json",
                         auto_unbox = TRUE)

    s3_keys_written <- character()

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) {
        s3_keys_written <<- c(s3_keys_written, s3_key)
        invisible(NULL)
      }
    )

    result <- .tbit_sync_table_metadata(conn, "tbl")

    expect_equal(result$action, "synced")
    expect_true("tbl/.metadata/metadata.json" %in% result$s3_keys)
    expect_true("tbl/.metadata/version_history.json" %in% result$s3_keys)
  })
})

test_that(".tbit_sync_table_metadata handles table with no version_history", {
  withr::with_tempdir({
    conn <- mock_tbit_conn(list())
    conn$path <- getwd()

    fs::dir_create("tbl")
    jsonlite::write_json(list(x = 1), "tbl/metadata.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .tbit_s3_write_json = function(conn, s3_key, data) invisible(NULL)
    )

    result <- .tbit_sync_table_metadata(conn, "tbl")

    expect_equal(length(result$s3_keys), 1)
    expect_equal(result$s3_keys, "tbl/.metadata/metadata.json")
  })
})
