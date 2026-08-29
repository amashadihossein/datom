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

# The fixtures in this block deliberately use REAL metadata field names. Field
# selection is an allowlist, so a fixture built from invented names
# (`name`, `author`, `x` -- all of which these tests once used) survives the
# assertion while asserting nothing: every invented field is dropped before
# hashing, leaving `data_sha` alone to carry a test about several fields.

test_that("metadata SHA is deterministic", {
  meta <- list(data_sha = "abc", table_type = "derived")
  sha1 <- .datom_compute_metadata_sha(meta)
  sha2 <- .datom_compute_metadata_sha(meta)
  expect_identical(sha1, sha2)
})

test_that("metadata SHA is order-independent", {
  meta1 <- list(table_type = "derived", data_sha = "abc", nrow = 3L)
  meta2 <- list(nrow = 3L, table_type = "derived", data_sha = "abc")
  sha1 <- .datom_compute_metadata_sha(meta1)
  sha2 <- .datom_compute_metadata_sha(meta2)
  expect_identical(sha1, sha2)

  # Non-vacuous: the shared fields really do all reach the hash, so the
  # invariance above is about ordering rather than about them being ignored.
  expect_false(identical(
    sha1, .datom_compute_metadata_sha(list(data_sha = "abc", nrow = 3L))
  ))
})

test_that("metadata SHA differs for different content", {
  meta1 <- list(data_sha = "abc", table_type = "derived")
  meta2 <- list(data_sha = "xyz", table_type = "derived")
  sha1 <- .datom_compute_metadata_sha(meta1)
  sha2 <- .datom_compute_metadata_sha(meta2)
  expect_false(sha1 == sha2)
})

