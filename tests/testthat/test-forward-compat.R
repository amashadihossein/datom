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

fc_clone_history <- function(fx, name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "version_history.json"))
}

fc_stored_history <- function(fx, name) {
  .datom_storage_read_json(
    fx$conn, .datom_artifact_meta_key(name, "version_history")
  )
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

# HOLDING THE DOOR OPEN, and why four round trips below need it.
#
# The write entry now REFUSES a document carrying a field it cannot place, on
# exactly the three documents the carry-forward rule covers -- so the two levels
# that need code to survive a rewrite can no longer be reached through
# `datom_write()` at all. That is the intended interaction, not a conflict: a
# build that meets an unfamiliar field should stop rather than rewrite the
# document, and carrying the field is what makes the write harmless if it ever
# does proceed.
#
# The merge is still worth pinning, for two reasons. The version-history entry
# below is genuinely live -- the refusal's scope does not include that document.
# And the day a release widens what the door accepts, the merge behind it has to
# already work; a merge that quietly broke while unreachable would ship as a
# silent field deletion on the first write that got through.
#
# So these four suppress the refusal and assert the merge. They do NOT suppress
# the schema check or the shape check, which are separate steps.
fc_hold_door_open <- function() {
  local_mocked_bindings(
    .datom_check_document_vocabulary = function(doc, known, source) {
      invisible(NULL)
    },
    .env = parent.frame()
  )
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

  # The converse, for the same reason the metadata lists have one: a name on this
  # list that nothing writes is invisible to the carry-forward rule, so a row
  # arriving from a newer datom with that field on it would lose it. No exception
  # is needed here today -- the list is exactly what a row carries when both of
  # its optional fields are supplied, which is what this fixture does.
  expect_identical(setdiff(.datom_manifest_entry_known_fields, names(row)),
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
  fc_hold_door_open()
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
  fc_hold_door_open()
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
  fc_hold_door_open()
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
  fc_hold_door_open()
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


# === round trip 4: an entry in the version history ============================

test_that("an unplaceable field on a version-history entry survives a later write", {
  # The fourth surface, and safe for the same reason as the manifest's top level:
  # the history list is read and the new version is prepended, so an entry
  # already in it is never rebuilt. Pinned rather than argued, because the
  # property is invisible from the code that relies on it -- and two later tasks
  # add fields to these entries (a payload integrity hash, and the commit a
  # version was first published from), at which point a rebuild here would start
  # destroying them.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  fc_edit_clone_json(
    fs::path(fx$repo_dir, "dm", "version_history.json"),
    function(history) {
      history[[1]]$future_history_field <- "keep me"
      history
    }
  )
  first_version <- fc_clone_history(fx, "dm")[[1]]$version

  fc_write(fx, fc_data(5))

  history <- fc_clone_history(fx, "dm")
  expect_length(history, 2L)
  # Newest first, so the edited entry is now second -- and still carries it.
  expect_identical(history[[2]]$version, first_version)
  expect_identical(history[[2]]$future_history_field, "keep me")
  expect_identical(
    fc_stored_history(fx, "dm")[[2]]$future_history_field, "keep me"
  )
})


# =============================================================================
# The write entry: floor, schema, reachable shape, vocabulary
# =============================================================================
#
# What these defend. A build that meets a document it cannot fully account for
# must stop rather than rewrite it, because the rewrite recomputes the version
# identity from the fields this build knows -- reaching a different answer from
# the build that wrote it, on content that never moved. Reads limp, writes stop.
#
# The refusals must never fire on the UPGRADE direction, which is the direction
# that always has to work, so each section carries the corresponding
# proceeds-normally case beside the refusal.


# --- the vocabulary check -----------------------------------------------------

test_that("a top-level field the build cannot place refuses the write, naming it", {
  err <- expect_error(
    .datom_check_document_vocabulary(
      list(data_sha = "abc", future_field = 1),
      .datom_metadata_known_fields(),
      "dm/metadata.json"
    ),
    class = "datom_vocabulary_unknown"
  )
  # Naming the field is the whole recourse: without it the user cannot tell
  # which document changed under them, or by how much.
  expect_match(conditionMessage(err), "future_field")
  expect_match(conditionMessage(err), "dm/metadata.json")
})

test_that("a document whose every field classifies passes silently", {
  expect_silent(
    .datom_check_document_vocabulary(
      list(data_sha = "abc", hash_algo = "datom-cv1", nrow = 3L),
      .datom_metadata_known_fields(),
      "dm/metadata.json"
    )
  )
})

test_that("custom is opaque -- its contents are never treated as unrecognised", {
  # `custom` holds arbitrary user keys by design, so it is classified as one
  # field and never descended into. Without this the check would refuse any
  # document whose user metadata datom has not seen before, which is all of it.
  expect_silent(
    .datom_check_document_vocabulary(
      list(
        data_sha = "abc",
        custom = list(anything = 1, at_all = list(deeply = "nested"))
      ),
      .datom_metadata_known_fields(),
      "dm/metadata.json"
    )
  )
})

test_that("a retired field name still classifies", {
  # `tables` is what the manifest's artifact list was called before schema v2.
  # Documents carrying it exist unchanged in the world, so the name stays in the
  # vocabulary forever. A build that pruned it would meet an OLDER file, fail to
  # place a key it should know, and refuse -- blocking the upgrade direction.
  expect_true("tables" %in% .datom_manifest_known_fields)

  expect_silent(
    .datom_check_document_vocabulary(
      list(project_name = "p", tables = list()),
      .datom_manifest_known_fields,
      ".datom/manifest.json"
    )
  )
})

test_that("a document with no top-level names is left to fail on its own terms", {
  # Not this check's job to report a malformed document, and reporting it here
  # would send the user to upgrade datom over a truncated file.
  expect_silent(.datom_check_document_vocabulary(
    "not a document", .datom_manifest_known_fields, "m.json"
  ))
  expect_silent(.datom_check_document_vocabulary(
    list("unnamed"), .datom_manifest_known_fields, "m.json"
  ))
})

test_that("the manifest top-level vocabulary covers what a real write produces", {
  # The forcing function for that list. It is hand-written rather than derived
  # from the writer, because a vocabulary read off the writer's own output could
  # never disagree with it -- and then adding a field without classifying it
  # would pass here and refuse every subsequent write on a real repo.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  expect_setequal(
    setdiff(names(fc_clone_manifest(fx)), .datom_manifest_known_fields),
    character()
  )
})


# --- the writer floor ---------------------------------------------------------

test_that("a repo declaring a newer writer than this build refuses the write", {
  conn <- mock_datom_conn(list())
  conn$min_writer_version <- "999.0.0"

  err <- expect_error(
    .datom_check_writer_floor(conn),
    class = "datom_writer_floor"
  )
  expect_match(conditionMessage(err), "999.0.0")
  expect_match(conditionMessage(err), as.character(utils::packageVersion("datom")))
})

test_that("no declared floor means no floor -- nothing changes at all", {
  # Every repo written so far is in this state, so this is the clause that keeps
  # the mechanism from being a breaking change on the day it ships.
  conn <- mock_datom_conn(list())
  expect_null(conn$min_writer_version)
  expect_silent(.datom_check_writer_floor(conn))
})

test_that("a floor at or below this build passes", {
  conn <- mock_datom_conn(list())

  conn$min_writer_version <- as.character(utils::packageVersion("datom"))
  expect_silent(.datom_check_writer_floor(conn))

  conn$min_writer_version <- "0.0.1"
  expect_silent(.datom_check_writer_floor(conn))
})

test_that("an unusable floor value aborts rather than being ignored", {
  # Treating a malformed policy field as an absent one turns a typo into a
  # silently disabled policy -- the failure this whole section exists to avoid,
  # arriving through the mechanism meant to prevent it.
  conn <- mock_datom_conn(list())

  for (bad in list("not a version", "", NA_character_, list("0.1.0"))) {
    conn$min_writer_version <- bad
    expect_error(
      .datom_check_writer_floor(conn),
      class = "datom_writer_floor_invalid"
    )
  }
})

test_that("the floor stops a write before anything is hashed or written", {
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))
  fx$conn$min_writer_version <- "999.0.0"

  before <- .datom_compute_metadata_sha(fc_clone_metadata(fx, "dm"))
  expect_error(
    datom_write(fx$conn, data = fc_data(5), name = "dm"),
    class = "datom_writer_floor"
  )
  expect_identical(.datom_compute_metadata_sha(fc_clone_metadata(fx, "dm")),
                   before)
})


