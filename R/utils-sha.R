# Internal helpers for SHA computation, metadata operations, and lineage validation


#' Validate source_lineage Field Structure
#'
#' Checks that `source_lineage` is either NULL or a list of entries each
#' containing non-empty string fields `project`, `table`, and `version_sha`.
#' Extra fields are allowed (pass-through). Aborts with a cli error pointing
#' to the first invalid entry.
#'
#' @param x Value to validate.
#' @return Invisibly TRUE if valid.
#' @keywords internal
.datom_validate_source_lineage <- function(x) {
  if (is.null(x)) return(invisible(TRUE))

  if (!is.list(x) || (length(x) > 0L && !is.null(names(x)))) {
    cli::cli_abort(
      "{.arg source_lineage} must be a list of entry lists, not a named list."
    )
  }

  required_fields <- c("project", "table", "version_sha")

  for (i in seq_along(x)) {
    entry <- x[[i]]
    if (!is.list(entry)) {
      cli::cli_abort(
        "Entry {i} of {.arg source_lineage} must be a list, not {.cls {class(entry)}}."
      )
    }
    missing <- setdiff(required_fields, names(entry))
    if (length(missing) > 0L) {
      cli::cli_abort(
        "Entry {i} of {.arg source_lineage} is missing required field{?s}: {.val {missing}}."
      )
    }
    for (field in required_fields) {
      val <- entry[[field]]
      if (!is.character(val) || length(val) != 1L || !nzchar(val)) {
        cli::cli_abort(
          "Entry {i} of {.arg source_lineage}: field {.field {field}} must be a non-empty string."
        )
      }
    }
  }

  invisible(TRUE)
}


#' Validate parents Field Structure
#'
#' Checks that `parents` is either NULL or a list of entries each
#' containing non-empty string fields `source`, `table`, `version`, and
#' `data_sha`. WHERE an entry carries a non-NULL, non-empty
#' `source_lineage` field, it is validated via
#' `.datom_validate_source_lineage()`. Aborts with a cli error pointing to
#' the first invalid entry.
#'
#' @param x Value to validate.
#' @return Invisibly TRUE if valid.
#' @keywords internal
.datom_validate_parents <- function(x) {
  if (is.null(x)) return(invisible(TRUE))

  # Parents are meant to come from datom_parent(); every failure points there
  # as the remedy, so a raw list lacking data_sha gets a friendly message in
  # the same single validation pass.
  remedy <- paste0(
    "Declare parents with {.fn datom_parent} so each carries a ",
    "resolved {.field data_sha}."
  )

  if (!is.list(x) || (length(x) > 0L && !is.null(names(x)))) {
    cli::cli_abort(c(
      "{.arg parents} must be a list of entry lists, not a named list.",
      "i" = remedy
    ))
  }

  required_fields <- c("source", "table", "version", "data_sha")

  for (i in seq_along(x)) {
    entry <- x[[i]]
    if (!is.list(entry)) {
      cli::cli_abort(c(
        paste0("Entry {i} of {.arg parents} must be a list, not ",
               "{.cls {class(entry)}}."),
        "i" = remedy
      ))
    }
    missing <- setdiff(required_fields, names(entry))
    if (length(missing) > 0L) {
      cli::cli_abort(c(
        paste0("Entry {i} of {.arg parents} is missing ",
               "required field{?s}: {.val {missing}}."),
        "i" = remedy
      ))
    }
    for (field in required_fields) {
      val <- entry[[field]]
      if (!is.character(val) || length(val) != 1L || !nzchar(val)) {
        cli::cli_abort(c(
          paste0("Entry {i} of {.arg parents}: field ",
                 "{.field {field}} must be a non-empty string."),
          "i" = remedy
        ))
      }
    }
    lineage <- entry$source_lineage
    if (!is.null(lineage) && length(lineage) > 0L) {
      .datom_validate_source_lineage(lineage)
    }
  }

  invisible(TRUE)
}


