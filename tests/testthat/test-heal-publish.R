# Heal's publish: a committed version GitHub or storage lacks is pushed and
# published before a write's own work, and only for the artifacts the command
# publishes (#155; design section 4, step d).
#
# Real projects throughout (folder git remote, local store; no AWS, no GitHub),
# as in test-heal.R: nothing in the datom stack is mocked except the binding
# that raises a break, a counter, or a failure a test must cause. "Nothing
# changed" compares snapshots of the clone, the remote and storage.


# --- fixtures -------------------------------------------------------------------

hp_df <- function(n = 3L, tag = "a") {
  data.frame(id = seq_len(n), val = rep(tag, n), stringsAsFactors = FALSE)
}

hp_write <- function(conn, name, n = 3L, tag = "a") {
  suppressMessages(datom_write(conn, data = hp_df(n, tag), name = name))
}

# Break a write of `name` at `step`; the break must be the error it stopped on.
hp_break <- function(conn, step, name, n = 5L, tag = "b") {
  local_break_at(step, name)
  expect_error(
    suppressMessages(datom_write(conn, data = hp_df(n, tag), name = name)),
    class = "datom_test_break"
  )
}

hp_snapshot <- function(fx, clone = fx$repo) {
  list(
    clone = snapshot_clone(clone),
    remote = snapshot_remote(fx),
    storage = snapshot_storage(fx)
  )
}

hp_msg <- function(err) gsub("\\s+", " ", cli::ansi_strip(conditionMessage(err)))

hp_stored_manifest <- function(fx) {
  .datom_storage_read_json(fx$conn, ".metadata/manifest.json")
}

hp_stored_version <- function(fx, name) {
  hp_stored_manifest(fx)$artifacts[[name]]$current_version
}

hp_clone_version <- function(repo, name) {
  jsonlite::read_json(file.path(repo, ".datom", "manifest.json"))$artifacts[[name]]$current_version
}

hp_rows_read <- function(fx, name) {
  nrow(as.data.frame(suppressMessages(datom_read(fx$reader, name))))
}

hp_head <- function(repo) git2r::sha(git2r::last_commit(git2r::repository(repo)))

# Rewrite the stored manifest, as storage edited outside datom would be.
hp_edit_stored_manifest <- function(fx, edit) {
  m <- hp_stored_manifest(fx)
  .datom_storage_write_json(fx$conn, ".metadata/manifest.json", edit(m))
}

# Record the storage keys written, passing every write through.
local_write_keys <- function(env = parent.frame()) {
  keys <- character()
  real <- get(".datom_storage_write_json", envir = asNamespace("datom"))
  local_mocked_bindings(
    .datom_storage_write_json = function(conn, key, data) {
      keys <<- c(keys, key)
      real(conn, key, data)
    },
    .env = env
  )
  function() keys
}

hp_published_notes <- function(expr) {
  notes <- character()
  value <- withCallingHandlers(expr, message = function(m) {
    if (inherits(m, "datom_heal_published")) {
      notes <<- c(notes, cli::ansi_strip(conditionMessage(m)))
    }
    invokeRestart("muffleMessage")
  })
  list(value = value, notes = notes)
}


# === a write finishes its own committed version (R2.2, R2.3) =====================

test_that("a re-run after a break in the metadata upload says it finished the earlier write, in order", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  hp_break(fx$conn, "metadata", "dm")
  v2 <- hp_clone_version(fx$repo, "dm")
  keys <- local_write_keys()

  run <- hp_published_notes(datom_write(fx$conn, data = hp_df(5L, "b"), name = "dm"))

  expect_length(run$notes, 1L)
  expect_match(run$notes, "Finished an earlier write of \"dm\"", fixed = TRUE)
  expect_match(run$notes, substr(v2, 1, 8), fixed = TRUE)
  expect_identical(run$value$action, "none")
  # Heal's publish: snapshot, history, metadata.json, then the manifest.
  expect_identical(keys(), c(
    .datom_artifact_snapshot_key("dm", v2),
    .datom_artifact_meta_key("dm", "version_history"),
    .datom_artifact_meta_key("dm", "metadata"),
    ".metadata/manifest.json"
  ))
})

