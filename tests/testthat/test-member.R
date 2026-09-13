# Tests for datom_member() and the member/tag validators (R/member.R).
#
# All storage access is mocked via .datom_storage_read_json; no real network
# egress occurs (the fail-closed guard in setup.R stays silent). Cross-project
# cases use two distinct mock stores keyed by conn$project_name.
#
# Versions are SHA-like (6-64 lowercase hex) since datom_member() validates
# them via .datom_validate_sha() before splicing into a storage key (#74 G).

# --- Fixtures ----------------------------------------------------------------

.member_conn <- function(project_name = "study001") {
  conn <- mock_datom_conn("mock-client")
  conn$project_name <- project_name
  conn
}

# A versioned metadata snapshot as datom writes one. `kind` is present from
# Task 7 onward; pass NULL to model a snapshot written before it existed.
.member_snapshot <- function(kind = "table", data_sha = "d_dm_aaa") {
  snap <- list(data_sha = data_sha, hash_algo = "datom-cv1")
  if (!is.null(kind)) snap$kind <- kind
  snap
}

# A well-formed member record, for the validator's tests.
.valid_member <- function(name = "dm",
                          version = "9f3aa1b2c3",
                          project = "study001",
                          kind = "table",
                          tags = NULL) {
  out <- list(
    id = list(project = project, name = name, kind = kind, version = version)
  )
  if (!is.null(tags)) out$tags <- tags
  out
}


# --- datom_member(): success paths -------------------------------------------

test_that("returns an id of exactly the four fields, kind from the snapshot", {
  conn <- .member_conn("study001")
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot("table")
  )

  m <- datom_member(conn, "dm", "9f3aa1b2c3")

  expect_setequal(names(m), "id")
  expect_setequal(names(m$id), c("project", "name", "kind", "version"))
  expect_length(m$id, 4L)
  expect_equal(m$id$project, "study001")
  expect_equal(m$id$project, conn$project_name)
  expect_equal(m$id$name, "dm")
  expect_equal(m$id$kind, "table")
  expect_equal(m$id$version, "9f3aa1b2c3")
})

test_that("a member of a set is typed as a set", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot("set")
  )

  expect_equal(datom_member(conn, "adam", "7c1bb2d3e4")$id$kind, "set")
})

test_that("kind defaults to table for a snapshot written before the field", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot(kind = NULL)
  )

  # Not padding: every pre-`kind` snapshot describes a table, because sets did
  # not exist yet, and an untyped pointer is one a reader cannot resolve.
  expect_equal(datom_member(conn, "dm", "9f3aa1b2c3")$id$kind, "table")
})

test_that("record retains no connection and is serializable", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  m <- datom_member(conn, "dm", "9f3aa1b2c3", tags = list(type = "input"))

  expect_false("conn" %in% names(m))
  expect_false(any(vapply(m, inherits, logical(1), what = "datom_conn")))

  back <- jsonlite::fromJSON(
    jsonlite::toJSON(m, auto_unbox = TRUE),
    simplifyVector = FALSE
  )
  expect_equal(back$id$name, "dm")
  expect_equal(back$id$kind, "table")
  expect_equal(back$tags$type, "input")
})

test_that("tags are carried, single- and multi-valued", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  m <- datom_member(
    conn, "adsl", "7c1bb2d3e4",
    tags = list(type = "output", domain = c("safety", "efficacy"))
  )

  expect_setequal(names(m), c("id", "tags"))
  expect_equal(m$tags$type, "output")
  expect_equal(m$tags$domain, c("safety", "efficacy"))
})


# --- datom_member(): the tags key must be ABSENT, never NULL -----------------
#
# Nothing about identity depends on this -- an absent tag map and an empty one
# both encode as h(0x03), so no hash moves and no golden changes. What breaks is
# one layer down: jsonlite writes a NULL element as `{}` rather than dropping
# it, so a record carrying `tags = NULL` would put an empty object into every
# untagged member of the stored payload, which is the one spelling a writer must
# never emit.

