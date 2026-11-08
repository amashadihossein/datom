# Healing what an interrupted command left behind.
#
# Every command that changes things starts the same way: the merge check, heal's
# reset, the command's own pull, heal's publish, and then the command's own
# work. Heal is datom's self-healing step: re-running a command that broke
# finishes the job, and it lives here, once, rather than in each command.
#
# Every publish -- heal's, a write's own, the metadata-only route's -- goes
# through one function here, `.datom_publish_artifacts()`, so the order readers
# depend on (each artifact's documents, `metadata.json` last, then the manifest)
# lives in one place.
#
# HEAL ACTS ONLY WHEN IT IS CERTAIN. Nothing records whose work a leftover is, so
# "certain" means the action is one the command was about to take anyway, on the
# same artifact: a write heals only the artifacts it is writing, and any other
# artifact's unfinished work stops it before anything changes, naming
# `datom_validate(fix = TRUE)`, which heals every artifact and is the consent to
# do so. A stop, not a prompt: scripts and a product layer cannot answer one.
#
# CHECK, THEN ACT. Each step runs only when its own read-only check finds
# something. On a clean, current clone the merge check finds no merge, `git
# status` finds no uncommitted datom file and the fetch finds nothing to merge,
# so nothing here writes to the clone, git or storage before the command's own
# work.
#
# The merge check and the pull are not heal. Every git-touching command calls the
# merge check and every write pulls, so removing heal would leave both in place.


# The files datom owns inside an artifact's folder. With `.datom/manifest.json`,
# these are the only files heal ever resets: never `project.yaml`, never a set
# write's `include_paths`, never `input_files/`.
.datom_artifact_own_files <- c("metadata.json", "version_history.json", "set.json")


# --- The merge check -----------------------------------------------------------

#' The Merge Check: Stop, or Finish, While a Merge Is in Progress
#'
#' Runs before anything a command changes: at the start of every pull
#' ([.datom_git_pull()]), and in [.datom_heal()] before its reset. On the common
#' path it only finds that `MERGE_HEAD` does not exist. Calling it twice in one
#' command is harmless.
#'
#' A merge in progress is told apart by **what is being merged**, never by text
#' or by a record datom keeps: it is a **merge of the remote branch** when the
#' branch's upstream tip, as last fetched, contains `MERGE_HEAD` (the same
#' commit, or the tip descends from it; local refs only, no fetch). That is the
#' only merge datom's pull makes, a `git fetch` during the merge does not change
#' the answer, and a user's own `git pull` makes the same merge. With no
#' upstream, or a detached HEAD, it is any other merge.
#'
#' - **Any other merge** (a local branch, another remote) stops, changing
#'   nothing, naming the merge and the two ways out.
#' - **A merge of the remote branch** with a file other than
#'   `.datom/manifest.json` still in conflict stops with those files and how to
#'   finish: take the remote copy of all of each conflicted artifact's datom
#'   files, resolve your own files, re-run.
#' - **A merge of the remote branch with only the manifest left in conflict, or
#'   nothing**, is finished: the manifest is rebuilt from the artifacts' files
#'   and the merge committed, with a message
#'   ([.datom_resolve_manifest_conflict()]). The command then carries on.
#'
#' `finish_merge = TRUE` (only [datom_pull()] passes it) treats any other merge
#' like a merge of the remote branch: it is finished once only the manifest is
#' left, and while another file conflicts it stops with the other-merge
#' message, since the recipe for the remote branch does not apply to it.
#'
#' Without the first stop datom would commit, and the next push share, a merge
#' the user started (one made with `--no-commit` to inspect it). Without the
#' second, heal's reset would put a file the user had resolved back to the local
#' side, and the next pull would conflict again. Without the finish, the user
#' would have to take the remote's whole manifest by hand, whose rows for the
#' clone's other unpushed writes would then stay stale with nothing reporting it.
#'
#' @param path Repository path.
#' @param finish_merge `TRUE` to finish a merge datom did not start; see above.
#' @return Invisibly `TRUE` when it finished a merge, `FALSE` when none was in
#'   progress; otherwise does not return.
#' @keywords internal
.datom_check_merge <- function(path, finish_merge = FALSE) {
  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  # `repo$path` is the git directory, which is also right for a worktree.
  merge_head_file <- fs::path(repo$path, "MERGE_HEAD")
  if (!fs::file_exists(merge_head_file)) return(invisible(FALSE))

  merge_head <- trimws(readLines(merge_head_file, n = 1L, warn = FALSE))

  of_upstream <- .datom_merge_is_of_upstream(repo, merge_head)
  if (!of_upstream && !isTRUE(finish_merge)) .datom_stop_other_merge(repo)

  # Finished only once nothing but the manifest conflicts.
  others <- setdiff(.datom_git_conflicted(repo), ".datom/manifest.json")
  if (length(others) > 0L) {
    if (!of_upstream) .datom_stop_other_merge(repo)
    .datom_stop_merge_conflict(path)
  }

  .datom_resolve_manifest_conflict(path)
  invisible(TRUE)
}


#' Is the Merge in Progress a Merge of the Remote Branch
#'
#' @param repo A `git2r::repository` handle.
#' @param merge_head The SHA in `MERGE_HEAD`.
#' @return `TRUE` when the branch's upstream tip, as last fetched, contains
#'   `merge_head`; `FALSE` otherwise, including with no upstream or a detached
#'   HEAD.
#' @keywords internal
.datom_merge_is_of_upstream <- function(repo, merge_head) {
  head <- tryCatch(git2r::repository_head(repo), error = function(e) NULL)
  if (is.null(head) || !git2r::is_branch(head)) return(FALSE)

  upstream <- tryCatch(git2r::branch_get_upstream(head), error = function(e) NULL)
  if (is.null(upstream)) return(FALSE)

  .datom_git_contains(repo, git2r::branch_target(upstream), merge_head)
}


#' Stop on a Merge datom Did Not Start
#'
#' The quoted name is the first line of `MERGE_MSG`, shown only to say which
#' merge; nothing is decided from it.
#'
#' @param repo A `git2r::repository` handle.
#' @return Does not return.
#' @keywords internal
.datom_stop_other_merge <- function(repo) {
  msg_file <- fs::path(repo$path, "MERGE_MSG")
  what <- if (fs::file_exists(msg_file)) {
    readLines(msg_file, n = 1L, warn = FALSE)
  } else {
    character()
  }
  if (length(what) == 0L || !nzchar(what)) what <- "unnamed"

  cli::cli_abort(
    c(
      "A merge datom did not start is in progress ({.val {what}}). datom \\
       changed nothing.",
      "i" = "Resolve it with git and run \\
             {.code datom_pull(conn, finish_merge = TRUE)} to let datom rebuild \\
             the manifest and commit, or drop it with {.code git merge --abort}."
    ),
    class = "datom_merge_other"
  )
}


#' Stop on a Merge of the Remote Branch That Still Conflicts
#'
#' The one message for this state, used by the merge check and by the pull that
#' produced the conflict. It lists the conflicted files and fills in the command
#' that takes the remote copy of **all** of each conflicted artifact's datom
#' files, not only the conflicted ones: `git checkout --theirs` does nothing to a
#' file that merged cleanly, which would leave the artifact half local and half
#' remote. Only files the merged commit holds are named, or git refuses the
#' command. A conflicted file counts as an artifact's when it is one of the
#' files datom owns in a folder the manifest names, in HEAD or in the merged
#' commit.
#'
#' The user never edits the manifest or runs `git commit` for such a merge:
#' re-running the write rebuilds the manifest and finishes the merge.
#'
#' @param path Repository path.
#' @param after_pull `TRUE` when the pull just produced the conflict; the message
#'   then ends "No version is published."
#' @param data_file_stored See [.datom_git_push()].
#' @return Does not return.
#' @keywords internal
.datom_stop_merge_conflict <- function(path, after_pull = FALSE,
                                       data_file_stored = FALSE) {
  repo <- git2r::repository(path)
  conflicted <- .datom_git_conflicted(repo)

  artifacts <- union(
    .datom_manifest_names_at(path, "HEAD"),
    .datom_manifest_names_at(path, "MERGE_HEAD")
  )
  is_datom <- dirname(conflicted) %in% artifacts &
    basename(conflicted) %in% .datom_artifact_own_files

  take <- unlist(lapply(unique(dirname(conflicted[is_datom])), function(a) {
    files <- paste0(a, "/", .datom_artifact_own_files)
    files[purrr::map_lgl(files, function(f) {
      !is.null(.datom_git_head_file(path, f, head = "MERGE_HEAD"))
    })]
  }))
  own <- setdiff(conflicted[!is_datom], ".datom/manifest.json")
  checkout_cmd <- paste(c("git checkout MERGE_HEAD --", take), collapse = " ")

  rerun <- "re-run your write: datom rebuilds the manifest and finishes the merge."
  rerun <- if (length(take) > 0L || length(own) > 0L) {
    paste("Then", rerun)
  } else {
    paste0("R", substring(rerun, 2L))
  }

  cli::cli_abort(
    c(
      if (length(conflicted) > 0L) {
        "A merge is in progress, and these files still conflict: \\
         {.file {conflicted}}."
      } else {
        "A merge is in progress."
      },
      if (length(take) > 0L) {
        c("i" = "Take the remote copy of datom's files: {.code {checkout_cmd}}.")
      },
      if (length(own) > 0L) {
        c("i" = "Resolve your own files and {.code git add} them.")
      },
      "i" = rerun,
      if (isTRUE(after_pull)) c("i" = "No version is published."),
      .datom_data_file_note(data_file_stored)
    ),
    class = "datom_merge_conflict"
  )
}