# Internal helpers for SHA computation and metadata operations


#' Encode a Numeric Payload for Canonical Hashing
#'
#' The single shared numeric encoder used by the `num`, `date`, `time`, and
#' `drtn` column kinds of `datom-cv1`. Produces a fixed, platform-independent
#' byte sequence: IEEE-754 doubles written little-endian regardless of host
#' endianness, with three canonicalizations so that logically-equal values
#' encode identically:
#'
#' * Every `NaN` payload (e.g. `0/0`, a signalling NaN, a negative NaN) is
#'   folded to R's single canonical quiet `NaN` bit pattern.
#' * `-0.0` is converted to `+0.0`.
#' * `NA_real_` is preserved as its own distinct bit pattern -- it is a
#'   specific `NaN` payload in R and is deliberately *not* folded into the
#'   canonical `NaN`, so `NA_real_` and `NaN` encode differently.
#'
#' No rounding is applied: doubles are encoded bit-exact.
#'
#' @param x A vector coercible to double (logical, integer, double, or the
#'   numeric payload of a Date/POSIXct/difftime column).
#' @return A raw vector of `8 * length(x)` bytes.
#' @keywords internal
.datom_encode_numeric <- function(x) {
  d <- as.double(x)

  # Fold every true NaN (is.nan() is FALSE for NA_real_) to R's canonical
  # quiet NaN, so distinct NaN payloads hash equal while NA_real_ stays
  # distinct.
  nan_idx <- which(is.nan(d))
  if (length(nan_idx) > 0L) d[nan_idx] <- NaN

  # Normalise negative zero to positive zero. `d == 0` is TRUE for both -0
  # and +0 and NA for NA/NaN, so which() drops the missing entries.
  zero_idx <- which(d == 0)
  if (length(zero_idx) > 0L) d[zero_idx] <- 0

  writeBin(d, raw(), size = 8L, endian = "little")
}


#' Encode a Character Payload for Canonical Hashing
#'
#' The character encoder for the `chr` column kind (character and factor
#' columns). Emits a one-byte-per-row NA mask (`0x01` where `is.na()`,
#' `0x00` otherwise) followed by each value re-encoded to UTF-8 via
#' `enc2utf8()` and NUL-terminated. The leading mask makes `NA` and the
#' empty string `""` distinguishable (both have an empty value section, but
#' `NA` sets its mask byte). No Unicode normalization is applied, so NFC and
#' NFD forms of the same text encode differently (a documented, benign
#' limitation).
#'
#' @param x A vector coercible to character (character or factor).
#' @return A raw vector: `length(x)` mask bytes followed by the
#'   NUL-terminated UTF-8 value bytes.
#' @keywords internal
.datom_encode_character <- function(x) {
  x <- as.character(x)
  na <- is.na(x)

  mask <- as.raw(ifelse(na, 1L, 0L))

  # NA values contribute an empty value section (just their NUL terminator);
  # the mask byte is what distinguishes them from "".
  vals <- x
  vals[na] <- ""
  vals <- enc2utf8(vals)

  # writeBin() on a character vector writes each element as a C string: its
  # bytes followed by a terminating NUL. Since vals is UTF-8, these are the
  # UTF-8 bytes.
  c(mask, writeBin(vals, raw()))
}


