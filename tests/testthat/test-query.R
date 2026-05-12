# Tests for query operations
# Phase 5, Chunk 6

# --- datom_list() --------------------------------------------------------------

test_that("rejects non-datom_conn", {
  expect_error(datom_list("not_conn"), "datom_conn")
})

test_that("returns empty data frame when manifest has no tables", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      list(updated_at = "2026-01-01", tables = list(), summary = list())
    }
  )

  conn <- mock_datom_conn(list())
  result <- datom_list(conn)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true("name" %in% names(result))
})

test_that("returns data frame with one row per table", {
  manifest <- list(
    tables = list(
      customers = list(
        current_version = "v1",
        current_data_sha = "sha1",
        last_updated = "2026-01-01"
      ),
      orders = list(
        current_version = "v2",
        current_data_sha = "sha2",
        last_updated = "2026-01-02"
      )
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_datom_conn(list())
  result <- datom_list(conn)

  expect_equal(nrow(result), 2)
  expect_equal(sort(result$name), c("customers", "orders"))
  expect_equal(result$current_version[result$name == "customers"], "v1")
  expect_equal(result$current_data_sha[result$name == "orders"], "sha2")
})

test_that("filters tables by glob pattern", {
  manifest <- list(
    tables = list(
      customer_us = list(current_version = "v1", last_updated = "2026-01-01"),
      customer_eu = list(current_version = "v2", last_updated = "2026-01-02"),
      orders = list(current_version = "v3", last_updated = "2026-01-03")
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_datom_conn(list())
  result <- datom_list(conn, pattern = "customer_*")

  expect_equal(nrow(result), 2)
  expect_true(all(grepl("^customer_", result$name)))
})

test_that("returns empty data frame when pattern matches nothing", {
  manifest <- list(
    tables = list(
      customers = list(current_version = "v1", last_updated = "2026-01-01")
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_datom_conn(list())
  result <- datom_list(conn, pattern = "zzz_*")

  expect_equal(nrow(result), 0)
})

test_that("includes version_count when include_versions = TRUE", {
  manifest <- list(
    tables = list(
      customers = list(
        current_version = "v1",
        last_updated = "2026-01-01",
        version_count = 15L
      )
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_datom_conn(list())

  result_no <- datom_list(conn, include_versions = FALSE)
  expect_false("version_count" %in% names(result_no))

  result_yes <- datom_list(conn, include_versions = TRUE)
  expect_true("version_count" %in% names(result_yes))
  expect_equal(result_yes$version_count, 15L)
})

test_that("reads correct S3 key for manifest", {
  captured_key <- NULL
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      captured_key <<- s3_key
      list(tables = list())
    }
  )

  conn <- mock_datom_conn(list())
  datom_list(conn)

  expect_equal(captured_key, ".metadata/manifest.json")
})

test_that("errors when manifest cannot be read from S3", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) stop("NoSuchKey")
  )

  conn <- mock_datom_conn(list())
  expect_error(datom_list(conn), "manifest")
})

test_that("handles missing fields gracefully with NA", {
  manifest <- list(
    tables = list(
      sparse = list()
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_datom_conn(list())
  result <- datom_list(conn)

  expect_equal(nrow(result), 1)
  expect_equal(result$name, "sparse")
  expect_true(is.na(result$current_version))
  expect_true(is.na(result$last_updated))
})

test_that("truncates hashes by default (short_hash = TRUE)", {
  full_sha <- "a793e733037c6d3152f22063a5e7f7be0fb27cfc0e9bf5b0c841a05997774e0f"
  manifest <- list(
    tables = list(
      dm = list(
        current_version = full_sha,
        current_data_sha = full_sha,
        last_updated = "2026-01-01"
      )
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_datom_conn(list())
  result <- datom_list(conn)

  expect_equal(nchar(result$current_version), 8)
  expect_equal(result$current_version, substr(full_sha, 1, 8))
  expect_equal(nchar(result$current_data_sha), 8)
})

test_that("returns full hashes with short_hash = FALSE", {
  full_sha <- "a793e733037c6d3152f22063a5e7f7be0fb27cfc0e9bf5b0c841a05997774e0f"
  manifest <- list(
    tables = list(
      dm = list(
        current_version = full_sha,
        current_data_sha = full_sha,
        last_updated = "2026-01-01"
      )
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) manifest
  )

  conn <- mock_datom_conn(list())
  result <- datom_list(conn, short_hash = FALSE)

  expect_equal(result$current_version, full_sha)
  expect_equal(result$current_data_sha, full_sha)
})


# --- datom_history() -----------------------------------------------------------

test_that("rejects non-datom_conn", {
  expect_error(datom_history("not_conn", "t"), "datom_conn")
})

test_that("validates table name", {
  conn <- mock_datom_conn(list())
  expect_error(datom_history(conn, ""), "must not be empty")
})

test_that("rejects invalid n", {
  conn <- mock_datom_conn(list())
  expect_error(datom_history(conn, "tbl", n = 0), "positive")
  expect_error(datom_history(conn, "tbl", n = -1), "positive")
  expect_error(datom_history(conn, "tbl", n = "x"), "positive")
})

test_that("returns data frame with version history", {
  history <- list(
    list(
      version = "meta_sha_1",
      data_sha = "data_sha_1",
      timestamp = "2026-01-15T10:00:00Z",
      author = "jane@co.com",
      commit_message = "Initial load"
    ),
    list(
      version = "meta_sha_2",
      data_sha = "data_sha_2",
      timestamp = "2026-01-14T10:00:00Z",
      author = "john@co.com",
      commit_message = "Fix data"
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) history
  )

  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "customers", short_hash = FALSE)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 2)
  expect_equal(result$version[1], "meta_sha_1")
  expect_equal(result$data_sha[2], "data_sha_2")
  expect_equal(result$author[1], "jane@co.com")
  expect_equal(result$commit_message[2], "Fix data")
})

test_that("limits results to n entries", {
  history <- list(
    list(version = "v1", data_sha = "s1", timestamp = "t1"),
    list(version = "v2", data_sha = "s2", timestamp = "t2"),
    list(version = "v3", data_sha = "s3", timestamp = "t3")
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) history
  )

  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "tbl", n = 2)

  expect_equal(nrow(result), 2)
  expect_equal(result$version, c("v1", "v2"))
})

test_that("returns empty data frame for empty history", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) list()
  )

  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "tbl")

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true("version" %in% names(result))
})

