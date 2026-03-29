# Tests for SHA computation utilities
# Phase 1, Chunk 1

# --- .datom_compute_data_sha() ------------------------------------------------

test_that("data SHA is deterministic for same data", {
  df <- data.frame(x = 1:5, y = letters[1:5])
  sha1 <- .datom_compute_data_sha(df)
  sha2 <- .datom_compute_data_sha(df)
  expect_identical(sha1, sha2)
})

test_that("data SHA differs for different data", {
  df1 <- data.frame(x = 1:5, y = letters[1:5])
  df2 <- data.frame(x = 1:5, y = letters[6:10])
  sha1 <- .datom_compute_data_sha(df1)
  sha2 <- .datom_compute_data_sha(df2)
  expect_false(sha1 == sha2)
})

test_that("data SHA is a 64-char hex string (SHA-256)", {
  df <- data.frame(x = 1:3)
  sha <- .datom_compute_data_sha(df)
  expect_type(sha, "character")
  expect_match(sha, "^[0-9a-f]{64}$")
})

test_that("column reorder produces different SHA by default", {
  df1 <- data.frame(x = 1:3, y = 4:6)
  df2 <- data.frame(y = 4:6, x = 1:3)
  sha1 <- .datom_compute_data_sha(df1)
  sha2 <- .datom_compute_data_sha(df2)
  expect_false(sha1 == sha2)
})

test_that("column reorder produces same SHA with sort_columns = TRUE", {
  df1 <- data.frame(x = 1:3, y = 4:6)
  df2 <- data.frame(y = 4:6, x = 1:3)
  sha1 <- .datom_compute_data_sha(df1, sort_columns = TRUE)
  sha2 <- .datom_compute_data_sha(df2, sort_columns = TRUE)
  expect_identical(sha1, sha2)
})

test_that("row reorder produces different SHA by default", {
  df1 <- data.frame(x = c(1, 2, 3), y = c("a", "b", "c"))
  df2 <- data.frame(x = c(3, 1, 2), y = c("c", "a", "b"))
  sha1 <- .datom_compute_data_sha(df1)
  sha2 <- .datom_compute_data_sha(df2)
  expect_false(sha1 == sha2)
})

test_that("row reorder produces same SHA with sort_rows = TRUE", {
  df1 <- data.frame(x = c(1, 2, 3), y = c("a", "b", "c"))
  df2 <- data.frame(x = c(3, 1, 2), y = c("c", "a", "b"))
  sha1 <- .datom_compute_data_sha(df1, sort_rows = TRUE)
  sha2 <- .datom_compute_data_sha(df2, sort_rows = TRUE)
  expect_identical(sha1, sha2)
})

test_that("data SHA rejects non-data-frame input", {
  expect_error(.datom_compute_data_sha(list(x = 1)), "data frame")
  expect_error(.datom_compute_data_sha("not a df"), "data frame")
})

test_that("data SHA rejects empty data frame", {
  expect_error(.datom_compute_data_sha(data.frame()), "at least one row")
  expect_error(.datom_compute_data_sha(data.frame(x = integer(0))), "at least one row")
})

test_that("data SHA cleans up temp files", {
  tmp_before <- list.files(tempdir(), pattern = "\\.parquet$")
  .datom_compute_data_sha(data.frame(x = 1:3))
  tmp_after <- list.files(tempdir(), pattern = "\\.parquet$")
  expect_equal(length(tmp_after), length(tmp_before))
})


# --- .datom_compute_metadata_sha() --------------------------------------------

test_that("metadata SHA is deterministic", {
  meta <- list(data_sha = "abc", name = "test")
  sha1 <- .datom_compute_metadata_sha(meta)
  sha2 <- .datom_compute_metadata_sha(meta)
  expect_identical(sha1, sha2)
})

test_that("metadata SHA is order-independent", {
  meta1 <- list(name = "test", data_sha = "abc", author = "me")
  meta2 <- list(author = "me", name = "test", data_sha = "abc")
  sha1 <- .datom_compute_metadata_sha(meta1)
  sha2 <- .datom_compute_metadata_sha(meta2)
  expect_identical(sha1, sha2)
})

test_that("metadata SHA differs for different content", {
  meta1 <- list(data_sha = "abc", name = "test")
  meta2 <- list(data_sha = "xyz", name = "test")
  sha1 <- .datom_compute_metadata_sha(meta1)
  sha2 <- .datom_compute_metadata_sha(meta2)
  expect_false(sha1 == sha2)
})

test_that("metadata SHA is a 64-char hex string", {
  sha <- .datom_compute_metadata_sha(list(x = 1))
  expect_match(sha, "^[0-9a-f]{64}$")
})

