# The version-to-commit link: which commit first produced a given version.
#
# WHY THIS IS A FILE OF ITS OWN, and not three lines inside the uploader. Three
# functions upload an artifact's `version_history.json` to storage, reached from
# four public entry points, and the clone's copy of that file can never carry
# `commit_sha` -- it is inside the commit it would name. So each of those three
# uploads is a chance to erase the field, and the ordinary write is the one that
# does it first: it sends the clone's copy wholesale, so the second write of an
# artifact would drop the first version's commit id with no repair involved.
# One helper, called by all three, because three copies of "keep `commit_sha`"
# are three places to lose it.
#
# THE ONE RULE: `commit_sha` is DERIVED, NEVER AUTHORED. No public verb accepts
# it. The write path hands in the commit it just made because it already holds
# it; every other gap is worked out from git. Keeping what storage already has is
# not enough on its own -- an older datom that has never heard of the field
# strips it through any of the three doors, and nothing refuses that build,
# because version-history entries have no field vocabulary to trip (unlike
# `metadata.json` and the manifest). That is tolerable only because the value can
# be recomputed **from a complete clone** -- and only if something recomputes.
# Hence both halves below: merge what storage holds, then derive what is still
# missing. The qualifier is not decoration: a shallow clone or a rewritten history
# cannot attribute a version, and for those the stored copy is the only copy.
#
# WHICH SILENCES ARE SAFE, since this file has several. Every give-up in the git
# walk is an ABSENCE signal: it leaves a gap that had no stored value either --
# that is why it was a gap -- so nothing is lost and nothing needs saying. The one
# exception is failing to READ the stored copy, which is a LOSS signal: storage
# held values nothing else can reproduce, and the upload replaces that file
# wholesale. That case is reported. Do not tidy the two into one handler.
#
# WHAT IT COSTS. Derivation runs per MISSING entry, so a repo upgrading to a
# build that writes the field backfills its back history once and then settles at
# nothing per write -- the version being written arrives with its commit already
# in hand. A value git cannot reproduce (shallow clone, rewritten history) is
# omitted rather than recorded empty, and such an artifact pays one git walk per
# write.
#
# NOTHING HERE TOUCHES THE CLONE. The merge happens in memory on the way to
# storage; the tracked file is left exactly as committed.


#' Add `commit_sha` to a History on Its Way to Storage
#'
#' Returns `history` with a `commit_sha` on every entry whose producing commit is
#' known, and unchanged entries where it is not. Called by each of the three
#' functions that upload `version_history.json`.
#'
#' Two sources, in this order:
#'
#' 1. **What storage already holds.** Cheap, and it is the only source for a
#'    value git can no longer produce.
#' 2. **Derived from git**, for the entries still missing after step 1 -- and
#'    only then, so a repo whose history is complete pays no git walk.
#'
#' `version` / `commit_sha` are the write path's shortcut: the caller has just
#' made the commit that produced that version, so the walk is not needed for it.
#' They are ignored when storage already records a commit for that version, since
#' the recorded value is the **first** commit that introduced it and a later
#' re-upload must not repoint it.
#'
#' **When step 1 failed rather than found nothing, and something was lost by it,
#' this says so.** The two states are not interchangeable: nothing to merge is the
#' ordinary first write, whereas a stored copy that would not read means the
#' values only storage had are now unknown, and the upload below replaces the file
#' wholesale. The warning is raised only when a version actually ends up with no
#' commit -- if git could attribute every one of them, the same values were
#' reconstructed and nothing is degraded.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param name Artifact name, of either kind -- `version_history.json` is shared.
#' @param history The clone's parsed history, newest-first, as a list of entries.
#' @param version The version this write produced, or `NULL`.
#' @param commit_sha The commit that produced `version`, or `NULL`. A caller that
#'   made no commit passes `NULL` and every entry is derived.
#' @return `history` with `commit_sha` filled in where it is known.
#' @keywords internal
.datom_history_with_commit_shas <- function(conn, name, history,
                                           version = NULL, commit_sha = NULL) {
  if (!is.list(history) || length(history) == 0L) return(history)

  stored <- .datom_stored_commit_shas(conn, name)
  known <- stored$shas

  if (.datom_is_text_scalar(version) && .datom_is_text_scalar(commit_sha) &&
      !(version %in% names(known))) {
    known[[version]] <- commit_sha
  }

  versions <- stats::na.omit(.datom_history_versions(history))
  if (length(setdiff(versions, names(known))) > 0L) {
    derived <- .datom_git_commit_shas_by_version(conn$path, name)
    known <- c(known, derived[setdiff(names(derived), names(known))])
  }

  out <- purrr::map(history, function(entry) {
    if (!is.list(entry)) return(entry)
    v <- entry$version
    if (!.datom_is_text_scalar(v) || !(v %in% names(known))) return(entry)
    # Assigned, never declared: `jsonlite` writes a NULL element as `{}`, so an
    # entry whose commit is unknown must omit the key rather than carry an empty
    # object where a sha belongs.
    entry$commit_sha <- known[[v]]
    entry
  })

  lost <- if (isTRUE(stored$unreadable)) {
    setdiff(versions, names(known))
  } else {
    character()
  }
  if (length(lost) > 0L) .datom_warn_commit_shas_lost(name, lost)

  out
}


