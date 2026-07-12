# Tests for datom_parent() -- the parent lineage constructor.
#
# All storage access is mocked via .datom_storage_read_json; no real network
# egress occurs (the fail-closed guard in setup.R stays silent). Cross-project
# cases use two distinct mock stores keyed by conn$project_name.

# --- Fixtures ----------------------------------------------------------------

.parent_conn <- function(project_name = "test-project") {
  conn <- mock_datom_conn("mock-client")
  conn$project_name <- project_name
  conn
}

.parent_snapshot <- function(data_sha = "d_dm_aaa",
                             source_lineage = list(
                               list(project = "study001", table = "dm",
                                    version_sha = "d_dm_aaa")
                             )) {
  snap <- list(
    data_sha   = data_sha,
    table_type = "imported"
  )
  if (!is.null(source_lineage)) snap$source_lineage <- source_lineage
  snap
}


# --- Success paths -----------------------------------------------------------

test_that("resolves data_sha and source_lineage from the snapshot", {
  snap <- .parent_snapshot()
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) snap
  )

  p <- datom_parent(conn, "dm", "v_dm_9f3")

  expect_setequal(
    names(p),
    c("source", "table", "version", "data_sha", "source_lineage")
  )
  expect_length(p, 5L)
  expect_equal(p$source, "study001")
  expect_equal(p$source, conn$project_name)
  expect_equal(p$table, "dm")
  expect_equal(p$version, "v_dm_9f3")
  expect_equal(p$data_sha, snap$data_sha)
  expect_equal(p$source_lineage, snap$source_lineage)
})

test_that("record retains no connection and is serializable", {
  snap <- .parent_snapshot()
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) snap
  )

  p <- datom_parent(conn, "dm", "v_dm_9f3")

  # No live connection leaks into the record.
  expect_false("conn" %in% names(p))
  expect_false(any(vapply(p, inherits, logical(1), what = "datom_conn")))

  # Round-trips through JSON as pure data.
  json <- jsonlite::toJSON(p, auto_unbox = TRUE)
  back <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_equal(back$source, p$source)
  expect_equal(back$table, p$table)
  expect_equal(back$version, p$version)
  expect_equal(back$data_sha, p$data_sha)
})

test_that("source_lineage is NULL when absent from the snapshot", {
  snap <- .parent_snapshot(source_lineage = NULL)
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) snap
  )

  p <- datom_parent(conn, "dm", "v_dm_9f3")

  expect_null(p$source_lineage)
  expect_true("source_lineage" %in% names(p))
})


# --- Error paths -------------------------------------------------------------

test_that("aborts when conn is not a datom_conn", {
  expect_error(
    datom_parent(list(project_name = "x"), "dm", "v1"),
    "datom_conn"
  )
})

test_that("aborts on an invalid table name", {
  conn <- .parent_conn()
  expect_error(datom_parent(conn, "", "v1"), "empty")
})

test_that("aborts on an invalid version", {
  conn <- .parent_conn()
  expect_error(datom_parent(conn, "dm", ""), "version")
  expect_error(datom_parent(conn, "dm", 123), "version")
})

test_that("aborts when the snapshot read fails, naming table/version/project", {
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      cli::cli_abort("Object not found")
    }
  )

  err <- expect_error(datom_parent(conn, "dm", "v_dm_9f3"))
  msg <- conditionMessage(err)
  expect_match(msg, "dm")
  expect_match(msg, "v_dm_9f3")
  expect_match(msg, "study001")
})

test_that("aborts when the snapshot is missing data_sha", {
  snap <- .parent_snapshot(data_sha = NULL)
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) snap
  )

  expect_error(datom_parent(conn, "dm", "v_dm_9f3"), "data_sha")
})

test_that("aborts when data_sha is an empty string", {
  snap <- .parent_snapshot(data_sha = "")
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) snap
  )

  expect_error(datom_parent(conn, "dm", "v_dm_9f3"), "data_sha")
})


# --- Audit invariant ---------------------------------------------------------

test_that("datom_parent has no data_sha parameter", {
  expect_false("data_sha" %in% names(formals(datom_parent)))
})


# --- Cross-project: two distinct mock stores ---------------------------------

test_that("source is derived per-connection across two project stores", {
  conn_a <- .parent_conn("study001")
  conn_b <- .parent_conn("labdata")

  store_a <- list(
    "dm/.metadata/v_dm_9f3.json" = .parent_snapshot(
      data_sha = "d_dm_aaa",
      source_lineage = list(
        list(project = "study001", table = "dm", version_sha = "d_dm_aaa")
      )
    )
  )
  store_b <- list(
    "ex/.metadata/v_ex_7c1.json" = .parent_snapshot(
      data_sha = "d_ex_bbb",
      source_lineage = list(
        list(project = "labdata", table = "ex", version_sha = "d_ex_bbb")
      )
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      store <- switch(conn$project_name,
        study001 = store_a,
        labdata  = store_b,
        cli::cli_abort("Unexpected project {conn$project_name}")
      )
      snap <- store[[key]]
      if (is.null(snap)) {
        cli::cli_abort("Key {key} not found in {conn$project_name} store")
      }
      snap
    }
  )

  p_a <- datom_parent(conn_a, "dm", "v_dm_9f3")
  p_b <- datom_parent(conn_b, "ex", "v_ex_7c1")

  expect_equal(p_a$source, "study001")
  expect_equal(p_a$data_sha, "d_dm_aaa")
  expect_equal(p_b$source, "labdata")
  expect_equal(p_b$data_sha, "d_ex_bbb")

  # Records have identical shape regardless of which store resolved them.
  expect_setequal(names(p_a), names(p_b))
})
