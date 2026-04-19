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
        Bucket = conn$bucket,
        Key = full_key,
        Body = body
      )
      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to upload file to S3.",
          "x" = "Bucket: {.val {conn$bucket}}",
          "x" = "Key: {.val {full_key}}",
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
        Bucket = conn$bucket,
        Key = full_key
      )
      writeBin(resp$Body, local_path)
      invisible(TRUE)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to download file from S3.",
          "x" = "Bucket: {.val {conn$bucket}}",
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
        Bucket = conn$bucket,
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
          "x" = "Bucket: {.val {conn$bucket}}",
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
      Bucket = conn$bucket,
      Key = full_key
    ),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to read JSON from S3.",
          "x" = "Bucket: {.val {conn$bucket}}",
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
          "x" = "Bucket: {.val {conn$bucket}}",
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
        Bucket = conn$bucket,
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
          "x" = "Bucket: {.val {conn$bucket}}",
          "x" = "Key: {.val {full_key}}",
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
#' Each redirect points to a new `s3://bucket/prefix/datom/` location and
#' may include new credentials. Recurses until no redirect is found.
#'
#' @param conn A `datom_conn` object for the current location.
#' @param max_depth Maximum number of redirects to follow (default 5).
#' @param .depth Internal counter — do not set manually.
#' @return A `datom_conn` object for the resolved final location.
#' @keywords internal
.datom_s3_resolve_redirect <- function(conn, max_depth = 5L, .depth = 0L) {
  if (.depth >= max_depth) {
    cli::cli_abort(
      c(
        "Redirect chain exceeded maximum depth of {max_depth}.",
        "i" = "This may indicate a circular redirect.",
        "i" = "Current location: {.val {conn$bucket}}/{.val {conn$prefix}}"
      )
    )
  }

  redirect_exists <- .datom_s3_exists(conn, ".redirect.json")
  if (!redirect_exists) {
    return(conn)
  }

  redirect <- .datom_s3_read_json(conn, ".redirect.json")

  if (is.null(redirect$redirect_to) || !nzchar(redirect$redirect_to)) {
    redirect_key <- .datom_build_storage_key(conn$prefix, ".redirect.json")
    cli::cli_abort(
      c(
        "Invalid redirect: {.field redirect_to} is missing or empty.",
        "x" = "Bucket: {.val {conn$bucket}}",
        "x" = "Key: {.val {redirect_key}}"
      )
    )
  }

  # Parse redirect_to URI — expected format: s3://bucket/prefix/datom/
  # Strip trailing "datom/" or "datom" to get the prefix
  redirect_uri <- sub("/datom/?$", "", redirect$redirect_to)
  parsed <- .datom_parse_s3_uri(redirect_uri)

  # Build new client if redirect provides credentials
  new_client <- conn$client
  if (!is.null(redirect$credentials)) {
    creds <- redirect$credentials
    if (is.null(creds$access_key_env) || is.null(creds$secret_key_env)) {
      cli::cli_abort(
        c(
          "Invalid redirect credentials: missing {.field access_key_env} or {.field secret_key_env}.",
          "x" = "Redirect from: {.val {conn$bucket}}/{.val {(.datom_build_storage_key(conn$prefix, '.redirect.json'))}}"
        )
      )
    }
    ak <- Sys.getenv(creds$access_key_env, unset = "")
    sk <- Sys.getenv(creds$secret_key_env, unset = "")
    new_client <- .datom_s3_client(ak, sk)
  }

  # Build a new conn for the redirect target
  new_conn <- new_datom_conn(
    project_name = conn$project_name,
    bucket = parsed$bucket,
    prefix = parsed$prefix,
    region = conn$region,
    client = new_client,
    path = conn$path,
    role = conn$role
  )

  # Recurse into the new location
  .datom_s3_resolve_redirect(
    conn = new_conn,
    max_depth = max_depth,
    .depth = .depth + 1L
  )
}