#' Compute a Single Column's datom-cv1 Digest
#'
#' Encodes one column to its per-column SHA-256 hex digest for `datom-cv1`,
#' as `sha256( utf8(tag) || utf8(colname) || 0x00 || payload )`. The tag is
#' the kind returned by [.datom_column_kind()] and the payload is produced by
#' the shared encoders. Labelled columns strip their class and attributes and
#' re-dispatch on the bare underlying vector, so value labels never enter
#' identity.
#'
#' @param name Column name (used verbatim, UTF-8, in the digest input).
#' @param x The column vector.
#' @return A 64-character SHA-256 hex string.
#' @keywords internal
.datom_col_digest <- function(name, x) {
  # Labelled columns strip class + attributes and re-dispatch on the bare
  # underlying vector (labels are metadata, not identity).
  if (inherits(x, c("haven_labelled", "labelled", "labelled_spss"))) {
    stripped <- x
    attributes(stripped) <- NULL
    return(.datom_col_digest(name, stripped))
  }

  kind <- .datom_column_kind(x)
  if (is.null(kind)) {
    # Unreachable: the all-offenders pre-scan in .datom_canonical_hash() has
    # already rejected any column .datom_column_kind() cannot classify.
    cli::cli_abort(
      "Column {.field {name}} reached the encoder unclassified.",
      .internal = TRUE
    )
  }

  payload <- switch(
    kind,
    i64  = writeBin(unclass(x), raw(), size = 8L, endian = "little"),
    chr  = .datom_encode_character(x),
    date = .datom_encode_numeric(unclass(x)),
    time = .datom_encode_numeric(unclass(x)),
    drtn = {
      # difftime carries its units attr; ITime is seconds-of-day, encoded as
      # difftime-secs so ITime and hms of the same clock times hash equal.
      units <- if (inherits(x, "ITime")) "secs" else attr(x, "units")
      c(.datom_encode_numeric(unclass(x)), as.raw(0L),
        charToRaw(enc2utf8(units)))
    },
    num  = .datom_encode_numeric(x)
  )

  digest::digest(
    c(charToRaw(kind), charToRaw(enc2utf8(name)), as.raw(0L), payload),
    algo = "sha256", serialize = FALSE
  )
}


#' Compute the datom-cv1 Canonical Content Hash
#'
#' The I/O-free identity engine for `datom-cv1`. Computes `data_sha` from the
#' in-memory logical values only -- no parquet write, no CSV, no temp files,
#' no `as.data.frame()` or coercion, and never invokes arrow. Columns are read
#' via `data[[i]]` / `names(data)` and dimensions via `nrow()` / `ncol()`, so
#' two frames with equal values hash identically regardless of container class
#' (tibble vs data.frame vs grouped_df), row names, or arrow version.
#'
#' Before encoding, every column is scanned through [.datom_hash_recourse()];
#' if any are unsupported the function aborts **once**, listing every offender
#' with its class and canonical recourse. This fires during `data_sha`
#' computation (step 1 of [datom_write()]), before any git or storage
#' mutation, so a refusal leaves no partial state.
#'
#' The final hash is
#' `sha256( "datom-cv1" || f64le(nrow) || f64le(ncol) || concat(col_digest_hex...) )`.
#'
#' @param data A data frame with at least one row and one column.
#' @return A list with `data_sha` (character) and `column_hashes` (an ordered
#'   list of `list(name, sha)` in column order, computed once and reused for
#'   both `data_sha` and the persisted column index).
#' @keywords internal
.datom_canonical_hash <- function(data) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame.")
  }
  if (nrow(data) == 0L || ncol(data) == 0L) {
    cli::cli_abort("{.arg data} must have at least one row and one column.")
  }

  nms <- names(data)

  # All-offenders pre-scan: identify every unsupported column before encoding
  # anything, so a refusal names all offenders at once and leaves no state.
  recourse <- lapply(data, .datom_hash_recourse)
  offenders <- which(!vapply(recourse, is.null, logical(1)))
  if (length(offenders) > 0L) {
    n <- length(offenders)
    bullets <- vapply(offenders, function(i) {
      paste0(
        "Column {.field ", nms[[i]], "} ",
        "({.cls ", .datom_class_label(data[[i]]), "}): ",
        recourse[[i]]
      )
    }, character(1L))
    names(bullets) <- rep("x", n)
    cli::cli_abort(c(
      "Cannot compute {.field data_sha}: {n} column{?s} {?is/are} not hashable.",
      bullets,
      "i" = paste0(
        "Run {.run datom_check_hashable(data)} or see ",
        "{.code vignette('design-version-shas')} -- ",
        "\"The datom table contract\"."
      )
    ))
  }

  # Per-column digests -- computed once, reused for data_sha and the index.
  col_hex <- vapply(
    seq_along(data),
    function(i) .datom_col_digest(nms[[i]], data[[i]]),
    character(1L)
  )
  column_hashes <- lapply(seq_along(data), function(i) {
    list(name = nms[[i]], sha = col_hex[[i]])
  })

  header <- c(
    charToRaw("datom-cv1"),
    writeBin(as.double(c(nrow(data), ncol(data))), raw(),
             size = 8L, endian = "little")
  )
  data_sha <- digest::digest(
    c(header, charToRaw(paste(col_hex, collapse = ""))),
    algo = "sha256", serialize = FALSE
  )

  list(data_sha = data_sha, column_hashes = column_hashes)
}


