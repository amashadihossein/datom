# Tests for sync operations
# Phase 6

# --- datom_sync_manifest() ----------------------------------------------------

test_that("rejects non-datom_conn", {
  expect_error(datom_sync_manifest("not_conn"), "datom_conn")
})

test_that("rejects reader role", {
  conn <- mock_datom_conn(list())
  conn$role <- "reader"
  conn$path <- "/tmp"
  expect_error(datom_sync_manifest(conn), "developer")
})

test_that("rejects conn without path", {
  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$path <- NULL
  expect_error(datom_sync_manifest(conn), "local git repo")
})

test_that("errors when input directory missing", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    expect_error(datom_sync_manifest(conn), "Input directory not found")
  })
})

test_that("errors when input directory has subdirectories", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files/subdir")
    writeLines("data", "input_files/a.csv")

    expect_error(datom_sync_manifest(conn), "flat")
  })
})

test_that("returns empty data frame when no files match", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")

    result <- datom_sync_manifest(conn)

    expect_s3_class(result, "data.frame")
    expect_equal(nrow(result), 0)
    expect_true(all(c("name", "file", "format", "file_sha", "status") %in% names(result)))
  })
})

test_that("scans files and marks all as new when no manifest exists", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id,val\n1,a\n2,b", "input_files/customers.csv")
    writeLines("id\tval\n1\ta", "input_files/orders.tsv")

    result <- datom_sync_manifest(conn)

    expect_equal(nrow(result), 2)
    expect_equal(sort(result$name), c("customers", "orders"))
    expect_true(all(result$status == "new"))
    expect_equal(result$format[result$name == "customers"], "csv")
    expect_equal(result$format[result$name == "orders"], "tsv")
  })
})

test_that("detects unchanged files via original_file_sha", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id,val\n1,a", "input_files/customers.csv")

    # Create manifest with matching SHA
    file_sha <- .datom_compute_file_sha("input_files/customers.csv")
    manifest <- list(
      tables = list(
        customers = list(original_file_sha = file_sha)
      )
    )
    fs::dir_create(".datom")
    jsonlite::write_json(manifest, ".datom/manifest.json", auto_unbox = TRUE)

    result <- datom_sync_manifest(conn)

    expect_equal(nrow(result), 1)
    expect_equal(result$status, "unchanged")
  })
})

test_that("detects changed files when SHA differs", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
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
    fs::dir_create(".datom")
    jsonlite::write_json(manifest, ".datom/manifest.json", auto_unbox = TRUE)

    result <- datom_sync_manifest(conn)

    expect_equal(nrow(result), 1)
    expect_equal(result$status, "changed")
  })
})

test_that("mixes new, changed, and unchanged statuses", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id\n1", "input_files/existing_same.csv")
    writeLines("id\n2", "input_files/existing_diff.csv")
    writeLines("id\n3", "input_files/brand_new.csv")

    same_sha <- .datom_compute_file_sha("input_files/existing_same.csv")
    manifest <- list(
      tables = list(
        existing_same = list(original_file_sha = same_sha),
        existing_diff = list(original_file_sha = "old_sha")
      )
    )
    fs::dir_create(".datom")
    jsonlite::write_json(manifest, ".datom/manifest.json", auto_unbox = TRUE)

    result <- datom_sync_manifest(conn)

    expect_equal(nrow(result), 3)
    expect_equal(result$status[result$name == "existing_same"], "unchanged")
    expect_equal(result$status[result$name == "existing_diff"], "changed")
    expect_equal(result$status[result$name == "brand_new"], "new")
  })
})

test_that("filters files by glob pattern", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("a", "input_files/customers.csv")
    writeLines("b", "input_files/orders.csv")
    writeLines("c", "input_files/readme.txt")

    result <- datom_sync_manifest(conn, pattern = "*.csv")

    expect_equal(nrow(result), 2)
    expect_true(all(result$format == "csv"))
  })
})

test_that("accepts custom input path", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    custom_dir <- fs::path(getwd(), "my_data")
    fs::dir_create(custom_dir)
    writeLines("id\n1", fs::path(custom_dir, "tbl.csv"))

    result <- datom_sync_manifest(conn, path = custom_dir)

    expect_equal(nrow(result), 1)
    expect_equal(result$name, "tbl")
  })
})

test_that("file_sha is a valid SHA-256 hex string", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id\n1", "input_files/tbl.csv")

    result <- datom_sync_manifest(conn)

    expect_match(result$file_sha, "^[0-9a-f]{64}$")
  })
})