test_that("an untagged member omits the tags key rather than nulling it", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  m <- datom_member(conn, "dm", "9f3aa1b2c3")

  expect_false("tags" %in% names(m))
  # The failure this guards is in the emitted bytes, so assert on them.
  json <- as.character(jsonlite::toJSON(m, auto_unbox = TRUE))
  expect_false(grepl("tags", json, fixed = TRUE))
})

test_that("a tag map that tidies away to nothing also omits the key", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  m <- datom_member(conn, "dm", "9f3aa1b2c3", tags = list(domain = character(0)))

  expect_false("tags" %in% names(m))
  json <- as.character(jsonlite::toJSON(m, auto_unbox = TRUE))
  expect_false(grepl("tags", json, fixed = TRUE))
})

test_that("an untagged member is accepted by the sv1 encoder unchanged", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  bare <- datom_member(conn, "dm", "9f3aa1b2c3")
  with_empty <- c(bare, list(tags = list()))

  # Identical hashes: which is exactly why omitting the key cannot be asserted
  # through identity and needs the byte-level test above.
  expect_equal(
    .datom_sv1_hex(.datom_sv1_member(bare)),
    .datom_sv1_hex(.datom_sv1_member(with_empty))
  )
})


# --- datom_member(): tag tidying (must NOT abort) ----------------------------

test_that("a key with no labels is dropped, not refused", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  m <- datom_member(
    conn, "dm", "9f3aa1b2c3",
    tags = list(type = "input", domain = character(0))
  )

  expect_setequal(names(m$tags), "type")
})

test_that("a NULL tag value is dropped, not refused", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  # What `list(domain = f())` looks like when f() returned nothing. Same
  # meaning as character(0), so the two must behave the same way.
  m <- datom_member(
    conn, "dm", "9f3aa1b2c3",
    tags = list(type = "input", domain = NULL)
  )

  expect_setequal(names(m$tags), "type")
})

test_that("tag value order and duplication are left for the write to canonicalize", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  m <- datom_member(
    conn, "dm", "9f3aa1b2c3",
    tags = list(domain = c("safety", "safety", "efficacy"))
  )

  # Deliberately untouched: canonical form has one implementation, and it is
  # the set write's. Neither spelling is an error, and both hash identically.
  expect_equal(m$tags$domain, c("safety", "safety", "efficacy"))
})


# --- datom_member(): tag refusals (AC27 a/b/c, per-member half) --------------

test_that("an empty-string tag value is refused (AC27 c)", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  err <- expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3", tags = list(domain = ""))
  )
  expect_match(conditionMessage(err), "empty label")
  # The offending key is named, not just the fact that something is wrong.
  expect_match(conditionMessage(err), "domain")
})

test_that("an empty string among several values is refused", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3",
                 tags = list(domain = c("safety", ""))),
    "empty label"
  )
})

test_that("NA as a tag value is refused (AC27 b)", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3", tags = list(domain = NA)),
    "NA"
  )
  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3",
                 tags = list(domain = NA_character_)),
    "NA"
  )
  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3",
                 tags = list(domain = c("safety", NA))),
    "NA"
  )
})

test_that("non-text tag values are refused, naming the key (AC27 a)", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  bad <- list(
    number  = 500,
    logical = TRUE,
    factor  = factor("a"),
    fn      = mean
  )

  for (nm in names(bad)) {
    err <- expect_error(
      datom_member(conn, "dm", "9f3aa1b2c3", tags = stats::setNames(
        list(bad[[nm]]), nm
      ))
    )
    expect_match(conditionMessage(err), nm)
  }
})

test_that("a nested object in a value position is refused", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3",
                 tags = list(domain = list(inner = "safety"))),
    "object"
  )
})

test_that("a duplicated or blank tag key is refused", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3",
                 tags = list(domain = "safety", domain = "efficacy")),
    "duplicate"
  )
  # Partially named: one key present, one blank.
  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3",
                 tags = list(type = "output", "safety")),
    "non-empty name"
  )
  # Wholly unnamed reads as "not a named list", which is the truer diagnosis.
  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3", tags = list("safety")),
    "named list"
  )
})