test_that("metadata SHA ignores created_at (volatile field)", {
  meta1 <- list(data_sha = "abc", created_at = "2025-01-01T00:00:00Z")
  meta2 <- list(data_sha = "abc", created_at = "2026-12-31T23:59:59Z")
  expect_identical(
    .datom_compute_metadata_sha(meta1),
    .datom_compute_metadata_sha(meta2)
  )
})

test_that("metadata SHA ignores datom_version (volatile field)", {
  meta1 <- list(data_sha = "abc", datom_version = "0.0.0.9000")
  meta2 <- list(data_sha = "abc", datom_version = "1.0.0")
  expect_identical(
    .datom_compute_metadata_sha(meta1),
    .datom_compute_metadata_sha(meta2)
  )
})

test_that("metadata SHA still differs for different semantic content", {
  meta1 <- list(data_sha = "abc", nrow = 10L, created_at = "2025-01-01T00:00:00Z")
  meta2 <- list(data_sha = "abc", nrow = 20L, created_at = "2025-01-01T00:00:00Z")
  expect_false(
    .datom_compute_metadata_sha(meta1) == .datom_compute_metadata_sha(meta2)
  )
})

test_that("metadata SHA is stable across JSON round-trip", {
  meta_in_memory <- list(
    data_sha = "abc123",
    nrow = 10L,
    ncol = 3L,
    colnames = c("a", "b", "c"),
    table_type = "derived",
    parents = list(list(source = "S1", table = "dm", version = "v1")),
    size_bytes = 1024,
    created_at = "2025-01-01T00:00:00Z",
    datom_version = "0.0.0.9000"
  )

  # Simulate JSON round-trip (as happens when reading from S3)
  json <- jsonlite::toJSON(meta_in_memory, auto_unbox = TRUE)
  meta_roundtripped <- jsonlite::fromJSON(as.character(json),
                                          simplifyVector = FALSE)

  expect_identical(
    .datom_compute_metadata_sha(meta_in_memory),
    .datom_compute_metadata_sha(meta_roundtripped)
  )
})

test_that("metadata SHA rejects unnamed list", {
  expect_error(.datom_compute_metadata_sha(list(1, 2)), "named list")
})

test_that("metadata SHA rejects non-list", {
  expect_error(.datom_compute_metadata_sha("string"), "named list")
})


# --- .datom_compute_file_sha() ------------------------------------------------

test_that("file SHA is deterministic", {
  tmp <- withr::local_tempfile(fileext = ".txt")
  writeLines("hello world", tmp)
  sha1 <- .datom_compute_file_sha(tmp)
  sha2 <- .datom_compute_file_sha(tmp)
  expect_identical(sha1, sha2)
})

test_that("file SHA differs for different content", {
  tmp1 <- withr::local_tempfile(fileext = ".txt")
  tmp2 <- withr::local_tempfile(fileext = ".txt")
  writeLines("hello", tmp1)
  writeLines("world", tmp2)
  sha1 <- .datom_compute_file_sha(tmp1)
  sha2 <- .datom_compute_file_sha(tmp2)
  expect_false(sha1 == sha2)
})

test_that("file SHA is a 64-char hex string", {
  tmp <- withr::local_tempfile(fileext = ".txt")
  writeLines("test", tmp)
  sha <- .datom_compute_file_sha(tmp)
  expect_match(sha, "^[0-9a-f]{64}$")
})

test_that("file SHA errors on missing file", {
  expect_error(.datom_compute_file_sha("/no/such/file.txt"), "File not found")
})


# --- .datom_abbreviate_sha() ---------------------------------------------------

test_that("abbreviates SHA to 8 characters by default", {
  sha <- "a793e733037c6d3152f22063a5e7f7be0fb27cfc0e9bf5b0c841a05997774e0f"
  expect_equal(.datom_abbreviate_sha(sha), "a793e733")
})

test_that("abbreviates to custom length", {
  sha <- "a793e733037c6d3152f22063a5e7f7be0fb27cfc0e9bf5b0c841a05997774e0f"
  expect_equal(.datom_abbreviate_sha(sha, n = 12), "a793e733037c")
})

test_that("handles NA values", {
  result <- .datom_abbreviate_sha(c("abcdef1234567890", NA_character_))
  expect_equal(result, c("abcdef12", NA_character_))
})

test_that("handles vector input", {
  shas <- c(
    "a793e733037c6d3152f22063a5e7f7be0fb27cfc0e9bf5b0c841a05997774e0f",
    "2320b970ae25b8393e2b421ecfe4fa0b9218f3de69cda83db4a22d002657aed7"
  )
  result <- .datom_abbreviate_sha(shas)
  expect_equal(result, c("a793e733", "2320b970"))
})

test_that("passes through non-character input unchanged", {
  expect_equal(.datom_abbreviate_sha(42), 42)
  expect_null(.datom_abbreviate_sha(NULL))
})

test_that("handles short strings gracefully", {
  expect_equal(.datom_abbreviate_sha("abc"), "abc")
})