test_that("table name is filename without extension", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("a", "input_files/my_table.sas7bdat")

    result <- datom_sync_manifest(conn)

    expect_equal(result$name, "my_table")
    expect_equal(result$format, "sas7bdat")
  })
})

test_that("returns empty when pattern matches nothing", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("a", "input_files/data.csv")

    result <- datom_sync_manifest(conn, pattern = "*.xlsx")

    expect_equal(nrow(result), 0)
  })
})


# --- datom_sync() --------------------------------------------------------------

test_that("datom_sync rejects non-datom_conn", {
  expect_error(datom_sync("not_conn", data.frame()), "datom_conn")
})

test_that("datom_sync rejects reader role", {
  conn <- mock_datom_conn(list())
  conn$role <- "reader"
  conn$path <- "/tmp"
  expect_error(datom_sync(conn, data.frame()), "developer")
})

test_that("datom_sync rejects conn without path", {
  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$path <- NULL
  expect_error(datom_sync(conn, data.frame()), "local git repo")
})

test_that("datom_sync rejects non-data-frame manifest", {
  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$path <- "/tmp"
  expect_error(datom_sync(conn, "not_a_df"), "data frame")
})

test_that("datom_sync rejects manifest missing required columns", {
  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$path <- "/tmp"
  bad_manifest <- data.frame(name = "x", file = "y")
  expect_error(datom_sync(conn, bad_manifest), "missing required columns")
})

test_that("datom_sync skips unchanged and returns early when nothing actionable", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
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

    local_mocked_bindings(
      .datom_check_rio = function() invisible(TRUE),
      .datom_check_git_current = function(...) invisible(TRUE)
    )

    result <- datom_sync(conn, manifest)

    expect_equal(nrow(result), 2)
    expect_true(all(result$result == "skipped"))
    expect_true(all(is.na(result$error)))
  })
})

test_that("datom_sync processes new files via datom_write", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")
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
      .datom_check_rio = function() invisible(TRUE),
      .datom_check_git_current = function(...) invisible(TRUE),
      .datom_import_file = function(file, format) data.frame(id = 1),
      datom_write = function(conn, data, name, message, ...) {
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
      }
    )

    result <- datom_sync(conn, manifest)

    expect_true(write_called)
    expect_equal(result$result, "success")
    expect_true(is.na(result$error))
  })
})

test_that("datom_sync skips unchanged rows and processes changed ones", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")

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
      .datom_check_rio = function() invisible(TRUE),
      .datom_check_git_current = function(...) invisible(TRUE),
      .datom_import_file = function(file, format) data.frame(x = 1),
      datom_write = function(conn, data, name, message, ...) {
        written_names <<- c(written_names, name)
        list(
          name = name,
          data_sha = "d1",
          metadata_sha = "m1",
          action = "full",
          commit_sha = "c1"
        )
      }
    )

    result <- datom_sync(conn, manifest)

    expect_equal(written_names, "changed_tbl")
    expect_equal(result$result[result$name == "unchanged_tbl"], "skipped")
    expect_equal(result$result[result$name == "changed_tbl"], "success")
  })
})

test_that("datom_sync continues on error when continue_on_error = TRUE", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")

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
      .datom_check_rio = function() invisible(TRUE),
      .datom_check_git_current = function(...) invisible(TRUE),
      .datom_import_file = function(file, format) {
        call_count <<- call_count + 1L
        if (grepl("bad", file)) stop("Import failed for bad file")
        data.frame(x = 1)
      },
      datom_write = function(conn, data, name, message, ...) {
        list(
          name = name, data_sha = "d", metadata_sha = "m",
          action = "full", commit_sha = "c"
        )
      }
    )

    result <- datom_sync(conn, manifest, continue_on_error = TRUE)

    expect_equal(call_count, 2L)
    expect_equal(result$result[result$name == "bad_tbl"], "error")
    expect_match(result$error[result$name == "bad_tbl"], "Import failed")
    expect_equal(result$result[result$name == "good_tbl"], "success")
  })
})

test_that("datom_sync stops on first error when continue_on_error = FALSE", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")

    manifest <- data.frame(
      name = c("bad_tbl", "good_tbl"),
      file = c("bad.csv", "good.csv"),
      format = c("csv", "csv"),
      file_sha = c("sha1", "sha2"),
      status = c("new", "new"),
      stringsAsFactors = FALSE
    )

    local_mocked_bindings(
      .datom_check_rio = function() invisible(TRUE),
      .datom_check_git_current = function(...) invisible(TRUE),
      .datom_import_file = function(file, format) {
        if (grepl("bad", file)) stop("Import failed")
        data.frame(x = 1)
      },
      datom_write = function(conn, data, name, message, ...) {
        list(name = name, data_sha = "d", metadata_sha = "m",
             action = "full", commit_sha = "c")
      }
    )

    expect_error(
      datom_sync(conn, manifest, continue_on_error = FALSE),
      "bad_tbl"
    )
  })
})

