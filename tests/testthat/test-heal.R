# The start of every write: the merge check, heal's reset and the pull (#155;
# design sections 1 and 4).
#
# Real projects throughout (folder git remote, local store; no AWS, no GitHub):
# the claims are about what a command leaves in the clone, the remote and
# storage, so nothing in the datom stack is mocked except the binding that
# raises a break, or a counter on a function a test must show is (not) called.
#
# "Nothing changed" is checked by comparing snapshots of the clone, the remote
# and storage taken before and after (helper-interrupt.R).


# --- fixtures -------------------------------------------------------------------

hl_df <- function(n = 3L, tag = "a") {
  data.frame(id = seq_len(n), val = rep(tag, n), stringsAsFactors = FALSE)
}

hl_write <- function(conn, name, n = 3L, tag = "a") {
  suppressMessages(datom_write(conn, data = hl_df(n, tag), name = name))
}

# Break a write of `name` at `step`; the break must be the error it stopped on.
hl_break <- function(conn, step, name, n = 5L, tag = "b") {
  local_break_at(step, name)
  expect_error(
    suppressMessages(datom_write(conn, data = hl_df(n, tag), name = name)),
    class = "datom_test_break"
  )
}

hl_snapshot <- function(fx, clone = fx$repo) {
  list(
    clone = snapshot_clone(clone),
    remote = snapshot_remote(fx),
    storage = snapshot_storage(fx)
  )
}

hl_msg <- function(err) gsub("\\s+", " ", cli::ansi_strip(conditionMessage(err)))

hl_stored_manifest <- function(fx) {
  .datom_storage_read_json(fx$conn, ".metadata/manifest.json")
}

hl_versions <- function(history) vapply(history, function(e) e$version, character(1))

hl_stored_history <- function(fx, name) {
  .datom_storage_read_json(fx$conn, .datom_artifact_meta_key(name, "version_history"))
}

hl_clone_history <- function(fx, name) {
  jsonlite::read_json(file.path(fx$repo, name, "version_history.json"))
}

hl_clean <- function(path) {
  st <- git2r::status(git2r::repository(path), staged = TRUE, unstaged = TRUE,
                      untracked = TRUE)
  length(unlist(st)) == 0L
}

# Run `expr`, keeping heal's reset notes (class `datom_heal_reset`) and
# muffling every other message.
hl_reset_notes <- function(expr) {
  notes <- character()
  value <- withCallingHandlers(expr, message = function(m) {
    if (inherits(m, "datom_heal_reset")) {
      notes <<- c(notes, cli::ansi_strip(conditionMessage(m)))
    }
    invokeRestart("muffleMessage")
  })
  list(value = value, notes = notes)
}

# A product project with a table `dm`, a member list for its set `adam`.
hl_product_project <- function(env = parent.frame()) {
  fx <- local_interrupt_project(mode = "product", set = "adam", env = env)
  hl_write(fx$conn, "dm")
  version <- datom_history(fx$conn, "dm", short_hash = FALSE)$version[[1L]]
  fx$members <- list(datom_member(fx$conn, "dm", version))
  fx
}

hl_write_set <- function(fx, description, ...) {
  suppressMessages(datom_write_set(
    fx$conn, fx$members, tags = list(description = description), ...
  ))
}

# Two clones whose writes of `dm` diverge: the teammate's clone (the project's
# own, `fx$conn`) publishes v2, while the second clone `b` has committed its
# own v3 and not pushed it.
hl_diverged <- function(env = parent.frame()) {
  fx <- local_interrupt_project(env = env)
  hl_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  local({
    local_break_at("push")
    expect_error(
      suppressMessages(datom_write(b$conn, data = hl_df(7L, "c"), name = "dm")),
      class = "datom_test_break"
    )
  })
  fx$v2 <- hl_write(fx$conn, "dm", 5L, "b")
  list(fx = fx, b = b)
}

# The same, after `b` re-ran its write: the pull merged and conflicted in `dm`'s
# files, and the merge is left in progress.
hl_conflicted_merge <- function(env = parent.frame()) {
  s <- hl_diverged(env = env)
  s$err <- expect_error(
    suppressMessages(datom_write(s$b$conn, data = hl_df(7L, "c"), name = "dm")),
    class = "datom_merge_conflict"
  )
  s
}

