#' Read a tbit Table
#'
#' Unified read function with routing via `routing.json`. Reads from S3
#' metadata cache for data readers.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param name Table name.
#' @param version Optional metadata_sha (tbit version). If NULL, uses current.
#' @param context Optional context for routing (e.g., "default", "cached").
#' @param ... Additional parameters forwarded to routed function.
#'
#' @return Data frame or routed function result.
#' @export
tbit_read <- function(conn,
                      name,
                      version = NULL,
                      context = NULL,
                      ...) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}


#' Write a tbit Table
#'
#' Writes data to a tbit repository. Commits to git, pushes, and syncs to S3.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param data Data frame to write. If NULL with name, does metadata-only sync.
#' @param name Table name. If NULL with NULL data, aliases to
#'   [tbit_sync_routing()].
#' @param metadata Optional list of custom metadata.
#' @param message Optional commit message.
#'
#' @return List with deployment details.
#' @export
tbit_write <- function(conn,
                       data = NULL,
                       name = NULL,
                       metadata = NULL,
                       message = NULL) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # Route based on arguments

  if (is.null(data) && is.null(name)) {
    return(tbit_sync_routing(conn))
  }

  if (is.null(data) && !is.null(name)) {
    return(.tbit_sync_metadata(conn, name))
  }

  if (!is.data.frame(data)) {
    cli::cli_abort("data must be a data frame")
  }

  # TODO: Implement normal write
  stop("Not yet implemented")
}
