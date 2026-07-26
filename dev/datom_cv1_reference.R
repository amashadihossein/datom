# ==============================================================================
# datom-cv1 -- reference implementation + self-test (standalone)
# ==============================================================================
# Canonical content hash for tabular data ("data_sha"), per datom issue #72.
#
# Design properties this script embodies:
#   * NO I/O in the identity path: hashes in-memory values only. No parquet,
#     no CSV, no temp files.
#   * NO base-coercion helpers: columns are read directly via data[[i]] /
#     names(data); as.data.frame() is never called; data-frame-level
#     attributes and row names are never consulted.
#   * NO sorting: row and column order are significant (identity).
#   * Dependency surface: R language storage contracts (typeof, IEEE-754
#     double bits, writeBin, enc2utf8) + SHA-256 (frozen standard, pinned
#     below against the published NIST test vector).
#   * Only dependency: the `digest` package, used solely as
#     digest(raw_bytes, algo = "sha256", serialize = FALSE).
#
# Run:  Rscript datom_cv1_reference.R
# The self-test prints PASS/FAIL per property and a final summary. It also
# prints golden hash constants for fixed fixtures -- record these and re-run
# on other machines / R versions / OSes: they must never change. Any change
# means the spec was violated and requires a conscious bump to datom-cv2.
# ==============================================================================

# --- core ---------------------------------------------------------------------

.cv1_sha256 <- function(bytes) {
  digest::digest(bytes, algo = "sha256", serialize = FALSE)
}

# The canonical quiet NaN: IEEE-754 0x7ff8000000000000, little-endian. Pinned
# as BYTES, not taken from R's `NaN`, because R's NaN sign bit is host-dependent
# (0x7ff8... on macOS/arm64, 0xfff8... on Linux/x86_64 -- it comes from a
# C-level 0.0/0.0). Assigning `NaN` folds NaN payloads but inherits that sign
# bit, which made data_sha platform-dependent for any table containing a NaN.
.cv1_nan_canonical <- as.raw(c(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf8, 0x7f))

# Numeric payload: logical/integer/double unified as IEEE-754 doubles,
# little-endian. NaN folded to .cv1_nan_canonical; -0 -> +0; NA_real_ preserved
# (is.nan(NA_real_) is FALSE, so NA survives the NaN handling untouched -- its
# own bit pattern, high word 0x7ff00000 / low word 1954, is fixed by R and
# therefore portable).
.cv1_num_payload <- function(x) {
  x <- as.double(x)
  nan_idx <- which(is.nan(x))
  z <- which(x == 0)           # which() drops NAs -- do not use x[x == 0]
  x[z] <- 0
  out <- writeBin(x, raw(), size = 8L, endian = "little")
  if (length(nan_idx) > 0L) {  # element i owns out[(8i - 7):(8i)]
    out[rep((nan_idx - 1L) * 8L, each = 8L) + seq_len(8L)] <- .cv1_nan_canonical
  }
  out
}

# Character payload: 1-byte-per-row NA mask (disambiguates NA from ""),
# then NUL-terminated UTF-8 strings (R strings cannot contain NUL, so the
# terminator is unambiguous). No Unicode normalization (documented: NFC != NFD).
.cv1_chr_payload <- function(x) {
  x <- enc2utf8(as.character(x))
  na <- is.na(x)
  x[na] <- ""
  c(writeBin(as.integer(na), raw(), size = 1L),
    writeBin(x, raw()))
}

