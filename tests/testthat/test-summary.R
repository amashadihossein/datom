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
    schema_version = 2L,
    updated_at = "2026-04-29T10:23:00Z",
    artifacts = list(
      a = list(kind = "table", version_count = 3L),
      b = list(kind = "table", version_count = 2L),
      c = list(kind = "table", version_count = 1L)
    ),
    summary = list(total_tables = 3L, total_versions = 6L, total_sets = 0L)
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
      list(
        schema_version = 2L, updated_at = NULL,
        artifacts = list(), summary = list()
      )
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
    schema_version = 2L,
    updated_at = "2026-04-29",
    artifacts = list(),
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
  manifest <- list(
    schema_version = 2L, updated_at = NA, artifacts = list(), summary = list()
  )
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
    schema_version = 2L,
    updated_at = "2026-04-29T10:23:00Z",
    artifacts = list(a = list(kind = "table"), b = list(kind = "table")),
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
  manifest <- list(
    schema_version = 2L, updated_at = "x", artifacts = list(), summary = list()
  )
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
  # The fixture's entry declares no kind of its own -- nothing did, before sets
  # existed -- so the count above is non-zero only because the conversion typed
  # it as a table on the way in.
  expect_equal(s$set_count, 0L)
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


# --- typed artifacts: the counters ---------------------------------------------
# Every test below needs a manifest holding a `kind = "set"` entry beside table
# entries. Nothing writes a set yet, so without a hand-built fixture like this
# one every counter change in this task would pass whether or not it was made.

test_that("datom_summary counts each kind separately", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      list(
        schema_version = 2L,
        artifacts = list(
          dm = list(kind = "table", version_count = 3L),
          lb = list(kind = "table", version_count = 2L),
          adam = list(kind = "set", version_count = 9L)
        ),
        summary = list(total_tables = 2L, total_versions = 5L, total_sets = 1L)
      )
    }
  )

  s <- datom_summary(mock_datom_conn(list()))

  expect_equal(s$table_count, 2L)
  expect_equal(s$set_count, 1L)
})


test_that("datom_summary's counted numbers agree with the manifest's stored block", {
  # Two independent sources for the same fact: datom_summary() counts the
  # entries itself while the manifest carries a summary block written at write
  # time. A filter applied to one and not the other is invisible until they are
  # compared.
  manifest <- list(
    schema_version = 2L,
    artifacts = list(
      dm = list(kind = "table", version_count = 3L),
      lb = list(kind = "table", version_count = 2L),
      adam = list(kind = "set", version_count = 9L)
    ),
    summary = list(total_tables = 2L, total_versions = 5L, total_sets = 1L)
  )
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )

  s <- datom_summary(mock_datom_conn(list()))

  expect_equal(s$table_count, manifest$summary$total_tables)
  expect_equal(s$set_count, manifest$summary$total_sets)
  expect_equal(s$total_versions, manifest$summary$total_versions)
})


test_that("print.datom_summary shows the set count", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      list(
        schema_version = 2L,
        updated_at = "2026-09-08T00:00:00Z",
        artifacts = list(
          dm = list(kind = "table"),
          adam = list(kind = "set")
        ),
        summary = list(total_versions = 2L)
      )
    }
  )
  s <- datom_summary(mock_datom_conn(list()))

  out <- cli::cli_format_method(print(s))

  expect_true(any(grepl("Sets:", out)))
})
