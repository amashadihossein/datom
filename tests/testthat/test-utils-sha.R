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

test_that("column reorder produces different SHA (order is significant)", {
  df1 <- data.frame(x = 1:3, y = 4:6)
  df2 <- data.frame(y = 4:6, x = 1:3)
  sha1 <- .datom_compute_data_sha(df1)
  sha2 <- .datom_compute_data_sha(df2)
  expect_false(sha1 == sha2)
})

test_that("row reorder produces different SHA (order is significant)", {
  df1 <- data.frame(x = c(1, 2, 3), y = c("a", "b", "c"))
  df2 <- data.frame(x = c(3, 1, 2), y = c("c", "a", "b"))
  sha1 <- .datom_compute_data_sha(df1)
  sha2 <- .datom_compute_data_sha(df2)
  expect_false(sha1 == sha2)
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

test_that("metadata SHA ignores parquet_sha (volatile: arrow-version byte drift)", {
  meta1 <- list(data_sha = "abc", parquet_sha = "aaa")
  meta2 <- list(data_sha = "abc", parquet_sha = "bbb")
  expect_identical(
    .datom_compute_metadata_sha(meta1),
    .datom_compute_metadata_sha(meta2)
  )
})

test_that("metadata SHA ignores column_hashes (volatile: derived from data_sha inputs)", {
  meta1 <- list(data_sha = "abc",
                column_hashes = list(list(name = "x", sha = "aaa")))
  meta2 <- list(data_sha = "abc",
                column_hashes = list(list(name = "x", sha = "bbb")))
  expect_identical(
    .datom_compute_metadata_sha(meta1),
    .datom_compute_metadata_sha(meta2)
  )
})

test_that("metadata SHA ignores size_bytes (volatile: arrow-version byte drift)", {
  meta1 <- list(data_sha = "abc", size_bytes = 1024)
  meta2 <- list(data_sha = "abc", size_bytes = 2048)
  expect_identical(
    .datom_compute_metadata_sha(meta1),
    .datom_compute_metadata_sha(meta2)
  )
})

test_that("metadata SHA includes hash_algo (semantic: a new algorithm is a new version)", {
  meta1 <- list(data_sha = "abc", hash_algo = "datom-cv1")
  meta2 <- list(data_sha = "abc", hash_algo = "datom-cv2")
  expect_false(
    .datom_compute_metadata_sha(meta1) == .datom_compute_metadata_sha(meta2)
  )
})

test_that("metadata SHA includes original_file_sha (semantic: a new source is a new version)", {
  meta1 <- list(data_sha = "abc", original_file_sha = "aaa")
  meta2 <- list(data_sha = "abc", original_file_sha = "bbb")
  expect_false(
    .datom_compute_metadata_sha(meta1) == .datom_compute_metadata_sha(meta2)
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


# --- .datom_validate_parents() ------------------------------------------------

# Helper: a well-formed parent entry (lean, no source_lineage).
.valid_parent_entry <- function(...) {
  utils::modifyList(
    list(
      source = "study001",
      table = "dm",
      version = "v_dm_9f3",
      data_sha = "d_dm_aaa"
    ),
    list(...)
  )
}

test_that("NULL parents is valid", {
  expect_true(.datom_validate_parents(NULL))
  expect_invisible(.datom_validate_parents(NULL))
})

test_that("well-formed list of entries passes (invisible TRUE)", {
  parents <- list(
    .valid_parent_entry(),
    .valid_parent_entry(source = "labdata", table = "ex", version = "v_ex_7c1",
                        data_sha = "d_ex_bbb")
  )
  expect_true(.datom_validate_parents(parents))
  expect_invisible(.datom_validate_parents(parents))
})

test_that("empty list is valid", {
  expect_true(.datom_validate_parents(list()))
})

test_that("named list is rejected as not a list of entry lists", {
  named <- list(a = .valid_parent_entry())
  expect_error(.datom_validate_parents(named), "list of entry lists")
})

test_that("non-list input is rejected", {
  expect_error(.datom_validate_parents("nope"), "list of entry lists")
})

test_that("entry missing a field is rejected naming index and field", {
  bad <- .valid_parent_entry()
  bad$data_sha <- NULL
  expect_error(
    .datom_validate_parents(list(.valid_parent_entry(), bad)),
    "Entry 2"
  )
  expect_error(
    .datom_validate_parents(list(.valid_parent_entry(), bad)),
    "data_sha"
  )
})

test_that("entry with an empty-string field is rejected", {
  bad <- .valid_parent_entry(version = "")
  expect_error(.datom_validate_parents(list(bad)), "Entry 1")
  expect_error(.datom_validate_parents(list(bad)), "version")
})

test_that("entry with a non-string field is rejected", {
  bad <- .valid_parent_entry(data_sha = 123)
  expect_error(.datom_validate_parents(list(bad)), "non-empty string")
})

test_that("entry with a multi-element field is rejected", {
  bad <- .valid_parent_entry(source = c("a", "b"))
  expect_error(.datom_validate_parents(list(bad)), "non-empty string")
})

test_that("non-list entry is rejected naming its index", {
  expect_error(
    .datom_validate_parents(list(.valid_parent_entry(), "nope")),
    "Entry 2"
  )
})

test_that("entry with a valid non-empty source_lineage passes", {
  entry <- .valid_parent_entry(
    source_lineage = list(
      list(project = "study001", table = "dm", version_sha = "d_dm_aaa")
    )
  )
  expect_true(.datom_validate_parents(list(entry)))
})

test_that("NULL source_lineage on an entry is accepted", {
  entry <- .valid_parent_entry(source_lineage = NULL)
  expect_true(.datom_validate_parents(list(entry)))
})

test_that("empty source_lineage on an entry is accepted", {
  entry <- .valid_parent_entry(source_lineage = list())
  expect_true(.datom_validate_parents(list(entry)))
})

test_that("malformed source_lineage on an entry is rejected", {
  entry <- .valid_parent_entry(
    source_lineage = list(
      list(project = "study001", table = "dm")  # missing version_sha
    )
  )
  expect_error(.datom_validate_parents(list(entry)), "source_lineage")
})


# ==============================================================================
# datom-cv1 canonical hash engine
# ==============================================================================

# Build a single-column data frame preserving the column's class/attributes
# ($<- keeps them; data.frame(col = ...) can mangle classed vectors).
one_col <- function(x) {
  d <- data.frame(x = seq_along(unclass(x)))
  d$x <- x
  d
}

sha <- function(d) .datom_compute_data_sha(d)

# --- .datom_encode_numeric(): Feature: datom-cv1, Property 4 ------------------

test_that("Property 4: numeric encoding semantics", {
  # 0/0 (computed NaN) canonicalizes to the same as a literal NaN
  expect_identical(sha(data.frame(x = c(1, 0 / 0))), sha(data.frame(x = c(1, NaN))))
  # -0.0 and +0.0 encode equal
  expect_identical(sha(data.frame(x = c(-0.0, 1))), sha(data.frame(x = c(0.0, 1))))
  # NA_real_ is distinct from NaN
  expect_false(sha(data.frame(x = c(1, NA_real_))) == sha(data.frame(x = c(1, NaN))))
  # no rounding: a one-ULP difference changes the hash
  expect_false(sha(data.frame(x = 1.0)) == sha(data.frame(x = 1.0 + .Machine$double.eps)))
})

# --- .datom_encode_character(): Feature: datom-cv1, Property 5 ----------------

test_that("Property 5: character encoding semantics", {
  # NA and "" are distinguishable
  expect_false(
    sha(data.frame(x = c("a", NA), stringsAsFactors = FALSE)) ==
      sha(data.frame(x = c("a", ""), stringsAsFactors = FALSE))
  )
  # NFC vs NFD differ (no Unicode normalization); fixtures built via intToUtf8
  nfc <- intToUtf8(0x00EF)                 # i-diaeresis, composed
  nfd <- intToUtf8(c(0x0069, 0x0308))      # i + combining diaeresis, decomposed
  expect_false(
    sha(data.frame(x = nfc, stringsAsFactors = FALSE)) ==
      sha(data.frame(x = nfd, stringsAsFactors = FALSE))
  )
  # CJK string hashes deterministically
  cjk <- intToUtf8(c(0x4E2D, 0x6587))
  expect_identical(
    sha(data.frame(x = cjk, stringsAsFactors = FALSE)),
    sha(data.frame(x = cjk, stringsAsFactors = FALSE))
  )
})

# --- .datom_canonical_hash(): Feature: datom-cv1, Properties 1-3, 6-10 --------

test_that("Property 1: container class and attributes are not identity", {
  df <- data.frame(x = 1:3, y = c("a", "b", "c"), stringsAsFactors = FALSE)
  fake_tbl <- df; class(fake_tbl) <- c("tbl_df", "tbl", "data.frame")
  expect_identical(sha(df), sha(fake_tbl))
  grp <- df; class(grp) <- c("grouped_df", "tbl_df", "tbl", "data.frame")
  expect_identical(sha(df), sha(grp))
  rn <- df; rownames(rn) <- c("r1", "r2", "r3")
  expect_identical(sha(df), sha(rn))
})

test_that("Property 2: determinism", {
  df <- data.frame(x = 1:3, y = c("a", "b", "c"), stringsAsFactors = FALSE)
  expect_identical(sha(df), sha(df))
})

test_that("Property 3: type-tag disambiguation", {
  # "1" (character) vs 1 (numeric) differ
  expect_false(
    sha(data.frame(x = 1)) ==
      sha(data.frame(x = "1", stringsAsFactors = FALSE))
  )
  # all-NA logical vs all-NA character differ (tag distinguishes them)
  expect_false(
    sha(data.frame(x = c(NA, NA))) ==
      sha(data.frame(x = c(NA_character_, NA_character_), stringsAsFactors = FALSE))
  )
})

test_that("Property 6: integer64 verbatim encoding (distinct tag)", {
  # faked integer64 (structure-only) exercises the i64 branch identically
  i64 <- one_col(structure(c(1, 2), class = "integer64"))
  dbl <- data.frame(x = c(1, 2))
  expect_identical(sha(i64), sha(i64))          # deterministic
  expect_false(sha(i64) == sha(dbl))            # distinct tag from double
})

test_that("Property 7: factor levels and orderedness are not identity", {
  f1 <- factor(c("a", "b"))
  f2 <- factor(c("a", "b"), levels = c("a", "b", "c"))  # extra unused level
  f3 <- factor(c("a", "b"), ordered = TRUE)             # ordered
  expect_identical(sha(one_col(f1)), sha(one_col(f2)))
  expect_identical(sha(one_col(f1)), sha(one_col(f3)))
})

test_that("Property 8: temporal encoding semantics", {
  # POSIXct: same instants, different tzone -> equal
  t_utc <- as.POSIXct("2026-01-02 03:04:05", tz = "UTC")
  t_ny <- t_utc; attr(t_ny, "tzone") <- "America/New_York"
  expect_identical(sha(one_col(t_utc)), sha(one_col(t_ny)))
  # difftime: same payload, different units (secs vs mins) -> differ
  expect_false(
    sha(one_col(as.difftime(60, units = "secs"))) ==
      sha(one_col(as.difftime(1, units = "mins")))
  )
  # ITime and hms of the same clock times -> equal (faked by class string)
  hms_f <- structure(3661, class = c("hms", "difftime"), units = "secs")
  itime_f <- structure(3661L, class = "ITime")
  expect_identical(sha(one_col(hms_f)), sha(one_col(itime_f)))
})

test_that("Property 9: labelled columns strip to their base type", {
  bare <- c(1, 2)
  lab <- structure(c(1, 2), class = "haven_labelled",
                   labels = c(a = 1), label = "a label")
  expect_identical(sha(one_col(bare)), sha(one_col(lab)))
})

test_that("Property 10: row and column order are significant", {
  expect_false(sha(data.frame(a = 1, b = 2)) == sha(data.frame(b = 2, a = 1)))
  expect_false(sha(data.frame(x = c(1, 2))) == sha(data.frame(x = c(2, 1))))
})

test_that(".datom_canonical_hash guards reject bad input", {
  expect_error(.datom_canonical_hash(list(x = 1)), "data frame")
  expect_error(.datom_canonical_hash("not a df"), "data frame")
  expect_error(.datom_canonical_hash(data.frame()), "at least one row")
  expect_error(.datom_canonical_hash(data.frame(x = integer(0))), "at least one row")
})

test_that(".datom_canonical_hash returns data_sha and an ordered column index", {
  df <- data.frame(x = 1:3, y = c("a", "b", "c"), stringsAsFactors = FALSE)
  res <- .datom_canonical_hash(df)
  expect_named(res, c("data_sha", "column_hashes"))
  expect_match(res$data_sha, "^[0-9a-f]{64}$")
  expect_identical(
    vapply(res$column_hashes, function(e) e$name, character(1)),
    names(df)
  )
  # data_sha recomputes from the column index + dims
  col_hex <- vapply(res$column_hashes, function(e) e$sha, character(1))
  header <- c(charToRaw("datom-cv1"),
              writeBin(as.double(c(nrow(df), ncol(df))), raw(),
                       size = 8L, endian = "little"))
  recompute <- digest::digest(c(header, charToRaw(paste(col_hex, collapse = ""))),
                              algo = "sha256", serialize = FALSE)
  expect_identical(recompute, res$data_sha)
})

# --- Golden vectors and reference parity (Feature: datom-cv1) -----------------
# Golden hex constants were computed on the reference platform (R 4.5.2) and are
# a CI drift tripwire: any platform / endianness / dependency-version change
# that alters identity breaks one of these immediately.

test_that("NIST SHA-256 vector pins the digest package", {
  expect_identical(
    digest::digest(charToRaw("abc"), algo = "sha256", serialize = FALSE),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  )
})

test_that("golden numeric vector is stable", {
  golden1 <- data.frame(
    x = c(0, -0, 1, -1, 0.1, 1/3, 1e300, -1e-300, Inf, -Inf, NA, NaN)
  )
  expect_identical(
    sha(golden1),
    "48b4c0cb79ac1a47d5b2e3bd4811995de2c183e544224027703785d785fa89a1"
  )
})

test_that("golden mixed data frame is stable", {
  golden2 <- data.frame(
    n = c(1L, NA, 3L),
    s = c("a", NA, ""),
    f = factor(c("x", "y", "x")),
    d = as.Date(c("2026-01-01", NA, "2026-12-31")),
    t = as.POSIXct(c("2026-01-02 03:04:05", NA, "1999-12-31 23:59:59"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  expect_identical(
    sha(golden2),
    "47c94f30e2214c7917cfca976960a475825afd710dd12e6cb003cff82fb41db2"
  )
})

test_that("golden single-kind vectors are stable", {
  expect_identical(
    sha(data.frame(x = c("a", NA, "", "z"), stringsAsFactors = FALSE)),
    "15ceda31e3f254bd4b7d1afa2150150dff971bb0c5943bb6fd3d90d4a9bd8c7c"
  )
  expect_identical(
    sha(data.frame(x = factor(c("x", "y", "x")))),
    "6abf705c3eb90ba047825cdad70d71f849d4ebdd5c90dc70de5bba408ba57d19"
  )
  expect_identical(
    sha(data.frame(x = as.Date(c("2026-01-01", NA, "2026-12-31")))),
    "2ce0b61a4f6474d237c3256d3e612117dfcc53e5cc67971e25ddabfe4d80c72f"
  )
  expect_identical(
    sha(one_col(as.POSIXct(c("2026-01-02 03:04:05", NA), tz = "UTC"))),
    "831c7afaa61d61d6f02880aa320e8320dd09cec0957f85ab4a523da113db030f"
  )
  expect_identical(
    sha(one_col(as.difftime(c(60, 120), units = "secs"))),
    "c1715086d34ee59c646b85d33ae3b79c022963f342f12f2b32109b7637c6917c"
  )
  expect_identical(
    sha(one_col(structure(c(1, 2), class = "integer64"))),
    "7cfcb4881940449f9472226dc4ae4d8beb10bae3e0027b795b083901d16626a4"
  )
})

test_that("golden relations: parity, tzone equality, units split, hms==ITime", {
  # integer / logical / double parity
  expect_identical(sha(data.frame(x = c(0L, 1L, NA))), sha(data.frame(x = c(0, 1, NA))))
  expect_identical(sha(data.frame(x = c(FALSE, TRUE, NA))), sha(data.frame(x = c(0, 1, NA))))
  # double-storage vs integer-storage Date
  d_dbl <- as.Date("2026-01-02")
  d_int <- structure(as.integer(unclass(d_dbl)), class = "Date")
  expect_identical(sha(one_col(d_dbl)), sha(one_col(d_int)))
})

test_that("metadata_sha golden is stable", {
  meta <- list(data_sha = "abc123", name = "mytable", nrow = 100L, ncol = 5L,
               table_type = "imported", hash_algo = "datom-cv1")
  expect_identical(
    .datom_compute_metadata_sha(meta),
    "59f1f1d936c5d65472733a924493ce2362255d442ebea6d41f7c3c9e7069d326"
  )
})

test_that("Property 11: package hash matches the standalone reference", {
  candidates <- c(
    file.path("dev", "datom_cv1_reference.R"),
    testthat::test_path("..", "..", "dev", "datom_cv1_reference.R"),
    testthat::test_path("dev", "datom_cv1_reference.R")
  )
  hit <- candidates[file.exists(candidates)]
  skip_if(length(hit) == 0, "reference script absent (e.g. CRAN, dev/ Rbuildignored)")
  ref_env <- new.env()
  invisible(utils::capture.output(
    suppressMessages(sys.source(hit[[1]], envir = ref_env))
  ))
  ref <- ref_env$datom_canonical_hash

  fixtures <- list(
    data.frame(x = 1:3, y = c("a", "b", "c"), stringsAsFactors = FALSE),
    data.frame(x = c(0, -0, 1, NA, NaN, 0 / 0)),
    data.frame(x = c("a", NA, ""), stringsAsFactors = FALSE),
    data.frame(x = factor(c("x", "y", "x"))),
    data.frame(x = as.Date(c("2026-01-01", NA))),
    one_col(as.POSIXct(c("2026-01-02 03:04:05", NA), tz = "UTC")),
    one_col(as.difftime(c(60, 120), units = "secs")),
    one_col(structure(c(1, 2), class = "integer64")),
    data.frame(x = intToUtf8(c(0x4E2D, 0x6587)), stringsAsFactors = FALSE)
  )
  for (fx in fixtures) {
    expect_identical(.datom_compute_data_sha(fx), ref(fx))
  }
})
