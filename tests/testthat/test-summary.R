# Tests for datom_summary()

# --- input validation --------------------------------------------------------

test_that("rejects non-datom_conn", {
  expect_error(datom_summary("not_conn"), "datom_conn")
})

test_that("aborts when manifest cannot be read", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) stop("boom")
  )
  conn <- mock_datom_conn(list())
  expect_error(datom_summary(conn), "manifest")
})

# --- structure / values ------------------------------------------------------

test_that("returns datom_summary with expected fields", {
  manifest <- list(
    updated_at = "2026-04-29T10:23:00Z",
    tables = list(
      a = list(version_count = 3L),
      b = list(version_count = 2L),
      c = list(version_count = 1L)
    ),
    summary = list(total_tables = 3L, total_versions = 6L)
  )
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )
  conn <- mock_datom_conn(list())  # role="reader", path=NULL

  s <- datom_summary(conn)

  expect_s3_class(s, "datom_summary")
  expect_equal(s$project_name, "test-project")
  expect_equal(s$role, "reader")
  expect_equal(s$backend, "s3")
  expect_equal(s$root, "test-bucket")
  expect_equal(s$prefix, "proj")
  expect_equal(s$table_count, 3L)
  expect_equal(s$total_versions, 6L)
  expect_equal(s$last_updated, "2026-04-29T10:23:00Z")
  expect_null(s$remote_url)
})

test_that("handles empty manifest (no tables, no summary)", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      list(updated_at = NULL, tables = list(), summary = list())
    }
  )
  conn <- mock_datom_conn(list())

  s <- datom_summary(conn)

  expect_equal(s$table_count, 0L)
  expect_equal(s$total_versions, 0L)
  expect_true(is.na(s$last_updated))
})

# --- developer remote_url ---------------------------------------------------

test_that("developer with local data clone reports git remote URL", {
  skip_if_not_installed("git2r")

  tmp <- withr::local_tempdir()
  repo <- git2r::init(tmp)
  git2r::config(repo, user.name = "x", user.email = "x@y")
  writeLines("hello", file.path(tmp, "f.txt"))
  git2r::add(repo, "f.txt")
  git2r::commit(repo, "init")
  git2r::remote_add(repo, "origin", "https://github.com/test-org/test-data.git")

  manifest <- list(
    updated_at = "2026-04-29",
    tables = list(),
    summary = list(total_versions = 0L)
  )
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_datom_conn(list())
  conn$path <- tmp
  conn$role <- "developer"

  s <- datom_summary(conn)
  expect_equal(s$remote_url, "https://github.com/test-org/test-data.git")
})

test_that("missing/broken local clone yields NULL remote_url (no error)", {
  manifest <- list(updated_at = NA, tables = list(), summary = list())
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )
  conn <- mock_datom_conn(list())
  conn$path <- tempfile()  # does not exist
  conn$role <- "developer"

  s <- datom_summary(conn)
  expect_null(s$remote_url)
})

# --- print method -----------------------------------------------------------

test_that("print.datom_summary emits the expected lines (reader)", {
  manifest <- list(
    updated_at = "2026-04-29T10:23:00Z",
    tables = list(a = list(), b = list()),
    summary = list(total_versions = 5L)
  )
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )
  conn <- mock_datom_conn(list())
  s <- datom_summary(conn)

  out <- cli::cli_format_method(print(s))

  expect_true(any(grepl("datom project summary", out)))
  expect_true(any(grepl("Project:", out)))
  expect_true(any(grepl("test-project", out)))
  expect_true(any(grepl("Tables:", out)))
  expect_true(any(grepl("not visible to readers", out)))
})

test_that("print uses 'local' backend label and shows root/prefix joined", {
  manifest <- list(updated_at = "x", tables = list(), summary = list())
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )
  conn <- mock_datom_conn(list(), root = "/tmp/store", prefix = "myproj")
  conn$backend <- "local"

  s <- datom_summary(conn)
  out <- cli::cli_format_method(print(s))

  expect_true(any(grepl("local", out)))
  expect_true(any(grepl("/tmp/store/myproj", out)))
})


# --- schema_version gate -------------------------------------------------------

test_that("datom_summary refuses a manifest declaring a newer schema", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      list(schema_version = 3L, artifacts = list())
    }
  )

  conn <- mock_datom_conn(list())
  err <- expect_error(datom_summary(conn), class = "datom_schema_unsupported")

  # Outside the read handler: inside it, the upgrade instruction would be
  # reworded as "Could not read manifest".
  expect_match(conditionMessage(err), "install_github")
  expect_false(grepl("Could not read manifest", conditionMessage(err)))
})

test_that("datom_summary tolerates a manifest with no schema_version", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      list(tables = list(a = list(version_count = 1L)))
    }
  )

  conn <- mock_datom_conn(list())
  expect_equal(datom_summary(conn)$table_count, 1L)
})

test_that("datom_summary reads the frozen old-format manifest as non-empty", {
  # Frozen fixture -- see the note in test-query.R. Do not update it to a newer
  # manifest shape; rewritten, it would go green while asserting nothing.
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      jsonlite::read_json(testthat::test_path("fixtures", "manifest-v1.json"))
    }
  )

  s <- datom_summary(mock_datom_conn(list()))

  expect_equal(s$table_count, 1L)
  expect_equal(s$total_versions, 2L)
})

test_that("datom_summary reports an unreadable manifest with the underlying cause", {
  # The read failure now travels back as a value rather than through a handler,
  # so pin that its message still reaches the user.
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) stop("bucket unreachable")
  )

  err <- expect_error(datom_summary(mock_datom_conn(list())))

  expect_match(conditionMessage(err), "Could not read manifest")
  expect_match(conditionMessage(err), "bucket unreachable")
})
