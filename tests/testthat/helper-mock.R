# Test helpers — loaded automatically by testthat before tests run

#' Build a Mock tbit_conn for Testing
#'
#' Creates a minimal `tbit_conn` object wrapping a mock S3 client.
#' The mock client should be a list with mock methods (e.g., `put_object`,
#' `get_object`, `head_object`).
#'
#' @param mock_client A list with mock S3 methods.
#' @param bucket Bucket name (default `"test-bucket"`).
#' @param prefix Prefix (default `"proj"`). Use `NULL` for no prefix.
#' @return A `tbit_conn` object.
mock_tbit_conn <- function(mock_client,
                           bucket = "test-bucket",
                           prefix = "proj") {
  structure(
    list(
      project_name = "test-project",
      bucket = bucket,
      prefix = prefix,
      region = "us-east-1",
      s3_client = mock_client,
      path = NULL,
      role = "reader"
    ),
    class = "tbit_conn"
  )
}
