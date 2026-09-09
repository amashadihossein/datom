# Forward compatibility: a field this build cannot place survives a write.
#
# The failure being prevented: datom rebuilds its own documents from scratch on a
# write rather than editing them, so a top-level field written by a newer datom
# is not merely ignored -- it is deleted. The requirement covers three levels,
# and they need different amounts of code, which is why they get separate tests:
# a table's own metadata document and one row of the manifest are both rebuilt
# and so must carry unfamiliar fields explicitly, while the manifest's top level
# is read-modify-written and survives without any help. The third case is tested
# precisely because it holds by accident of structure -- a later refactor that
# rebuilt the document instead would break it silently.
#
# The unit tests below drive the helpers directly; the round trips go through the
# real write path on a real git repo and a real local store, because the claim is
# about the composition (build -> merge -> write file -> push -> mirror), not
# about any one function.


# --- fixture ------------------------------------------------------------------

#' Real developer project: git repo + bare remote + local store.
#'
#' Mirrors `local_identity_project()` in `test-identity-contract.R` -- same
#' shape, same reason (nothing in the datom stack is mocked), duplicated because
#' testthat does not share definitions between test files. `gov_root` stays NULL
#' so `.datom_check_ref_current()` skips.
local_fc_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)

  repo_dir <- fs::path(root, "repo")
  store_dir <- fs::path(root, "store")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, store_dir, bare_dir))

  git2r::init(bare_dir, bare = TRUE)
  repo <- git2r::init(repo_dir)
  git2r::config(repo, user.name = "FC Test", user.email = "fc@test.com")
  writeLines("init", fs::path(repo_dir, "README.md"))
  git2r::add(repo, "README.md")
  git2r::commit(repo, "Initial commit")
  git2r::remote_add(repo, name = "origin", url = as.character(bare_dir))
  git2r::push(repo, name = "origin", refspec = test_head_refspec(repo),
              set_upstream = TRUE)

  conn <- mock_datom_conn(list(), root = as.character(store_dir),
                          prefix = "proj")
  conn$backend <- "local"
  conn$role <- "developer"
  conn$path <- as.character(repo_dir)
  conn$project_name <- "fc-project"

  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir)
}

# The clone's copy of a document -- the one the write path rewrites.
fc_clone_metadata <- function(fx, name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "metadata.json"))
}

fc_clone_manifest <- function(fx) {
  jsonlite::read_json(fs::path(fx$repo_dir, ".datom", "manifest.json"))
}

# The storage mirror, read through the package's own key resolution so the test
# does not hard-code the `{prefix}/datom/` layout.
fc_stored_metadata <- function(fx, name) {
  .datom_storage_read_json(fx$conn, .datom_artifact_meta_key(name, "metadata"))
}

fc_stored_manifest <- function(fx) {
  .datom_storage_read_json(fx$conn, ".metadata/manifest.json")
}

# Edit a JSON document in place, in the clone or in storage.
fc_edit_clone_json <- function(path, edit) {
  doc <- jsonlite::read_json(path)
  jsonlite::write_json(edit(doc), path, auto_unbox = TRUE, pretty = TRUE)
}

fc_edit_stored_json <- function(conn, key, edit) {
  .datom_storage_write_json(conn, key, edit(.datom_storage_read_json(conn, key)))
}

fc_write <- function(fx, data, name = "dm", ...) {
  suppressMessages(datom_write(fx$conn, data = data, name = name, ...))
}

fc_data <- function(n) {
  data.frame(id = seq_len(n), grp = rep("a", n), stringsAsFactors = FALSE)
}


# === .datom_carry_unknown_fields() ============================================

test_that("a field the build cannot place is carried onto the rebuilt document", {
  rebuilt <- list(known_a = 1, known_b = 2)
  prior <- list(known_a = 99, future_field = "keep me")

  out <- .datom_carry_unknown_fields(rebuilt, prior, c("known_a", "known_b"))

  expect_identical(out$future_field, "keep me")
  # The rebuilt document is authoritative for everything it does speak to.
  expect_identical(out$known_a, 1)
})

