# A conflict only in the manifest (#155; requirements R3.8, R3.9; design
# section 5): datom rebuilds `.datom/manifest.json` from the artifacts' files
# and finishes the merge, at the pull or from the merge check.
#
# Real projects throughout (folder git remote, local store; no AWS, no GitHub),
# as in test-heal.R. Two clones conflict in the manifest when both write without
# a pull in between. Every write now pulls first, so that happens only when the
# other clone's push lands after this write's opening pull and before its own
# push; `local_teammate_after_commit()` makes it happen inside the write.


# --- fixtures -------------------------------------------------------------------

mc_df <- function(n = 3L, tag = "a") {
  data.frame(id = seq_len(n), val = rep(tag, n), stringsAsFactors = FALSE)
}

mc_write <- function(conn, name, n = 3L, tag = "a", ...) {
  suppressMessages(datom_write(conn, data = mc_df(n, tag), name = name, ...))
}

# Break a write of `name` at `step`; the break must be the error it stopped on.
mc_break <- function(conn, step, name, n = 5L, tag = "b", ...) {
  local_break_at(step, name)
  expect_error(
    suppressMessages(datom_write(conn, data = mc_df(n, tag), name = name, ...)),
    class = "datom_test_break"
  )
}

mc_msg <- function(err) gsub("\\s+", " ", cli::ansi_strip(conditionMessage(err)))

mc_manifest <- function(repo) {
  jsonlite::read_json(file.path(repo, ".datom", "manifest.json"))
}

mc_stored_manifest <- function(fx) {
  .datom_storage_read_json(fx$conn, ".metadata/manifest.json")
}

mc_versions <- function(manifest) {
  vapply(manifest$artifacts, function(row) row$current_version, character(1))
}

# The version a clone's own files record for an artifact: its history's entry
# for the current metadata (each fixture's history is unambiguous).
mc_file_version <- function(repo, name) {
  meta <- jsonlite::read_json(file.path(repo, name, "metadata.json"))
  history <- jsonlite::read_json(file.path(repo, name, "version_history.json"))
  .datom_recorded_current_version(meta, history)
}

mc_rows_read <- function(fx, name) {
  nrow(as.data.frame(suppressMessages(datom_read(fx$reader, name))))
}

mc_merging <- function(repo) fs::file_exists(file.path(repo, ".git", "MERGE_HEAD"))

mc_head_parents <- function(repo) {
  length(git2r::parents(git2r::last_commit(git2r::repository(repo))))
}

mc_head <- function(repo) git2r::sha(git2r::last_commit(git2r::repository(repo)))

mc_snapshot <- function(fx, clone) {
  list(
    clone = snapshot_clone(clone),
    remote = snapshot_remote(fx),
    storage = snapshot_storage(fx)
  )
}

# Run `expr`, keeping the merge-finished notes (class `datom_merge_finished`)
# and muffling every other message.
mc_finished_notes <- function(expr) {
  notes <- character()
  value <- withCallingHandlers(expr, message = function(m) {
    if (inherits(m, "datom_merge_finished")) {
      notes <<- c(notes, gsub("\\s+", " ", cli::ansi_strip(conditionMessage(m))))
    }
    invokeRestart("muffleMessage")
  })
  list(value = value, notes = notes)
}

# Once, right after the next commit datom makes, run `teammate()`: how a test
# lands another clone's push after this write's opening pull and before its own
# push. Mocked bindings apply to every call, the teammate's own commits
# included, hence the once-only flag.
local_teammate_after_commit <- function(teammate, env = parent.frame()) {
  real_commit <- get(".datom_git_commit", envir = asNamespace("datom"))
  fired <- FALSE
  local_mocked_bindings(
    .datom_git_commit = function(...) {
      sha <- real_commit(...)
      if (!fired) {
        fired <<- TRUE
        teammate()
      }
      sha
    },
    .env = env
  )
}

# A clone `b` whose write of `name` committed and broke at its push, while the
# project's own clone (the teammate) went on to write `ae`, so the remote holds
# a commit `b` lacks. `b`'s next pull merges, and both sides changed the
# manifest.
mc_diverged_on_manifest <- function(name = "dm", env = parent.frame()) {
  fx <- local_interrupt_project(env = env)
  fx$dm <- mc_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  mc_break(b$conn, "push", name)
  fx$ae <- mc_write(fx$conn, "ae")
  list(fx = fx, b = b)
}


# === resolved at the pull (R3.8, R7.7, P6) ========================================