#' The Files a Merge in Progress Still Has in Conflict
#'
#' @param repo A `git2r::repository` handle.
#' @return Repo-relative paths, possibly empty.
#' @keywords internal
.datom_git_conflicted <- function(repo) {
  st <- git2r::status(repo, staged = TRUE, unstaged = TRUE, untracked = FALSE)
  entries <- c(st$staged, st$unstaged)
  unique(unname(unlist(entries[names(entries) == "conflicted"], use.names = FALSE)))
}


# --- A conflict only in the manifest -------------------------------------------

#' Finish a Merge Whose Only Conflict Is the Manifest
#'
#' Requirements R3.8 (design section 5). The manifest is derived: every fact on
#' a row is also recorded in the artifact's own files. So a manifest a merge
#' left in conflict is rebuilt from those files rather than merged by hand. Two
#' callers: the pull ([.datom_git_pull()]), when its merge conflicts in
#' `.datom/manifest.json` and nowhere else (every write rewrites the manifest's
#' timestamp and summary, so two clones writing different artifacts conflict
#' there), and the merge check ([.datom_check_merge()]), once a merge in
#' progress has nothing but the manifest left in conflict.
#'
#' In order, and the order matters:
#'
#' 1. **The merged-in side's copy** (`MERGE_HEAD`'s, or HEAD's if that one does
#'    not parse) is written in place of the conflict markers. Its top level,
#'    `project_name` included, is kept as it is.
#' 2. **The format check** ([.datom_check_write_entry()]) runs on that copy and
#'    on every artifact's files in the merged clone, before anything else is
#'    written. The merge may have brought documents from a newer datom, which
#'    this build must not rewrite in its own shape, commit and share. A refusal
#'    stages and commits nothing and leaves the merge in progress; its message
#'    keeps the refusal's class and evidence and adds the ways out.
#' 3. **Each row is compared with its artifact's files**, and only a row naming
#'    a different version, or a missing one, is rebuilt
#'    ([.datom_manifest_row()]), carrying forward any field this build cannot
#'    place. There is no comparison with the merge base: a row the local side
#'    did not touch already agrees with the files the merge brought in, so
#'    whichever side changed an artifact, its row ends up naming what its files
#'    record.
#' 4. The summary is recomputed, the timestamp set, and the merge committed
#'    ("Merge finished by datom (manifest rebuilt)"), together with whatever
#'    the user resolved and staged. A message says so.
#'
#' **It needs no connection.** Everything it reads is in the clone: since the
#' writer floor is read from `.datom/project.yaml`, the format check uses only
#' the clone's path, so a stand-in holding the path is passed (design section
#' 10, item 6). That is how the pull inside [datom_get_conn()], which runs
#' before the connection exists, reaches it.
#'
#' It runs only on the conflict path, so the common path never reaches it.
#'
#' @param path Repository path.
#' @param data_file_stored See [.datom_git_push()]; a refusal then adds the line
#'   about the write's data file.
#' @return Invisibly, the artifacts whose rows were rebuilt.
#' @keywords internal
.datom_resolve_manifest_conflict <- function(path, data_file_stored = FALSE) {
  rel <- ".datom/manifest.json"
  parses <- function(text) {
    !is.null(text) && is.list(tryCatch(
      jsonlite::fromJSON(text, simplifyVector = FALSE),
      error = function(e) NULL
    ))
  }
  start <- purrr::detect(
    list(
      .datom_git_head_file(path, rel, head = "MERGE_HEAD"),
      .datom_git_head_file(path, rel)
    ),
    parses
  )
  if (is.null(start)) .datom_stop_merge_manifest_unusable()

  manifest_path <- fs::path(path, rel)
  writeBin(charToRaw(enc2utf8(start)), manifest_path)

  # Before anything else is written. Only the path is read (see above).
  clone <- list(path = path)
  refused <- tryCatch(
    {
      .datom_check_write_entry(clone, NULL)
      NULL
    },
    error = function(e) e
  )
  if (!is.null(refused)) .datom_stop_merge_refused(refused, data_file_stored)

  read <- .datom_read_manifest(clone, "clone", operation = "write")
  manifest <- read$manifest

  artifacts <- .datom_clone_artifact_names(clone)
  fresh <- stats::setNames(
    lapply(artifacts, function(nm) {
      .datom_row_from_clone(path, nm, manifest$artifacts[[nm]])
    }),
    artifacts
  )
  fresh <- purrr::compact(fresh)
  manifest$artifacts[names(fresh)] <- fresh

  manifest$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  manifest$summary <- .datom_manifest_summary(manifest$artifacts)

  .datom_notify_manifest_upgraded(read$declared, "this repo's manifest")
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)
  .datom_git_commit(path, rel, "Merge finished by datom (manifest rebuilt)")

  rebuilt <- names(fresh)
  cli::cli_inform(
    c("i" = if (length(rebuilt) > 0L) {
      "Finished the merge in progress: rebuilt the {.file .datom/manifest.json} \\
       row{?s} of {.val {rebuilt}} from {?its/their} files, and committed the \\
       merge."
    } else {
      "Finished the merge in progress: every row of {.file .datom/manifest.json} \\
       already agreed with its artifact's files, and the merge is committed."
    }),
    class = "datom_merge_finished"
  )

  invisible(rebuilt)
}


#' One Artifact's Manifest Row, Rebuilt From Its Files in the Clone
#'
#' @param path Repository path.
#' @param name Artifact name.
#' @param row The row the manifest holds for it now, or `NULL`.
#' @return The rebuilt row, or `NULL` when `row` already names the version the
#'   files describe, or the clone holds no `metadata.json` to rebuild from.
#' @keywords internal
.datom_row_from_clone <- function(path, name, row) {
  meta <- .datom_read_clone_json(path, paste0(name, "/metadata.json"))
  if (is.null(meta)) return(NULL)
  history <- .datom_read_clone_json(path, paste0(name, "/version_history.json"))

  version <- .datom_documents_version(meta, history)
  if (is.list(row) && identical(row$current_version, version)) return(NULL)

  # A set's count is the length of its payload, which the clone holds as
  # `set.json`: the same tidied member list the write counted.
  member_count <- if (identical(meta$kind %||% "table", "set")) {
    payload <- .datom_read_clone_json(path, paste0(name, "/set.json"))
    if (is.list(payload$members)) as.integer(length(payload$members))
  }

  .datom_carry_unknown_fields(
    .datom_manifest_row(meta, history, member_count = member_count, version = version),
    row,
    .datom_manifest_entry_known_fields
  )
}


#' The Version an Artifact's Documents Describe
#'
#' The document's own version (`.datom_compute_metadata_sha()` of its
#' `metadata.json`) when every top-level field of that document is one this
#' build can place and its history names that version; otherwise the version
#' the history records for the document ([.datom_recorded_current_version()]).
#' Shared by the manifest rebuild after a merge, which reads the clone's
#' documents, and by `datom_validate()`'s `manifest_mismatch_s3` check, which
#' reads the stored ones.
#'
#' **Why the document's own version first.** The history alone cannot tell two
#' versions of the same data apart when only their custom metadata differs. A
#' write that sets custom metadata back to earlier values returns to a version
#' the history already holds: it appends no entry and stamps a fresh
#' `created_at`, so the history matches neither entry's timestamp and falls back
#' to its newest one for that data, which is the wrong one. Hashing the document
#' gives the id the write recorded.
#'
#' **Why every field must be one this build can place.** The hash takes only
#' the identity fields this build knows. A document from a newer datom, with a
#' field this build cannot place, can hash (ignoring that field) to an older
#' entry written before the field existed; such a document gets the recorded
#' version. In the clone the format check has just passed, so this never
#' applies there; in storage nothing has checked the document.
#'
#' **Why the history must name it.** A version named here is one the history
#' records, never a manufactured one, which is the rule every rebuild keeps. A
#' document committed by hand hashes to an id no entry holds, and gets the
#' recorded one.
#'
#' @param meta The artifact's parsed `metadata.json`.
#' @param history Its parsed `version_history.json`, or `NULL`.
#' @return A version string, or `NULL` when the history records nothing usable.
#' @keywords internal
.datom_documents_version <- function(meta, history) {
  placeable <- all(names(meta) %in% .datom_metadata_known_fields())
  if (placeable) {
    own <- .datom_compute_metadata_sha(meta)
    if (own %in% .datom_history_versions(history %||% list())) return(own)
  }
  .datom_recorded_current_version(meta, history)
}