test_that("several unplaceable fields are carried, and order is rebuilt-then-carried", {
  out <- .datom_carry_unknown_fields(
    list(known_a = 1),
    list(future_one = "a", known_a = 9, future_two = list(x = 1)),
    "known_a"
  )

  expect_identical(names(out), c("known_a", "future_one", "future_two"))
  expect_identical(out$future_two, list(x = 1))
})

test_that("a KNOWN field the write did not set is still dropped", {
  # The narrowness that makes this safe. Carrying every absent field forward
  # would preserve a stale claim (for instance, that a table came from a file it
  # no longer comes from) instead of letting it go.
  out <- .datom_carry_unknown_fields(
    list(known_a = 1),
    list(known_a = 9, known_b = "stale"),
    c("known_a", "known_b")
  )

  expect_false("known_b" %in% names(out))
})

test_that("the rebuilt document wins where both hold the same field", {
  out <- .datom_carry_unknown_fields(
    list(future_field = "new"),
    list(future_field = "old"),
    character()
  )

  expect_identical(out$future_field, "new")
})

test_that("nothing to carry leaves the document untouched", {
  rebuilt <- list(known_a = 1)

  expect_identical(.datom_carry_unknown_fields(rebuilt, NULL, "known_a"), rebuilt)
  expect_identical(
    .datom_carry_unknown_fields(rebuilt, "not a document", "known_a"), rebuilt
  )
  expect_identical(
    .datom_carry_unknown_fields(rebuilt, list(1, 2), "known_a"), rebuilt
  )
  expect_identical(
    .datom_carry_unknown_fields(rebuilt, list(known_a = 9), "known_a"), rebuilt
  )
})

test_that("a document that is not a list is returned as-is", {
  expect_identical(
    .datom_carry_unknown_fields("not a document", list(future_field = 1),
                                character()),
    "not a document"
  )
})


# === the two vocabularies =====================================================

test_that("the metadata vocabulary is exactly the two halves of the classification", {
  expect_setequal(
    .datom_metadata_known_fields(),
    c(.datom_metadata_identity_fields, .datom_metadata_excluded_fields)
  )
})

test_that("every field the metadata builder emits is in the metadata vocabulary", {
  # Forcing function. The inventory is derived from the builder rather than
  # listed here, so adding a field to the builder without classifying it fails
  # this test instead of quietly making that field look unplaceable -- at which
  # point every write would carry a stale copy of it forward.
  meta <- .datom_build_metadata(
    data.frame(a = 1L),
    data_sha = strrep("a", 64),
    custom = list(note = "x"),
    table_type = "imported",
    size_bytes = 10,
    parents = list(list(source = "p", table = "t", version = strrep("b", 64))),
    source_lineage = list(list(project = "p", table = "t",
                               version_sha = strrep("c", 64))),
    original_file_sha = strrep("d", 64),
    column_hashes = list(list(name = "a", sha = strrep("e", 64)))
  )

  expect_identical(setdiff(names(meta), .datom_metadata_known_fields()),
                   character())
})

test_that("every field written onto a manifest row is in the row vocabulary", {
  # The same forcing function one level down. Both optional row fields are
  # supplied, so the inventory is the widest a row can be.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3),
           .original_file_sha = strrep("f", 64), .original_format = "csv")

  row <- fc_clone_manifest(fx)$artifacts$dm

  expect_identical(setdiff(names(row), .datom_manifest_entry_known_fields),
                   character())
})


# === .datom_prior_metadata() ==================================================

test_that("the prior metadata document is read from the clone, or NULL when there is none", {
  fx <- local_fc_project()

  expect_null(.datom_prior_metadata(fx$conn, "dm"))

  fc_write(fx, fc_data(3))
  expect_identical(.datom_prior_metadata(fx$conn, "dm")$nrow, 3L)
})

test_that("an unparseable prior metadata document reads as absent, not as an error", {
  # Nothing to preserve either way, and the write fails on that file moments
  # later with the parser's own error -- this helper must not pre-empt it.
  fx <- local_fc_project()
  fs::dir_create(fs::path(fx$repo_dir, "dm"))
  writeLines("{not json", fs::path(fx$repo_dir, "dm", "metadata.json"))

  expect_null(.datom_prior_metadata(fx$conn, "dm"))
})