# Per-column digest: sha256( tag || utf8(name) || 0x00 || payload ).
# Dispatch order is part of the spec -- do not reorder.
.cv1_col_digest <- function(name, x) {
  if (inherits(x, "integer64")) {
    # bit64: int64 bit patterns stored in doubles. Copy bits verbatim --
    # NO NaN/zero canonicalization (NaN-space bit patterns are legitimate
    # large integers; touching them would corrupt values).
    tag <- "i64"
    payload <- writeBin(unclass(x), raw(), size = 8L, endian = "little")
  } else if (is.factor(x)) {
    # Levels and orderedness are not identity.
    tag <- "chr"
    payload <- .cv1_chr_payload(as.character(x))
  } else if (inherits(x, "Date")) {
    # Also catches data.table::IDate (class c("IDate","Date")).
    # as.double unifies integer-storage Dates.
    tag <- "date"
    payload <- .cv1_num_payload(unclass(x))
  } else if (inherits(x, "POSIXct")) {
    # Epoch seconds pin the instant; tzone (display metadata) is excluded.
    tag <- "time"
    payload <- .cv1_num_payload(unclass(x))
  } else if (inherits(x, "difftime")) {
    # Also catches hms::hms. Units string REQUIRED: payload is units-scaled,
    # omitting it would let 1 min collide with 1 sec (false collision).
    tag <- "drtn"
    payload <- c(.cv1_num_payload(unclass(x)), as.raw(0L),
                 charToRaw(enc2utf8(attr(x, "units"))))
  } else if (inherits(x, "ITime")) {
    # data.table::ITime: seconds-of-day as integer. Encoded as difftime-secs
    # so ITime and hms of the same clock times hash equal.
    tag <- "drtn"
    payload <- c(.cv1_num_payload(unclass(x)), as.raw(0L), charToRaw("secs"))
  } else if (inherits(x, c("haven_labelled", "labelled"))) {
    # haven/labelled (incl. labelled_spss): labels are metadata, not identity.
    y <- unclass(x)
    attributes(y) <- NULL
    return(.cv1_col_digest(name, y))
  } else if (!is.null(attr(x, "class"))) {
    # Unknown classed columns abort LOUDLY. Unknown classes can be
    # attribute-scaled (e.g. units: the number 1 could mean 1 mg or 1 kg);
    # hashing the bare payload would create false collisions. No silent fallback.
    stop(sprintf(
      "datom-cv1: column '%s' has unsupported class '%s'; convert to a supported type (POSIXlt -> as.POSIXct).",
      name, paste(class(x), collapse = "/")), call. = FALSE)
  } else if (is.logical(x) || is.integer(x) || is.double(x)) {
    tag <- "num"
    payload <- .cv1_num_payload(x)
  } else if (is.character(x)) {
    tag <- "chr"
    payload <- .cv1_chr_payload(x)
  } else {
    stop(sprintf(
      "datom-cv1: column '%s' has unsupported type '%s' (list/complex/raw columns are not supported).",
      name, typeof(x)), call. = FALSE)
  }
  .cv1_sha256(c(charToRaw(tag), charToRaw(enc2utf8(name)), as.raw(0L), payload))
}

# Final hash. Input must already BE a data.frame (tibbles pass is.data.frame);
# no coercion is performed -- columns are read directly.
datom_canonical_hash <- function(data) {
  if (!is.data.frame(data)) {
    stop("datom-cv1: `data` must be a data.frame.", call. = FALSE)
  }
  if (nrow(data) == 0L || ncol(data) == 0L) {
    stop("datom-cv1: `data` must have at least one row and one column.", call. = FALSE)
  }
  nms <- names(data)
  col_digests <- vapply(
    seq_along(data),
    function(i) .cv1_col_digest(nms[[i]], data[[i]]),
    character(1L)
  )
  header <- c(charToRaw("datom-cv1"),
              writeBin(as.double(c(nrow(data), ncol(data))), raw(),
                       size = 8L, endian = "little"))
  .cv1_sha256(c(header, charToRaw(paste(col_digests, collapse = ""))))
}

# ==============================================================================
# Self-test suite
# ==============================================================================

.results <- new.env(parent = emptyenv())
.results$pass <- 0L; .results$fail <- 0L

check <- function(label, ok) {
  ok <- isTRUE(ok)
  if (ok) .results$pass <- .results$pass + 1L else .results$fail <- .results$fail + 1L
  cat(sprintf("[%s] %s\n", if (ok) "PASS" else "FAIL", label))
  invisible(ok)
}

expect_error_msg <- function(expr, pattern) {
  err <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  !is.null(err) && grepl(pattern, err, fixed = FALSE)
}

h <- datom_canonical_hash

cat("== datom-cv1 self-test ==\n\n")