#' Stop When the Format Check Refuses What a Merge Brings In
#'
#' The refusal's own class is kept, so a caller matches it as it would at a
#' write's door, and its message, with its evidence (the document, what this
#' build cannot read, the installed datom version), follows as the cause.
#'
#' @param e The refusal.
#' @param data_file_stored See [.datom_git_push()].
#' @return Does not return.
#' @keywords internal
.datom_stop_merge_refused <- function(e, data_file_stored = FALSE) {
  cli::cli_abort(
    c(
      "A merge is in progress, and this build of datom cannot write what it \\
       brings in (below), so datom did not finish it.",
      "i" = "The merge is still in progress: datom committed nothing for it, \\
             and nothing was pushed or published.",
      .datom_data_file_note(data_file_stored),
      "i" = "Upgrade datom and re-run, or drop the merge with \\
             {.code git merge --abort}."
    ),
    class = setdiff(class(e), c("rlang_error", "error", "condition")),
    parent = e
  )
}


#' Stop When Neither Side of a Merge Holds a Manifest datom Can Start From
#'
#' Only a manifest broken outside datom on both sides reaches this.
#'
#' @return Does not return.
#' @keywords internal
.datom_stop_merge_manifest_unusable <- function() {
  cli::cli_abort(
    c(
      "A merge is in progress, and datom cannot finish it: neither side of the \\
       merge holds a {.file .datom/manifest.json} that parses.",
      "i" = "datom changed nothing.",
      "i" = "Drop the merge with {.code git merge --abort}."
    ),
    class = "datom_merge_conflict"
  )
}


# --- Heal ------------------------------------------------------------------------

#' Heal What an Interrupted Write Left Behind: the Reset
#'
#' Heal has two halves, and the command's own pull runs between them: this one,
#' the reset (requirements R2.4, R3.1), and [.datom_heal_publish()], which
#' pushes and publishes what an earlier run committed. Each route calls the
#' three in that order, in exactly one place, after the checks that need no
#' storage state heal can change and before change detection:
#'
#' ```
#' healed <- .datom_heal(conn, artifact = name)
#' .datom_pull_before_write(conn, reset = healed$reset)
#' .datom_heal_publish(conn, artifact = name)
#' ```
#'
#' The pull sits between them because uncommitted datom files left by a crash
#' make git refuse a merge that touches them (so the reset runs first), and
#' what storage lacks is decided against the clone as the pull left it (so the
#' publish runs after). It is a call of its own rather than one made from here
#' because the pull belongs to the command: removing heal would leave it.
#'
#' This half starts with the merge check, then resets what never committed. It
#' runs only when its own check finds something: one `git status`.
#'
#' **Two lists, because resetting and publishing are certain under different
#' conditions.** `artifact` names what the command publishes; `rewrite`, a
#' subset of it, names the artifacts whose files the command writes again. Only
#' those may be put back: the metadata-only route publishes its table and
#' rewrites none of its files, so there an uncommitted edit of the table stops
#' the command instead (`rewrite = character()`).
#'
#' **What heal repairs:**
#' - the artifacts in `rewrite`: their datom files left by a write that broke
#'   before its commit are put back to the last commit, with a message, and the
#'   command then writes them again;
#' - the artifacts in `artifact`: their committed versions GitHub or storage
#'   lacks are pushed and published ([.datom_heal_publish()]);
#' - with `all = TRUE` (the repair), every artifact, both halves, with a warning
#'   naming each artifact reset, since that write is not run again.
#'
#' **What heal leaves:**
#' - **another artifact's unfinished work**: a write never acts on an artifact it
#'   is not writing. It stops before anything changes, naming the artifact and
#'   `datom_validate(fix = TRUE)`;
#' - a merge in progress: the merge check runs first and stops, unless it is a
#'   merge of the remote branch with nothing but the manifest left in conflict,
#'   which it finishes ([.datom_check_merge()]);
#' - every file datom does not own: `project.yaml`, a set write's
#'   `include_paths`, `input_files/`, and a user's own `app/metadata.json` (only
#'   folders the manifest names, or whose `metadata.json` declares a datom
#'   `hash_algo`, are artifacts; see [.datom_clone_artifact_names()]);
#' - damage a released datom left, files changed in storage by hand.
#'
#' The shared `.datom/manifest.json` follows `rewrite` too: it is reset only when
#' every row differing from HEAD's belongs to an artifact in `rewrite`; a
#' differing row of any other artifact is that artifact's unfinished work, and
#' stops the command.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param artifact Names of the artifacts the command publishes, or `NULL` for
#'   none.
#' @param rewrite Names of the artifacts whose files the command writes again:
#'   a subset of `artifact`, all of it by default. A name outside `artifact` is
#'   an internal error.
#' @param all `TRUE` for the repair: act on every artifact.
#' @return Invisibly, a list with `reset`: the artifacts whose files were put
#'   back.
#' @keywords internal
.datom_heal <- function(conn, artifact = NULL, rewrite = artifact, all = FALSE) {
  stray <- setdiff(rewrite, artifact)
  if (!isTRUE(all) && length(stray) > 0L) {
    cli::cli_abort(
      "Internal error: heal was asked to rewrite {.val {stray}}, which the \\
       command does not publish.",
      class = "datom_internal_error"
    )
  }

  .datom_check_merge(conn$path)

  # The gate is this one `git status`. The reset behind it would find nothing on
  # a clean clone either way, so the gate's only observable is cost; no test can
  # tell it is there, and none tries.
  unfinished <- .datom_unfinished_files(conn)
  reset <- if (length(unfinished) > 0L) {
    .datom_reset_unfinished(conn, unfinished, rewrite = rewrite, all = all)
  } else {
    character()
  }

  invisible(list(reset = reset))
}


#' datom's Own Files That Differ From the Last Commit
#'
#' Staged, unstaged and untracked alike, restricted to the files datom owns:
#' `.datom/manifest.json`, and `metadata.json`, `version_history.json` and
#' `set.json` in each artifact folder ([.datom_clone_artifact_names()]). git
#' reports an untracked folder as `lb/`, so such a folder is looked into for
#' those three names only.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param st The clone's `git2r::status()` with staged, unstaged and untracked
#'   files, when the caller already has it; `NULL` to read it here.
#' @return Repo-relative paths with forward slashes, possibly empty.
#' @keywords internal
.datom_unfinished_files <- function(conn, st = NULL) {
  st <- st %||% git2r::status(
    git2r::repository(conn$path),
    staged = TRUE, unstaged = TRUE, untracked = TRUE
  )

  changed <- unname(unlist(c(st$staged, st$unstaged), use.names = FALSE))
  untracked <- unname(unlist(st$untracked, use.names = FALSE))
  untracked_dirs <- untracked[grepl("/$", untracked)]
  inside <- unlist(lapply(sub("/$", "", untracked_dirs), function(d) {
    names <- if (identical(d, ".datom")) "manifest.json" else .datom_artifact_own_files
    paste0(d, "/", names)
  }))
  inside <- inside[fs::file_exists(fs::path(conn$path, inside))]

  candidates <- unique(c(changed, untracked[!grepl("/$", untracked)], inside))
  if (length(candidates) == 0L) return(character())

  artifacts <- .datom_clone_artifact_names(conn)
  owned <- candidates == ".datom/manifest.json" |
    (dirname(candidates) %in% artifacts &
       basename(candidates) %in% .datom_artifact_own_files)

  candidates[owned]
}


