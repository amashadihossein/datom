# Internal S3 operations
#
# Phase 2: Low-level S3 wrappers around paws.storage.
# These accept a lightweight list(bucket, s3_client) for now.
# Phase 4 introduces the full tbit_conn S3 class and refactors the call sites.


#' Create an S3 Client from Credential Environment Variables
#'
#' Reads AWS credentials from the named environment variables and
#' constructs a `paws.storage::s3()` client. Never stores raw credentials.
#'
#' @param credentials Named list with `access_key_env` and `secret_key_env`
#'   pointing to environment variable names.
#' @param region AWS region string (e.g. `"us-east-1"`).
#' @return A `paws.storage` S3 client.
#' @keywords internal
.tbit_s3_client <- function(credentials, region = "us-east-1") {
  if (!is.list(credentials) ||
      !all(c("access_key_env", "secret_key_env") %in% names(credentials))) {
    cli::cli_abort(
      "{.arg credentials} must be a list with {.val access_key_env} and {.val secret_key_env}."
    )
  }

  access_key <- Sys.getenv(credentials$access_key_env, unset = "")
  if (!nzchar(access_key)) {
    cli::cli_abort(
      "Environment variable {.envvar {credentials$access_key_env}} is not set or is empty."
    )
  }

  secret_key <- Sys.getenv(credentials$secret_key_env, unset = "")
  if (!nzchar(secret_key)) {
    cli::cli_abort(
      "Environment variable {.envvar {credentials$secret_key_env}} is not set or is empty."
    )
  }

  paws.storage::s3(
    config = list(
      credentials = list(
        creds = list(
          access_key_id = access_key,
          secret_access_key = secret_key
        )
      ),
      region = region
    )
  )
}