# A second clone `b` with the user's own files in the way of a teammate's
# commits: the teammate changes `app.R` and adds `new.R`; `b` has `app.R`
# modified or staged, or an untracked `new.R`, and with `own_commit` a commit of
# its own too.
hl_in_the_way <- function(case, own_commit = FALSE, env = parent.frame()) {
  fx <- local_interrupt_project(env = env)
  hl_write(fx$conn, "dm")
  writeLines("v1", file.path(fx$repo, "app.R"))
  git_commit_files(fx$repo, "app.R", "Add app.R")
  b <- local_second_clone(fx)

  writeLines("v2", file.path(fx$repo, "app.R"))
  writeLines("new", file.path(fx$repo, "new.R"))
  git_commit_files(fx$repo, c("app.R", "new.R"), "Teammate's edits")

  if (own_commit) {
    writeLines("mine", file.path(b$repo, "mine.R"))
    git_commit_files(b$repo, "mine.R", "Own work", push = FALSE)
  }
  switch(case,
    modified = writeLines("local edit", file.path(b$repo, "app.R")),
    staged = {
      writeLines("local edit", file.path(b$repo, "app.R"))
      git2r::add(git2r::repository(b$repo), "app.R")
    },
    untracked = writeLines("local", file.path(b$repo, "new.R"))
  )
  list(fx = fx, b = b)
}


# === a write never acts on another artifact (D14 principle 8, P13) ==============

test_that("another table's write broken before its commit stops a write of a different table, changing nothing (P13, R7.2)", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  hl_write(fx$conn, "lb")
  hl_break(fx$conn, "commit", "dm")
  before <- hl_snapshot(fx)

  err <- expect_error(hl_write(fx$conn, "lb", 7L), class = "datom_unfinished_work")

  msg <- hl_msg(err)
  expect_match(msg, "dm/metadata.json", fixed = TRUE)
  expect_match(msg, "dm/version_history.json", fixed = TRUE)
  expect_match(msg, "datom changed nothing")
  expect_match(msg, "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_identical(hl_snapshot(fx), before)
})

test_that("a set write with include_paths stops on another artifact's unfinished write, committing nothing (P8, P13)", {
  fx <- hl_product_project()
  hl_write(fx$conn, "lb")
  hl_break(fx$conn, "commit", "lb")
  fs::dir_create(file.path(fx$repo, "R"))
  writeLines("build <- function() NULL", file.path(fx$repo, "R", "build.R"))
  before <- hl_snapshot(fx)

  err <- expect_error(
    hl_write_set(fx, "v1", include_paths = "R/build.R"),
    class = "datom_unfinished_work"
  )

  expect_match(hl_msg(err), "lb/metadata.json", fixed = TRUE)
  expect_identical(hl_snapshot(fx), before)
})

test_that("a re-run of the broken write puts its files back, says so, and finishes (R2.4)", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  hl_break(fx$conn, "commit", "dm")

  run <- hl_reset_notes(datom_write(fx$conn, data = hl_df(5L, "b"), name = "dm"))

  expect_length(run$notes, 1L)
  expect_match(run$notes, "\"dm\"")
  expect_match(run$notes, "writing it again now")
  expect_identical(run$value$action, "full")
  expect_identical(nrow(as.data.frame(suppressMessages(datom_read(fx$reader, "dm")))), 5L)
  expect_true(hl_clean(fx$repo))
})

test_that("a table write never publishes what never committed (P4)", {
  # Before heal, a re-run with different data built its history on the broken
  # run's uncommitted one, and published a version no commit ever named.
  fx <- local_interrupt_project()
  v1 <- hl_write(fx$conn, "dm")
  hl_break(fx$conn, "commit", "dm", n = 5L)

  v3 <- suppressMessages(hl_write(fx$conn, "dm", 7L, "c"))

  expected <- c(v1$metadata_sha, v3$metadata_sha)
  expect_setequal(hl_versions(hl_stored_history(fx, "dm")), expected)
  expect_setequal(hl_versions(hl_clone_history(fx, "dm")), expected)
})

test_that("a set write never publishes what never committed (P4)", {
  fx <- hl_product_project()
  v1 <- hl_write_set(fx, "v1")
  local({
    local_break_at("commit", "adam")
    expect_error(hl_write_set(fx, "v2"), class = "datom_test_break")
  })

  v3 <- hl_write_set(fx, "v3")

  expected <- c(v1$metadata_sha, v3$metadata_sha)
  expect_setequal(hl_versions(hl_stored_history(fx, "adam")), expected)
  expect_setequal(hl_versions(hl_clone_history(fx, "adam")), expected)
})

