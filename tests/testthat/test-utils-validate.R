# Tests for name validation utilities
# Phase 1, Chunk 3

# --- .datom_validate_name() ----------------------------------------------------

# Valid names
test_that("accepts simple lowercase name", {
  expect_invisible(.datom_validate_name("customers"))
  expect_equal(.datom_validate_name("customers"), "customers")
})

test_that("accepts uppercase name", {
  expect_equal(.datom_validate_name("ADSL"), "ADSL")
})

test_that("accepts name with underscores", {
  expect_equal(.datom_validate_name("lab_results"), "lab_results")
})

test_that("accepts name with hyphens", {
  expect_equal(.datom_validate_name("my-table"), "my-table")
})

test_that("accepts name with numbers", {
  expect_equal(.datom_validate_name("table2"), "table2")
})

test_that("accepts mixed case with numbers and underscores", {
  expect_equal(.datom_validate_name("ADLB_v2_final"), "ADLB_v2_final")
})

test_that("accepts single letter name", {
  expect_equal(.datom_validate_name("x"), "x")
})

test_that("accepts name with spaces", {
  expect_equal(.datom_validate_name("my table"), "my table")
})

test_that("accepts name with parentheses", {
  expect_equal(.datom_validate_name("ADSL (v2)"), "ADSL (v2)")
})

test_that("accepts name with spaces underscores and hyphens combined", {
  expect_equal(.datom_validate_name("Lab Results (final-v2)"), "Lab Results (final-v2)")
})

# Invalid: type/empty
test_that("rejects non-character input", {
  expect_error(.datom_validate_name(123), "single non-NA character")
  expect_error(.datom_validate_name(NULL), "single non-NA character")
  expect_error(.datom_validate_name(TRUE), "single non-NA character")
})

test_that("rejects vector of names", {
  expect_error(.datom_validate_name(c("a", "b")), "single non-NA character")
})

test_that("rejects NA", {
  expect_error(.datom_validate_name(NA_character_), "single non-NA character")
})

test_that("rejects empty string", {
  expect_error(.datom_validate_name(""), "must not be empty")
})

# Invalid: pattern
test_that("rejects name starting with number", {
  expect_error(.datom_validate_name("123abc"), "start with a letter")
})

test_that("rejects name starting with underscore", {
  expect_error(.datom_validate_name("_hidden"), "start with a letter")
})

test_that("rejects name with slashes", {
  expect_error(.datom_validate_name("customers/orders"), "letters, numbers, underscores")
})

test_that("rejects name with dots", {
  expect_error(.datom_validate_name("my.table"), "letters, numbers, underscores")
})

test_that("rejects name with special characters", {
  expect_error(.datom_validate_name("table@1"), "letters, numbers, underscores")
  expect_error(.datom_validate_name("table!"), "letters, numbers, underscores")
  expect_error(.datom_validate_name("table#1"), "letters, numbers, underscores")
})

# Invalid: reserved names
test_that("rejects .metadata", {
  expect_error(.datom_validate_name(".metadata"), "start with a letter")
})

test_that("rejects input_files", {
  expect_error(.datom_validate_name("input_files"), "reserved name")
})

test_that("rejects datom", {
  expect_error(.datom_validate_name("datom"), "reserved name")
})

test_that("rejects reserved names case-insensitively", {
  expect_error(.datom_validate_name("INPUT_FILES"), "reserved name")
  expect_error(.datom_validate_name("Datom"), "reserved name")
})

# Invalid: length
test_that("rejects name over 128 characters", {
  long_name <- paste0("a", paste(rep("b", 128), collapse = ""))
  expect_error(.datom_validate_name(long_name), "128 characters")
})

test_that("accepts name at exactly 128 characters", {
  name_128 <- paste0("a", paste(rep("b", 127), collapse = ""))
  expect_equal(nchar(name_128), 128)
  expect_equal(.datom_validate_name(name_128), name_128)
})


# --- .datom_check_namespace_free() ------------------------------------------

test_that("returns TRUE when namespace is free (no manifest on S3)", {
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) FALSE
  )

  expect_true(.datom_check_namespace_free(conn))
})

test_that("aborts when namespace is occupied by another project", {
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) TRUE,
    .datom_storage_read_json = function(conn, s3_key) {
      list(project_name = "OTHER_PROJECT", tables = list())
    }
  )

  expect_error(
    .datom_check_namespace_free(conn),
    "already occupied.*OTHER_PROJECT"
  )
})

test_that("aborts when namespace is occupied by same project name", {
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) TRUE,
    .datom_storage_read_json = function(conn, s3_key) {
      list(project_name = "test-project", tables = list())
    }
  )

  # Even same project name is blocked — use .force to override

  expect_error(
    .datom_check_namespace_free(conn),
    "already occupied"
  )
})

test_that("shows <unknown> when manifest has no project_name field", {
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) TRUE,
    .datom_storage_read_json = function(conn, s3_key) {
      list(tables = list())  # pre-Phase 7 manifest without project_name
    }
  )

  expect_error(
    .datom_check_namespace_free(conn),
    "already occupied.*unknown"
  )
})

test_that("shows <unreadable> when manifest read fails", {
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) TRUE,
    .datom_storage_read_json = function(conn, s3_key) {
      stop("access denied")
    }
  )

  expect_error(
    .datom_check_namespace_free(conn),
    "already occupied.*unreadable"
  )
})

