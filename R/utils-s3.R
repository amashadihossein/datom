# Internal S3 operations
#
# Low-level S3 wrappers around paws.storage.
# Functions accept a `tbit_conn` object and an `s3_key` relative to
# `prefix/tbit/`. The full key is built internally via `.tbit_build_s3_key()`.


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
#' @param conn A `tbit_conn` object.
#' @param local_path Local file path to upload.
#' @param s3_key Relative S3 key (after `prefix/tbit/`).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.tbit_s3_upload <- function(conn, local_path, s3_key) {
  if (!fs::file_exists(local_path)) {
    cli::cli_abort(
      "File not found: {.path {local_path}}"
    )
  }

  full_key <- .tbit_build_s3_key(conn$prefix, s3_key)
  body <- readBin(local_path, what = "raw", n = fs::file_size(local_path))

  tryCatch(
    {
      conn$s3_client$put_object(
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
#' @param conn A `tbit_conn` object.
#' @param s3_key Relative S3 key (after `prefix/tbit/`).
#' @param local_path Local file path (destination).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.tbit_s3_download <- function(conn, s3_key, local_path) {
  full_key <- .tbit_build_s3_key(conn$prefix, s3_key)
  fs::dir_create(fs::path_dir(local_path))

  tryCatch(
    {
      resp <- conn$s3_client$get_object(
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
#' @param conn A `tbit_conn` object.
#' @param s3_key Relative S3 key (after `prefix/tbit/`).
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.tbit_s3_exists <- function(conn, s3_key) {
  full_key <- .tbit_build_s3_key(conn$prefix, s3_key)

  tryCatch(
    {
      conn$s3_client$head_object(
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
#' how `.tbit_s3_write_json()` writes them).
#'
#' @param conn A `tbit_conn` object.
#' @param s3_key Relative S3 key (after `prefix/tbit/`).
#' @return Parsed R list.
#' @keywords internal
.tbit_s3_read_json <- function(conn, s3_key) {
  full_key <- .tbit_build_s3_key(conn$prefix, s3_key)

  resp <- tryCatch(
    conn$s3_client$get_object(
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
#' @param conn A `tbit_conn` object.
#' @param s3_key Relative S3 key (after `prefix/tbit/`).
#' @param data An R list to serialize to JSON.
#' @return Invisible `TRUE` on success.
#' @keywords internal
.tbit_s3_write_json <- function(conn, s3_key, data) {
  full_key <- .tbit_build_s3_key(conn$prefix, s3_key)
  json_raw <- charToRaw(
    jsonlite::toJSON(data, auto_unbox = TRUE, pretty = TRUE)
  )

  tryCatch(
    {
      conn$s3_client$put_object(
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
#' Each redirect points to a new `s3://bucket/prefix/tbit/` location and
#' may include new credentials. Recurses until no redirect is found.
#'
#' @param conn A `tbit_conn` object for the current location.
#' @param max_depth Maximum number of redirects to follow (default 5).
#' @param .depth Internal counter — do not set manually.
#' @return A `tbit_conn` object for the resolved final location.
#' @keywords internal
.tbit_s3_resolve_redirect <- function(conn, max_depth = 5L, .depth = 0L) {
  if (.depth >= max_depth) {
    cli::cli_abort(
      c(
        "Redirect chain exceeded maximum depth of {max_depth}.",
        "i" = "This may indicate a circular redirect.",
        "i" = "Current location: {.val {conn$bucket}}/{.val {conn$prefix}}"
      )
    )
  }

  redirect_exists <- .tbit_s3_exists(conn, ".redirect.json")
  if (!redirect_exists) {
    return(conn)
  }

  redirect <- .tbit_s3_read_json(conn, ".redirect.json")

  if (is.null(redirect$redirect_to) || !nzchar(redirect$redirect_to)) {
    redirect_key <- .tbit_build_s3_key(conn$prefix, ".redirect.json")
    cli::cli_abort(
      c(
        "Invalid redirect: {.field redirect_to} is missing or empty.",
        "x" = "Bucket: {.val {conn$bucket}}",
        "x" = "Key: {.val {redirect_key}}"
      )
    )
  }

  # Parse redirect_to URI — expected format: s3://bucket/prefix/tbit/
  # Strip trailing "tbit/" or "tbit" to get the prefix
  redirect_uri <- sub("/tbit/?$", "", redirect$redirect_to)
  parsed <- .tbit_parse_s3_uri(redirect_uri)

  # Build new client if redirect provides credentials
  new_client <- conn$s3_client
  if (!is.null(redirect$credentials)) {
    creds <- redirect$credentials
    if (is.null(creds$access_key_env) || is.null(creds$secret_key_env)) {
      cli::cli_abort(
        c(
          "Invalid redirect credentials: missing {.field access_key_env} or {.field secret_key_env}.",
          "x" = "Redirect from: {.val {conn$bucket}}/{.val {(.tbit_build_s3_key(conn$prefix, '.redirect.json'))}}"
        )
      )
    }
    new_client <- .tbit_s3_client(creds)
  }

  # Build a new conn for the redirect target
  new_conn <- new_tbit_conn(
    project_name = conn$project_name,
    bucket = parsed$bucket,
    prefix = parsed$prefix,
    region = conn$region,
    s3_client = new_client,
    path = conn$path,
    role = conn$role
  )

  # Recurse into the new location
  .tbit_s3_resolve_redirect(
    conn = new_conn,
    max_depth = max_depth,
    .depth = .depth + 1L
  )
}