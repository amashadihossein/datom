# Validating a set: the payload address that depends on the kind, the member
# check that stops at one level, and what a repair may and may not touch.
#
# These run against a real git repo, a real bare remote and a real local store,
# because the claims are about the composition -- discover, read the clone's
# metadata, address the payload, list members, resolve each one -- rather than
# about any one function. Mocking the storage layer would let a wrong key pass.
#
# THREE OF THESE ARE THE TESTS A NAIVE IMPLEMENTATION PASSES EVERYTHING ELSE
# WHILE FAILING.
#
#   * A missing payload and an unresolvable member must be DISTINGUISHABLE. One
#     status covering both would still let a healthy set report `ok`, so the
#     healthy case proves nothing on its own.
#   * The inner set of a nested set must NOT be opened. Asserted by recording
#     which storage keys were read, because a validator that descended would
#     return the same statuses.
#   * A repair must leave a stored payload and its recorded hash alone. This is
#     only a real assertion because the repair CAN now upload a payload -- with
#     no upload path at all it would pass forever, whatever the code did.


# --- fixture ------------------------------------------------------------------

#' Real product project: git repo + bare remote + local store + product config.
#'
#' Mirrors `local_set_project()` in `test-write-set.R`; duplicated because
#' testthat does not share definitions between test files.
local_validate_set_project <- function(set_name = "product-a",
                                       env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)

  repo_dir <- fs::path(root, "repo")
  store_dir <- fs::path(root, "store")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, store_dir, bare_dir))

  git2r::init(bare_dir, bare = TRUE)
  repo <- git2r::init(repo_dir)
  git2r::config(repo, user.name = "Set Test", user.email = "set@test.com")
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
  conn$project_name <- "set-project"

  write_product_config(repo_dir, "set-project", set_name)

  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir,
       repo = repo, set_name = set_name)
}

vs_data <- function(n = 3L) {
  data.frame(id = seq_len(n), val = letters[seq_len(n)],
             stringsAsFactors = FALSE)
}

# Write a table and return the version just minted, which is what a member pins.
vs_table <- function(fx, name, n = 3L) {
  suppressMessages(datom_write(fx$conn, data = vs_data(n), name = name))
  datom_history(fx$conn, name, short_hash = FALSE)$version[[1L]]
}

# A set with one same-project table member, written and ready to validate.
vs_one_member_set <- function(fx) {
  version <- vs_table(fx, "dm")
  members <- list(datom_member(fx$conn, "dm", version,
                               tags = list(type = "input")))
  suppressMessages(
    datom_write_set(fx$conn, members, tags = list(description = "one member"))
  )
  invisible(version)
}

# Located through the package's own path resolution, so a storage-layout change
# breaks the code rather than quietly passing a test that looks elsewhere.
vs_stored <- function(fx, key) .datom_local_path(fx$conn, key)

vs_clone_meta <- function(fx, name = fx$set_name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "metadata.json"),
                      simplifyVector = TRUE)
}

vs_payload_key <- function(fx, name = fx$set_name) {
  .datom_artifact_payload_key(name, vs_clone_meta(fx, name)$data_sha, "set")
}

vs_validate <- function(fx, ...) suppressMessages(datom_validate(fx$conn, ...))

vs_row <- function(result, name) result$tables[result$tables$table == name, ]

vs_statuses <- function(result, name) {
  trimws(strsplit(vs_row(result, name)$status, ",", fixed = TRUE)[[1L]])
}

vs_edit_json <- function(path, f) {
  doc <- jsonlite::read_json(path)
  jsonlite::write_json(f(doc), path, auto_unbox = TRUE, pretty = TRUE)
  invisible(path)
}

# Put a hand-built member list at the set's stored payload address. The
# validator reads members from storage and does not re-hash the object, so the
# recorded `document_sha` is deliberately left alone here.
vs_replace_members <- function(fx, members) {
  path <- vs_stored(fx, vs_payload_key(fx))
  vs_edit_json(path, function(doc) {
    doc$members <- members
    doc
  })
}