test_that("metadata SHA is a 64-char hex string", {
  sha <- .datom_compute_metadata_sha(list(data_sha = "abc"))
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


# --- .datom_compute_original_file_sha() ------------------------------------------------

test_that("file SHA is deterministic", {
  tmp <- withr::local_tempfile(fileext = ".txt")
  writeLines("hello world", tmp)
  sha1 <- .datom_compute_original_file_sha(tmp)
  sha2 <- .datom_compute_original_file_sha(tmp)
  expect_identical(sha1, sha2)
})

test_that("file SHA differs for different content", {
  tmp1 <- withr::local_tempfile(fileext = ".txt")
  tmp2 <- withr::local_tempfile(fileext = ".txt")
  writeLines("hello", tmp1)
  writeLines("world", tmp2)
  sha1 <- .datom_compute_original_file_sha(tmp1)
  sha2 <- .datom_compute_original_file_sha(tmp2)
  expect_false(sha1 == sha2)
})

test_that("file SHA is a 64-char hex string", {
  tmp <- withr::local_tempfile(fileext = ".txt")
  writeLines("test", tmp)
  sha <- .datom_compute_original_file_sha(tmp)
  expect_match(sha, "^[0-9a-f]{64}$")
})

test_that("file SHA errors on missing file", {
  expect_error(.datom_compute_original_file_sha("/no/such/file.txt"), "File not found")
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
  # a negative NaN folds to the same encoding as a positive one
  expect_identical(sha(data.frame(x = c(1, -(0 / 0)))),
                   sha(data.frame(x = c(1, NaN))))
})

test_that("Property 4: NaN encodes to a host-independent canonical pattern", {
  # These are BYTE-level assertions on purpose. The hash-equality checks above
  # hold on any single machine even when the encoder emits the host's own NaN,
  # because both sides then emit the same wrong bytes -- so they cannot catch a
  # platform divergence. Only pinning the bytes can.
  #
  # R's `NaN` is 0x7ff8000000000000 on macOS/arm64 and 0xfff8000000000000 on
  # Linux/x86_64 (it comes from a C-level 0.0/0.0). The encoder therefore
  # splices the pinned pattern in rather than assigning `NaN`. Before that fix
  # the numeric golden below passed on macOS and failed on Linux in CI.
  canonical <- as.raw(c(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf8, 0x7f))
  expect_identical(.datom_nan_canonical, canonical)

  # Every flavour of NaN reaching the encoder emits exactly that pattern.
  expect_identical(
    .datom_encode_numeric(c(NaN, 0 / 0, -(0 / 0), Inf - Inf)),
    rep(canonical, 4L)
  )

  # NA_real_ keeps R's own NA payload (high word 0x7ff00000, low word 1954).
  # That pattern is fixed by R itself, not by the host FPU, so it is portable
  # and is deliberately NOT folded into the canonical NaN.
  expect_identical(
    .datom_encode_numeric(NA_real_),
    as.raw(c(0xa2, 0x07, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x7f))
  )

  # The splice must land in the right 8-byte slot and leave neighbours alone.
  mixed <- .datom_encode_numeric(c(1, NaN, 2))
  expect_length(mixed, 24L)
  expect_identical(mixed[9:16], canonical)
  expect_identical(mixed[1:8], .datom_encode_numeric(1))
  expect_identical(mixed[17:24], .datom_encode_numeric(2))
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

test_that("Feature: datom-cv1, Property 12: column index integrity", {
  df <- data.frame(
    id  = 1:4,
    age = c(10, 20, 30, 40),
    grp = factor(c("a", "b", "a", "b")),
    lab = c("w", "x", "y", "z"),
    stringsAsFactors = FALSE
  )
  res <- .datom_canonical_hash(df)

  # (a) the persisted column_hashes array is ordered to names(data)
  expect_identical(
    vapply(res$column_hashes, function(e) e$name, character(1)),
    names(df)
  )

  # (b) each entry's sha equals the standalone per-column digest
  for (e in res$column_hashes) {
    expect_identical(e$sha, .datom_col_digest(e$name, df[[e$name]]))
  }

  # (c) data_sha recomputes from the stored column_hashes + dims. Formula
  #     lifted verbatim from .datom_canonical_hash() so the test cannot drift.
  shas   <- vapply(res$column_hashes, function(e) e$sha, character(1))
  header <- c(charToRaw("datom-cv1"),
              writeBin(as.double(c(nrow(df), ncol(df))), raw(),
                       size = 8L, endian = "little"))
  recompute <- digest::digest(c(header, charToRaw(paste(shas, collapse = ""))),
                              algo = "sha256", serialize = FALSE)
  expect_identical(recompute, res$data_sha)

  # (d) changing exactly one column flips exactly that column's entry, leaving
  #     every other entry untouched.
  df2 <- df
  df2$age <- c(11, 20, 30, 40)
  res2 <- .datom_canonical_hash(df2)

  before <- vapply(res$column_hashes,  function(e) e$sha, character(1))
  after  <- vapply(res2$column_hashes, function(e) e$sha, character(1))
  changed <- which(before != after)
  expect_identical(changed, which(names(df) == "age"))
  expect_identical(before[-changed], after[-changed])
})

# --- .datom_compute_metadata_sha(): Feature: datom-cv1, Properties 13-14 ------

test_that("Feature: datom-cv1, Property 13: metadata_sha field ordering is locale-independent", {
  # A fixture whose collation order genuinely MOVES with the locale: the C
  # locale sorts by byte value ("_" = 0x5f and every uppercase letter precede
  # the lowercase ones), while en_US.UTF-8 uses dictionary order. Without a
  # discriminating fixture this property would pass vacuously, so the difference
  # is asserted before the invariance is.
  #
  # WHY THIS TARGETS `.datom_metadata_sha_from_fields()` AND NOT
  # `.datom_compute_metadata_sha()`. Field selection is an allowlist, so the
  # synthetic names below would be dropped before any sorting happened, leaving
  # one field and nothing to order -- the test would pass while asserting
  # nothing. Real field names cannot replace them either: all ten identity field
  # names sort identically under C and en_US.UTF-8 (checked), so no fixture built
  # from them can discriminate. Hence the split: selection is tested by the
  # goldens and the classification test, ordering is tested here.
  meta <- list(
    data_sha = "abc",
    Zeta = 1L,
    alpha = 2L,
    `_leading` = 3L,
    Beta = 4L,
    beta = 5L
  )

  locale_ok <- tryCatch(
    withr::with_collate(
      "en_US.UTF-8",
      identical(Sys.getlocale("LC_COLLATE"), "en_US.UTF-8")
    ),
    warning = function(w) FALSE,
    error = function(e) FALSE
  )
  skip_if_not(isTRUE(locale_ok),
              "en_US.UTF-8 collation unavailable on this platform.")

  order_c <- withr::with_collate("C", sort(names(meta)))
  order_us <- withr::with_collate("en_US.UTF-8", sort(names(meta)))
  expect_false(identical(order_c, order_us))

  # The hash does not move with the locale (Requirement 6.2).
  sha_c <- withr::with_collate("C", .datom_metadata_sha_from_fields(meta))
  sha_us <- withr::with_collate("en_US.UTF-8",
                                .datom_metadata_sha_from_fields(meta))
  expect_identical(sha_c, sha_us)

  # And it is the radix (byte-order) arrangement that is hashed, not either
  # locale's sort() -- recomputed here from the implementation's own recipe so a
  # future ordering change cannot pass this test silently.
  radix <- meta[sort(names(meta), method = "radix")]
  expect_identical(
    sha_c,
    digest::digest(jsonlite::toJSON(radix, auto_unbox = TRUE),
                   algo = "sha256", serialize = FALSE)
  )
  expect_false(identical(
    sha_c,
    digest::digest(jsonlite::toJSON(meta[order_us], auto_unbox = TRUE),
                   algo = "sha256", serialize = FALSE)
  ))
})

test_that("Feature: datom-cv1, Property 14: metadata_sha volatile-field membership", {
  base <- list(
    data_sha = "abc",
    hash_algo = "datom-cv1",
    table_type = "imported",
    nrow = 3L,
    ncol = 2L,
    original_file_sha = "f00"
  )
  reference <- .datom_compute_metadata_sha(base)

  # (a) Volatile fields never move the hash, whichever value they carry.
  #     `size_bytes` is in this set as a deliberate amendment to the written
  #     Requirement 7.1 list: it is the parquet file size, which drifts with the
  #     arrow version for identical logical content -- exactly the drift
  #     parquet_sha is excluded for.
  volatile_values <- list(
    created_at = list("2025-01-01T00:00:00Z", "2026-12-31T23:59:59Z"),
    datom_version = list("0.0.0.9000", "1.0.0"),
    parquet_sha = list("aaa", "bbb"),
    size_bytes = list(1024, 2048),
    column_hashes = list(
      list(list(name = "x", sha = "aaa")),
      list(list(name = "x", sha = "bbb"))
    )
  )
  for (field in names(volatile_values)) {
    for (value in volatile_values[[field]]) {
      variant <- base
      variant[[field]] <- value
      expect_identical(.datom_compute_metadata_sha(variant), reference,
                       info = field)
    }
  }

  # (b) Presence versus absence is also immaterial for a volatile field --
  #     Requirement 14.4, which is what lets datom_write() set parquet_sha after
  #     metadata_sha has already been computed.
  all_volatile <- base
  all_volatile$created_at <- "2025-01-01T00:00:00Z"
  all_volatile$datom_version <- "9.9.9"
  all_volatile$parquet_sha <- "ccc"
  all_volatile$size_bytes <- 4096
  all_volatile$column_hashes <- list(
    list(name = "id", sha = "aaa"),
    list(name = "v", sha = "bbb")
  )
  expect_identical(.datom_compute_metadata_sha(all_volatile), reference)

  # (c) Semantic fields DO move it: a new source file or a new algorithm is
  #     legitimately a new version (Requirement 7.4).
  for (field in c("original_file_sha", "hash_algo")) {
    changed <- base
    changed[[field]] <- "something-else"
    expect_false(identical(.datom_compute_metadata_sha(changed), reference),
                 info = field)

    dropped <- base
    dropped[[field]] <- NULL
    expect_false(identical(.datom_compute_metadata_sha(dropped), reference),
                 info = field)
  }
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

# The golden numeric fixture, shared by the golden-hash test and the byte pin
# below. Extreme magnitudes are built PARSE-EXACTLY -- powers of two and the
# IEEE-754 DBL_MAX / DBL_MIN constants -- never from decimal literals such as
# `1e300`. See the byte-pin test for why.
golden_numeric_values <- c(
  0, -0, 1, -1, 0.1, 1 / 3,
  2^999, -2^-999,
  .Machine$double.xmax, -.Machine$double.xmin,
  Inf, -Inf, NA, NaN
)

test_that("golden numeric vector is stable", {
  golden1 <- data.frame(x = golden_numeric_values)
  expect_identical(
    sha(golden1),
    "050d620ab1e57453b32da5d458994eb25e8c77bba6c0eb58893a7cea3960dec3"
  )
})

test_that("golden numeric fixture is parse-exact on every architecture", {
  # This pin is the diagnostic half of the golden above. A golden hash that
  # disagrees across platforms says only "something differs"; these bytes say
  # WHICH value differs, which is the difference between a five-minute fix and a
  # long bisect.
  #
  # History: the fixture used to contain `1e300` and `-1e-300` and the golden
  # hash disagreed between architectures -- x86_64 Linux and Windows agreed with
  # each other and disagreed with arm64 macOS. The encoder was not at fault. R's
  # `R_strtod` accumulates extreme-exponent decimal literals in a `long double`,
  # which is 80-bit extended on x86_64 (correctly rounded here) but only 64-bit
  # on Apple arm64, where `1e300` lands 4 ULP away. So the same source text
  # yields different doubles per architecture -- upstream of datom entirely, and
  # not fixable inside the hash. The fix is to build extreme magnitudes from
  # values every parser represents exactly.
  #
  # `0.1` stays: small-exponent decimals take R_strtod's exact fast path and are
  # byte-identical across architectures (verified on both).
  expected_payload <- c(
    "0000000000000000",  # 0
    "0000000000000000",  # -0  -> normalised to +0
    "000000000000f03f",  # 1
    "000000000000f0bf",  # -1
    "9a9999999999b93f",  # 0.1
    "555555555555d53f",  # 1/3
    "000000000000607e",  # 2^999
    "0000000000008081",  # -2^-999
    "ffffffffffffef7f",  # .Machine$double.xmax
    "0000000000001080",  # -.Machine$double.xmin
    "000000000000f07f",  # Inf
    "000000000000f0ff",  # -Inf
    "a20700000000f07f",  # NA_real_ (R's own payload: high 0x7ff00000, low 1954)
    "000000000000f87f"   # NaN -> pinned canonical 0x7ff8000000000000
  )

  actual <- .datom_encode_numeric(golden_numeric_values)
  per_slot <- vapply(
    seq_along(golden_numeric_values),
    function(i) paste(as.character(actual[((i - 1L) * 8L) + 1:8]), collapse = ""),
    character(1L)
  )
  expect_identical(per_slot, expected_payload)
})

test_that("text -> double conversion is not portable, but the goldens do not depend on it", {
  # Base R parses decimals with `R_strtod5()` (src/main/util.c), which
  # accumulates digits into an `LDOUBLE` accumulator and scales by a power of
  # ten. `LDOUBLE` is `long double` when the build has one, so the result
  # depends on the platform's long-double WIDTH -- not on its architecture:
  # x86_64 (80-bit) and aarch64-Linux/s390x (128-bit quad) agree with correct
  # rounding, while Apple-silicon macOS, 32-bit ARM, and any
  # --disable-long-double build (CRAN's noLD flavour) deviate. Linux and macOS
  # on the same arm64 chip land on opposite sides. This is accepted R behaviour;
  # `?NumericConstants` promises grammar, not correct rounding.
  #
  # Asserted here: only what is portable, plus the anchors that explain the
  # mechanism. Nothing asserts a specific parse of a decimal literal, because
  # that is exactly the thing that varies.

  # A literal and as.numeric() share the same parser, so they agree with each
  # other on any build -- that much IS portable.
  expect_identical(1e300, as.numeric("1e300"))
  expect_identical(1e-300, as.numeric("1e-300"))

  # The mechanism's boundary: 10^22 is the largest power of ten exactly
  # representable in a double, 10^23 the first that is not. On a build whose
  # LDOUBLE is only 53-bit this is where the second rounding enters, which is
  # why a bare `1e-23` is the first one-digit value to drift there. The
  # representability itself is an IEEE-754 fact and portable: 10^k is exact iff
  # 5^k < 2^53.
  expect_true(5^22 < 2^53)
  expect_false(5^23 < 2^53)

  # The goldens sidestep the parser entirely. Powers of two and the DBL_MAX /
  # DBL_MIN constants are bit-exact on every build:
  expect_identical(
    writeBin(2^999, raw(), size = 8L, endian = "little"),
    as.raw(c(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x60, 0x7e))
  )
  expect_identical(
    writeBin(.Machine$double.xmax, raw(), size = 8L, endian = "little"),
    as.raw(c(0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xef, 0x7f))
  )

  # C99 hex-float literals are the dependency-free escape hatch for an exact
  # decimal-looking constant: base-2 significand and a power-of-two exponent, so
  # no base-10 rounding happens anywhere. Documented in ?NumericConstants.
  expect_identical(0x1.999999999999ap-4, 0.1)
  expect_identical(
    writeBin(0x1.fcp+996, raw(), size = 8L, endian = "little"),
    as.raw(c(0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x3f, 0x7e))
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

test_that("metadata_sha golden is stable, and an unknown field does not move it", {
  # This fixture used to be pinned WITH its `name` key, at
  # 59f1f1d936c5d65472733a924493ce2362255d442ebea6d41f7c3c9e7069d326. `name` is
  # not a metadata field -- no builder emits it, and `metadata.json` is written
  # as exactly the object a builder produced -- so the old pin was a hash of a
  # document datom cannot write.
  #
  # Rather than retire the fixture, it is reused for the property that changed
  # its value: an unrecognised extra field is ignored, so a document carrying one
  # hashes identically to one without it. The pinned constant is the no-`name`
  # value, which is what this same fixture already produced before the allowlist.
  plain <- list(data_sha = "abc123", nrow = 100L, ncol = 5L,
                table_type = "imported", hash_algo = "datom-cv1")
  expect_identical(
    .datom_compute_metadata_sha(plain),
    "cce751b3f74d9f45c79ec96e4a19529580fec36b6ea37b39800b3a8a58e94ac8"
  )

  # A legacy unknown key (`name`) and a forward-looking one (a field a future
  # release might add) are both ignored, together and separately. The second case
  # is the one that matters: `name` is a historical accident, whereas an unknown
  # field arriving from a newer datom is the situation the allowlist exists for.
  with_name <- c(plain, list(name = "mytable"))
  with_future <- c(plain, list(some_future_field = "whatever"))
  with_both <- c(with_name, list(some_future_field = "whatever"))

  expect_identical(.datom_compute_metadata_sha(with_name),
                   .datom_compute_metadata_sha(plain))
  expect_identical(.datom_compute_metadata_sha(with_future),
                   .datom_compute_metadata_sha(plain))
  expect_identical(.datom_compute_metadata_sha(with_both),
                   .datom_compute_metadata_sha(plain))
})

# A metadata document built the way datom actually builds one: every top-level
# key comes from `.datom_build_metadata()`, plus `parquet_sha`, which
# `datom_write()` assigns after change detection rather than at build time. The
# `optional` switch selects the two shapes that matter -- every conditionally
# present field supplied, and none of them.
#
# WHY IT IS BUILDER-DERIVED RATHER THAN HAND-WRITTEN. The goldens below are the
# before/after anchor for a change to how `.datom_compute_metadata_sha()`
# SELECTS fields, so the fixture has to be a document datom can actually
# produce. The older `metadata_sha golden is stable` fixture above is not: it
# carries a `name` key that no builder emits and omits `colnames`, which every
# builder emits.
#
# `data_sha` and `column_hashes` are literals rather than a live
# `.datom_canonical_hash()` call, deliberately: a cv1 encoding drift would then
# redden the cv1 goldens only, so a failure here names one regime instead of two.
builder_metadata_fixture <- function(optional = TRUE) {
  df <- data.frame(id = 1:3, val = c("a", "b", "c"), stringsAsFactors = FALSE)

  args <- list(
    data = df,
    data_sha = "2eb1fa3e668dc15f6e5c2b384d2dbf39b216f12573c07c95543fa208dba4fef8",
    column_hashes = list(
      list(name = "id", sha = strrep("a", 64L)),
      list(name = "val", sha = strrep("b", 64L))
    )
  )

  if (optional) {
    args <- c(args, list(
      table_type = "imported",
      size_bytes = 4096,
      original_file_sha = "f00dcafe",
      parents = list(list(source = "STUDY_001", table = "dm",
                          version = "a1b2c3d4", data_sha = "e5f6a7b8")),
      source_lineage = list(list(project = "STUDY_001", table = "dm",
                                 version_sha = "e5f6a7b8")),
      custom = list(owner = "biostat", study = "STUDY_001")
    ))
  }

  meta <- do.call(.datom_build_metadata, args)
  meta$parquet_sha <- "deadbeef"
  meta
}

test_that("builder-derived metadata_sha goldens are stable", {
  # These two values are the evidence that a later change to field SELECTION is
  # behaviour-preserving: they are computed from documents datom writes, so if
  # either moves, some real artifact's recorded version moved with it.
  #
  # Both are reproducible run to run. The only fields that vary between two
  # builds of the same table are `created_at` and `datom_version`, and neither
  # participates in `metadata_sha`.
  expect_identical(
    .datom_compute_metadata_sha(builder_metadata_fixture(optional = TRUE)),
    "f4d88543b11b4918fe96e8ec319ae6d664693735a545508095aa4c4b44da9a02"
  )

  # The no-optional-fields shape is pinned separately because "a document
  # missing an optional field still hashes to its own established value" is a
  # distinct property from "a fully populated document does".
  expect_identical(
    .datom_compute_metadata_sha(builder_metadata_fixture(optional = FALSE)),
    "d0c1ea7510fe9da7361de62e21886f45dbca7b556e00765c3160222f24393fd7"
  )
})

test_that("the pinned fixtures carry exactly the keys datom's writers emit", {
  # Guards the goldens above against quietly ceasing to be realistic. Listed
  # explicitly rather than derived, because the point is to notice when the set
  # changes: a builder gaining a semantic field legitimately moves the pins, and
  # that must surface as a decision rather than as a mystery.
  always <- c("data_sha", "hash_algo", "parquet_sha", "table_type", "nrow",
              "ncol", "colnames", "column_hashes", "created_at",
              "datom_version")
  conditional <- c("original_file_sha", "parents", "source_lineage",
                   "size_bytes", "custom")

  expect_setequal(names(builder_metadata_fixture(optional = TRUE)),
                  c(always, conditional))
  expect_setequal(names(builder_metadata_fixture(optional = FALSE)), always)
})

test_that("every field a metadata builder emits is classified", {
  # THE FORCING FUNCTION for the allowlist's failure direction. An unclassified
  # field is silently excluded from identity, so identity quietly stops
  # responding to real content -- and no other test in the suite would notice.
  #
  # The inventory is DERIVED from what a builder emits, never hardcoded. That is
  # the whole value of this test: a hardcoded list of today's field names would
  # pass forever and would not notice the next release adding one. Written this
  # way, it fails the moment a builder gains a field, which forces the
  # classification decision at the point the field is introduced.
  emitted <- names(builder_metadata_fixture(optional = TRUE))
  classified <- c(.datom_metadata_identity_fields,
                  .datom_metadata_excluded_fields)

  # Whichever field name appears here is the one that needs a decision: into
  # .datom_metadata_identity_fields if it is content, into
  # .datom_metadata_excluded_fields if it is not.
  expect_identical(setdiff(emitted, classified), character(0))

  # The converse: nothing in the identity list is a field datom never writes.
  # This is what keeps that list readable as "the fields the builders emit", and
  # it is what rules out the tempting shortcut of allowlisting `name` to keep an
  # old golden byte-identical -- the list would then advertise a field that does
  # not exist.
  expect_identical(setdiff(.datom_metadata_identity_fields, emitted),
                   character(0))
})

test_that("a field is classified exactly once", {
  # A name in both lists would make its treatment depend on which list a reader
  # consulted, and both lists are documentation as much as code.
  expect_identical(
    intersect(.datom_metadata_identity_fields, .datom_metadata_excluded_fields),
    character(0)
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


test_that("metadata SHA ignores schema_version and document_sha (volatile)", {
  # Both are container facts, not content. If schema_version entered identity,
  # the v1 -> v2 bump would mint a new version for every artifact in every repo
  # while its content stood still -- the failure the volatile list exists for.
  # document_sha is the stored-bytes hash of a JSON payload, i.e. the set-side
  # analogue of parquet_sha, and drifts for the same reasons.
  base <- list(
    data_sha = "abc",
    hash_algo = "datom-cv1",
    table_type = "imported",
    nrow = 3L,
    ncol = 2L
  )
  reference <- .datom_compute_metadata_sha(base)

  variants <- list(
    schema_version = list(1L, 2L, 3L),
    document_sha = list("aaa", "bbb")
  )
  for (field in names(variants)) {
    for (value in variants[[field]]) {
      variant <- base
      variant[[field]] <- value
      expect_identical(.datom_compute_metadata_sha(variant), reference,
                       info = field)
    }
  }

  # Presence versus absence is immaterial too, which is what makes this task's
  # change inert for every metadata document already written.
  both <- base
  both$schema_version <- 2L
  both$document_sha <- "ccc"
  expect_identical(.datom_compute_metadata_sha(both), reference)
})
