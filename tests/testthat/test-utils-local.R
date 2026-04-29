# Tests for local filesystem backend functions (R/utils-local.R)
# Phase 12, Chunk 2

# --- Helper: create a mock local conn ----------------------------------------

make_local_conn <- function(root, prefix = "proj") {
  structure(
    list(
      backend = "local",
      root = as.character(root),
      prefix = prefix,
      client = NULL
    ),
    class = "datom_conn"
  )
}

# --- .datom_local_path --------------------------------------------------------

test_that(".datom_local_path() builds correct full path", {
  conn <- make_local_conn("/store", "proj")
  result <- .datom_local_path(conn, "table1/abc.parquet")

  expect_equal(
    as.character(result),
    as.character(fs::path("/store", "proj", "datom", "table1", "abc.parquet"))
  )
})

test_that(".datom_local_path() works with NULL prefix", {
  conn <- make_local_conn("/store", NULL)
  result <- .datom_local_path(conn, "table1/abc.parquet")

  expect_equal(
    as.character(result),
    as.character(fs::path("/store", "datom", "table1", "abc.parquet"))
  )
})

# --- .datom_local_upload ------------------------------------------------------

test_that(".datom_local_upload() copies file to store", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  # Create a source file
  src <- fs::path(withr::local_tempdir(), "data.parquet")
  writeLines("fake parquet data", src)

  result <- .datom_local_upload(conn, src, "table1/abc.parquet")

  expect_true(result)
  dest <- fs::path(store_dir, "proj", "datom", "table1", "abc.parquet")
  expect_true(fs::file_exists(dest))
  expect_equal(readLines(dest), "fake parquet data")
})

test_that(".datom_local_upload() overwrites existing file", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  src1 <- fs::path(withr::local_tempdir(), "v1.txt")
  writeLines("version 1", src1)
  .datom_local_upload(conn, src1, "table1/data.txt")

  src2 <- fs::path(withr::local_tempdir(), "v2.txt")
  writeLines("version 2", src2)
  .datom_local_upload(conn, src2, "table1/data.txt")

  dest <- fs::path(store_dir, "proj", "datom", "table1", "data.txt")
  expect_equal(readLines(dest), "version 2")
})

test_that(".datom_local_upload() errors on missing source file", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  expect_error(
    .datom_local_upload(conn, "/nonexistent/file.txt", "key"),
    "File not found"
  )
})

# --- .datom_local_download ----------------------------------------------------

test_that(".datom_local_download() copies file from store", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  # Seed a file in the store
  store_file <- fs::path(store_dir, "proj", "datom", "table1", "abc.parquet")
  fs::dir_create(fs::path_dir(store_file))
  writeLines("stored data", store_file)

  dest <- fs::path(withr::local_tempdir(), "downloaded.parquet")
  result <- .datom_local_download(conn, "table1/abc.parquet", dest)

  expect_true(result)
  expect_true(fs::file_exists(dest))
  expect_equal(readLines(dest), "stored data")
})

test_that(".datom_local_download() creates parent dirs", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  store_file <- fs::path(store_dir, "proj", "datom", "table1", "abc.parquet")
  fs::dir_create(fs::path_dir(store_file))
  writeLines("data", store_file)

  dest <- fs::path(withr::local_tempdir(), "deep", "nested", "file.parquet")
  .datom_local_download(conn, "table1/abc.parquet", dest)

  expect_true(fs::file_exists(dest))
})

test_that(".datom_local_download() errors on missing store file", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  expect_error(
    .datom_local_download(conn, "nonexistent/file.txt", "/tmp/dest.txt"),
    "File not found"
  )
})

# --- .datom_local_exists ------------------------------------------------------

test_that(".datom_local_exists() returns TRUE for existing file", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  store_file <- fs::path(store_dir, "proj", "datom", "table1", "abc.parquet")
  fs::dir_create(fs::path_dir(store_file))
  writeLines("data", store_file)

  expect_true(.datom_local_exists(conn, "table1/abc.parquet"))
})

test_that(".datom_local_exists() returns FALSE for missing file", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  expect_false(.datom_local_exists(conn, "nonexistent/file.txt"))
})

# --- .datom_local_read_json ---------------------------------------------------

test_that(".datom_local_read_json() reads and parses JSON", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  store_file <- fs::path(store_dir, "proj", "datom", "meta", "info.json")
  fs::dir_create(fs::path_dir(store_file))
  writeLines('{"name": "test", "version": 1}', store_file)

  result <- .datom_local_read_json(conn, "meta/info.json")

  expect_type(result, "list")
  expect_equal(result$name, "test")
  expect_equal(result$version, 1)
})

test_that(".datom_local_read_json() errors on missing file", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  expect_error(
    .datom_local_read_json(conn, "nonexistent.json"),
    "not found"
  )
})

test_that(".datom_local_read_json() errors on invalid JSON", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  store_file <- fs::path(store_dir, "proj", "datom", "bad.json")
  fs::dir_create(fs::path_dir(store_file))
  writeLines("not valid json {{{", store_file)

  expect_error(
    .datom_local_read_json(conn, "bad.json"),
    "parse"
  )
})

# --- .datom_local_write_json --------------------------------------------------

test_that(".datom_local_write_json() writes valid JSON", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  data <- list(name = "test", values = list(1, 2, 3))
  result <- .datom_local_write_json(conn, "meta/info.json", data)

  expect_true(result)

  dest <- fs::path(store_dir, "proj", "datom", "meta", "info.json")
  expect_true(fs::file_exists(dest))

  parsed <- jsonlite::fromJSON(dest, simplifyVector = FALSE)
  expect_equal(parsed$name, "test")
  expect_length(parsed$values, 3)
})