test_that("a write with nothing to save leaves the user's own unpushed commit alone", {
  # `datom_repo_commit(push = FALSE)` says "push later". The clone is ahead, but
  # nothing of datom's is unfinished, so heal's publish has nothing to do and
  # must not push it. (Review of 5bdb7da: before the fix it pushed it, and the
  # user saw only "No changes detected".)
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  writeLines("build <- function() NULL", file.path(fx$repo, "build.R"))
  suppressMessages(datom_repo_commit(fx$conn, "Add build", paths = "build.R", push = FALSE))
  user_commit <- hp_head(fx$repo)
  remote_before <- snapshot_remote(fx)
  storage_before <- snapshot_storage(fx)

  expect_identical(hp_write(fx$conn, "dm")$action, "none")

  expect_identical(snapshot_remote(fx), remote_before)
  expect_identical(snapshot_storage(fx), storage_before)
  expect_identical(hp_head(fx$repo), user_commit)
})

test_that("a write reads the stored manifest once (R3.4)", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  reads <- local_stored_manifest_reads()

  hp_write(fx$conn, "dm", 5L, "b")

  expect_identical(reads(), 1L)
})

test_that("a revert to earlier content, then storage failing after the push, is published by the re-run (S4)", {
  # Containment, not "older": the revert brings back v1's id, which the history
  # already holds below v2, and the stored row names v2.
  fx <- local_interrupt_project()
  v1 <- hp_write(fx$conn, "dm")
  hp_write(fx$conn, "dm", 5L, "b")
  hp_break(fx$conn, "metadata", "dm", n = 3L, tag = "a")
  expect_identical(hp_clone_version(fx$repo, "dm"), v1$metadata_sha)

  rerun <- hp_write(fx$conn, "dm")

  expect_identical(rerun$action, "none")
  expect_identical(hp_stored_version(fx, "dm"), v1$metadata_sha)
  expect_identical(hp_rows_read(fx, "dm"), 3L)
})


# === the metadata-only route publishes its own table (two lists) =================

test_that("datom_write(conn, name =) after a break in the metadata upload publishes the version and the manifest", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  hp_break(fx$conn, "metadata", "dm")
  v2 <- hp_clone_version(fx$repo, "dm")

  result <- suppressMessages(datom_write(fx$conn, name = "dm"))

  expect_identical(result$action, "published")
  expect_identical(result$metadata_sha, v2)
  expect_identical(hp_stored_version(fx, "dm"), v2)
  expect_true(.datom_storage_exists(fx$conn, .datom_artifact_snapshot_key("dm", v2)))
  expect_identical(hp_rows_read(fx, "dm"), 5L)
})

test_that("datom_write(conn, name =) stops on an uncommitted change to the table's manifest row", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  manifest_path <- file.path(fx$repo, ".datom", "manifest.json")
  m <- jsonlite::read_json(manifest_path)
  m$artifacts$dm$size_bytes <- 1
  jsonlite::write_json(m, manifest_path, auto_unbox = TRUE, pretty = TRUE)
  before <- hp_snapshot(fx)

  err <- expect_error(
    suppressMessages(datom_write(fx$conn, name = "dm")),
    class = "datom_unfinished_work"
  )

  expect_match(hp_msg(err), "\"dm\": changes to datom's files that were never committed ('.datom/manifest.json')", fixed = TRUE)
  expect_identical(hp_snapshot(fx), before)
})

test_that("heal refuses to reset an artifact the command does not publish", {
  fx <- local_interrupt_project()
  expect_error(
    .datom_heal(fx$conn, artifact = "dm", rewrite = c("dm", "lb")),
    class = "datom_internal_error"
  )
})

test_that("datom_write(conn, name =) pushes a commit the remote lacks before it publishes, and makes no commit", {
  # So storage never names a version GitHub does not have. (Moved here from a
  # mocked test in test-read-write.R when the push moved into heal's publish.)
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  hp_break(fx$conn, "push", "dm")
  head <- hp_head(fx$repo)
  events <- character()
  real_push <- get(".datom_git_push", envir = asNamespace("datom"))
  real_write <- get(".datom_storage_write_json", envir = asNamespace("datom"))
  local_mocked_bindings(
    .datom_git_push = function(...) {
      events <<- c(events, "push")
      real_push(...)
    },
    .datom_storage_write_json = function(conn, key, data) {
      events <<- c(events, "upload")
      real_write(conn, key, data)
    }
  )

  suppressMessages(datom_write(fx$conn, name = "dm"))

  expect_identical(events[[1]], "push")
  expect_identical(sum(events == "push"), 1L)
  expect_true("upload" %in% events)
  expect_identical(hp_head(fx$repo), head)
  expect_identical(unname(snapshot_remote(fx)), head)
})