test_that("reads correct S3 key for version history", {
  captured_key <- NULL
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      captured_key <<- s3_key
      list()
    }
  )

  conn <- mock_datom_conn(list())
  datom_history(conn, "ADSL")

  expect_equal(captured_key, "ADSL/.metadata/version_history.json")
})

test_that("errors when version history cannot be read from S3", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) stop("NoSuchKey")
  )

  conn <- mock_datom_conn(list())
  expect_error(datom_history(conn, "ghost"), "No version history")
})

test_that("handles author as list (name + email)", {
  history <- list(
    list(
      version = "v1",
      data_sha = "s1",
      timestamp = "2026-01-01",
      author = list(name = "Jane Doe", email = "jane@co.com"),
      commit_message = "Update"
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) history
  )

  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "tbl")

  expect_equal(result$author, "Jane Doe <jane@co.com>")
})

test_that("handles missing fields with NA", {
  history <- list(
    list(version = "v1")
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) history
  )

  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "tbl")

  expect_equal(nrow(result), 1)
  expect_equal(result$version, "v1")
  expect_true(is.na(result$data_sha))
  expect_true(is.na(result$author))
})

test_that("truncates version and data_sha by default (short_hash = TRUE)", {
  full_version <- "a793e733037c6d3152f22063a5e7f7be0fb27cfc0e9bf5b0c841a05997774e0f"
  full_data_sha <- "2320b970ae25b8393e2b421ecfe4fa0b9218f3de69cda83db4a22d002657aed7"
  history <- list(
    list(
      version = full_version,
      data_sha = full_data_sha,
      timestamp = "2026-01-15T10:00:00Z",
      author = "jane@co.com",
      commit_message = "Sync dm"
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) history
  )

  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "dm")

  expect_equal(nchar(result$version), 8)
  expect_equal(result$version, substr(full_version, 1, 8))
  expect_equal(nchar(result$data_sha), 8)
  expect_equal(result$data_sha, substr(full_data_sha, 1, 8))
})