test_that(".datom_local_write_json() round-trips with read_json", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  original <- list(a = "hello", b = 42, c = list(nested = TRUE))
  .datom_local_write_json(conn, "test.json", original)
  result <- .datom_local_read_json(conn, "test.json")

  expect_equal(result$a, original$a)
  expect_equal(result$b, original$b)
  expect_equal(result$c$nested, original$c$nested)
})

# --- .datom_local_list_objects ------------------------------------------------

test_that(".datom_local_list_objects() lists files under prefix", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  # Create some files
  base <- fs::path(store_dir, "proj", "datom", "table1")
  fs::dir_create(base)
  writeLines("a", fs::path(base, "abc.parquet"))
  writeLines("b", fs::path(base, "def.parquet"))
  fs::dir_create(fs::path(base, ".metadata"))
  writeLines("{}", fs::path(base, ".metadata", "meta.json"))

  result <- .datom_local_list_objects(conn, "table1")
  expect_length(result, 3)
  expect_true(any(grepl("abc.parquet", result)))
  expect_true(any(grepl("def.parquet", result)))
  expect_true(any(grepl("meta.json", result)))
})

test_that(".datom_local_list_objects() returns empty for missing dir", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  result <- .datom_local_list_objects(conn, "nonexistent")
  expect_length(result, 0)
  expect_type(result, "character")
})

# --- .datom_local_delete ------------------------------------------------------

test_that(".datom_local_delete() removes existing file", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  store_file <- fs::path(store_dir, "proj", "datom", "table1", "abc.parquet")
  fs::dir_create(fs::path_dir(store_file))
  writeLines("data", store_file)
  expect_true(fs::file_exists(store_file))

  result <- .datom_local_delete(conn, "table1/abc.parquet")

  expect_true(result)
  expect_false(fs::file_exists(store_file))
})

test_that(".datom_local_delete() is silent for missing file", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  # Should not error
  result <- .datom_local_delete(conn, "nonexistent/file.txt")
  expect_true(result)
})

# --- .datom_local_delete_prefix ----------------------------------------------

test_that(".datom_local_delete_prefix() handles NULL prefix on conn", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, NULL)

  # No datom dir yet -> no-op
  expect_equal(.datom_local_delete_prefix(conn, NULL), 0L)

  fs::dir_create(fs::path(store_dir, "datom", "t1"))
  writeLines("x", fs::path(store_dir, "datom", "t1", "f.parquet"))

  expect_equal(.datom_local_delete_prefix(conn, NULL), 1L)
  expect_false(fs::dir_exists(fs::path(store_dir, "datom")))
})

test_that(".datom_local_delete_prefix() handles NA prefix on conn (defensive)", {
  # Regression: yaml/json round-trip can yield NA where NULL was expected;
  # nzchar(NA) returns NA and breaks the if-guard with
  # "missing value where TRUE/FALSE needed".
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, NA_character_)

  expect_equal(.datom_local_delete_prefix(conn, NULL), 0L)

  fs::dir_create(fs::path(store_dir, "datom", "t1"))
  writeLines("x", fs::path(store_dir, "datom", "t1", "f.parquet"))

  expect_equal(.datom_local_delete_prefix(conn, NULL), 1L)
  expect_false(fs::dir_exists(fs::path(store_dir, "datom")))
})

test_that(".datom_local_delete_prefix() honors non-NULL prefix on conn", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  fs::dir_create(fs::path(store_dir, "proj", "datom", "t1"))
  writeLines("x", fs::path(store_dir, "proj", "datom", "t1", "f.parquet"))

  expect_equal(.datom_local_delete_prefix(conn, NULL), 1L)
  expect_false(fs::dir_exists(fs::path(store_dir, "proj", "datom")))
})

# ==============================================================================
# Dispatch tests: .datom_storage_*() → .datom_local_*() (Chunk 3)
# ==============================================================================

test_that(".datom_storage_upload() dispatches to local backend", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  src <- fs::path(withr::local_tempdir(), "data.txt")
  writeLines("dispatch test", src)

  .datom_storage_upload(conn, src, "t1/file.txt")

  dest <- fs::path(store_dir, "proj", "datom", "t1", "file.txt")
  expect_true(fs::file_exists(dest))
  expect_equal(readLines(dest), "dispatch test")
})

test_that(".datom_storage_download() dispatches to local backend", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  store_file <- fs::path(store_dir, "proj", "datom", "t1", "file.txt")
  fs::dir_create(fs::path_dir(store_file))
  writeLines("download test", store_file)

  dest <- fs::path(withr::local_tempdir(), "out.txt")
  .datom_storage_download(conn, "t1/file.txt", dest)

  expect_equal(readLines(dest), "download test")
})

test_that(".datom_storage_exists() dispatches to local backend", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  expect_false(.datom_storage_exists(conn, "nope.txt"))

  store_file <- fs::path(store_dir, "proj", "datom", "yes.txt")
  fs::dir_create(fs::path_dir(store_file))
  writeLines("hi", store_file)

  expect_true(.datom_storage_exists(conn, "yes.txt"))
})

test_that(".datom_storage_read_json() dispatches to local backend", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  store_file <- fs::path(store_dir, "proj", "datom", "info.json")
  fs::dir_create(fs::path_dir(store_file))
  writeLines('{"key": "value"}', store_file)

  result <- .datom_storage_read_json(conn, "info.json")
  expect_equal(result$key, "value")
})

test_that(".datom_storage_write_json() dispatches to local backend", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  .datom_storage_write_json(conn, "out.json", list(a = 1))

  dest <- fs::path(store_dir, "proj", "datom", "out.json")
  expect_true(fs::file_exists(dest))
  parsed <- jsonlite::fromJSON(dest)
  expect_equal(parsed$a, 1)
})