#' Upload File to S3
#'
#' Reads a local file as raw bytes and uploads via `put_object()`.
#'
#' @param s3_client A `paws.storage` S3 client.
#' @param bucket S3 bucket name.
#' @param local_path Local file path to upload.
#' @param s3_key S3 object key (destination).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.tbit_s3_upload <- function(s3_client, bucket, local_path, s3_key) {
  if (!fs::file_exists(local_path)) {
    cli::cli_abort(
      "File not found: {.path {local_path}}"
    )
  }

  body <- readBin(local_path, what = "raw", n = fs::file_size(local_path))

  tryCatch(
    {
      s3_client$put_object(
        Bucket = bucket,
        Key = s3_key,
        Body = body
      )
      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to upload file to S3.",
          "x" = "Bucket: {.val {bucket}}",
          "x" = "Key: {.val {s3_key}}",
          "x" = "Local path: {.path {local_path}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' Download File from S3
#'
#' Downloads an S3 object and writes it to a local path. Creates parent
#' directories if needed.
#'
#' @param s3_client A `paws.storage` S3 client.
#' @param bucket S3 bucket name.
#' @param s3_key S3 object key (source).
#' @param local_path Local file path (destination).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.tbit_s3_download <- function(s3_client, bucket, s3_key, local_path) {
  fs::dir_create(fs::path_dir(local_path))

  tryCatch(
    {
      resp <- s3_client$get_object(
        Bucket = bucket,
        Key = s3_key
      )
      writeBin(resp$Body, local_path)
      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to download file from S3.",
          "x" = "Bucket: {.val {bucket}}",
          "x" = "Key: {.val {s3_key}}",
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
#' @param s3_client A `paws.storage` S3 client.
#' @param bucket S3 bucket name.
#' @param s3_key S3 object key.
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.tbit_s3_exists <- function(s3_client, bucket, s3_key) {
  tryCatch(
    {
      s3_client$head_object(
        Bucket = bucket,
        Key = s3_key
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
          "x" = "Bucket: {.val {bucket}}",
          "x" = "Key: {.val {s3_key}}",
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
#' how `.tbit_s3_write_json()` writes them).
#'
#' @param s3_client A `paws.storage` S3 client.
#' @param bucket S3 bucket name.
#' @param s3_key S3 object key.
#' @return Parsed R list.
#' @keywords internal
.tbit_s3_read_json <- function(s3_client, bucket, s3_key) {
  resp <- tryCatch(
    s3_client$get_object(
      Bucket = bucket,
      Key = s3_key
    ),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to read JSON from S3.",
          "x" = "Bucket: {.val {bucket}}",
          "x" = "Key: {.val {s3_key}}",
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
          "x" = "Bucket: {.val {bucket}}",
          "x" = "Key: {.val {s3_key}}",
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
#' @param s3_client A `paws.storage` S3 client (from `.tbit_s3_client()`).
#' @param bucket S3 bucket name.
#' @param s3_key S3 object key (path within bucket).
#' @param data An R list to serialize to JSON.
#' @return Invisible `TRUE` on success.
#' @keywords internal
.tbit_s3_write_json <- function(s3_client, bucket, s3_key, data) {
  json_raw <- charToRaw(
    jsonlite::toJSON(data, auto_unbox = TRUE, pretty = TRUE)
  )

  tryCatch(
    {
      s3_client$put_object(
        Bucket = bucket,
        Key = s3_key,
        Body = json_raw,
        ContentType = "application/json"
      )
      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to write JSON to S3.",
          "x" = "Bucket: {.val {bucket}}",
          "x" = "Key: {.val {s3_key}}",
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' Resolve S3 Redirect Chain
#'
#' Follows `.redirect.json` files placed in old buckets after migration.
#' Each redirect points to a new `s3://bucket/prefix/tbit/` location and
#' may include new credentials. Recurses until no redirect is found.
#'
#' @param s3_client A `paws.storage` S3 client for the current location.
#' @param bucket Current S3 bucket.
#' @param prefix Current S3 prefix (without trailing `/tbit`).
#' @param max_depth Maximum number of redirects to follow (default 5).
#' @param .depth Internal counter — do not set manually.
#' @return A list with `bucket`, `prefix`, and `s3_client` for the resolved
#'   final location.
#' @keywords internal
.tbit_s3_resolve_redirect <- function(s3_client, bucket, prefix,
                                      max_depth = 5L, .depth = 0L) {
  if (.depth >= max_depth) {
    cli::cli_abort(
      c(
        "Redirect chain exceeded maximum depth of {max_depth}.",
        "i" = "This may indicate a circular redirect.",
        "i" = "Current location: {.val {bucket}}/{.val {prefix}}"
      )
    )
  }

  redirect_key <- .tbit_build_s3_key(prefix, ".redirect.json")

  redirect_exists <- .tbit_s3_exists(s3_client, bucket, redirect_key)
  if (!redirect_exists) {
    return(list(bucket = bucket, prefix = prefix, s3_client = s3_client))
  }

  redirect <- .tbit_s3_read_json(s3_client, bucket, redirect_key)

  if (is.null(redirect$redirect_to) || !nzchar(redirect$redirect_to)) {
    cli::cli_abort(
      c(
        "Invalid redirect: {.field redirect_to} is missing or empty.",
        "x" = "Bucket: {.val {bucket}}",
        "x" = "Key: {.val {redirect_key}}"
      )
    )
  }

  # Parse redirect_to URI — expected format: s3://bucket/prefix/tbit/
  # Strip trailing "tbit/" or "tbit" to get the prefix
  redirect_uri <- sub("/tbit/?$", "", redirect$redirect_to)
  parsed <- .tbit_parse_s3_uri(redirect_uri)

  # Build new client if redirect provides credentials
  new_client <- s3_client
  if (!is.null(redirect$credentials)) {
    creds <- redirect$credentials
    if (is.null(creds$access_key_env) || is.null(creds$secret_key_env)) {
      cli::cli_abort(
        c(
          "Invalid redirect credentials: missing {.field access_key_env} or {.field secret_key_env}.",
          "x" = "Redirect from: {.val {bucket}}/{.val {redirect_key}}"
        )
      )
    }
    new_client <- .tbit_s3_client(creds)
  }

  # Recurse into the new location
  .tbit_s3_resolve_redirect(
    s3_client = new_client,
    bucket = parsed$bucket,
    prefix = parsed$prefix,
    max_depth = max_depth,
    .depth = .depth + 1L
  )
}