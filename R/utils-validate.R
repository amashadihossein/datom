# Internal validation helpers

# Reserved names that cannot be used as table names
.datom_reserved_names <- c(
  ".metadata", ".datom", "input_files", "datom",
  ".git", ".gitignore", "renv"
)


#' Validate a datom Table Name
#'
#' Checks that a table name is filesystem-safe and S3-safe. Returns the
#' name invisibly on success, errors with a clear message on failure.
#'
#' @param name Character string to validate as a table name.
#' @return Invisible `name` on success.
#' @keywords internal
.datom_validate_name <- function(name) {
  if (!is.character(name) || length(name) != 1L || is.na(name)) {
    cli::cli_abort("{.arg name} must be a single non-NA character string.")
  }

  if (!nzchar(name)) {
    cli::cli_abort("{.arg name} must not be empty.")
  }

  if (nchar(name) > 128L) {
    cli::cli_abort(
      "{.arg name} must be 128 characters or fewer (got {nchar(name)})."
    )
  }

  if (!grepl("^[a-zA-Z]", name)) {
    cli::cli_abort(
      "{.arg name} must start with a letter. Got: {.val {name}}"
    )
  }

  if (!grepl("^[a-zA-Z][a-zA-Z0-9_ ()-]*$", name)) {
    cli::cli_abort(
      "{.arg name} may only contain letters, numbers, underscores, hyphens, spaces, and parentheses. Got: {.val {name}}"
    )
  }

  name_lower <- tolower(name)
  if (name_lower %in% .datom_reserved_names) {
    cli::cli_abort(
      "{.val {name}} is a reserved name and cannot be used as a table name."
    )
  }

  invisible(name)
}


#' Validate a SHA-Like Input (Version / data_sha)
#'
#' Ensures a user-supplied SHA-like string is 6-64 lowercase hex characters.
#' Used to guard values that get spliced into a storage key (`{table}/{sha}`)
#' -- on the local backend an unvalidated value like `"../../x"` would escape
#' the namespace via `fs::path()`. The 6-char minimum still covers the short
#' prefixes `.datom_resolve_version()` intentionally accepts.
#'
#' @param x Value to validate.
#' @param arg Name of the calling argument, used in the error message.
#' @return Invisible `x` on success. Aborts otherwise.
#' @keywords internal
.datom_validate_sha <- function(x, arg = "version") {
  if (!is.character(x) || length(x) != 1L || is.na(x) ||
      !grepl("^[0-9a-f]{6,64}$", x)) {
    cli::cli_abort("{.arg {arg}} must be 6-64 lowercase hex characters.")
  }
  invisible(x)
}


#' Validate a Caller-Supplied Relative Storage Key
#'
#' Guards a whole key string that a caller composed, as opposed to one datom
#' built itself from validated parts. The internal key builders in
#' `R/utils-path.R` need no such check: `.datom_validate_name()` admits only
#' `[a-zA-Z0-9_ ()-]` and `.datom_validate_sha()` only hex, so their output
#' cannot contain a `..` segment or a `datom/` segment. A key arriving through
#' a public export has had no such filtering.
#'
#' Two distinct failures are caught:
#'
#' * **Traversal / shape.** A `..` segment or a leading `/` escapes the datom
#'   namespace on the local backend, where the key is pasted into a path and
#'   resolved by the filesystem (`.datom_local_path()`). This applies to reads
#'   as much as to writes -- reading `../../secrets.json` is exactly the sort
#'   of probe the guard sweep in #74 existed to close.
#' * **A full key passed where a relative one belongs.** The two key shapes are
#'   documented at the top of `R/utils-path.R`; mixing them does not error
#'   today, it resolves under `{prefix}/datom/{prefix}/datom/...` and finds
#'   nothing, which reads to the caller as a missing object rather than a
#'   malformed key. A `datom` path segment is the detectable form, and it can
#'   never occur in a legitimate relative key because `datom` is a reserved
#'   artifact name (`.datom_reserved_names`).
#'
#' @param key Value to validate as a relative storage key.
#' @param arg Name of the calling argument, used in the error message.
#' @return Invisible `key` on success. Aborts otherwise.
#' @keywords internal
.datom_validate_rel_key <- function(key, arg = "key") {
  if (!is.character(key) || length(key) != 1L || is.na(key)) {
    cli::cli_abort("{.arg {arg}} must be a single non-NA character string.")
  }

  if (!nzchar(key)) {
    cli::cli_abort("{.arg {arg}} must not be empty.")
  }

  if (grepl("^/", key)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a relative storage key, not an absolute path.",
        "x" = "Got: {.val {key}}",
        "i" = "Drop the leading {.val /}: keys are resolved under the datom namespace."
      )
    )
  }

  segments <- strsplit(key, "/", fixed = TRUE)[[1]]

  if (any(segments == "..")) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must not contain a {.val ..} path segment.",
        "x" = "Got: {.val {key}}",
        "i" = "Keys are confined to this project's datom namespace."
      )
    )
  }

  if (any(segments == "datom")) {
    cli::cli_abort(
      c(
        "{.arg {arg}} looks like a full storage key, not a relative one.",
        "x" = "Got: {.val {key}}",
        "i" = "Relative keys start after {.val {{prefix}}/datom/} -- e.g. {.val dm/.metadata/metadata.json}, not {.val proj/datom/dm/.metadata/metadata.json}.",
        "i" = "Passing a full key resolves under {.val {{prefix}}/datom/{{prefix}}/datom/} and finds nothing."
      )
    )
  }

  invisible(key)
}


# --- S3 namespace safety -------------------------------------------------------

#' Check Whether an S3 Namespace is Free
#'
#' Checks for the existence of `.metadata/manifest.json` in the target S3
#' namespace. If found, the namespace is occupied by an existing datom project.
#' Returns `TRUE` if the namespace is free. Aborts with an actionable error
#' if occupied, showing the existing project name when possible.
#'
#' Uses `head_object` first (cheap) and only reads the manifest (via
#' `get_object`) when the namespace is occupied, to extract the project name
#' for the error message.
#'
#' @param conn A `datom_conn` object (typically a temporary conn built by
#'   `datom_init_repo()` before the repo is fully initialised).
#' @return Invisible `TRUE` if the namespace is free.
#' @keywords internal
.datom_check_namespace_free <- function(conn) {
  occupied <- .datom_storage_exists(conn, ".metadata/manifest.json")

  if (!occupied) return(invisible(TRUE))

  # Namespace is occupied — try to read the project name for a helpful message

  existing_project <- tryCatch({
    manifest <- .datom_storage_read_json(conn, ".metadata/manifest.json")
    manifest$project_name %||% "<unknown>"
  }, error = function(e) {
    "<unreadable>"
  })

  s3_location <- paste0(
    "s3://", conn$root, "/",
    if (!is.null(conn$prefix)) paste0(gsub("/+$", "", conn$prefix), "/") else "",
    "datom/"
  )

  cli::cli_abort(c(
    "S3 namespace is already occupied by project {.val {existing_project}}.",
    "x" = "Location: {.val {s3_location}}",
    "i" = "Each datom project must use a unique S3 namespace (bucket + prefix).",
    "i" = "Use a different {.arg prefix} or {.arg bucket}, or pass {.code .force = TRUE} to override."
  ))
}
