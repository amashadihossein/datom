# Reconstructing the artifact index from storage.
#
# What is being protected: a manifest whose artifact list has moved somewhere this
# build cannot see looks EXACTLY like a repo with nothing in it. Every discovery
# command reports an empty project and none of them errors. So the rebuild is not
# a convenience -- it is the difference between a wrong answer given confidently
# and a right answer given with a caveat.
#
# The two triggers are the two conditions that make a WRITER refuse. That pairing
# is asserted here rather than left to two files, because "same evidence, opposite
# responses" is the part a later change is most likely to tidy away.


# --- fixture ------------------------------------------------------------------

#' Real developer project: git repo + bare remote + local store.
#'
#' Same shape and same reason as `local_identity_project()` in
#' `test-identity-contract.R` -- nothing in the datom stack is mocked, because the
#' claim under test is about the composition. Duplicated because testthat does not
#' share definitions between test files.
local_rebuild_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  repo_dir <- fs::path(root, "repo")
  store_dir <- fs::path(root, "store")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, store_dir, bare_dir))

  git2r::init(bare_dir, bare = TRUE)
  repo <- git2r::init(repo_dir)
  git2r::config(repo, user.name = "Rebuild Test", user.email = "rb@test.com")
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
  conn$project_name <- "rebuild-project"

  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir)
}

rb_data <- function(n = 3L) {
  data.frame(id = seq_len(n), val = letters[seq_len(n)],
             stringsAsFactors = FALSE)
}

# An imported write, so `original_format` is on the document. That field is the
# reason this task persists anything at all: it used to live on the manifest row
# and nowhere else, which made it the one field a reconstruction had to drop.
rb_write_imported <- function(fx, name = "dm", data = rb_data(), format = "csv") {
  suppressMessages(datom_write(
    fx$conn, data = data, name = name,
    .table_type = "imported",
    .original_file_sha = strrep("f", 64L),
    .original_format = format
  ))
}

rb_stored_manifest <- function(fx) {
  .datom_storage_read_json(fx$conn, ".metadata/manifest.json")
}


# --- enumerating artifacts from a listing ---------------------------------------

test_that(".datom_storage_artifact_names strips the namespace root before matching", {
  # The backends return FULL keys, including `{prefix}/datom/`, while every other
  # part of datom speaks in keys relative to the namespace root. Mixing the two
  # shapes double-prefixes silently and does not error, so this asserts the strip
  # rather than trusting it.
  local_mocked_bindings(
    .datom_storage_list_objects = function(conn, prefix) c(
      "proj/datom/dm/.metadata/metadata.json",
      "proj/datom/dm/.metadata/version_history.json",
      "proj/datom/dm/abc123.parquet",
      "proj/datom/ae/.metadata/metadata.json",
      "proj/datom/.metadata/manifest.json",
      "proj/datom/.metadata/dispatch.json"
    )
  )

  expect_equal(
    .datom_storage_artifact_names(mock_datom_conn(list())),
    c("ae", "dm")
  )
})

test_that(".datom_storage_artifact_names returns nothing for an empty namespace", {
  local_mocked_bindings(
    .datom_storage_list_objects = function(conn, prefix) character()
  )

  expect_equal(
    .datom_storage_artifact_names(mock_datom_conn(list())),
    character()
  )
})


# --- which recorded version describes the current state ------------------------

test_that(".datom_recorded_current_version takes the newest entry in the ordinary case", {
  meta <- list(data_sha = "aa", created_at = "t2")
  history <- list(
    list(version = "v2", data_sha = "aa", timestamp = "t2"),
    list(version = "v1", data_sha = "bb", timestamp = "t1")
  )

  expect_equal(.datom_recorded_current_version(meta, history), "v2")
})

test_that(".datom_recorded_current_version follows a revert to older content", {
  # A write that reverts to content already in the history appends NO entry, so
  # the current state is an older row. Taking the newest entry would publish a
  # version that describes different content -- and every readable-looking field
  # would still line up, which is why this case gets its own test.
  meta <- list(data_sha = "bb", created_at = "t3")
  history <- list(
    list(version = "v2", data_sha = "aa", timestamp = "t2"),
    list(version = "v1", data_sha = "bb", timestamp = "t1")
  )

  expect_equal(.datom_recorded_current_version(meta, history), "v1")
})