#' Say Which Commit Links Went Unrecorded, and Why
#'
#' Split out so the wording lives next to the reasoning rather than inside a
#' branch. A warning rather than a refusal, and the reason is that refusing would
#' deadlock the only route out: the repair verb goes through the same helper, so a
#' stored history that will not parse could never be replaced. That file is a
#' projection for git-less readers and rebuilding it is exactly what the repair is
#' for -- what must not happen is rebuilding it in silence.
#'
#' **It says that the unreadable copy is being replaced**, because of which cause
#' is the likelier one. The two are indistinguishable here, but a reachable store
#' holding bad bytes is more plausible than one that refuses a read and accepts a
#' write -- and in that case this very operation overwrites the evidence. Somebody
#' who would have gone looking should be told it will not be there. Worded as what
#' this write does rather than as a completed fact: the message is raised before
#' the upload, so a write that then fails leaves the bad copy in place.
#'
#' @param name Artifact name.
#' @param lost Versions left with no commit recorded.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_warn_commit_shas_lost <- function(name, lost) {
  # The quantity is bound before any `{?}` marker in each string: cli resolves a
  # plural against the most recent quantity in the SAME message, so a marker in a
  # bullet that names no count aborts with "Cannot pluralize without a quantity".
  n <- length(lost)

  cli::cli_warn(
    c(
      "The stored version history for {.val {name}} could not be read, so \\
       {n} version{?s} lost the commit recorded against {?it/them}.",
      "x" = "Affected: {.val {substr(lost, 1, 8)}}.",
      "i" = "This build could not work the commit out from git either -- a \\
             shallow clone or a rewritten history does not carry it.",
      "i" = "Everything else was written normally; {.fn datom_history} will \\
             report {.val NA} there.",
      "i" = "This write replaces that copy, so the unreadable bytes will not be \\
             there to inspect afterwards.",
      "i" = "If storage was merely unreachable, re-run once it is available: a \\
             copy that reads restores the recorded values."
    ),
    class = "datom_commit_shas_lost"
  )
  invisible(NULL)
}


#' The `commit_sha` Storage Already Holds, by Version
#'
#' **Nothing there and could not look are separate answers, and only one of them
#' is safe to pass over in silence.** The first write of an artifact has no stored
#' history, which is ordinary and silent. A stored copy that exists and will not
#' read is the opposite: the values only storage had are now unknown, and the
#' caller is about to replace that file wholesale -- so an entry git cannot
#' attribute loses a good value. Collapsing the two into "no known values" makes
#' the loss invisible in exactly the case where it is unrecoverable, which is why
#' this returns the distinction rather than just a map.
#'
#' The existence probe is what separates them. Its own failure counts as *could
#' not look*, never as absence: an unreachable store cannot report that a file is
#' missing.
#'
#' A stored copy that reads but holds no usable pair is an absence, not a failure
#' -- the document was inspected and had nothing to contribute.
#'
#' @param conn A `datom_conn` object.
#' @param name Artifact name.
#' @return A list with `shas` (named character vector, `commit_sha` named by
#'   version, empty when there are none) and `unreadable` (`TRUE` when storage
#'   holds a copy this call could not read).
#' @keywords internal
.datom_stored_commit_shas <- function(conn, name) {
  key <- .datom_artifact_meta_key(name, "version_history")
  empty <- stats::setNames(character(), character())

  present <- tryCatch(.datom_storage_exists(conn, key), error = function(e) NA)
  if (isFALSE(present)) return(list(shas = empty, unreadable = FALSE))

  stored <- tryCatch(.datom_storage_read_json(conn, key), error = function(e) NULL)

  # A read failure and a parse failure arrive as the same condition from both
  # backends, so they cannot be told apart here. Treated alike on purpose: both
  # mean the stored values are unavailable, and the caller's response is the same
  # either way.
  if (is.null(stored)) return(list(shas = empty, unreadable = TRUE))

  if (!is.list(stored) || length(stored) == 0L) {
    return(list(shas = empty, unreadable = FALSE))
  }

  pairs <- purrr::keep(stored, function(entry) {
    is.list(entry) &&
      .datom_is_text_scalar(entry$version) &&
      .datom_is_text_scalar(entry$commit_sha)
  })

  list(
    shas = stats::setNames(
      purrr::map_chr(pairs, ~ as.character(.x$commit_sha)),
      purrr::map_chr(pairs, ~ as.character(.x$version))
    ),
    unreadable = FALSE
  )
}


