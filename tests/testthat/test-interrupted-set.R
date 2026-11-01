# A set write that breaks partway, then is re-run (#155; design section 3).
#
# The set twin of test-interrupted-write.R: a real product project (folder git
# remote, local store), a set written once, a second write broken at one step,
# the same write re-run, and a reader with no clone asked what it sees. Nothing
# in the datom stack is mocked except the one binding that raises the break
# (`local_break_at()`, helper-interrupt.R), or, where a test needs a second
# spelling of one payload, the function that spells it.
#
# Steps 1-5 of the break table. The manifest upload, step 6, is finished by a
# later command, not by a re-run of the same write, and is tested with that
# command.

iset_project <- function(env = parent.frame()) {
  fx <- local_interrupt_project(mode = "product", set = "adam", env = env)
  suppressMessages(datom_write(fx$conn, data = datom_example_data("dm"), name = "dm"))
  version <- datom_history(fx$conn, "dm", short_hash = FALSE)$version[[1L]]
  fx$members <- list(datom_member(fx$conn, "dm", version, tags = list(type = "input")))
  fx
}

iset_write <- function(fx, description) {
  suppressMessages(datom_write_set(
    fx$conn, fx$members, tags = list(description = description)
  ))
}

# Which version a reader gets, told apart by the set's description.
iset_reads_as <- function(fx) {
  suppressMessages(datom_get_set(fx$reader, "adam"))$tags$description
}

iset_stored_payload <- function(fx, data_sha) {
  .datom_local_path(fx$conn, .datom_artifact_payload_key("adam", data_sha, "set"))
}

iset_clone_payload <- function(fx) file.path(fx$repo, "adam", "set.json")

sha_of <- function(path) digest::digest(file = path, algo = "sha256")

# Break the write of `description` at `step`. The break must be the error the
# write stopped on, or the test would silently become a plain write test.
iset_break_write <- function(fx, step, description) {
  local_break_at(step, "adam")
  expect_error(iset_write(fx, description), class = "datom_test_break")
}

# Write v1, break the write of v2 at `step`, re-run it, and check what a reader
# sees (P1), the hash the version records (P3), and that the clone and storage
# hold one spelling of the payload (R1.5).
expect_set_rerun_finishes <- function(step) {
  fx <- iset_project()
  iset_write(fx, "v1")

  iset_break_write(fx, step, "v2")

  # Nothing readers follow moved: they still get v1.
  expect_identical(iset_reads_as(fx), "v1")

  rerun <- iset_write(fx, "v2")
  expect_identical(rerun$action, "full")

  # P1: the new version reads, and the stored manifest names it.
  expect_identical(iset_reads_as(fx), "v2")
  manifest <- .datom_storage_read_json(fx$conn, ".metadata/manifest.json")
  expect_identical(manifest$artifacts$adam$current_version, rerun$metadata_sha)

  # P3: the recorded hash is the hash of the stored bytes; R1.5: so is the
  # clone's copy.
  stored_meta <- .datom_storage_read_json(fx$conn, .datom_artifact_meta_key("adam", "metadata"))
  stored <- iset_stored_payload(fx, rerun$data_sha)
  expect_identical(stored_meta$document_sha, sha_of(stored))
  expect_identical(sha_of(iset_clone_payload(fx)), sha_of(stored))
}


# --- P1 and P3, steps 1-5 -----------------------------------------------------

test_that("a set write broken at its payload upload finishes on a re-run", {
  expect_set_rerun_finishes("upload")
})

test_that("a set write broken after its clone files, before its manifest row, finishes on a re-run", {
  expect_set_rerun_finishes("clone_files")
})

test_that("a set write broken at its commit finishes on a re-run", {
  expect_set_rerun_finishes("commit")
})

test_that("a set write broken at its push finishes on a re-run", {
  # Before the payload went first, this left a pushed version with no stored
  # payload, and the re-run reused the hash the clone's history named, so it
  # uploaded nothing and every read of the version failed.
  expect_set_rerun_finishes("push")
})