test_that("files staged before a break are unstaged and put back, and a first write's are removed", {
  # A break between staging and committing: the case `local_break_at("commit")`
  # cannot make, since it replaces the commit before anything is staged.
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")

  stage_then_break <- function(path, files, message, ...) {
    git2r::add(git2r::repository(path), files)
    stop(datom_test_break("commit"))
  }

  # An artifact already committed: its edits are staged.
  local({
    local_mocked_bindings(.datom_git_commit = stage_then_break)
    expect_error(hl_write(fx$conn, "dm", 5L, "b"), class = "datom_test_break")
  })
  expect_false(hl_clean(fx$repo))
  expect_identical(hl_write(fx$conn, "dm", 5L, "b")$action, "full")
  expect_true(hl_clean(fx$repo))

  # An artifact's first write: its files are staged as new.
  local({
    local_mocked_bindings(.datom_git_commit = stage_then_break)
    expect_error(hl_write(fx$conn, "lb"), class = "datom_test_break")
  })
  run <- hl_reset_notes(datom_write(fx$conn, data = hl_df(), name = "lb"))
  expect_match(run$notes, "\"lb\"")
  expect_true(hl_clean(fx$repo))
  expect_identical(hl_stored_manifest(fx)$artifacts$lb$current_version,
                   run$value$metadata_sha)
})


test_that("the manifest is put back only when every row that differs from HEAD's is the write's own", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  hl_write(fx$conn, "lb")
  manifest_path <- file.path(fx$repo, ".datom", "manifest.json")
  edit_row <- function(name) {
    m <- jsonlite::read_json(manifest_path)
    m$artifacts[[name]]$size_bytes <- 1
    jsonlite::write_json(m, manifest_path, auto_unbox = TRUE, pretty = TRUE)
  }

  # Another table's row alone: that table's unfinished work.
  edit_row("lb")
  before <- hl_snapshot(fx)
  err <- expect_error(hl_write(fx$conn, "dm", 5L, "b"), class = "datom_unfinished_work")
  expect_match(hl_msg(err), "\"lb\": '.datom/manifest.json'", fixed = TRUE)
  expect_identical(hl_snapshot(fx), before)

  # The write's own row: put back, and the write goes ahead.
  git2r::checkout(git2r::repository(fx$repo), path = ".datom/manifest.json", force = TRUE)
  edit_row("dm")
  run <- hl_reset_notes(datom_write(fx$conn, data = hl_df(5L, "b"), name = "dm"))
  expect_match(run$notes, "\"dm\"")
  expect_identical(run$value$action, "full")
  expect_true(hl_clean(fx$repo))
})


# === the metadata-only route (D13) ==============================================

test_that("datom_write(conn, name =) stops on the table's own unfinished write, publishing nothing", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  hl_break(fx$conn, "commit", "dm")
  before <- hl_snapshot(fx)

  err <- expect_error(
    suppressMessages(datom_write(fx$conn, name = "dm")),
    class = "datom_unfinished_work"
  )

  expect_match(hl_msg(err), "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_identical(hl_snapshot(fx), before)
})

test_that("datom_write(conn, name =) stops on a hand edit of the table's metadata.json, publishing nothing (D13)", {
  # datom's own files are not hand-edited; an uncommitted change to one is an
  # unfinished write, and this route never rewrites the table's files.
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  meta_path <- file.path(fx$repo, "dm", "metadata.json")
  meta <- jsonlite::read_json(meta_path, simplifyVector = TRUE)
  meta$custom <- list(note = "hand-edited")
  jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)
  before <- hl_snapshot(fx)

  err <- expect_error(
    suppressMessages(datom_write(fx$conn, name = "dm")),
    class = "datom_unfinished_work"
  )

  msg <- hl_msg(err)
  expect_match(msg, "dm/metadata.json", fixed = TRUE)
  expect_match(msg, "datom_validate(fix = TRUE)", fixed = TRUE)
  expect_identical(hl_snapshot(fx), before)
})


# === which folders are artifacts (P8) ===========================================