test_that("returns full hashes with short_hash = FALSE", {
  full_version <- "a793e733037c6d3152f22063a5e7f7be0fb27cfc0e9bf5b0c841a05997774e0f"
  full_data_sha <- "2320b970ae25b8393e2b421ecfe4fa0b9218f3de69cda83db4a22d002657aed7"
  history <- list(
    list(
      version = full_version,
      data_sha = full_data_sha,
      timestamp = "2026-01-15T10:00:00Z"
    )
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) history
  )

  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "dm", short_hash = FALSE)

  expect_equal(result$version, full_version)
  expect_equal(result$data_sha, full_data_sha)
})


# --- datom_get_parents() -------------------------------------------------------

test_that("datom_get_parents rejects non-datom_conn", {
  expect_error(datom_get_parents("not_conn", "tbl"), "datom_conn")
})

test_that("datom_get_parents validates table name", {
  conn <- mock_datom_conn(list())
  expect_error(datom_get_parents(conn, ""), "must not be empty")
  expect_error(datom_get_parents(conn, "bad name!"), class = "rlang_error")
})

test_that("returns parents from current metadata", {
  parents <- list(
    list(source = "proj_a", table = "tbl1", version = "sha_abc"),
    list(source = "proj_b", table = "tbl2", version = "sha_def")
  )
  metadata <- list(
    data_sha = "sha1",
    table_type = "derived",
    parents = parents,
    nrow = 10L
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      expect_equal(s3_key, "customers/.metadata/metadata.json")
      metadata
    }
  )

  conn <- mock_datom_conn(list())
  result <- datom_get_parents(conn, "customers")

  expect_length(result, 2)
  expect_equal(result[[1]]$source, "proj_a")
  expect_equal(result[[1]]$table, "tbl1")
  expect_equal(result[[1]]$version, "sha_abc")
  expect_equal(result[[2]]$source, "proj_b")
})

test_that("returns NULL for imported table (no parents)", {
  metadata <- list(
    data_sha = "sha1",
    table_type = "imported",
    nrow = 10L
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) metadata
  )

  conn <- mock_datom_conn(list())
  result <- datom_get_parents(conn, "imported_tbl")

  expect_null(result)
})

test_that("returns NULL for derived table with no recorded lineage", {
  metadata <- list(
    data_sha = "sha1",
    table_type = "derived",
    nrow = 10L
  )

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) metadata
  )

  conn <- mock_datom_conn(list())
  result <- datom_get_parents(conn, "no_lineage_tbl")

  expect_null(result)
})

test_that("reads versioned metadata snapshot when version provided", {
  parents <- list(
    list(source = "proj_a", table = "tbl1", version = "sha_v1")
  )
  versioned_meta <- list(
    data_sha = "sha_old",
    table_type = "derived",
    parents = parents,
    nrow = 5L
  )

  captured_key <- NULL
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      captured_key <<- s3_key
      versioned_meta
    }
  )

  conn <- mock_datom_conn(list())
  result <- datom_get_parents(conn, "tbl", version = "meta_sha_123")

  expect_equal(captured_key, "tbl/.metadata/meta_sha_123.json")
  expect_length(result, 1)
  expect_equal(result[[1]]$source, "proj_a")
})

test_that("errors when table not found (current)", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      stop("Failed to read JSON from S3")
    }
  )

  conn <- mock_datom_conn(list())
  expect_error(datom_get_parents(conn, "ghost"), "No metadata found")
})

test_that("errors when versioned snapshot not found", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      stop("Failed to read JSON from S3")
    }
  )

  conn <- mock_datom_conn(list())
  expect_error(
    datom_get_parents(conn, "tbl", version = "nonexistent_sha"),
    "not found"
  )
})

test_that("rejects invalid version argument", {
  conn <- mock_datom_conn(list())
  expect_error(datom_get_parents(conn, "tbl", version = ""), "non-empty")
  expect_error(datom_get_parents(conn, "tbl", version = 123), "non-empty")
})


# --- datom_get_lineage() -------------------------------------------------------

test_that("datom_get_lineage rejects non-datom_conn", {
  expect_error(datom_get_lineage("not_conn", "tbl"), "datom_conn")
})

test_that("datom_get_lineage validates table name", {
  conn <- mock_datom_conn(list())
  expect_error(datom_get_lineage(conn, ""), "must not be empty")
  expect_error(datom_get_lineage(conn, "bad name!"), class = "rlang_error")
})

test_that("rejects invalid depth", {
  conn <- mock_datom_conn(list())
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) list(source_lineage = NULL)
  )
  expect_error(datom_get_lineage(conn, "tbl", depth = "all"), "should be one of")
})