#' Put Back What a Write Left Before Its Commit
#'
#' Decides first and acts second, so a stop changes nothing. Each uncommitted
#' file belongs to the artifact whose folder holds it; the manifest's changes
#' belong to the artifacts whose rows differ from HEAD's. When any of those is
#' not one the command writes again (`rewrite`; `all` is `FALSE`), the command
#' stops naming them. Otherwise every file is put back to the last commit:
#' unstaged, then checked out from HEAD, or deleted when HEAD does not hold it
#' (an artifact's first write), with its folder removed once empty.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param unfinished What [.datom_unfinished_files()] found.
#' @param rewrite,all See [.datom_heal()].
#' @return The artifacts whose files were put back.
#' @keywords internal
.datom_reset_unfinished <- function(conn, unfinished, rewrite = NULL,
                                    all = FALSE) {
  owners <- .datom_unfinished_owners(conn, unfinished)
  by_artifact <- owners$by_artifact
  rows <- owners$rows
  unknown_rows <- owners$unknown_rows

  touched <- owners$touched
  own <- if (isTRUE(all)) touched else intersect(touched, rewrite)
  others <- setdiff(touched, own)

  if (length(others) > 0L || (unknown_rows && !isTRUE(all))) {
    .datom_stop_unfinished_files(others, by_artifact, rows, unknown_rows)
  }

  .datom_restore_files(conn$path, unfinished)

  if (length(own) == 0L) {
    cli::cli_inform(
      c("i" = "Reset {.file .datom/manifest.json} to its last commit: its \\
               uncommitted changes touched no artifact's row."),
      class = "datom_heal_reset"
    )
  }

  purrr::walk(own, function(a) {
    if (isTRUE(all) && !(a %in% rewrite)) {
      cli::cli_warn(
        "Reset an unfinished write of {.val {a}} that stopped before its \\
         commit. Run that write again to save it.",
        class = "datom_heal_reset"
      )
    } else {
      cli::cli_inform(
        c("i" = "Found an unfinished write of {.val {a}} that stopped before \\
                 its commit; writing it again now."),
        class = "datom_heal_reset"
      )
    }
  })

  own
}


#' Whose Unfinished Work datom's Uncommitted Files Are
#'
#' Each uncommitted file in an artifact's folder belongs to that artifact; the
#' manifest's changes belong to the artifacts whose rows differ from HEAD's.
#' Shared by heal's reset, which decides from it what it may put back, and by
#' the pull's stop when it cannot catch up, which names the same artifacts.
#'
#' @param conn A `datom_conn` object with a local path (a list with `path` is
#'   enough).
#' @param unfinished What [.datom_unfinished_files()] found.
#' @return A list: `by_artifact` (the files, by artifact), `rows` (the artifacts
#'   whose manifest rows differ), `unknown_rows` (`TRUE` when the manifest's
#'   changes cannot be tied to any artifact) and `touched` (every artifact
#'   named).
#' @keywords internal
.datom_unfinished_owners <- function(conn, unfinished) {
  manifest_rel <- ".datom/manifest.json"
  artifact_files <- setdiff(unfinished, manifest_rel)
  by_artifact <- split(artifact_files, dirname(artifact_files))

  rows <- if (manifest_rel %in% unfinished) {
    .datom_manifest_rows_changed(conn)
  } else {
    character()
  }
  unknown_rows <- anyNA(rows)
  rows <- rows[!is.na(rows)]

  list(
    by_artifact = by_artifact,
    rows = rows,
    unknown_rows = unknown_rows,
    touched = union(names(by_artifact), rows)
  )
}


#' The Manifest Rows That Differ From HEAD's
#'
#' Rows are compared by artifact name, with **both copies in the current
#' format first**: a write converts an older manifest as it edits it, so a
#' repo last written by an older datom has HEAD's copy in the old shape and the
#' working tree's in the new one. Compared raw, every row would differ, and each
#' write would stop naming the other artifacts. The format check runs on each
#' copy first, as for every read that converts (a refusal names its evidence).
#'
#' A row added, removed or rewritten differs. A write rewrites only its own row
#' (and the summary and timestamp, which belong to no artifact), so the names
#' returned are the artifacts whose writes touched the manifest.
#'
#' @param conn A `datom_conn` object with a local path.
#' @return Artifact names; `NA_character_` when either copy cannot be parsed, so
#'   the changes cannot be tied to any artifact.
#' @keywords internal
.datom_manifest_rows_changed <- function(conn) {
  head_rows <- .datom_manifest_rows(
    .datom_git_head_file(conn$path, ".datom/manifest.json"),
    current = TRUE, source = ".datom/manifest.json (last commit)"
  )
  wt_path <- fs::path(conn$path, ".datom", "manifest.json")
  wt_rows <- .datom_manifest_rows(
    if (fs::file_exists(wt_path)) {
      paste(readLines(wt_path, warn = FALSE), collapse = "\n")
    },
    current = TRUE, source = ".datom/manifest.json"
  )
  if (is.null(head_rows) || is.null(wt_rows)) return(NA_character_)

  nms <- union(names(head_rows), names(wt_rows))
  nms[!purrr::map_lgl(nms, function(n) identical(head_rows[[n]], wt_rows[[n]]))]
}


#' A Manifest's Rows, From Its Text
#'
#' @param text The manifest as one string, or `NULL` when there is none.
#' @param current `TRUE` to check the declared format and convert the document
#'   to the current shape before taking its rows, so two copies compare like
#'   for like. `FALSE` (the default) only reads names, from either shape, and
#'   never refuses: the callers that only need names include the merge-conflict
#'   message, which must not be replaced by a format refusal about the remote's
#'   copy.
#' @param source The copy's name, for a format refusal.
#' @return A named list of rows (empty when there is no manifest), or `NULL`
#'   when the text does not parse.
#' @keywords internal
.datom_manifest_rows <- function(text, current = FALSE,
                                 source = ".datom/manifest.json") {
  if (is.null(text)) return(list())
  doc <- tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.list(doc)) return(NULL)

  if (isTRUE(current)) {
    declared <- .datom_check_schema_version(doc, source, operation = "write")
    return(.datom_manifest_upgrade(doc, declared)$artifacts %||% list())
  }

  # The artifact list's name before schema v2 is `tables`.
  doc$artifacts %||% doc$tables %||% list()
}


#' Put Files Back to the Last Commit
#'
#' @param path Repository path.
#' @param files Repo-relative paths.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_restore_files <- function(path, files) {
  repo <- git2r::repository(path)

  staged <- unname(unlist(
    git2r::status(repo, staged = TRUE, unstaged = FALSE, untracked = FALSE)$staged,
    use.names = FALSE
  ))
  to_unstage <- intersect(files, staged)
  if (length(to_unstage) > 0L) git2r::reset(repo, path = to_unstage)

  in_head <- purrr::map_lgl(files, function(f) {
    !is.null(.datom_git_head_file(path, f))
  })
  if (any(in_head)) git2r::checkout(repo, path = files[in_head], force = TRUE)

  added <- fs::path(path, files[!in_head])
  added <- added[fs::file_exists(added)]
  if (length(added) > 0L) fs::file_delete(added)

  # An artifact's first write leaves a folder holding only datom's files.
  folders <- setdiff(unique(fs::path_dir(added)), fs::path(path, ".datom"))
  purrr::walk(folders, function(d) {
    if (fs::dir_exists(d) && length(fs::dir_ls(d, all = TRUE)) == 0L) {
      fs::dir_delete(d)
    }
  })

  invisible(NULL)
}


#' Stop on Another Artifact's Uncommitted Files
#'
#' A write never acts on an artifact it is not writing (requirements D14,
#' principle 8): nothing can prove whose work a leftover is. Two ways out: that
#' artifact's own write, re-run, finishes it (heal resets and rewrites it), and
#' `datom_validate(fix = TRUE)` discards the changes for every artifact.
#'
#' @param others The artifacts with uncommitted changes the command does not
#'   write.
#' @param by_artifact Their files, by artifact.
#' @param rows The artifacts whose manifest rows differ from HEAD's.
#' @param unknown_rows `TRUE` when the manifest's changes cannot be tied to any
#'   artifact.
#' @return Does not return.
#' @keywords internal
.datom_stop_unfinished_files <- function(others, by_artifact, rows,
                                         unknown_rows) {
  files_of <- function(a) {
    c(by_artifact[[a]], if (a %in% rows) ".datom/manifest.json")
  }
  details <- purrr::map_chr(others, function(a) {
    files <- files_of(a)
    cli::format_inline("{.val {a}}: {.file {files}}")
  })
  if (unknown_rows) {
    details <- c(details, cli::format_inline(
      "{.file .datom/manifest.json}: changed in a way datom cannot tie to an \\
       artifact"
    ))
  }
  what <- if (length(others) > 0L) others else ".datom/manifest.json"
  rerun <- if (length(others) == 0L) {
    character()
  } else if (length(others) == 1L) {
    "Re-run that write to finish it, or run"
  } else {
    "Re-run each of those writes to finish it, or run"
  }
  way_out <- paste(c(rerun, if (length(rerun) == 0L) "Run"), collapse = "")

  cli::cli_abort(
    c(
      "{.val {what}} {?has/have} unfinished work: changes to datom's files that \\
       were never committed.",
      purrr::set_names(details, rep("*", length(details))),
      "i" = "datom changed nothing.",
      "i" = "{way_out} {.code datom_validate(fix = TRUE)} to discard the \\
             changes. Then re-run this command."
    ),
    class = "datom_unfinished_work"
  )
}


# --- Heal's publish -------------------------------------------------------------

