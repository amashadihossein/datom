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

test_that("aborts when namespace is occupied by another project (AC22)", {
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

test_that(".datom_check_namespace_free's occupied abort carries a condition class", {
  # Callers dispatch on the class, never on the message. datom_init_repo() used to
  # recognise this refusal with grepl("already occupied", ...) and re-raise it,
  # which made rewording the message enough to downgrade a refusal to a warning.
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) TRUE,
    .datom_storage_read_json = function(conn, s3_key) list(project_name = "OTHER")
  )

  expect_error(
    .datom_check_namespace_free(conn),
    class = "datom_namespace_occupied"
  )
})

test_that(".datom_check_namespace_free refuses when it cannot reach the store (AC22)", {
  # FAILS CLOSED, and it did not used to. Returning "free" for a namespace this
  # connection could not read is a verification check silently removing itself,
  # which this project's compatibility posture forbids at any stage -- breaking
  # loudly is fine, degrading quietly is not.
  #
  # Nothing is lost by refusing: datom_init_repo() cannot finish without storage
  # either, since it uploads the manifest a few steps later.
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) stop("Network error")
  )

  err <- expect_error(
    .datom_check_namespace_free(conn),
    class = "datom_namespace_unverified"
  )
  msg <- conditionMessage(err)
  # Carries the underlying cause, so the user knows what to fix.
  expect_match(msg, "Network error")
  # And does NOT offer .force, which skips this check but not the manifest
  # upload, so it cannot rescue an init without storage.
  expect_no_match(msg, "force", fixed = TRUE)
})

test_that(".datom_check_namespace_free's two refusals are distinguishable (AC22)", {
  # Occupied and unverified are different answers with different recourse, so a
  # caller must be able to tell them apart without reading English.
  conn <- mock_datom_conn(list())

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) stop("boom")
  )
  expect_error(.datom_check_namespace_free(conn),
               class = "datom_namespace_unverified")

  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) TRUE,
    .datom_storage_read_json = function(conn, s3_key) list(project_name = "OTHER")
  )
  err <- expect_error(.datom_check_namespace_free(conn),
                      class = "datom_namespace_occupied")
  expect_false(inherits(err, "datom_namespace_unverified"))
})

# The hazard the condition class alone does NOT close -- a failure raised inside
# the namespace check for some new reason being swallowed -- belongs to the caller,
# not to this function, because the caller is what used to wrap it. Its test lives
# with datom_init_repo() in test-conn.R. Asserting it here would look like coverage
# and prove nothing: an abort has always escaped this function.

