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

#' One artifact as storage holds it: its current-state document and its history.
#'
#' Only the fields a manifest rebuild copies are populated. The point is that a
#' reconstruction has a real recorded `version` to read rather than a hash it
#' computed for itself, which is the property AC37(e) pins.
#'
#' @param version The recorded version of the current state.
#' @param data_sha Content identity of the current state.
#' @param created_at Timestamp the history entry copies verbatim.
#' @param size_bytes Stored size, aggregated by the summary counters.
#' @param older Extra, older history entries -- each a list with at least
#'   `version` and `data_sha`. Prepend order matches datom's: newest first.
#' @param extra_meta Extra top-level metadata fields (e.g. `original_format`).
#' @return A list with `metadata` and `history`.
mock_stored_artifact <- function(version = strrep("b", 64L),
                                 data_sha = strrep("a", 64L),
                                 created_at = "2026-01-01T00:00:00Z",
                                 size_bytes = 128,
                                 older = list(),
                                 extra_meta = list()) {
  # modifyList, not c(): `extra_meta` has to be able to OVERRIDE a field, and
  # concatenating leaves two entries under one name where the first silently wins.
  metadata <- utils::modifyList(
    list(
      schema_version = 2L,
      data_sha = data_sha,
      hash_algo = "datom-cv1",
      table_type = "derived",
      created_at = created_at,
      size_bytes = size_bytes
    ),
    extra_meta
  )

  history <- c(
    list(list(version = version, data_sha = data_sha, timestamp = created_at)),
    older
  )

  list(metadata = metadata, history = history)
}

#' Mock a store a manifest rebuild can actually read.
#'
#' Mocks the two storage entry points a rebuild uses -- the recursive listing and
#' the JSON read -- so a test can hand a reader a manifest it must reconstruct and
#' still get a correct answer back.
#'
#' The listing returns **full** keys, including the `{prefix}/datom/` portion,
#' because that is what both real backends return. A mock that returned relative
#' keys would let a rebuild that forgot to strip the namespace root pass.
#'
#' @param manifest The document served for `.metadata/manifest.json`.
#' @param artifacts Named list of [mock_stored_artifact()] results.
#' @param prefix The conn prefix the keys are built under.
#' @param .env Frame the mock is scoped to.
#' @return Invisibly `NULL`.
mock_rebuildable_store <- function(manifest,
                                   artifacts = list(),
                                   prefix = "proj",
                                   .env = parent.frame()) {
  root <- paste0(c(prefix, "datom"), collapse = "/")
  keys <- unlist(lapply(names(artifacts), function(nm) {
    paste0(root, "/", nm, "/.metadata/",
           c("metadata.json", "version_history.json"))
  }), use.names = FALSE)
  if (is.null(keys)) keys <- character()

  testthat::local_mocked_bindings(
    .datom_storage_list_objects = function(conn, prefix) keys,
    .datom_storage_read_json = function(conn, s3_key) {
      if (identical(s3_key, ".metadata/manifest.json")) return(manifest)

      parts <- regmatches(
        s3_key,
        regexec("^([^/]+)/\\.metadata/(metadata|version_history)\\.json$", s3_key)
      )[[1]]

      art <- if (length(parts) == 3L) artifacts[[parts[[2]]]] else NULL
      if (is.null(art)) stop("no such object: ", s3_key)

      if (identical(parts[[3]], "metadata")) art$metadata else art$history
    },
    .env = .env
  )

  invisible(NULL)
}
