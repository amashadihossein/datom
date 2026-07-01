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
                           root = "test-bucket",
                           prefix = "proj",
                           gov_root = NULL,
                           gov_prefix = NULL,
                           gov_region = NULL,
                           gov_backend = NULL,
                           gov_client = NULL) {
  structure(
    list(
      project_name = "test-project",
      backend = "s3",
      root = root,
      prefix = prefix,
      region = "us-east-1",
      client = mock_client,
      path = NULL,
      role = "reader",
      endpoint = NULL,
      gov_root = gov_root,
      gov_prefix = gov_prefix,
      gov_region = gov_region,
      gov_backend = gov_backend,
      gov_client = gov_client
    ),
    class = "datom_conn"
  )
}

#' Evaluate a connection-creating expression, muffling only the benign,
#' well-understood conn-time warnings.
#'
#' `datom_get_conn()` / `datom_clone()` emit two expected warnings for the
#' mock / local fixtures used throughout the suite:
#'   * "... has no governance attached ..." (a `store$governance` is supplied
#'     but no governance is actually attached), plus its paired
#'     "credentials supplied will be ignored" note; and
#'   * "Could not resolve ref.json ..." (the mock governance store has no
#'     `ref.json`, so conn-time ref resolution is warn-only).
#'
#' These are incidental to what most connection tests assert (conn fields,
#' roles, endpoints, project names). This helper muffles ONLY those messages;
#' any other warning propagates so genuine regressions stay visible (the
#' suite targets WARN 0). Tests that specifically assert one of these warnings
#' pass a narrower `pattern` so the asserted warning still reaches
#' `expect_warning()`.
#'
#' @param expr Expression that creates a connection.
#' @param pattern Regex of warning messages to muffle.
#' @return The value of `expr`.
muffle_conn_warnings <- function(
    expr,
    pattern = "has no governance attached|credentials supplied will be ignored|Could not resolve ref\\.json") {
  withCallingHandlers(
    expr,
    warning = function(w) {
      if (grepl(pattern, conditionMessage(w))) invokeRestart("muffleWarning")
    }
  )
}
