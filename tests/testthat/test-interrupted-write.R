# A table write that breaks partway, then is re-run (#155; design section 3).
#
# Each test builds a real project (folder git remote, local store), writes v1,
# breaks a write of v2 at one step, re-runs the same write, and asks a reader
# with no clone what it sees. Nothing in the datom stack is mocked except the
# one binding that raises the break (`local_break_at()`, helper-interrupt.R).
#
# Steps 1-5 of the break table: the data file upload, the clone files, the
# commit, the push, and the metadata upload (whole, and at two points inside
# it). The manifest upload, step 6, is finished by a later command, not by a
# re-run of the same write, and is tested with that command.

interrupt_v1 <- function() datom_example_data("dm")

interrupt_v2 <- function() {
  d <- datom_example_data("dm")
  d$USUBJID[1] <- paste0(d$USUBJID[1], "-v2")
  d
}

# Which version a reader gets, told apart by one cell.
interrupt_reads_as <- function(fx, name = "dm") {
  r <- suppressMessages(datom_read(fx$reader, name))
  first <- as.character(as.data.frame(r)$USUBJID[1])
  if (identical(first, interrupt_v1()$USUBJID[1])) return("v1")
  if (identical(first, interrupt_v2()$USUBJID[1])) return("v2")
  "other"
}

interrupt_stored_manifest_version <- function(fx, name = "dm") {
  manifest <- .datom_storage_read_json(fx$conn, ".metadata/manifest.json")
  manifest$artifacts[[name]]$current_version
}

# The hash of the bytes stored at a version's data address.
interrupt_stored_file_sha <- function(fx, data_sha, name = "dm") {
  key <- .datom_artifact_payload_key(name, data_sha, "table")
  digest::digest(file = .datom_local_path(fx$conn, key), algo = "sha256")
}

# Break a write of `data` at `step`. The break must be the error the write
# stopped on, or the test would silently become a plain write test.
interrupt_break_write <- function(fx, step, data, name = "dm") {
  local_break_at(step, name)
  expect_error(
    suppressMessages(datom_write(fx$conn, data = data, name = name)),
    class = "datom_test_break"
  )
}

# Break the write of v2 at `step`, re-run it, and check what a reader sees
# (P1) and the hash the version records (P3).
expect_rerun_finishes <- function(step) {
  fx <- local_interrupt_project()
  suppressMessages(datom_write(fx$conn, data = interrupt_v1(), name = "dm"))

  interrupt_break_write(fx, step, interrupt_v2())

  # Nothing readers follow moved: they still get v1.
  expect_identical(interrupt_reads_as(fx), "v1")

  rerun <- suppressMessages(datom_write(fx$conn, data = interrupt_v2(), name = "dm"))
  expect_identical(rerun$action, "full")

  # P1: the new version reads, and the stored manifest names it.
  expect_identical(interrupt_reads_as(fx), "v2")
  expect_identical(interrupt_stored_manifest_version(fx), rerun$metadata_sha)

  # P3: the hash the version records is the hash of the stored bytes.
  stored_meta <- .datom_storage_read_json(fx$conn, .datom_artifact_meta_key("dm", "metadata"))
  expect_identical(stored_meta$parquet_sha, interrupt_stored_file_sha(fx, rerun$data_sha))
}


# --- P1 and P3, steps 1-5 -----------------------------------------------------

test_that("a write broken at its data file upload finishes on a re-run", {
  expect_rerun_finishes("upload")
})

test_that("a write broken after its clone files, before its manifest row, finishes on a re-run", {
  expect_rerun_finishes("clone_files")
})

test_that("a write broken at its commit finishes on a re-run", {
  expect_rerun_finishes("commit")
})

test_that("a write broken at its push finishes on a re-run", {
  # The case #155 was filed for: before the data file went first, the pushed
  # version had no data file, the re-run skipped the upload because the clone's
  # history already named its hash, and every read of it failed.
  expect_rerun_finishes("push")
})

test_that("a write broken at its metadata upload finishes on a re-run", {
  expect_rerun_finishes("metadata")
})