vs_raw_member <- function(project = "set-project", name = "dm",
                          kind = "table", version = strrep("a", 64L)) {
  list(id = list(project = project, name = name, kind = kind,
                 version = version))
}

#' Record the storage keys a validation looked at, while letting the real
#' backend answer.
#'
#' The originals are captured before the mock replaces the binding, so calling
#' them inside does not recurse.
vs_watch_storage <- function(env = parent.frame()) {
  seen <- new.env(parent = emptyenv())
  seen$exists <- character()
  seen$read <- character()
  seen$download <- character()

  real_exists <- .datom_storage_exists
  real_read <- .datom_storage_read_json
  real_download <- .datom_storage_download

  testthat::local_mocked_bindings(
    .datom_storage_exists = function(conn, key) {
      seen$exists <- c(seen$exists, key)
      real_exists(conn, key)
    },
    .datom_storage_read_json = function(conn, key) {
      seen$read <- c(seen$read, key)
      real_read(conn, key)
    },
    .datom_storage_download = function(conn, key, local_path) {
      seen$download <- c(seen$download, key)
      real_download(conn, key, local_path)
    },
    .env = env
  )

  seen
}


# === the kind branch ==========================================================

test_that("a healthy set validates ok, and its row says it is a set", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  result <- vs_validate(fx)

  expect_true(result$valid)
  expect_equal(vs_row(result, fx$set_name)$status, "ok")
  expect_equal(vs_row(result, fx$set_name)$kind, "set")
  expect_equal(vs_row(result, "dm")$kind, "table")
})

test_that("a set's payload is looked for as JSON, never as a parquet object", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  seen <- vs_watch_storage()
  result <- vs_validate(fx)

  expect_true(vs_payload_key(fx) %in% seen$exists)
  # The hardcoded kind produced exactly this key, and reported every set's
  # payload missing.
  expect_false(any(grepl(paste0("^", fx$set_name, "/.*\\.parquet$"), seen$exists)))
  expect_true(result$valid)
})

test_that("an artifact declaring an unknown kind is reported, not fatal", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  vs_edit_json(
    fs::path(fx$repo_dir, fx$set_name, "metadata.json"),
    function(doc) {
      doc$kind <- "constellation"
      doc
    }
  )

  result <- vs_validate(fx)

  row <- vs_row(result, fx$set_name)
  expect_equal(row$kind, NA_character_)
  # Not `data_missing_s3`: nothing was checked, so nothing may be reported
  # missing.
  expect_equal(vs_statuses(result, fx$set_name), "kind_unsupported")
  expect_true(is.na(row$data_s3))
  expect_false(result$valid)
  # The table beside it is still reported, which is what "not fatal" buys.
  expect_equal(vs_row(result, "dm")$status, "ok")
})

test_that("the zero-row frame carries the same columns as a populated one", {
  fx <- local_validate_set_project()
  empty <- .datom_validate_tables(fx$conn)

  vs_one_member_set(fx)
  populated <- .datom_validate_tables(fx$conn)

  expect_equal(nrow(empty), 0L)
  expect_equal(names(empty), names(populated))
  expect_true("kind" %in% names(empty))
})


# === the member check =========================================================

test_that("a missing payload and an unresolvable member are distinguishable", {
  fx <- local_validate_set_project()
  version <- vs_one_member_set(fx)

  # (1) the payload object is gone
  payload <- vs_stored(fx, vs_payload_key(fx))
  fs::file_delete(payload)

  missing_payload <- vs_validate(fx)
  expect_equal(vs_statuses(missing_payload, fx$set_name), "data_missing_s3")
  expect_false(missing_payload$valid)

  # (2) the payload is there, but the version a member pins is not
  fs::file_copy(fs::path(fx$repo_dir, fx$set_name, "set.json"), payload)
  fs::file_delete(vs_stored(fx, .datom_artifact_snapshot_key("dm", version)))

  rotten_member <- vs_validate(fx)
  expect_equal(vs_statuses(rotten_member, fx$set_name), "members_unresolvable")
  expect_false(rotten_member$valid)
})

