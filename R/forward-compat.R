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


# --- The write entry -----------------------------------------------------------
#
# Carrying an unfamiliar field forward (above) keeps a write from destroying
# information. It does not make the write CORRECT. A build that meets a field it
# cannot place has been handed a document by a newer datom, and it would go on to
# recompute that document's version identity from the fields it does know --
# reaching a different answer from the build that wrote it, on content that never
# moved. So the write stops instead.
#
# Reads limp, writes stop. That asymmetry is deliberate and it runs through the
# whole schema design: a reader that guesses wrong gives one wrong answer to one
# person, while a writer that guesses wrong leaves the repo wrong for everybody.
#
# Everything in this section runs BEFORE any hashing, any local file write and
# any commit, so a refusal leaves nothing half-written. A write is several steps
# -- local files, one commit, then the storage mirror -- and stopping halfway
# through is worse than the disagreement being prevented.
#
# ALL OF IT READS THE CLONE, never storage. The clone is the copy being
# overwritten, reading it costs no network round trip, it is where a pull from a
# collaborator on a newer datom lands, and storage cannot legitimately be ahead
# of git because git is written first and gates the mirror.


# Every field name this build writes at the TOP LEVEL of `.datom/manifest.json`,
# plus every name that has ever been written there. Append-only, and never
# pruned: a build that forgets a name meets an OLDER document, fails to place a
# key it should know, and refuses it -- blocking the upgrade direction, which is
# the one direction that must always work.
#
#   schema_version    which format the document is in
#   project_name      the project this manifest belongs to
#   artifacts         the artifact list, keyed by name
#   summary           aggregate counters, recomputed on every write
#   updated_at        when the document was last rewritten
#
# RETIRED, still recognised:
#   tables            the artifact list's name before schema v2. Documents
#                     carrying it exist unchanged in the world. The conversion
#                     renames it before this list is consulted, so in practice
#                     the entry is what makes the check safe if it is ever
#                     consulted on an unconverted document -- and it is the
#                     worked example of retiring a name by marking it.
.datom_manifest_known_fields <- c(
  "artifacts", "project_name", "schema_version", "summary", "tables",
  "updated_at"
)


#' Refuse a Write This Repo Has Declared Too Old
#'
#' A repo may state the lowest version of datom it accepts writes from. The
#' field is optional and lives in `project.yaml`; **absent means no limit**, so
#' no repo written so far changes behaviour.
#'
#' It exists for the two cases the vocabulary check structurally cannot see,
#' because neither introduces a new field name: a change in what an existing
#' field *means*, and a block for a reason that is not about format at all
#' ("0.1.4 wrote bad hashes, do not let it write here"). A version number is the
#' right currency for both -- the schema number cannot carry them, since it does
#' not move for a change that is reader-safe, and a package version directly
#' answers the question a refusal raises.
#'
#' **The reading half ships even though nothing sets the field yet**, and that
#' ordering is the whole point: a build that does not look for the field can
#' never be bound by it. This is exactly why no released datom can be stopped
#' from writing -- the looking has to be inside the build being stopped. Setting
#' the field is a separate, later mechanism, and it owns the guard that whoever
#' raises a floor must already satisfy it.
#'
#' A value that will not parse as a version **aborts** rather than being ignored.
#' Treating a malformed floor as no floor would turn a typo in a policy field
#' into a silently disabled policy.
#'
#' @param conn A `datom_conn` object.
#' @return Invisibly `NULL`. Aborts when the running build is older than the
#'   declared floor.
#' @keywords internal
.datom_check_writer_floor <- function(conn) {
  declared <- conn$min_writer_version
  if (is.null(declared)) return(invisible(NULL))

  usable <- length(declared) == 1L && !is.na(declared) &&
    (is.character(declared) || is.numeric(declared))

  floor <- if (usable) {
    tryCatch(as.package_version(as.character(declared)), error = function(e) NULL)
  } else {
    NULL
  }

  if (is.null(floor)) {
    cli::cli_abort(
      c(
        "{.field min_writer_version} in {.file project.yaml} is not a usable version.",
        "x" = "Got: {.val {declared}}",
        "i" = "Expected a single version string, e.g. {.val 0.2.0}.",
        "i" = "Remove the field to accept writes from any version."
      ),
      class = "datom_writer_floor_invalid"
    )
  }

  installed <- utils::packageVersion("datom")
  if (installed >= floor) return(invisible(NULL))

  cli::cli_abort(
    c(
      "This repo accepts writes from datom {as.character(floor)} or newer.",
      "x" = "Installed datom is {as.character(installed)}.",
      "i" = "Declared by {.field min_writer_version} in {.file project.yaml}.",
      "i" = "Upgrade with {.code remotes::install_github('amashadihossein/datom')}."
    ),
    class = "datom_writer_floor"
  )
}


