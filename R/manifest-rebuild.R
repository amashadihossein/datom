# Reconstructing the artifact index from storage.
#
# The manifest is a projection: every fact in it is also recorded in the
# per-artifact documents it summarises. That is what makes this file possible,
# and it is the reason the manifest gets a survivable failure mode where
# per-artifact metadata gets none -- there is nothing to rebuild metadata from.
#
# TWO CONDITIONS BRING A READER HERE, and they are the same two that make a
# WRITER refuse (`.datom_check_write_entry()`): the document holds no artifact
# list this build can reach, or it declares a format above what this build
# supports. Same evidence, opposite responses. Reads limp, writes stop -- a
# reader that carries on gives one person one session's answers, while a writer
# that carries on leaves the repo wrong for everybody. Do not "unify" the two
# sides; the asymmetry is the design.
#
# A REBUILD IS IN MEMORY, FOR THIS SESSION, ALWAYS. It writes nothing -- not the
# clone's copy, not storage's. A reader holds storage credentials and no clone,
# so persisting is not available to the population this exists for; and a read
# that quietly rewrote a repo's index would be a far larger surprise than the
# one it is fixing. The recorded copy is repaired by the next ordinary write.
#
# IT IS NOT SILENT. Every rebuild warns once, naming the upgrade. A repair that
# succeeds without saying so is itself a silent degradation, which is the exact
# failure the whole schema contract exists to remove.
#
# ACCEPTED COST, RECORDED SO IT IS NOT MET AS A SURPRISE: nothing memoises this,
# so it runs again on every call for as long as the repo stays broken. One
# listing plus two reads per artifact means a 300-artifact repo spends ~601
# storage requests per command -- and `datom_status()` reads two copies of the
# manifest, so a repo broken on both sides pays twice in one call. That is the
# cost the manifest exists to avoid (`dev/datom_specification.md:1694`: "For
# repos with 100-300 tables, this avoids hundreds of S3 GETs on unchanged
# re-runs"), which is exactly why the trigger is a broken index rather than
# anything a healthy repo can hit. The user experiences it as datom hanging,
# because the warning only arrives once the work is finished.
#
# Not memoised on purpose. A session cache is already deferred package-wide
# pending its invalidation design (`dev/datom_specification.md:2031`), and adding
# one here would put session state into a library that has none in order to speed
# up a state the next ordinary write removes. Upgrading, or writing once, is the
# fix.


#' Artifact Names Present in Storage
#'
#' Enumerates artifacts from a storage listing, by the one signal that
#' identifies one: a `{name}/.metadata/metadata.json` object. Deliberately
#' independent of the manifest, because the manifest is the document under
#' suspicion whenever this is called.
#'
#' The clone-side equivalent is [.datom_clone_artifact_names()]. They are not
#' interchangeable and neither can stand in for the other: a storage-only reader
#' has no clone at all, and the clone can hold an artifact whose upload has not
#' happened yet.
#'
#' **The listing returns FULL keys** -- including the `{prefix}/datom/` portion
#' -- while every other part of datom's business logic speaks in keys relative to
#' the datom namespace root. Mixing the two shapes double-prefixes silently and
#' does not error, so the root is stripped here, once, against the same builder
#' the backends use.
#'
#' @param conn A `datom_conn` object.
#' @return Character vector of artifact names, possibly empty. One storage
#'   listing, recursive.
#' @keywords internal
.datom_storage_artifact_names <- function(conn) {
  keys <- .datom_storage_list_objects(conn, "")
  if (length(keys) == 0L) return(character())

  root <- paste0(.datom_build_storage_key(conn$prefix, ""), "/")
  under_root <- startsWith(keys, root)
  rel <- ifelse(under_root, substring(keys, nchar(root) + 1L), keys)

  matched <- regmatches(
    rel,
    regexec("^([^/]+)/\\.metadata/metadata\\.json$", rel)
  )

  names <- purrr::map_chr(matched, function(m) {
    if (length(m) < 2L) NA_character_ else m[[2L]]
  })

  sort(unique(names[!is.na(names)]))
}


