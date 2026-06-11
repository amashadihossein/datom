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