test_that("a set write broken at its metadata upload finishes on a re-run", {
  expect_set_rerun_finishes("metadata")
})

test_that("a set write broken at the stored history upload finishes on a re-run", {
  expect_set_rerun_finishes("history")
})

test_that("a set write broken at the stored metadata.json upload finishes on a re-run", {
  expect_set_rerun_finishes("metadata_json")
})


# --- the payload goes first ---------------------------------------------------

test_that("a set write broken at its payload upload has changed nothing in the clone or git", {
  fx <- iset_project()
  iset_write(fx, "v1")
  repo <- git2r::repository(fx$repo)
  head_before <- git2r::sha(git2r::last_commit(repo))
  files <- file.path(fx$repo, "adam", c("set.json", "metadata.json", "version_history.json"))
  before <- lapply(files, readLines)

  iset_break_write(fx, "upload", "v2")

  expect_identical(lapply(files, readLines), before)
  expect_identical(git2r::sha(git2r::last_commit(repo)), head_before)
  status <- git2r::status(repo)
  expect_length(c(unlist(status$staged), unlist(status$unstaged)), 0L)
})


# --- one spelling in git and storage (R1.5) -----------------------------------

# The payload written in another spelling of the same content: compact JSON
# instead of pretty-printed. Same members and tags, so the same data_sha, and
# different bytes, so a different document_sha.
iset_compact_spelling <- function(payload, path) {
  jsonlite::write_json(payload, path, auto_unbox = TRUE, pretty = FALSE)
  invisible(path)
}

test_that("a re-run that spells the payload differently keeps the stored spelling in set.json", {
  # The re-run finds this content in the clone's history (the broken run wrote
  # it there), so it records the stored payload's hash. Its own bytes differ, so
  # set.json must take the stored ones, or git would hold bytes that do not
  # match the recorded hash.
  fx <- iset_project()
  iset_write(fx, "v1")
  iset_break_write(fx, "push", "v2")

  local_mocked_bindings(.datom_write_set_payload = iset_compact_spelling)
  rerun <- iset_write(fx, "v2")

  stored <- iset_stored_payload(fx, rerun$data_sha)
  expect_identical(readBin(iset_clone_payload(fx), "raw", 1e6), readBin(stored, "raw", 1e6))
  # Without this the test could not fail: the two spellings would agree.
  compact <- withr::local_tempfile(fileext = ".json")
  iset_compact_spelling(jsonlite::read_json(stored), compact)
  expect_false(identical(sha_of(compact), sha_of(stored)))

  expect_identical(
    jsonlite::read_json(file.path(fx$repo, "adam", "metadata.json"))$document_sha,
    sha_of(stored)
  )
  expect_identical(iset_reads_as(fx), "v2")
})

test_that("a payload already stored in another spelling is kept, its hash recorded, and copied to set.json", {
  # An earlier run that broke after its upload, here one on a build that spelled
  # payloads compactly, stored this content first. The write keeps that file
  # (P2), records ITS hash (P3), and puts its bytes in set.json (R1.5).
  fx <- iset_project()
  iset_write(fx, "v1")

  planted <- NULL
  local({
    local_mocked_bindings(
      .datom_storage_upload_absent = function(conn, local_path, key, sha256 = NULL) {
        planted <<- .datom_local_path(conn, key)
        fs::dir_create(fs::path_dir(planted))
        iset_compact_spelling(jsonlite::read_json(local_path), planted)
        stop(datom_test_break("upload"))
      }
    )
    expect_error(iset_write(fx, "v2"), class = "datom_test_break")
  })
  planted_sha <- sha_of(planted)

  result <- iset_write(fx, "v2")

  expect_identical(result$action, "full")
  expect_identical(as.character(iset_stored_payload(fx, result$data_sha)), as.character(planted))
  expect_identical(sha_of(planted), planted_sha)
  expect_identical(
    jsonlite::read_json(file.path(fx$repo, "adam", "metadata.json"))$document_sha,
    planted_sha
  )
  expect_identical(sha_of(iset_clone_payload(fx)), planted_sha)
  expect_identical(iset_reads_as(fx), "v2")
})
