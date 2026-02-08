#' Sync Routing Metadata to S3
#'
#' Updates all metadata in S3 to match git after migration or routing changes.
#' Requires interactive confirmation.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#'
#' @return Summary of updated files.
#' @export
tbit_sync_routing <- function(conn) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}


#' Scan and Prepare Manifest for Sync
#'
#' Scans flat `input_files/` directory and computes SHAs. Checks against
#' manifest for fast no-op detection.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param path Optional path to input_files directory.
#' @param pattern Glob pattern for file matching. Default "*".
#'
#' @return Manifest for review before calling [tbit_sync()].
#' @export
tbit_sync_manifest <- function(conn,
                               path = NULL,
                               pattern = "*") {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}


#' Sync Files to tbit Repository
#'
#' Processes new/changed files from manifest. One commit per table.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param manifest Manifest from [tbit_sync_manifest()].
#' @param continue_on_error If TRUE, continues on individual file errors.
#'
#' @return Updated manifest with results.
#' @export
tbit_sync <- function(conn,
                      manifest,
                      continue_on_error = TRUE) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}