# --- 0. pin SHA-256 itself against the published NIST test vector -------------
check("NIST vector: sha256('abc') is correct (pins the digest package)",
      .cv1_sha256(charToRaw("abc")) ==
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

# --- 1. determinism ------------------------------------------------------------
df <- data.frame(x = 1:3, y = c("a", "b", "c"), stringsAsFactors = FALSE)
check("same input twice -> same hash", h(df) == h(df))

# --- 2. container class is not identity ----------------------------------------
fake_tbl <- df; class(fake_tbl) <- c("tbl_df", "tbl", "data.frame")
check("tibble-classed vs plain data.frame -> equal", h(df) == h(fake_tbl))
if (requireNamespace("tibble", quietly = TRUE)) {
  check("real tibble vs data.frame -> equal",
        h(df) == h(tibble::tibble(x = 1:3, y = c("a", "b", "c"))))
}

# --- 3. numeric type unification -----------------------------------------------
check("integer vs double of same numbers -> equal",
      h(data.frame(x = c(0L, 1L, NA))) == h(data.frame(x = c(0, 1, NA))))
check("logical vs 0/1 double -> equal",
      h(data.frame(x = c(FALSE, TRUE, NA))) == h(data.frame(x = c(0, 1, NA))))
check("number vs its string -> DIFFER",
      h(data.frame(x = 1)) != h(data.frame(x = "1")))

# --- 4. NA / NaN / zero canonicalization ----------------------------------------
check("NA_real_ vs NaN -> DIFFER",
      h(data.frame(x = c(1, NA))) != h(data.frame(x = c(1, NaN))))
check("computed NaN (0/0) vs literal NaN -> equal",
      h(data.frame(x = c(1, 0/0))) == h(data.frame(x = c(1, NaN))))
check("negative NaN vs positive NaN -> equal (sign bit folded)",
      h(data.frame(x = c(1, -(0/0)))) == h(data.frame(x = c(1, NaN))))
# The bytes emitted for a NaN must be the pinned canonical pattern on EVERY
# platform, not whatever R's NaN happens to be here. This is the assertion that
# makes the numeric golden portable; without it, macOS and Linux disagree.
check("NaN encodes as the pinned 0x7ff8000000000000, host-independent",
      identical(.cv1_num_payload(c(NaN, -(0/0), 0/0)),
                rep(.cv1_nan_canonical, 3L)))
check("NA_real_ keeps R's portable NA payload (high 0x7ff00000, low 1954)",
      identical(.cv1_num_payload(NA_real_),
                as.raw(c(0xa2, 0x07, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x7f))))
check("-0 vs +0 -> equal",
      h(data.frame(x = c(-0.0, 1))) == h(data.frame(x = c(0.0, 1))))
check("NA vs empty string -> DIFFER",
      h(data.frame(x = c("a", NA))) != h(data.frame(x = c("a", ""))))

# --- 5. names and order are identity (no sorting) -------------------------------
check("column rename -> DIFFER",
      h(data.frame(x = 1:3)) != h(data.frame(y = 1:3)))
check("column order -> DIFFER (order is identity)",
      h(data.frame(a = 1, b = 2)) != h(data.frame(b = 2, a = 1)))
check("row order -> DIFFER (order is identity)",
      h(data.frame(x = c(1, 2))) != h(data.frame(x = c(2, 1))))

# --- 6. dates / times ------------------------------------------------------------
d  <- as.Date("2026-01-02")
d_int <- structure(as.integer(unclass(d)), class = "Date")   # integer-storage Date
check("double-storage vs integer-storage Date -> equal",
      h(data.frame(x = d)) == h(data.frame(x = d_int)))

t_utc <- as.POSIXct("2026-01-02 03:04:05", tz = "UTC")
t_ny  <- t_utc; attr(t_ny, "tzone") <- "America/New_York"    # same instant
check("same instants, different tzone -> equal",
      h(data.frame(x = t_utc)) == h(data.frame(x = t_ny)))

check("difftime same values same units -> equal",
      h(data.frame(x = as.difftime(60, units = "secs"))) ==
        h(data.frame(x = as.difftime(60, units = "secs"))))
check("difftime 60 secs vs 1 min (same duration, different units) -> DIFFER (documented benign split)",
      h(data.frame(x = as.difftime(60, units = "secs"))) !=
        h(data.frame(x = as.difftime(1, units = "mins"))))

# --- 7. factor / labelled ---------------------------------------------------------
check("factor vs its character values -> equal",
      h(data.frame(x = factor(c("a", "b")))) == h(data.frame(x = c("a", "b"))))
lab <- structure(c(1, 2), class = c("haven_labelled", "vctrs_vctr", "double"),
                 label = "a label", labels = c(one = 1))
dlab <- data.frame(x = 1:2); dlab$x <- lab
check("haven_labelled-shaped vs bare numeric -> equal",
      h(dlab) == h(data.frame(x = c(1, 2))))

# --- 8. unicode (fixtures built via intToUtf8: pure-ASCII source, no escapes,
# --- immune to editor/browser re-normalization) -----------------------------------
s_nfc <- paste0("na", intToUtf8(0x00EF), "ve")          # precomposed: i-diaeresis
s_nfd <- paste0("nai", intToUtf8(0x0308), "ve")         # decomposed: i + combining diaeresis
jp    <- intToUtf8(c(0x65E5, 0x672C, 0x8A9E))           # CJK sample
check("NFC vs NFD -> DIFFER (documented limitation, benign direction)",
      h(data.frame(x = s_nfc)) != h(data.frame(x = s_nfd)))
check("non-ASCII string hashes deterministically",
      h(data.frame(x = jp)) == h(data.frame(x = jp)))

# --- 9. unsupported columns abort loudly -------------------------------------------
dl <- data.frame(x = 1:2); dl$x <- list(1, 2)
check("list column -> abort", expect_error_msg(h(dl), "unsupported type 'list'"))
du <- data.frame(x = 1:2); du$x <- structure(c(1, 2), class = "units")
check("unknown classed column -> abort naming the class",
      expect_error_msg(h(du), "unsupported class 'units'"))
dp <- data.frame(x = 1:2); dp$x <- as.POSIXlt(c("2026-01-01", "2026-01-02"), tz = "UTC")
check("POSIXlt column -> abort with as.POSIXct hint",
      expect_error_msg(h(dp), "POSIXlt|POSIXct"))

# --- 10. integer64 (optional) --------------------------------------------------------
if (requireNamespace("bit64", quietly = TRUE)) {
  i64 <- bit64::as.integer64("9218868437227407267")  # bits fall in double-NaN space
  di  <- data.frame(x = 1:1); di$x <- i64
  check("integer64 in NaN bit-space hashes deterministically (no corruption)",
        h(di) == h(di))
  dnum <- data.frame(x = 1); dsame <- data.frame(x = 1:1); dsame$x <- bit64::as.integer64(1)
  check("integer64 vs double (distinct tag) -> DIFFER",
        h(dsame) != h(dnum))
} else {
  cat("[skip] bit64 not installed -- integer64 checks skipped\n")
}

# --- golden constants: record these, re-run everywhere, they must never change -----
cat("\n== golden constants (portable across machines / R versions / OSes) ==\n")
# Extreme magnitudes are built PARSE-EXACTLY (powers of two and the DBL_MAX /
# DBL_MIN constants), never from decimal literals like 1e300. R's R_strtod
# accumulates extreme-exponent decimals in a long double; that is 80-bit
# extended on x86_64 (where the result comes out correctly rounded) but only
# 64-bit on Apple arm64, where `1e300` parses 4 ULP off. The encoder is exact on
# both -- it is the source text -> double conversion that is not portable, i.e.
# upstream of datom entirely. A fixture using 1e300 therefore hashed differently
# per architecture (caught by CI: x86 Linux/Windows agreed with each other and
# disagreed with arm64 macOS). Small-exponent decimals like 0.1 take the exact
# fast path and ARE portable, so they stay.
golden1 <- data.frame(x = c(
  0, -0, 1, -1, 0.1, 1/3,
  2^999, -2^-999,                                   # exact powers of two
  .Machine$double.xmax, -.Machine$double.xmin,      # IEEE-754 fixed constants
  Inf, -Inf, NA, NaN
))
cat("golden numeric :", h(golden1), "\n")
golden2 <- data.frame(
  n = c(1L, NA, 3L),
  s = c("a", NA, ""),
  f = factor(c("x", "y", "x")),
  d = as.Date(c("2026-01-01", NA, "2026-12-31")),
  t = as.POSIXct(c("2026-01-02 03:04:05", NA, "1999-12-31 23:59:59"), tz = "UTC"),
  stringsAsFactors = FALSE
)
cat("golden mixed   :", h(golden2), "\n")

cat(sprintf("\n== summary: %d passed, %d failed ==\n", .results$pass, .results$fail))
if (.results$fail > 0L) stop("datom-cv1 self-test FAILED", call. = FALSE)