test_that(".datom_recorded_current_version separates two versions of the same content", {
  # A metadata-only change mints a new version against an unchanged `data_sha`,
  # so content alone cannot separate them. The history entry copies the
  # document's `created_at` verbatim, which can.
  meta <- list(data_sha = "aa", created_at = "t1")
  history <- list(
    list(version = "v2", data_sha = "aa", timestamp = "t2"),
    list(version = "v1", data_sha = "aa", timestamp = "t1")
  )

  expect_equal(.datom_recorded_current_version(meta, history), "v1")
})

test_that(".datom_recorded_current_version invents nothing when the history is unusable", {
  # A row carrying no version is better than a row carrying a manufactured one:
  # an index pointing at a version that does not exist is worse than an index
  # admitting it does not know.
  expect_null(.datom_recorded_current_version(list(data_sha = "aa"), NULL))
  expect_null(.datom_recorded_current_version(list(data_sha = "aa"), list()))
  expect_null(.datom_recorded_current_version(
    list(data_sha = "aa"), list(list(data_sha = "aa"))
  ))
})


# --- AC37: the triggers --------------------------------------------------------

test_that("an absent artifact key is rebuilt, with one warning naming the upgrade", {
  # AC37(a). The document is well-formed and current-numbered; it simply has no
  # artifact list where this build looks. Without the rebuild this reads as an
  # empty repo and nothing errors.
  mock_rebuildable_store(
    manifest = list(schema_version = 2L, project_name = "p",
                    updated_at = "2026-01-02T00:00:00Z"),
    artifacts = list(dm = mock_stored_artifact(), ae = mock_stored_artifact())
  )

  conn <- mock_datom_conn(list())
  warnings <- capture_warnings(result <- datom_list(conn))

  expect_length(warnings, 1L)
  expect_match(warnings, "install_github")
  expect_equal(sort(result$name), c("ae", "dm"))
})

test_that("a too-new manifest rebuilds for a reader and refuses for a writer", {
  # AC37(b), both halves against the SAME document, because the pairing is the
  # claim: reads limp, writes stop. A reader that carries on gives one person one
  # session's answers; a writer that carries on leaves the repo wrong for
  # everybody.
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")
    jsonlite::write_json(
      list(schema_version = 99L, artifacts = list()),
      ".datom/manifest.json", auto_unbox = TRUE
    )

    mock_rebuildable_store(
      manifest = list(schema_version = 99L, artifacts = list()),
      artifacts = list(dm = mock_stored_artifact())
    )

    read <- NULL
    expect_warning(
      read <- .datom_read_manifest(conn, "clone"),
      class = "datom_manifest_rebuilt"
    )
    expect_length(read$manifest$artifacts, 1L)

    expect_error(
      .datom_read_manifest(conn, "clone", operation = "write"),
      class = "datom_schema_unsupported"
    )
  })
})

test_that("a genuinely empty repo triggers no rebuild and lists no storage", {
  # AC37(c), asserted on the absence of the listing CALL rather than on the
  # result, because an empty result is what a rebuild of an empty store returns
  # too. An empty artifact list is what a brand-new repo looks like, so rebuilding
  # on empty would put one storage listing on every read of every healthy repo and
  # would hide a truncated document behind a plausible answer.
  listed <- FALSE
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      list(schema_version = 2L, project_name = "p",
           artifacts = structure(list(), names = character()),
           summary = list())
    },
    .datom_storage_list_objects = function(conn, prefix) {
      listed <<- TRUE
      character()
    }
  )

  read <- .datom_read_manifest(mock_datom_conn(list()), "storage")

  expect_true(read$ok)
  expect_false(listed)
  expect_length(read$manifest$artifacts, 0L)
})

test_that("an EMPTY v1 manifest does rebuild, and that is not a contradiction", {
  # The companion to the test above, and the distinction is easy to get backwards.
  # A current-shape empty manifest carries its artifact list present-and-empty, so
  # nothing fires. A v1 manifest with no `tables` key at all comes out of the
  # conversion with NO artifact key -- the conversion preserves that difference on
  # purpose -- so it is the absent-key trigger. Both are correct under the same
  # rule; only the input differs.
  mock_rebuildable_store(
    manifest = list(project_name = "p"),
    artifacts = list(dm = mock_stored_artifact())
  )

  read <- NULL
  expect_warning(
    read <- .datom_read_manifest(mock_datom_conn(list()), "storage"),
    class = "datom_manifest_rebuilt"
  )
  expect_length(read$manifest$artifacts, 1L)
})