# --- the entry sequence, through the real write path --------------------------

test_that("an unrecognised field in a table's metadata refuses the write", {
  # The clause an implementation that checks only the manifest would pass while
  # leaving the document that matters most unchecked: per-artifact metadata is
  # never rebuildable, and it is where version identity lives.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  fc_edit_clone_json(
    fs::path(fx$repo_dir, "dm", "metadata.json"),
    function(doc) c(doc, list(future_field = "from a newer datom"))
  )

  err <- expect_error(
    datom_write(fx$conn, data = fc_data(5), name = "dm"),
    class = "datom_vocabulary_unknown"
  )
  expect_match(conditionMessage(err), "future_field")
  expect_match(conditionMessage(err), "dm/metadata.json")
})

test_that("the per-artifact check needs no storage read", {
  # It reads the clone's copy. That is not a compromise: git is written before
  # storage, so a newer build's document reaches this repo by a pull, which lands
  # in the clone. Making storage the source would add a network read to every
  # write and inspect the copy that cannot legitimately be ahead.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  fc_edit_clone_json(
    fs::path(fx$repo_dir, "dm", "metadata.json"),
    function(doc) c(doc, list(future_field = "x"))
  )

  reads <- 0L
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      reads <<- reads + 1L
      cli::cli_abort("storage must not be read at the door")
    }
  )

  expect_error(
    datom_write(fx$conn, data = fc_data(5), name = "dm"),
    class = "datom_vocabulary_unknown"
  )
  expect_identical(reads, 0L)
})

