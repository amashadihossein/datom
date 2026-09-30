# Tests for datom_parent() -- the parent lineage constructor.
#
# All storage access is mocked via .datom_storage_read_json; no real network
# egress occurs (the fail-closed guard in setup.R stays silent). Cross-project
# cases use two distinct mock stores keyed by conn$project_name.
#
# Versions are SHA-like (6-64 lowercase hex) since datom_parent() validates
# them via .datom_validate_sha() before splicing into a storage key (#74 G).

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
                             ),
                             project = "study001") {
  snap <- list(
    data_sha   = data_sha,
    table_type = "imported"
  )
  if (!is.null(source_lineage)) snap$source_lineage <- source_lineage
  # What a current build records: the writing repo's own project name. Pass NULL
  # to model a snapshot written before the field existed.
  if (!is.null(project)) snap$project <- project
  snap
}


# --- Success paths -----------------------------------------------------------

test_that("resolves data_sha and source_lineage from the snapshot", {
  snap <- .parent_snapshot()
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) snap
  )

  p <- datom_parent(conn, "dm", "9f3aa1b2c3")

  expect_setequal(
    names(p),
    c("source", "table", "version", "data_sha", "source_lineage")
  )
  expect_length(p, 5L)
  expect_equal(p$source, "study001")
  expect_equal(p$source, conn$project_name)
  expect_equal(p$table, "dm")
  expect_equal(p$version, "9f3aa1b2c3")
  expect_equal(p$data_sha, snap$data_sha)
  expect_equal(p$source_lineage, snap$source_lineage)
})

test_that("record retains no connection and is serializable", {
  snap <- .parent_snapshot()
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) snap
  )

  p <- datom_parent(conn, "dm", "9f3aa1b2c3")

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

  p <- datom_parent(conn, "dm", "9f3aa1b2c3")

  expect_null(p$source_lineage)
  expect_true("source_lineage" %in% names(p))
})


# --- Error paths -------------------------------------------------------------

test_that("aborts when conn is not a datom_conn", {
  expect_error(
    datom_parent(list(project_name = "x"), "dm", "9f3aa1"),
    "datom_conn"
  )
})

test_that("aborts on an invalid table name", {
  conn <- .parent_conn()
  expect_error(datom_parent(conn, "", "9f3aa1"), "empty")
})

test_that("aborts on an invalid version", {
  conn <- .parent_conn()
  expect_error(datom_parent(conn, "dm", ""), "version")
  expect_error(datom_parent(conn, "dm", 123), "version")
})

test_that("aborts on a path-traversal version (#74 G)", {
  conn <- .parent_conn()
  expect_error(datom_parent(conn, "dm", "../../etc/passwd"), "hex")
  expect_error(datom_parent(conn, "dm", "not-hex-zzz"), "hex")
  # Too short (< 6 chars) is rejected too.
  expect_error(datom_parent(conn, "dm", "abc"), "hex")
})

test_that("aborts when the snapshot read fails, naming table/version/project", {
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      cli::cli_abort("Object not found")
    }
  )

  err <- expect_error(datom_parent(conn, "dm", "9f3aa1b2c3"))
  msg <- conditionMessage(err)
  expect_match(msg, "dm")
  expect_match(msg, "9f3aa1b2c3")
  expect_match(msg, "study001")
})

test_that("aborts when the snapshot declares a newer schema", {
  # The snapshot is byte-identical to metadata.json, so it carries the format
  # number. Both fields read out of it are durable -- data_sha becomes a storage
  # address, source_lineage is unioned into a written table's lineage -- so a
  # half-understood document would be copied forward, not just misread once.
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      c(.parent_snapshot(), list(schema_version = 99L))
    }
  )

  err <- expect_error(
    datom_parent(conn, "dm", "9f3aa1b2c3"),
    class = "datom_schema_unsupported"
  )
  # Checked outside the handler that turns a read failure into "not found".
  expect_false(grepl("not found", conditionMessage(err), fixed = TRUE))
})

test_that("a snapshot with no declared schema is tolerated as v1", {
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .parent_snapshot()
  )

  expect_equal(datom_parent(conn, "dm", "9f3aa1b2c3")$data_sha, "d_dm_aaa")
})

test_that("aborts when the snapshot is missing data_sha", {
  snap <- .parent_snapshot(data_sha = NULL)
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) snap
  )

  expect_error(datom_parent(conn, "dm", "9f3aa1b2c3"), "data_sha")
})