test_that("a user's own app/metadata.json, tracked or not, is not an artifact (P8)", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  fs::dir_create(file.path(fx$repo, c("app", "app2")))
  writeLines('{"name": "my app", "settings": {"x": 1}}',
             file.path(fx$repo, "app", "metadata.json"))
  git_commit_files(fx$repo, "app/metadata.json", "Add the app's config")
  writeLines('{"name": "my app", "settings": {"x": 2}}',
             file.path(fx$repo, "app", "metadata.json"))
  writeLines('{"y": 1}', file.path(fx$repo, "app2", "metadata.json"))
  user_files <- file.path(fx$repo, c("app", "app2"), "metadata.json")
  bytes <- tools::md5sum(user_files)

  # Heal leaves both alone, and the write goes ahead.
  expect_identical(hl_write(fx$conn, "dm", 5L, "b")$action, "full")
  expect_identical(tools::md5sum(user_files), bytes)

  # The format check does not read them (their fields are not datom's).
  expect_no_error(.datom_check_write_entry(fx$conn, NULL))

  # The repair does not publish them.
  suppressMessages(.datom_sync_data_metadata(fx$conn, .confirm = FALSE))
  expect_false(any(grepl("(^|/)app2?/", names(snapshot_storage(fx)))))
  expect_identical(tools::md5sum(user_files), bytes)
})

test_that("an artifact's first write broken before its manifest row is still an artifact (the hash_algo rule)", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  hl_break(fx$conn, "clone_files", "lb")
  expect_true(fs::file_exists(file.path(fx$repo, "lb", "metadata.json")))
  expect_null(jsonlite::read_json(file.path(fx$repo, ".datom", "manifest.json"))$artifacts$lb)

  # Another write stops on it ...
  err <- expect_error(hl_write(fx$conn, "dm", 5L, "b"), class = "datom_unfinished_work")
  expect_match(hl_msg(err), "lb/metadata.json", fixed = TRUE)

  # ... and its own re-run puts it back and finishes.
  run <- hl_reset_notes(datom_write(fx$conn, data = hl_df(5L, "b"), name = "lb"))
  expect_match(run$notes, "\"lb\"")
  expect_true(hl_clean(fx$repo))
  expect_identical(hl_stored_manifest(fx)$artifacts$lb$current_version,
                   run$value$metadata_sha)
})


# === the pull (R3.7) =============================================================

test_that("a failed fetch stops a write before anything changes (P9)", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  remote <- file.path(fx$root, "remote.git")
  away <- paste0(remote, ".away")
  fs::file_move(remote, away)
  before <- list(clone = snapshot_clone(fx$repo), storage = snapshot_storage(fx))

  err <- expect_error(hl_write(fx$conn, "dm", 5L, "b"), class = "datom_fetch_failed")

  expect_match(hl_msg(err), "datom changed nothing")
  expect_identical(
    list(clone = snapshot_clone(fx$repo), storage = snapshot_storage(fx)),
    before
  )
  fs::file_move(away, remote)
})

test_that("a clone behind the remote pulls first, so its write leaves the newer version in storage (P5)", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  v2 <- hl_write(fx$conn, "dm", 5L, "b")

  lb <- hl_write(b$conn, "lb")

  stored <- hl_stored_manifest(fx)
  expect_identical(stored$artifacts$dm$current_version, v2$metadata_sha)
  expect_identical(stored$artifacts$lb$current_version, lb$metadata_sha)
  expect_identical(nrow(as.data.frame(suppressMessages(datom_read(fx$reader, "dm")))), 5L)
})

test_that("a pull conflicting outside the manifest stops the write, publishing nothing (P5, R7.6)", {
  s <- hl_diverged()
  before <- snapshot_storage(s$fx)

  err <- expect_error(
    suppressMessages(datom_write(s$b$conn, data = hl_df(7L, "c"), name = "dm")),
    class = "datom_merge_conflict"
  )

  msg <- hl_msg(err)
  expect_match(msg, "dm/metadata.json", fixed = TRUE)
  expect_match(msg, "git checkout MERGE_HEAD -- dm/metadata.json dm/version_history.json",
               fixed = TRUE)
  expect_match(msg, "No version is published")
  expect_identical(snapshot_storage(s$fx), before)
  expect_identical(hl_stored_manifest(s$fx)$artifacts$dm$current_version,
                   s$fx$v2$metadata_sha)
  expect_true(fs::file_exists(file.path(s$b$repo, ".git", "MERGE_HEAD")))
})