# === round trip 1: a table's own metadata document ============================

test_that("an unplaceable field in a table's metadata survives a write, in git and in storage", {
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  fc_edit_clone_json(
    fs::path(fx$repo_dir, "dm", "metadata.json"),
    function(doc) c(doc, list(future_field = list(note = "written by a newer datom")))
  )

  fc_write(fx, fc_data(5))

  expect_identical(fc_clone_metadata(fx, "dm")$future_field$note,
                   "written by a newer datom")
  expect_identical(fc_stored_metadata(fx, "dm")$future_field$note,
                   "written by a newer datom")
  # ... and the recomputed fields really were recomputed, so this is not a test
  # of the document having been left alone wholesale.
  expect_identical(fc_clone_metadata(fx, "dm")$nrow, 5L)
})

test_that("a KNOWN metadata field the write did not set is still dropped", {
  fx <- local_fc_project()
  fc_write(fx, fc_data(3), metadata = list(note = "first write"))
  expect_identical(fc_clone_metadata(fx, "dm")$custom$note, "first write")

  # Same table, written with no user metadata: `custom` is a field datom knows,
  # so it goes rather than lingering.
  fc_write(fx, fc_data(5))

  expect_false("custom" %in% names(fc_clone_metadata(fx, "dm")))
})

test_that("an unplaceable metadata field does not mint a version on its own", {
  # Identity ignores fields it cannot place, so planting one in both copies
  # leaves the write a no-op -- and the field is still there afterwards.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  add_field <- function(doc) c(doc, list(future_field = "x"))
  fc_edit_clone_json(fs::path(fx$repo_dir, "dm", "metadata.json"), add_field)
  fc_edit_stored_json(fx$conn, .datom_artifact_meta_key("dm", "metadata"),
                      add_field)

  result <- fc_write(fx, fc_data(3))

  expect_identical(result$action, "none")
  expect_identical(fc_clone_metadata(fx, "dm")$future_field, "x")
})


# === round trip 2: one row of the manifest ====================================

test_that("an unplaceable field on a manifest row survives a write, in git and in storage", {
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))
  first_version <- fc_clone_manifest(fx)$artifacts$dm$current_version

  fc_edit_clone_json(
    fs::path(fx$repo_dir, ".datom", "manifest.json"),
    function(doc) {
      doc$artifacts$dm$future_entry_field <- "keep me"
      doc
    }
  )

  fc_write(fx, fc_data(5))

  row <- fc_clone_manifest(fx)$artifacts$dm
  expect_identical(row$future_entry_field, "keep me")
  expect_identical(fc_stored_manifest(fx)$artifacts$dm$future_entry_field,
                   "keep me")
  # The row was genuinely rebuilt around it.
  expect_false(identical(row$current_version, first_version))
})

test_that("a KNOWN manifest row field the write did not set is still dropped", {
  # `original_format` is the case that decides this: a table imported from a CSV
  # and later written straight from a data frame has no format to declare, and
  # the row must stop claiming one rather than keep a stale answer.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3), .original_format = "csv")
  expect_identical(fc_clone_manifest(fx)$artifacts$dm$original_format, "csv")

  fc_write(fx, fc_data(5))

  expect_false("original_format" %in% names(fc_clone_manifest(fx)$artifacts$dm))
})


# === round trip 3: the manifest's top level ===================================

test_that("an unplaceable field beside the manifest's artifact list survives a write", {
  # This one holds because the manifest is read, edited and written back rather
  # than rebuilt. Tested anyway: a refactor to rebuilding it would take the
  # guarantee away without failing anything else.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  fc_edit_clone_json(
    fs::path(fx$repo_dir, ".datom", "manifest.json"),
    function(doc) c(doc, list(future_top_field = "keep me"))
  )

  fc_write(fx, fc_data(5))

  expect_identical(fc_clone_manifest(fx)$future_top_field, "keep me")
  expect_identical(fc_stored_manifest(fx)$future_top_field, "keep me")
})