test_that("aborts when data_sha is an empty string", {
  snap <- .parent_snapshot(data_sha = "")
  conn <- .parent_conn("study001")

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) snap
  )

  expect_error(datom_parent(conn, "dm", "9f3aa1b2c3"), "data_sha")
})


# --- Audit invariant ---------------------------------------------------------

test_that("datom_parent has no data_sha parameter", {
  expect_false("data_sha" %in% names(formals(datom_parent)))
})


# --- Cross-project: two distinct mock stores ---------------------------------

test_that("source comes from each snapshot's own metadata across two stores", {
  # Each store's snapshot records the project that wrote it, as a real write does,
  # so this asserts the recorded name is read per artifact rather than the
  # connection's label being copied through.
  conn_a <- .parent_conn("study001")
  conn_b <- .parent_conn("labdata")

  store_a <- list(
    "dm/.metadata/9f3aa1b2c3.json" = .parent_snapshot(
      data_sha = "d_dm_aaa",
      source_lineage = list(
        list(project = "study001", table = "dm", version_sha = "d_dm_aaa")
      ),
      project = "study001"
    )
  )
  store_b <- list(
    "ex/.metadata/7c1bb2d3e4.json" = .parent_snapshot(
      data_sha = "d_ex_bbb",
      source_lineage = list(
        list(project = "labdata", table = "ex", version_sha = "d_ex_bbb")
      ),
      project = "labdata"
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

  p_a <- datom_parent(conn_a, "dm", "9f3aa1b2c3")
  p_b <- datom_parent(conn_b, "ex", "7c1bb2d3e4")

  expect_equal(p_a$source, "study001")
  expect_equal(p_a$data_sha, "d_dm_aaa")
  expect_equal(p_b$source, "labdata")
  expect_equal(p_b$data_sha, "d_ex_bbb")

  # Records have identical shape regardless of which store resolved them.
  expect_setequal(names(p_a), names(p_b))
})

# --- where a parent's source comes from --------------------------------------
#
# The same cascade a member's project uses, and here it matters more: `parents` is
# part of the declaring table's identity, so a name read off an unvalidated reader
# label changes a VERSION rather than only a citation. datom_parent() also has no
# role check, so a reader connection reaches this code.

.parent_manifest <- function(project_name = "the-repos-own-name") {
  m <- list(schema_version = 2L)
  if (!is.null(project_name)) m$project_name <- project_name
  m$artifacts <- structure(list(), names = character(0))
  m
}

test_that("a mislabelled reader records the parent repo's own name", {
  conn <- .parent_conn("a-label-nobody-validated")
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      .parent_snapshot(project = "study001")
    }
  )

  expect_equal(datom_parent(conn, "dm", "9f3aa1b2c3")$source, "study001")
})

test_that("a snapshot written before the field falls back to the manifest", {
  conn <- .parent_conn("a-label-nobody-validated")
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (grepl("manifest", key, fixed = TRUE)) return(.parent_manifest())
      .parent_snapshot(project = NULL)
    }
  )

  expect_equal(
    datom_parent(conn, "dm", "9f3aa1b2c3")$source,
    "the-repos-own-name"
  )
})

test_that("with neither recorded, the label is used and called unverified", {
  conn <- .parent_conn("a-label-nobody-validated")
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (grepl("manifest", key, fixed = TRUE)) {
        return(.parent_manifest(project_name = NULL))
      }
      .parent_snapshot(project = NULL)
    }
  )

  expect_warning(
    p <- datom_parent(conn, "dm", "9f3aa1b2c3"),
    "unverified"
  )
  expect_equal(p$source, "a-label-nobody-validated")
})


# --- Taking the version from a set (x =) --------------------------------------
#
# A hand-built datom_set, and a mock store keyed by the snapshot key, so a parent
# resolved at the wrong version fails to read rather than passing on a
# catch-all snapshot.

.v_dm      <- strrep("a", 64)
.v_lb_live <- strrep("b", 64)
.v_lb_base <- strrep("c", 64)
.v_ex      <- strrep("d", 64)
.v_subset  <- strrep("e", 64)

.parent_member <- function(name, version, kind = "table", tags = NULL,
                           project = "study001") {
  m <- list(id = list(project = project, name = name, kind = kind,
                      version = version))
  if (!is.null(tags)) m$tags <- tags
  m
}

.parent_set <- function(members) {
  structure(
    list(name = "liver-safety", project = "liver", version = NULL,
         data_sha = NULL, tags = NULL, members = members),
    class = "datom_set"
  )
}