#' The Version Storage Recorded for an Artifact's Current State
#'
#' Picks the `version_history.json` entry that describes `metadata.json`, and
#' returns the `version` **recorded** on it.
#'
#' **Never recomputed, and that is the point of this function existing at all.**
#' Hashing `metadata.json` here would reach for the identity code in precisely
#' the scenario a rebuild is for -- a repo touched by a build whose field
#' classification differs from this one's -- and publish a `current_version`
#' matching no version in the recorded history. An index pointing at a version
#' that does not exist is worse than the empty list it replaced.
#'
#' Which entry describes the current state is not simply the newest one. History
#' is prepended newest-first, but a write that reverts to content already in the
#' history appends nothing, so the current state can be an older entry. The
#' selection therefore narrows by recorded fields only:
#'
#' 1. Entries whose `data_sha` equals the current document's. One match settles
#'    it -- this is the revert case, and it is why the newest entry alone is
#'    wrong.
#' 2. Several matches means metadata-only versions of the same content; the one
#'    whose `timestamp` equals the document's `created_at` is the current one,
#'    since a version's history entry copies that field verbatim.
#' 3. Anything still ambiguous takes the newest candidate. That is a choice
#'    between two entries that both describe the current **content**, so the
#'    worst case is naming the wrong one of two versions of the same bytes.
#'
#' **No match at all returns `NULL`, and it deliberately does not fall back to
#' the newest entry.** No match means the history does not record the state
#' `metadata.json` describes -- a truncated or partly-synced history. The newest
#' entry there is a version of *different content*, so naming it would be a wrong
#' statement rather than a missing one, and a row already tolerates carrying no
#' version. `datom_validate()` owns the inconsistency. This is the same trade the
#' carry-forward rule makes in `R/forward-compat.R`: a stale claim that outlives
#' what it described is worse than an absent one.
#'
#' @param meta The artifact's parsed `metadata.json`.
#' @param history The artifact's parsed `version_history.json`, a list of
#'   entries, or `NULL`.
#' @return The recorded version string, or `NULL` when the history records
#'   nothing usable -- in which case the rebuilt row simply carries no version,
#'   rather than a manufactured one.
#' @keywords internal
.datom_recorded_current_version <- function(meta, history) {
  if (!is.list(history) || length(history) == 0L) return(NULL)

  version_of <- function(entry) {
    if (!is.list(entry)) return(NULL)
    v <- entry$version
    if (is.null(v) || !is.character(v) || length(v) != 1L || !nzchar(v)) NULL else v
  }

  candidates <- purrr::keep(history, function(entry) {
    is.list(entry) && !is.null(meta$data_sha) &&
      identical(entry$data_sha, meta$data_sha)
  })

  if (length(candidates) > 1L) {
    exact <- purrr::keep(candidates, function(entry) {
      !is.null(meta$created_at) && identical(entry$timestamp, meta$created_at)
    })
    if (length(exact) >= 1L) candidates <- exact
  }

  if (length(candidates) == 0L) return(NULL)

  version_of(candidates[[1L]])
}


#' Rebuild One Artifact's Manifest Row from Its Own Documents
#'
#' Every field on the row is copied from `metadata.json` or counted from
#' `version_history.json`. The row's shape has to match what
#' `.datom_update_manifest_entry()` writes, field for field, or a rebuilt repo
#' answers differently from a healthy one -- so the two are pinned against each
#' other by a test rather than by matching comments.
#'
#' `last_updated` is the one field with no recorded source: the writer stamps the
#' wall clock at the moment it rewrites the row, and that moment is not in any
#' document. The version's own `created_at` is used instead, which is the closest
#' true statement available -- when this artifact's current state was written.
#'
#' **Rebuilding a set's row is not finished here.** `kind` is recovered, so a set
#' is at least counted as a set, but a set's row also carries `member_count`, and
#' that number is in the payload rather than in `metadata.json` -- so it takes a
#' third read, at the content-addressed payload key. Whoever writes the set write
#' path owns closing that gap; nothing writes a set row yet, so there is no
#' shape to match against today.
#'
#' @param conn A `datom_conn` object.
#' @param name Artifact name.
#' @return A named list: one manifest artifact row.
#' @keywords internal
.datom_rebuild_manifest_entry <- function(conn, name) {
  meta <- .datom_storage_read_json(conn, .datom_artifact_meta_key(name, "metadata"))

  # The per-artifact document gets the same compatibility check every other
  # reader applies to it, and its refusal is meant to escape this rebuild rather
  # than be softened into a missing row. Metadata is stamped and NOT
  # rebuildable, so if the release that moved the manifest ahead also moved
  # metadata, there is nothing here to salvage. Survivability is available
  # exactly when the break was manifest-only.
  .datom_check_schema_version(meta, paste0(name, "/.metadata/metadata.json"))

  history <- tryCatch(
    .datom_storage_read_json(conn, .datom_artifact_meta_key(name, "version_history")),
    error = function(e) NULL
  )

  entry <- list(
    # Read from the document, which now declares it. The fallback covers every
    # artifact written before it did -- all of them tables, since sets did not
    # exist -- and is the same assumption the v1 manifest upgrade makes about an
    # untyped row. It is not optional either way: an untyped row is silently
    # uncounted by `.datom_artifacts_of_kind()`, so a rebuilt repo would list its
    # artifacts while reporting zero of them.
    kind = meta$kind %||% "table",
    current_version = .datom_recorded_current_version(meta, history),
    current_data_sha = meta$data_sha,
    last_updated = meta$created_at,
    # as.numeric, not as.integer: an artifact over 2 GB overflows R's integer
    # limit and the NA then poisons the summary total.
    size_bytes = as.numeric(meta$size_bytes %||% 0),
    version_count = if (is.list(history)) length(history) else 0L
  )

  entry$version_count <- as.integer(entry$version_count)

  if (!is.null(meta$original_file_sha)) {
    entry$original_file_sha <- meta$original_file_sha
  }
  # Recoverable only because this build persists it into metadata. Before that it
  # lived on the manifest row alone, which made it the one field a rebuild had to
  # drop.
  if (!is.null(meta$original_format)) {
    entry$original_format <- meta$original_format
  }

  purrr::compact(entry)
}