test_that("the user's own files in the way of a pull stop a write and datom_pull(), changing nothing (P14, R3.7)", {
  # git2r's merge silently does nothing in these states; the pull confirms it
  # caught up, by commit.
  for (case in c("modified", "staged", "untracked")) {
    for (own_commit in c(FALSE, TRUE)) {
      s <- hl_in_the_way(case, own_commit)
      before <- hl_snapshot(s$fx, s$b$repo)
      label <- paste(case, if (own_commit) "with a commit of its own" else "")

      err <- expect_error(hl_write(s$b$conn, "lb"), class = "datom_pull_blocked",
                          label = label)
      expect_match(hl_msg(err), "git stash -u", fixed = TRUE, label = label)
      expect_identical(hl_snapshot(s$fx, s$b$repo), before, label = label)

      expect_error(suppressMessages(datom_pull(s$b$conn)),
                   class = "datom_pull_blocked", label = label)
      expect_identical(hl_snapshot(s$fx, s$b$repo), before, label = label)
    }
  }
})

test_that("following the stash recipe, the write then finishes (P14)", {
  s <- hl_in_the_way("modified")
  repo <- git2r::repository(s$b$repo)
  expect_error(hl_write(s$b$conn, "lb"), class = "datom_pull_blocked")

  # git stash -u; datom_pull(conn); git stash pop
  git2r::stash(repo, message = "aside", untracked = TRUE,
               stasher = .datom_git_signature(repo))
  suppressMessages(datom_pull(s$b$conn))
  git2r::stash_pop(repo)

  # ... resolve what `git stash pop` reports: a conflict in app.R. Keep a merged
  # copy and clear the conflict from the index.
  conflicted <- unlist(git2r::status(repo)$unstaged)
  expect_true("app.R" %in% conflicted[names(conflicted) == "conflicted"])
  writeLines(c("v2", "local edit"), file.path(s$b$repo, "app.R"))
  git2r::reset(repo, path = "app.R")

  lb <- hl_write(s$b$conn, "lb")
  expect_identical(lb$action, "full")
  expect_identical(hl_stored_manifest(s$fx)$artifacts$lb$current_version,
                   lb$metadata_sha)
})

test_that("with no upstream branch, a clone behind the remote has its push refused, naming datom_pull()", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  git2r::branch_set_upstream(git2r::repository_head(git2r::repository(b$repo)), NULL)
  hl_write(fx$conn, "lb")
  stored_before <- hl_stored_manifest(fx)

  err <- expect_error(hl_write(b$conn, "ae"), class = "datom_push_rejected")

  msg <- hl_msg(err)
  expect_match(msg, "datom_pull(conn)", fixed = TRUE)
  expect_match(msg, "git branch --set-upstream-to=origin/", fixed = TRUE)
  expect_match(msg, "Nothing was pushed or published")
  expect_match(msg, "data file may already be in storage")
  expect_identical(hl_stored_manifest(fx), stored_before)
  expect_false(.datom_storage_exists(fx$conn, .datom_artifact_meta_key("ae", "metadata")))
})

test_that("datom_pull() and datom_repo_push() on a new local-only branch neither stop nor change anything, and the push sets an upstream", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  repo <- git2r::repository(fx$repo)
  git2r::checkout(repo, branch = "feature", create = TRUE)
  before <- snapshot_clone(fx$repo)

  expect_no_error(suppressMessages(datom_pull(fx$conn)))
  expect_identical(snapshot_clone(fx$repo), before)

  writeLines("notes", file.path(fx$repo, "NOTES.md"))
  git_commit_files(fx$repo, "NOTES.md", "Notes", push = FALSE)
  expect_no_error(suppressMessages(datom_repo_push(fx$conn)))

  upstream <- git2r::branch_get_upstream(git2r::repository_head(repo))
  expect_false(is.null(upstream))
  expect_match(upstream$name, "feature$")
  expect_true("feature" %in% names(snapshot_remote(fx)))
})


# === after a merge: the format check, the floor (R3.7) ===========================

hl_newer_format_lb <- function(fx) {
  meta_path <- file.path(fx$repo, "lb", "metadata.json")
  meta <- jsonlite::read_json(meta_path)
  meta$future_field <- "from a newer datom"
  jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)
  git_commit_files(fx$repo, "lb/metadata.json", "lb, written by a newer datom")
}