test_that("two clones writing different tables without a pull in between both finish, and the manifest names both", {
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  ae <- NULL
  local_teammate_after_commit(function() ae <<- mc_write(fx$conn, "ae"))

  run <- mc_finished_notes(datom_write(b$conn, data = mc_df(), name = "lb"))

  expect_false(is.null(ae))
  expect_identical(run$value$action, "full")
  expect_length(run$notes, 1L)
  expect_match(run$notes, "rebuilt the '.datom/manifest.json' row of \"lb\"", fixed = TRUE)

  # The merge is finished and shared.
  expect_false(mc_merging(b$repo))
  expect_identical(mc_head_parents(b$repo), 2L)
  expect_identical(snapshot_remote(fx)[[1L]], mc_head(b$repo))

  # Every row names what its files record; the teammate's row is the
  # teammate's, untouched.
  clone <- mc_manifest(b$repo)
  expect_setequal(names(clone$artifacts), c("dm", "ae", "lb"))
  expect_identical(clone$artifacts$lb$current_version, run$value$metadata_sha)
  expect_identical(clone$artifacts$ae, mc_manifest(fx$repo)$artifacts$ae)
  expect_identical(clone$summary$total_tables, 3L)

  # The stored manifest matches the clone's, and readers see both tables.
  expect_identical(mc_versions(mc_stored_manifest(fx))[names(clone$artifacts)],
                   mc_versions(clone))
  expect_identical(mc_rows_read(fx, "lb"), 3L)
  expect_identical(mc_rows_read(fx, "ae"), 3L)
})

test_that("a write whose push broke while the other clone pushed finishes on a re-run, with the manifest naming both", {
  s <- mc_diverged_on_manifest("dm")
  v_local <- mc_file_version(s$b$repo, "dm")

  run <- mc_finished_notes(datom_write(s$b$conn, data = mc_df(5L, "b"), name = "dm"))

  # The merge rebuilt the remote's stale row of dm from this clone's files, and
  # heal's publish then finished the version the broken run committed.
  expect_match(run$notes, "row of \"dm\"", fixed = TRUE)
  expect_identical(run$value$action, "none")
  expect_false(mc_merging(s$b$repo))
  expect_identical(mc_head_parents(s$b$repo), 2L)

  clone <- mc_manifest(s$b$repo)
  expect_identical(clone$artifacts$dm$current_version, v_local)
  expect_identical(clone$artifacts$ae$current_version, s$fx$ae$metadata_sha)

  stored <- mc_stored_manifest(s$fx)
  expect_identical(mc_versions(stored)[names(clone$artifacts)], mc_versions(clone))
  expect_identical(mc_rows_read(s$fx, "dm"), 5L)
  expect_identical(mc_rows_read(s$fx, "ae"), 3L)
})

test_that("datom_pull() resolves a manifest-only conflict and says so", {
  s <- mc_diverged_on_manifest("lb")

  run <- mc_finished_notes(datom_pull(s$b$conn))

  expect_length(run$notes, 1L)
  expect_match(run$notes, "row of \"lb\"", fixed = TRUE)
  expect_false(mc_merging(s$b$repo))
  expect_identical(mc_head_parents(s$b$repo), 2L)
  clone <- mc_manifest(s$b$repo)
  expect_setequal(names(clone$artifacts), c("dm", "ae", "lb"))
  expect_identical(clone$artifacts$lb$current_version, mc_file_version(s$b$repo, "lb"))
  expect_identical(clone$artifacts$ae$current_version, s$fx$ae$metadata_sha)
})

test_that("a teammate's set of custom metadata back to earlier values keeps the version its write recorded", {
  # The teammate's ae goes v1 -> v2 -> v1 by custom metadata alone. The revert
  # appends no history entry and stamps a fresh created_at, so the history on
  # its own would name v2.
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  mc_break(b$conn, "push", "dm")
  v1 <- mc_write(fx$conn, "ae", metadata = list(note = "x"))
  mc_write(fx$conn, "ae", metadata = list(note = "y"))
  v3 <- mc_write(fx$conn, "ae", metadata = list(note = "x"))
  expect_identical(v3$metadata_sha, v1$metadata_sha)

  suppressMessages(datom_pull(b$conn))

  expect_identical(mc_manifest(b$repo)$artifacts$ae$current_version, v1$metadata_sha)
})