#' Refuse a Document Carrying a Field This Build Cannot Place
#'
#' Compares one document's **top-level** key names against the names this build
#' can classify, and aborts naming any it cannot. The evidence is in the file:
#' no version comparison, no configuration, no network.
#'
#' Chosen over a declared version floor as the *primary* mechanism for one
#' reason -- **it cannot be forgotten.** A floor protects a repo only if somebody
#' remembers to raise it; this fires on the evidence whether or not anyone did
#' anything.
#'
#' **Top-level keys only, and that is a scope rather than a shortcut.** It means
#' do not descend into a value -- `custom` holds arbitrary user keys by design
#' and is classified as one recognised field, and the manifest's `summary` block
#' is a derived aggregate that is rebuilt on every write. It does **not** mean
#' skip the manifest's artifact entries: an entry is its own document for this
#' purpose and gets checked against its own vocabulary.
#'
#' **The check cannot fire on the upgrade path**, and no code guards against
#' that: a newer build's vocabulary is a superset of every older build's, so it
#' can never meet a name it does not know. A directional special case would be
#' dead code protecting an unreachable state.
#'
#' The accepted cost is that any release adding a field to a datom-owned document
#' forces a fleet-wide **writer** upgrade, cosmetic additions included. Writes
#' are infrequent, done by few people, and they change content -- a false refusal
#' costs one person an install, a miss costs corrupted data.
#'
#' @param doc Parsed document. A non-list, or a list with no names, has no
#'   top-level keys to classify and passes through: it is not this check's job to
#'   report a malformed document, and the write fails on it moments later on its
#'   own terms.
#' @param known Character vector of field names this build can place.
#' @param source Path or key of the document, for the message.
#' @return Invisibly `NULL`. Aborts on an unclassifiable key.
#' @keywords internal
.datom_check_document_vocabulary <- function(doc, known, source) {
  if (!is.list(doc)) return(invisible(NULL))

  keys <- names(doc)
  if (is.null(keys)) return(invisible(NULL))

  keys <- keys[nzchar(keys)]
  unknown <- setdiff(keys, known)
  if (length(unknown) == 0L) return(invisible(NULL))

  cli::cli_abort(
    c(
      "{.val {source}} carries {length(unknown)} field{?s} this build of datom \\
       cannot place.",
      "x" = "Unrecognised: {.field {unknown}}.",
      "i" = "A newer datom wrote this document, and this build would rewrite it \\
             without accounting for what it cannot place.",
      "i" = "Upgrade with {.code remotes::install_github('amashadihossein/datom')}, \\
             or write from the build that produced it."
    ),
    class = "datom_vocabulary_unknown"
  )
}


