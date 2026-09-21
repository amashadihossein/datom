# Internal helpers for S3 path construction and parsing

#' Build S3 Object Key
#'
#' Constructs S3 keys from path components, inserting the `datom/` segment
#' per the storage structure convention.
#'
#' Mapping from arguments to key, for reference:
#'
#' ```
#' ("proj", "customers", "abc123.parquet")
#'   -> "proj/datom/customers/abc123.parquet"
#'
#' ("proj", "customers", ".metadata", "metadata.json")
#'   -> "proj/datom/customers/.metadata/metadata.json"
#'
#' ("proj", ".metadata", "dispatch.json")
#'   -> "proj/datom/.metadata/dispatch.json"
#'
#' (NULL, "customers", "abc123.parquet")
#'   -> "datom/customers/abc123.parquet"
#' ```
#'
#' @param prefix Optional S3 prefix (e.g., "project-alpha"). NULL if none.
#' @param ... Path segments after the `datom/` segment (e.g., table name,
#'   file name, ".metadata").
#' @return Character string S3 key.
#' @keywords internal
.datom_build_storage_key <- function(prefix = NULL, ...) {
  segments <- c(...)

  if (length(segments) == 0L) {
    cli::cli_abort("At least one path segment is required after {.arg prefix}.")
  }

  # Remove any leading/trailing slashes from each component
  prefix_clean <- if (!is.null(prefix)) gsub("^/+|/+$", "", prefix) else NULL
  segments_clean <- gsub("^/+|/+$", "", segments)

  # Build: prefix / datom / segments...
  parts <- c(prefix_clean, "datom", segments_clean)

  # Drop any empty strings
  parts <- parts[nzchar(parts)]

  paste(parts, collapse = "/")
}


# --- Relative artifact keys ---------------------------------------------------
#
# Two key shapes exist and are easy to confuse:
#
#   FULL     `{prefix}/datom/{...}`  -- built by `.datom_build_storage_key()`,
#            used only inside the backend layer (`.datom_s3_*`, `.datom_local_*`).
#   RELATIVE `{...}`                 -- what the `.datom_storage_*()` dispatch
#            layer takes, because each backend prepends the full prefix itself.
#
# Business logic therefore must NOT call `.datom_build_storage_key()`: passing a
# full key to `.datom_storage_write_json()` would double-prefix it. The helpers
# below build the relative keys instead, so call sites stop hand-rolling
# `paste0()` and the `.parquet` vs `.json` extension decision lives in one place.
#
# They also apply the `.datom_validate_name()` / `.datom_validate_sha()` guards,
# which several call sites previously omitted -- any caller-influenced value
# spliced into a key can otherwise escape the namespace on the local backend.


#' Build the Relative Key for an Artifact's Payload
#'
#' The stored data object for an artifact: parquet for a table, JSON for a set.
#' This is the single place that decision is made.
#'
#' @param name Artifact name (validated).
#' @param sha Content hash addressing the payload -- `data_sha` (validated as
#'   6-64 hex, since it is spliced into a storage key).
#' @param kind `"table"` (parquet payload) or `"set"` (JSON payload).
#' @return Character relative key, e.g. `"dm/9f2a....parquet"`.
#' @keywords internal
.datom_artifact_payload_key <- function(name, sha, kind = c("table", "set")) {
  kind <- match.arg(kind)
  .datom_validate_name(name)
  .datom_validate_sha(sha, arg = "data_sha")

  ext <- switch(kind, table = ".parquet", set = ".json")
  paste0(name, "/", sha, ext)
}


#' Build the Relative Key for an Artifact's Current-State Metadata
#'
#' @param name Artifact name (validated).
#' @param which `"metadata"` for `metadata.json` (current state) or
#'   `"version_history"` for `version_history.json` (the version index).
#' @return Character relative key, e.g. `"dm/.metadata/metadata.json"`.
#' @keywords internal
.datom_artifact_meta_key <- function(name, which = c("metadata", "version_history")) {
  which <- match.arg(which)
  .datom_validate_name(name)

  paste0(name, "/.metadata/", which, ".json")
}


#' Build the Relative Key for a Versioned Metadata Snapshot
#'
#' Note this is a different directory from the payload key: the snapshot lives
#' under `.metadata/` and is addressed by `metadata_sha` (the version), whereas
#' the payload sits beside it addressed by `data_sha` (the content). Both end in
#' `.json` for a set, which is exactly why they are easy to confuse.
#'
#' @param name Artifact name (validated).
#' @param metadata_sha The version (validated as 6-64 hex).
#' @return Character relative key, e.g. `"dm/.metadata/c3d4....json"`.
#' @keywords internal
.datom_artifact_snapshot_key <- function(name, metadata_sha) {
  .datom_validate_name(name)
  .datom_validate_sha(metadata_sha, arg = "version")

  paste0(name, "/.metadata/", metadata_sha, ".json")
}


