# Internal helpers for S3 path construction and parsing

#' Build S3 Object Key
#'
#' Constructs S3 keys from path components, inserting the `tbit/` segment
#' per the storage structure convention.
#'
#' @param prefix Optional S3 prefix (e.g., "project-alpha"). NULL if none.
#' @param ... Path segments after the `tbit/` segment (e.g., table name,
#'   file name, ".metadata").
#' @return Character string S3 key.
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' # Data file
#' .tbit_build_s3_key("proj", "customers", "abc123.parquet")
#' # → "proj/tbit/customers/abc123.parquet"
#'
#' # Table metadata
#' .tbit_build_s3_key("proj", "customers", ".metadata", "metadata.json")
#' # → "proj/tbit/customers/.metadata/metadata.json"
#'
#' # Repo-level metadata
#' .tbit_build_s3_key("proj", ".metadata", "routing.json")
#' # → "proj/tbit/.metadata/routing.json"
#'
#' # No prefix
#' .tbit_build_s3_key(NULL, "customers", "abc123.parquet")
#' # → "tbit/customers/abc123.parquet"
#' }
.tbit_build_s3_key <- function(prefix = NULL, ...) {
  segments <- c(...)

  if (length(segments) == 0L) {
    cli::cli_abort("At least one path segment is required after {.arg prefix}.")
  }

  # Remove any leading/trailing slashes from each component
  prefix_clean <- if (!is.null(prefix)) gsub("^/+|/+$", "", prefix) else NULL
  segments_clean <- gsub("^/+|/+$", "", segments)

  # Build: prefix / tbit / segments...
  parts <- c(prefix_clean, "tbit", segments_clean)

  # Drop any empty strings
  parts <- parts[nzchar(parts)]

  paste(parts, collapse = "/")
}


#' Parse S3 URI into Components
#'
#' Extracts bucket and prefix from an `s3://` URI.
#'
#' @param uri Character string S3 URI (e.g., "s3://my-bucket/prefix/path").
#' @return Named list with `bucket` (character) and `prefix` (character or NULL).
#' @keywords internal
#'
#' @examples
#' \dontrun{
#' .tbit_parse_s3_uri("s3://my-bucket/data/proj")
#' # → list(bucket = "my-bucket", prefix = "data/proj")
#'
#' .tbit_parse_s3_uri("s3://my-bucket")
#' # → list(bucket = "my-bucket", prefix = NULL)
#' }
.tbit_parse_s3_uri <- function(uri) {
  if (!is.character(uri) || length(uri) != 1L) {
    cli::cli_abort("{.arg uri} must be a single character string.")
  }

  if (!grepl("^s3://", uri)) {
    cli::cli_abort("{.arg uri} must start with {.val s3://}. Got: {.val {uri}}")
  }

  # Strip scheme
  stripped <- sub("^s3://", "", uri)

  # Remove trailing slashes
  stripped <- gsub("/+$", "", stripped)

  if (!nzchar(stripped)) {
    cli::cli_abort("{.arg uri} must include a bucket name.")
  }

  # Split on first slash
  slash_pos <- regexpr("/", stripped)

  if (slash_pos == -1L) {
    # No prefix — bucket only
    bucket <- stripped
    prefix <- NULL
  } else {
    bucket <- substr(stripped, 1L, slash_pos - 1L)
    prefix <- substr(stripped, slash_pos + 1L, nchar(stripped))
    # Clean up any double slashes in prefix
    prefix <- gsub("/+", "/", prefix)
    if (!nzchar(prefix)) prefix <- NULL
  }

  list(bucket = bucket, prefix = prefix)
}


#' Build Full S3 URI
#'
#' Convenience function that combines bucket and key into an S3 URI.
#'
#' @param bucket S3 bucket name.
#' @param key S3 object key (from `.tbit_build_s3_key()`).
#' @return Character string S3 URI.
#' @keywords internal
.tbit_build_s3_uri <- function(bucket, key) {
  if (!is.character(bucket) || !nzchar(bucket)) {
    cli::cli_abort("{.arg bucket} must be a non-empty string.")
  }
  if (!is.character(key) || !nzchar(key)) {
    cli::cli_abort("{.arg key} must be a non-empty string.")
  }

  paste0("s3://", bucket, "/", key)
}


#' Render README.md from Template
#'
#' Reads the template from `inst/templates/README.md` and fills in
#' project-specific values using `{{{ }}}` delimiters.
#'
#' @param project_name Project name string.
#' @param bucket S3 bucket name.
#' @param prefix S3 prefix (can be NULL).
#' @param region AWS region string.
#' @param remote_url Git remote URL.
#' @param cred_names Named list with `access_key_env` and `secret_key_env`.
#'
#' @return Character string — the rendered README content.
#' @keywords internal
.tbit_render_readme <- function(project_name,
                                bucket,
                                prefix,
                                region,
                                remote_url,
                                cred_names) {
  template_path <- system.file(
    "templates", "README.md",
    package = "tbit",
    mustWork = TRUE
  )

  template <- paste(readLines(template_path, warn = FALSE), collapse = "\n")

  prefix_display <- if (is.null(prefix)) "*(none)*" else paste0("`", prefix, "`")
  prefix_code <- if (is.null(prefix)) "NULL" else paste0('"', prefix, '"')

  glue::glue(
    template,
    project_name   = project_name,
    bucket         = bucket,
    prefix_display = prefix_display,
    prefix_code    = prefix_code,
    region         = region,
    remote_url     = remote_url,
    access_key_env = cred_names[["access_key_env"]],
    secret_key_env = cred_names[["secret_key_env"]],
    created_at     = format(Sys.Date(), "%Y-%m-%d"),
    tbit_version   = as.character(utils::packageVersion("tbit")),
    .open  = "{{{",
    .close = "}}}"
  )
}