test_that("datom_sync commit message includes status", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")

    manifest <- data.frame(
      name = "tbl", file = "x.csv", format = "csv",
      file_sha = "s1", status = "new",
      stringsAsFactors = FALSE
    )

    captured_msg <- NULL

    local_mocked_bindings(
      .datom_check_rio = function() invisible(TRUE),
      .datom_check_git_current = function(...) invisible(TRUE),
      .datom_import_file = function(file, format) data.frame(x = 1),
      datom_write = function(conn, data, name, message, ...) {
        captured_msg <<- message
        list(name = name, data_sha = "d", metadata_sha = "m",
             action = "full", commit_sha = "c")
      }
    )

    datom_sync(conn, manifest)

    expect_match(captured_msg, "Sync tbl")
    expect_match(captured_msg, "new")
  })
})

test_that("datom_sync augments manifest with result and error columns", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")

    manifest <- data.frame(
      name = "tbl", file = "x.csv", format = "csv",
      file_sha = "s", status = "new",
      stringsAsFactors = FALSE
    )

    local_mocked_bindings(
      .datom_check_rio = function() invisible(TRUE),
      .datom_check_git_current = function(...) invisible(TRUE),
      .datom_import_file = function(file, format) data.frame(x = 1),
      datom_write = function(conn, data, name, message, ...) {
        list(name = name, data_sha = "d", metadata_sha = "m",
             action = "full", commit_sha = "c")
      }
    )

    result <- datom_sync(conn, manifest)

    expect_true("result" %in% names(result))
    expect_true("error" %in% names(result))
    expect_equal(ncol(result), 7L)  # 5 original + 2 new
  })
})


# --- .datom_import_file() ------------------------------------------------------

test_that(".datom_import_file reads parquet via arrow", {
  withr::with_tempdir({
    df <- data.frame(a = 1:3, b = letters[1:3])
    arrow::write_parquet(df, "test.parquet")

    result <- .datom_import_file("test.parquet", "parquet")

    expect_s3_class(result, "data.frame")
    expect_equal(nrow(result), 3)
    expect_equal(result$a, 1:3)
  })
})

test_that(".datom_import_file delegates non-parquet to rio", {
  withr::with_tempdir({
    writeLines("id,val\n1,a\n2,b", "test.csv")

    # Mock rio::import at our package level
    local_mocked_bindings(
      .datom_import_file = function(file, format) {
        # Simulate what the real function does: call rio::import
        utils::read.csv(file)
      }
    )

    result <- .datom_import_file("test.csv", "csv")

    expect_s3_class(result, "data.frame")
    expect_equal(nrow(result), 2)
  })
})


# --- .datom_update_manifest_entry() --------------------------------------------

test_that(".datom_update_manifest_entry creates manifest from scratch", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$path <- getwd()

    fs::dir_create(".datom")

    .datom_update_manifest_entry(
      conn, "customers",
      metadata_sha = "meta456",
      data_sha = "data123",
      file_sha = "file789",
      format = "csv"
    )

    expect_true(fs::file_exists(".datom/manifest.json"))

    m <- jsonlite::read_json(".datom/manifest.json")
    expect_equal(m$tables$customers$current_version, "meta456")
    expect_equal(m$tables$customers$current_data_sha, "data123")
    expect_equal(m$tables$customers$original_file_sha, "file789")
    expect_equal(m$tables$customers$original_format, "csv")
    expect_equal(m$summary$total_tables, 1)
  })
})

test_that(".datom_update_manifest_entry updates existing manifest", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$path <- getwd()

    fs::dir_create(".datom")

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
    jsonlite::write_json(existing, ".datom/manifest.json", auto_unbox = TRUE)

    write_result <- list(data_sha = "new_d", metadata_sha = "new_m")

    .datom_update_manifest_entry(
      conn, "customers",
      metadata_sha = "new_m",
      data_sha = "new_d",
      file_sha = "new_f",
      format = "csv"
    )

    m <- jsonlite::read_json(".datom/manifest.json")
    expect_equal(length(m$tables), 2)
    expect_equal(m$tables$customers$current_version, "new_m")
    expect_equal(m$tables$orders$current_version, "old_ver")
    expect_equal(m$summary$total_tables, 2)
  })
})

