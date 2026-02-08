#' List Available Tables
#'
#' Lists tables from S3 manifest.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param pattern Optional glob pattern for filtering.
#' @param include_versions If TRUE, includes version count info.
#'
#' @return Data frame with table info.
#' @export
tbit_list <- function(conn,
                      pattern = NULL,
                      include_versions = FALSE) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}


#' Show Version History
#'
#' Shows version history for a table including author and commit message.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param name Table name.
#' @param n Maximum number of versions to return. Default 10.
#'
#' @return Data frame with version details.
#' @export
tbit_history <- function(conn,
                         name,
                         n = 10) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}


#' Show Repository Status
#'
#' Shows uncommitted changes and sync state.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#'
#' @return Status summary (printed, returns invisibly).
#' @export
tbit_status <- function(conn) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}