test_that("an unrecognised field on the manifest, top level or row, refuses the write", {
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  fc_edit_clone_json(
    fs::path(fx$repo_dir, ".datom", "manifest.json"),
    function(doc) c(doc, list(future_top_field = "x"))
  )
  err <- expect_error(
    datom_write(fx$conn, data = fc_data(5), name = "dm"),
    class = "datom_vocabulary_unknown"
  )
  expect_match(conditionMessage(err), "future_top_field")

  # An entry is its own document for this purpose. "Top-level keys only" means
  # do not descend into a value -- it does not mean skip the entries, which is
  # the reading that would leave every per-artifact row unchecked.
  fc_edit_clone_json(
    fs::path(fx$repo_dir, ".datom", "manifest.json"),
    function(doc) {
      doc$future_top_field <- NULL
      doc$artifacts$dm$future_row_field <- "x"
      doc
    }
  )
  err <- expect_error(
    datom_write(fx$conn, data = fc_data(5), name = "dm"),
    class = "datom_vocabulary_unknown"
  )
  expect_match(conditionMessage(err), "future_row_field")
  expect_match(conditionMessage(err), "artifact dm")
})

test_that("the mirror-everything route checks every artifact in the clone", {
  # The route with no artifact name in its arguments. Checking only the manifest
  # here would leave the per-artifact documents it is about to mirror unexamined,
  # and this is the route datom_validate(fix = TRUE) reaches.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3), name = "dm")
  fc_write(fx, fc_data(3), name = "ae")

  fc_edit_clone_json(
    fs::path(fx$repo_dir, "ae", "metadata.json"),
    function(doc) c(doc, list(future_field = "x"))
  )

  # No `.confirm = FALSE` needed: the entry refuses above the routing decision,
  # so the interactive confirmation this route would otherwise ask for is never
  # reached. That placement is the point -- a refusal must land before the write
  # starts, not partway through it.
  err <- expect_error(
    suppressMessages(datom_write(fx$conn)),
    class = "datom_vocabulary_unknown"
  )
  expect_match(conditionMessage(err), "ae/metadata.json")
})