#' Work Out Which Commit First Produced Each of an Artifact's Versions
#'
#' Walks the commits that touched `{name}/metadata.json`, oldest-first, hashing
#' the document as each commit left it. A commit whose document hashes to version
#' `V` is a commit that produced `V`, and the first one reached is the one
#' recorded -- which is what makes a code-only commit nobody's producer: it
#' leaves that document untouched, so it is not in the walk at all.
#'
#' One version maps to one-or-more commits by design, because a version is
#' content-derived and code-invariant. Taking the oldest is not arbitrary
#' tie-breaking; it answers "where did this version come from".
#'
#' A repo git cannot answer for -- a shallow clone, a rewritten history, a
#' document that will not parse -- yields no entry for the versions it lost.
#' Callers omit the field in that case rather than recording a blank.
#'
#' **Every give-up here is silent on purpose**, and that is not a house style: a
#' version this cannot attribute is one the caller had no stored value for either,
#' since a stored value is what stops it being asked about. So there is nothing to
#' lose and nothing to report. The asymmetry with reading the stored copy, where a
#' failure does lose something, is spelled out at the top of this file.
#'
#' @param repo_path Path to the local clone.
#' @param name Artifact name.
#' @return Named character vector, commit sha named by version. Empty when
#'   nothing could be derived.
#' @keywords internal
.datom_git_commit_shas_by_version <- function(repo_path, name) {
  empty <- stats::setNames(character(), character())

  if (is.null(repo_path) || !nzchar(repo_path)) return(empty)
  if (!requireNamespace("git2r", quietly = TRUE)) return(empty)

  rel <- paste0(name, "/metadata.json")

  repo <- tryCatch(git2r::repository(repo_path), error = function(e) NULL)
  if (is.null(repo)) return(empty)

  commits <- tryCatch(
    git2r::commits(repo, path = rel, reverse = TRUE),
    error = function(e) NULL
  )
  if (!is.list(commits) || length(commits) == 0L) return(empty)

  shas <- purrr::map_chr(commits, ~ as.character(.x$sha))

  versions <- purrr::map_chr(shas, function(sha) {
    doc <- .datom_metadata_at_commit(repo, sha, rel)
    if (is.null(doc)) return(NA_character_)
    tryCatch(
      .datom_compute_metadata_sha(doc),
      error = function(e) NA_character_
    )
  })

  keep <- !is.na(versions) & !duplicated(versions)
  stats::setNames(shas[keep], versions[keep])
}


#' Read a Metadata Document as One Commit Left It
#'
#' `revparse_single(repo, "<sha>:<path>")` is the whole mechanism: it resolves
#' git's own `commit:path` syntax straight to the blob and raises when the path
#' is absent at that commit. Indexing the tree object instead returns an empty
#' list for a path that is not there, which reads as a successful lookup.
#'
#' @param repo A `git2r` repository handle.
#' @param sha Commit sha.
#' @param rel Repo-relative path of the document.
#' @return The parsed document, or `NULL` when it cannot be read.
#' @keywords internal
.datom_metadata_at_commit <- function(repo, sha, rel) {
  tryCatch(
    {
      blob <- git2r::revparse_single(repo, paste0(sha, ":", rel))
      text <- paste(git2r::content(blob), collapse = "\n")
      # `fromJSON()`'s defaults, matching every other site that hashes a
      # metadata document read off disk -- the canonical form is type-agnostic,
      # but reading it two ways in two places invites the drift anyway.
      doc <- jsonlite::fromJSON(text)
      if (!is.list(doc) || is.null(names(doc))) NULL else doc
    },
    error = function(e) NULL
  )
}


#' The Versions a History Names
#'
#' @param history Parsed `version_history.json`, a list of entries.
#' @return Character vector, `NA` for an entry with no usable version.
#' @keywords internal
.datom_history_versions <- function(history) {
  purrr::map_chr(history, function(entry) {
    if (!is.list(entry) || !.datom_is_text_scalar(entry$version)) {
      return(NA_character_)
    }
    as.character(entry$version)
  })
}