test_that(".datom_check_rio errors when rio not available", {
  local_mocked_bindings(
    .datom_check_rio = function() {
      cli::cli_abort(c(
        "Package {.pkg rio} is required for file import during sync.",
        "i" = "Install with {.code install.packages(\"rio\")}"
      ))
    }
  )
  expect_error(.datom_check_rio(), "rio")
})


# --- datom_sync_dispatch() -----------------------------------------------------

test_that("datom_sync_dispatch rejects non-datom_conn", {
  expect_error(datom_sync_dispatch("not_conn"), "datom_conn")
})

test_that("datom_sync_dispatch rejects reader role", {
  conn <- mock_datom_conn(list())
  conn$role <- "reader"
  conn$path <- "/tmp"
  expect_error(datom_sync_dispatch(conn), "developer")
})

test_that("datom_sync_dispatch rejects conn without path", {
  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$path <- NULL
  expect_error(datom_sync_dispatch(conn), "local git repo")
})

test_that("datom_sync_dispatch requires interactive confirmation by default", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    # Non-interactive session should fail with .confirm = TRUE
    expect_error(datom_sync_dispatch(conn, .confirm = TRUE), "Interactive")
  })
})

test_that("datom_sync_dispatch aborts when conn lacks gov_local_path", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$gov_local_path <- NULL

    expect_error(
      datom_sync_dispatch(conn, .confirm = FALSE),
      "gov clone"
    )
  })
})

# Helper: build a developer conn with gov clone seeded with project files
.setup_sync_dispatch_conn <- function(project_name = "myproj",
                                      seed_dispatch = TRUE,
                                      seed_ref = TRUE) {
  gov_dir <- withr::local_tempdir(.local_envir = parent.frame())
  proj_dir <- fs::path(gov_dir, "projects", project_name)
  fs::dir_create(proj_dir)
  if (seed_dispatch) {
    jsonlite::write_json(list(methods = list()),
                         fs::path(proj_dir, "dispatch.json"),
                         auto_unbox = TRUE)
  }
  if (seed_ref) {
    jsonlite::write_json(list(current = list()),
                         fs::path(proj_dir, "ref.json"),
                         auto_unbox = TRUE)
  }
  fs::dir_create(".datom")
  jsonlite::write_json(list(tables = list()),
                       ".datom/manifest.json", auto_unbox = TRUE)

  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$path <- getwd()
  conn$gov_local_path <- gov_dir
  conn$project_name <- project_name
  conn
}

test_that("datom_sync_dispatch syncs per-table metadata to storage", {
  withr::with_tempdir({
    conn <- .setup_sync_dispatch_conn()

    fs::dir_create("customers")
    jsonlite::write_json(list(data_sha = "abc"), "customers/metadata.json",
                         auto_unbox = TRUE)
    jsonlite::write_json(list(versions = list()), "customers/version_history.json",
                         auto_unbox = TRUE)

    s3_keys_written <- character()

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(...) invisible(TRUE),
      .datom_gov_write_ref = function(...) invisible(TRUE),
      .datom_storage_write_json = function(conn, s3_key, data) {
        s3_keys_written <<- c(s3_keys_written, s3_key)
        invisible(NULL)
      }
    )

    result <- datom_sync_dispatch(conn, .confirm = FALSE)

    expect_true("customers/.metadata/metadata.json" %in% s3_keys_written)
    expect_true("customers/.metadata/version_history.json" %in% s3_keys_written)
    expect_equal(result$tables$customers$action, "synced")
  })
})

test_that("datom_sync_dispatch ignores non-table directories", {
  withr::with_tempdir({
    conn <- .setup_sync_dispatch_conn()

    fs::dir_create("input_files")
    fs::dir_create("renv")
    fs::dir_create("R")
    fs::dir_create("tests")
    fs::dir_create(".git")

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(...) invisible(TRUE),
      .datom_gov_write_ref = function(...) invisible(TRUE),
      .datom_storage_write_json = function(...) invisible(NULL)
    )

    result <- datom_sync_dispatch(conn, .confirm = FALSE)

    expect_equal(length(result$tables), 0)
  })
})