test_that("a per-artifact document from a newer schema refuses the write", {
  # The gap the manifest-only door left open: the metadata-only route copies this
  # document from the clone straight to storage, so before the entry sequence
  # read it, a document pulled from a collaborator on a newer datom went through
  # unexamined.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  fc_edit_clone_json(
    fs::path(fx$repo_dir, "dm", "metadata.json"),
    function(doc) {
      doc$schema_version <- 99L
      doc
    }
  )

  err <- expect_error(
    datom_write(fx$conn, name = "dm"),
    class = "datom_schema_unsupported"
  )
  expect_match(conditionMessage(err), "cannot write")
})

test_that("the forward path never refuses -- a pre-rename repo writes normally", {
  # R23.4's first row, and the case a naive "refuse when the artifact list is
  # absent" rule would have deadlocked: a current build meeting a pre-rename repo
  # finds no `artifacts` key either, so refusing on that would mean no repo could
  # ever be moved forward.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  fc_edit_clone_json(
    fs::path(fx$repo_dir, ".datom", "manifest.json"),
    function(doc) {
      names(doc)[names(doc) == "artifacts"] <- "tables"
      doc$schema_version <- NULL
      doc$artifacts <- NULL
      doc$tables$dm$kind <- NULL
      doc
    }
  )

  # Assert the pre-state, so this cannot pass by the fixture edit silently not
  # having taken: without it, a manifest that stayed current-shaped would write
  # fine and prove nothing about the forward path.
  before <- fc_clone_manifest(fx)
  expect_true("tables" %in% names(before))
  expect_false("artifacts" %in% names(before))
  expect_null(before$schema_version)

  expect_no_error(fc_write(fx, fc_data(5)))

  manifest <- fc_clone_manifest(fx)
  expect_true("artifacts" %in% names(manifest))
  expect_false("tables" %in% names(manifest))
  expect_identical(manifest$schema_version, 2L)
})

test_that("a manifest with no reachable artifact list refuses the write", {
  # Same evidence the reader will one day rebuild from, opposite response. The
  # writer must not overwrite a document whose shape it cannot reach: the file
  # may belong to a lineage this build cannot produce, and replacing it with a
  # shape this build invented is worse than stopping.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))
  before <- fc_clone_manifest(fx)

  fc_edit_clone_json(
    fs::path(fx$repo_dir, ".datom", "manifest.json"),
    function(doc) {
      doc$artifacts <- NULL
      doc
    }
  )

  expect_error(
    datom_write(fx$conn, data = fc_data(5), name = "dm"),
    class = "datom_shape_unreachable"
  )
  # And it really did not write: the artifact list is still missing rather than
  # replaced by a one-entry list naming only this write.
  expect_false("artifacts" %in% names(fc_clone_manifest(fx)))
  expect_identical(fc_stored_manifest(fx)$artifacts$dm$current_version,
                   before$artifacts$dm$current_version)
})

test_that("a brand-new repo and a reader connection both pass the entry", {
  # Nothing has been written, so nothing can disagree; and a reader-role
  # connection has no clone to inspect and should keep failing on the clearer
  # developer-role message a few lines later.
  fx <- local_fc_project()
  expect_silent(.datom_check_write_entry(fx$conn, "dm"))
  expect_silent(.datom_check_write_entry(fx$conn, NULL))

  reader <- mock_datom_conn(list())
  expect_silent(.datom_check_write_entry(reader, "dm"))
})

test_that("the metadata-only route re-checks after its pull", {
  # The door read the clone; then this route pulls from the remote as its first
  # act, which can land a collaborator's newer document on top of what was just
  # checked. The check therefore runs again, against what the pull left on disk.
  fx <- local_fc_project()
  fc_write(fx, fc_data(3))

  local_mocked_bindings(
    .datom_git_pull = function(path, pat = NULL) {
      fc_edit_clone_json(
        fs::path(path, "dm", "metadata.json"),
        function(doc) c(doc, list(arrived_in_the_pull = "x"))
      )
      invisible(TRUE)
    }
  )

  err <- expect_error(
    datom_write(fx$conn, name = "dm"),
    class = "datom_vocabulary_unknown"
  )
  expect_match(conditionMessage(err), "arrived_in_the_pull")
})