test_that("datom_write(conn, name =) pushes first when it uploads a committed metadata.json the remote lacks", {
  # The stored manifest row agrees (a document committed outside datom), so
  # heal's publish finds nothing to finish and does not push; the route's own
  # upload must not name a document GitHub does not have. (Review of 5bdb7da.)
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  meta_path <- file.path(fx$repo, "dm", "metadata.json")
  meta <- jsonlite::read_json(meta_path)
  meta$custom <- list(note = "edited by hand")
  jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)
  git_commit_files(fx$repo, "dm/metadata.json", "Edit dm's metadata by hand", push = FALSE)
  events <- character()
  real_push <- get(".datom_git_push", envir = asNamespace("datom"))
  real_write <- get(".datom_storage_write_json", envir = asNamespace("datom"))
  local_mocked_bindings(
    .datom_git_push = function(...) {
      events <<- c(events, "push")
      real_push(...)
    },
    .datom_storage_write_json = function(conn, key, data) {
      events <<- c(events, "upload")
      real_write(conn, key, data)
    }
  )

  expect_identical(suppressMessages(datom_write(fx$conn, name = "dm"))$action, "published")

  expect_identical(events[[1]], "push")
  expect_identical(unname(snapshot_remote(fx)), hp_head(fx$repo))
})

test_that("datom_write(conn, name =) broken at its push finishes on a re-run", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  hp_break(fx$conn, "push", "dm")
  v2 <- hp_clone_version(fx$repo, "dm")
  local({
    local_break_at("push")
    expect_error(suppressMessages(datom_write(fx$conn, name = "dm")),
                 class = "datom_test_break")
  })
  expect_identical(hp_rows_read(fx, "dm"), 3L)

  suppressMessages(datom_write(fx$conn, name = "dm"))

  expect_identical(hp_rows_read(fx, "dm"), 5L)
  expect_identical(hp_stored_version(fx, "dm"), v2)
})

test_that("datom_write(conn, name =) broken at its metadata upload finishes on a re-run", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  hp_break(fx$conn, "metadata", "dm")
  v2 <- hp_clone_version(fx$repo, "dm")
  local({
    local_break_at("metadata", "dm")
    # The route's publish is heal's, which stops with its own message; the
    # break is the failure it carries.
    err <- expect_error(suppressMessages(datom_write(fx$conn, name = "dm")),
                        class = "datom_publish_failed")
    expect_s3_class(err$failed$dm, "datom_test_break")
  })
  expect_identical(hp_rows_read(fx, "dm"), 3L)

  suppressMessages(datom_write(fx$conn, name = "dm"))

  expect_identical(hp_rows_read(fx, "dm"), 5L)
  expect_identical(hp_stored_version(fx, "dm"), v2)
})

test_that("a committed metadata.json that does not hash to its recorded version gets its own snapshot, and the manifest still goes up", {
  # A hand edit committed with plain git, as 0.2.0's metadata-only route did.
  # Heal's comparison of manifest rows cannot see it (the row is unchanged); the
  # route's own check of the stored metadata.json does.
  fx <- local_interrupt_project()
  v1 <- hp_write(fx$conn, "dm")
  v1_snapshot <- .datom_local_path(fx$conn, .datom_artifact_snapshot_key("dm", v1$metadata_sha))
  v1_bytes <- tools::md5sum(v1_snapshot)
  meta_path <- file.path(fx$repo, "dm", "metadata.json")
  meta <- jsonlite::read_json(meta_path)
  meta$custom <- list(note = "edited by hand")
  jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)
  git_commit_files(fx$repo, "dm/metadata.json", "Edit dm's metadata by hand")
  edited <- .datom_compute_metadata_sha(jsonlite::read_json(meta_path))
  expect_false(identical(edited, v1$metadata_sha))
  keys <- local_write_keys()

  suppressMessages(datom_write(fx$conn, name = "dm"))

  expect_identical(tools::md5sum(v1_snapshot), v1_bytes)
  expect_true(.datom_storage_exists(fx$conn, .datom_artifact_snapshot_key("dm", edited)))
  expect_identical(utils::tail(keys(), 1L), ".metadata/manifest.json")
  snapshots <- grep("^dm/\\.metadata/[0-9a-f]{64}\\.json$", keys(), value = TRUE)
  expect_identical(snapshots, .datom_artifact_snapshot_key("dm", edited))
})


# === another artifact's committed work stops a write (D14 principle 8, P13) =======

