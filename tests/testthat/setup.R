# Fail-closed network guard ---------------------------------------------------
#
# CRAN policy: package tests must not require internet and must fail gracefully.
# datom's suite mocks network entry points per test (`.datom_s3_client`,
# `.datom_storage_*`, `httr2::req_perform`) and uses local bare git repos.
# Because mocking is opt-in, a test that forgets a binding would silently dial
# out. This guard makes that failure LOUD instead of leaky: by default the two
# HTTP egress chokepoints are replaced with functions that abort.
#
#   * `.datom_s3_client()`  -- factory for the paws S3 client (all S3 traffic)
#   * `httr2::req_perform()` -- performs every GitHub API request
#
# Tests that legitimately exercise these paths already shadow them
# (`local_mocked_bindings()` / `mockery::stub()`), so the guard only fires for
# an un-mocked -- i.e. leaking -- code path, naming the chokepoint that leaked.
#
# libgit2 (git2r) opens its own sockets and cannot be trapped at the R level.
# The git rule is enforced by convention: tests use local bare repos only and
# never hand a real URL to an executed clone/fetch (the two failure-path tests
# that need a "bad remote" stub `git2r::clone` / `git2r::fetch`).
#
# Escape hatch: set DATOM_ALLOW_REAL_NETWORK=1 to skip the guard (e.g. for a
# deliberate, manually run integration check).

if (!nzchar(Sys.getenv("DATOM_ALLOW_REAL_NETWORK"))) {

  .datom_block_egress <- function(chokepoint) {
    function(...) {
      cli::cli_abort(c(
        "Real network egress blocked in tests via {.fn {chokepoint}}.",
        "x" = "A test reached a live-network code path without mocking it.",
        "i" = "Mock the relevant binding (e.g. {.fn .datom_s3_client},
               {.fn .datom_storage_exists}, or {.fn httr2::req_perform}) in
               that test, or use a local fixture.",
        "i" = "Set {.envvar DATOM_ALLOW_REAL_NETWORK=1} to allow real network
               access for a deliberate integration run."
      ))
    }
  }

  # S3 chokepoint (datom namespace).
  .datom_s3_client_orig <- getFromNamespace(".datom_s3_client", "datom")
  assignInNamespace(".datom_s3_client", .datom_block_egress(".datom_s3_client"),
                    ns = "datom")
  withr::defer(
    assignInNamespace(".datom_s3_client", .datom_s3_client_orig, ns = "datom"),
    teardown_env()
  )

  # HTTP chokepoint (httr2 namespace) -- covers every GitHub API call.
  if (requireNamespace("httr2", quietly = TRUE)) {
    .datom_req_perform_orig <- httr2::req_perform
    assignInNamespace("req_perform", .datom_block_egress("httr2::req_perform"),
                      ns = "httr2")
    withr::defer(
      assignInNamespace("req_perform", .datom_req_perform_orig, ns = "httr2"),
      teardown_env()
    )
  }
}