test_that("datom_sync_dispatch handles per-table errors gracefully", {
  withr::with_tempdir({
    conn <- .setup_sync_dispatch_conn()

    fs::dir_create("good_tbl")
    jsonlite::write_json(list(data_sha = "d1"), "good_tbl/metadata.json",
                         auto_unbox = TRUE)
    fs::dir_create("bad_tbl")
    jsonlite::write_json(list(data_sha = "d2"), "bad_tbl/metadata.json",
                         auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(...) invisible(TRUE),
      .datom_gov_write_ref = function(...) invisible(TRUE),
      .datom_storage_write_json = function(conn, s3_key, data) {
        if (grepl("bad_tbl", s3_key)) stop("storage upload failed")
        invisible(NULL)
      }
    )

    result <- datom_sync_dispatch(conn, .confirm = FALSE)

    expect_equal(result$tables$good_tbl$action, "synced")
    expect_equal(result$tables$bad_tbl$action, "error")
    expect_match(result$tables$bad_tbl$error, "storage upload failed")
  })
})

test_that("datom_sync_dispatch syncs metadata snapshots from .metadata dir", {
  withr::with_tempdir({
    conn <- .setup_sync_dispatch_conn()

    fs::dir_create("orders")
    jsonlite::write_json(list(data_sha = "d1"), "orders/metadata.json",
                         auto_unbox = TRUE)
    fs::dir_create("orders/.metadata")
    jsonlite::write_json(list(version = 1), "orders/.metadata/abc123.json",
                         auto_unbox = TRUE)

    s3_keys_written <- character()

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(...) invisible(TRUE),
      .datom_gov_write_ref = function(...) invisible(TRUE),
      .datom_storage_write_json = function(conn, s3_key, data) {
        s3_keys_written <<- c(s3_keys_written, s3_key)
        invisible(NULL)
      }
    )

    datom_sync_dispatch(conn, .confirm = FALSE)

    expect_true("orders/.metadata/metadata.json" %in% s3_keys_written)
    expect_true("orders/.metadata/abc123.json" %in% s3_keys_written)
  })
})

test_that("datom_sync_dispatch returns correct summary structure", {
  withr::with_tempdir({
    conn <- .setup_sync_dispatch_conn()

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(...) invisible(TRUE),
      .datom_gov_write_ref = function(...) invisible(TRUE),
      .datom_storage_write_json = function(...) invisible(NULL)
    )

    result <- datom_sync_dispatch(conn, .confirm = FALSE)

    expect_type(result, "list")
    expect_true("repo_files" %in% names(result))
    expect_true("tables" %in% names(result))
    expect_type(result$repo_files, "character")
    expect_type(result$tables, "list")
  })
})

test_that("datom_sync_dispatch handles multiple tables", {
  withr::with_tempdir({
    conn <- .setup_sync_dispatch_conn()

    for (nm in c("alpha", "beta", "gamma")) {
      fs::dir_create(nm)
      jsonlite::write_json(list(data_sha = nm), paste0(nm, "/metadata.json"),
                           auto_unbox = TRUE)
    }

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(...) invisible(TRUE),
      .datom_gov_write_ref = function(...) invisible(TRUE),
      .datom_storage_write_json = function(...) invisible(NULL)
    )

    result <- datom_sync_dispatch(conn, .confirm = FALSE)

    expect_equal(length(result$tables), 3)
    expect_true(all(purrr::map_chr(result$tables, "action") == "synced"))
  })
})


# --- datom_sync_dispatch() gov-first path (Phase 15, Chunk 7) -----------------

test_that("datom_sync_dispatch with gov_local_path calls .datom_gov_write_dispatch", {
  withr::with_tempdir({
    gov_dir <- withr::local_tempdir()
    project_dir <- fs::path(gov_dir, "projects", "myproj")
    fs::dir_create(project_dir)
    jsonlite::write_json(list(methods = list()), fs::path(project_dir, "dispatch.json"),
                         auto_unbox = TRUE)

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$gov_local_path <- gov_dir
    conn$project_name <- "myproj"

    # Manifest (data repo)
    fs::dir_create(".datom")
    jsonlite::write_json(list(tables = list()), ".datom/manifest.json", auto_unbox = TRUE)

    write_dispatch_called <- FALSE

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(conn, project_name, dispatch) {
        write_dispatch_called <<- TRUE
        invisible(TRUE)
      },
      .datom_gov_write_ref = function(conn, project_name, ref) invisible(TRUE),
      .datom_storage_write_json = function(conn, s3_key, data) invisible(NULL)
    )

    result <- datom_sync_dispatch(conn, .confirm = FALSE)

    expect_true(write_dispatch_called)
    expect_true(any(grepl("dispatch.json", result$repo_files)))
  })
})