test_that("tags that are not a named list are refused", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3", tags = c(type = "output")),
    "named list"
  )
  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3", tags = "output"),
    "named list"
  )
})

test_that("tags are validated before the snapshot is read", {
  conn <- .member_conn()
  reads <- 0L
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      reads <<- reads + 1L
      .member_snapshot()
    }
  )

  expect_error(
    datom_member(conn, "dm", "9f3aa1b2c3", tags = list(domain = 500)),
    "domain"
  )
  # A malformed tag map costs no storage round trip.
  expect_equal(reads, 0L)
})


# --- datom_member(): other error paths --------------------------------------

test_that("aborts when conn is not a datom_conn", {
  expect_error(
    datom_member(list(project_name = "x"), "dm", "9f3aa1"),
    "datom_conn"
  )
})

test_that("aborts on an invalid artifact name", {
  conn <- .member_conn()
  expect_error(datom_member(conn, "", "9f3aa1"), "empty")
  expect_error(datom_member(conn, "renv", "9f3aa1"), "reserved")
})

test_that("aborts on an invalid version", {
  conn <- .member_conn()
  expect_error(datom_member(conn, "dm", ""), "version")
  expect_error(datom_member(conn, "dm", 123), "version")
  expect_error(datom_member(conn, "dm", NA_character_), "version")
})

test_that("aborts on a path-traversal version (#74 G)", {
  conn <- .member_conn()
  expect_error(datom_member(conn, "dm", "../../etc/passwd"), "hex")
  expect_error(datom_member(conn, "dm", "not-hex-zzz"), "hex")
  expect_error(datom_member(conn, "dm", "abc"), "hex")
})

test_that("aborts when the snapshot read fails, naming name/version/project", {
  conn <- .member_conn("study001")
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      cli::cli_abort("Object not found")
    }
  )

  err <- expect_error(datom_member(conn, "dm", "9f3aa1b2c3"))
  msg <- conditionMessage(err)
  expect_match(msg, "dm")
  expect_match(msg, "9f3aa1b2c3")
  expect_match(msg, "study001")
})

test_that("aborts when the snapshot declares an unknown kind", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot("view")
  )

  err <- expect_error(datom_member(conn, "dm", "9f3aa1b2c3"))
  msg <- conditionMessage(err)
  # A kind this build cannot classify is refused rather than passed through as
  # a pointer nothing can resolve; the message says how to proceed.
  expect_match(msg, "table")
  expect_match(msg, "set")
  expect_match(msg, "upgrade")
})

test_that("aborts when the snapshot's kind is not a single string", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      .member_snapshot(kind = c("table", "set"))
    }
  )

  expect_error(datom_member(conn, "dm", "9f3aa1b2c3"), "kind")
})


# --- datom_member(): audit invariants ---------------------------------------

test_that("datom_member carries no data_sha, as parameter or as field", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  # The version already pins content; a second copy is a second thing to keep
  # consistent. Deliberate divergence from datom_parent().
  expect_false("data_sha" %in% names(formals(datom_member)))
  m <- datom_member(conn, "dm", "9f3aa1b2c3")
  expect_false("data_sha" %in% names(m))
  expect_false("data_sha" %in% names(m$id))
})

test_that("a constructed member satisfies the validator and the encoder", {
  conn <- .member_conn()
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) .member_snapshot()
  )

  members <- list(
    datom_member(conn, "dm", "9f3aa1b2c3"),
    datom_member(conn, "adsl", "7c1bb2d3e4", tags = list(type = "output"))
  )

  expect_true(.datom_validate_members(members))
  expect_silent(.datom_sv1_member(members[[2]]))
})


# --- datom_member(): cross-project ------------------------------------------