#' Everything a Write Must Clear Before It Starts
#'
#' The one entry sequence for every write route. Ordered, and the order matters:
#'
#' 1. **The floor** -- refuse if this repo has declared this build too old.
#' 2. **The manifest, read through the one shared reader**, which checks the
#'    declared format and then converts an older document in memory. Refusing a
#'    format from the future has to happen before the conversion, because there
#'    is no conversion step for a version this build has never heard of.
#' 3. **The shape the conversion reached.** If the artifact list is still absent
#'    after the chain has run, this document belongs to a lineage this build
#'    cannot produce -- refuse rather than overwrite it in an older shape.
#' 4. **The vocabulary**, on the manifest's top level, on each of its artifact
#'    entries, and on each per-artifact metadata document this write will touch.
#'
#' **Why step 3 is worded as "still absent after the chain" and not "absent".**
#' A current build meeting a pre-rename repo finds no artifact list either, and a
#' rule that refused on that would deadlock the very upgrade it exists to
#' protect: no repo could ever move forward. The discriminator is not the key, it
#' is whether the chain can *reach* the shape. Note the deliberate asymmetry with
#' the reader, which will one day *rebuild* on this same condition -- same
#' evidence, opposite response, because reads limp and writes stop.
#'
#' **Which per-artifact documents get checked depends on the route**, which is
#' why `artifact` exists. A table write or a metadata-only sync touches one
#' artifact; the mirror-everything route touches all of them, and it is the route
#' with no artifact name in its arguments at all. Both cases enumerate through
#' [.datom_clone_artifact_names()], the same helper the mirror route itself uses,
#' so the door cannot end up inspecting a different set than the one that gets
#' written.
#'
#' **Callable more than once, and one route calls it twice.** Nothing here
#' mutates anything, so re-running it is free. The metadata-only route pulls from
#' the remote as its first act -- after this check has already read the clone --
#' so a collaborator's newer document can arrive in that pull; that route runs
#' the sequence again afterwards. See `.datom_sync_metadata()`.
#'
#' @param conn A `datom_conn` object.
#' @param artifact Name of the single artifact this write touches, or `NULL` to
#'   check every artifact present in the clone.
#' @return Invisibly `NULL`. Aborts on any refusal.
#' @keywords internal
.datom_check_write_entry <- function(conn, artifact = NULL) {
  .datom_check_writer_floor(conn)

  # No clone, nothing to inspect. A reader-role connection lands here and then
  # fails a few lines later with a clearer message about needing the developer
  # role; letting that message stand beats replacing it with a vaguer one.
  if (is.null(conn$path) || !nzchar(conn$path)) return(invisible(NULL))

  read <- .datom_read_manifest(conn, "clone", operation = "write")

  # `ok = FALSE` is either an absent manifest -- a repo where nothing has been
  # written, so nothing can disagree -- or a file that will not parse, which is
  # not a compatibility failure and not this check's to report: the write fails
  # on the same file moments later with the parser's own error.
  if (read$ok) {
    if (!("artifacts" %in% names(read$manifest))) {
      cli::cli_abort(
        c(
          "Cannot find an artifact list in {.file .datom/manifest.json}.",
          "x" = "The document declares schema v{read$declared} and holds no \\
                 artifact list this build can reach.",
          "i" = "A newer datom may have restructured it. Writing now would \\
                 replace it with a shape this build invented.",
          "i" = "Upgrade with {.code remotes::install_github('amashadihossein/datom')}, \\
                 or restore the file from git history."
        ),
        class = "datom_shape_unreachable"
      )
    }

    .datom_check_document_vocabulary(
      read$manifest, .datom_manifest_known_fields, ".datom/manifest.json"
    )

    purrr::iwalk(read$manifest$artifacts %||% list(), function(entry, nm) {
      .datom_check_document_vocabulary(
        entry, .datom_manifest_entry_known_fields,
        paste0(".datom/manifest.json (artifact ", nm, ")")
      )
    })
  }

  to_check <- if (is.null(artifact)) {
    .datom_clone_artifact_names(conn)
  } else {
    artifact
  }

  purrr::walk(to_check, function(nm) {
    doc <- .datom_prior_metadata(conn, nm)
    if (is.null(doc)) return(invisible(NULL))

    source <- paste0(nm, "/metadata.json")

    # The schema check belongs here as much as the vocabulary one, and this is
    # the only place it happens for this document on a write. The metadata-only
    # route copies the clone's copy straight to storage, so before this existed a
    # document pulled from a collaborator on a newer datom went through
    # unexamined.
    .datom_check_schema_version(doc, source, operation = "write")

    .datom_check_document_vocabulary(
      doc, .datom_metadata_known_fields(), source
    )
  })

  invisible(NULL)
}