#' Parse S3 URI into Components
#'
#' Extracts bucket and prefix from an `s3://` URI.
#'
#' Mapping from URI to components, for reference:
#'
#' ```
#' "s3://my-bucket/data/proj" -> list(bucket = "my-bucket", prefix = "data/proj")
#' "s3://my-bucket"           -> list(bucket = "my-bucket", prefix = NULL)
#' ```
#'
#' @param uri Character string S3 URI (e.g., "s3://my-bucket/prefix/path").
#' @return Named list with `bucket` (character) and `prefix` (character or NULL).
#' @keywords internal
.datom_parse_s3_uri <- function(uri) {
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
#' @param key S3 object key (from `.datom_build_storage_key()`).
#' @return Character string S3 URI.
#' @keywords internal
.datom_build_s3_uri <- function(bucket, key) {
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
#' @param backend Storage backend (`"s3"` or `"local"`).
#' @param root Storage root (S3 bucket name or local directory path).
#' @param prefix Storage prefix (can be NULL).
#' @param region AWS region string (NULL for local backend).
#' @param remote_url Git remote URL.
#' @param gov Governance store component (e.g. from `datom_store_s3()`), or
#'   `NULL` for a solo project with no governance attached. Determines whether
#'   the rendered store snippets use `governance = NULL` or a gov-store
#'   constructor.
#'
#' @return Character string — the rendered README content.
#' @keywords internal
.datom_render_readme <- function(project_name,
                                backend = "s3",
                                root,
                                prefix,
                                region = NULL,
                                remote_url,
                                gov = NULL) {
  template_path <- system.file(
    "templates", "README.md",
    package = "datom",
    mustWork = TRUE
  )

  template <- paste(readLines(template_path, warn = FALSE), collapse = "\n")

  prefix_display <- if (is.null(prefix)) "*(none)*" else paste0("`", prefix, "`")
  prefix_code <- if (is.null(prefix)) "NULL" else paste0('"', prefix, '"')
  region_display <- region %||% "*(n/a)*"

  # Store constructor snippet for README
  if (backend == "local") {
    store_constructor <- paste0('datom_store_local("', root, '", ', prefix_code, ')')
  } else {
    store_constructor <- paste0(
      'datom_store_s3("', root, '", ', prefix_code, ', "',
      region_display, '", access_key = "...", secret_key = "...")'
    )
  }

  # Governance constructor snippet: NULL for a solo project (gov-on-demand,
  # not yet attached), or a constructor mirroring the attached gov component.
  gov_constructor <- if (is.null(gov)) {
    "NULL"
  } else {
    .datom_store_constructor_snippet(gov)
  }

  glue::glue(
    template,
    project_name      = project_name,
    backend           = backend,
    root              = root,
    prefix_display    = prefix_display,
    prefix_code       = prefix_code,
    region            = region_display,
    remote_url        = remote_url,
    store_constructor = store_constructor,
    gov_constructor   = gov_constructor,
    created_at        = format(Sys.Date(), "%Y-%m-%d"),
    datom_version     = as.character(utils::packageVersion("datom")),
    .open  = "{{{",
    .close = "}}}"
  )
}


#' Build a Store-Constructor Snippet for a Component
#'
#' Renders a copy/paste `datom_store_local(...)` or `datom_store_s3(...)` call
#' string for a store component, for embedding in a generated README. Secrets
#' are shown as placeholders.
#'
#' @param component A store component (`datom_store_local`, `datom_store_s3`,
#'   or `datom_store_s3_creds`).
#' @return Character scalar — an R constructor call as text.
#' @keywords internal
.datom_store_constructor_snippet <- function(component) {
  backend <- .datom_store_backend(component)
  prefix  <- component$prefix
  prefix_code <- if (is.null(prefix)) "NULL" else paste0('"', prefix, '"')

  if (backend == "local") {
    return(paste0('datom_store_local("', .datom_store_root(component), '", ',
                  prefix_code, ')'))
  }

  # s3 / s3_creds
  if (inherits(component, "datom_store_s3_creds")) {
    return('datom_store_s3_creds(access_key = "...", secret_key = "...")')
  }

  region <- .datom_store_region(component) %||% "us-east-1"
  paste0('datom_store_s3("', .datom_store_root(component), '", ', prefix_code,
         ', "', region, '", access_key = "...", secret_key = "...")')
}