test_that("project is derived per-connection across two project stores", {
  conn_a <- .member_conn("study001")
  conn_b <- .member_conn("labdata")

  store_a <- list("dm/.metadata/9f3aa1b2c3.json" = .member_snapshot("table"))
  store_b <- list("adam/.metadata/7c1bb2d3e4.json" = .member_snapshot("set"))

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

  m_a <- datom_member(conn_a, "dm", "9f3aa1b2c3")
  m_b <- datom_member(conn_b, "adam", "7c1bb2d3e4")

  expect_equal(m_a$id$project, "study001")
  expect_equal(m_a$id$kind, "table")
  expect_equal(m_b$id$project, "labdata")
  expect_equal(m_b$id$kind, "set")
  expect_setequal(names(m_a$id), names(m_b$id))
})


# --- .datom_drop_empty_tags() ------------------------------------------------

test_that("empty-valued keys are dropped and the rest kept unchanged", {
  tags <- list(
    type   = "output",
    domain = character(0),
    role   = NULL,
    empty  = list(),
    multi  = c("a", "b")
  )

  out <- .datom_drop_empty_tags(tags)

  expect_setequal(names(out), c("type", "multi"))
  expect_equal(out$type, "output")
  expect_equal(out$multi, c("a", "b"))
})

test_that("NULL and a fully-populated map pass through untouched", {
  expect_null(.datom_drop_empty_tags(NULL))
  tags <- list(type = "output")
  expect_identical(.datom_drop_empty_tags(tags), tags)
})

test_that("a non-list is returned untouched for the validator to report", {
  # Dropping must not be where a type error surfaces -- the validator has the
  # message that names the required shape.
  expect_identical(.datom_drop_empty_tags(c(type = "output")),
                   c(type = "output"))
})

test_that("a map whose every value is empty becomes an empty list", {
  out <- .datom_drop_empty_tags(list(a = character(0), b = NULL))
  expect_length(out, 0L)
})


# --- .datom_validate_tag_map() ----------------------------------------------

test_that("NULL, empty, and well-formed maps are valid", {
  expect_true(.datom_validate_tag_map(NULL))
  expect_invisible(.datom_validate_tag_map(NULL))
  expect_true(.datom_validate_tag_map(list()))
  expect_true(.datom_validate_tag_map(
    list(type = "output", domain = c("safety", "efficacy"))
  ))
})

test_that("a list of length-1 strings is valid -- the parsed-JSON spelling", {
  # What a tag map looks like after a round trip with simplifyVector = FALSE.
  expect_true(.datom_validate_tag_map(list(domain = list("safety", "efficacy"))))
})

test_that("the label used in messages is the one the caller passed", {
  err <- expect_error(
    .datom_validate_tag_map(list(domain = ""), "members[[2]]$tags")
  )
  expect_match(conditionMessage(err), "members[[2]]$tags$domain", fixed = TRUE)
})

test_that("an optional remedy bullet is appended to every abort", {
  err <- expect_error(
    .datom_validate_tag_map(list(domain = ""), "tags",
                            remedy = "Use {.fn datom_member}.")
  )
  expect_match(conditionMessage(err), "datom_member")
})

test_that("an empty value passes validation, because it is a tidy case", {
  # The drop runs first at every call site; refusing here would make the tidy
  # rule unreachable, which is the ordering R2.14 forbids.
  expect_true(.datom_validate_tag_map(list(domain = character(0))))
})


# --- .datom_validate_members() ----------------------------------------------

test_that("NULL and an empty list are valid, and zero members is not our call", {
  # The zero-member refusal is a payload-level decision and belongs to the set
  # write, which sees the whole payload. Duplicating it here would put one
  # refusal in two places with two messages.
  expect_true(.datom_validate_members(NULL))
  expect_invisible(.datom_validate_members(NULL))
  expect_true(.datom_validate_members(list()))
})

test_that("a well-formed member list is valid", {
  members <- list(
    .valid_member("dm", "9f3aa1b2c3"),
    .valid_member("adsl", "7c1bb2d3e4", kind = "set",
                  tags = list(type = "output"))
  )
  expect_true(.datom_validate_members(members))
})

test_that("a named list of members is rejected", {
  expect_error(
    .datom_validate_members(list(a = .valid_member())),
    "named list"
  )
})

