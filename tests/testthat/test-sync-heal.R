# The scan and the sync on a real project (#155 task 6; requirements R4, R3.7;
# design section 7): the scan compares input files with the last commit and
# reports `unpushed` from the clone alone; the sync heals and pulls once for the
# whole batch, finishes what an earlier run left of its own tables, and stops
# after a table's write that failed partway once it had changed the clone.
#
# Real projects throughout (folder git remote, local store; no AWS, no GitHub),
# as in test-heal.R. A sync needs rio and an `input_files/` folder.


# --- fixtures -------------------------------------------------------------------

sh_project <- function(env = parent.frame()) {
  skip_if_not_installed("rio")
  fx <- local_interrupt_project(env = env)
  fx$input <- file.path(fx$repo, "input_files")
  fs::dir_create(fx$input)
  fx
}

# Write the input file of each table: `n` rows tagged `tag`.
sh_csv <- function(fx, names, n = 3L, tag = "a") {
  for (nm in names) {
    utils::write.csv(
      data.frame(id = seq_len(n), val = rep(tag, n), stringsAsFactors = FALSE),
      file.path(fx$input, paste0(nm, ".csv")),
      row.names = FALSE
    )
  }
  invisible(NULL)
}

sh_scan <- function(conn) suppressMessages(datom_sync_manifest(conn))

sh_sync <- function(conn, manifest = sh_scan(conn), ...) {
  suppressMessages(datom_sync(conn, manifest, ...))
}

# Each of `names` synced once (3 rows tagged "a"), then its input file changed
# (5 rows tagged "b"), so the next scan shows every one `changed`.
sh_synced_then_changed <- function(fx, names) {
  sh_csv(fx, names)
  first <- sh_sync(fx$conn)
  stopifnot(all(first$result == "success"))
  sh_csv(fx, names, n = 5L, tag = "b")
  invisible(NULL)
}

sh_status <- function(scan) stats::setNames(scan$status, scan$name)
sh_result <- function(sync) stats::setNames(sync$result, sync$name)

sh_rows_read <- function(fx, name) {
  nrow(as.data.frame(suppressMessages(datom_read(fx$reader, name))))
}

sh_clone_version <- function(fx, name) {
  jsonlite::read_json(file.path(fx$repo, ".datom", "manifest.json"))$artifacts[[name]]$current_version
}

sh_stored_version <- function(fx, name) {
  .datom_storage_read_json(fx$conn, ".metadata/manifest.json")$artifacts[[name]]$current_version
}

sh_snapshot <- function(fx) {
  list(
    clone = snapshot_clone(fx$repo),
    remote = snapshot_remote(fx),
    storage = snapshot_storage(fx)
  )
}

sh_msg <- function(err) gsub("\\s+", " ", cli::ansi_strip(conditionMessage(err)))

# Break one table's write, inside a sync, at one step; every other table's write
# runs unbroken. "import" breaks the file's import, before datom_write(); the
# other steps are local_break_at()'s, scoped to that table's one datom_write().
local_break_sync_at <- function(table, step, env = parent.frame()) {
  if (identical(step, "import")) {
    real_import <- get(".datom_import_file", envir = asNamespace("datom"))
    local_mocked_bindings(
      .datom_import_file = function(file, format) {
        if (identical(as.character(fs::path_ext_remove(fs::path_file(file))), table)) {
          stop(datom_test_break("import"))
        }
        real_import(file, format)
      },
      .env = env
    )
    return(invisible(NULL))
  }

  real_write <- get("datom_write", envir = asNamespace("datom"))
  local_mocked_bindings(
    datom_write = function(conn, data = NULL, name = NULL, ...) {
      if (identical(name, table)) local_break_at(step, name)
      real_write(conn, data = data, name = name, ...)
    },
    .env = env
  )
  invisible(NULL)
}

# Run a sync, keeping the "stopped after a failed write" messages (class
# `datom_sync_stopped`) and muffling every other message.
sh_sync_noting_stops <- function(conn, manifest = sh_scan(conn), ...) {
  notes <- character()
  value <- withCallingHandlers(
    datom_sync(conn, manifest, ...),
    message = function(m) {
      if (inherits(m, "datom_sync_stopped")) {
        notes <<- c(notes, gsub("\\s+", " ", cli::ansi_strip(conditionMessage(m))))
      }
      invokeRestart("muffleMessage")
    }
  )
  list(value = value, notes = notes)
}