test_that("a write broken at the stored history upload finishes on a re-run", {
  # Snapshot stored, history and metadata.json not. With metadata.json uploaded
  # first (the old order), it would already name v2 here, the re-run would
  # report "no changes", and the stored history and manifest would stay behind.
  expect_rerun_finishes("history")
})

test_that("a write broken at the stored metadata.json upload finishes on a re-run", {
  expect_rerun_finishes("metadata_json")
})


# --- the data file goes first -------------------------------------------------

test_that("a write broken at its data file upload has changed nothing in the clone or git", {
  # The upload is the first thing a write changes. Placed any later, a break
  # there would leave the clone's files (and their history entry naming a hash
  # with no stored file) behind for the re-run to trust.
  fx <- local_interrupt_project()
  suppressMessages(datom_write(fx$conn, data = interrupt_v1(), name = "dm"))
  repo <- git2r::repository(fx$repo)
  head_before <- git2r::sha(git2r::last_commit(repo))
  meta_before <- readLines(file.path(fx$repo, "dm", "metadata.json"))
  history_before <- readLines(file.path(fx$repo, "dm", "version_history.json"))

  interrupt_break_write(fx, "upload", interrupt_v2())

  expect_identical(readLines(file.path(fx$repo, "dm", "metadata.json")), meta_before)
  expect_identical(
    readLines(file.path(fx$repo, "dm", "version_history.json")),
    history_before
  )
  expect_identical(git2r::sha(git2r::last_commit(repo)), head_before)
  status <- git2r::status(repo)
  expect_length(c(unlist(status$staged), unlist(status$unstaged)), 0L)
})

test_that("a version whose content is already stored, in other bytes, records the stored file's hash and reads", {
  # P3, the "exists" branch: an earlier run that broke, or a colleague on
  # another arrow version, stored this content first in different bytes. The
  # write keeps that file (P2) and records ITS hash; recording the fresh bytes'
  # hash would make every read of the version fail its integrity check.
  fx <- local_interrupt_project()
  suppressMessages(datom_write(fx$conn, data = interrupt_v1(), name = "dm"))

  v2 <- interrupt_v2()
  data_sha <- .datom_canonical_hash(v2)$data_sha
  planted <- .datom_local_path(fx$conn, .datom_artifact_payload_key("dm", data_sha, "table"))
  fs::dir_create(fs::path_dir(planted))
  arrow::write_parquet(v2, planted, compression = "uncompressed")
  planted_sha <- digest::digest(file = planted, algo = "sha256")

  fresh <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(v2, fresh)
  # Without this the test could not fail: the two hashes would agree.
  expect_false(identical(planted_sha, digest::digest(file = fresh, algo = "sha256")))

  result <- suppressMessages(datom_write(fx$conn, data = v2, name = "dm"))

  expect_identical(result$action, "full")
  expect_identical(digest::digest(file = planted, algo = "sha256"), planted_sha)
  expect_identical(
    jsonlite::read_json(file.path(fx$repo, "dm", "metadata.json"))$parquet_sha,
    planted_sha
  )
  expect_identical(interrupt_reads_as(fx), "v2")
})


# --- step 5's order -----------------------------------------------------------

test_that("the metadata upload stores the snapshot, then the history, then metadata.json, and the manifest after all three", {
  # metadata.json is what change detection reads, so it goes last within the
  # step; the manifest is the last thing a write publishes.
  fx <- local_interrupt_project()
  suppressMessages(datom_write(fx$conn, data = interrupt_v1(), name = "dm"))

  real_write_json <- .datom_storage_write_json
  keys <- character()
  local_mocked_bindings(.datom_storage_write_json = function(conn, key, data) {
    keys <<- c(keys, key)
    real_write_json(conn, key, data)
  })
  result <- suppressMessages(datom_write(fx$conn, data = interrupt_v2(), name = "dm"))

  expect_identical(keys, c(
    .datom_artifact_snapshot_key("dm", result$metadata_sha),
    .datom_artifact_meta_key("dm", "version_history"),
    .datom_artifact_meta_key("dm", "metadata"),
    ".metadata/manifest.json"
  ))
})
