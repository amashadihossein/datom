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
# always be recomputed, which is only true if something recomputes. Hence both
# halves below: merge what storage holds, then derive what is still missing.
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

  known <- .datom_stored_commit_shas(conn, name)

  if (.datom_is_text_scalar(version) && .datom_is_text_scalar(commit_sha) &&
      !(version %in% names(known))) {
    known[[version]] <- commit_sha
  }

  versions <- .datom_history_versions(history)
  if (length(setdiff(stats::na.omit(versions), names(known))) > 0L) {
    derived <- .datom_git_commit_shas_by_version(conn$path, name)
    known <- c(known, derived[setdiff(names(derived), names(known))])
  }

  purrr::map(history, function(entry) {
    if (!is.list(entry)) return(entry)
    v <- entry$version
    if (!.datom_is_text_scalar(v) || !(v %in% names(known))) return(entry)
    # Assigned, never declared: `jsonlite` writes a NULL element as `{}`, so an
    # entry whose commit is unknown must omit the key rather than carry an empty
    # object where a sha belongs.
    entry$commit_sha <- known[[v]]
    entry
  })
}


#' The `commit_sha` Storage Already Holds, by Version
#'
#' A missing or unparseable stored history is an absence, not a failure: the
#' first write of an artifact has none, and this function's caller is on its way
#' to writing one.
#'
#' @param conn A `datom_conn` object.
#' @param name Artifact name.
#' @return Named character vector, `commit_sha` named by version. Empty when
#'   storage holds nothing.
#' @keywords internal
.datom_stored_commit_shas <- function(conn, name) {
  stored <- tryCatch(
    .datom_storage_read_json(
      conn, .datom_artifact_meta_key(name, "version_history")
    ),
    error = function(e) NULL
  )

  if (!is.list(stored) || length(stored) == 0L) return(stats::setNames(character(), character()))

  pairs <- purrr::keep(stored, function(entry) {
    is.list(entry) &&
      .datom_is_text_scalar(entry$version) &&
      .datom_is_text_scalar(entry$commit_sha)
  })

  stats::setNames(
    purrr::map_chr(pairs, ~ as.character(.x$commit_sha)),
    purrr::map_chr(pairs, ~ as.character(.x$version))
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