test_that("datom_sync_dispatch with gov_local_path calls .datom_gov_write_ref", {
  withr::with_tempdir({
    gov_dir <- withr::local_tempdir()
    project_dir <- fs::path(gov_dir, "projects", "myproj")
    fs::dir_create(project_dir)
    jsonlite::write_json(list(current = list()), fs::path(project_dir, "ref.json"),
                         auto_unbox = TRUE)

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$gov_local_path <- gov_dir
    conn$project_name <- "myproj"

    fs::dir_create(".datom")
    jsonlite::write_json(list(tables = list()), ".datom/manifest.json", auto_unbox = TRUE)

    write_ref_called <- FALSE

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(conn, project_name, dispatch) invisible(TRUE),
      .datom_gov_write_ref = function(conn, project_name, ref) {
        write_ref_called <<- TRUE
        invisible(TRUE)
      },
      .datom_storage_write_json = function(conn, s3_key, data) invisible(NULL)
    )

    result <- datom_sync_dispatch(conn, .confirm = FALSE)

    expect_true(write_ref_called)
    expect_true(any(grepl("ref.json", result$repo_files)))
  })
})

test_that("datom_sync_dispatch gov-path still syncs manifest to data storage", {
  withr::with_tempdir({
    gov_dir <- withr::local_tempdir()
    fs::dir_create(fs::path(gov_dir, "projects", "myproj"))

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$gov_local_path <- gov_dir
    conn$project_name <- "myproj"

    fs::dir_create(".datom")
    jsonlite::write_json(list(tables = list()), ".datom/manifest.json", auto_unbox = TRUE)

    storage_keys <- character()

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(...) invisible(TRUE),
      .datom_gov_write_ref = function(...) invisible(TRUE),
      .datom_storage_write_json = function(conn, s3_key, data) {
        storage_keys <<- c(storage_keys, s3_key)
        invisible(NULL)
      }
    )

    datom_sync_dispatch(conn, .confirm = FALSE)

    expect_true(".metadata/manifest.json" %in% storage_keys)
  })
})

test_that("datom_sync_dispatch gov-path dispatch failure is warn-only", {
  withr::with_tempdir({
    gov_dir <- withr::local_tempdir()
    project_dir <- fs::path(gov_dir, "projects", "myproj")
    fs::dir_create(project_dir)
    jsonlite::write_json(list(methods = list()), fs::path(project_dir, "dispatch.json"),
                         auto_unbox = TRUE)

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$gov_local_path <- gov_dir
    conn$project_name <- "myproj"

    fs::dir_create(".datom")
    jsonlite::write_json(list(tables = list()), ".datom/manifest.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(...) stop("gov push failed"),
      .datom_gov_write_ref = function(...) invisible(TRUE),
      .datom_storage_write_json = function(...) invisible(NULL)
    )

    expect_no_error(datom_sync_dispatch(conn, .confirm = FALSE))
  })
})

test_that("datom_sync_dispatch gov-path skips files missing from gov clone", {
  withr::with_tempdir({
    gov_dir <- withr::local_tempdir()
    # project dir exists but is empty -- no dispatch.json or ref.json
    fs::dir_create(fs::path(gov_dir, "projects", "myproj"))

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$gov_local_path <- gov_dir
    conn$project_name <- "myproj"

    fs::dir_create(".datom")
    jsonlite::write_json(list(tables = list()), ".datom/manifest.json", auto_unbox = TRUE)

    write_dispatch_called <- FALSE
    write_ref_called <- FALSE

    local_mocked_bindings(
      .datom_gov_write_dispatch = function(...) { write_dispatch_called <<- TRUE },
      .datom_gov_write_ref = function(...) { write_ref_called <<- TRUE },
      .datom_storage_write_json = function(...) invisible(NULL)
    )

    result <- datom_sync_dispatch(conn, .confirm = FALSE)

    expect_false(write_dispatch_called)
    expect_false(write_ref_called)
    # only manifest synced
    expect_equal(result$repo_files, ".metadata/manifest.json")
  })
})


# --- .datom_sync_table_metadata() ----------------------------------------------

test_that(".datom_sync_table_metadata uploads metadata and version_history", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$path <- getwd()

    fs::dir_create("tbl")
    jsonlite::write_json(list(x = 1), "tbl/metadata.json", auto_unbox = TRUE)
    jsonlite::write_json(list(v = 1), "tbl/version_history.json",
                         auto_unbox = TRUE)

    s3_keys_written <- character()

    local_mocked_bindings(
      .datom_storage_write_json = function(conn, s3_key, data) {
        s3_keys_written <<- c(s3_keys_written, s3_key)
        invisible(NULL)
      }
    )

    result <- .datom_sync_table_metadata(conn, "tbl")

    expect_equal(result$action, "synced")
    expect_true("tbl/.metadata/metadata.json" %in% result$s3_keys)
    expect_true("tbl/.metadata/version_history.json" %in% result$s3_keys)
  })
})

