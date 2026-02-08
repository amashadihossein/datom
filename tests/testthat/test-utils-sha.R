# Tests for SHA computation utilities
# Phase 1, Chunk 1

# --- .tbit_compute_data_sha() ------------------------------------------------

test_that("data SHA is deterministic for same data", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  sha1 <- .tbit_compute_data_sha(df)
  sha2 <- .tbit_compute_data_sha(df)
  expect_identical(sha1, sha2)
})

test_that("data SHA differs for different data", {
  df1 <- data.frame(x = 1:5, y = letters[1:5])
  df2 <- data.frame(x = 1:5, y = letters[6:10])
  sha1 <- .tbit_compute_data_sha(df1)
  sha2 <- .tbit_compute_data_sha(df2)
  expect_false(sha1 == sha2)
})

test_that("data SHA is a 64-char hex string (SHA-256)", {
  df <- data.frame(x = 1:3)
  sha <- .tbit_compute_data_sha(df)
  expect_type(sha, "character")
  expect_match(sha, "^[0-9a-f]{64}$")
})

test_that("column reorder produces different SHA by default", {
  df1 <- data.frame(x = 1:3, y = 4:6)
  df2 <- data.frame(y = 4:6, x = 1:3)
  sha1 <- .tbit_compute_data_sha(df1)
  sha2 <- .tbit_compute_data_sha(df2)
  expect_false(sha1 == sha2)
})

test_that("column reorder produces same SHA with sort_columns = TRUE", {
  df1 <- data.frame(x = 1:3, y = 4:6)
  df2 <- data.frame(y = 4:6, x = 1:3)
  sha1 <- .tbit_compute_data_sha(df1, sort_columns = TRUE)
  sha2 <- .tbit_compute_data_sha(df2, sort_columns = TRUE)
  expect_identical(sha1, sha2)
})

test_that("row reorder produces different SHA by default", {
  df1 <- data.frame(x = c(1, 2, 3), y = c("a", "b", "c"))
  df2 <- data.frame(x = c(3, 1, 2), y = c("c", "a", "b"))
  sha1 <- .tbit_compute_data_sha(df1)
  sha2 <- .tbit_compute_data_sha(df2)
  expect_false(sha1 == sha2)
})

test_that("row reorder produces same SHA with sort_rows = TRUE", {
  df1 <- data.frame(x = c(1, 2, 3), y = c("a", "b", "c"))
  df2 <- data.frame(x = c(3, 1, 2), y = c("c", "a", "b"))
  sha1 <- .tbit_compute_data_sha(df1, sort_rows = TRUE)
  sha2 <- .tbit_compute_data_sha(df2, sort_rows = TRUE)
  expect_identical(sha1, sha2)
})

test_that("data SHA rejects non-data-frame input", {
  expect_error(.tbit_compute_data_sha(list(x = 1)), "data frame")
  expect_error(.tbit_compute_data_sha("not a df"), "data frame")
})

test_that("data SHA rejects empty data frame", {
  expect_error(.tbit_compute_data_sha(data.frame()), "at least one row")
  expect_error(.tbit_compute_data_sha(data.frame(x = integer(0))), "at least one row")
})

test_that("data SHA cleans up temp files", {
  tmp_before <- list.files(tempdir(), pattern = "\\.parquet$")
  .tbit_compute_data_sha(data.frame(x = 1:3))
  tmp_after <- list.files(tempdir(), pattern = "\\.parquet$")
  expect_equal(length(tmp_after), length(tmp_before))
})


# --- .tbit_compute_metadata_sha() --------------------------------------------

test_that("metadata SHA is deterministic", {
  meta <- list(data_sha = "abc", name = "test")
  sha1 <- .tbit_compute_metadata_sha(meta)
  sha2 <- .tbit_compute_metadata_sha(meta)
  expect_identical(sha1, sha2)
})

test_that("metadata SHA is order-independent", {
  meta1 <- list(name = "test", data_sha = "abc", author = "me")
  meta2 <- list(author = "me", name = "test", data_sha = "abc")
  sha1 <- .tbit_compute_metadata_sha(meta1)
  sha2 <- .tbit_compute_metadata_sha(meta2)
  expect_identical(sha1, sha2)
})

test_that("metadata SHA differs for different content", {
  meta1 <- list(data_sha = "abc", name = "test")
  meta2 <- list(data_sha = "xyz", name = "test")
  sha1 <- .tbit_compute_metadata_sha(meta1)
  sha2 <- .tbit_compute_metadata_sha(meta2)
  expect_false(sha1 == sha2)
})

test_that("metadata SHA is a 64-char hex string", {
  sha <- .tbit_compute_metadata_sha(list(x = 1))
  expect_match(sha, "^[0-9a-f]{64}$")
})

test_that("metadata SHA rejects unnamed list", {
  expect_error(.tbit_compute_metadata_sha(list(1, 2)), "named list")
})

test_that("metadata SHA rejects non-list", {
  expect_error(.tbit_compute_metadata_sha("string"), "named list")
})


# --- .tbit_compute_file_sha() ------------------------------------------------

test_that("file SHA is deterministic", {
  tmp <- withr::local_tempfile(fileext = ".txt")
  writeLines("hello world", tmp)
  sha1 <- .tbit_compute_file_sha(tmp)
  sha2 <- .tbit_compute_file_sha(tmp)
  expect_identical(sha1, sha2)
})

test_that("file SHA differs for different content", {
  tmp1 <- withr::local_tempfile(fileext = ".txt")
  tmp2 <- withr::local_tempfile(fileext = ".txt")
  writeLines("hello", tmp1)
  writeLines("world", tmp2)
  sha1 <- .tbit_compute_file_sha(tmp1)
  sha2 <- .tbit_compute_file_sha(tmp2)
  expect_false(sha1 == sha2)
})

test_that("file SHA is a 64-char hex string", {
  tmp <- withr::local_tempfile(fileext = ".txt")
  writeLines("test", tmp)
  sha <- .tbit_compute_file_sha(tmp)
  expect_match(sha, "^[0-9a-f]{64}$")
})

test_that("file SHA errors on missing file", {
  expect_error(.tbit_compute_file_sha("/no/such/file.txt"), "File not found")
})