test_that("the unresolvable member is named, not just counted", {
  fx <- local_validate_set_project()
  version <- vs_one_member_set(fx)
  fs::file_delete(vs_stored(fx, .datom_artifact_snapshot_key("dm", version)))

  messages <- capture.output(datom_validate(fx$conn), type = "message")
  combined <- paste(messages, collapse = " ")

  expect_match(combined, "do not resolve")
  expect_match(combined, "dm@")
})

test_that("a malformed member record reports members_unresolvable", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  # No `version`: a pointer datom_write_set() cannot produce, so the payload was
  # hand-edited or written by something else.
  broken <- vs_raw_member()
  broken$id$version <- NULL
  vs_replace_members(fx, list(broken))

  result <- vs_validate(fx)

  expect_equal(vs_statuses(result, fx$set_name), "members_unresolvable")
})

test_that("a member list that is not a list of records is reported", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  # A JSON object where an array of records belongs.
  vs_replace_members(fx, list(dm = vs_raw_member()))

  result <- vs_validate(fx)

  expect_equal(vs_statuses(result, fx$set_name), "members_unresolvable")
})

test_that("a member of another project is checked as a pointer only", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  # Nothing of this project is in this namespace, and that is the ordinary case
  # rather than the error case: access in datom is per project.
  vs_replace_members(fx, list(vs_raw_member(project = "other-project",
                                            name = "ae")))

  seen <- vs_watch_storage()
  result <- vs_validate(fx)

  expect_equal(vs_row(result, fx$set_name)$status, "ok")
  expect_true(result$valid)
  # No existence check was even attempted for it -- reporting it missing would
  # be the defect this tolerance exists to avoid.
  expect_false(any(grepl("^ae/", seen$exists)))
})

test_that("a member that is a set is confirmed, never descended into", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  # An inner set that exists in storage only: a pinned version snapshot, and a
  # payload of its own that must not be opened.
  inner_version <- strrep("b", 64L)
  inner_data_sha <- strrep("c", 64L)
  inner_snapshot <- .datom_artifact_snapshot_key("inner", inner_version)
  inner_payload <- .datom_artifact_payload_key("inner", inner_data_sha, "set")

  purrr::walk(c(inner_snapshot, inner_payload), function(key) {
    path <- vs_stored(fx, key)
    fs::dir_create(fs::path_dir(path))
    jsonlite::write_json(list(kind = "set", data_sha = inner_data_sha),
                         path, auto_unbox = TRUE)
  })

  vs_replace_members(fx, list(vs_raw_member(name = "inner", kind = "set",
                                            version = inner_version)))

  seen <- vs_watch_storage()
  result <- vs_validate(fx)

  expect_equal(vs_row(result, fx$set_name)$status, "ok")
  expect_true(inner_snapshot %in% seen$exists)
  # The outer set's own payload is read; the inner one's is not, at any layer.
  expect_true(vs_payload_key(fx) %in% seen$read)
  expect_false(inner_payload %in% c(seen$read, seen$download))
  expect_false(inner_snapshot %in% c(seen$read, seen$download))
})

test_that("a set recording no document_sha is reported rather than tolerated", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  vs_edit_json(
    fs::path(fx$repo_dir, fx$set_name, "metadata.json"),
    function(doc) {
      doc$document_sha <- NULL
      doc
    }
  )

  result <- vs_validate(fx)

  # Not merged with the member finding: a reader refuses such a version before
  # it parses anything, and its message says to run this verb.
  expect_true("document_sha_missing" %in% vs_statuses(result, fx$set_name))
  expect_false("members_unresolvable" %in% vs_statuses(result, fx$set_name))
  expect_false(result$valid)
})


# === what a repair may and may not touch ======================================

