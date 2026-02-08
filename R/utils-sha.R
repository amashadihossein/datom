# Internal helpers for SHA computation and metadata operations

#' Compute SHA-256 of Data
#'
#' Computes a deterministic SHA-256 hash of a data frame by writing to
#' parquet format. By default, preserves column and row order — reordering
#' either will produce a different hash.
#'
#' @param data Data frame to hash.
#' @param sort_columns If TRUE, sorts columns alphabetically before hashing.
#'   Useful when column order shouldn't affect identity.
#' @param sort_rows If TRUE, sorts rows by all columns before hashing.
#'   Useful when row order shouldn't affect identity.
#' @return Character SHA-256 hash.
#' @keywords internal
.tbit_compute_data_sha <- function(data, sort_columns = FALSE, sort_rows = FALSE) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame.")
  }

  if (ncol(data) == 0L || nrow(data) == 0L) {
    cli::cli_abort("{.arg data} must have at least one row and one column.")
  }

  prepared <- data

  if (sort_columns) {
    col_order <- sort(names(prepared))
    prepared <- prepared[, col_order, drop = FALSE]
  }

  if (sort_rows) {
    row_order <- do.call(order, prepared)
    prepared <- prepared[row_order, , drop = FALSE]
    rownames(prepared) <- NULL
  }

  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  arrow::write_parquet(prepared, tmp)
  digest::digest(file = tmp, algo = "sha256")
}


#' Compute SHA-256 of Metadata
#'
#' Sorts fields alphabetically before hashing for deterministic results,
#' regardless of field insertion order.
#'
#' @param metadata Named list of metadata fields.
#' @return Character SHA-256 hash.
#' @keywords internal
.tbit_compute_metadata_sha <- function(metadata) {
  if (!is.list(metadata) || is.null(names(metadata))) {
    cli::cli_abort("{.arg metadata} must be a named list.")
  }

  field_names <- names(metadata)
  sorted_names <- sort(field_names)
  sorted_metadata <- metadata[sorted_names]
  sha <- digest::digest(sorted_metadata, algo = "sha256")
  sha
}


#' Compute SHA-256 of File
#'
#' @param path Path to file.
#' @return Character SHA-256 hash.
#' @keywords internal
.tbit_compute_file_sha <- function(path) {
  path <- fs::path_abs(path)

  if (!fs::file_exists(path)) {
    cli::cli_abort("File not found: {.path {path}}")
  }

  digest::digest(file = path, algo = "sha256")
}


#' Sync Single Table Metadata to S3
#'
#' @param conn Connection object.
#' @param name Table name.
#' @return Summary of sync operation.
#' @keywords internal
.tbit_sync_metadata <- function(conn, name) {
  # TODO: Implement
  stop("Not yet implemented")
}
