# Test helpers — loaded automatically by testthat before tests run

#' Build a Mock datom_conn for Testing
#'
#' Creates a minimal `datom_conn` object wrapping a mock S3 client.
#' The mock client should be a list with mock methods (e.g., `put_object`,
#' `get_object`, `head_object`).
#'
#' @param mock_client A list with mock S3 methods.
#' @param bucket Bucket name (default `"test-bucket"`).
#' @param prefix Prefix (default `"proj"`). Use `NULL` for no prefix.
#' @return A `datom_conn` object.
mock_datom_conn <- function(mock_client,
                           bucket = "test-bucket",
                           prefix = "proj",
                           gov_bucket = NULL,
                           gov_prefix = NULL,
                           gov_region = NULL,
                           gov_s3_client = NULL) {
  structure(
    list(
      project_name = "test-project",
      bucket = bucket,
      prefix = prefix,
      region = "us-east-1",
      s3_client = mock_client,
      path = NULL,
      role = "reader",
      endpoint = NULL,
      gov_bucket = gov_bucket,
      gov_prefix = gov_prefix,
      gov_region = gov_region,
      gov_s3_client = gov_s3_client
    ),
    class = "datom_conn"
  )
}