test_that("another table's write broken after its commit stops a write of a different table, changing nothing (P13, R7.2)", {
  for (step in c("push", "metadata")) {
    fx <- local_interrupt_project()
    hp_write(fx$conn, "dm")
    hp_write(fx$conn, "lb")
    hp_break(fx$conn, step, "lb")
    before <- hp_snapshot(fx)

    err <- expect_error(hp_write(fx$conn, "dm", 7L, "c"),
                        class = "datom_unfinished_work", label = step)

    msg <- hp_msg(err)
    expect_match(msg, "\"lb\": storage and this clone name different versions",
                 fixed = TRUE, label = step)
    # A stored row that differs can be a teammate's publish not yet pulled.
    expect_match(msg, "If a teammate has just written it", fixed = TRUE, label = step)
    expect_match(msg, "Nothing was published", label = step)
    expect_match(msg, "datom_validate(fix = TRUE)", fixed = TRUE, label = step)
    expect_identical(hp_snapshot(fx), before, label = step)
  }
})

test_that("a publish landing behind a colleague's newer one is corrected by that table's next write, and a write of another table stops (P10)", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  # This clone pushes v2, and its publish is slow ...
  hp_break(fx$conn, "metadata", "dm")
  # ... while the teammate pulls v2, writes v3 and publishes it ...
  v3 <- hp_write(b$conn, "dm", 7L, "c")
  # ... and then this clone's publish of v2 lands.
  suppressMessages(.datom_publish_artifacts(fx$conn, "dm"))
  expect_identical(hp_rows_read(fx, "dm"), 5L)

  # In an up-to-date clone, a write of another table stops naming the fix.
  before <- hp_snapshot(fx, b$repo)
  err <- expect_error(hp_write(b$conn, "lb"), class = "datom_unfinished_work")
  expect_match(hp_msg(err), "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_identical(hp_snapshot(fx, b$repo), before)

  # The table's next write puts storage back at git's latest.
  rerun <- hp_write(b$conn, "dm", 7L, "c")
  expect_identical(rerun$action, "none")
  expect_identical(hp_stored_version(fx, "dm"), v3$metadata_sha)
  expect_identical(hp_rows_read(fx, "dm"), 7L)
})


# === storage that names something this clone has never seen (R3.10, P14) =========