test_that("rejects invalid version argument", {
  conn <- mock_datom_conn(list())
  expect_error(datom_get_lineage(conn, "tbl", version = ""), "non-empty")
  expect_error(datom_get_lineage(conn, "tbl", version = 123), "non-empty")
})

test_that("depth = 'source' returns source_lineage from current metadata", {
  sl <- list(
    list(project = "raw-proj", table = "dm", version_sha = "v1"),
    list(project = "raw-proj", table = "lb", version_sha = "v2")
  )
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) list(source_lineage = sl)
  )
  conn <- mock_datom_conn(list())
  result <- datom_get_lineage(conn, "analysis_pop")

  expect_length(result, 2)
  expect_equal(result[[1]]$project, "raw-proj")
  expect_equal(result[[1]]$table, "dm")
  expect_equal(result[[2]]$table, "lb")
})

test_that("depth = 'parents' returns parents from current metadata", {
  parents <- list(list(source = "p", table = "dm_clean", version = "sha_abc"))
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) list(parents = parents)
  )
  conn <- mock_datom_conn(list())
  result <- datom_get_lineage(conn, "analysis_pop", depth = "parents")

  expect_length(result, 1)
  expect_equal(result[[1]]$table, "dm_clean")
})

test_that("depth = 'source' returns NULL when source_lineage absent", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) list(data_sha = "abc")
  )
  conn <- mock_datom_conn(list())
  result <- datom_get_lineage(conn, "old_table")
  expect_null(result)
})

test_that("depth = 'parents' returns NULL when parents absent", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) list(data_sha = "abc")
  )
  conn <- mock_datom_conn(list())
  result <- datom_get_lineage(conn, "old_table", depth = "parents")
  expect_null(result)
})

test_that("reads versioned metadata snapshot when version provided", {
  sl <- list(list(project = "p", table = "t", version_sha = "v1"))
  captured_key <- NULL
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      captured_key <<- key
      list(source_lineage = sl)
    }
  )
  conn <- mock_datom_conn(list())
  result <- datom_get_lineage(conn, "tbl", version = "meta_sha_123")

  expect_true(grepl("meta_sha_123\\.json$", captured_key))
  expect_equal(result[[1]]$version_sha, "v1")
})

test_that("errors on missing table (no metadata)", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) stop("not found")
  )
  conn <- mock_datom_conn(list())
  expect_error(datom_get_lineage(conn, "ghost"), "No metadata found")
})

test_that("errors on missing version snapshot", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) stop("not found")
  )
  conn <- mock_datom_conn(list())
  expect_error(
    datom_get_lineage(conn, "tbl", version = "nonexistent_sha"),
    "not found"
  )
})


# --- datom_validate_lineage() --------------------------------------------------

test_that("datom_validate_lineage rejects non-datom_conn", {
  expect_error(datom_validate_lineage("not_conn", "tbl"), "datom_conn")
})

test_that("datom_validate_lineage validates table name", {
  conn <- mock_datom_conn(list())
  expect_error(datom_validate_lineage(conn, ""), "must not be empty")
})

test_that("datom_validate_lineage rejects invalid version argument", {
  conn <- mock_datom_conn(list())
  expect_error(datom_validate_lineage(conn, "tbl", version = ""), "non-empty")
  expect_error(datom_validate_lineage(conn, "tbl", version = 123), "non-empty")
})

test_that("returns unchecked when table has no parents", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) list(data_sha = "abc")
  )
  conn <- mock_datom_conn(list())
  result <- datom_validate_lineage(conn, "raw_dm")

  expect_equal(result$status, "unchecked")
  expect_length(result$missing, 0)
  expect_length(result$extra, 0)
})

test_that("returns ok when declared matches computed union exactly", {
  sl_a <- list(list(project = "raw", table = "dm", version_sha = "v1"))
  sl_b <- list(list(project = "raw", table = "lb", version_sha = "v2"))
  parents <- list(
    list(table = "dm_clean", version = "p_sha_a"),
    list(table = "lb_clean", version = "p_sha_b")
  )
  declared_sl <- c(sl_a, sl_b)

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (grepl("dm_clean", key)) list(source_lineage = sl_a)
      else if (grepl("lb_clean", key)) list(source_lineage = sl_b)
      else list(parents = parents, source_lineage = declared_sl)
    }
  )
  conn <- mock_datom_conn(list())
  result <- datom_validate_lineage(conn, "analysis_pop")

  expect_equal(result$status, "ok")
  expect_length(result$missing, 0)
  expect_length(result$extra, 0)
  expect_length(result$wrong_version, 0)
})

