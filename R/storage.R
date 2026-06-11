# Storage Extension API
#
# Exported wrappers over the internal storage dispatch layer
# (`.datom_storage_*()` in `R/utils-storage.R`). Intended for package
# developers (e.g. datomanager) that need to move or inspect bytes without
# reaching into internals via `:::`.
#
# Naming: `datom_storage_*` for byte-level primitives;
#         `datom_repo_*`    for data-repo git operations (see R/repo.R).


#' List All Objects in a datom Storage Namespace
#'
#' Returns the full storage keys of every object under the datom namespace
#' for this connection (`{prefix}/datom/...`). Intended for package developers
#' building tools on top of datom (e.g. datomanager); end users typically do
#' not need to inspect raw storage keys directly.
#'
#' Keys are returned in their full storage-key form -- for S3 that is
#' `"{prefix}/datom/..."` relative to the bucket root; for local backends it
#' is a path relative to `conn$root`. This mirrors the contract of the
#' internal `.datom_storage_list_objects()` dispatch layer.
#'
#' @param conn A `datom_conn` object.
#' @return A character vector of full storage keys. May be empty if the
#'   namespace contains no objects.
#' @export
#' @examples
#' \dontrun{
#' conn <- datom_get_conn(path = ".", store = store)
#' keys <- datom_storage_list(conn)
#' length(keys)
#' }
datom_storage_list <- function(conn) {
  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object.")
  }
  .datom_storage_list_objects(conn, "")
}


#' Delete All Objects Under a datom Storage Prefix
#'
#' Removes every file under `{prefix}/datom/{prefix_key}` from storage.
#' Pass `prefix_key = NULL` (the default) to delete the entire datom
#' namespace for this connection. A missing or empty prefix is a no-op.
#'
#' **Irreversible.** Intended for package developers building tools on top of
#' datom (e.g. datomanager for rollback or source deletion after migration).
#' End users performing a full project teardown should use
#' [datom_decommission()] instead.
#'
#' @param conn A `datom_conn` object.
#' @param prefix_key Relative prefix to delete under (after
#'   `{prefix}/datom/`). `NULL` (default) deletes the entire datom namespace
#'   root for this connection.
#' @return Invisibly, a backend-specific value. For S3: the count of deleted
#'   objects (0L if nothing found). For the local backend: `1L` if the prefix
#'   directory existed and was removed, `0L` otherwise.
#' @export
#' @examples
#' \dontrun{
#' # Delete a single table's objects
#' datom_storage_delete_prefix(conn, prefix_key = "demographics")
#'
#' # Delete the entire datom namespace (use with care)
#' datom_storage_delete_prefix(conn)
#' }
datom_storage_delete_prefix <- function(conn, prefix_key = NULL) {
  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object.")
  }
  .datom_storage_delete_prefix(conn, prefix_key)
}


# ==============================================================================
# datom_storage_copy() and private helpers
# ==============================================================================

#' Strip datom Namespace Prefix from a Full Storage Key
#'
#' Converts a full storage key (as returned by `.datom_storage_list_objects()`)
#' to a relative key suitable for upload/download helpers (after
#' `{prefix}/datom/`).
#'
#' @param full_key Full storage key string.
#' @param conn The source `datom_conn` (provides prefix for stripping).
#' @return Relative key string.
#' @keywords internal
.datom_storage_rel_key <- function(full_key, conn) {
  has_prefix <- !is.null(conn$prefix) && !is.na(conn$prefix) && nzchar(conn$prefix)
  ns_root <- if (isTRUE(has_prefix)) {
    paste0(gsub("^/+|/+$", "", conn$prefix), "/datom/")
  } else {
    "datom/"
  }
  sub(paste0("^", ns_root), "", full_key)
}