test_that("storage naming a version the clone's history lacks stops a write, and the repair publishes the clone's in its place", {
  fx <- local_interrupt_project()
  v1 <- hp_write(fx$conn, "dm")
  unseen <- strrep("f", 64L)
  hp_edit_stored_manifest(fx, function(m) {
    m$artifacts$dm$current_version <- unseen
    m
  })
  before <- hp_snapshot(fx)

  err <- expect_error(hp_write(fx$conn, "dm", 5L, "b"),
                      class = "datom_stored_version_unseen")

  msg <- hp_msg(err)
  expect_match(msg, "\"ffffffff\" of \"dm\"", fixed = TRUE)
  expect_match(msg, "Re-run", fixed = TRUE)
  expect_match(msg, "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_identical(hp_snapshot(fx), before)

  # The repair's half of heal (wired into datom_validate(fix = TRUE) with the
  # repair itself) publishes this clone's version and names the one it replaced.
  expect_warning(
    suppressMessages(.datom_heal_publish(fx$conn, all = TRUE)),
    regexp = "ffffffff", class = "datom_heal_override"
  )
  expect_identical(hp_stored_version(fx, "dm"), v1$metadata_sha)

  expect_identical(hp_write(fx$conn, "dm", 5L, "b")$action, "full")
})

test_that("a stored row for an artifact the clone lacks stops a write, and the repair drops it, saying so", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  hp_edit_stored_manifest(fx, function(m) {
    m$artifacts$zz <- m$artifacts$dm
    m
  })
  before <- hp_snapshot(fx)

  err <- expect_error(hp_write(fx$conn, "dm", 5L, "b"), class = "datom_unfinished_work")

  msg <- hp_msg(err)
  expect_match(msg, "\"zz\": storage names it, this clone does not have it", fixed = TRUE)
  expect_match(msg, "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_identical(hp_snapshot(fx), before)

  expect_warning(
    suppressMessages(.datom_heal_publish(fx$conn, all = TRUE)),
    regexp = "zz.*dropped", class = "datom_heal_override"
  )
  expect_false("zz" %in% names(hp_stored_manifest(fx)$artifacts))

  expect_identical(hp_write(fx$conn, "dm", 5L, "b")$action, "full")
})


# === the manifest upload when the push brought in a teammate's commit (R3.10) =====

# A write of `dm` whose push brings in the teammate's commit of `lb`, made (and,
# with `teammate_published`, published) after this write's opening pull and
# heal. The push is replaced by one that leaves the clone as that merge would --
# the teammate's `lb` files and manifest row committed -- then pushes, and says
# it pulled commits in, so these tests reach the agreement check without the
# manifest rebuild. The end-to-end case, through a real merge, is in
# test-manifest-conflict.R.
hp_push_bringing_in <- function(fx, b, teammate_published = FALSE,
                                env = parent.frame()) {
  real_push <- get(".datom_git_push", envir = asNamespace("datom"))
  local_mocked_bindings(
    .datom_git_push = function(path, pat = NULL, pull_first = TRUE) {
      # Only the write's own push pulls first; heal's and the publish's do not.
      if (!isTRUE(pull_first)) {
        return(real_push(path, pat = pat, pull_first = pull_first))
      }
      # The teammate's documents only: the publish would push their commit
      # first, and this stand-in for a merge keeps that commit off the remote.
      if (teammate_published) {
        testthat::with_mocked_bindings(
          suppressMessages(.datom_publish_artifacts(b$conn, "lb")),
          .datom_git_ahead = function(...) 0L
        )
      }
      fs::dir_copy(file.path(b$repo, "lb"), file.path(path, "lb"), overwrite = TRUE)
      theirs <- jsonlite::read_json(file.path(b$repo, ".datom", "manifest.json"))
      manifest_path <- file.path(path, ".datom", "manifest.json")
      ours <- jsonlite::read_json(manifest_path)
      ours$artifacts$lb <- theirs$artifacts$lb
      jsonlite::write_json(ours, manifest_path, auto_unbox = TRUE, pretty = TRUE)
      git_commit_files(path, c("lb/metadata.json", "lb/version_history.json",
                               ".datom/manifest.json"),
                       "Merge the teammate's lb", push = FALSE)
      real_push(path, pat = pat, pull_first = FALSE)
      invisible(TRUE)
    },
    .env = env
  )
}

test_that("a write whose push brings in a teammate's version storage lacks publishes its own documents and holds back the manifest", {
  fx <- local_interrupt_project()
  v1 <- hp_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  hp_break(b$conn, "push", "lb")
  hp_push_bringing_in(fx, b)

  expect_warning(
    v2 <- hp_write(fx$conn, "dm", 5L, "b"),
    regexp = "datom_validate(fix = TRUE)", fixed = TRUE
  )

  expect_identical(hp_rows_read(fx, "dm"), 5L)
  expect_identical(hp_stored_version(fx, "dm"), v1$metadata_sha)
  expect_false("lb" %in% names(hp_stored_manifest(fx)$artifacts))
})

test_that("a write whose push brings in a teammate's version already in storage publishes the manifest", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  hp_break(b$conn, "push", "lb")
  hp_push_bringing_in(fx, b, teammate_published = TRUE)

  v2 <- expect_no_warning(hp_write(fx$conn, "dm", 5L, "b"))

  stored <- hp_stored_manifest(fx)
  expect_identical(stored$artifacts$dm$current_version, v2$metadata_sha)
  expect_identical(stored$artifacts$lb$current_version, hp_clone_version(b$repo, "lb"))
})


test_that("heal's push does not pull, so a teammate's commit landing after the route's pull is refused, not published", {
  # This clone re-runs a write of dm whose push broke, so heal's publish pushes
  # dm's commit. A teammate's commit of lb (its publish not yet landed) reaches
  # the remote just after this write's pull. Had heal's push pulled it in, the
  # manifest heal uploads would name lb's version before lb's documents were in
  # storage: the merge's manifest-only conflict would be rebuilt, naming it.
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  hp_break(b$conn, "push", "lb")
  hp_break(fx$conn, "push", "dm")
  real_pull <- get(".datom_pull_before_write", envir = asNamespace("datom"))
  local_mocked_bindings(.datom_pull_before_write = function(conn, ...) {
    moved <- real_pull(conn, ...)
    git2r::push(git2r::repository(b$repo), name = "origin",
                refspec = test_head_refspec(git2r::repository(b$repo)))
    moved
  })
  storage_before <- snapshot_storage(fx)

  expect_error(hp_write(fx$conn, "dm", 5L, "b"), class = "datom_push_rejected")

  expect_identical(snapshot_storage(fx), storage_before)
})