test_that("a corrupt manifest still fails visibly instead of being rebuilt", {
  # AC37(d). Two kinds of corrupt, and neither may be quietly reconstructed: a
  # value that is not a schema version at all, and a file that will not parse. A
  # rebuild here would turn a damaged repo into a plausible-looking one.
  listed <- FALSE
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      list(schema_version = "not-a-number", artifacts = list())
    },
    .datom_storage_list_objects = function(conn, prefix) {
      listed <<- TRUE
      character()
    }
  )

  expect_error(
    .datom_read_manifest(mock_datom_conn(list()), "storage"),
    class = "datom_schema_invalid"
  )
  expect_false(listed)

  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$path <- getwd()
    fs::dir_create(".datom")
    writeLines('{"artifacts": {', ".datom/manifest.json")

    read <- .datom_read_manifest(conn, "clone")
    expect_false(read$ok)
    expect_false(is.null(read$error))
  })
})

test_that("a rebuilt current_version is the recorded one, never a recomputed hash", {
  # AC37(e). Recomputing would reach for the identity code in exactly the
  # scenario a rebuild is for -- a repo touched by a build whose field
  # classification differs from this one's -- and publish a version matching
  # nothing in the recorded history. The fixture's recorded version is
  # deliberately not the hash of its own document, so a recomputing
  # implementation cannot pass by coincidence.
  recorded <- strrep("b", 64L)
  artifact <- mock_stored_artifact(version = recorded)

  mock_rebuildable_store(
    manifest = list(schema_version = 2L),
    artifacts = list(dm = artifact)
  )

  expect_false(
    identical(.datom_compute_metadata_sha(artifact$metadata), recorded)
  )

  read <- NULL
  expect_warning(
    read <- .datom_read_manifest(mock_datom_conn(list()), "storage"),
    class = "datom_manifest_rebuilt"
  )
  expect_equal(read$manifest$artifacts$dm$current_version, recorded)
})


# --- AC37(f): a rebuilt index equals the recorded one on a healthy repo ---------

test_that("a rebuilt index matches the recorded one field for field", {
  # AC37(f), on a real git repo and a real local store with nothing mocked. This
  # is the test that keeps a rebuilt repo answering the same questions the same
  # way -- a row that dropped a field, or typed one differently, changes what
  # every counter and every listing reports.
  fx <- local_rebuild_project()
  rb_write_imported(fx, "dm", rb_data(3L))
  rb_write_imported(fx, "ae", rb_data(5L), format = "parquet")

  recorded <- rb_stored_manifest(fx)
  rebuilt <- .datom_rebuild_manifest(fx$conn, recorded)

  expect_setequal(names(rebuilt), names(recorded))
  expect_equal(rebuilt$project_name, recorded$project_name)
  expect_equal(rebuilt$schema_version, recorded$schema_version)
  expect_setequal(names(rebuilt$artifacts), names(recorded$artifacts))
  expect_equal(rebuilt$summary, recorded$summary)

  for (nm in names(recorded$artifacts)) {
    got <- rebuilt$artifacts[[nm]]
    want <- recorded$artifacts[[nm]]

    expect_setequal(names(got), names(want))

    # `last_updated` is the one field with no recorded source: the writer stamps
    # the wall clock at the moment it rewrites the row, and that moment is in no
    # document. The rebuild uses the version's own `created_at` instead, which is
    # the closest true statement available. Asserted as present and plausible
    # rather than equal, and called out here so the exception is a decision rather
    # than a gap somebody later "fixes" by inventing a timestamp.
    expect_match(got$last_updated, "^\\d{4}-\\d{2}-\\d{2}T")

    for (field in setdiff(names(want), "last_updated")) {
      expect_equal(got[[field]], want[[field]], info = paste(nm, field))
    }
  }
})