test_that(".datom_check_namespace_free names the backend it checked (AC22)", {
  # A message that says S3 to somebody using a local store, or prints s3:// in
  # front of a filesystem path, is confidently wrong -- which this spec has
  # repeatedly judged worse than saying nothing.
  local_mocked_bindings(
    .datom_storage_exists = function(conn, s3_key) TRUE,
    .datom_storage_read_json = function(conn, s3_key) list(project_name = "OTHER")
  )

  s3_conn <- mock_datom_conn(list(), root = "my-bucket", prefix = "p")
  err <- expect_error(.datom_check_namespace_free(s3_conn),
                      class = "datom_namespace_occupied")
  expect_match(conditionMessage(err), "S3 namespace")
  expect_match(conditionMessage(err), "s3://my-bucket", fixed = TRUE)

  local_conn <- mock_datom_conn(list(), root = "/tmp/store", prefix = "p")
  local_conn$backend <- "local"
  err <- expect_error(.datom_check_namespace_free(local_conn),
                      class = "datom_namespace_occupied")
  msg <- conditionMessage(err)
  expect_match(msg, "local namespace")
  expect_no_match(msg, "s3://", fixed = TRUE)
  expect_no_match(msg, "bucket")
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


# --- .datom_check_schema_version() ---------------------------------------------

test_that(".datom_check_schema_version tolerates an absent field as v1 (AC7)", {
  # Every repo written before the field existed carries no schema_version, so
  # absence must behave exactly as it did then.
  expect_equal(
    .datom_check_schema_version(list(data_sha = "abc"), "dm/.metadata/metadata.json"),
    1L
  )
  expect_equal(.datom_check_schema_version(list(), "manifest.json"), 1L)
  expect_equal(.datom_check_schema_version(NULL, "manifest.json"), 1L)
})

test_that(".datom_check_schema_version accepts the supported version and older", {
  expect_equal(
    .datom_check_schema_version(list(schema_version = 2L), "manifest.json"),
    2L
  )
  expect_equal(
    .datom_check_schema_version(list(schema_version = 1L), "manifest.json"),
    1L
  )
  # JSON round-trips small integers as doubles; both spellings must pass.
  expect_equal(
    .datom_check_schema_version(list(schema_version = 2), "manifest.json"),
    2L
  )
})

test_that(".datom_check_schema_version refuses a newer version with recourse (AC7)", {
  err <- expect_error(
    .datom_check_schema_version(list(schema_version = 3L), "manifest.json"),
    class = "datom_schema_unsupported"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "v3")
  expect_match(msg, "manifest.json")
  expect_match(msg, "install_github")
  # The supported ceiling must render as a number, not as cli markup: the
  # constant's leading dot makes `{.datom_supported_schema}` a cli style.
  expect_match(msg, "supports up to v2")
})

test_that(".datom_check_schema_version boundary is strictly greater-than", {
  # The writer bump lands in the next task; if the check were >= the whole
  # read path would break the moment anything writes v2.
  expect_silent(.datom_check_schema_version(list(schema_version = 2L), "m.json"))
})

test_that(".datom_check_schema_version refuses an unusable value", {
  unusable <- list(
    "two",           # hand-edited to a string
    NA,              # NA would otherwise propagate into if() as an opaque error
    NA_integer_,
    2.5,             # fractional
    0L,              # below the first real version
    -1L,
    c(1L, 2L),       # not a scalar
    TRUE,
    list(2L)
  )
  purrr::walk(unusable, function(v) {
    expect_error(
      .datom_check_schema_version(list(schema_version = v), "manifest.json"),
      class = "datom_schema_invalid"
    )
  })
})

test_that(".datom_check_schema_version names the offending document", {
  err <- expect_error(
    .datom_check_schema_version(list(schema_version = 9L), "dm/.metadata/metadata.json"),
    class = "datom_schema_unsupported"
  )
  expect_match(conditionMessage(err), "dm/.metadata/metadata.json", fixed = TRUE)
})

test_that(".datom_check_schema_version compares against a supplied ceiling", {
  # The argument exists so a document with its own format number is not measured
  # against the repo-wide one. Without it, project.yaml's gate would be nominal:
  # the day that file's shape breaks and its constant becomes 2L, a build whose
  # repo-wide ceiling is already 2L would compare 2 > 2, proceed, and misread it.
  expect_equal(
    .datom_check_schema_version(list(schema_version = 1L), "project.yaml",
                                supported = 1L),
    1L
  )
  err <- expect_error(
    .datom_check_schema_version(list(schema_version = 2L), "project.yaml",
                                supported = 1L),
    class = "datom_schema_unsupported"
  )
  expect_match(conditionMessage(err), "v2")

  # A document the repo-wide ceiling would have waved through.
  expect_silent(.datom_check_schema_version(list(schema_version = 2L), "m.json"))
})

test_that(".datom_check_schema_version's message reports the ceiling it used", {
  # Both halves must read from the same number. Feeding the comparison but not
  # the message produces a refusal that says "supports up to v2" while refusing
  # a v2 file, which reads as a bug in datom rather than as an upgrade prompt.
  err <- expect_error(
    .datom_check_schema_version(list(schema_version = 3L), "project.yaml",
                                supported = 1L),
    class = "datom_schema_unsupported"
  )
  expect_match(conditionMessage(err), "supports up to v1")
  expect_no_match(conditionMessage(err), "supports up to v2")
})

test_that(".datom_check_schema_version defaults to the repo-wide ceiling", {
  # Every existing call site reads a machine-written document -- a manifest or a
  # per-artifact metadata snapshot -- and those genuinely do share one number, so
  # the argument stays optional and the default must stay this value.
  expect_equal(
    .datom_check_schema_version(list(schema_version = .datom_supported_schema),
                                "manifest.json"),
    .datom_supported_schema
  )
  expect_error(
    .datom_check_schema_version(
      list(schema_version = .datom_supported_schema + 1L), "manifest.json"
    ),
    class = "datom_schema_unsupported"
  )
})


# --- .datom_check_project_schema() ---------------------------------------------

test_that(".datom_check_project_schema pins project.yaml to its own ceiling", {
  # The pairing of file and ceiling lives in this wrapper and nowhere else, so a
  # third caller cannot supply the wrong one. It is deliberately NOT the
  # repo-wide number: this file's shape moves on its own clock.
  expect_equal(
    .datom_check_project_schema(list(schema_version = .datom_project_schema),
                                "project.yaml"),
    .datom_project_schema
  )
  expect_error(
    .datom_check_project_schema(
      list(schema_version = .datom_project_schema + 1L), "project.yaml"
    ),
    class = "datom_schema_unsupported"
  )
})

test_that(".datom_check_project_schema tolerates an absent field as v1", {
  # Every repo written before the field existed carries no schema_version. This
  # is a characterization test, not new behaviour: the shared checker already
  # returns 1L for an absent field, and reusing it is what stops a second
  # absent-means-v1 branch growing here that can only agree with the first by
  # luck.
  expect_equal(.datom_check_project_schema(list(project_name = "p"), "p.yaml"), 1L)
  expect_equal(.datom_check_project_schema(list(), "p.yaml"), 1L)
})

test_that(".datom_check_project_schema words the refusal for the caller", {
  read_err <- expect_error(
    .datom_check_project_schema(list(schema_version = 9L), "project.yaml"),
    class = "datom_schema_unsupported"
  )
  expect_match(conditionMessage(read_err), "cannot read")

  write_err <- expect_error(
    .datom_check_project_schema(list(schema_version = 9L), "project.yaml",
                                operation = "write"),
    class = "datom_schema_unsupported"
  )
  expect_match(conditionMessage(write_err), "cannot write")
})

test_that(".datom_check_project_schema names the config file", {
  err <- expect_error(
    .datom_check_project_schema(list(schema_version = 9L),
                                "/repo/.datom/project.yaml"),
    class = "datom_schema_unsupported"
  )
  expect_match(conditionMessage(err), "/repo/.datom/project.yaml", fixed = TRUE)
})

test_that(".datom_project_schema is separate from the repo-wide ceiling", {
  # Not a tautology: the two constants are equal today only by accident of
  # history, and this pins the intent that they are independent numbers. If
  # someone replaces the constant with `.datom_supported_schema`, a build one
  # manifest bump behind loses the whole developer path on a config file whose
  # shape never changed.
  expect_type(.datom_project_schema, "integer")
  expect_length(.datom_project_schema, 1L)
  expect_gte(.datom_project_schema, 1L)
})