test_that("two clones writing the same table still stop at the push, publishing nothing", {
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  v2 <- NULL
  local_teammate_after_commit(function() v2 <<- mc_write(fx$conn, "dm", 5L, "b"))

  err <- expect_error(
    suppressMessages(datom_write(b$conn, data = mc_df(7L, "c"), name = "dm")),
    class = "datom_merge_conflict"
  )

  msg <- mc_msg(err)
  expect_match(msg, "dm/version_history.json", fixed = TRUE)
  expect_match(msg, "No version is published")
  expect_match(msg, "data file may already be in storage")
  expect_true(mc_merging(b$repo))
  expect_identical(mc_versions(mc_stored_manifest(fx))[["dm"]], v2$metadata_sha)
  expect_identical(mc_rows_read(fx, "dm"), 5L)
})

test_that("the teammate's publish broken after its push: the merged write holds back the manifest and publishes its own documents", {
  # The end-to-end case of the manifest upload's agreement check: once the
  # merge is rebuilt, this clone's manifest names the teammate's version of ae,
  # whose documents are not in storage.
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  local_teammate_after_commit(function() {
    local({
      local_break_at("metadata")
      expect_error(mc_write(fx$conn, "ae"), class = "datom_test_break")
    })
  })
  stored_before <- mc_stored_manifest(fx)

  expect_warning(
    lb <- suppressMessages(datom_write(b$conn, data = mc_df(5L, "b"), name = "lb")),
    class = "datom_manifest_held_back"
  )

  expect_identical(mc_head_parents(b$repo), 2L)
  expect_setequal(names(mc_manifest(b$repo)$artifacts), c("dm", "ae", "lb"))
  expect_identical(mc_stored_manifest(fx), stored_before)
  expect_identical(mc_rows_read(fx, "lb"), 5L)
})


# === finished by the merge check, after the user resolved the rest (R3.9) =====

test_that("after taking the remote copy of a conflicted artifact as the message says, a re-run finishes the merge with every row agreeing with its files", {
  skip_if(!nzchar(Sys.which("git")), "needs the git command line")
  # This clone has unpushed writes of dm and lb, and a teammate has published dm
  # v2. Taking the remote's whole manifest by hand would leave lb's row out. A
  # write stops on another artifact's unfinished work, so the second write here
  # skips heal (`.healed = TRUE`, the argument that lets a sync heal once for a
  # batch of tables); a sync whose pushes all fail leaves this state.
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  local({
    local_break_at("push")
    expect_error(suppressMessages(datom_write(b$conn, data = mc_df(7L, "c"), name = "dm")),
                 class = "datom_test_break")
    expect_error(suppressMessages(datom_write(b$conn, data = mc_df(4L, "l"), name = "lb",
                                              .healed = TRUE)),
                 class = "datom_test_break")
  })
  v2 <- mc_write(fx$conn, "dm", 5L, "b")

  err <- expect_error(mc_write(b$conn, "lb", 4L, "l"), class = "datom_merge_conflict")
  checkout <- regmatches(mc_msg(err), regexpr("git checkout MERGE_HEAD -- [^`]+", mc_msg(err)))
  expect_identical(checkout,
                   "git checkout MERGE_HEAD -- dm/metadata.json dm/version_history.json")
  args <- strsplit(trimws(checkout), " ")[[1L]][-1L]
  expect_identical(system2("git", c("-C", b$repo, args), stdout = FALSE, stderr = FALSE), 0L)

  run <- mc_finished_notes(datom_write(b$conn, data = mc_df(4L, "l"), name = "lb"))

  expect_length(run$notes, 1L)
  expect_false(mc_merging(b$repo))
  expect_identical(mc_head_parents(b$repo), 2L)
  clone <- mc_manifest(b$repo)
  expect_identical(clone$artifacts$dm$current_version, v2$metadata_sha)
  expect_identical(clone$artifacts$lb$current_version, mc_file_version(b$repo, "lb"))
  expect_identical(mc_versions(mc_stored_manifest(fx))[names(clone$artifacts)],
                   mc_versions(clone))
  expect_identical(mc_rows_read(fx, "dm"), 5L)
  expect_identical(mc_rows_read(fx, "lb"), 4L)
})