test_that("detects missing entry (in union, absent from declared)", {
  sl_a <- list(list(project = "raw", table = "dm", version_sha = "v1"))
  sl_b <- list(list(project = "raw", table = "lb", version_sha = "v2"))
  parents <- list(
    list(table = "dm_clean", version = "p_sha_a"),
    list(table = "lb_clean", version = "p_sha_b")
  )
  declared_sl <- sl_a  # missing lb

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (grepl("dm_clean", key)) list(source_lineage = sl_a)
      else if (grepl("lb_clean", key)) list(source_lineage = sl_b)
      else list(parents = parents, source_lineage = declared_sl)
    }
  )
  conn <- mock_datom_conn(list())
  result <- datom_validate_lineage(conn, "analysis_pop")

  expect_equal(result$status, "mismatch")
  expect_length(result$missing, 1)
  expect_equal(result$missing[[1]]$table, "lb")
  expect_length(result$extra, 0)
})

test_that("detects extra entry (declared but not in union)", {
  sl_a <- list(list(project = "raw", table = "dm", version_sha = "v1"))
  parents <- list(list(table = "dm_clean", version = "p_sha_a"))
  phantom <- list(project = "raw", table = "phantom", version_sha = "v_ph")
  declared_sl <- c(sl_a, list(phantom))

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (grepl("dm_clean", key)) list(source_lineage = sl_a)
      else list(parents = parents, source_lineage = declared_sl)
    }
  )
  conn <- mock_datom_conn(list())
  result <- datom_validate_lineage(conn, "analysis_pop")

  expect_equal(result$status, "mismatch")
  expect_length(result$extra, 1)
  expect_equal(result$extra[[1]]$table, "phantom")
  expect_length(result$missing, 0)
})

test_that("detects wrong version_sha (project+table match, sha differs)", {
  sl_actual  <- list(list(project = "raw", table = "dm", version_sha = "v_actual"))
  sl_declared <- list(list(project = "raw", table = "dm", version_sha = "v_stale"))
  parents <- list(list(table = "dm_clean", version = "p_sha"))

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (grepl("dm_clean", key)) list(source_lineage = sl_actual)
      else list(parents = parents, source_lineage = sl_declared)
    }
  )
  conn <- mock_datom_conn(list())
  result <- datom_validate_lineage(conn, "analysis_pop")

  expect_equal(result$status, "mismatch")
  expect_length(result$wrong_version, 1)
  expect_equal(result$wrong_version[[1]]$declared$version_sha, "v_stale")
  expect_equal(result$wrong_version[[1]]$computed$version_sha, "v_actual")
  expect_length(result$missing, 0)
  expect_length(result$extra, 0)
})

test_that("returns error status when parent metadata is unreachable", {
  parents <- list(list(table = "missing_parent", version = "sha"))

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (grepl("missing_parent", key)) stop("not found")
      else list(parents = parents, source_lineage = list())
    }
  )
  conn <- mock_datom_conn(list())
  result <- datom_validate_lineage(conn, "tbl")

  expect_equal(result$status, "error")
  expect_true(nzchar(result$message))
})

test_that("checks versioned snapshot when version provided", {
  sl <- list(list(project = "raw", table = "dm", version_sha = "v1"))
  parents <- list(list(table = "dm_clean", version = "p_sha"))

  captured_key <- NULL
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (!grepl("dm_clean", key)) captured_key <<- key
      if (grepl("dm_clean", key)) list(source_lineage = sl)
      else list(parents = parents, source_lineage = sl)
    }
  )
  conn <- mock_datom_conn(list())
  datom_validate_lineage(conn, "tbl", version = "meta_sha_xyz")

  expect_true(grepl("meta_sha_xyz\\.json$", captured_key))
})


# --- .datom_lineage_union() ----------------------------------------------------

test_that("union of empty lists returns empty list", {
  expect_length(.datom_lineage_union(list(list(), list())), 0)
})

test_that("union deduplicates identical entries", {
  e <- list(project = "p", table = "t", version_sha = "v")
  result <- .datom_lineage_union(list(list(e), list(e)))
  expect_length(result, 1)
})