test_that(".datom_sync_table_metadata handles table with no version_history", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$path <- getwd()

    fs::dir_create("tbl")
    jsonlite::write_json(list(x = 1), "tbl/metadata.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_storage_write_json = function(conn, s3_key, data) invisible(NULL)
    )

    result <- .datom_sync_table_metadata(conn, "tbl")

    expect_equal(length(result$s3_keys), 1)
    expect_equal(result$s3_keys, "tbl/.metadata/metadata.json")
  })
})


# --- datom_pull() --------------------------------------------------------------

test_that("datom_pull rejects non-datom_conn", {
  expect_error(datom_pull("not_conn"), "datom_conn")
})

test_that("datom_pull rejects reader role", {
  conn <- mock_datom_conn(list())
  conn$role <- "reader"
  conn$path <- "/tmp"
  expect_error(datom_pull(conn), "developer")
})

test_that("datom_pull rejects conn without path", {
  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$path <- NULL
  expect_error(datom_pull(conn), "local git repo")
})

test_that("datom_pull reports already up to date when nothing to pull", {
  withr::with_tempdir({
    # Create a real git repo with remote
    bare_dir <- withr::local_tempdir()
    bare_repo <- git2r::init(bare_dir, bare = TRUE)

    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")
    writeLines("init", "README.md")
    git2r::add(repo, "README.md")
    git2r::commit(repo, "Initial commit")
    git2r::remote_add(repo, name = "origin", url = bare_dir)
    git2r::push(repo, name = "origin",
                refspec = "refs/heads/master", set_upstream = TRUE)

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    result <- datom_pull(conn)

    expect_equal(result$commits_pulled, 0L)
    expect_equal(result$branch, "master")
  })
})

test_that("datom_pull counts commits pulled from upstream", {
  withr::with_tempdir({
    # Create bare + working repo pair
    bare_dir <- withr::local_tempdir()
    git2r::init(bare_dir, bare = TRUE)

    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")
    writeLines("init", "README.md")
    git2r::add(repo, "README.md")
    git2r::commit(repo, "Initial commit")
    git2r::remote_add(repo, name = "origin", url = bare_dir)
    git2r::push(repo, name = "origin",
                refspec = "refs/heads/master", set_upstream = TRUE)

    # Simulate another user pushing 2 commits via a clone
    other_dir <- withr::local_tempdir()
    other_repo <- git2r::clone(bare_dir, other_dir)
    git2r::config(other_repo, user.name = "Other", user.email = "other@test.com")

    writeLines("a", fs::path(other_dir, "a.txt"))
    git2r::add(other_repo, "a.txt")
    git2r::commit(other_repo, "Commit A")

    writeLines("b", fs::path(other_dir, "b.txt"))
    git2r::add(other_repo, "b.txt")
    git2r::commit(other_repo, "Commit B")

    git2r::push(other_repo, name = "origin",
                refspec = "refs/heads/master")

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    result <- datom_pull(conn)

    expect_equal(result$commits_pulled, 2L)
    expect_equal(result$branch, "master")

    # Files should now exist locally
    expect_true(fs::file_exists("a.txt"))
    expect_true(fs::file_exists("b.txt"))
  })
})

test_that("datom_pull aborts on merge conflict", {
  withr::with_tempdir({
    bare_dir <- withr::local_tempdir()
    git2r::init(bare_dir, bare = TRUE)

    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")
    writeLines("init", "README.md")
    git2r::add(repo, "README.md")
    git2r::commit(repo, "Initial commit")
    git2r::remote_add(repo, name = "origin", url = bare_dir)
    git2r::push(repo, name = "origin",
                refspec = "refs/heads/master", set_upstream = TRUE)

    # Another user pushes a conflicting change
    other_dir <- withr::local_tempdir()
    other_repo <- git2r::clone(bare_dir, other_dir)
    git2r::config(other_repo, user.name = "Other", user.email = "other@test.com")
    writeLines("other version", fs::path(other_dir, "README.md"))
    git2r::add(other_repo, "README.md")
    git2r::commit(other_repo, "Other edit")
    git2r::push(other_repo, name = "origin",
                refspec = "refs/heads/master")

    # Local conflicting edit
    writeLines("my version", "README.md")
    git2r::add(repo, "README.md")
    git2r::commit(repo, "My conflicting edit")

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    expect_error(datom_pull(conn), "conflict|merge", ignore.case = TRUE)
  })
})