test_that("a user's own file, resolved and added, goes into the merge datom finishes", {
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  writeLines("v1", file.path(fx$repo, "app.R"))
  git_commit_files(fx$repo, "app.R", "Add app.R")
  b <- local_second_clone(fx)
  writeLines("mine", file.path(b$repo, "app.R"))
  git_commit_files(b$repo, "app.R", "My app.R", push = FALSE)
  mc_break(b$conn, "push", "lb")
  writeLines("theirs", file.path(fx$repo, "app.R"))
  git_commit_files(fx$repo, "app.R", "Their app.R")
  mc_write(fx$conn, "ae")

  err <- expect_error(mc_write(b$conn, "lb", 5L, "b"), class = "datom_merge_conflict")
  expect_match(mc_msg(err), "app.R")
  expect_no_match(mc_msg(err), "git checkout MERGE_HEAD", fixed = TRUE)

  writeLines("resolved", file.path(b$repo, "app.R"))
  git2r::add(git2r::repository(b$repo), "app.R")
  mc_write(b$conn, "lb", 5L, "b")

  expect_false(mc_merging(b$repo))
  expect_identical(.datom_git_head_file(b$repo, "app.R"), "resolved\n")
  expect_identical(snapshot_remote(fx)[[1L]], mc_head(b$repo))
})


# === the format check before the rebuild (R3.8, P6) ================================

# The teammate writes ae, then commits a manifest carrying a top-level field
# this build cannot place, as a newer datom would leave it.
mc_newer_manifest <- function(fx) {
  mc_write(fx$conn, "ae")
  path <- file.path(fx$repo, ".datom", "manifest.json")
  m <- jsonlite::read_json(path)
  m$future_field <- "from a newer datom"
  jsonlite::write_json(m, path, auto_unbox = TRUE, pretty = TRUE)
  git_commit_files(fx$repo, ".datom/manifest.json", "Manifest from a newer datom")
}

test_that("a merge bringing a manifest field this build cannot place stops before the rebuild, at the pull and from the merge check", {
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  mc_break(b$conn, "push", "lb")
  mc_newer_manifest(fx)
  head_before <- mc_head(b$repo)
  storage_before <- snapshot_storage(fx)
  installed <- as.character(utils::packageVersion("datom"))

  check <- function(err, label) {
    msg <- mc_msg(err)
    expect_match(msg, ".datom/manifest.json", fixed = TRUE, label = label)
    expect_match(msg, "future_field", fixed = TRUE, label = label)
    expect_match(msg, paste0("Installed datom is ", installed), fixed = TRUE, label = label)
    expect_match(msg, "git merge --abort", fixed = TRUE, label = label)
    expect_true(mc_merging(b$repo), label = label)
    expect_identical(mc_head(b$repo), head_before, label = label)
    expect_identical(snapshot_storage(fx), storage_before, label = label)
  }

  # At the pull a write makes.
  err <- expect_error(mc_write(b$conn, "lb", 5L, "b"), class = "datom_vocabulary_unknown")
  check(err, "the pull")

  # From the merge check, on the next command.
  err <- expect_error(suppressMessages(datom_pull(b$conn)), class = "datom_vocabulary_unknown")
  check(err, "the merge check")
})

test_that("every refusal of the format check names the installed datom version", {
  installed <- as.character(utils::packageVersion("datom"))
  repo <- withr::local_tempdir()
  fs::dir_create(file.path(repo, ".datom"))

  jsonlite::write_json(list(schema_version = .datom_supported_schema, items = list()),
                       file.path(repo, ".datom", "manifest.json"), auto_unbox = TRUE)
  err <- expect_error(.datom_check_write_entry(list(path = repo), NULL),
                      class = "datom_shape_unreachable")
  expect_match(mc_msg(err), paste0("Installed datom is ", installed), fixed = TRUE)

  err <- expect_error(
    .datom_check_document_vocabulary(list(future_field = 1), "known", "doc.json"),
    class = "datom_vocabulary_unknown"
  )
  expect_match(mc_msg(err), paste0("Installed datom is ", installed), fixed = TRUE)
})


# === a merge datom did not start: finish_merge (R3.9) =============================

# A local branch `feature` holding a user's file, and the project's branch moved
# on by a write of dm v2, so feature's manifest names dm v1.
mc_feature_branch <- function(fx, conflicting = FALSE) {
  repo <- git2r::repository(fx$repo)
  main <- git2r::repository_head(repo)$name
  git2r::checkout(repo, branch = "feature", create = TRUE)
  writeLines("feature", file.path(fx$repo, "app.R"))
  git_commit_files(fx$repo, "app.R", "Feature work", push = FALSE)
  git2r::checkout(repo, branch = main)
  if (conflicting) {
    writeLines("main", file.path(fx$repo, "app.R"))
    git_commit_files(fx$repo, "app.R", "Main work", push = FALSE)
  }
  repo
}

