# Internal helpers for SHA computation and metadata operations

#' Compute SHA-256 of Data
#'
#' @param data Data frame to hash.
#' @return Character SHA-256 hash.
#' @keywords internal
.tbit_compute_data_sha <- function(data) {
  # Write to temp parquet, compute hash
 tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  arrow::write_parquet(data, tmp)
  digest::digest(file = tmp, algo = "sha256")
}


#' Compute SHA-256 of Metadata
#'
#' Sorts fields alphabetically before hashing for deterministic results.
#'
#' @param metadata List of metadata fields.
#' @return Character SHA-256 hash.
#' @keywords internal
.tbit_compute_metadata_sha <- function(metadata) {
  sorted <- metadata[order(names(metadata))]
  digest::digest(sorted, algo = "sha256")
}


#' Compute SHA-256 of File
#'
#' @param path Path to file.
#' @return Character SHA-256 hash.
#' @keywords internal
.tbit_compute_file_sha <- function(path) {
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