#' Heal What an Interrupted Write Left Behind: Push and Publish
#'
#' The second half of heal (requirements R2.2, R2.3, R3.2-R3.4, R3.10), run by
#' each route right after its own pull (see [.datom_heal()] for the order). It
#' finishes a committed version that GitHub or storage lacks: a write whose push
#' broke, or whose storage upload failed after the push.
#'
#' **Check, then act.** The check is one read of the stored manifest: does any
#' stored row name a different version from the clone's? Only then does
#' anything run. Whether the clone is ahead of the remote is not the check: an
#' unfinished datom version always shows as a differing row (the manifest is
#' published after the push), while a commit of the user's own, made with
#' `datom_repo_commit(push = FALSE)`, makes the clone ahead with nothing to
#' finish, and a write with nothing to save must not push it (task 4b's
#' checkpoint review). On a clean, current, published clone this reads and
#' writes nothing else.
#'
#' **A write acts only on its own artifacts** (requirements D14 principle 8):
#' - another artifact whose stored row differs, or a stored row for an artifact
#'   the clone lacks, stops the command before the push, naming it and
#'   `datom_validate(fix = TRUE)`;
#' - for its own artifact, the clone's history must contain the version the
#'   stored row names (containment, not "older": a revert brings back an id the
#'   history already holds). Otherwise storage holds something this clone has
#'   never seen, and the command stops. The repair (`all = TRUE`) overrides
#'   this: it publishes the clone's version, says which stored version it
#'   replaced, and drops a stored row whose artifact the clone lacks.
#'
#' Then, finishing a version of its own, it pushes if the clone is ahead,
#' **without pulling again**: the route's
#' pull ran moments ago, and a remote that moved since makes git refuse the
#' push, which stops the command before storage changes. Pulling here could
#' bring in a teammate's commit whose version is not in storage yet, and the
#' manifest below would then name it. With no upstream branch it cannot tell
#' whether it is ahead, so it pushes before the checks instead (git refuses the
#' push when the clone is behind). Then it publishes the artifacts through
#' [.datom_publish_artifacts()], manifest last. If that fails, the command stops
#' before its own work.
#'
#' The stops here say "Nothing was pushed or published" rather than "datom
#' changed nothing": by now heal's reset may have put back the command's own
#' files, and the pull may have brought the clone up to date.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param artifact Names of the artifacts the command publishes.
#' @param all `TRUE` for the repair: every artifact is the command's own.
#' @return Invisibly, a list with `published` (the versions published, named by
#'   artifact) and `pushed` (`TRUE` when it pushed).
#' @keywords internal
.datom_heal_publish <- function(conn, artifact = NULL, all = FALSE) {
  # With no upstream branch datom cannot tell what the remote holds, so it
  # pushes first: git refuses the push when the clone is behind, which stops the
  # command before storage changes (and before a stored row this clone has not
  # pulled could be misread as unfinished work), and a push that lands sets the
  # upstream. With an upstream, the push waits until the checks below pass, so
  # a write never pushes another artifact's commit.
  ahead <- .datom_git_ahead(conn$path)
  pushed <- FALSE
  if (is.na(ahead)) {
    .datom_git_push(conn$path, pat = conn$github_pat, pull_first = FALSE)
    pushed <- TRUE
    ahead <- FALSE
  } else {
    ahead <- ahead > 0L
  }

  stored <- .datom_stored_manifest(conn)
  if (identical(stored$status, "unreadable")) {
    if (!isTRUE(all)) .datom_stop_stored_manifest_unreadable(stored$error)
    why <- .datom_one_line(stored$error)
    cli::cli_warn(
      c(
        "Could not read the stored manifest, so every artifact and the manifest \\
         are published from this clone.",
        "x" = "{why}"
      ),
      class = "datom_heal_override"
    )
    stored <- list(status = "absent", rows = list(), error = NULL)
  }
  clone_rows <- .datom_clone_manifest_rows(conn)
  differ <- .datom_unpublished_artifacts(clone_rows, stored)

  # The gate: storage names what the clone names. Decided from the manifests
  # alone, not from whether the clone is ahead: a commit of the user's own
  # (`datom_repo_commit(push = FALSE)`, which says "push later") makes the clone
  # ahead with nothing of datom's unfinished, and a write with nothing to save
  # must not push it. An unfinished datom version always shows here, because
  # the stored manifest is updated only after the push.
  if (length(differ) == 0L) {
    return(invisible(list(published = character(), pushed = pushed)))
  }

  own <- if (isTRUE(all)) differ else intersect(differ, artifact)
  others <- setdiff(differ, own)
  if (length(others) > 0L) {
    .datom_stop_unpublished_others(others, in_clone = names(clone_rows))
  }

  # The containment check (R3.10): storage must not name a version of the
  # artifact that this clone's history lacks.
  unseen <- own[purrr::map_lgl(own, function(nm) {
    version <- stored$rows[[nm]]$current_version
    .datom_is_text_scalar(version) &&
      !.datom_history_contains(conn$path, nm, version)
  })]
  if (length(unseen) > 0L && !isTRUE(all)) {
    .datom_stop_stored_version_unseen(unseen, stored$rows)
  }
  if (isTRUE(all)) .datom_warn_stored_replaced(own, unseen, stored$rows, clone_rows)

  # Past the gate and the stop on other artifacts, every differing row is the
  # command's own, so a push here always carries a version being finished.
  if (ahead) {
    .datom_git_push(conn$path, pat = conn$github_pat, pull_first = FALSE)
    pushed <- TRUE
  }

  to_publish <- intersect(own, names(clone_rows))
  result <- .datom_publish_artifacts(conn, to_publish, on_failure = "return")
  if (length(result$failed) > 0L) .datom_stop_publish_failed(result$failed)

  purrr::iwalk(result$published, function(version, nm) {
    cli::cli_inform(
      c("i" = "Finished an earlier write of {.val {nm}}: published version \\
               {.val {substr(version, 1L, 8L)}}, which it had committed."),
      class = "datom_heal_published"
    )
  })

  invisible(list(published = result$published, pushed = pushed))
}


#' The Stored Manifest, Told Apart From an Absent or Unreadable One
#'
#' The one read of the stored manifest heal's publish makes (requirements
#' R3.4). An existence check first, because the two failures mean different
#' things: an absent manifest means storage names nothing, so every artifact
#' the clone holds differs from it; one that exists and cannot be read (storage
#' unreachable, or the file damaged) means datom cannot tell what storage
#' lacks, and a write stops rather than guess. A manifest from a newer datom is
#' refused by the format check, as everywhere a write reads one.
#'
#' @param conn A `datom_conn` object.
#' @return A list with `status` (`"ok"`, `"absent"` or `"unreadable"`), `rows`
#'   (the artifact rows, in the current format) and `error` (the condition, for
#'   `"unreadable"`).
#' @keywords internal
.datom_stored_manifest <- function(conn) {
  key <- ".metadata/manifest.json"
  present <- tryCatch(.datom_storage_exists(conn, key), error = function(e) e)
  if (inherits(present, "error")) {
    return(list(status = "unreadable", rows = list(), error = present))
  }
  if (!isTRUE(present)) return(list(status = "absent", rows = list(), error = NULL))

  read <- .datom_read_manifest(conn, "storage", operation = "write")
  if (!isTRUE(read$ok)) {
    return(list(status = "unreadable", rows = list(), error = read$error))
  }

  list(status = "ok", rows = read$manifest$artifacts %||% list(), error = NULL)
}


#' The Clone's Manifest Rows, in the Current Format
#'
#' After heal's reset and the pull, the working tree's manifest is the committed
#' one, so this is the version each artifact's last commit names.
#'
#' @param conn A `datom_conn` object with a local path.
#' @return A named list of rows, empty when the clone has no manifest.
#' @keywords internal
.datom_clone_manifest_rows <- function(conn) {
  read <- .datom_read_manifest(conn, "clone", operation = "write")
  if (isTRUE(read$absent)) return(list())
  if (!isTRUE(read$ok)) stop(read$error)
  read$manifest$artifacts %||% list()
}


#' The Artifacts Whose Committed Version Readers Cannot See
#'
#' Those whose clone row names a different `current_version` from the stored
#' row ("differs", not "behind": a revert to earlier content is a different row,
#' not an older one). A version in unpushed commits is always among them,
#' because the manifest is published last. Two more cases count as differing:
#' an absent stored manifest (every clone row), and a stored row for an artifact
#' the clone does not have, which a whole-manifest upload would otherwise drop
#' without a word.
#'
#' @param clone_rows The clone's rows ([.datom_clone_manifest_rows()]).
#' @param stored What [.datom_stored_manifest()] read.
#' @return Artifact names.
#' @keywords internal
.datom_unpublished_artifacts <- function(clone_rows, stored) {
  in_clone <- names(clone_rows)
  if (identical(stored$status, "absent")) return(in_clone)

  stored_rows <- stored$rows
  differ <- in_clone[purrr::map_lgl(in_clone, function(nm) {
    !identical(clone_rows[[nm]]$current_version, stored_rows[[nm]]$current_version)
  })]

  c(differ, setdiff(names(stored_rows), in_clone))
}


#' Does an Artifact's History in the Clone Name a Version
#'
#' @param path Repository path.
#' @param name Artifact name.
#' @param version The version to look for.
#' @return `TRUE` or `FALSE`; `FALSE` when the clone has no history for it.
#' @keywords internal
.datom_history_contains <- function(path, name, version) {
  history <- .datom_read_clone_json(path, paste0(name, "/version_history.json"))
  version %in% .datom_history_versions(history %||% list())
}


#' Publish Artifacts From the Clone, Manifest Last
#'
#' **The one publish path.** A write's own publish (after its push), heal's
#' publish, the metadata-only route and the repair all go through it, so the
#' order readers depend on lives in one place. For each artifact, the documents as committed
#' in the clone go up through [.datom_push_metadata_s3()]: the snapshot, the
#' history, then `metadata.json` last. Then the manifest, last of all, and only
#' if every artifact's documents went up: a manifest published after a failure
#' would name a version whose `metadata.json` is old, and heal, which compares
#' manifest rows, would then see nothing to finish.
#'
#' **The snapshot is keyed by the document's own version**, computed from the
#' `metadata.json` being published. That is the key the write itself used: the
#' committed file is the document the write computed its version from, and the
#' fields added after (`parquet_sha`, carried unknown fields) are outside
#' identity. A document committed by hand gets one snapshot under its own key;
#' no snapshot is ever overwritten with a document that does not hash to it.
#'
#' **`recheck_manifest`**: the manifest goes up as the clone holds it, every row
#' at once. A write whose push pulled in a teammate's commit would then name
#' the teammate's version, which may not be in storage yet. So when that pull
#' moved HEAD, the stored manifest is read once more, and the manifest goes up
#' only if every row but those published here agrees with it; otherwise it is
#' held back with a warning naming the fix.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param names Artifacts to publish. Empty publishes the manifest only.
#' @param commit_sha The commit a write just made, for its one artifact's
#'   history; `NULL` (heal, the repair) works every entry's commit out from git,
#'   which names the first commit that produced each version.
#' @param recheck_manifest See above.
#' @param on_failure `"raise"` (a write's own publish) re-signals the first
#'   failure as it was raised; `"return"` hands the failures back, for heal's
#'   stop and the repair's report.
#' @return Invisibly, a list with `published` (versions, named by artifact),
#'   `failed` (conditions, named by artifact) and `manifest` (`"published"`,
#'   `"held_back"`, `"not_reached"` or `"none"` when the clone has no manifest).
#' @keywords internal
.datom_publish_artifacts <- function(conn, names, commit_sha = NULL,
                                     recheck_manifest = FALSE,
                                     on_failure = c("raise", "return")) {
  on_failure <- match.arg(on_failure)
  if (!is.null(commit_sha) && length(names) != 1L) {
    cli::cli_abort(
      "Internal error: a commit can be named for one artifact's publish only.",
      class = "datom_internal_error"
    )
  }

  outcomes <- purrr::map(names, function(nm) {
    tryCatch(
      list(version = .datom_publish_documents(conn, nm, commit_sha)),
      error = function(e) list(error = e)
    )
  })
  outcomes <- stats::setNames(outcomes, names)
  failed <- purrr::compact(purrr::map(outcomes, "error"))
  published <- unlist(purrr::compact(purrr::map(outcomes, "version")))

  manifest <- if (length(failed) == 0L) {
    .datom_publish_manifest(conn, names, recheck = recheck_manifest)
  } else {
    "not_reached"
  }

  if (length(failed) > 0L && identical(on_failure, "raise")) stop(failed[[1L]])

  invisible(list(
    published = published %||% character(),
    failed = failed,
    manifest = manifest
  ))
}


#' Publish One Artifact's Committed Documents
#'
#' @param conn A `datom_conn` object with a local path.
#' @param name Artifact name.
#' @param commit_sha See [.datom_publish_artifacts()].
#' @return The version published: the document's own.
#' @keywords internal
.datom_publish_documents <- function(conn, name, commit_sha = NULL) {
  meta <- .datom_read_clone_json(conn$path, paste0(name, "/metadata.json"))
  if (is.null(meta)) {
    cli::cli_abort("The clone holds no {.file {name}/metadata.json} to publish.")
  }
  version <- .datom_compute_metadata_sha(meta)
  .datom_push_metadata_s3(conn, name, meta, version, commit_sha = commit_sha)
  version
}


#' Publish the Clone's Manifest
#'
#' The clone's manifest in the current format, as every write leaves it. See
#' [.datom_publish_artifacts()] for `recheck`.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param own The artifacts just published; their rows are the ones expected to
#'   differ from storage's.
#' @param recheck `TRUE` to compare every other row with storage first.
#' @return `"published"`, `"held_back"` or `"none"`.
#' @keywords internal
.datom_publish_manifest <- function(conn, own, recheck = FALSE) {
  read <- .datom_read_manifest(conn, "clone", operation = "write")
  if (isTRUE(read$absent)) return("none")
  if (!isTRUE(read$ok)) stop(read$error)

  if (isTRUE(recheck)) {
    stored <- .datom_stored_manifest(conn)
    # Storage was read at the start of the command and took this write's
    # documents moments ago, so this is an outage (or a damaged file) in the
    # seconds since. Nothing can be compared, so the manifest is held back, and
    # the warning says so rather than naming a version storage lacks.
    if (identical(stored$status, "unreadable")) {
      .datom_warn_manifest_held_back(character(), own, unreadable = stored$error)
      return("held_back")
    }
    disagree <- setdiff(
      .datom_unpublished_artifacts(read$manifest$artifacts %||% list(), stored),
      own
    )
    if (length(disagree) > 0L) {
      .datom_warn_manifest_held_back(disagree, own)
      return("held_back")
    }
  }

  .datom_notify_manifest_upgraded(read$declared, "data storage")
  .datom_storage_write_json_at(conn, ".metadata/manifest.json", read$manifest)
  "published"
}


#' Write One Document to Storage, Saying Which on Failure
#'
#' [.datom_storage_write_json()], with the key added to a failure's condition
#' (`datom_storage_key`) and the condition re-signalled otherwise unchanged, so
#' a caller that reports the failure can name the file, and one that only lets
#' it through sees the error it always saw.
#'
#' @param conn A `datom_conn` object.
#' @param key Relative storage key.
#' @param data An R list to serialize to JSON.
#' @return Invisible `TRUE` on success.
#' @keywords internal
.datom_storage_write_json_at <- function(conn, key, data) {
  tryCatch(
    .datom_storage_write_json(conn, key, data),
    error = function(e) {
      e$datom_storage_key <- key
      stop(e)
    }
  )
}


#' Read One of datom's Own JSON Files in the Clone
#'
#' **The one reader for an artifact's `metadata.json` and
#' `version_history.json` in the clone**, used by heal's publish, the history
#' lookups, the local metadata write and the manifest row's version count. A
#' file that does not parse (only possible when committed outside datom: an
#' uncommitted one is reset by heal) stops with one condition class and one
#' message giving the way out. `.datom_prior_metadata()` keeps its own reader on
#' purpose: it treats a broken `metadata.json` as absent, since the write
#' replaces it.
#'
#' @param path Repository path.
#' @param rel The file, relative to the repo root (`"dm/version_history.json"`).
#' @return The parsed document (`simplifyVector = FALSE`), or `NULL` when the
#'   file does not exist.
#' @keywords internal
.datom_read_clone_json <- function(path, rel) {
  file <- fs::path(path, rel)
  if (!fs::file_exists(file)) return(NULL)
  tryCatch(
    jsonlite::read_json(file),
    error = function(e) .datom_stop_clone_file_unreadable(path, rel, e)
  )
}


#' Stop on One of datom's Own Files That Does Not Parse
#'
#' The way out restores **all** of the artifact's datom files from one commit:
#' restoring only the broken one would leave `metadata.json` describing a
#' version its history no longer records. The restore is committed with plain
#' git, because `datom_repo_commit()` stops on datom's own uncommitted files.
#'
#' @param path Repository path.
#' @param rel The file that does not parse.
#' @param e The parser's condition.
#' @return Does not return.
#' @keywords internal
.datom_stop_clone_file_unreadable <- function(path, rel, e) {
  artifact <- dirname(rel)
  files <- paste0(artifact, "/", .datom_artifact_own_files)
  files <- files[fs::file_exists(fs::path(path, files))]
  log_cmd <- paste0("git log -- ", artifact, "/")
  checkout_cmd <- paste(c("git checkout <commit> --", files), collapse = " ")
  why <- .datom_one_line(e)

  cli::cli_abort(
    c(
      "{.file {rel}} does not parse.",
      "x" = "{why}",
      "i" = "Restore {.val {artifact}}'s datom files from a commit where they \\
             parse ({.code {log_cmd}} lists them): {.code {checkout_cmd}}, then \\
             {.code git commit}, and re-run."
    ),
    class = "datom_clone_file_unreadable"
  )
}


#' A Condition's Message on One Line, Without Styling
#'
#' @param e A condition.
#' @return One string.
#' @keywords internal
.datom_one_line <- function(e) {
  gsub("\\s+", " ", trimws(cli::ansi_strip(conditionMessage(e))))
}


#' Stop on Another Artifact's Committed Work Storage Does Not Match
#'
#' Heal's publish acts only on the command's own artifacts. A stored row that
#' differs from the clone's can be this clone's unfinished write (committed,
#' not published) or a teammate's newer publish this clone has not pulled; a
#' stored row the clone lacks can be a teammate's new artifact. The message
#' gives the way out for both.
#'
#' @param others The artifacts.
#' @param in_clone The artifacts the clone's manifest names.
#' @return Does not return.
#' @keywords internal
.datom_stop_unpublished_others <- function(others, in_clone) {
  details <- purrr::map_chr(others, function(a) {
    if (a %in% in_clone) {
      cli::format_inline("{.val {a}}: storage and this clone name different \\
                          versions of it")
    } else {
      cli::format_inline("{.val {a}}: storage names it, this clone does not \\
                          have it")
    }
  })

  # cli resolves a plural within one bullet, so each bullet names its count.
  n <- length(others)
  cli::cli_abort(
    c(
      "{.val {others}} {?has/have} unfinished work this command does not finish.",
      purrr::set_names(details, rep("*", length(details))),
      "i" = "Nothing was pushed or published.",
      "i" = "Run {.code datom_validate(fix = TRUE)} to publish this clone's \\
             {cli::qty(n)}version{?s} of {?it/them}, then re-run this command.",
      "i" = "If a teammate has just written {cli::qty(n)}{?it/them}, a re-run \\
             may be enough: a write pulls first."
    ),
    class = "datom_unfinished_work"
  )
}


#' Stop When Storage Names a Version This Clone Has Never Seen
#'
#' @param unseen The command's own artifacts in that state.
#' @param stored_rows The stored manifest's rows.
#' @return Does not return.
#' @keywords internal
.datom_stop_stored_version_unseen <- function(unseen, stored_rows) {
  details <- purrr::map_chr(unseen, function(a) {
    version <- substr(stored_rows[[a]]$current_version, 1L, 8L)
    cli::format_inline("Storage names version {.val {version}} of {.val {a}}, \\
                        which this clone has not seen.")
  })

  cli::cli_abort(
    c(
      purrr::set_names(details, rep("x", length(details))),
      "i" = "Nothing was pushed or published.",
      "i" = "Re-run: a write pulls first, which brings in a teammate's newer \\
             version. If this persists, run {.code datom_validate(fix = TRUE)}, \\
             which publishes this clone's version in its place."
    ),
    class = "datom_stored_version_unseen"
  )
}


#' Say Which Stored Versions the Repair Replaced or Dropped
#'
#' The repair overrides the containment check rather than stop on it, because
#' a state the check refuses would otherwise lock the project: every write of
#' another artifact names the repair, and the repair would stop too. So it says
#' what it overrode.
#'
#' @param own Every artifact the repair publishes.
#' @param unseen Those whose stored version this clone has never seen.
#' @param stored_rows The stored manifest's rows.
#' @param clone_rows The clone's rows.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_warn_stored_replaced <- function(own, unseen, stored_rows, clone_rows) {
  version_of <- function(row) substr(row$current_version %||% "", 1L, 8L)

  purrr::walk(setdiff(own, names(clone_rows)), function(a) {
    cli::cli_warn(
      "Storage named {.val {a}}, which this clone does not have; its row is \\
       dropped from the manifest. Its documents stay in storage, named by \\
       nothing.",
      class = "datom_heal_override"
    )
  })
  purrr::walk(intersect(unseen, names(clone_rows)), function(a) {
    old <- version_of(stored_rows[[a]])
    new <- version_of(clone_rows[[a]])
    cli::cli_warn(
      "Storage named version {.val {old}} of {.val {a}}, which this clone has \\
       not seen; published this clone's version {.val {new}} in its place.",
      class = "datom_heal_override"
    )
  })
  invisible(NULL)
}


#' Stop When the Stored Manifest Cannot Be Read
#'
#' @param e The condition the read raised.
#' @return Does not return.
#' @keywords internal
.datom_stop_stored_manifest_unreadable <- function(e) {
  why <- .datom_one_line(e)
  cli::cli_abort(
    c(
      "Could not read the stored manifest, so datom cannot tell what storage is \\
       missing.",
      "x" = "{why}",
      "i" = "Nothing was pushed or published.",
      "i" = "Re-run once storage is reachable. If the file itself is damaged, \\
             run {.code datom_validate(fix = TRUE)}, which publishes it again \\
             from this clone."
    ),
    class = "datom_stored_manifest_unreadable",
    parent = e
  )
}


#' Stop When Heal Could Not Publish an Earlier Write
#'
#' A file in the clone that does not parse already carries the message with its
#' way out, so that condition goes through unchanged.
#'
#' @param failed The failures, named by artifact.
#' @return Does not return.
#' @keywords internal
.datom_stop_publish_failed <- function(failed) {
  unreadable <- purrr::keep(failed, ~ inherits(.x, "datom_clone_file_unreadable"))
  if (length(unreadable) > 0L) stop(unreadable[[1L]])

  details <- purrr::imap_chr(failed, function(e, a) {
    key <- e$datom_storage_key
    msg <- .datom_one_line(e)
    if (is.null(key)) {
      cli::format_inline("{.val {a}}: {msg}")
    } else {
      cli::format_inline("{.val {a}}, at {.file {key}}: {msg}")
    }
  })
  names_failed <- names(failed)

  # The original conditions ride along as `failed`, for a caller (or a test)
  # that needs the cause; the message already states it.
  cli::cli_abort(
    c(
      "Could not finish publishing {.val {names_failed}}, committed by an \\
       earlier run.",
      purrr::set_names(details, rep("x", length(details))),
      "i" = "The manifest was not published, so readers still see the previous \\
             version.",
      "i" = "Re-run once storage is reachable."
    ),
    failed = failed,
    class = "datom_publish_failed"
  )
}


#' Warn That a Write Held Back the Manifest
#'
#' Two causes, each named as it is: the commits the write's push brought in
#' name versions storage does not hold yet, or storage's manifest could not be
#' read to check them. The way out is the same.
#'
#' @param disagree The artifacts whose rows disagree with storage, other than
#'   the write's own; empty when the stored manifest could not be read.
#' @param own The artifacts the write published.
#' @param unreadable The condition the read of the stored manifest raised, or
#'   `NULL` when it was read.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_warn_manifest_held_back <- function(disagree, own, unreadable = NULL) {
  published <- c(
    "i" = "{.val {own}} is published: a read gets the new version, while \\
           {.fn datom_list} names the previous one until the manifest is \\
           published."
  )
  why <- if (!is.null(unreadable)) .datom_one_line(unreadable)

  bullets <- if (is.null(unreadable)) {
    n <- length(disagree)
    c(
      "Did not publish the manifest: the commits this write's push brought in \\
       name {cli::qty(n)}{?a version/versions} of {.val {disagree}} that \\
       storage does not hold yet.",
      published,
      "i" = "Run {.code datom_validate(fix = TRUE)} to publish it. Until then, \\
             writes of other artifacts stop and name that fix."
    )
  } else {
    c(
      "Did not publish the manifest: this write's push brought in commits, and \\
       storage's manifest could not be read to check them against it.",
      "x" = "{why}",
      published,
      "i" = "Once storage is reachable, run {.code datom_validate(fix = TRUE)} \\
             to publish it. Until then, writes of other artifacts stop and \\
             name that fix."
    )
  }

  cli::cli_warn(
    bullets,
    # Carried for datom_sync(), which stops after such a write and names them.
    disagree = disagree,
    unreadable = why,
    class = "datom_manifest_held_back"
  )
  invisible(NULL)
}


# --- The pull a write makes --------------------------------------------------------

#' The Pull a Write Makes Before Its Own Work
#'
#' The write commands' step between heal's reset and the command's own work
#' (requirements R3.7): [.datom_git_pull()], then, only when HEAD moved, the
#' format check on every artifact. A merge -- a fast-forward included -- may have
#' brought documents from a newer datom, or a raised writer floor in
#' `project.yaml`. Without a merge nothing new arrived, and the check at the
#' start of the write already read the command's own artifact.
#'
#' Not part of heal: removing heal would leave this in place.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param reset The artifacts heal's reset has just put back, so a stop here
#'   says so rather than "datom changed nothing".
#' @return Invisibly, whether HEAD moved.
#' @keywords internal
.datom_pull_before_write <- function(conn, reset = character()) {
  moved <- .datom_git_pull(conn$path, pat = conn$github_pat, reset = reset)
  if (isTRUE(moved)) .datom_check_write_entry(conn, NULL)
  invisible(moved)
}


# --- Unfinished work, seen from the clone alone -----------------------------------

#' The Artifacts Whose Files the Commits Not Yet Pushed Change
#'
#' What the scan's `unpushed` status is read from (requirements R4.2), and what
#' the push commands' message will name (R3.6): the artifacts whose datom files
#' differ between HEAD and the last commit it shares with its upstream branch.
#' Taken from that common commit rather than from the upstream tip, so commits
#' the remote holds and the clone lacks (a teammate's, already fetched) are not
#' counted as this clone's. The net change, not each commit's: a file changed and
#' then changed back by unpushed commits is not counted, since the remote already
#' has what HEAD holds.
#'
#' **Local refs only**: no fetch, so it costs no network and answers from what the
#' clone last saw of the remote.
#'
#' **With no upstream branch it names nothing.** Without one datom cannot tell
#' what the remote holds, and on the project's branch that state arises only when
#' init failed to set one (it warns). The scan then shows such a table
#' `unchanged`, and [datom_sync()] still finishes it: heal's publish pushes first
#' when there is no upstream ([.datom_heal_publish()]).
#'
#' @param path Repository path.
#' @return Artifact names, possibly empty.
#' @keywords internal
.datom_pushed_artifacts <- function(path) {
  repo <- git2r::repository(path)
  upstream <- tryCatch(
    git2r::branch_get_upstream(git2r::repository_head(repo)),
    error = function(e) NULL
  )
  if (is.null(upstream)) return(character())

  head_sha <- .datom_git_head_sha(repo)
  tip <- git2r::branch_target(upstream)
  # Level with the remote, or behind it: nothing of this clone's is unpushed.
  if (.datom_git_contains(repo, tip, head_sha)) return(character())

  head_commit <- git2r::lookup(repo, head_sha)
  base <- git2r::merge_base(head_commit, git2r::lookup(repo, tip))
  if (is.null(base)) return(character())

  changes <- git2r::diff(git2r::tree(base), git2r::tree(head_commit))
  files <- unique(unlist(lapply(changes$files, function(f) {
    c(f$old_file, f$new_file)
  })))
  owned <- files[basename(files) %in% .datom_artifact_own_files]

  intersect(
    unique(dirname(owned)),
    .datom_clone_artifact_names(list(path = path))
  )
}


#' The Commit a Clone's HEAD Points At
#'
#' Taken by [datom_sync()] before each table's write, for
#' [.datom_write_left_changes()] to compare with afterwards.
#'
#' @param path Repository path.
#' @return The SHA, or `NA_character_` in a repo with no commits.
#' @keywords internal
.datom_clone_head <- function(path) {
  .datom_git_head_sha(git2r::repository(path))
}


#' Did a Failed Write Leave Anything in the Clone
#'
#' [datom_sync()] asks this after one table's write fails, on the error path only
#' (requirements R4.6). The sync heals once for the whole batch, so no later
#' table's write checks for another table's unfinished work: a later commit would
#' take the failed table's uncommitted manifest row, and a later manifest upload
#' would name a version whose `metadata.json` is not in storage. So the sync stops
#' when the failed write had begun changing the clone, and carries on only when
#' it had not.
#'
#' Two signs, either enough: datom's own files differ from the last commit (the
#' write stopped before its commit, or during it), or HEAD is no longer the
#' commit it was before the write (it committed, and stopped at the push or in
#' storage). Before the write both were clean: heal had just reset, or stopped
#' on, any uncommitted datom file, and each earlier table's write either finished
#' or stopped the sync.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param head_before What [.datom_clone_head()] returned before the write.
#' @return `TRUE` or `FALSE`.
#' @keywords internal
.datom_write_left_changes <- function(conn, head_before) {
  if (!identical(.datom_clone_head(conn$path), head_before)) return(TRUE)
  length(.datom_unfinished_files(conn)) > 0L
}


# --- The git and config commands ------------------------------------------------

#' Stop a Commit That Would Take datom's Own Uncommitted Files
#'
#' [datom_repo_commit()] never commits a datom write that never committed
#' (requirements R3.5, D9). Its files, left by a write that stopped before its
#' commit, would otherwise become a version nobody published, with half its
#' steps done. The command acts on an artifact it is not writing, so it stops
#' rather than reset them (D14 principle 8): the artifact's own write, re-run,
#' finishes it, and `datom_validate(fix = TRUE)` discards the changes.
#'
#' **What the commit would take** is worked out the way git stages, before
#' anything is staged:
#' - with `paths = NULL`, everything;
#' - a path that is the file, or a folder above it (`"dm"`, `"dm/"`, `"."`);
#' - **a file already staged**, whatever `paths` says: a commit takes the whole
#'   index, so a datom file staged earlier (by the user's `git add`, or by a
#'   write stopped between staging and committing) goes into a commit of
#'   `paths = "build.R"` too.
#'
#' A leading `./` is dropped before matching. `git2r::add()` stages nothing for
#' `"./dm"`, so this stops a commit git would have left `dm` out of: a stop with
#' a way out, rather than a miss. A commit whose paths take none of these files
#' goes ahead, and datom's files stay as they are.
#'
#' One `git status`, shared with [.datom_unfinished_files()].
#'
#' @param conn A `datom_conn` object with a local path.
#' @param paths The command's `paths`: `NULL`, or repo-relative paths.
#' @return Invisibly `NULL` when the commit takes none of datom's uncommitted
#'   files; otherwise does not return.
#' @keywords internal
.datom_stop_commit_of_unfinished <- function(conn, paths = NULL) {
  st <- git2r::status(
    git2r::repository(conn$path),
    staged = TRUE, unstaged = TRUE, untracked = TRUE
  )
  unfinished <- .datom_unfinished_files(conn, st)
  if (length(unfinished) == 0L) return(invisible(NULL))

  staged <- unname(unlist(st$staged, use.names = FALSE))
  taken <- unfinished[unfinished %in% staged |
                        .datom_paths_take(paths, unfinished)]
  if (length(taken) == 0L) return(invisible(NULL))

  owners <- .datom_unfinished_owners(conn, taken)
  .datom_stop_unfinished_files(
    owners$touched, owners$by_artifact, owners$rows, owners$unknown_rows
  )
}


#' Which Files a Commit's Paths Would Stage
#'
#' @param paths `NULL` (everything), or repo-relative paths: a file, or a
#'   folder whose files it stages.
#' @param files Repo-relative paths with forward slashes.
#' @return A logical vector along `files`.
#' @keywords internal
.datom_paths_take <- function(paths, files) {
  if (is.null(paths)) return(rep(TRUE, length(files)))

  p <- gsub("\\\\", "/", paths)
  p <- sub("^(\\./)+", "", p)
  p <- sub("/+$", "", p)
  everything <- any(p %in% c("", "."))

  purrr::map_lgl(files, function(f) {
    everything || any(f == p | startsWith(f, paste0(p, "/")))
  })
}


#' Say That a Push Carried Versions Readers Cannot See Yet
#'
#' The git and config commands ([datom_repo_push()], [datom_repo_commit()],
#' [datom_repo_attach_governance()], [datom_repo_set_data_store()]) push and do
#' not publish (requirements R3.6, D10). When the commits they push hold a datom
#' version, this names each such artifact and the way to publish it. Every
#' version in commits being pushed is unpublished by definition, since a write
#' publishes only after its push, so this needs no storage read: the caller
#' takes the names from [.datom_pushed_artifacts()] **before** the push, while
#' the commits are still the clone's alone.
#'
#' A message rather than a warning: the push did what was asked. The state it
#' leaves is not hidden either way, since a write of any other artifact then
#' stops, naming the same fix.
#'
#' @param names The artifacts whose datom files the pushed commits change.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_note_pushed_unpublished <- function(names) {
  if (length(names) == 0L) return(invisible(NULL))
  n <- length(names)

  cli::cli_inform(
    c(
      "!" = "Pushed a new version of {.val {names}} that readers cannot see \\
             yet: it is on the git remote but not in storage, and this command \\
             does not publish.",
      "i" = "{cli::qty(n)}Run {.code datom_validate(fix = TRUE)}, or write \\
             {?that artifact/each of them} again, to publish {?it/them}. Until \\
             then, a write of any other table or set stops."
    ),
    class = "datom_pushed_unpublished",
    pushed = names
  )
  invisible(NULL)
}
