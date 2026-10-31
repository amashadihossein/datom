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

# --- .datom_local_upload_absent ----------------------------------------------

# A store, a source file with known bytes, and the path the key lands at.
local_absent_fixture <- function(bytes = "new bytes", env = parent.frame()) {
  store_dir <- withr::local_tempdir(.local_envir = env)
  src <- fs::path(withr::local_tempdir(.local_envir = env), "data.parquet")
  writeBin(charToRaw(bytes), src)
  conn <- make_local_conn(store_dir, "proj")
  list(
    conn = conn,
    src = src,
    key = "dm/abc.parquet",
    dest = as.character(.datom_local_path(conn, "dm/abc.parquet"))
  )
}

store_bytes <- function(path, bytes) {
  fs::dir_create(fs::path_dir(path))
  writeBin(charToRaw(bytes), path)
}

read_bytes <- function(path) rawToChar(readBin(path, "raw", fs::file_size(path)))

# Every file in the key's folder, dotfiles included (`fs::dir_ls()` hides them
# by default, and the temporary name starts with a dot).
files_beside <- function(dest) {
  as.character(fs::path_file(fs::dir_ls(fs::path_dir(dest), all = TRUE)))
}

test_that(".datom_local_upload_absent() uploads to an absent key, leaving no temporary file", {
  f <- local_absent_fixture()

  expect_identical(.datom_local_upload_absent(f$conn, f$src, f$key), "uploaded")
  expect_identical(read_bytes(f$dest), "new bytes")
  expect_identical(files_beside(f$dest), "abc.parquet")
})

test_that(".datom_local_upload_absent() never replaces a stored file (P2)", {
  f <- local_absent_fixture()
  store_bytes(f$dest, "stored bytes")

  expect_identical(.datom_local_upload_absent(f$conn, f$src, f$key), "exists")
  expect_identical(read_bytes(f$dest), "stored bytes")
  expect_identical(files_beside(f$dest), "abc.parquet")
})

test_that(".datom_local_upload_absent() checks for a stored file before copying anything", {
  f <- local_absent_fixture()
  store_bytes(f$dest, "stored bytes")
  copy <- mockery::mock(NULL)
  mockery::stub(.datom_local_upload_absent, "fs::file_copy", copy)

  expect_identical(.datom_local_upload_absent(f$conn, f$src, f$key), "exists")
  mockery::expect_called(copy, 0)
})

test_that(".datom_local_upload_absent() leaves a file stored between its check and its link intact", {
  f <- local_absent_fixture()
  # Another writer stores the key after the existence check, just before the link.
  link_after_other_writer <- function(from, to) {
    store_bytes(to, "other writer")
    base::file.link(from, to)
  }
  mockery::stub(.datom_local_upload_absent, "file.link", link_after_other_writer)

  expect_identical(.datom_local_upload_absent(f$conn, f$src, f$key), "exists")
  expect_identical(read_bytes(f$dest), "other writer")
  expect_identical(files_beside(f$dest), "abc.parquet")
})

test_that(".datom_local_upload_absent() falls back to a move where hard links are unsupported", {
  f <- local_absent_fixture()
  mockery::stub(.datom_local_upload_absent, "file.link", function(from, to) FALSE)

  expect_identical(.datom_local_upload_absent(f$conn, f$src, f$key), "uploaded")
  expect_identical(read_bytes(f$dest), "new bytes")
  expect_identical(files_beside(f$dest), "abc.parquet")
})

test_that(".datom_local_upload_absent() leaves nothing at the key when the copy fails partway", {
  f <- local_absent_fixture()
  half_copy <- function(path, new_path, ...) {
    writeBin(charToRaw("new by"), new_path)
    stop("disk full")
  }
  mockery::stub(.datom_local_upload_absent, "fs::file_copy", half_copy)

  expect_error(.datom_local_upload_absent(f$conn, f$src, f$key), "disk full")
  expect_false(fs::file_exists(f$dest))
  expect_identical(files_beside(f$dest), character(0))
})

test_that(".datom_local_upload_absent() copies under a temporary name beside the key", {
  f <- local_absent_fixture()
  seen <- NULL
  record_link <- function(from, to) {
    seen <<- from
    base::file.link(from, to)
  }
  mockery::stub(.datom_local_upload_absent, "file.link", record_link)

  .datom_local_upload_absent(f$conn, f$src, f$key)

  expect_true(.datom_is_temp_key(seen))
  expect_identical(fs::path_dir(seen), fs::path_dir(f$dest))
})

test_that(".datom_local_upload_absent() errors on a missing source file", {
  f <- local_absent_fixture()

  expect_error(
    .datom_local_upload_absent(f$conn, "/nonexistent/file.parquet", f$key),
    "File not found"
  )
  expect_false(fs::file_exists(f$dest))
})

# --- .datom_is_temp_key -------------------------------------------------------

test_that(".datom_is_temp_key() recognises a local upload's temporary names only", {
  expect_identical(
    .datom_is_temp_key(c(
      "dm/.abc.parquet.1a2b3c.tmp",
      "proj/datom/dm/.abc.json.ff01.tmp",
      "dm/abc.parquet",
      "dm/abc.tmp",
      "proj/datom/.metadata/manifest.json",
      "dm/.metadata/metadata.json",
      ".metadata/manifest.json"
    )),
    c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE)
  )
  expect_identical(.datom_is_temp_key(character(0)), logical(0))
})

# --- .datom_local_object_sha256 -----------------------------------------------

test_that(".datom_local_object_sha256() hashes the stored file", {
  f <- local_absent_fixture()
  store_bytes(f$dest, "stored bytes")

  expect_identical(
    .datom_local_object_sha256(f$conn, f$key),
    digest::digest(charToRaw("stored bytes"), algo = "sha256", serialize = FALSE)
  )
})

test_that(".datom_local_object_sha256() errors on a missing file", {
  f <- local_absent_fixture()

  expect_error(.datom_local_object_sha256(f$conn, f$key), "File not found")
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

test_that(".datom_storage_upload_absent() dispatches to local backend", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  src <- fs::path(withr::local_tempdir(), "data.txt")
  writeLines("dispatch test", src)

  expect_identical(.datom_storage_upload_absent(conn, src, "t1/file.txt"), "uploaded")
  expect_identical(.datom_storage_upload_absent(conn, src, "t1/file.txt"), "exists")
})

test_that(".datom_storage_object_sha256() dispatches to local backend", {
  store_dir <- withr::local_tempdir()
  conn <- make_local_conn(store_dir, "proj")

  store_file <- fs::path(store_dir, "proj", "datom", "t1", "file.txt")
  fs::dir_create(fs::path_dir(store_file))
  writeLines("hash me", store_file)

  expect_identical(
    .datom_storage_object_sha256(conn, "t1/file.txt"),
    digest::digest(file = as.character(store_file), algo = "sha256")
  )
})
