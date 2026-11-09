# The git and config commands meet unfinished datom work (#155, task 8;
# requirements R3.5, R3.6, D9, D10).
#
# `datom_repo_commit()` never commits a datom write that stopped before its own
# commit: when the commit would take datom's uncommitted files it stops before
# staging anything. The four push commands push a datom write's commit without
# publishing it, and say so.
#
# Real projects throughout (folder git remote, local store; no AWS, no GitHub):
# nothing in the datom stack is mocked except the binding that raises a break.


# --- fixtures -------------------------------------------------------------------

ru_df <- function(n = 3L, tag = "a") {
  data.frame(id = seq_len(n), val = rep(tag, n), stringsAsFactors = FALSE)
}

ru_write <- function(conn, name, n = 3L, tag = "a") {
  suppressMessages(datom_write(conn, data = ru_df(n, tag), name = name))
}

# Break a write of `name` at `step`; the break must be the error it stopped on.
ru_break <- function(conn, step, name, n = 5L, tag = "b") {
  local_break_at(step, name)
  expect_error(
    suppressMessages(datom_write(conn, data = ru_df(n, tag), name = name)),
    class = "datom_test_break"
  )
}

ru_snapshot <- function(fx) {
  list(
    clone = snapshot_clone(fx$repo),
    remote = snapshot_remote(fx),
    storage = snapshot_storage(fx)
  )
}

ru_msg <- function(err) gsub("\\s+", " ", cli::ansi_strip(conditionMessage(err)))

ru_rows_read <- function(fx, name) {
  nrow(as.data.frame(suppressMessages(datom_read(fx$reader, name))))
}

ru_head <- function(repo) git2r::sha(git2r::last_commit(git2r::repository(repo)))

ru_remote_tip <- function(fx) unname(snapshot_remote(fx))

# `dm` written once, then a second write of it stopped before its commit: its
# datom files are changed and uncommitted. Plus a file of the user's.
ru_unfinished_dm <- function(fx) {
  ru_write(fx$conn, "dm")
  ru_break(fx$conn, "commit", "dm")
  writeLines("build <- function() NULL", file.path(fx$repo, "build.R"))
  expect_true(length(.datom_unfinished_files(fx$conn)) > 0L)
}

# The R3.6 messages a call gives, with the artifacts each names.
ru_pushed_notes <- function(expr) {
  notes <- list()
  value <- withCallingHandlers(expr, message = function(m) {
    if (inherits(m, "datom_pushed_unpublished")) {
      notes[[length(notes) + 1L]] <<- list(
        text = gsub("\\s+", " ", cli::ansi_strip(conditionMessage(m))),
        pushed = m$pushed
      )
    }
    invokeRestart("muffleMessage")
  })
  list(value = value, notes = notes)
}


# === datom_repo_commit() and a write that never committed (R3.5) =================