# lb twice -- a live input and a locked baseline -- so a name alone is ambiguous
# and only a label picks one. The baseline is listed FIRST, so a resolver that
# ignored the labels and took the first match would pick the baseline when the
# live one is asked for -- the live case is the one that separates them.
.parent_fixture_set <- function() {
  .parent_set(list(
    .parent_member("lb", .v_lb_base, tags = list(release = "baseline")),
    .parent_member("dm", .v_dm, tags = list(type = "input")),
    .parent_member("lb", .v_lb_live, tags = list(type = "input")),
    .parent_member("ex", .v_ex, tags = list(type = "input")),
    .parent_member("subset", .v_subset, kind = "set")
  ))
}

.parent_store <- function() {
  keys <- c(
    paste0("dm/.metadata/", .v_dm, ".json"),
    paste0("lb/.metadata/", .v_lb_live, ".json"),
    paste0("lb/.metadata/", .v_lb_base, ".json"),
    paste0("ex/.metadata/", .v_ex, ".json")
  )
  shas <- c("d_dm", "d_lb_live", "d_lb_base", "d_ex")
  stats::setNames(
    lapply(shas, function(s) .parent_snapshot(data_sha = s)),
    keys
  )
}

.local_parent_store <- function(env = parent.frame()) {
  store <- .parent_store()
  reads <- new.env()
  reads$keys <- character(0)
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      reads$keys <- c(reads$keys, key)
      snap <- store[[key]]
      if (is.null(snap)) cli::cli_abort("Key {key} not found")
      snap
    },
    .env = env
  )
  reads
}

test_that("x = declares the parent at the version the set pins", {
  .local_parent_store()
  conn <- .parent_conn("study001")

  got <- datom_parent(conn, "dm", x = .parent_fixture_set())

  # Always a list with x, even for one table.
  expect_type(got, "list")
  expect_null(names(got))
  expect_length(got, 1L)
  expect_equal(got[[1]]$version, .v_dm)
  expect_equal(got[[1]]$data_sha, "d_dm")
  expect_equal(got[[1]]$table, "dm")
  expect_equal(got[[1]]$source, "study001")
  expect_setequal(
    names(got[[1]]),
    c("source", "table", "version", "data_sha", "source_lineage")
  )
})

test_that("x = with several tables returns one record each, in order", {
  .local_parent_store()
  conn <- .parent_conn("study001")

  got <- datom_parent(conn, c("ex", "dm", "lb"), x = .parent_fixture_set(),
                      tags = list(type = "input"))

  expect_length(got, 3L)
  expect_equal(vapply(got, `[[`, "", "table"), c("ex", "dm", "lb"))
  expect_equal(
    vapply(got, `[[`, "", "version"),
    c(.v_ex, .v_dm, .v_lb_live)
  )
  # The result is what datom_write(parents = ) accepts.
  expect_invisible(.datom_validate_parents(got))
})

test_that("x = picks the member datom_fetch_member() picks", {
  .local_parent_store()
  conn <- .parent_conn("study001")
  x <- .parent_fixture_set()

  # datom_fetch_member() hands a table member's version to datom_read(); make
  # the read report the version it was asked for.
  local_mocked_bindings(
    datom_read = function(conn, name, version = NULL, ...) version
  )

  cases <- list(
    list(table = "dm", tags = NULL),
    list(table = "lb", tags = list(type = "input")),
    list(table = "lb", tags = list(release = "baseline"))
  )
  for (case in cases) {
    fetched <- datom_fetch_member(conn, x, case$table, tags = case$tags)
    parent <- datom_parent(conn, case$table, x = x, tags = case$tags)
    expect_equal(parent[[1]]$version, fetched)
  }

  # The two lb cases must pick different members, or the parity above could
  # hold for a resolver that ignores labels.
  expect_false(identical(.v_lb_live, .v_lb_base))
})

test_that("x = stops on a name the set holds twice, listing both", {
  reads <- .local_parent_store()
  conn <- .parent_conn("study001")

  err <- expect_error(
    datom_parent(conn, "lb", x = .parent_fixture_set()),
    class = "datom_member_ambiguous"
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, substr(.v_lb_live, 1, 8), fixed = TRUE)
  expect_match(msg, substr(.v_lb_base, 1, 8), fixed = TRUE)
  expect_length(reads$keys, 0L)
})