# === the scan: against the last commit, `unpushed` from the clone (R4.1, R4.2) ===

test_that("the scan compares with the last commit: a table whose write stopped before its commit shows changed (R4.1)", {
  fx <- sh_project()
  sh_synced_then_changed(fx, "t1")
  broken <- local({
    local_break_sync_at("t1", "commit")
    sh_sync(fx$conn)
  })
  expect_identical(broken$result, "error")
  # The working tree's row already names the new file, so a scan reading it
  # would call the table unchanged.
  wt_sha <- jsonlite::read_json(file.path(fx$repo, ".datom", "manifest.json"))$artifacts$t1$original_file_sha
  expect_identical(wt_sha, sh_scan(fx$conn)$original_file_sha)

  expect_identical(sh_status(sh_scan(fx$conn)), c(t1 = "changed"))
})

test_that("a table saved but not pushed shows unpushed, read from the clone alone: no fetch, no storage read (R4.2)", {
  fx <- sh_project()
  sh_synced_then_changed(fx, c("t1", "t2"))
  local({
    local_break_sync_at("t2", "push")
    sh_sync(fx$conn)
  })

  calls <- c(fetch = 0L, storage = 0L)
  # `force()`: the real function, taken before the mock replaces it.
  count <- function(what, real) {
    force(real)
    function(...) {
      calls[[what]] <<- calls[[what]] + 1L
      real(...)
    }
  }
  ns <- asNamespace("datom")
  local_mocked_bindings(fetch = count("fetch", git2r::fetch), .package = "git2r")
  local_mocked_bindings(
    .datom_storage_read_json = count("storage", ns$.datom_storage_read_json),
    .datom_storage_exists = count("storage", ns$.datom_storage_exists),
    .datom_storage_list_objects = count("storage", ns$.datom_storage_list_objects),
    .datom_storage_download = count("storage", ns$.datom_storage_download)
  )

  scan <- sh_scan(fx$conn)

  expect_identical(sh_status(scan), c(t1 = "unchanged", t2 = "unpushed"))
  expect_identical(calls, c(fetch = 0L, storage = 0L))
})

test_that("a teammate's commit the clone has fetched but not merged is not counted as unpushed", {
  # `unpushed` is measured from the commit HEAD shares with the remote, not
  # from the remote's tip, so what the remote holds and this clone lacks is not
  # read as this clone's own unpushed work.
  fx <- sh_project()
  sh_csv(fx, c("t1", "t2"))
  sh_sync(fx$conn)
  b <- local_second_clone(fx)
  fs::dir_create(file.path(b$repo, "input_files"))
  sh_csv(fx, "t1", n = 5L, tag = "b")
  local({
    local_break_sync_at("t1", "push")
    sh_sync(fx$conn)
  })
  utils::write.csv(data.frame(id = 1:7, val = "c"),
                   file.path(b$repo, "input_files", "t2.csv"), row.names = FALSE)
  teammate <- sh_sync(b$conn)
  expect_identical(sh_result(teammate), c(t2 = "success"))
  git2r::fetch(git2r::repository(fx$repo), name = "origin")

  expect_identical(sh_status(sh_scan(fx$conn)), c(t1 = "unpushed", t2 = "unchanged"))
})

test_that("the scan names unpushed tables in its summary line only when there are some", {
  fx <- sh_project()
  sh_synced_then_changed(fx, "t1")
  expect_message(datom_sync_manifest(fx$conn), "0 new, 1 changed, 0 unchanged", fixed = TRUE)

  local({
    local_break_sync_at("t1", "push")
    sh_sync(fx$conn)
  })
  expect_message(datom_sync_manifest(fx$conn), "0 changed, 1 unpushed, 0 unchanged", fixed = TRUE)
})


# === the sync finishes its own tables (R4.3, R4.4) ================================