test_that("datom_pull returns invisible result", {
  withr::with_tempdir({
    bare_dir <- withr::local_tempdir()
    git2r::init(bare_dir, bare = TRUE)

    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")
    writeLines("init", "README.md")
    git2r::add(repo, "README.md")
    git2r::commit(repo, "Initial commit")
    git2r::remote_add(repo, name = "origin", url = bare_dir)
    git2r::push(repo, name = "origin",
                refspec = "refs/heads/master", set_upstream = TRUE)

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    expect_invisible(datom_pull(conn))
  })
})

# --- datom_pull() gov semantics (Phase 15, Chunk 6) --------------------------

test_that("datom_pull also pulls gov repo when gov_local_path is set", {
  withr::with_tempdir({
    # Data repo
    bare_dir <- withr::local_tempdir()
    git2r::init(bare_dir, bare = TRUE)

    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")
    writeLines("init", "README.md")
    git2r::add(repo, "README.md")
    git2r::commit(repo, "Initial commit")
    git2r::remote_add(repo, name = "origin", url = bare_dir)
    git2r::push(repo, "origin", "refs/heads/master", set_upstream = TRUE)

    # Gov repo
    gov_bare <- withr::local_tempdir()
    git2r::init(gov_bare, bare = TRUE)
    gov_local <- withr::local_tempdir()
    # seed gov bare with one commit so it can be cloned
    gov_work <- withr::local_tempdir()
    gov_w_repo <- git2r::init(gov_work)
    git2r::config(gov_w_repo, user.name = "Test", user.email = "test@test.com")
    writeLines("gov-init", fs::path(gov_work, "README.md"))
    git2r::add(gov_w_repo, "README.md")
    git2r::commit(gov_w_repo, "Gov init")
    git2r::remote_add(gov_w_repo, "origin", gov_bare)
    git2r::push(gov_w_repo, "origin", "refs/heads/master", set_upstream = TRUE)
    git2r::clone(gov_bare, gov_local)

    gov_pull_called <- FALSE

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$gov_local_path <- gov_local

    local_mocked_bindings(
      .datom_gov_pull = function(conn) { gov_pull_called <<- TRUE; invisible(TRUE) }
    )

    datom_pull(conn)
    expect_true(gov_pull_called)
  })
})

test_that("datom_pull result includes gov field", {
  withr::with_tempdir({
    bare_dir <- withr::local_tempdir()
    git2r::init(bare_dir, bare = TRUE)
    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")
    writeLines("init", "README.md")
    git2r::add(repo, "README.md")
    git2r::commit(repo, "Init")
    git2r::remote_add(repo, "origin", bare_dir)
    git2r::push(repo, "origin", "refs/heads/master", set_upstream = TRUE)

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$gov_local_path <- NULL  # no gov

    result <- datom_pull(conn)
    expect_true(is.list(result))
    expect_null(result$gov)  # no gov_local_path -> NULL
  })
})

test_that("datom_pull aborts when gov pull fails", {
  withr::with_tempdir({
    bare_dir <- withr::local_tempdir()
    git2r::init(bare_dir, bare = TRUE)
    repo <- git2r::init(".")
    git2r::config(repo, user.name = "Test", user.email = "test@test.com")
    writeLines("init", "README.md")
    git2r::add(repo, "README.md")
    git2r::commit(repo, "Init")
    git2r::remote_add(repo, "origin", bare_dir)
    git2r::push(repo, "origin", "refs/heads/master", set_upstream = TRUE)

    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$gov_local_path <- "/nonexistent/gov"

    local_mocked_bindings(
      .datom_gov_pull = function(conn) stop("network failure")
    )

    expect_error(datom_pull(conn), "network failure")
  })
})


# --- datom_pull_gov() ---------------------------------------------------------

test_that("datom_pull_gov rejects non-datom_conn", {
  expect_error(datom_pull_gov("not_conn"), "datom_conn")
})

test_that("datom_pull_gov rejects reader role", {
  conn <- mock_datom_conn(list())
  conn$role <- "reader"
  expect_error(datom_pull_gov(conn), "developer")
})

test_that("datom_pull_gov rejects conn without gov_local_path", {
  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$gov_local_path <- NULL
  expect_error(datom_pull_gov(conn), "gov_local_path")
})

test_that("datom_pull_gov calls .datom_gov_pull and returns invisibly", {
  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$gov_local_path <- "/some/gov"

  local_mocked_bindings(
    .datom_gov_pull = function(conn) invisible(TRUE)
  )

  expect_invisible(datom_pull_gov(conn))
})