#' Reconstruct the Whole Artifact Index from Storage
#'
#' One storage listing plus two reads per artifact. The result is a complete
#' manifest in this build's shape: the artifact rows, the summary counters
#' recomputed from them, and the current format declared.
#'
#' `project_name` and `updated_at` are carried from the document being replaced
#' when it has them. Both are recorded facts about the repo rather than about the
#' artifacts, so neither is recoverable from a listing -- and inventing a fresh
#' `updated_at` would state that the index was rewritten now, when nothing was
#' written at all.
#'
#' Aborts rather than returning a partial index. Half an artifact list is
#' indistinguishable from a repo that only has half those artifacts, and the
#' caller's job is to decide what an unreachable store means -- see
#' [.datom_read_manifest()], which keeps a schema refusal separate from an IO
#' failure on the way back out.
#'
#' @param conn A `datom_conn` object.
#' @param prior The document being replaced, or `NULL`.
#' @return A manifest in current shape.
#' @keywords internal
.datom_rebuild_manifest <- function(conn, prior = NULL) {
  names_found <- .datom_storage_artifact_names(conn)

  # lapply, not purrr::map, and the difference is behavioural rather than
  # stylistic: purrr re-signals whatever a mapped function throws as its own
  # indexed error, with the original demoted to a parent. A compatibility refusal
  # raised on one artifact's document then arrives at the caller carrying purrr's
  # class instead of its own, and the caller decides what to do BY that class.
  artifacts <- structure(
    lapply(names_found, function(nm) .datom_rebuild_manifest_entry(conn, nm)),
    names = names_found
  )

  manifest <- .datom_manifest_skeleton(
    if (is.list(prior)) prior$project_name %||% conn$project_name else conn$project_name
  )
  manifest$artifacts <- artifacts

  tables <- .datom_artifacts_of_kind(artifacts, "table")
  sets <- .datom_artifacts_of_kind(artifacts, "set")

  manifest$summary <- list(
    total_tables = length(tables),
    total_size_bytes = sum(purrr::map_dbl(
      tables, ~ as.numeric(.x$size_bytes %||% 0L)
    )),
    total_versions = sum(purrr::map_int(
      tables, ~ as.integer(.x$version_count %||% 0L)
    )),
    total_sets = length(sets)
  )

  if (is.list(prior) && !is.null(prior$updated_at)) {
    manifest$updated_at <- prior$updated_at
  }

  manifest
}


#' Say That the Artifact Index Was Reconstructed
#'
#' One warning per rebuild, carrying a condition class so a caller -- or a test
#' -- can count them rather than match on wording.
#'
#' It names what happened, why, and what to do, in that order. The "why" is the
#' part a user cannot work out for themselves: a manifest whose artifact list has
#' moved somewhere this build cannot see looks exactly like an empty repo, and
#' the whole point of warning is that this session's answers came from a
#' reconstruction rather than from the recorded index.
#'
#' @param source Which copy of the manifest was rebuilt.
#' @param reason `"schema"` (the document declares a format above this build) or
#'   `"shape"` (no artifact list this build can reach).
#' @param declared The version the document declared, for the schema reason.
#' @param n How many artifacts the rebuild found.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_warn_manifest_rebuilt <- function(source, reason, declared, n) {
  why <- if (identical(reason, "schema")) {
    cli::format_inline(
      "It declares datom schema v{as.integer(declared)}, above the \\
       v{(.datom_supported_schema)} this build supports."
    )
  } else {
    cli::format_inline(
      "It holds no artifact list this build can reach."
    )
  }

  cli::cli_warn(
    c(
      "Rebuilt the artifact index of {.val {source}} from storage.",
      "x" = why,
      "i" = "Listed storage instead and found {n} artifact{?s}. Nothing was \\
             written -- the recorded index is unchanged.",
      "i" = "Upgrade with {.code remotes::install_github('amashadihossein/datom')} \\
             so this repo is read from its own index again."
    ),
    class = "datom_manifest_rebuilt"
  )

  invisible(NULL)
}