#' Copy a Single Storage Object Between Two Connections
#'
#' Dispatches on the (from_backend, to_backend) pair. For local->local uses
#' `fs::file_copy`; all other combos transfer raw bytes.
#'
#' @param from_conn Source `datom_conn`.
#' @param to_conn Destination `datom_conn`.
#' @param rel_key Relative storage key (after `{prefix}/datom/`).
#' @return Named list with `key` (character) and `bytes` (numeric).
#' @keywords internal
.datom_copy_one <- function(from_conn, to_conn, rel_key) {
  from_backend <- from_conn$backend
  to_backend   <- to_conn$backend

  tryCatch(
    {
      if (from_backend == "local" && to_backend == "local") {
        src  <- .datom_local_path(from_conn, rel_key)
        dest <- .datom_local_path(to_conn,   rel_key)
        fs::dir_create(fs::path_dir(dest))
        fs::file_copy(src, dest, overwrite = TRUE)
        bytes <- as.numeric(fs::file_size(src))

      } else if (from_backend == "local" && to_backend == "s3") {
        src_path <- .datom_local_path(from_conn, rel_key)
        body     <- readBin(src_path, what = "raw", n = fs::file_size(src_path))
        dest_key <- .datom_build_storage_key(to_conn$prefix, rel_key)
        to_conn$client$put_object(
          Bucket = to_conn$root,
          Key    = dest_key,
          Body   = body
        )
        bytes <- length(body)

      } else if (from_backend == "s3" && to_backend == "local") {
        src_key   <- .datom_build_storage_key(from_conn$prefix, rel_key)
        resp      <- from_conn$client$get_object(
          Bucket = from_conn$root,
          Key    = src_key
        )
        dest_path <- .datom_local_path(to_conn, rel_key)
        fs::dir_create(fs::path_dir(dest_path))
        writeBin(resp$Body, dest_path)
        bytes <- length(resp$Body)

      } else if (from_backend == "s3" && to_backend == "s3") {
        src_key  <- .datom_build_storage_key(from_conn$prefix, rel_key)
        resp     <- from_conn$client$get_object(
          Bucket = from_conn$root,
          Key    = src_key
        )
        dest_key <- .datom_build_storage_key(to_conn$prefix, rel_key)
        to_conn$client$put_object(
          Bucket = to_conn$root,
          Key    = dest_key,
          Body   = resp$Body
        )
        bytes <- length(resp$Body)

      } else {
        cli::cli_abort(
          "Unsupported backend combination: {.val {from_backend}} -> {.val {to_backend}}"
        )
      }

      list(key = rel_key, bytes = bytes)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to copy object.",
          "x" = "Key: {.val {rel_key}}",
          "x" = "From: {.val {from_backend}} ({.val {from_conn$root}})",
          "x" = "To: {.val {to_backend}} ({.val {to_conn$root}})",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' Copy All Objects Between Two datom Storage Namespaces
#'
#' Enumerates all objects under `from_conn`'s datom namespace and streams each
#' one to `to_conn`'s datom namespace. All four backend combinations are
#' supported:
#'
#' * **local -> local**: direct file copy via `fs::file_copy()`.
#' * **local -> S3**: reads raw bytes and uploads via `put_object`.
#' * **S3 -> local**: downloads via `get_object` and writes to disk.
#' * **S3 -> S3**: streams bytes through memory (get then put).
#'   Server-side `copy_object` (same-region optimisation) is reserved for a
#'   future release.
#'
#' This is a policy-free primitive. It does not modify the source namespace,
#' update `project.yaml`, or switch `ref.json`. For a complete managed
#' migration (governed projects) use `datomanager::gov_migrate_data()`.
#' For solo-project relocation combine this function with
#' [datom_repo_set_data_store()].
#'
#' @param from_conn A `datom_conn` object (source).
#' @param to_conn A `datom_conn` object (destination).
#' @return A data frame with columns `key` (character, relative key after
#'   `{prefix}/datom/`) and `bytes` (numeric, byte count per object). Returns
#'   a zero-row data frame if the source namespace is empty.
#' @export
#' @seealso [datom_storage_verify()], [datom_storage_list()],
#'   [datom_storage_delete_prefix()], [datom_repo_set_data_store()]
#' @examples
#' \dontrun{
#' from_conn <- datom_get_conn(path = ".", store = old_store)
#' to_conn   <- datom_get_conn(path = ".", store = new_store)
#' copied    <- datom_storage_copy(from_conn, to_conn)
#' nrow(copied)  # number of objects copied
#' sum(copied$bytes)  # total bytes
#' }
datom_storage_copy <- function(from_conn, to_conn) {
  if (!inherits(from_conn, "datom_conn")) {
    cli::cli_abort("{.arg from_conn} must be a {.cls datom_conn} object.")
  }
  if (!inherits(to_conn, "datom_conn")) {
    cli::cli_abort("{.arg to_conn} must be a {.cls datom_conn} object.")
  }

  full_keys <- datom_storage_list(from_conn)

  if (length(full_keys) == 0L) {
    cli::cli_alert_info("Source namespace is empty -- nothing to copy.")
    return(data.frame(key = character(0), bytes = numeric(0)))
  }

  from_label <- c(s3 = "S3", local = "local")[from_conn$backend] %||% from_conn$backend
  to_label   <- c(s3 = "S3", local = "local")[to_conn$backend]   %||% to_conn$backend

  cli::cli_alert_info(
    "Copying {length(full_keys)} object{?s} ({.val {from_label}} -> {.val {to_label}})..."
  )

  results <- purrr::map(full_keys, function(full_key) {
    rel_key <- .datom_storage_rel_key(full_key, from_conn)
    .datom_copy_one(from_conn, to_conn, rel_key)
  })

  out <- data.frame(
    key   = purrr::map_chr(results, "key"),
    bytes = purrr::map_dbl(results, "bytes"),
    stringsAsFactors = FALSE
  )

  total_bytes <- sum(out$bytes)
  cli::cli_alert_success(
    "Copied {nrow(out)} object{?s} ({format(total_bytes, big.mark = ',')} bytes total)."
  )
  out
}


# ==============================================================================
# datom_storage_verify() and private helpers
# ==============================================================================

#' Get Byte Size of a Single Storage Object
#'
#' Returns the byte size of the object at `rel_key` without reading its content.
#' For S3 uses `HEAD`; for local uses `fs::file_size()`. Errors if the object
#' is not found.
#'
#' @param conn A `datom_conn` object.
#' @param rel_key Relative storage key (after `{prefix}/datom/`).
#' @return Numeric byte count.
#' @keywords internal
.datom_storage_byte_size <- function(conn, rel_key) {
  if (conn$backend == "s3") {
    full_key <- .datom_build_storage_key(conn$prefix, rel_key)
    resp <- conn$client$head_object(Bucket = conn$root, Key = full_key)
    as.numeric(resp$ContentLength)
  } else {
    path <- .datom_local_path(conn, rel_key)
    as.numeric(fs::file_size(path))
  }
}


#' Compute SHA-256 Hash of a Storage Object's Content
#'
#' For S3, downloads the raw bytes and hashes in memory. For local, hashes
#' the file directly. Used by `datom_storage_verify()` in `content` mode.
#'
#' @param conn A `datom_conn` object.
#' @param rel_key Relative storage key (after `{prefix}/datom/`).
#' @return Character SHA-256 hex string.
#' @keywords internal
.datom_storage_content_hash <- function(conn, rel_key) {
  if (conn$backend == "s3") {
    full_key <- .datom_build_storage_key(conn$prefix, rel_key)
    resp <- conn$client$get_object(Bucket = conn$root, Key = full_key)
    digest::digest(resp$Body, algo = "sha256", serialize = FALSE)
  } else {
    path <- as.character(.datom_local_path(conn, rel_key))
    digest::digest(file = path, algo = "sha256")
  }
}


#' Verify a Single Storage Object
#'
#' Checks that the object at `rel_key` in `to_conn` matches the one in
#' `from_conn`. Returns a named list with `key`, `ok` (logical), and `issue`
#' (character or `NA_character_`).
#'
#' @param from_conn Source `datom_conn`.
#' @param to_conn Destination `datom_conn`.
#' @param rel_key Relative key (after `{prefix}/datom/`).
#' @param mode `"structural"` or `"content"`.
#' @return Named list: `key`, `ok`, `issue`.
#' @keywords internal
.datom_verify_one <- function(from_conn, to_conn, rel_key, mode) {
  # Source size -- expected to always exist; hard-error if not
  src_size <- tryCatch(
    .datom_storage_byte_size(from_conn, rel_key),
    error = function(e) {
      cli::cli_abort(
        c(
          "Cannot read source object for verification.",
          "x" = "Key: {.val {rel_key}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )

  # Destination -- missing / inaccessible is a verification failure, not an error
  dest_size <- tryCatch(
    .datom_storage_byte_size(to_conn, rel_key),
    error = function(e) NA_real_
  )

  if (is.na(dest_size)) {
    return(list(key = rel_key, ok = FALSE, issue = "destination object not found"))
  }

  if (mode == "structural") {
    if (!isTRUE(src_size == dest_size)) {
      return(list(
        key   = rel_key,
        ok    = FALSE,
        issue = paste0("size mismatch: source=", src_size, "B destination=", dest_size, "B")
      ))
    }
    return(list(key = rel_key, ok = TRUE, issue = NA_character_))
  }

  # content mode: re-hash both sides
  src_hash  <- .datom_storage_content_hash(from_conn, rel_key)
  dest_hash <- .datom_storage_content_hash(to_conn,   rel_key)

  if (src_hash != dest_hash) {
    return(list(
      key   = rel_key,
      ok    = FALSE,
      issue = paste0("content hash mismatch: source=", src_hash,
                     " destination=", dest_hash)
    ))
  }

  list(key = rel_key, ok = TRUE, issue = NA_character_)
}


#' Verify a Copy Between Two datom Storage Namespaces
#'
#' Checks that objects in `to_conn`'s datom namespace match their counterparts
#' in `from_conn`. Two verification modes are available:
#'
#' * **`"structural"` (default)**: Confirms each destination object exists and
#'   its byte size matches the source. Fast -- one `HEAD`/stat per object, no
#'   byte transfer. Catches truncated or missing objects, which is the dominant
#'   copy failure mode.
#' * **`"content"`**: Re-reads destination bytes, recomputes the SHA-256 hash,
#'   and compares against the source hash. Expensive (full re-download for
#'   remote backends) but gives true bit-level integrity. Use for regulated or
#'   paranoid runs.
#'
#' @param from_conn A `datom_conn` object (source / reference).
#' @param to_conn A `datom_conn` object (destination to verify).
#' @param keys Character vector of relative keys (after `{prefix}/datom/`) to
#'   verify. `NULL` (default) verifies every key returned by
#'   `datom_storage_list(from_conn)`. Pass a subset to verify a sample.
#' @param mode `"structural"` (default) or `"content"`. See above.
#' @return A data frame with columns:
#'   * `key` (character): relative storage key.
#'   * `ok` (logical): `TRUE` if the object passed verification.
#'   * `issue` (character): description of the mismatch, or `NA` if `ok`.
#'   Returns a zero-row data frame if `keys` is empty.
#' @export
#' @seealso [datom_storage_copy()], [datom_storage_list()]
#' @examples
#' \dontrun{
#' copied <- datom_storage_copy(from_conn, to_conn)
#' # Verify all copied objects structurally (default, fast)
#' results <- datom_storage_verify(from_conn, to_conn)
#' all(results$ok)
#'
#' # Verify a subset with full content hash
#' results <- datom_storage_verify(from_conn, to_conn,
#'                                 keys  = copied$key[1:10],
#'                                 mode  = "content")
#' }
datom_storage_verify <- function(from_conn, to_conn,
                                 keys = NULL,
                                 mode = c("structural", "content")) {
  if (!inherits(from_conn, "datom_conn")) {
    cli::cli_abort("{.arg from_conn} must be a {.cls datom_conn} object.")
  }
  if (!inherits(to_conn, "datom_conn")) {
    cli::cli_abort("{.arg to_conn} must be a {.cls datom_conn} object.")
  }
  mode <- match.arg(mode)

  if (is.null(keys)) {
    full_keys <- datom_storage_list(from_conn)
    rel_keys  <- purrr::map_chr(full_keys, .datom_storage_rel_key, conn = from_conn)
  } else {
    if (!is.character(keys)) {
      cli::cli_abort("{.arg keys} must be a character vector or NULL.")
    }
    rel_keys <- keys
  }

  if (length(rel_keys) == 0L) {
    return(data.frame(
      key   = character(0),
      ok    = logical(0),
      issue = character(0),
      stringsAsFactors = FALSE
    ))
  }

  mode_label <- if (mode == "structural") "structural (size)" else "content (hash)"
  cli::cli_alert_info(
    "Verifying {length(rel_keys)} object{?s} -- {.val {mode_label}} mode..."
  )

  results <- purrr::map(
    rel_keys, .datom_verify_one,
    from_conn = from_conn, to_conn = to_conn, mode = mode
  )

  out <- data.frame(
    key   = purrr::map_chr(results, "key"),
    ok    = purrr::map_lgl(results, "ok"),
    issue = vapply(results, function(r) {
      v <- r$issue
      if (is.null(v) || is.na(v)) NA_character_ else as.character(v)
    }, character(1L)),
    stringsAsFactors = FALSE
  )

  n_fail <- sum(!out$ok)
  if (n_fail == 0L) {
    cli::cli_alert_success("All {nrow(out)} object{?s} verified successfully.")
  } else {
    cli::cli_alert_warning(
      "{n_fail} of {nrow(out)} object{?s} failed verification."
    )
  }

  out
}