test_that("the sync pushes and publishes an unpushed row without importing the file (R4.3)", {
  fx <- sh_project()
  sh_synced_then_changed(fx, "t1")
  local({
    local_break_sync_at("t1", "push")
    sh_sync(fx$conn)
  })
  scan <- sh_scan(fx$conn)
  expect_identical(sh_status(scan), c(t1 = "unpushed"))
  imports <- 0L
  real_import <- get(".datom_import_file", envir = asNamespace("datom"))
  local_mocked_bindings(.datom_import_file = function(file, format) {
    imports <<- imports + 1L
    real_import(file, format)
  })

  result <- sh_sync(fx$conn, scan)

  expect_identical(sh_result(result), c(t1 = "success"))
  expect_identical(imports, 0L)
  expect_identical(unname(snapshot_remote(fx)), snapshot_clone(fx$repo)$head)
  expect_identical(sh_stored_version(fx, "t1"), sh_clone_version(fx, "t1"))
  expect_identical(sh_rows_read(fx, "t1"), 5L)
})

test_that("a table pushed but not yet published shows unchanged, and the sync that follows publishes it (R4.4)", {
  fx <- sh_project()
  sh_synced_then_changed(fx, "t1")
  local({
    local_break_sync_at("t1", "metadata")
    sh_sync(fx$conn)
  })
  scan <- sh_scan(fx$conn)
  expect_identical(sh_status(scan), c(t1 = "unchanged"))
  expect_identical(sh_rows_read(fx, "t1"), 3L)

  result <- sh_sync(fx$conn, scan)

  expect_identical(sh_result(result), c(t1 = "success"))
  expect_identical(sh_stored_version(fx, "t1"), sh_clone_version(fx, "t1"))
  expect_identical(sh_rows_read(fx, "t1"), 5L)
})