#' Compute the datom-cv1 Content Hash of a Data Frame
#'
#' Thin wrapper over [.datom_canonical_hash()] returning only the scalar
#' `data_sha`. Preserves the scalar-string contract for callers that need
#' just the content hash (for example the `datom_sync()` self-lineage entry).
#' Row and column order are significant; there is no sort option.
#'
#' @param data Data frame to hash.
#' @return Character SHA-256 `data_sha`.
#' @keywords internal
.datom_compute_data_sha <- function(data) {
  .datom_canonical_hash(data)$data_sha
}


#' Compute SHA-256 of Metadata
#'
#' Sorts fields by C-locale byte order (`method = "radix"`) before hashing so
#' the result is deterministic regardless of field insertion order **and**
#' regardless of the host's `LC_COLLATE` (default collation sorts differ
#' between `C` and e.g. `en_US.UTF-8`, which would otherwise make the same
#' metadata hash differently on different machines).
#'
#' Volatile fields are excluded so that identical semantic content always
#' produces the same SHA regardless of when or how it was serialized:
#' `created_at` and `datom_version` (write-time provenance), `parquet_sha` and
#' `size_bytes` (stored-object byte facts -- both drift with the arrow version
#' and must not re-enter identity), and `column_hashes` (a deterministic
#' function of the same values that already fix `data_sha`). `original_file_sha`
#' and `hash_algo` remain in the semantic set -- a new source file or a new hash
#' algorithm legitimately defines a new version.
#'
#' Hashes a JSON canonical form rather than the R object directly. This
#' ensures that metadata read back from JSON (e.g., from S3) produces the
#' same SHA as metadata built in-memory, despite R type differences
#' (integer vs double, character vector vs list) introduced by JSON
#' round-tripping.
#'
#' @param metadata Named list of metadata fields.
#' @return Character SHA-256 hash.
#' @keywords internal
.datom_compute_metadata_sha <- function(metadata) {
  if (!is.list(metadata) || is.null(names(metadata))) {
    cli::cli_abort("{.arg metadata} must be a named list.")
  }

  # Exclude volatile fields that don't define content identity
  volatile <- c("created_at", "datom_version", "parquet_sha", "column_hashes",
                "size_bytes")
  semantic <- metadata[setdiff(names(metadata), volatile)]

  sorted_names <- sort(names(semantic), method = "radix")
  sorted_metadata <- semantic[sorted_names]

  # JSON canonical form: type-agnostic (integer/double, vector/list all
  # serialise identically), so in-memory and S3-round-tripped metadata
  # always produce the same hash.
  canonical <- jsonlite::toJSON(sorted_metadata, auto_unbox = TRUE)
  digest::digest(canonical, algo = "sha256", serialize = FALSE)
}


#' Compute SHA-256 of an Input File's Raw Bytes
#'
#' Answers "have this input artifact's bytes changed?". This is the
#' `original_file_sha` of the three-SHA identity model -- distinct from
#' `data_sha` (canonical logical content) and `parquet_sha` (stored bytes).
#'
#' @param path Path to file.
#' @return Character SHA-256 hash.
#' @keywords internal
.datom_compute_original_file_sha <- function(path) {
  path <- fs::path_abs(path)

  if (!fs::file_exists(path)) {
    cli::cli_abort("File not found: {.path {path}}")
  }

  digest::digest(file = path, algo = "sha256")
}