test_that("a fast-forward pull bringing a newer-format document stops the write before its own work", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  hl_write(fx$conn, "lb")
  b <- local_second_clone(fx)
  hl_newer_format_lb(fx)
  storage_before <- snapshot_storage(fx)

  err <- expect_error(hl_write(b$conn, "dm", 5L, "b"), class = "datom_vocabulary_unknown")

  expect_match(hl_msg(err), "future_field")
  expect_identical(snapshot_storage(fx), storage_before)
})

test_that("a pull that merges in a newer-format document stops the write before its own work", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  hl_write(fx$conn, "lb")
  b <- local_second_clone(fx)
  writeLines("mine", file.path(b$repo, "mine.R"))
  git_commit_files(b$repo, "mine.R", "Own work", push = FALSE)
  hl_newer_format_lb(fx)
  storage_before <- snapshot_storage(fx)

  err <- expect_error(hl_write(b$conn, "dm", 5L, "b"), class = "datom_vocabulary_unknown")

  expect_match(hl_msg(err), "future_field")
  expect_identical(snapshot_storage(fx), storage_before)
})

test_that("a writer floor raised in a commit the pull brings in stops the write", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  write_writer_floor(fx$repo, "999.0.0")
  git_commit_files(fx$repo, ".datom/project.yaml", "Raise the writer floor")
  storage_before <- snapshot_storage(fx)

  expect_error(hl_write(b$conn, "dm", 5L, "b"), class = "datom_writer_floor")
  expect_identical(snapshot_storage(fx), storage_before)
})

test_that("a project.yaml that does not parse stops the write", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  writeLines("project_name: [unclosed", file.path(fx$repo, ".datom", "project.yaml"))
  storage_before <- snapshot_storage(fx)

  expect_error(hl_write(fx$conn, "dm", 5L, "b"), class = "datom_project_config_unreadable")
  expect_identical(snapshot_storage(fx), storage_before)
})


# === where heal runs ===============================================================

local_heal_counter <- function(env = parent.frame()) {
  calls <- 0L
  real <- get(".datom_heal", envir = asNamespace("datom"))
  local_mocked_bindings(
    .datom_heal = function(...) {
      calls <<- calls + 1L
      real(...)
    },
    .env = env
  )
  function() calls
}

test_that("a mistyped argument is refused before heal runs", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  hl_write(fx$conn, "lb")
  hl_break(fx$conn, "commit", "lb")
  calls <- local_heal_counter()

  # The argument's own refusal, not heal's stop on `lb`.
  expect_error(datom_write(fx$conn, data = "not a frame", name = "dm"),
               "must be a data frame")
  expect_identical(calls(), 0L)
})

test_that("heal runs exactly once on each route it is wired into", {
  fx <- hl_product_project()
  calls <- local_heal_counter()

  hl_write(fx$conn, "dm", 5L, "b")
  expect_identical(calls(), 1L)

  suppressMessages(datom_write(fx$conn, name = "dm"))
  expect_identical(calls(), 2L)

  hl_write_set(fx, "v1")
  expect_identical(calls(), 3L)
})

test_that("on a clean, current, published clone, nothing before a write's own work writes anything or merges (P12)", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")

  calls <- c(merge = 0L, reset = 0L, storage = 0L)
  count <- function(what) function(...) {
    calls[[what]] <<- calls[[what]] + 1L
    stop("not on the common path: ", what)
  }
  local_mocked_bindings(
    .datom_git_merge_upstream = count("merge"),
    .datom_reset_unfinished = count("reset"),
    .datom_storage_write_json = count("storage"),
    .datom_storage_upload_absent = count("storage"),
    .datom_storage_upload = count("storage")
  )
  before <- hl_snapshot(fx)

  .datom_check_merge(fx$repo)
  .datom_heal(fx$conn, artifact = "dm")
  moved <- .datom_pull_before_write(fx$conn)

  expect_false(moved)
  expect_identical(calls, c(merge = 0L, reset = 0L, storage = 0L))
  expect_identical(hl_snapshot(fx), before)
})


# === a merge in progress (R3.9) ===================================================