test_that("datom_repo_commit(paths = NULL) stops on a write that never committed, changing nothing", {
  fx <- local_interrupt_project()
  ru_unfinished_dm(fx)
  before <- ru_snapshot(fx)

  err <- expect_error(
    suppressMessages(datom_repo_commit(fx$conn, "Add build script")),
    class = "datom_unfinished_work"
  )

  msg <- ru_msg(err)
  expect_match(msg, "\"dm\" has unfinished work", fixed = TRUE)
  expect_match(msg, "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_match(msg, "datom changed nothing", fixed = TRUE)
  expect_identical(ru_snapshot(fx), before)
})

test_that("after datom_validate(fix = TRUE), datom_repo_commit(paths = NULL) commits the user's files and none of the write's", {
  fx <- local_interrupt_project()
  ru_unfinished_dm(fx)
  dm_head <- .datom_git_head_file(fx$repo, "dm/metadata.json")

  suppressWarnings(suppressMessages(datom_validate(fx$conn, fix = TRUE)))
  expect_length(.datom_unfinished_files(fx$conn), 0L)

  suppressMessages(datom_repo_commit(fx$conn, "Add build script"))

  expect_false(is.null(.datom_git_head_file(fx$repo, "build.R")))
  expect_identical(.datom_git_head_file(fx$repo, "dm/metadata.json"), dm_head)
  expect_identical(ru_rows_read(fx, "dm"), 3L)
})

test_that("datom_repo_commit() stops when a path names a datom file or a folder holding one", {
  fx <- local_interrupt_project()
  ru_unfinished_dm(fx)
  before <- ru_snapshot(fx)

  for (p in list("dm", "dm/", "dm/metadata.json", ".datom", ".",
                 c("build.R", "dm/version_history.json"))) {
    expect_error(
      suppressMessages(datom_repo_commit(fx$conn, "Commit", paths = p, push = FALSE)),
      class = "datom_unfinished_work",
      info = paste(p, collapse = ", ")
    )
    expect_identical(ru_snapshot(fx), before, info = paste(p, collapse = ", "))
  }
})

test_that("datom_repo_commit() of the user's own paths goes ahead and leaves the write's files alone", {
  fx <- local_interrupt_project()
  ru_unfinished_dm(fx)
  unfinished <- .datom_unfinished_files(fx$conn)
  bytes <- tools::md5sum(file.path(fx$repo, setdiff(unfinished, ".datom/manifest.json")))

  sha <- suppressMessages(datom_repo_commit(fx$conn, "Add build script", paths = "build.R"))

  expect_identical(sha, ru_head(fx$repo))
  expect_identical(ru_remote_tip(fx), sha)
  expect_false(is.null(.datom_git_head_file(fx$repo, "build.R")))
  # The write's files are still uncommitted and unchanged, for its own re-run.
  expect_identical(.datom_unfinished_files(fx$conn), unfinished)
  expect_identical(
    tools::md5sum(file.path(fx$repo, setdiff(unfinished, ".datom/manifest.json"))),
    bytes
  )
})

test_that("datom_repo_commit() of the user's own paths stops when a datom file is already staged", {
  # A commit takes the whole index, so a datom file staged with `git add` would
  # be committed alongside `build.R`.
  fx <- local_interrupt_project()
  ru_unfinished_dm(fx)
  git2r::add(git2r::repository(fx$repo), "dm/metadata.json")
  before <- ru_snapshot(fx)

  err <- expect_error(
    suppressMessages(datom_repo_commit(fx$conn, "Add build script", paths = "build.R")),
    class = "datom_unfinished_work"
  )

  expect_match(ru_msg(err), "'dm/metadata.json'", fixed = TRUE)
  expect_identical(ru_snapshot(fx), before)
})

test_that("datom_repo_commit(push = FALSE) during a merge in progress leaves the merge and every file alone", {
  fx <- local_interrupt_project()
  ru_write(fx$conn, "dm")
  writeLines("v1", file.path(fx$repo, "app.R"))
  git_commit_files(fx$repo, "app.R", "Add app.R")
  b <- local_second_clone(fx)
  writeLines("teammate", file.path(b$repo, "app.R"))
  git_commit_files(b$repo, "app.R", "Teammate's edit")
  writeLines("mine", file.path(fx$repo, "app.R"))
  git_commit_files(fx$repo, "app.R", "My edit", push = FALSE)
  expect_error(suppressMessages(datom_pull(fx$conn)), class = "datom_merge_conflict")
  writeLines("notes", file.path(fx$repo, "NOTES.md"))
  before <- ru_snapshot(fx)
  expect_true(before$clone$merging)

  err <- expect_error(
    suppressMessages(datom_repo_commit(fx$conn, "Mid-merge", push = FALSE)),
    class = "datom_merge_conflict"
  )

  expect_match(ru_msg(err), "A merge is in progress", fixed = TRUE)
  expect_identical(ru_snapshot(fx), before)
})


# === the push commands push, and say so (R3.6) ===================================

test_that("datom_repo_push() names the version it pushed, publishes nothing, and a write of another table stops", {
  fx <- local_interrupt_project()
  ru_write(fx$conn, "dm")
  ru_break(fx$conn, "push", "dm")
  storage_before <- snapshot_storage(fx)

  run <- ru_pushed_notes(datom_repo_push(fx$conn))

  expect_length(run$notes, 1L)
  expect_identical(run$notes[[1]]$pushed, "dm")
  expect_match(run$notes[[1]]$text, "new version of \"dm\" that readers cannot see yet",
               fixed = TRUE)
  expect_match(run$notes[[1]]$text, "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_identical(ru_remote_tip(fx), ru_head(fx$repo))
  expect_identical(snapshot_storage(fx), storage_before)
  expect_identical(ru_rows_read(fx, "dm"), 3L)

  # A write of any other table stops, naming dm, and changes nothing.
  before <- ru_snapshot(fx)
  err <- expect_error(ru_write(fx$conn, "lb"), class = "datom_unfinished_work")
  expect_match(ru_msg(err), "\"dm\"", fixed = TRUE)
  expect_identical(ru_snapshot(fx), before)
})

test_that("after datom_repo_push(), a write of that table publishes the pushed version", {
  fx <- local_interrupt_project()
  ru_write(fx$conn, "dm")
  ru_break(fx$conn, "push", "dm")
  suppressMessages(datom_repo_push(fx$conn))

  res <- ru_write(fx$conn, "dm", 5L, "b")

  expect_identical(res$action, "none")
  expect_identical(ru_rows_read(fx, "dm"), 5L)
  ru_write(fx$conn, "lb")
  expect_identical(ru_rows_read(fx, "lb"), 3L)
})

test_that("after datom_repo_push(), datom_validate(fix = TRUE) publishes the pushed version", {
  fx <- local_interrupt_project()
  ru_write(fx$conn, "dm")
  ru_break(fx$conn, "push", "dm")
  suppressMessages(datom_repo_push(fx$conn))

  suppressWarnings(suppressMessages(datom_validate(fx$conn, fix = TRUE)))

  expect_identical(ru_rows_read(fx, "dm"), 5L)
  expect_true(suppressMessages(datom_validate(fx$conn))$valid)
})

test_that("datom_repo_commit() names a datom version its push carries, and says nothing when there is none", {
  fx <- local_interrupt_project()
  ru_write(fx$conn, "dm")
  writeLines("one", file.path(fx$repo, "one.R"))
  quiet <- ru_pushed_notes(datom_repo_commit(fx$conn, "Add one.R", paths = "one.R"))
  expect_length(quiet$notes, 0L)

  ru_break(fx$conn, "push", "dm")
  writeLines("two", file.path(fx$repo, "two.R"))
  run <- ru_pushed_notes(datom_repo_commit(fx$conn, "Add two.R", paths = "two.R"))

  expect_length(run$notes, 1L)
  expect_identical(run$notes[[1]]$pushed, "dm")
  expect_identical(ru_remote_tip(fx), ru_head(fx$repo))
  expect_identical(ru_rows_read(fx, "dm"), 3L)
})

test_that("datom_repo_attach_governance() names a datom version its push carries, and the next push names nothing", {
  fx <- local_interrupt_project()
  ru_write(fx$conn, "dm")
  ru_break(fx$conn, "push", "dm")

  run <- ru_pushed_notes(datom_repo_attach_governance(
    fx$conn,
    gov_repo_url = "https://github.com/example/acme-gov",
    gov_store = datom_store_local(file.path(fx$root, "gov-storage"))
  ))
  expect_length(run$notes, 1L)
  expect_identical(run$notes[[1]]$pushed, "dm")
  expect_identical(ru_rows_read(fx, "dm"), 3L)

  # Pushed now, so the next push carries no datom version.
  quiet <- ru_pushed_notes(datom_repo_set_data_store(
    fx$conn, datom_store_local(file.path(fx$root, "storage"))
  ))
  expect_length(quiet$notes, 0L)
})

test_that("datom_repo_set_data_store() names a datom version its push carries", {
  fx <- local_interrupt_project()
  ru_write(fx$conn, "dm")
  ru_break(fx$conn, "push", "dm")

  run <- ru_pushed_notes(datom_repo_set_data_store(
    fx$conn, datom_store_local(file.path(fx$root, "storage-moved"))
  ))

  expect_length(run$notes, 1L)
  expect_identical(run$notes[[1]]$pushed, "dm")
  expect_identical(ru_remote_tip(fx), ru_head(fx$repo))
})


# === the break table's datom_repo_commit() row (R7.1) ============================

test_that("datom_repo_commit() broken at its push: the re-run commits nothing and pushes", {
  fx <- local_interrupt_project()
  writeLines("build <- function() NULL", file.path(fx$repo, "build.R"))
  local({
    local_break_at("push")
    expect_error(
      suppressMessages(datom_repo_commit(fx$conn, "Add build script", paths = "build.R")),
      class = "datom_test_break"
    )
  })
  committed <- ru_head(fx$repo)
  expect_false(identical(ru_remote_tip(fx), committed))

  res <- suppressMessages(datom_repo_commit(fx$conn, "Add build script", paths = "build.R"))

  expect_null(res)
  expect_identical(ru_head(fx$repo), committed)
  expect_identical(ru_remote_tip(fx), committed)
})


# === the two config commands commit too (R3.5, R3.9; task 8's checkpoint review) ==
#
# Each commits one named file before its push makes any pull, and a commit takes
# the whole index. So a datom file already staged would go into it, and a merge
# in progress would be finished by it (a probe on 2026-11-07: two parents,
# MERGE_HEAD gone). Both checks run before the command writes its file.

ru_attach_gov <- function(fx) {
  datom_repo_attach_governance(
    fx$conn,
    gov_repo_url = "https://github.com/example/acme-gov",
    gov_store = datom_store_local(file.path(fx$root, "gov-storage"))
  )
}

ru_set_store <- function(fx) {
  datom_repo_set_data_store(fx$conn, datom_store_local(file.path(fx$root, "storage-moved")))
}

ru_config_commands <- list(attach_governance = ru_attach_gov, set_data_store = ru_set_store)

# A merge of a local branch, started with --no-commit and left open: a merge
# datom did not start.
ru_open_other_merge <- function(fx) {
  repo <- git2r::repository(fx$repo)
  home <- git2r::repository_head(repo)$name
  git2r::checkout(repo, "feature", create = TRUE)
  writeLines("feature", file.path(fx$repo, "feature.R"))
  git_commit_files(fx$repo, "feature.R", "Feature work", push = FALSE)
  git2r::checkout(repo, home)
  writeLines("main", file.path(fx$repo, "main.R"))
  git_commit_files(fx$repo, "main.R", "Main work", push = FALSE)
  res <- git2r::merge(repo, "feature", commit_on_success = FALSE)
  force(res)
  expect_true(fs::file_exists(fs::path(repo$path, "MERGE_HEAD")))
}

for (cmd in names(ru_config_commands)) {
  test_that(paste0("datom_repo_", cmd, "() stops on a datom file already staged, changing nothing"), {
    fx <- local_interrupt_project()
    ru_unfinished_dm(fx)
    git2r::add(git2r::repository(fx$repo), "dm/metadata.json")
    before <- ru_snapshot(fx)

    err <- expect_error(
      suppressMessages(ru_config_commands[[cmd]](fx)),
      class = "datom_unfinished_work"
    )

    expect_match(ru_msg(err), "'dm/metadata.json'", fixed = TRUE)
    expect_identical(ru_snapshot(fx), before)
  })

  test_that(paste0("datom_repo_", cmd, "() goes ahead when datom's uncommitted files are not staged"), {
    fx <- local_interrupt_project()
    ru_unfinished_dm(fx)
    unfinished <- .datom_unfinished_files(fx$conn)

    sha <- suppressMessages(ru_config_commands[[cmd]](fx))

    expect_identical(ru_remote_tip(fx), sha)
    expect_identical(.datom_unfinished_files(fx$conn), unfinished)
  })

  test_that(paste0("datom_repo_", cmd, "() stops on a merge datom did not start, changing nothing"), {
    fx <- local_interrupt_project()
    ru_write(fx$conn, "dm")
    ru_open_other_merge(fx)
    before <- ru_snapshot(fx)

    expect_error(
      suppressMessages(ru_config_commands[[cmd]](fx)),
      class = "datom_merge_other"
    )

    expect_identical(ru_snapshot(fx), before)
  })
}