test_that("unfinished work on a table outside the preview stops the sync before anything changes", {
  fx <- sh_project()
  sh_synced_then_changed(fx, "t1")
  local({
    local_break_at("push")
    expect_error(
      suppressMessages(datom_write(fx$conn, data = data.frame(id = 1:2), name = "x")),
      class = "datom_test_break"
    )
  })
  before <- sh_snapshot(fx)

  err <- expect_error(sh_sync(fx$conn), class = "datom_unfinished_work")

  expect_match(sh_msg(err), "\"x\"", fixed = TRUE)
  expect_match(sh_msg(err), "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_identical(sh_snapshot(fx), before)
})

test_that("an unchanged preview row with uncommitted edits stops the sync, naming datom_validate(fix = TRUE), and its edits survive", {
  fx <- sh_project()
  sh_csv(fx, c("t1", "t2"))
  sh_sync(fx$conn)
  # A write of t1 from R (not from its file) that stopped before its commit.
  local({
    local_break_at("commit")
    expect_error(
      suppressMessages(datom_write(fx$conn, data = data.frame(id = 1:9), name = "t1")),
      class = "datom_test_break"
    )
  })
  sh_csv(fx, "t2", n = 5L, tag = "b")
  scan <- sh_scan(fx$conn)
  expect_identical(sh_status(scan), c(t1 = "unchanged", t2 = "changed"))
  before <- sh_snapshot(fx)

  err <- expect_error(sh_sync(fx$conn, scan), class = "datom_unfinished_work")

  expect_match(sh_msg(err), "\"t1\"", fixed = TRUE)
  expect_match(sh_msg(err), "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_identical(sh_snapshot(fx), before)
})


# === heal and the pull run once per sync (R3.7, R3.4) =============================

test_that("a three-table sync heals once and reads the stored manifest once", {
  fx <- sh_project()
  sh_synced_then_changed(fx, c("t1", "t2", "t3"))
  calls <- local_heal_counter()
  reads <- local_stored_manifest_reads()

  result <- sh_sync(fx$conn)

  expect_identical(unname(result$result), rep("success", 3L))
  expect_identical(calls(), c(reset = 1L, publish = 1L))
  expect_identical(reads(), 1L)
})

test_that("a sync whose fetch fails stops before anything changes (DD1)", {
  fx <- sh_project()
  sh_synced_then_changed(fx, "t1")
  scan <- sh_scan(fx$conn)
  before <- list(clone = snapshot_clone(fx$repo), storage = snapshot_storage(fx))
  fs::file_move(file.path(fx$root, "remote.git"), file.path(fx$root, "away.git"))

  expect_error(sh_sync(fx$conn, scan), class = "datom_fetch_failed")

  expect_identical(
    list(clone = snapshot_clone(fx$repo), storage = snapshot_storage(fx)),
    before
  )
})

test_that("a preview table whose metadata comes from a newer datom stops the sync before heal runs", {
  fx <- sh_project()
  sh_csv(fx, "t1")
  sh_sync(fx$conn)
  meta_path <- file.path(fx$repo, "t1", "metadata.json")
  meta <- jsonlite::read_json(meta_path)
  meta$future_field <- "from a newer datom"
  jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)
  git_commit_files(fx$repo, "t1/metadata.json", "A newer datom's document")
  calls <- local_heal_counter()

  expect_error(sh_sync(fx$conn), class = "datom_vocabulary_unknown")
  expect_identical(calls(), c(reset = 0L, publish = 0L))
})

test_that("a stale preview: a teammate synced the same file first, and the row says it was already up to date (DD3)", {
  fx <- sh_project()
  b <- local_second_clone(fx)
  fs::dir_create(file.path(b$repo, "input_files"))
  sh_csv(fx, "dm")
  file.copy(file.path(fx$input, "dm.csv"), file.path(b$repo, "input_files", "dm.csv"))
  mine <- sh_scan(fx$conn)
  expect_identical(sh_status(mine), c(dm = "new"))
  sh_sync(b$conn)

  msgs <- cli::ansi_strip(testthat::capture_messages(result <- datom_sync(fx$conn, mine)))

  expect_identical(sh_result(result), c(dm = "success"))
  expect_true(any(grepl("\"dm\" was already up to date", msgs, fixed = TRUE)))
  expect_false(any(grepl("synced (new)", msgs, fixed = TRUE)))
  expect_identical(nrow(datom_history(fx$conn, "dm")), 1L)
  expect_identical(snapshot_clone(fx$repo)$head, unname(snapshot_remote(fx)))
})


# === a write that fails partway (the break table's datom_sync() row; R4.6) =========

# The second of three tables broken at `step`. Checks the first sync's result
# and its stop note, and what a re-scan shows for t2; then runs the way out --
# after a stop, the same call with the same preview, as the note says; after a
# failure that left the clone untouched, a re-scan and re-sync -- and checks
# every table reads.
sh_break_second_of_three <- function(step, rescan_t2, stops) {
  fx <- sh_project(env = parent.frame())
  tables <- c("t1", "t2", "t3")
  sh_synced_then_changed(fx, tables)
  preview <- sh_scan(fx$conn)

  first <- local({
    local_break_sync_at("t2", step)
    sh_sync_noting_stops(fx$conn, preview)
  })

  expect_match(first$value$error[first$value$name == "t2"],
               paste("simulated break at", step), fixed = TRUE)
  if (stops) {
    expect_identical(sh_result(first$value),
                     c(t1 = "success", t2 = "error", t3 = "skipped"))
    expect_match(first$value$error[first$value$name == "t3"], "Not attempted", fixed = TRUE)
    expect_length(first$notes, 1L)
    expect_match(first$notes, "after the write of \"t2\" failed partway", fixed = TRUE)
    expect_match(first$notes, "Not attempted: \"t3\"", fixed = TRUE)
    expect_match(first$notes, "Run the same `datom_sync()` call again, with the same preview",
                 fixed = TRUE)
  } else {
    expect_identical(sh_result(first$value),
                     c(t1 = "success", t2 = "error", t3 = "success"))
    expect_length(first$notes, 0L)
  }

  rescan <- sh_scan(fx$conn)
  expect_identical(sh_status(rescan)[["t2"]], rescan_t2)

  again <- sh_sync(fx$conn, if (stops) preview else rescan)

  expect_false(any(again$result == "error"))
  for (t in tables) {
    expect_identical(sh_rows_read(fx, t), 5L)
    expect_identical(sh_stored_version(fx, t), sh_clone_version(fx, t))
  }
  expect_true(all(sh_scan(fx$conn)$status == "unchanged"))
  invisible(NULL)
}

test_that("sync: the second of three tables fails at its file import; the rest carry on, and a re-sync finishes it", {
  sh_break_second_of_three("import", rescan_t2 = "changed", stops = FALSE)
})

test_that("sync: the second of three tables fails at its data file upload; the rest carry on, and a re-sync finishes it", {
  sh_break_second_of_three("upload", rescan_t2 = "changed", stops = FALSE)
})

test_that("sync: the second of three tables fails at its commit; the sync stops, and a re-sync finishes it", {
  sh_break_second_of_three("commit", rescan_t2 = "changed", stops = TRUE)
})

test_that("sync: the second of three tables fails at its push; the sync stops, and a re-sync finishes it", {
  sh_break_second_of_three("push", rescan_t2 = "unpushed", stops = TRUE)
})

test_that("sync: the second of three tables fails at its manifest upload; the sync stops, and a re-sync finishes it", {
  sh_break_second_of_three("manifest", rescan_t2 = "unchanged", stops = TRUE)
})

test_that("a table whose write held back the manifest stops the sync, and the way out finishes every table (R4.6)", {
  # Two people at once (S7). t1's push brings in a teammate's commit of `ae`
  # whose files are not in storage yet, so t1's write publishes t1 and holds
  # back the manifest. Without the stop, t2's write -- whose own push brings in
  # nothing, so it checks nothing -- would upload the manifest naming `ae`.
  fx <- sh_project()
  sh_synced_then_changed(fx, c("t1", "t2"))
  b <- local_second_clone(fx)
  preview <- sh_scan(fx$conn)
  stored_manifest <- function() .datom_storage_read_json(fx$conn, ".metadata/manifest.json")
  stored_before <- stored_manifest()
  local_teammate_after_commit(function() {
    local({
      local_break_at("metadata")
      expect_error(
        suppressMessages(datom_write(b$conn, data = data.frame(id = 1:4), name = "ae")),
        class = "datom_test_break"
      )
    })
  })

  held <- list()
  run <- withCallingHandlers(
    sh_sync_noting_stops(fx$conn, preview),
    datom_manifest_held_back = function(w) {
      held[[length(held) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  )

  expect_length(held, 1L)
  expect_identical(held[[1]]$disagree, "ae")
  expect_identical(sh_result(run$value), c(t1 = "success", t2 = "skipped"))
  expect_match(run$value$error[run$value$name == "t2"], "held back the manifest", fixed = TRUE)
  expect_identical(stored_manifest(), stored_before)
  expect_identical(sh_rows_read(fx, "t1"), 5L)
  expect_identical(sh_rows_read(fx, "t2"), 3L)
  expect_length(run$notes, 1L)
  expect_match(run$notes, "after the write of \"t1\" held back the manifest", fixed = TRUE)
  expect_match(run$notes, "a version of \"ae\" that storage does not hold yet", fixed = TRUE)
  expect_match(run$notes, "Not attempted: \"t2\"", fixed = TRUE)
  expect_match(run$notes, "Run `datom_validate(fix = TRUE)`", fixed = TRUE)

  # The same call alone stops on the teammate's table, naming the same fix.
  err <- expect_error(sh_sync(fx$conn, preview), class = "datom_unfinished_work")
  expect_match(sh_msg(err), "\"ae\"", fixed = TRUE)
  expect_match(sh_msg(err), "datom_validate(fix = TRUE)", fixed = TRUE)

  # The way out the stop names: the fix, then the same call again.
  suppressMessages(suppressWarnings(datom_validate(fx$conn, fix = TRUE)))
  again <- sh_sync(fx$conn, preview)

  expect_identical(sh_result(again), c(t1 = "success", t2 = "success"))
  expect_identical(sh_rows_read(fx, "t1"), 5L)
  expect_identical(sh_rows_read(fx, "t2"), 5L)
  expect_identical(sh_rows_read(fx, "ae"), 4L)
  for (t in c("t1", "t2", "ae")) {
    expect_identical(sh_stored_version(fx, t), sh_clone_version(fx, t))
  }
})

test_that("with continue_on_error = FALSE, a write that changed the clone says to run the same sync again", {
  fx <- sh_project()
  sh_synced_then_changed(fx, c("t1", "t2"))

  err <- local({
    local_break_sync_at("t1", "push")
    expect_error(sh_sync(fx$conn, continue_on_error = FALSE), "t1")
  })
  expect_match(sh_msg(err), "Run the same `datom_sync()` call again, with the same preview",
               fixed = TRUE)
  expect_no_match(sh_msg(err), "continue_on_error = TRUE", fixed = TRUE)

  # A failure that left the clone untouched still suggests carrying on.
  err <- local({
    local_break_sync_at("t2", "import")
    expect_error(sh_sync(fx$conn, continue_on_error = FALSE), "t2")
  })
  expect_match(sh_msg(err), "continue_on_error = TRUE", fixed = TRUE)
})