test_that("fix = TRUE leaves a stored payload and its recorded hash alone", {
  fx <- local_validate_set_project()
  version <- vs_one_member_set(fx)

  payload <- vs_stored(fx, vs_payload_key(fx))
  before_bytes <- digest::digest(file = payload, algo = "sha256")
  stored_meta_key <- .datom_artifact_meta_key(fx$set_name, "metadata")
  before_recorded <- jsonlite::read_json(vs_stored(fx, stored_meta_key),
                                         simplifyVector = TRUE)$document_sha

  # Something else is wrong, so the repair runs: the mirrored manifest is gone.
  fs::file_delete(vs_stored(fx, ".metadata/manifest.json"))
  expect_false(vs_validate(fx)$valid)

  suppressMessages(datom_validate(fx$conn, fix = TRUE))

  expect_equal(digest::digest(file = payload, algo = "sha256"), before_bytes)
  expect_equal(
    jsonlite::read_json(vs_stored(fx, stored_meta_key),
                        simplifyVector = TRUE)$document_sha,
    before_recorded
  )

  # And the version-pinned read still verifies against that recorded hash.
  set_version <- datom_history(fx$conn, fx$set_name,
                               short_hash = FALSE)$version[[1L]]
  expect_silent(
    suppressMessages(datom_get_set(fx$conn, fx$set_name, version = set_version))
  )
  expect_true(vs_validate(fx)$valid)
  expect_type(version, "character")
})

test_that("fix = TRUE restores a set payload storage has lost", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  clone_payload <- fs::path(fx$repo_dir, fx$set_name, "set.json")
  payload <- vs_stored(fx, vs_payload_key(fx))
  recorded <- vs_clone_meta(fx)$document_sha
  fs::file_delete(payload)

  messages <- capture.output(datom_validate(fx$conn, fix = TRUE),
                             type = "message")
  combined <- paste(messages, collapse = " ")

  expect_true(fs::file_exists(payload))
  expect_equal(digest::digest(file = payload, algo = "sha256"), recorded)
  expect_equal(readLines(payload, warn = FALSE),
               readLines(clone_payload, warn = FALSE))
  expect_match(combined, "Restored the stored payload")

  # A set is NOT named among the artifacts the sync cannot repair -- that advice
  # points at a write verb which, with the members unchanged, does nothing.
  expect_false(grepl("still missing from storage", combined))

  after <- vs_validate(fx)
  expect_true(after$valid)
  expect_equal(vs_clone_meta(fx)$document_sha, recorded)
})

test_that("a stored payload that is present is never re-uploaded", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  # THE CLONE'S COPY IS LEFT MATCHING ON PURPOSE. Modifying it first would make
  # this test pass through the hash check instead, leaving the never-overwrite
  # rule -- the one that keeps a recorded document_sha describing real bytes --
  # unasserted.
  uploaded <- character()
  real_upload <- .datom_storage_upload
  local_mocked_bindings(
    .datom_storage_upload = function(conn, local_path, key) {
      uploaded <<- c(uploaded, key)
      real_upload(conn, local_path, key)
    }
  )

  fs::file_delete(vs_stored(fx, ".metadata/manifest.json"))
  suppressMessages(datom_validate(fx$conn, fix = TRUE))

  expect_false(vs_payload_key(fx) %in% uploaded)
  expect_equal(uploaded, character())
})

test_that("the mirror-everything route restores the payload too, not just the repair", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  payload <- vs_stored(fx, vs_payload_key(fx))
  recorded <- vs_clone_meta(fx)$document_sha
  fs::file_delete(payload)

  # The shared function both public routes land on: `datom_validate(fix = TRUE)`
  # and `datom_write(conn)` with no data and no name. Called directly here for
  # the reason test-sync.R calls it directly -- the write route asks for
  # interactive confirmation, which a test session cannot give.
  suppressMessages(.datom_sync_data_metadata(fx$conn, .confirm = FALSE))

  expect_true(fs::file_exists(payload))
  expect_equal(digest::digest(file = payload, algo = "sha256"), recorded)
})

test_that("the restore declines loudly when the clone's payload does not match", {
  fx <- local_validate_set_project()
  vs_one_member_set(fx)

  payload <- vs_stored(fx, vs_payload_key(fx))
  fs::file_delete(payload)
  cat("\n", file = fs::path(fx$repo_dir, fx$set_name, "set.json"),
      append = TRUE)

  messages <- capture.output(datom_validate(fx$conn, fix = TRUE),
                             type = "message")
  combined <- paste(messages, collapse = " ")

  expect_false(fs::file_exists(payload))
  expect_match(combined, "does not match the hash")
  expect_match(combined, "datom_write_set")
})
