# Internal S3 operations
#
# Low-level S3 wrappers around paws.storage.
# Functions accept a `datom_conn` object and an `s3_key` relative to
# `prefix/datom/`. The full key is built internally via `.datom_build_storage_key()`.


#' Create an S3 Client from Credentials
#'
#' Constructs a `paws.storage::s3()` client from credential values.
#' Never stores raw credentials beyond the paws client object.
#'
#' @param access_key AWS access key ID string.
#' @param secret_key AWS secret access key string.
#' @param region AWS region string (e.g. `"us-east-1"`).
#' @param endpoint Optional S3 endpoint URL. NULL for default AWS endpoint.
#' @param session_token Optional AWS session token for temporary credentials.
#' @return A `paws.storage` S3 client.
#' @keywords internal
.datom_s3_client <- function(access_key, secret_key, region = "us-east-1",
                             endpoint = NULL, session_token = NULL) {
  if (!is.character(access_key) || length(access_key) != 1L ||
      is.na(access_key) || !nzchar(access_key)) {
    cli::cli_abort("{.arg access_key} must be a single non-empty string.")
  }

  if (!is.character(secret_key) || length(secret_key) != 1L ||
      is.na(secret_key) || !nzchar(secret_key)) {
    cli::cli_abort("{.arg secret_key} must be a single non-empty string.")
  }

  creds <- list(
    access_key_id = access_key,
    secret_access_key = secret_key
  )
  if (!is.null(session_token)) {
    creds$session_token <- session_token
  }

  config <- list(
    credentials = list(creds = creds),
    region = region
  )

  if (!is.null(endpoint)) {
    config$endpoint <- endpoint
  }

  paws.storage::s3(config = config)
}