test_that("datom_pull(conn, finish_merge = TRUE) finishes a user's merge of a local branch, rebuilding the manifest", {
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  repo <- mc_feature_branch(fx)
  v2 <- mc_write(fx$conn, "dm", 5L, "b")
  git2r::merge(repo, "feature", commit_on_success = FALSE,
               merger = .datom_git_signature(repo))
  expect_true(mc_merging(fx$repo))

  # Untouched without being asked.
  before <- mc_snapshot(fx, fx$repo)
  expect_error(suppressMessages(datom_pull(fx$conn)), class = "datom_merge_other")
  expect_identical(mc_snapshot(fx, fx$repo), before)

  run <- mc_finished_notes(datom_pull(fx$conn, finish_merge = TRUE))

  expect_length(run$notes, 1L)
  expect_match(run$notes, "row of \"dm\"", fixed = TRUE)
  expect_false(mc_merging(fx$repo))
  expect_identical(mc_head_parents(fx$repo), 2L)
  expect_identical(.datom_git_head_file(fx$repo, "app.R"), "feature\n")
  expect_identical(mc_manifest(fx$repo)$artifacts$dm$current_version, v2$metadata_sha)
})

test_that("datom_pull(conn, finish_merge = TRUE) commits nothing while another file still conflicts", {
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  repo <- mc_feature_branch(fx, conflicting = TRUE)
  git2r::merge(repo, "feature", merger = .datom_git_signature(repo))
  expect_true(mc_merging(fx$repo))
  before <- mc_snapshot(fx, fx$repo)

  err <- expect_error(suppressMessages(datom_pull(fx$conn, finish_merge = TRUE)),
                      class = "datom_merge_other")

  expect_match(mc_msg(err), "git merge --abort", fixed = TRUE)
  expect_identical(mc_snapshot(fx, fx$repo), before)
})

test_that("datom_pull(conn, finish_merge = TRUE) with no merge in progress pulls as usual", {
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  ae <- mc_write(fx$conn, "ae")

  pulled <- suppressMessages(datom_pull(b$conn, finish_merge = TRUE))

  expect_identical(pulled$commits_pulled, 1L)
  expect_identical(mc_manifest(b$repo)$artifacts$ae$current_version, ae$metadata_sha)
  expect_error(datom_pull(b$conn, finish_merge = NA), "must be")
})


# === the two stop messages, in full (R3.9) ======================================

test_that("the merge check's two stops say exactly this", {
  # A merge of the remote branch with datom's files in conflict.
  fx <- local_interrupt_project()
  mc_write(fx$conn, "dm")
  b <- local_second_clone(fx)
  mc_break(b$conn, "push", "dm", 7L, "c")
  mc_write(fx$conn, "dm", 5L, "b")
  err <- expect_error(mc_write(b$conn, "dm", 7L, "c"), class = "datom_merge_conflict")
  expect_identical(
    mc_msg(err),
    paste(
      "A merge is in progress, and these files still conflict: '.datom/manifest.json',",
      "'dm/metadata.json', and 'dm/version_history.json'.",
      "i Take the remote copy of datom's files:",
      "`git checkout MERGE_HEAD -- dm/metadata.json dm/version_history.json`.",
      "i Then re-run your write: datom rebuilds the manifest and finishes the merge.",
      "i No version is published."
    )
  )
  # Repeated by the merge check on the next command, without the lines only the
  # pull that made the conflict can say.
  err <- expect_error(suppressMessages(datom_pull(b$conn)), class = "datom_merge_conflict")
  expect_identical(
    mc_msg(err),
    paste(
      "A merge is in progress, and these files still conflict: '.datom/manifest.json',",
      "'dm/metadata.json', and 'dm/version_history.json'.",
      "i Take the remote copy of datom's files:",
      "`git checkout MERGE_HEAD -- dm/metadata.json dm/version_history.json`.",
      "i Then re-run your write: datom rebuilds the manifest and finishes the merge."
    )
  )

  # A merge datom did not start.
  fx2 <- local_interrupt_project()
  mc_write(fx2$conn, "dm")
  repo <- mc_feature_branch(fx2, conflicting = TRUE)
  git2r::merge(repo, "feature", merger = .datom_git_signature(repo))
  err <- expect_error(suppressMessages(datom_pull(fx2$conn)), class = "datom_merge_other")
  expect_identical(
    mc_msg(err),
    paste(
      "A merge datom did not start is in progress (\"Merge branch 'feature'\").",
      "datom changed nothing.",
      "i Resolve it with git and run `datom_pull(conn, finish_merge = TRUE)` to let",
      "datom rebuild the manifest and commit, or drop it with `git merge --abort`."
    )
  )
})
