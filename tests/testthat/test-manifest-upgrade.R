# Tests for the manifest schema upgrade chain: one step per adjacent version
# pair, plus the dispatcher that applies them in order.


# --- .datom_manifest_upgrade_v1_to_v2() ---------------------------------------

test_that("the v1 step moves the artifact list and types every entry", {
  v1 <- list(
    project_name = "p",
    tables = list(
      dm = list(current_version = "abc", size_bytes = 10),
      lb = list(current_version = "def", size_bytes = 20)
    ),
    summary = list(total_tables = 2L)
  )

  v2 <- .datom_manifest_upgrade_v1_to_v2(v1)

  expect_null(v2$tables)
  expect_length(v2$artifacts, 2L)
  expect_equal(v2$artifacts$dm$kind, "table")
  expect_equal(v2$artifacts$lb$kind, "table")
  # Everything else on the entry survives, unmoved.
  expect_equal(v2$artifacts$dm$current_version, "abc")
  expect_equal(v2$artifacts$lb$size_bytes, 20)
})


test_that("the v1 step renames in place, so sibling keys keep their position", {
  # An in-place rename rather than add-then-remove: a key this build does not
  # recognise must come out of the conversion where it went in, because a later
  # build is the one that knows what it means.
  v1 <- list(
    project_name = "p",
    tables = list(dm = list(current_version = "abc")),
    something_from_a_later_build = list(a = 1),
    summary = list()
  )

  v2 <- .datom_manifest_upgrade_v1_to_v2(v1)

  expect_equal(
    names(v2),
    c("project_name", "artifacts", "something_from_a_later_build", "summary")
  )
  expect_equal(v2$something_from_a_later_build$a, 1)
})


test_that("the v1 step leaves a document with no artifact list without one", {
  # Absent and empty are different states -- a truncated document versus a repo
  # with nothing in it -- and only one of them is worth recovering from.
  v2 <- .datom_manifest_upgrade_v1_to_v2(list(project_name = "p"))

  expect_false("artifacts" %in% names(v2))
  expect_false("tables" %in% names(v2))
})


test_that("the v1 step does not stamp the version itself", {
  # Recording the version reached is the dispatcher's job. A step that stamped
  # would declare the document finished halfway along a longer chain.
  v2 <- .datom_manifest_upgrade_v1_to_v2(list(tables = list(dm = list())))

  expect_null(v2$schema_version)
})


# --- .datom_manifest_upgrade() ------------------------------------------------

test_that("the dispatcher converts a v1 document and records the version reached", {
  v1 <- list(tables = list(dm = list(current_version = "abc")))

  upgraded <- .datom_manifest_upgrade(v1, 1L)

  expect_equal(upgraded$schema_version, 2L)
  expect_equal(upgraded$artifacts$dm$kind, "table")
  expect_null(upgraded$tables)
})


test_that("the dispatcher is the identity on a document already at the current version", {
  current <- list(
    schema_version = 2L,
    artifacts = list(dm = list(kind = "table", current_version = "abc"))
  )

  expect_identical(.datom_manifest_upgrade(current, 2L), current)
})


test_that("the dispatcher runs zero steps on a current-version document", {
  # Not just "the result looks unchanged": R's seq() counts DOWN when from > to,
  # so an unguarded chain would run every step backwards here and a v1 step
  # applied to a v2 document is not always visible in the output.
  ran <- 0L
  local_mocked_bindings(
    .datom_manifest_upgrade_steps = list(
      "1" = function(m) {
        ran <<- ran + 1L
        m
      }
    )
  )

  .datom_manifest_upgrade(list(schema_version = 2L, artifacts = list()), 2L)
  expect_equal(ran, 0L)

  .datom_manifest_upgrade(list(tables = list()), 1L)
  expect_equal(ran, 1L)
})


test_that("applying the dispatcher twice equals applying it once", {
  v1 <- list(
    project_name = "p",
    tables = list(dm = list(current_version = "abc", size_bytes = 10))
  )

  once <- .datom_manifest_upgrade(v1, 1L)
  twice <- .datom_manifest_upgrade(once, once$schema_version)

  expect_identical(twice, once)
})


test_that("the dispatcher leaves a document that did not parse to a list alone", {
  # `null` on disk must not come back as an object: stamping a non-list would
  # invent a document where the file had none.
  expect_null(.datom_manifest_upgrade(NULL, 1L))
})


test_that("the dispatcher refuses a version with no step to reach the next one", {
  # Reachable only by a coding error -- a step added to the supported version
  # without a function to go with it -- and the alternative is writing a file
  # that declares a shape it does not have.
  local_mocked_bindings(
    .datom_manifest_upgrade_steps = list()
  )

  expect_error(
    .datom_manifest_upgrade(list(tables = list()), 1L),
    class = "datom_schema_no_upgrade_step"
  )
})


test_that("the check supplies the version the dispatcher converts from", {
  # The two halves in the order they must run: a document too new for this
  # build never reaches the chain, because there is no step for a version this
  # build does not know.
  too_new <- list(schema_version = 99L, artifacts = list())
  expect_error(
    .datom_check_schema_version(too_new, "m.json"),
    class = "datom_schema_unsupported"
  )

  old <- list(tables = list(dm = list()))
  declared <- .datom_check_schema_version(old, "m.json")
  expect_equal(declared, 1L)
  expect_equal(.datom_manifest_upgrade(old, declared)$schema_version, 2L)
})