# === when heal's publish fails ===================================================

test_that("heal's publish failing stops the write before its own work, naming the artifact and the file, with the manifest held back", {
  fx <- local_interrupt_project()
  v1 <- hp_write(fx$conn, "dm")
  hp_break(fx$conn, "metadata", "dm")
  head <- hp_head(fx$repo)
  real <- get(".datom_storage_write_json", envir = asNamespace("datom"))
  history_key <- .datom_artifact_meta_key("dm", "version_history")
  uploads <- mock_upload_absent(NULL)
  local_mocked_bindings(
    .datom_storage_write_json = function(conn, key, data) {
      if (identical(key, history_key)) stop("disk full")
      real(conn, key, data)
    },
    .datom_storage_upload_absent = uploads$fn
  )

  err <- expect_error(hp_write(fx$conn, "dm", 7L, "c"), class = "datom_publish_failed")

  msg <- hp_msg(err)
  expect_match(msg, "\"dm\", at 'dm/.metadata/version_history.json': disk full",
               fixed = TRUE)
  expect_match(msg, "manifest was not published")
  expect_identical(hp_stored_version(fx, "dm"), v1$metadata_sha)
  expect_identical(hp_head(fx$repo), head)
  expect_length(uploads$keys(), 0L)
})

hp_break_history_file <- function(fx) {
  writeLines("{ not json", file.path(fx$repo, "dm", "version_history.json"))
  git_commit_files(fx$repo, "dm/version_history.json", "A history that does not parse")
}

test_that("a committed history that does not parse stops heal's publish with the restore message", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  hp_break(fx$conn, "metadata", "dm")
  hp_break_history_file(fx)
  before <- hp_snapshot(fx)

  err <- expect_error(hp_write(fx$conn, "dm", 7L, "c"),
                      class = "datom_clone_file_unreadable")

  msg <- hp_msg(err)
  expect_match(msg, "'dm/version_history.json' does not parse", fixed = TRUE)
  expect_match(msg, "git checkout <commit> -- dm/metadata.json dm/version_history.json",
               fixed = TRUE)
  expect_identical(hp_snapshot(fx), before)
})

test_that("a committed history that does not parse stops a write of that artifact with nothing pending, changing nothing", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  hp_break_history_file(fx)
  before <- hp_snapshot(fx)

  err <- expect_error(hp_write(fx$conn, "dm", 7L, "c"),
                      class = "datom_clone_file_unreadable")

  expect_match(hp_msg(err), "git log -- dm/", fixed = TRUE)
  expect_identical(hp_snapshot(fx), before)
})

test_that("a committed history that does not parse stops a metadata-only change too, changing nothing", {
  # Same data, new custom metadata: no data file decision reads the history, so
  # the local metadata write is the first reader, and it reads before it writes.
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  hp_break_history_file(fx)
  before <- hp_snapshot(fx)

  expect_error(
    suppressMessages(datom_write(fx$conn, data = hp_df(), name = "dm",
                                 metadata = list(note = "new"))),
    class = "datom_clone_file_unreadable"
  )
  expect_identical(hp_snapshot(fx), before)
})


# === the line saying what happened ===============================================

test_that("a pull that stops after heal put the write's own files back says nothing was published; heal's own line names the reset", {
  fx <- local_interrupt_project()
  hp_write(fx$conn, "dm")
  writeLines("v1", file.path(fx$repo, "app.R"))
  git_commit_files(fx$repo, "app.R", "Add app.R")
  b <- local_second_clone(fx)
  hp_break(fx$conn, "commit", "dm")
  writeLines("v2", file.path(b$repo, "app.R"))
  git_commit_files(b$repo, "app.R", "Teammate's edit")
  writeLines("local edit", file.path(fx$repo, "app.R"))

  notes <- character()
  err <- withCallingHandlers(
    expect_error(datom_write(fx$conn, data = hp_df(5L, "b"), name = "dm"),
                 class = "datom_pull_blocked"),
    message = function(m) {
      if (inherits(m, "datom_heal_reset")) {
        notes <<- c(notes, cli::ansi_strip(conditionMessage(m)))
      }
      invokeRestart("muffleMessage")
    }
  )

  expect_match(notes, "unfinished write of \"dm\".*writing it again now")
  msg <- hp_msg(err)
  expect_match(msg, "git stash -u", fixed = TRUE)
  expect_match(msg, "Nothing was published.", fixed = TRUE)
  expect_no_match(msg, "datom changed nothing")
})