test_that("original_format survives into metadata, which is what makes it rebuildable", {
  # Before this, the field was written onto the manifest row and nowhere else --
  # so it was the single field a reconstruction could not recover. It is
  # classified as NOT identity: its sibling `original_file_sha` is identity, and
  # copying that choice here would re-mint a version for every imported table in
  # every repo, on content that did not move.
  fx <- local_rebuild_project()
  rb_write_imported(fx, "dm", rb_data(3L), format = "sas7bdat")

  meta <- jsonlite::read_json(fs::path(fx$repo_dir, "dm", "metadata.json"))
  expect_equal(meta$original_format, "sas7bdat")

  stripped <- meta
  stripped$original_format <- NULL
  expect_identical(
    .datom_compute_metadata_sha(meta),
    .datom_compute_metadata_sha(stripped)
  )

  rebuilt <- .datom_rebuild_manifest(fx$conn, rb_stored_manifest(fx))
  expect_equal(rebuilt$artifacts$dm$original_format, "sas7bdat")
})


# --- when the rebuild itself cannot be done ------------------------------------

test_that("a per-artifact document this build cannot read stops the rebuild", {
  # R22.11's qualification, and the reason survivability is narrower than it
  # looks: per-artifact metadata is stamped and NOT reconstructible, so if the
  # release that moved the manifest ahead also moved metadata, there is nothing
  # here to salvage. The refusal has to escape the rebuild rather than become a
  # missing row.
  mock_rebuildable_store(
    manifest = list(schema_version = 99L),
    artifacts = list(dm = mock_stored_artifact(
      extra_meta = list(schema_version = 99L)
    ))
  )

  err <- expect_error(
    .datom_read_manifest(mock_datom_conn(list()), "storage"),
    class = "datom_schema_unsupported"
  )
  expect_match(conditionMessage(err), "dm/\\.metadata/metadata\\.json")
})

test_that("a too-new manifest whose rebuild fails still refuses as a schema problem", {
  # AC32 held across the behaviour change. When the rebuild cannot be done, the
  # original refusal is what surfaces -- never an unreadable-manifest message.
  # Disguising it is the one thing the schema contract forbids at every reader,
  # because "could not read manifest" sends the user to check their credentials
  # while the actual instruction is to upgrade.
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) list(schema_version = 99L),
    .datom_storage_list_objects = function(conn, prefix) stop("bucket unreachable")
  )

  err <- expect_error(
    datom_list(mock_datom_conn(list())),
    class = "datom_schema_unsupported"
  )
  expect_match(conditionMessage(err), "install_github")
  expect_false(grepl("Could not read manifest", conditionMessage(err)))
})

test_that("an unreachable-shape manifest whose rebuild fails comes back as an IO failure", {
  # The other side of the same fork, and it must NOT be a schema refusal: this
  # document was perfectly readable and declared a format this build knows. The
  # only thing that went wrong is storage, so each caller keeps its own policy for
  # that -- datom_list() aborts with the cause, datom_status() reports the
  # manifest unavailable and carries on.
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) list(schema_version = 2L),
    .datom_storage_list_objects = function(conn, prefix) stop("bucket unreachable")
  )

  read <- .datom_read_manifest(mock_datom_conn(list()), "storage")
  expect_false(read$ok)
  expect_match(conditionMessage(read$error), "bucket unreachable")

  status <- datom_status(mock_datom_conn(list()))
  expect_false(status$tables$available)
})

test_that("a rebuild writes nothing, on either copy", {
  # In memory, for this session, always. A reader holds storage credentials and no
  # clone, so persisting is not available to the population this exists for; and a
  # read that quietly rewrote a repo's index would be a larger surprise than the
  # one it is fixing. The recorded copy is repaired by the next ordinary write.
  fx <- local_rebuild_project()
  rb_write_imported(fx, "dm", rb_data(3L))

  clone_path <- fs::path(fx$repo_dir, ".datom", "manifest.json")
  broken <- jsonlite::read_json(clone_path)
  names(broken)[names(broken) == "artifacts"] <- "artefacts"
  jsonlite::write_json(broken, clone_path, auto_unbox = TRUE, pretty = TRUE)

  before_clone <- readLines(clone_path, warn = FALSE)
  before_stored <- rb_stored_manifest(fx)

  read <- NULL
  expect_warning(
    read <- .datom_read_manifest(fx$conn, "clone"),
    class = "datom_manifest_rebuilt"
  )

  expect_length(read$manifest$artifacts, 1L)
  expect_identical(readLines(clone_path, warn = FALSE), before_clone)
  expect_identical(rb_stored_manifest(fx), before_stored)
})
