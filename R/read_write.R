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
    cli::cli_abort("{.arg conn} must be a {.cls tbit_conn} object from {.fn tbit_get_conn}.")
  }

  .tbit_validate_name(name)

  # 1. Read metadata + version history from S3
  metadata_list <- .tbit_read_metadata(conn, name)

  # 2. Resolve version to data_sha

  data_sha <- .tbit_resolve_version(metadata_list, version = version, name = name)

  # 3. Download and read parquet
  # TODO: Phase 6 will add routing via context + routing.json
  .tbit_read_parquet(conn, name, data_sha)
}


# --- Read infrastructure ------------------------------------------------------

#' Read Table Metadata from S3
#'
#' Fetches both `metadata.json` (current state) and `version_history.json`
#' (version index) for a given table from S3.
#'
#' @param conn A `tbit_conn` object.
#' @param name Table name (validated).
#' @return Named list with `current` (metadata.json contents) and
#'   `history` (version_history.json contents as a list of entries).
#' @keywords internal
.tbit_read_metadata <- function(conn, name) {
  .tbit_validate_name(name)

  metadata_key <- paste0(name, "/.metadata/metadata.json")
  history_key <- paste0(name, "/.metadata/version_history.json")

  current <- .tbit_s3_read_json(conn, metadata_key)
  history <- .tbit_s3_read_json(conn, history_key)

  list(current = current, history = history)
}


#' Resolve Version to data_sha
#'
#' Given metadata from [.tbit_read_metadata()], resolves a version spec
#' to the corresponding `data_sha`. If `version` is NULL, returns the
#' current `data_sha` from `metadata.json`. If a metadata_sha string,
#' looks it up in `version_history.json`.
#'
#' @param metadata_list Return value of [.tbit_read_metadata()].
#' @param version NULL (current) or a metadata_sha string.
#' @param name Table name (for error messages).
#' @return Character string `data_sha`.
#' @keywords internal
.tbit_resolve_version <- function(metadata_list, version = NULL, name = "table") {
  if (is.null(version)) {
    data_sha <- metadata_list$current$data_sha
    if (is.null(data_sha) || !nzchar(data_sha)) {
      cli::cli_abort(
        c(
          "metadata.json for {.val {name}} has no {.field data_sha}.",
          "i" = "The metadata may be corrupt or the table has no data."
        )
      )
    }
    return(data_sha)
  }

  if (!is.character(version) || length(version) != 1L || !nzchar(version)) {
    cli::cli_abort("{.arg version} must be a single non-empty string or NULL.")
  }

  # Look up version (metadata_sha) in history
  history <- metadata_list$history
  if (!is.list(history) || length(history) == 0L) {
    cli::cli_abort(
      c(
        "No version history found for {.val {name}}.",
        "i" = "version_history.json is empty or missing."
      )
    )
  }

  # history is a list of entries; each has $version and $data_sha
  match_idx <- purrr::detect_index(history, ~ identical(.x$version, version))

  if (match_idx == 0L) {
    cli::cli_abort(
      c(
        "Version {.val {version}} not found in history for {.val {name}}.",
        "i" = "Use {.fn tbit_history} to see available versions."
      )
    )
  }

  data_sha <- history[[match_idx]]$data_sha
  if (is.null(data_sha) || !nzchar(data_sha)) {
    cli::cli_abort(
      c(
        "Version {.val {version}} has no {.field data_sha} in history.",
        "i" = "The version_history.json entry may be corrupt."
      )
    )
  }

  data_sha
}


#' Download and Read Parquet from S3
#'
#' Downloads `{table}/{data_sha}.parquet` from S3 to a temporary file
#' and reads it via `arrow::read_parquet()`.
#'
#' @param conn A `tbit_conn` object.
#' @param name Table name.
#' @param data_sha SHA identifying the parquet file.
#' @return Data frame.
#' @keywords internal
.tbit_read_parquet <- function(conn, name, data_sha) {
  .tbit_validate_name(name)

  if (!is.character(data_sha) || length(data_sha) != 1L || !nzchar(data_sha)) {
    cli::cli_abort("{.arg data_sha} must be a single non-empty string.")
  }

  s3_key <- paste0(name, "/", data_sha, ".parquet")
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  .tbit_s3_download(conn, s3_key, tmp)

  arrow::read_parquet(tmp)
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