test_that("a non-list member is rejected naming its index", {
  err <- expect_error(
    .datom_validate_members(list(.valid_member(), "nope"))
  )
  expect_match(conditionMessage(err), "Member 2")
})

test_that("an unexpected top-level field on a member is rejected", {
  # The likely accident: passing a datom_parent() record, or attaching user
  # metadata beside the id instead of putting it in tags.
  bad <- .valid_member()
  bad$data_sha <- "d_dm_aaa"

  err <- expect_error(.datom_validate_members(list(bad)))
  expect_match(conditionMessage(err), "data_sha")
  expect_match(conditionMessage(err), "datom_member")
})

test_that("a missing or malformed id is rejected", {
  no_id <- list(tags = list(type = "output"))
  expect_error(.datom_validate_members(list(no_id)), "id")

  bad <- .valid_member()
  bad$id <- "dm"
  expect_error(.datom_validate_members(list(bad)), "id")
})

test_that("an id missing one of the four fields is rejected, naming it", {
  for (field in c("project", "name", "kind", "version")) {
    bad <- .valid_member()
    bad$id[[field]] <- NULL
    err <- expect_error(.datom_validate_members(list(bad)))
    expect_match(conditionMessage(err), field)
  }
})

test_that("an id carrying a fifth field is rejected", {
  bad <- .valid_member()
  bad$id$data_sha <- "d_dm_aaa"
  err <- expect_error(.datom_validate_members(list(bad)))
  expect_match(conditionMessage(err), "data_sha")
})

test_that("an id field that is NA is rejected", {
  # THE POINT OF THIS TEST: mirroring .datom_validate_parents() verbatim would
  # accept NA_character_, because it is character, has length 1, and
  # nzchar(NA_character_) is TRUE. This validator has to be stricter than its
  # model, and the test below pins that the model really is looser.
  for (field in c("project", "name", "kind", "version")) {
    bad <- .valid_member()
    bad$id[[field]] <- NA_character_
    expect_error(.datom_validate_members(list(bad)), "non-empty string")
  }
})

test_that("the parents validator does accept NA, which is why we diverge", {
  # Pins the looseness this validator deliberately does not inherit. Not a
  # claim that .datom_validate_parents() is correct -- that is out of scope
  # here -- only that a verbatim mirror would have shipped the hole.
  loose <- list(
    list(source = "study001", table = "dm", version = "9f3aa1b2c3",
         data_sha = NA_character_)
  )
  expect_true(.datom_validate_parents(loose))
})

test_that("an id field that is empty, non-character, or multi-element is rejected", {
  for (val in list("", 123, c("a", "b"), TRUE, list("a"))) {
    bad <- .valid_member()
    bad$id$name <- val
    expect_error(.datom_validate_members(list(bad)), "non-empty string")
  }
})

test_that("a kind outside the two datom knows is rejected", {
  bad <- .valid_member(kind = "view")
  err <- expect_error(.datom_validate_members(list(bad)))
  expect_match(conditionMessage(err), "view")
  expect_match(conditionMessage(err), "table")
})

test_that("member tags are validated through the shared tag grammar", {
  expect_error(
    .datom_validate_members(list(.valid_member(tags = list(domain = "")))),
    "empty label"
  )
  expect_error(
    .datom_validate_members(list(.valid_member(tags = list(domain = 500)))),
    "domain"
  )
  err <- expect_error(
    .datom_validate_members(list(
      .valid_member(),
      .valid_member(tags = list(domain = NA))
    ))
  )
  # The failing member is identifiable from the message.
  expect_match(conditionMessage(err), "members[[2]]$tags", fixed = TRUE)
})

test_that("every refusal points at datom_member as the remedy", {
  cases <- list(
    list(a = .valid_member()),
    list("nope"),
    list(list(tags = list(type = "x"))),
    list(.valid_member(kind = "view"))
  )
  for (case in cases) {
    err <- expect_error(.datom_validate_members(case))
    expect_match(conditionMessage(err), "datom_member")
  }
})