test_that("error message includes S3 location", {
  conn <- mock_datom_conn(list(), root = "my-bucket", prefix = "data/prod")

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) TRUE,
    .datom_storage_read_json = function(conn, s3_key) {
      list(project_name = "PROD_DATA")
    }
  )

  expect_error(
    .datom_check_namespace_free(conn),
    "my-bucket"
  )
})

test_that("error message suggests .force = TRUE", {
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) TRUE,
    .datom_storage_read_json = function(conn, s3_key) {
      list(project_name = "EXISTING")
    }
  )

  expect_error(
    .datom_check_namespace_free(conn),
    "\\.force = TRUE"
  )
})


# --- .datom_validate_sha() (#74 G) ---------------------------------------------

test_that(".datom_validate_sha accepts 6-64 lowercase hex", {
  expect_invisible(.datom_validate_sha("abc123"))
  expect_equal(.datom_validate_sha("abc123"), "abc123")
  expect_equal(.datom_validate_sha(paste(rep("a", 64), collapse = "")),
               paste(rep("a", 64), collapse = ""))
  expect_equal(.datom_validate_sha("deadbeef"), "deadbeef")
})

test_that(".datom_validate_sha rejects path-traversal strings", {
  expect_error(.datom_validate_sha("../../etc/passwd"), "hex")
  expect_error(.datom_validate_sha("../secret"), "hex")
  expect_error(.datom_validate_sha("a/b/c"), "hex")
})

test_that(".datom_validate_sha rejects non-hex, uppercase, and out-of-range", {
  expect_error(.datom_validate_sha("not-hex"), "hex")
  expect_error(.datom_validate_sha("ABC123"), "hex")   # uppercase
  expect_error(.datom_validate_sha("abc"), "hex")      # too short (< 6)
  expect_error(.datom_validate_sha(paste(rep("a", 65), collapse = "")), "hex")  # > 64
})

test_that(".datom_validate_sha rejects non-scalar / NA / non-character", {
  expect_error(.datom_validate_sha(NA_character_), "hex")
  expect_error(.datom_validate_sha(123), "hex")
  expect_error(.datom_validate_sha(c("abc123", "def456")), "hex")
  expect_error(.datom_validate_sha(character(0)), "hex")
})

test_that(".datom_validate_sha uses the arg label in the message", {
  err <- expect_error(.datom_validate_sha("zzz", arg = "data_sha"))
  expect_match(conditionMessage(err), "data_sha")
})


# === .datom_validate_rel_key() ================================================

test_that(".datom_validate_rel_key accepts ordinary relative keys", {
  expect_invisible(.datom_validate_rel_key("dm/.metadata/metadata.json"))
  expect_equal(
    .datom_validate_rel_key("dm/abc123.parquet"),
    "dm/abc123.parquet"
  )
  expect_invisible(.datom_validate_rel_key(".metadata/manifest.json"))
  expect_invisible(.datom_validate_rel_key("single-segment.json"))
})

test_that(".datom_validate_rel_key refuses non-string and empty input", {
  expect_error(.datom_validate_rel_key(NULL), "single non-NA character")
  expect_error(.datom_validate_rel_key(NA_character_), "single non-NA character")
  expect_error(.datom_validate_rel_key(c("a.json", "b.json")), "single non-NA character")
  expect_error(.datom_validate_rel_key(42), "single non-NA character")
  expect_error(.datom_validate_rel_key(""), "must not be empty")
})

test_that(".datom_validate_rel_key refuses traversal segments", {
  # On the local backend the key is pasted into a path and resolved by the
  # filesystem, so a `..` segment escapes the datom namespace entirely.
  expect_error(.datom_validate_rel_key("../../secrets.json"), "path segment")
  expect_error(.datom_validate_rel_key("dm/../../secrets.json"), "path segment")
  expect_error(.datom_validate_rel_key("dm/.."), "path segment")
})

test_that(".datom_validate_rel_key allows dots that are not a traversal segment", {
  # Only a whole `..` segment is a traversal; these are legitimate keys and
  # the guard must not become a blanket ban on the dot character.
  expect_invisible(.datom_validate_rel_key("dm/.metadata/metadata.json"))
  expect_invisible(.datom_validate_rel_key("my.data/abc.json"))
  expect_invisible(.datom_validate_rel_key("dm/..hidden.json"))
})

test_that(".datom_validate_rel_key refuses an absolute path", {
  expect_error(.datom_validate_rel_key("/dm/abc.json"), "not an absolute path")
  expect_error(.datom_validate_rel_key("//dm/abc.json"), "not an absolute path")
})

test_that(".datom_validate_rel_key refuses a full key passed as relative", {
  # The double-prefix hazard: this resolves under
  # `{prefix}/datom/{prefix}/datom/...` and silently finds nothing, so it
  # reads to the caller as a missing object rather than a malformed key.
  err <- expect_error(
    .datom_validate_rel_key("proj/datom/dm/.metadata/metadata.json"),
    "full storage key"
  )
  expect_match(conditionMessage(err), "relative")

  expect_error(.datom_validate_rel_key("datom/dm/abc.json"), "full storage key")
})

test_that(".datom_validate_rel_key uses the arg label in the message", {
  err <- expect_error(.datom_validate_rel_key("", arg = "prefix_key"))
  expect_match(conditionMessage(err), "prefix_key")
})