#' Sync Single Table Metadata to S3
#'
#' @param conn Connection object.
#' @param name Table name.
#' @return Summary of sync operation.
#' @keywords internal
.datom_sync_metadata <- function(conn, name) {
  .datom_validate_name(name)

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Metadata sync requires {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Metadata sync requires a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  repo_path <- conn$path
  table_dir <- fs::path(repo_path, name)

  # Pull before write to ensure fresh state
  .datom_git_pull(repo_path, pat = conn$github_pat)

  metadata_path <- fs::path(table_dir, "metadata.json")
  if (!fs::file_exists(metadata_path)) {
    cli::cli_abort(c(
      "No metadata found for table {.val {name}}.",
      "i" = "Expected {.path {metadata_path}} to exist."
    ))
  }

  # Read metadata from git repo

  metadata <- jsonlite::read_json(metadata_path, simplifyVector = TRUE)
  metadata_sha <- .datom_compute_metadata_sha(metadata)

  # Check for changes against S3
  change_type <- .datom_has_changes(conn, name, metadata$data_sha, metadata_sha)$change_type

  if (change_type == "none") {
    cli::cli_alert_info("No metadata changes for {.val {name}}. Skipping sync.")
    return(invisible(list(
      name = name,
      metadata_sha = metadata_sha,
      action = "none"
    )))
  }

  # Git commit + push first (local -> git -> S3 ordering)
  history_path <- fs::path(table_dir, "version_history.json")

  git_files <- character()
  if (fs::file_exists(metadata_path)) {
    git_files <- c(git_files, fs::path_rel(metadata_path, repo_path))
  }
  if (fs::file_exists(history_path)) {
    git_files <- c(git_files, fs::path_rel(history_path, repo_path))
  }

  commit_sha <- tryCatch(
    {
      sha <- .datom_git_commit(repo_path, git_files, paste0("Sync metadata for ", name))
      .datom_git_push(repo_path, pat = conn$github_pat)
      sha
    },
    error = function(e) {
      cli::cli_abort(c(
        "Git commit/push failed for {.val {name}}. S3 sync aborted.",
        "x" = conditionMessage(e),
        "i" = "Resolve the git issue and re-run. S3 was not modified."
      ))
    }
  )

  # Sync metadata files to S3 (only after git succeeds)
  s3_metadata_key <- paste0(name, "/.metadata/metadata.json")
  .datom_storage_write_json(conn, s3_metadata_key, metadata)

  s3_keys <- s3_metadata_key

  # Sync version_history.json if it exists locally
  if (fs::file_exists(history_path)) {
    history <- jsonlite::read_json(history_path)
    s3_history_key <- paste0(name, "/.metadata/version_history.json")
    .datom_storage_write_json(conn, s3_history_key, history)
    s3_keys <- c(s3_keys, s3_history_key)
  }

  cli::cli_alert_success("Synced metadata for {.val {name}} to S3.")

  invisible(list(
    name = name,
    metadata_sha = metadata_sha,
    action = change_type,
    s3_keys = s3_keys,
    commit_sha = commit_sha
  ))
}


#' Abbreviate SHA Hash
#'
#' Truncates a SHA-256 hash to a short prefix for display. Accepts
#' character vectors; `NA` values pass through unchanged.
#'
#' @param sha Character vector of SHA hashes.
#' @param n Number of characters to keep. Default 8.
#' @return Character vector of abbreviated hashes.
#' @keywords internal
.datom_abbreviate_sha <- function(sha, n = 8L) {
  if (!is.character(sha)) return(sha)
  ifelse(is.na(sha), NA_character_, substr(sha, 1L, n))
}
