# Forward compatibility: keeping a document readable and writable by builds that
# do not know its full shape.
#
# The problem this file exists for. A datom-owned document can arrive carrying a
# top-level field this build has never heard of -- a collaborator on a newer
# datom wrote it and this developer pulled. Datom's write path does not edit such
# a document in place; it rebuilds it from scratch from what it knows and
# overwrites the file. So an older build does not merely miscompute around the
# unfamiliar field: it DELETES it. Every field datom writes today happens to be
# recomputable from data it still holds, so nothing is lost yet; the rule exists
# for the first field that is not.
#
# Nothing here can be retrofitted. A build already installed and pinned in an
# renv.lock will keep deleting fields it does not know, because the preserving
# has to happen inside the build doing the writing. That is why this ships now
# rather than when a non-recomputable field first appears.


#' Every Metadata Field Name This Build Knows
#'
#' The two halves of the classification joined: the fields that make up a
#' version's identity, and the fields datom deliberately keeps out of it. A name
#' in neither half is a name this build cannot place.
#'
#' A function rather than a stored vector, for two reasons that both bite.
#' `R/` is sourced alphabetically (DESCRIPTION declares no `Collate`), and this
#' file sorts before `R/utils-sha.R` where both halves are defined -- so a
#' constant built from them here would be built from values that do not exist
#' yet and the package would fail to install. Deriving it at call time also means
#' it cannot fall out of step with either half.
#'
#' **Append-only.** A name that has ever been written must keep classifying
#' forever, including names datom no longer writes: a build that forgets one
#' meets an older document, fails to place a field it should know, and starts
#' preserving as unfamiliar something it could have handled -- or, once the
#' write-side refusal lands, refuses the document outright and blocks the
#' upgrade direction, which must always work.
#'
#' @return Character vector of field names, unsorted.
#' @keywords internal
.datom_metadata_known_fields <- function() {
  union(.datom_metadata_identity_fields, .datom_metadata_excluded_fields)
}


# Every field name this build writes into one artifact's row in
# `.datom/manifest.json`. Append-only, for the reason above.
#
# Kept as its own list rather than derived from the row builder, because the
# builder is what this list polices: a row assembled from `.datom_build_*`-style
# output could never disagree with a vocabulary read off that same output. The
# forcing function is a test that writes a real artifact and asserts every field
# on the resulting row appears here, so adding a field to the builder without
# classifying it fails rather than passing silently.
#
#   kind                            which kind of artifact the row describes
#   current_version                 the version the row points at
#   current_data_sha                that version's content identity
#   last_updated                    when the row was last rewritten
#   size_bytes, version_count       counters the summary block aggregates
#   original_file_sha               imported artifacts only
#   original_format                 imported artifacts only
.datom_manifest_entry_known_fields <- c(
  "current_data_sha", "current_version", "kind", "last_updated",
  "original_file_sha", "original_format", "size_bytes", "version_count"
)


#' Carry Unrecognised Top-Level Fields Onto a Rebuilt Document
#'
#' Copies onto `rebuilt` every top-level field of `prior` whose name is not in
#' `known`, so a field this build cannot place survives being rewritten.
#'
#' **Only unrecognised fields are carried, and that narrowness is the design.**
#' A field datom knows about keeps exactly the behaviour it has today, including
#' disappearing when this write does not set it. `original_format` is the case
#' that makes the difference concrete: a table first imported from a CSV and
#' later written straight from a data frame has no format to declare, and the
#' row is meant to stop claiming one. Carrying every absent field forward
#' instead of only the unplaceable ones would leave that claim standing against
#' a version it does not describe -- a wrong statement, which is worse than a
#' missing one.
#'
#' Where `rebuilt` already has a field, `rebuilt` wins. That cannot happen for a
#' genuinely unrecognised field, since this build only writes names it knows;
#' stating the precedence costs one term and removes the question.
#'
#' Top-level only, at each level separately. A field nested inside a value datom
#' does understand -- inside `custom`, or inside the manifest's `summary` block
#' -- is not this function's business: `custom` is carried whole as one
#' recognised field, and `summary` is a derived aggregate that is meant to be
#' recomputed.
#'
#' A field whose value is JSON `null` gets no special handling. Absence in a
#' datom document is spelled by omitting the key, never by nulling it, so such a
#' field is already off-convention; it is carried, but a `null` re-serialises as
#' an empty object rather than as `null`.
#'
#' @param rebuilt The document this build assembled, a named list.
#' @param prior The document that was already on disk, a named list, or `NULL` /
#'   anything unparsed when there was none -- in which case there is nothing to
#'   carry and `rebuilt` is returned unchanged.
#' @param known Character vector of field names this build can place.
#' @return `rebuilt`, with the unrecognised fields of `prior` appended.
#' @keywords internal
.datom_carry_unknown_fields <- function(rebuilt, prior, known) {
  if (!is.list(rebuilt)) return(rebuilt)
  if (!is.list(prior)) return(rebuilt)

  prior_names <- names(prior)
  if (is.null(prior_names)) return(rebuilt)

  unknown <- setdiff(prior_names, c(known, names(rebuilt)))
  unknown <- unknown[nzchar(unknown)]
  if (length(unknown) == 0L) return(rebuilt)

  rebuilt[unknown] <- prior[unknown]

  rebuilt
}


#' The Metadata Document Already in the Clone, If Any
#'
#' Reads `{name}/metadata.json` from the local git checkout, for the one purpose
#' of finding fields to carry forward. Returns `NULL` when there is no such file
#' or it will not parse -- both mean there is nothing to preserve, and neither is
#' this function's business to report: a brand-new artifact legitimately has no
#' prior document, and an unparseable one fails moments later on its own terms.
#'
#' **The clone's copy, not storage's.** Three reasons, any one sufficient: it is
#' the file being overwritten, so preserving its own content is the claim being
#' made; it is a local file read rather than a network round trip; and it is
#' where a pull from a collaborator on a newer datom lands. Storage cannot
#' legitimately hold a newer document than the clone, because git is written
#' first and gates the storage mirror -- if it does, that is drift, and
#' `datom_validate()` owns drift.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param name Artifact name.
#' @return The parsed document, or `NULL`.
#' @keywords internal
.datom_prior_metadata <- function(conn, name) {
  if (is.null(conn$path) || !nzchar(conn$path)) return(NULL)

  path <- fs::path(conn$path, name, "metadata.json")
  if (!fs::file_exists(path)) return(NULL)

  tryCatch(jsonlite::read_json(path), error = function(e) NULL)
}
