# Internal local filesystem operations
#
# Low-level filesystem wrappers using fs::.
# Functions accept a `datom_conn` object and a relative key.
# The full path is built via `.datom_build_storage_key()` resolved against
# `conn$root`.


#' Resolve a Storage Key to a Local Path
#'
#' Builds the full filesystem path from `conn$root`, `conn$prefix`, and the
#' relative key segments.
#'
#' @param conn A `datom_conn` object with `backend = "local"`.
#' @param key Relative storage key (after `prefix/datom/`).
#' @return An absolute filesystem path.
#' @keywords internal
.datom_local_path <- function(conn, key) {
  full_key <- .datom_build_storage_key(conn$prefix, key)
  fs::path(conn$root, full_key)
}


#' Upload File to Local Storage
#'
#' Copies a local file to the store directory. Creates parent directories
#' if needed.
#'
#' @param conn A `datom_conn` object with `backend = "local"`.
#' @param local_path Local file path to upload.
#' @param key Relative storage key (after `prefix/datom/`).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_local_upload <- function(conn, local_path, key) {
  if (!fs::file_exists(local_path)) {
    cli::cli_abort("File not found: {.path {local_path}}")
  }

  dest <- .datom_local_path(conn, key)
  fs::dir_create(fs::path_dir(dest))
  fs::file_copy(local_path, dest, overwrite = TRUE)
  invisible(TRUE)
}


#' Download File from Local Storage
#'
#' Copies a file from the store directory to a local path. Creates parent
#' directories if needed.
#'
#' @param conn A `datom_conn` object with `backend = "local"`.
#' @param key Relative storage key (after `prefix/datom/`).
#' @param local_path Local file path (destination).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_local_download <- function(conn, key, local_path) {
  src <- .datom_local_path(conn, key)

  if (!fs::file_exists(src)) {
    cli::cli_abort(
      c(
        "File not found in local store.",
        "x" = "Root: {.path {conn$root}}",
        "x" = "Key: {.val {key}}"
      )
    )
  }

  fs::dir_create(fs::path_dir(local_path))
  fs::file_copy(src, local_path, overwrite = TRUE)
  invisible(TRUE)
}


#' Check if Local Storage Object Exists
#'
#' @param conn A `datom_conn` object with `backend = "local"`.
#' @param key Relative storage key (after `prefix/datom/`).
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.datom_local_exists <- function(conn, key) {
  dest <- .datom_local_path(conn, key)
  unname(fs::file_exists(dest))
}


#' Read and Parse JSON from Local Storage
#'
#' Reads a JSON file from the store and parses it. Uses
#' `simplifyVector = FALSE` to match S3 behavior.
#'
#' @param conn A `datom_conn` object with `backend = "local"`.
#' @param key Relative storage key (after `prefix/datom/`).
#' @return Parsed R list.
#' @keywords internal
.datom_local_read_json <- function(conn, key) {
  dest <- .datom_local_path(conn, key)

  if (!fs::file_exists(dest)) {
    cli::cli_abort(
      c(
        "JSON file not found in local store.",
        "x" = "Root: {.path {conn$root}}",
        "x" = "Key: {.val {key}}"
      )
    )
  }

  tryCatch(
    jsonlite::fromJSON(dest, simplifyVector = FALSE),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to parse JSON from local store.",
          "x" = "Path: {.path {dest}}",
          "i" = "Parse error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
}


#' Write an R List to Local Storage as JSON
#'
#' Serializes `data` to JSON and writes to the store directory. Creates parent
#' directories if needed.
#'
#' @param conn A `datom_conn` object with `backend = "local"`.
#' @param key Relative storage key (after `prefix/datom/`).
#' @param data An R list to serialize to JSON.
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_local_write_json <- function(conn, key, data) {
  dest <- .datom_local_path(conn, key)
  fs::dir_create(fs::path_dir(dest))

  json_text <- jsonlite::toJSON(data, auto_unbox = TRUE, pretty = TRUE)
  writeLines(json_text, dest)
  invisible(TRUE)
}


#' List Objects in Local Storage
#'
#' Lists files under a given prefix in the store.
#'
#' @param conn A `datom_conn` object with `backend = "local"`.
#' @param prefix Relative prefix to list under.
#' @return Character vector of relative keys (relative to `conn$root`).
#' @keywords internal
.datom_local_list_objects <- function(conn, prefix) {
  full_prefix <- .datom_build_storage_key(conn$prefix, prefix)
  search_dir <- fs::path(conn$root, full_prefix)

  if (!fs::dir_exists(search_dir)) return(character(0))

  files <- fs::dir_ls(search_dir, recurse = TRUE, type = "file", all = TRUE)
  # Return keys relative to conn$root
  as.character(fs::path_rel(files, conn$root))
}


#' Delete a File from Local Storage
#'
#' @param conn A `datom_conn` object with `backend = "local"`.
#' @param key Relative storage key (after `prefix/datom/`).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_local_delete <- function(conn, key) {
  dest <- .datom_local_path(conn, key)

  if (fs::file_exists(dest)) {
    fs::file_delete(dest)
  }

  invisible(TRUE)
}