test_that("union keeps distinct entries", {
  a <- list(project = "p", table = "t1", version_sha = "v1")
  b <- list(project = "p", table = "t2", version_sha = "v2")
  result <- .datom_lineage_union(list(list(a), list(b)))
  expect_length(result, 2)
})

test_that("union keeps both versions when project+table same but sha differs", {
  v1 <- list(project = "p", table = "t", version_sha = "v1")
  v2 <- list(project = "p", table = "t", version_sha = "v2")
  result <- .datom_lineage_union(list(list(v1), list(v2)))
  expect_length(result, 2)
})


# --- datom_status() ------------------------------------------------------------

test_that("datom_status rejects non-datom_conn", {
  expect_error(datom_status("not_conn"), "datom_conn")
})

test_that("datom_status returns connection info for reader", {
  conn <- mock_datom_conn(list())
  conn$role <- "reader"

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      list(tables = list(a = list(), b = list()))
    }
  )

  result <- datom_status(conn)

  expect_equal(result$connection$project_name, "test-project")
  expect_equal(result$connection$role, "reader")
  expect_equal(result$tables$count, 2)
  expect_true(result$tables$available)
  expect_false(result$connection$has_path)
})

test_that("datom_status handles S3 manifest read failure", {
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) stop("S3 error")
  )

  result <- datom_status(conn)

  expect_false(result$tables$available)
  expect_equal(result$tables$count, 0)
})

test_that("datom_status shows git info for developer", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    local_mocked_bindings(
      .datom_storage_read_json = function(conn, s3_key) list(tables = list()),
      .datom_status_git = function(path) {
        list(uncommitted = c("R/foo.R"), branch = "main")
      }
    )

    result <- datom_status(conn)

    expect_equal(result$git$branch, "main")
    expect_equal(result$git$uncommitted, "R/foo.R")
  })
})

test_that("datom_status shows clean git when no changes", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    local_mocked_bindings(
      .datom_storage_read_json = function(conn, s3_key) list(tables = list()),
      .datom_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- datom_status(conn)

    expect_equal(length(result$git$uncommitted), 0)
  })
})

test_that("datom_status shows input_files sync state", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id\n1", "input_files/new_tbl.csv")
    writeLines("id\n2", "input_files/existing.csv")

    # Manifest has existing with matching SHA
    existing_sha <- .datom_compute_file_sha("input_files/existing.csv")
    fs::dir_create(".datom")
    jsonlite::write_json(list(
      tables = list(
        existing = list(original_file_sha = existing_sha)
      )
    ), ".datom/manifest.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_storage_read_json = function(conn, s3_key) list(tables = list()),
      .datom_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- datom_status(conn)

    expect_equal(result$input_files$n_total, 2)
    expect_equal(result$input_files$n_new, 1)
    expect_equal(result$input_files$n_unchanged, 1)
    expect_equal(result$input_files$n_changed, 0)
  })
})

test_that("datom_status omits input_files when dir missing", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    local_mocked_bindings(
      .datom_storage_read_json = function(conn, s3_key) list(tables = list()),
      .datom_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- datom_status(conn)

    expect_null(result$input_files)
  })
})

test_that("datom_status detects changed input files", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")
    writeLines("id\n99", "input_files/orders.csv")

    fs::dir_create(".datom")
    jsonlite::write_json(list(
      tables = list(orders = list(original_file_sha = "old_sha"))
    ), ".datom/manifest.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_storage_read_json = function(conn, s3_key) list(tables = list()),
      .datom_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- datom_status(conn)

    expect_equal(result$input_files$n_changed, 1)
    expect_equal(result$input_files$n_new, 0)
  })
})

test_that("datom_status returns correct structure", {
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) list(tables = list())
  )

  result <- datom_status(conn)

  expect_type(result, "list")
  expect_true("connection" %in% names(result))
  expect_true("tables" %in% names(result))
  expect_equal(result$connection$root, "test-bucket")
})

test_that("datom_status handles empty input_files dir", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create("input_files")

    local_mocked_bindings(
      .datom_storage_read_json = function(conn, s3_key) list(tables = list()),
      .datom_status_git = function(path) {
        list(uncommitted = character(), branch = "main")
      }
    )

    result <- datom_status(conn)

    expect_equal(result$input_files$n_total, 0)
  })
})