#' Upload File to S3
#'
#' Reads a local file as raw bytes and uploads via `put_object()`.
#'
#' @param conn A `datom_conn` object.
#' @param local_path Local file path to upload.
#' @param s3_key Relative S3 key (after `prefix/datom/`).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_s3_upload <- function(conn, local_path, s3_key) {
  if (!fs::file_exists(local_path)) {
    cli::cli_abort(
      "File not found: {.path {local_path}}"
    )
  }

  full_key <- .datom_build_storage_key(conn$prefix, s3_key)
  body <- readBin(local_path, what = "raw", n = fs::file_size(local_path))

  tryCatch(
    {
      conn$client$put_object(
        Bucket = conn$root,
        Key = full_key,
        Body = body
      )
      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to upload file to S3.",
          "x" = "Root: {.val {conn$root}}",
          "x" = "Key: {.val {full_key}}",
          "x" = "Local path: {.path {local_path}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' Upload a File to S3 Only If Its Key Is Absent
#'
#' Checks with a HEAD request first, so a re-run never resends a large file
#' that is already stored. If the key is absent, uploads with
#' `IfNoneMatch = "*"`: S3 then refuses the upload with HTTP 412 when another
#' writer stored the key in between, and that refusal is returned as
#' `"exists"`. On an S3-compatible service that ignores the condition only the
#' check protects the stored file, and the race between check and upload
#' remains.
#'
#' The upload carries the file's SHA-256 (`ChecksumSHA256`, base64 of the raw
#' digest). S3 verifies it on arrival and keeps it with the object, so
#' `.datom_s3_object_sha256()` can read the stored file's hash later without
#' downloading it.
#'
#' Every other failure stops with the usual upload error. That includes a 409,
#' which AWS returns when a delete of the key finishes while the upload runs;
#' in datom only a teardown deletes data files, so it is not retried, which
#' could upload into a project being torn down.
#'
#' @param conn A `datom_conn` object.
#' @param local_path Local file path to upload.
#' @param s3_key Relative S3 key (after `prefix/datom/`).
#' @return `"uploaded"` or `"exists"`.
#' @keywords internal
.datom_s3_upload_absent <- function(conn, local_path, s3_key) {
  if (!fs::file_exists(local_path)) {
    cli::cli_abort("File not found: {.path {local_path}}")
  }

  if (.datom_s3_exists(conn, s3_key)) return("exists")

  full_key <- .datom_build_storage_key(conn$prefix, s3_key)
  body <- readBin(local_path, what = "raw", n = fs::file_size(local_path))
  checksum <- jsonlite::base64_enc(
    digest::digest(body, algo = "sha256", serialize = FALSE, raw = TRUE)
  )

  tryCatch(
    {
      conn$client$put_object(
        Bucket = conn$root,
        Key = full_key,
        Body = body,
        IfNoneMatch = "*",
        ChecksumSHA256 = checksum
      )
      "uploaded"
    },
    http_412 = function(e) "exists",
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to upload file to S3.",
          "x" = "Root: {.val {conn$root}}",
          "x" = "Key: {.val {full_key}}",
          "x" = "Local path: {.path {local_path}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' SHA-256 of the Bytes Stored at an S3 Key
#'
#' Asks S3 for the checksum it keeps with the object (`ChecksumMode =
#' "ENABLED"`) and uses it only when it is the SHA-256 of the whole file (see
#' `.datom_s3_whole_file_sha256()`). Otherwise downloads the object and hashes
#' it.
#'
#' @param conn A `datom_conn` object.
#' @param s3_key Relative S3 key (after `prefix/datom/`).
#' @return The SHA-256 as a lowercase hex string.
#' @keywords internal
.datom_s3_object_sha256 <- function(conn, s3_key) {
  full_key <- .datom_build_storage_key(conn$prefix, s3_key)

  head <- tryCatch(
    conn$client$head_object(
      Bucket = conn$root,
      Key = full_key,
      ChecksumMode = "ENABLED"
    ),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to read a stored file's checksum from S3.",
          "x" = "Root: {.val {conn$root}}",
          "x" = "Key: {.val {full_key}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )

  stored <- .datom_s3_whole_file_sha256(head$ChecksumSHA256, head$ChecksumType)
  if (!is.null(stored)) return(stored)

  resp <- tryCatch(
    conn$client$get_object(Bucket = conn$root, Key = full_key),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to download a stored file from S3 to hash it.",
          "x" = "Root: {.val {conn$root}}",
          "x" = "Key: {.val {full_key}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
  digest::digest(resp$Body, algo = "sha256", serialize = FALSE)
}


#' The Whole-File SHA-256 in an S3 Checksum, If It Is One
#'
#' A stored `ChecksumSHA256` is the file's SHA-256 only when it covers the
#' whole file: `ChecksumType` is `FULL_OBJECT`, or there is no type and the
#' value carries no `-N` part-count suffix. A file uploaded in parts carries a
#' checksum of its parts' checksums instead (type `COMPOSITE`, value ending in
#' `-N`), and read as a plain hash it would record a wrong one, so every read
#' of that version would be refused.
#'
#' The suffix rule does not rely on the base64 decoder refusing a suffixed
#' value (the one used here does, a lenient one would not), and a value that
#' does not decode to exactly 32 bytes is not trusted either.
#'
#' @param checksum The `ChecksumSHA256` field of a `head_object()` response.
#' @param type The `ChecksumType` field of the same response.
#' @return The SHA-256 as a lowercase hex string, or `NULL` when the checksum
#'   is absent or does not cover the whole file.
#' @keywords internal
.datom_s3_whole_file_sha256 <- function(checksum, type) {
  present <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)

  if (!present(checksum)) return(NULL)
  if (present(type) && !identical(type, "FULL_OBJECT")) return(NULL)
  if (!present(type) && grepl("-[0-9]+$", checksum)) return(NULL)

  digest_raw <- tryCatch(jsonlite::base64_dec(checksum), error = function(e) NULL)
  if (length(digest_raw) != 32L) return(NULL)

  paste(as.character(digest_raw), collapse = "")
}


#' Download File from S3
#'
#' Downloads an S3 object and writes it to a local path. Creates parent
#' directories if needed.
#'
#' @param conn A `datom_conn` object.
#' @param s3_key Relative S3 key (after `prefix/datom/`).
#' @param local_path Local file path (destination).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_s3_download <- function(conn, s3_key, local_path) {
  full_key <- .datom_build_storage_key(conn$prefix, s3_key)
  fs::dir_create(fs::path_dir(local_path))

  tryCatch(
    {
      resp <- conn$client$get_object(
        Bucket = conn$root,
        Key = full_key
      )
      writeBin(resp$Body, local_path)
      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to download file from S3.",
          "x" = "Root: {.val {conn$root}}",
          "x" = "Key: {.val {full_key}}",
          "x" = "Local path: {.path {local_path}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' Check if S3 Object Exists
#'
#' Uses a HEAD request for efficiency. Returns `TRUE` if the object exists,
#' `FALSE` on 404/NoSuchKey. Any other error (403, network) is re-thrown.
#'
#' @param conn A `datom_conn` object.
#' @param s3_key Relative S3 key (after `prefix/datom/`).
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.datom_s3_exists <- function(conn, s3_key) {
  full_key <- .datom_build_storage_key(conn$prefix, s3_key)

  tryCatch(
    {
      conn$client$head_object(
        Bucket = conn$root,
        Key = full_key
      )
      TRUE
    },
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("404|NoSuchKey|Not Found", msg, ignore.case = TRUE)) {
        return(FALSE)
      }
      cli::cli_abort(
        c(
          "Failed to check S3 object existence.",
          "x" = "Root: {.val {conn$root}}",
          "x" = "Key: {.val {full_key}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' Read and Parse JSON from S3
#'
#' Downloads an S3 object, reads it as text, and parses as JSON.
#' Uses `simplifyVector = FALSE` to keep lists as lists (matching
#' how `.datom_s3_write_json()` writes them).
#'
#' @param conn A `datom_conn` object.
#' @param s3_key Relative S3 key (after `prefix/datom/`).
#' @return Parsed R list.
#' @keywords internal
.datom_s3_read_json <- function(conn, s3_key) {
  full_key <- .datom_build_storage_key(conn$prefix, s3_key)

  resp <- tryCatch(
    conn$client$get_object(
      Bucket = conn$root,
      Key = full_key
    ),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to read JSON from S3.",
          "x" = "Root: {.val {conn$root}}",
          "x" = "Key: {.val {full_key}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )

  json_text <- rawToChar(resp$Body)

  tryCatch(
    jsonlite::fromJSON(json_text, simplifyVector = FALSE),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to parse JSON from S3 object.",
          "x" = "Root: {.val {conn$root}}",
          "x" = "Key: {.val {full_key}}",
          "i" = "Parse error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' Write an R List to S3 as JSON
#'
#' Serializes `data` to JSON via `jsonlite::toJSON()` and uploads to S3.
#'
#' @param conn A `datom_conn` object.
#' @param s3_key Relative S3 key (after `prefix/datom/`).
#' @param data An R list to serialize to JSON.
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_s3_write_json <- function(conn, s3_key, data) {
  full_key <- .datom_build_storage_key(conn$prefix, s3_key)
  json_raw <- charToRaw(
    jsonlite::toJSON(data, auto_unbox = TRUE, pretty = TRUE)
  )

  tryCatch(
    {
      conn$client$put_object(
        Bucket = conn$root,
        Key = full_key,
        Body = json_raw,
        ContentType = "application/json"
      )
      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to write JSON to S3.",
          "x" = "Root: {.val {conn$root}}",
          "x" = "Key: {.val {full_key}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' Delete All S3 Objects Under a Prefix
#'
#' Lists every key under `{prefix}/datom/{prefix_key}` and deletes in batches
#' of up to 1000. A missing prefix is a no-op.
#'
#' @param conn A `datom_conn` object.
#' @param prefix_key Relative prefix (after `prefix/datom/`).
#' @return Invisibly, the count of deleted objects.
#' @keywords internal
.datom_s3_delete_prefix <- function(conn, prefix_key = NULL) {
  # NULL prefix_key = delete everything under conn's datom namespace root
  if (is.null(prefix_key)) {
    has_prefix <- !is.null(conn$prefix) && !is.na(conn$prefix) && nzchar(conn$prefix)
    base <- if (isTRUE(has_prefix)) {
      paste0(gsub("^/+|/+$", "", conn$prefix), "/datom/")
    } else {
      "datom/"
    }
    full_prefix <- base
  } else {
    full_prefix <- .datom_build_storage_key(conn$prefix, prefix_key)
    if (!endsWith(full_prefix, "/")) full_prefix <- paste0(full_prefix, "/")
  }

  all_keys <- character()
  continuation <- NULL

  repeat {
    args <- list(Bucket = conn$root, Prefix = full_prefix, MaxKeys = 1000L)
    if (!is.null(continuation)) args$ContinuationToken <- continuation
    resp <- do.call(conn$client$list_objects_v2, args)
    keys <- purrr::map_chr(resp$Contents %||% list(), "Key")
    all_keys <- c(all_keys, keys)
    if (!isTRUE(resp$IsTruncated)) break
    continuation <- resp$NextContinuationToken
  }

  if (length(all_keys) == 0L) return(invisible(0L))

  batches <- split(all_keys, ceiling(seq_along(all_keys) / 1000))
  for (batch in batches) {
    conn$client$delete_objects(
      Bucket = conn$root,
      Delete = list(
        Objects = purrr::map(batch, ~ list(Key = .x)),
        Quiet = TRUE
      )
    )
  }

  invisible(length(all_keys))
}


#' List S3 Objects Under a Prefix
#'
#' Lists every key under `{prefix}/datom/{prefix_key}` and returns relative
#' keys (relative to the datom namespace, i.e. with the `prefix/datom/` part
#' stripped). Paginates via `ContinuationToken`.
#'
#' @param conn A `datom_conn` object.
#' @param prefix Relative prefix (after `prefix/datom/`).
#' @return Character vector of relative keys (may be empty).
#' @keywords internal
.datom_s3_list_objects <- function(conn, prefix) {
  full_prefix <- .datom_build_storage_key(conn$prefix, prefix)
  if (!endsWith(full_prefix, "/")) full_prefix <- paste0(full_prefix, "/")

  # Strip leading "{prefix}/datom/" or "datom/" so returned keys are relative
  # to the datom namespace root, mirroring `.datom_local_list_objects()`
  # (which returns keys relative to `conn$root`, i.e. including the
  # `{prefix}/datom/` portion). For consistency with how callers use these
  # helpers via gov-conn (where `prefix` arg already lives under
  # `datom/`), we keep keys as-is (full_key form). Callers strip as needed.

  all_keys <- character()
  continuation <- NULL

  repeat {
    args <- list(Bucket = conn$root, Prefix = full_prefix, MaxKeys = 1000L)
    if (!is.null(continuation)) args$ContinuationToken <- continuation
    resp <- do.call(conn$client$list_objects_v2, args)
    keys <- purrr::map_chr(resp$Contents %||% list(), "Key")
    all_keys <- c(all_keys, keys)
    if (!isTRUE(resp$IsTruncated)) break
    continuation <- resp$NextContinuationToken
  }

  all_keys
}