test_that("x = keeps each refusal's own class when the table is not first", {
  .local_parent_store()
  conn <- .parent_conn("study001")

  # The condition must reach the caller with its own class from inside the
  # per-table loop, not wrapped by an iteration helper. `inherit = FALSE`
  # matters: by default expect_error() also searches a chained error's parents,
  # so it would pass on purrr's wrapper while a caller's
  # tryCatch(datom_member_ambiguous = ) never fired.
  expect_error(
    datom_parent(conn, c("dm", "lb"), x = .parent_fixture_set()),
    class = "datom_member_ambiguous",
    inherit = FALSE
  )
  expect_error(
    datom_parent(conn, c("dm", "subset"), x = .parent_fixture_set()),
    class = "datom_parent_not_a_table",
    inherit = FALSE
  )
})

test_that("x = stops on a name the set does not hold", {
  .local_parent_store()
  conn <- .parent_conn("study001")

  expect_error(
    datom_parent(conn, "vs", x = .parent_fixture_set()),
    class = "datom_member_not_found"
  )
})

test_that("x = stops on a member that is a set, before any read", {
  reads <- .local_parent_store()
  conn <- .parent_conn("study001")

  err <- expect_error(
    datom_parent(conn, "subset", x = .parent_fixture_set()),
    class = "datom_parent_not_a_table"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "subset")
  expect_length(reads$keys, 0L)
})

test_that("x = refuses malformed tags as datom_fetch_member() does, before any read", {
  # R5.3: resolved exactly as datom_fetch_member() resolves it, labels included.
  # Without the check a numeric label reaches the resolver and fails as "not
  # found", which names the wrong problem. The validator raises no class, so the
  # two verbs are compared on the message's first line; the remedy lines differ
  # by one example value.
  reads <- .local_parent_store()
  conn <- .parent_conn("study001")
  x <- .parent_fixture_set()
  local_mocked_bindings(datom_read = function(conn, name, version = NULL, ...) {
    stop("no read expected")
  })
  first_line <- function(e) strsplit(cli::ansi_strip(conditionMessage(e)), "\n")[[1]][1]

  for (bad in list(list(type = 1), list("input"))) {
    err_parent <- expect_error(datom_parent(conn, "lb", x = x, tags = bad))
    err_fetch <- expect_error(datom_fetch_member(conn, x, "lb", tags = bad))
    expect_false(inherits(err_parent, "datom_member_not_found"))
    expect_identical(first_line(err_parent), first_line(err_fetch))
  }
  expect_match(first_line(err_parent), "named list", fixed = TRUE)
  expect_length(reads$keys, 0L)
})

test_that("x = refuses an invalid table name as a name, not as not found", {
  # Each name is validated before it is looked up. Without that, a name no
  # member could ever have fails as datom_member_not_found. Not first in the
  # vector, so the check has to run per name.
  .local_parent_store()
  conn <- .parent_conn("study001")

  err <- expect_error(
    datom_parent(conn, c("dm", "Not A Name!"), x = .parent_fixture_set())
  )
  expect_false(inherits(err, "datom_member_not_found"))
  expect_match(cli::ansi_strip(conditionMessage(err)), "may only contain",
               fixed = TRUE)
})

test_that("x must be a datom_set", {
  conn <- .parent_conn("study001")
  expect_error(
    datom_parent(conn, "dm", x = list(members = list())),
    class = "datom_not_a_set"
  )
})

test_that("x = refuses an empty or NA table vector", {
  conn <- .parent_conn("study001")
  x <- .parent_fixture_set()
  expect_error(datom_parent(conn, character(0), x = x), "member names")
  expect_error(datom_parent(conn, c("dm", NA), x = x), "member names")
})

test_that("exactly one of version and x is required", {
  conn <- .parent_conn("study001")
  x <- .parent_fixture_set()

  expect_error(
    datom_parent(conn, "dm", .v_dm, x = x),
    class = "datom_parent_version_or_set"
  )
  expect_error(
    datom_parent(conn, "dm"),
    class = "datom_parent_version_or_set"
  )
})

test_that("tags without x is refused rather than ignored", {
  .local_parent_store()
  conn <- .parent_conn("study001")

  expect_error(
    datom_parent(conn, "dm", .v_dm, tags = list(type = "input")),
    class = "datom_parent_tags_without_set"
  )
})

test_that("a positional call without x still returns one record", {
  .local_parent_store()
  conn <- .parent_conn("study001")

  p <- datom_parent(conn, "dm", .v_dm)

  expect_setequal(
    names(p),
    c("source", "table", "version", "data_sha", "source_lineage")
  )
  expect_equal(p$version, .v_dm)
  expect_equal(p$data_sha, "d_dm")
})
