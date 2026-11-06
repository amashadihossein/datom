# Healing what an interrupted command left behind.
#
# Every command that changes things starts the same way: the merge check, heal's
# reset, the command's own pull, and then the command's own work. Heal is
# datom's self-healing step: re-running a command that broke finishes the job,
# and it lives here, once, rather than in each command.
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

#' Stop While a Merge Is in Progress
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
#' - **A merge of the remote branch** stops with the files that still conflict
#'   and how to finish: take the remote copy of all of each conflicted
#'   artifact's datom files, resolve your own files, re-run.
#'
#' Without the first stop datom would commit, and the next push share, a merge
#' the user started (one made with `--no-commit` to inspect it). Without the
#' second, heal's reset would put a file the user had resolved back to the local
#' side, and the next pull would conflict again.
#'
#' @param path Repository path.
#' @return Invisibly `NULL` when no merge is in progress; otherwise does not
#'   return.
#' @keywords internal
.datom_check_merge <- function(path) {
  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  # `repo$path` is the git directory, which is also right for a worktree.
  merge_head_file <- fs::path(repo$path, "MERGE_HEAD")
  if (!fs::file_exists(merge_head_file)) return(invisible(NULL))

  merge_head <- trimws(readLines(merge_head_file, n = 1L, warn = FALSE))

  if (!.datom_merge_is_of_upstream(repo, merge_head)) .datom_stop_other_merge(repo)

  # A merge of the remote branch. Finishing it by rebuilding the manifest, once
  # nothing but the manifest conflicts, is not built yet; until it is, every
  # such merge stops here with the instructions for finishing it.
  .datom_stop_merge_conflict(path)
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


# --- Heal ------------------------------------------------------------------------

#' Heal What an Interrupted Write Left Behind
#'
#' Runs in exactly one place per route, after the checks that need no storage
#' state heal can change and before change detection. It starts with the merge
#' check, then resets what never committed (requirements R2.4, R3.1). Each step
#' runs only when its own check finds something: here one `git status`.
#'
#' **What heal repairs:**
#' - the artifacts the command writes (`artifact`): their datom files left by a
#'   write that broke before its commit are put back to the last commit, with a
#'   message, and the command then writes them again;
#' - with `all = TRUE` (the repair), every artifact's, with a warning naming
#'   each, since that write is not run again.
#'
#' **What heal leaves:**
#' - **another artifact's unfinished work**: a write never acts on an artifact it
#'   is not writing. It stops before anything changes, naming the artifact and
#'   `datom_validate(fix = TRUE)`;
#' - a merge in progress: the merge check stops first ([.datom_check_merge()]);
#' - every file datom does not own: `project.yaml`, a set write's
#'   `include_paths`, `input_files/`, and a user's own `app/metadata.json` (only
#'   folders the manifest names, or whose `metadata.json` declares a datom
#'   `hash_algo`, are artifacts; see [.datom_clone_artifact_names()]);
#' - damage a released datom left, files changed in storage by hand.
#'
#' The shared `.datom/manifest.json` is reset only when every row differing from
#' HEAD's belongs to an artifact the command writes; a differing row of any other
#' artifact is that artifact's unfinished work, and stops the command.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param artifact Names of the artifacts the command is writing, or `NULL` for
#'   none (the metadata-only route rewrites no file, so any uncommitted change
#'   to one stops it).
#' @param all `TRUE` for the repair: act on every artifact.
#' @return Invisibly, a list with `reset` (the artifacts whose files were put
#'   back) and `published` (empty: publishing is not built here yet).
#' @keywords internal
.datom_heal <- function(conn, artifact = NULL, all = FALSE) {
  .datom_check_merge(conn$path)

  # The gate is this one `git status`. The reset behind it would find nothing on
  # a clean clone either way, so the gate's only observable is cost; no test can
  # tell it is there, and none tries.
  unfinished <- .datom_unfinished_files(conn)
  reset <- if (length(unfinished) > 0L) {
    .datom_reset_unfinished(conn, unfinished, artifact = artifact, all = all)
  } else {
    character()
  }

  invisible(list(reset = reset, published = character()))
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
#' @return Repo-relative paths with forward slashes, possibly empty.
#' @keywords internal
.datom_unfinished_files <- function(conn) {
  repo <- git2r::repository(conn$path)
  st <- git2r::status(repo, staged = TRUE, unstaged = TRUE, untracked = TRUE)

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
#' not the command's own (and `all` is `FALSE`), the command stops naming them.
#' Otherwise every file is put back to the last commit: unstaged, then checked
#' out from HEAD, or deleted when HEAD does not hold it (an artifact's first
#' write), with its folder removed once empty.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param unfinished What [.datom_unfinished_files()] found.
#' @param artifact,all See [.datom_heal()].
#' @return The artifacts whose files were put back.
#' @keywords internal
.datom_reset_unfinished <- function(conn, unfinished, artifact = NULL,
                                    all = FALSE) {
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

  touched <- union(names(by_artifact), rows)
  own <- if (isTRUE(all)) touched else intersect(touched, artifact)
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
    if (isTRUE(all) && !(a %in% artifact)) {
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


#' The Manifest Rows That Differ From HEAD's
#'
#' Rows are compared as parsed from each copy, by artifact name: a row added,
#' removed or rewritten differs. A write rewrites only its own row (and the
#' summary and timestamp, which belong to no artifact), so the names returned
#' are the artifacts whose writes touched the manifest.
#'
#' @param conn A `datom_conn` object with a local path.
#' @return Artifact names; `NA_character_` when either copy cannot be parsed, so
#'   the changes cannot be tied to any artifact.
#' @keywords internal
.datom_manifest_rows_changed <- function(conn) {
  head_rows <- .datom_manifest_rows(
    .datom_git_head_file(conn$path, ".datom/manifest.json")
  )
  wt_path <- fs::path(conn$path, ".datom", "manifest.json")
  wt_rows <- .datom_manifest_rows(
    if (fs::file_exists(wt_path)) {
      paste(readLines(wt_path, warn = FALSE), collapse = "\n")
    }
  )
  if (is.null(head_rows) || is.null(wt_rows)) return(NA_character_)

  nms <- union(names(head_rows), names(wt_rows))
  nms[!purrr::map_lgl(nms, function(n) identical(head_rows[[n]], wt_rows[[n]]))]
}


#' A Manifest's Rows, From Its Text
#'
#' @param text The manifest as one string, or `NULL` when there is none.
#' @return A named list of rows (empty when there is no manifest), or `NULL`
#'   when the text does not parse.
#' @keywords internal
.datom_manifest_rows <- function(text) {
  if (is.null(text)) return(list())
  doc <- tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.list(doc)) return(NULL)
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
#' @return Invisibly, whether HEAD moved.
#' @keywords internal
.datom_pull_before_write <- function(conn) {
  moved <- .datom_git_pull(conn$path, pat = conn$github_pat)
  if (isTRUE(moved)) .datom_check_write_entry(conn, NULL)
  invisible(moved)
}
