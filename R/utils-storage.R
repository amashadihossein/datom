# Storage dispatch layer
#
# Generic storage operations that dispatch to backend-specific implementations
# based on `conn$backend`. Business logic calls these — never the backend
# functions directly (e.g. `.datom_s3_upload()`).
#
# Currently supports: "s3", "local"


#' Upload File to Storage
#'
#' @param conn A `datom_conn` object.
#' @param local_path Local file path to upload.
#' @param key Relative storage key (after `prefix/datom/`).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_storage_upload <- function(conn, local_path, key) {
  backend <- conn$backend %||% "s3"
  switch(backend,
    s3 = .datom_s3_upload(conn, local_path, key),
    local = .datom_local_upload(conn, local_path, key),
    cli::cli_abort("Unsupported storage backend: {.val {backend}}")
  )
}


#' Download File from Storage
#'
#' @param conn A `datom_conn` object.
#' @param key Relative storage key (after `prefix/datom/`).
#' @param local_path Local file path (destination).
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_storage_download <- function(conn, key, local_path) {
  backend <- conn$backend %||% "s3"
  switch(backend,
    s3 = .datom_s3_download(conn, key, local_path),
    local = .datom_local_download(conn, key, local_path),
    cli::cli_abort("Unsupported storage backend: {.val {backend}}")
  )
}


#' Check if Storage Object Exists
#'
#' @param conn A `datom_conn` object.
#' @param key Relative storage key (after `prefix/datom/`).
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.datom_storage_exists <- function(conn, key) {
  backend <- conn$backend %||% "s3"
  switch(backend,
    s3 = .datom_s3_exists(conn, key),
    local = .datom_local_exists(conn, key),
    cli::cli_abort("Unsupported storage backend: {.val {backend}}")
  )
}


#' Read and Parse JSON from Storage
#'
#' @param conn A `datom_conn` object.
#' @param key Relative storage key (after `prefix/datom/`).
#' @return Parsed R list.
#' @keywords internal
.datom_storage_read_json <- function(conn, key) {
  backend <- conn$backend %||% "s3"
  switch(backend,
    s3 = .datom_s3_read_json(conn, key),
    local = .datom_local_read_json(conn, key),
    cli::cli_abort("Unsupported storage backend: {.val {backend}}")
  )
}


#' Write an R List to Storage as JSON
#'
#' @param conn A `datom_conn` object.
#' @param key Relative storage key (after `prefix/datom/`).
#' @param data An R list to serialize to JSON.
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_storage_write_json <- function(conn, key, data) {
  backend <- conn$backend %||% "s3"
  switch(backend,
    s3 = .datom_s3_write_json(conn, key, data),
    local = .datom_local_write_json(conn, key, data),
    cli::cli_abort("Unsupported storage backend: {.val {backend}}")
  )
}


#' Delete All Objects Under a Storage Prefix
#'
#' Removes every file under `prefix/datom/{prefix_key}` from storage.
#' For S3 this lists then batch-deletes. For local it removes the directory.
#' A missing prefix is a no-op (returns 0L). Pass `prefix_key = NULL` to
#' delete the entire datom namespace for this connection.
#'
#' @param conn A `datom_conn` object.
#' @param prefix_key Relative prefix to delete under (after `prefix/datom/`).
#'   `NULL` deletes the entire datom namespace root.
#' @return Invisibly, the count of deleted objects.
#' @keywords internal
.datom_storage_delete_prefix <- function(conn, prefix_key = NULL) {
  backend <- conn$backend %||% "s3"
  switch(backend,
    s3    = .datom_s3_delete_prefix(conn, prefix_key),
    local = .datom_local_delete_prefix(conn, prefix_key),
    cli::cli_abort("Unsupported storage backend: {.val {backend}}")
  )
}
