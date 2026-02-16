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