test_that("a merge of the remote branch with datom's files in conflict stops a write, datom_pull() and datom_repo_push(), changing nothing", {
  s <- hl_conflicted_merge()
  before <- hl_snapshot(s$fx, s$b$repo)

  commands <- list(
    write = function() hl_write(s$b$conn, "lb"),
    pull = function() suppressMessages(datom_pull(s$b$conn)),
    push = function() suppressMessages(datom_repo_push(s$b$conn))
  )
  for (nm in names(commands)) {
    err <- expect_error(commands[[nm]](), class = "datom_merge_conflict", label = nm)
    msg <- hl_msg(err)
    expect_match(msg, "dm/metadata.json", fixed = TRUE, label = nm)
    expect_match(msg, "git checkout MERGE_HEAD -- dm/metadata.json dm/version_history.json",
                 fixed = TRUE, label = nm)
    expect_match(msg, "re-run your write", label = nm)
    expect_identical(hl_snapshot(s$fx, s$b$repo), before, label = nm)
  }
  expect_true(fs::file_exists(file.path(s$b$repo, ".git", "MERGE_HEAD")))
})

test_that("datom's own conflicted merge is still a merge of the remote branch after a later fetch", {
  s <- hl_conflicted_merge()
  hl_write(s$fx$conn, "lb")
  git2r::fetch(git2r::repository(s$b$repo), "origin")

  expect_error(hl_write(s$b$conn, "ae"), class = "datom_merge_conflict")
})

test_that("a user's own conflicted git pull is a merge of the remote branch", {
  skip_if(!nzchar(Sys.which("git")), "needs the git command line")
  s <- hl_diverged()
  suppressWarnings(system2(
    "git", c("-C", s$b$repo, "-c", "user.name=t", "-c", "user.email=t@t",
             "pull", "--no-rebase", "-q"),
    stdout = FALSE, stderr = FALSE
  ))
  expect_true(fs::file_exists(file.path(s$b$repo, ".git", "MERGE_HEAD")))

  expect_error(hl_write(s$b$conn, "lb"), class = "datom_merge_conflict")
})

hl_feature_branch <- function(fx) {
  repo <- git2r::repository(fx$repo)
  main <- git2r::repository_head(repo)$name
  git2r::checkout(repo, branch = "feature", create = TRUE)
  writeLines("feature", file.path(fx$repo, "feature.R"))
  git_commit_files(fx$repo, "feature.R", "Feature work", push = FALSE)
  git2r::checkout(repo, branch = main)
  writeLines("main", file.path(fx$repo, "main.R"))
  git_commit_files(fx$repo, "main.R", "Main work", push = FALSE)
  repo
}

test_that("a user's merge of a local branch, nothing conflicted, stops a write and datom_pull() with the other-merge message", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  repo <- hl_feature_branch(fx)
  git2r::merge(repo, "feature", commit_on_success = FALSE,
               merger = .datom_git_signature(repo))
  expect_true(fs::file_exists(file.path(fx$repo, ".git", "MERGE_HEAD")))
  before <- hl_snapshot(fx)

  err <- expect_error(hl_write(fx$conn, "dm", 5L, "b"), class = "datom_merge_other")
  msg <- hl_msg(err)
  expect_match(msg, "Merge branch 'feature'", fixed = TRUE)
  expect_match(msg, "datom_pull(conn, finish_merge = TRUE)", fixed = TRUE)
  expect_match(msg, "git merge --abort", fixed = TRUE)
  expect_identical(hl_snapshot(fx), before)

  expect_error(suppressMessages(datom_pull(fx$conn)), class = "datom_merge_other")
  expect_identical(hl_snapshot(fx), before)
})

test_that("a merge of another remote's branch stops a write and datom_pull() with the other-merge message", {
  fx <- local_interrupt_project()
  hl_write(fx$conn, "dm")
  repo <- hl_feature_branch(fx)
  other <- file.path(fx$root, "other.git")
  fs::dir_create(other)
  git2r::init(other, bare = TRUE)
  git2r::remote_add(repo, "other", other)
  git2r::push(repo, "other", "refs/heads/feature")
  git2r::fetch(repo, "other")
  git2r::merge(repo, "other/feature", commit_on_success = FALSE,
               merger = .datom_git_signature(repo))
  expect_true(fs::file_exists(file.path(fx$repo, ".git", "MERGE_HEAD")))
  before <- hl_snapshot(fx)

  expect_error(hl_write(fx$conn, "dm", 5L, "b"), class = "datom_merge_other")
  expect_error(suppressMessages(datom_pull(fx$conn)), class = "datom_merge_other")
  expect_identical(hl_snapshot(fx), before)
})
