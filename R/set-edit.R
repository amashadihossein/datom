# Editing a set that already exists: selecting members already in hand, and
# repointing them at newer versions.
#
# WHY A VERB RATHER THAN LIST SURGERY. The only route before this was editing
# the list `datom_get_set()` returned, and two of the obvious spellings are
# silently wrong. Filtering members by name drops EVERY version of that name, so
# a deliberately frozen baseline goes out with the live table. And rebuilding a
# pointer from its name plus a new version loses that member's labels, which are
# part of the set's content -- so the set's identity moves for a reason nobody
# asked for.
#
# FIVE THINGS HERE ARE LOAD-BEARING.
#
#   1. LABELS ARE CARRIED, NEVER REBUILT. `datom_member()` tidies the tag map it
#      is handed -- a key whose value is empty is dropped -- so passing the old
#      labels back through it can return fewer labels than it was given. The
#      pointer is therefore built with NO tags and the old record's `tags` is
#      attached verbatim afterwards. Every datom-written payload is tidied
#      already, which is exactly why this is invisible in an ordinary fixture and
#      shows up only on a hand-built or foreign-written set.
#
#   2. THE `fetch` LINK IS REBUILT FOR EVERY MEMBER THAT HAD ONE. A link pins the
#      version it was built at. Move the record's version and leave the link
#      alone and the member contradicts itself: `id` says the new version and
#      `$fetch()` returns the old data, silently. The rebuild goes through the
#      one existing factory, never inline -- a closure built in this file would
#      put the frame holding `conn`, and therefore the PAT, on its parent chain.
#
#   3. CONNECTIONS ARE MATCHED ON AN UNVERIFIED LABEL AND THE RESULT IS
#      VERIFIED. `conn$project_name` is a string the caller supplied and nothing
#      compares it against the repo, so it can only choose the route. What
#      confirms the route is the REBUILT member's recorded project: it comes from
#      the artifact's own metadata, so a connection labelled for one project
#      while pointing at another's storage is caught after the read rather than
#      trusted before it.
#
#   4. UNKNOWN REFUSES, KNOWN-AND-BENIGN REPORTS. No connection for a member's
#      project means whether it moved is unknowable, so the whole call stops --
#      reporting it as unchanged would state something nothing checked. An
#      artifact that no longer appears in its project is a known answer, so it is
#      reported and its pin is left: a version is immutable and still reads, and
#      refusing a whole refresh over one retired input is the wrong trade.
#
#   5. NOTHING IS WRITTEN, SO THE REPORT IS THE DRY RUN. Both facts follow from
#      it: no confirmation prompt is needed, and a refresh that finds nothing new
#      returns a byte-identical payload, which the existing change detection
#      reports as no change with no version minted.


# --- the object being edited ----------------------------------------------------

#' The Member List of a Set or a Draft, or an Abort Naming What Was Passed
#'
#' Both shapes are accepted because [datom_write_set()] already accepts both, so
#' an edit verb narrower than the write would create a shape the write takes and
#' the edit refuses.
#'
#' @param x The value the caller passed.
#' @param arg Argument name for the message.
#' @return The member list, possibly empty.
#' @keywords internal
.datom_edit_members <- function(x, arg = "x") {
  if (!inherits(x, "datom_set") && !inherits(x, "datom_set_draft")) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a {.cls datom_set} from {.fn datom_get_set} or a \\
         {.cls datom_set_draft} from {.fn datom_assemble_set}.",
        "i" = "You passed {.cls {class(x)}}.",
        "i" = "Read the set first: \\
               {.code x <- datom_get_set(conn, \"my-product\")}."
      ),
      class = "datom_not_a_set"
    )
  }

  members <- x$members
  if (!is.list(members)) return(list())

  members
}


#' Forget the Version an Edited Set Was Read As
#'
#' `datom_get_set()` fills `version` and `data_sha` from the payload it read.
#' Once a member moves, those two describe a payload that no longer exists -- and
#' a set exists to be cited, so a stale version is a wrong statement rather than
#' a missing one. Left in place when nothing moved: there the object still
#' describes exactly the stored version, and dropping a true fact would cost the
#' common "refresh found nothing" case its citability for no reason.
#'
#' **Spelled `x["f"] <- list(NULL)`, never `x$f <- NULL`**, which would REMOVE the
#' element and change `names(x)`. A read set may legitimately report a `NULL`
#' version, so the field exists and is empty rather than being absent.
#'
#' A draft has neither field, so this is a no-op on one.
#'
#' @param x The edited `datom_set` or `datom_set_draft`.
#' @return `x`, with `version` and `data_sha` emptied when it had them.
#' @keywords internal
.datom_forget_set_identity <- function(x) {
  if (!inherits(x, "datom_set")) return(x)

  x["version"] <- list(NULL)
  x["data_sha"] <- list(NULL)

  x
}


# --- the selection --------------------------------------------------------------

#' The Position of a Member Named by a Record or a Link
#'
#' Matched on the whole `id`, which is a member's only unique key: the same name
#' can appear twice, and two projects may both hold a `dm`.
#'
#' @param members The set's member list.
#' @param record The record the caller passed, or the one a link carries.
#' @return An integer vector of positions, normally of length one.
#' @keywords internal
.datom_match_member_id <- function(members, record) {
  id <- .datom_member_id(record)

  key <- function(m) {
    paste(
      .datom_id_text(m$id, "project"), .datom_id_text(m$id, "name"),
      .datom_id_text(m$id, "kind"), .datom_id_text(m$id, "version"),
      sep = "\r"
    )
  }

  at <- which(vapply(members, key, character(1L)) == key(list(id = id)))

  if (length(at) == 0L) {
    cli::cli_abort(
      c(
        "That member is not in this set.",
        "i" = "A record or a link selects the member with exactly its \\
               {.field id} -- project, name, kind and version.",
        "i" = "See what the set holds with {.fn datom_list_members}, or select \\
               by name."
      ),
      class = "datom_member_not_found"
    )
  }

  at
}


#' Which Members Does This Call Refer To?
#'
#' The plural selector both edit verbs share. [.datom_find_member()] resolves
#' exactly **one** member and aborts on an ambiguous name, which is right for a
#' fetch and only half of what an edit needs: an edit legitimately acts on many.
#'
#' Three routes, and the difference between them is how many members they can
#' return:
#'
#' | What arrives | What comes back |
#' |---|---|
#' | no `member` | every member, narrowed by `tags` and `version` |
#' | a name | exactly one, aborting when the name is ambiguous |
#' | a record or a link | exactly the member carrying that `id` |
#'
#' **An explicitly named member that is ambiguous aborts**, and that is not in
#' tension with the caller who sweeps: a sweep can honour "refresh everything"
#' while skipping a name it cannot choose between, whereas a caller who named one
#' member asked for something that cannot be done, so it is a user error and the
#' narrowing arguments are what resolve it. The abort comes from
#' [.datom_find_member()] rather than from a second copy of that message.
#'
#' `tags` and `version` narrow a **name** or a sweep. Supplied beside a record or
#' a link they are refused rather than ignored, because ignoring them would act
#' on a different member than the one asked for and report success.
#'
#' @param members The set's member list.
#' @param member A name, a member record, a `datom_link`, or `NULL` for all.
#' @param tags Optional label filter.
#' @param version Optional version, or a prefix of one.
#' @param version_arg The calling verb's name for `version`, for messages.
#' @return An integer vector of positions in `members`, never empty.
#' @keywords internal
.datom_select_members <- function(members, member = NULL, tags = NULL,
                                  version = NULL, version_arg = "version") {
  if (!is.null(member)) {
    got <- .datom_member_shape(member)
    shape <- got$shape

    if (is.null(got$record)) {
      record <- .datom_find_member(members, member, tags, version)
      return(which(vapply(
        members, function(m) identical(m, record), logical(1L)
      )))
    }

    if (!is.null(tags) || !is.null(version)) {
      cli::cli_abort(
        c(
          "{.arg tags} and {.arg {version_arg}} narrow a member {.emph name}, \\
           and you passed {shape}.",
          "i" = "{shape} already names one exact member, so a filter beside it \\
                 could only disagree with it.",
          "i" = "Drop the filter, or pass the member's name instead."
        ),
        class = "datom_member_filter_ignored"
      )
    }

    return(.datom_match_member_id(members, got$record))
  }

  keep <- rep(TRUE, length(members))
  if (!is.null(tags)) {
    keep <- keep & vapply(
      members, function(m) .datom_member_has_tags(m, tags), logical(1L)
    )
  }
  if (!is.null(version)) {
    keep <- keep & vapply(
      members,
      function(m) isTRUE(startsWith(.datom_id_text(m$id, "version"), version)),
      logical(1L)
    )
  }

  at <- which(keep)
  if (length(at) > 0L) return(at)

  if (length(members) == 0L) {
    cli::cli_abort(
      c(
        "This set has no members, so there is nothing to select.",
        "i" = "A set with no members cannot be written either -- build one with \\
               {.fn datom_assemble_set} and {.fn datom_add_member}."
      ),
      class = "datom_member_not_found"
    )
  }

  lines <- .datom_member_lines(members)
  cli::cli_abort(
    c(
      "No member of this set matches what you narrowed by.",
      "i" = "{length(members)} member{?s} in the set:",
      .datom_line_bullets(lines),
      "i" = "A label filter needs the key and the exact value; a version may be \\
             given as a prefix."
    ),
    class = "datom_member_not_found"
  )
}


# --- the connections -------------------------------------------------------------

#' The Supplied Connections, Keyed by the Project Each One Claims
#'
#' One connection or a list of them, because a set legitimately spans projects
#' and access in datom is per project. The key is `conn$project_name`, which
#' nothing verifies -- see this file's header for what confirms the choice
#' afterwards.
#'
#' **Two connections claiming one project are refused rather than ordered**, since
#' choosing between them would be a guess and the wrong one reads another
#' project's namespace.
#'
#' @param conn A `datom_conn`, or a list of them.
#' @param arg Argument name for the message.
#' @return A named list of connections.
#' @keywords internal
.datom_edit_conns <- function(conn, arg = "conn") {
  conns <- if (inherits(conn, "datom_conn")) list(conn) else conn

  remedy <- paste0(
    "Pass one connection, or one per project the set spans: ",
    "{.code list(conn_a, conn_b)}."
  )

  if (!is.list(conns) || length(conns) == 0L) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a {.cls datom_conn} from {.fn datom_get_conn}, or \\
         a list of them.",
        "i" = "You passed {.cls {class(conn)}}.",
        "i" = remedy
      ),
      class = "datom_not_a_conn"
    )
  }

  ok <- vapply(conns, function(cn) inherits(cn, "datom_conn"), logical(1L))
  if (!all(ok)) {
    cli::cli_abort(
      c(
        "Every entry of {.arg {arg}} must be a {.cls datom_conn}.",
        "i" = "Entr{?y/ies} {.val {which(!ok)}} {?is/are} not one.",
        "i" = remedy
      ),
      class = "datom_not_a_conn"
    )
  }

  labels <- vapply(
    conns,
    function(cn) {
      if (.datom_is_text_scalar(cn$project_name)) cn$project_name else NA_character_
    },
    character(1L)
  )

  if (anyNA(labels)) {
    cli::cli_abort(
      c(
        "Every connection must name the project it is for.",
        "i" = "Members are matched to connections by project name, so a \\
               connection without one cannot serve any member.",
        "i" = "Open it with {.fn datom_get_conn}, which sets the name."
      ),
      class = "datom_not_a_conn"
    )
  }

  duplicated_labels <- unique(labels[duplicated(labels)])
  if (length(duplicated_labels) > 0L) {
    cli::cli_abort(
      c(
        "Two connections are for project {.val {duplicated_labels}}.",
        "i" = "One project is served by one connection here; choosing between \\
               two would be a guess, and the wrong one reads a different \\
               namespace.",
        "i" = "Pass one connection per project."
      ),
      class = "datom_edit_conn_duplicate"
    )
  }

  stats::setNames(conns, labels)
}


#' Each Artifact's Current Version in One Project, in One Read
#'
#' The manifest carries `current_version` per artifact, so learning what moved
#' costs **one read per project** rather than one per member. Only the members
#' that actually move then pay a snapshot read, through [datom_member()], which
#' is what keeps the new pointer trustworthy.
#'
#' The manifest is read directly rather than through [datom_list()] for two
#' reasons: `datom_list()` abbreviates that column to 8 characters by default,
#' which is not a version a member can record, and its abort would name S3 on a
#' local backend.
#'
#' An unreadable manifest **refuses**. It is the one answer that cannot be
#' reported: a member whose project could not be read is a member whose state is
#' unknown, which is the same situation as a missing connection.
#'
#' @param conn A connection to the project.
#' @return A named character vector of artifact name to current version, with
#'   `NA` for an entry that records none. Empty when the project has no
#'   artifacts.
#' @keywords internal
.datom_current_artifact_versions <- function(conn) {
  read <- .datom_read_manifest(conn, scope = "storage", operation = "read")

  if (!isTRUE(read$ok)) {
    why <- if (is.null(read$error)) {
      "the document could not be read"
    } else {
      conditionMessage(read$error)
    }
    cli::cli_abort(
      c(
        "Could not read the manifest for project \\
         {.val {conn$project_name}}.",
        "i" = "It is what says which version of each artifact is current, so \\
               without it whether those members moved is unknown.",
        "i" = "Underlying error: {why}"
      ),
      class = "datom_edit_manifest_unreadable"
    )
  }

  artifacts <- read$manifest$artifacts
  if (!is.list(artifacts) || length(artifacts) == 0L ||
      is.null(names(artifacts))) {
    return(stats::setNames(character(), character()))
  }

  vapply(
    names(artifacts),
    function(nm) {
      entry <- artifacts[[nm]]
      # Presence first: `entry[["current_version"]]` on an entry that lacks the
      # field is a subscript error rather than NULL.
      value <- if (is.list(entry) && "current_version" %in% names(entry)) {
        entry$current_version
      }
      if (.datom_is_text_scalar(value)) value else NA_character_
    },
    character(1L)
  )
}


# --- repointing one member -------------------------------------------------------

#' Repoint One Member at One Version
#'
#' Points 1, 2 and 3 of this file's header all live here: the labels are attached
#' verbatim rather than passed through the constructor, the link is rebuilt
#' through the shared factory, and the rebuilt record's recorded project is
#' compared against the one it replaces.
#'
#' @param record The member record being replaced.
#' @param conn The connection for that member's project.
#' @param version The version to pin.
#' @return The new member record, carrying the old labels and, when the old
#'   record had one, a link to the new version.
#' @keywords internal
.datom_repoint_member <- function(record, conn, version) {
  # NO TAGS PASSED IN. `datom_member()` drops a tag key whose value is empty, so
  # handing it the old labels can hand back fewer -- and labels are content.
  fresh <- datom_member(conn, .datom_id_text(record$id, "name"), version)

  was <- .datom_id_text(record$id, "project")
  if (!identical(fresh$id$project, was)) {
    cli::cli_abort(
      c(
        "Repointing {.val {fresh$id$name}} would move it from project \\
         {.val {was}} to project {.val {fresh$id$project}}.",
        "i" = "A connection's project name is a label nothing checks against \\
               the repo, so the connection used here is labelled \\
               {.val {was}} while its store holds project \\
               {.val {fresh$id$project}}.",
        "i" = "A same-named artifact in another project is a different \\
               artifact, so repointing at it would be silent.",
        "i" = "Open a connection whose store really is project {.val {was}}'s \\
               and retry."
      ),
      class = "datom_update_project_mismatch"
    )
  }

  # Verbatim, and before the link is built, so the link's carried record holds
  # them too.
  if (length(record$tags) > 0L) fresh$tags <- record$tags

  # Only for a member that had a link, or a draft's members would grow a field
  # they never carried.
  if (is.function(record$fetch)) {
    fresh$fetch <- .datom_member_as_link(fresh)

    # A tripwire, not the guarantee: the guarantee is that every edit path
    # rebuilds the link from the record through the one factory above. This is
    # what reddens if a later change edits a record without rebuilding.
    if (!identical(attr(fresh$fetch, "datom_member")$id, fresh$id)) {
      cli::cli_abort(
        c(
          "Internal error: a repointed member's link disagrees with its \\
           record.",
          "i" = "Please report this at \\
                 {.url https://github.com/amashadihossein/datom/issues}."
        ),
        class = "datom_member_link_drift"
      )
    }
  }

  fresh
}


# --- the report -------------------------------------------------------------------

#' One Display Line Per Moved Member, Grouped by Project
#'
#' Grouped by project because that is the axis connections are supplied along, so
#' a surprise in the grouping is a surprise about which connection served what.
#'
#' @param changes The change table.
#' @param abbreviate Whether to shorten versions to 8 characters (the console)
#'   or leave them whole (a commit message, where git is the durable record).
#' @return A character vector of lines.
#' @keywords internal
.datom_update_lines <- function(changes, abbreviate = TRUE) {
  short <- function(v) if (abbreviate) substr(v, 1L, 8L) else v

  unlist(
    lapply(unique(changes$project), function(p) {
      rows <- changes[changes$project == p, , drop = FALSE]
      c(
        paste0("project ", p, ":"),
        sprintf("  %s  %s -> %s", rows$name, short(rows$from), short(rows$to))
      )
    }),
    use.names = FALSE
  )
}


#' Say What Moved, What Did Not, and That Nothing Was Written
#'
#' The report is the deliverable rather than decoration: nothing is written, so
#' this is the dry run, and it is the only place the caller sees what an
#' inferred "current" resolved to.
#'
#' Lines are emitted with [cli::cli_verbatim()] because they embed artifact names
#' and label values, and cli reads `{anything}` in message text as markup -- an
#' artifact called `dm{1}` would be a parse error rather than a line.
#'
#' @param changes The change table, possibly with zero rows.
#' @param gone The selected members whose artifact no longer appears in its
#'   project.
#' @param skipped_lines Description lines for members skipped as ambiguous.
#' @param n_selected How many members the call selected.
#' @param n Maximum number of lines to print before truncating.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_report_member_updates <- function(changes, gone, skipped_lines,
                                        n_selected, n = 20L) {
  moved <- nrow(changes)

  if (moved == 0L) {
    cli::cli_alert_info(
      "No member moved: all {n_selected} selected {?is/are} already at the \\
       version this would pin."
    )
  } else {
    cli::cli_alert_success(
      "Repointed {moved} member{?s}, of {n_selected} selected."
    )
    lines <- .datom_update_lines(changes)
    if (length(lines) > n) {
      extra <- length(lines) - n
      lines <- c(lines[seq_len(n)], paste0("... and ", extra, " more"))
    }
    cli::cli_verbatim(lines)
  }

  if (nrow(gone) > 0L) {
    cli::cli_alert_warning(
      "Left {nrow(gone)} member{?s} pinned: no artifact of that name is listed \\
       in its project now."
    )
    cli::cli_verbatim(
      sprintf("  %s (%s) in %s", gone$name, gone$kind, gone$project)
    )
    cli::cli_alert_info(
      "The pin still reads -- a version is immutable -- so the set is still \\
       writable."
    )
    cli::cli_alert_info(
      "A manifest can also lag a write that got partway through, so it is not \\
       proof the artifact is gone: check with {.fn datom_list} on that project."
    )
  }

  if (length(skipped_lines) > 0L) {
    cli::cli_alert_warning(
      "Skipped {length(skipped_lines)} member{?s}: that artifact name appears \\
       more than once in this set."
    )
    cli::cli_verbatim(paste0("  ", skipped_lines))
    cli::cli_alert_info(
      "That is legal -- a current table beside a locked baseline, say -- and \\
       only your labels say which is which, so choosing would be a guess."
    )
    cli::cli_alert_info(
      "Repoint one deliberately: narrow by label with \\
       {.code tags = list(release = \"live\")}, or pick it out with \\
       {.code version_from = }."
    )
  }

  if (moved > 0L) {
    cli::cli_alert_info(
      "Nothing has been written. Write the set with \\
       {.code datom_write_set(conn, x)}."
    )
  }

  invisible(NULL)
}


#' The Commit Message a Set Write Uses
#'
#' A set write commits `Update {name}`, which says nothing in `git log`. When an
#' update produced a change list and the caller passed no `message`, the default
#' names what moved instead.
#'
#' Two messages, because they go to two places. The **subject** is recorded as the
#' version's `commit_message`, where one line is what [datom_history()] can show.
#' The **commit** gets the subject plus the full list, with whole versions rather
#' than prefixes: git is the durable record, so completeness belongs there rather
#' than on screen.
#'
#' An explicit `message` always wins, and a change list of the wrong shape is
#' ignored rather than trusted -- it is an attribute, so a caller can put anything
#' there.
#'
#' @param name The set's name.
#' @param message The caller's `message`, or `NULL`.
#' @param updates The change list carried by the object being written, or `NULL`.
#' @return A list of `history` (a single line, or `NULL` to leave the existing
#'   default in place) and `commit`.
#' @keywords internal
.datom_set_commit_messages <- function(name, message, updates) {
  if (!is.null(message)) return(list(history = message, commit = message))

  fallback <- paste0("Update ", name)
  usable <- is.data.frame(updates) && nrow(updates) > 0L &&
    all(c("project", "name", "from", "to") %in% names(updates))
  if (!usable) return(list(history = NULL, commit = fallback))

  subject <- paste0(
    fallback, ": repoint ", nrow(updates), " member",
    if (nrow(updates) == 1L) "" else "s"
  )
  body <- paste(.datom_update_lines(updates, abbreviate = FALSE),
                collapse = "\n")

  list(history = subject, commit = paste0(subject, "\n\n", body))
}


# --- the verb ---------------------------------------------------------------------

#' Repoint a set's members at newer versions
#'
#' Moves members of a set forward to the versions that are current now, and
#' returns the set with those pointers changed. **Nothing is written**: the
#' report you see is the dry run, and the set is stored only when you pass the
#' result to [datom_write_set()].
#'
#' This is the operation a product needs when its inputs move on -- a hundred
#' members of which thirty upstream tables have advanced. Doing it by hand is
#' list surgery on what [datom_get_set()] returned, and two of the obvious
#' spellings are silently wrong: filtering members by name drops *every* version
#' of that name, and rebuilding a pointer from its name plus a new version drops
#' that member's labels.
#'
#' @section Which connection to pass:
#' One per project the set spans, since access in datom is per project. A set
#' whose members all live in the project that owns it needs only that one
#' connection; a product drawing on three studies needs three, in a list.
#'
#' A set's projects can be listed **offline, with no connection at all**:
#'
#' ```r
#' unique(datom_list_members(x)$project)
#' ```
#'
#' A `datom_set_draft` carries the connection it was opened with, and this verb
#' **ignores** it: a draft carries exactly one while this call legitimately spans
#' several, and quietly preferring the embedded one would make the same call
#' behave differently depending on how `x` was produced.
#'
#' @section Which members move:
#' With no `member`, **every** member -- refreshing everything is the common case
#' and rerunning it changes nothing. Otherwise select one the way
#' [datom_fetch_member()] does: by name, by a member record, or by a link. `tags`
#' and `version_from` narrow either a name or the sweep, so
#' `tags = list(release = "live")` repoints the labelled members and leaves the
#' rest pinned.
#'
#' A name that matches more than one member **aborts**, because the request
#' cannot be honoured as typed; a *sweep* that meets the same pair skips it and
#' says so, because refusing a whole refresh over one frozen baseline would make
#' the first update on such a set an error.
#'
#' @section Which version each member moves to:
#' `version_to` omitted, each selected member moves to the version its own
#' project reports as current, and every move is reported before anything is
#' written. That is the one place datom infers "newest", and the reason it is
#' allowed here is in the verb's name: a pointer *constructor* requires an
#' explicit version ([datom_member()] refuses to guess), while a verb whose whole
#' meaning is *move this forward* states the time-dependence up front and then
#' says what it picked. What the set records is still an exact version, so a
#' script that later reads that set is as reproducible as ever.
#'
#' `version_to` supplied, the selected member moves to exactly that version --
#' a rollback to a known-good, or a deliberate step to something that is not the
#' newest. It requires the selection to resolve to one member, because one
#' explicit version across several artifacts is not a meaning. It is also what
#' makes this verb better than removing and re-adding a member: **the labels come
#' with it**, where re-adding makes you retype them.
#'
#' @section What it declines to do, and how:
#' | Situation | Response |
#' |---|---|
#' | a member's project has no supplied connection | the whole call is refused, naming that project |
#' | a member's artifact no longer appears in its project | reported, and its pin is left alone |
#' | two members share a name and a project | both skipped and reported |
#'
#' The first refuses because whether those members moved is unknowable, and
#' reporting them as unchanged would state something nothing checked. The second
#' does not, because the answer *is* known: the pinned version is immutable and
#' still reads, so the set stays writable.
#'
#' @section What comes back:
#' The class it was handed -- a `datom_set` for a `datom_set` and a
#' `datom_set_draft` for a draft -- with matching members repointed and each
#' moved member's labels byte-identical to what they were.
#'
#' When something moved, a `datom_set`'s `version` and `data_sha` are emptied:
#' they described the payload it was read as, and that is no longer what the
#' object holds. When nothing moved they are left alone, because the object still
#' describes exactly that stored version.
#'
#' The returned object also carries the change list as an attribute, which
#' [datom_write_set()] uses for the commit message when you pass no `message` of
#' your own -- so `git log` names what moved instead of saying `Update {name}`.
#' Passing `x$members` rather than `x` to the write loses that and nothing else.
#'
#' @param x A `datom_set` from [datom_get_set()], or a `datom_set_draft` from
#'   [datom_assemble_set()].
#' @param conn A `datom_conn` from [datom_get_conn()], or a list of them -- one
#'   per project the selected members belong to.
#' @param member Optional: the member to repoint, as its name, a member record,
#'   or a link. `NULL` (the default) selects every member.
#' @param tags Optional named list of labels narrowing the selection, e.g.
#'   `list(type = "input")`. A member matches when it carries every label listed.
#' @param version_from Optional version, or a prefix of one, narrowing the
#'   selection to the member pinned at it.
#' @param version_to Optional exact version to move to. `NULL` (the default)
#'   means whatever that artifact's project reports as current. Requires the
#'   selection to resolve to a single member.
#'
#' @return `x` with the matching members repointed, and its change list attached
#'   as the `datom_updates` attribute.
#' @seealso [datom_write_set()] to store the result, [datom_list_members()] to
#'   see what a set holds, [datom_member()] to build a pointer from scratch.
#' @export
#'
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   # A product repo declares itself as one and names the single set it owns.
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store,
#'                   mode = "product", set = "example_product")
#'
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   dm <- datom_example_data("dm")
#'   datom_write(conn, data = dm, name = "dm")
#'   datom_write_set(conn, list(
#'     datom_member(conn, "dm", datom_history(conn, "dm")$version[1],
#'                  tags = list(type = "input"))
#'   ))
#'
#'   # The table moves on, so the set now cites an older version of it.
#'   datom_write(conn, data = dm[-1, , drop = FALSE], name = "dm")
#'
#'   x <- datom_get_set(conn, "example_product")
#'   x <- datom_update_members(x, conn)
#'
#'   # The label came with it, and nothing is stored until the write.
#'   print(datom_list_members(x))
#'   datom_write_set(conn, x)
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_update_members <- function(x, conn, member = NULL, tags = NULL,
                                 version_from = NULL, version_to = NULL) {

  members <- .datom_edit_members(x)
  conns <- .datom_edit_conns(conn)

  if (!is.null(tags)) {
    .datom_validate_tag_map(
      tags, "tags",
      remedy = "Narrow by labels a member carries, e.g. \\
                {.code list(type = \"input\")}."
    )
  }
  if (!is.null(version_from) && !.datom_is_text_scalar(version_from)) {
    cli::cli_abort(
      c(
        "{.arg version_from} must be a single non-empty string.",
        "i" = "It says which member to repoint -- a version, or a prefix of \\
               one, as {.fn datom_history} reports them."
      )
    )
  }
  if (!is.null(version_to) &&
      (!.datom_is_text_scalar(version_to) ||
       !grepl("^[0-9a-f]{64}$", version_to))) {
    cli::cli_abort(
      c(
        "{.arg version_to} must be a full 64-character version.",
        "i" = "A member records the exact version it pins, so a prefix cannot \\
               be stored -- unlike {.arg version_from}, which only has to \\
               match.",
        "i" = "Take the whole string from \\
               {.code datom_history(conn, \"dm\")$version}."
      ),
      class = "datom_update_version_to_invalid"
    )
  }

  at <- .datom_select_members(members, member, tags, version_from,
                             "version_from")

  if (!is.null(version_to) && length(at) > 1L) {
    lines <- .datom_member_lines(members[at])
    cli::cli_abort(
      c(
        "{.arg version_to} names one version, and this call selects \\
         {length(at)} members.",
        "i" = "Each artifact has its own versions, so one explicit version \\
               across several of them is not a meaning.",
        .datom_line_bullets(lines),
        "i" = "Narrow to one member -- by name, by {.arg tags}, or with \\
               {.arg version_from} -- or drop {.arg version_to} to move every \\
               selected member to its project's current version."
      ),
      class = "datom_update_target_ambiguous"
    )
  }

  # Every selected member has to be resolvable before any read happens, so an
  # unusable pointer is reported as one rather than as a missing artifact.
  ids <- lapply(at, function(i) .datom_member_id(members[[i]]))

  selected <- data.frame(
    i = at,
    project = vapply(ids, function(id) id$project, character(1L)),
    name = vapply(ids, function(id) id$name, character(1L)),
    kind = vapply(ids, function(id) id$kind, character(1L)),
    from = vapply(ids, function(id) id$version, character(1L)),
    stringsAsFactors = FALSE
  )

  unknown <- setdiff(unique(selected$project), names(conns))
  if (length(unknown) > 0L) {
    cli::cli_abort(
      c(
        "No connection was supplied for project {.val {unknown}}.",
        "i" = "Whether those members moved is unknowable without one, and \\
               leaving them alone silently would report a refresh that did not \\
               happen.",
        "i" = "List the projects a set spans offline, with no connection: \\
               {.code unique(datom_list_members(x)$project)}.",
        "i" = "Then pass one connection each: \\
               {.code datom_update_members(x, list(conn_a, conn_b))}."
      ),
      class = "datom_update_conn_missing"
    )
  }

  # Skipped on the sweep, because only the caller's labels say which of a live
  # table and a frozen baseline is which. Keyed on project AND name: two projects
  # may both hold a `dm`, and those two move independently with nothing to guess.
  # An explicitly named member never reaches this -- the selector aborts there.
  # "\r" as the separator, for the reason the payload check uses it: an artifact
  # name may hold a printable separator, so a printable one could make two
  # different members collide into one key.
  key <- paste(selected$project, selected$name, sep = "\r")
  is_shared <- key %in% unique(key[duplicated(key)])
  skipped <- selected[is_shared, , drop = FALSE]
  selected <- selected[!is_shared, , drop = FALSE]

  # One manifest read per project that still has a candidate in it, never one per
  # member.
  targets <- if (is.null(version_to)) {
    projects <- unique(selected$project)
    currents <- stats::setNames(
      lapply(projects, function(p) .datom_current_artifact_versions(conns[[p]])),
      projects
    )
    vapply(
      seq_len(nrow(selected)),
      function(k) {
        current <- currents[[selected$project[[k]]]]
        nm <- selected$name[[k]]
        if (nm %in% names(current)) current[[nm]] else NA_character_
      },
      character(1L)
    )
  } else {
    rep(version_to, nrow(selected))
  }

  gone <- selected[is.na(targets), , drop = FALSE]
  moves <- !is.na(targets) & targets != selected$from
  changes <- selected[moves, , drop = FALSE]
  changes$to <- targets[moves]

  if (nrow(changes) > 0L) {
    repointed <- purrr::map(
      seq_len(nrow(changes)),
      function(k) {
        .datom_repoint_member(
          members[[changes$i[[k]]]],
          conns[[changes$project[[k]]]],
          changes$to[[k]]
        )
      }
    )
    members[changes$i] <- repointed

    x$members <- members
    x <- .datom_forget_set_identity(x)
    attr(x, "datom_updates") <- changes[
      , c("project", "name", "kind", "from", "to"), drop = FALSE
    ]
  }

  .datom_report_member_updates(
    changes = changes,
    gone = gone,
    skipped_lines = if (nrow(skipped) > 0L) {
      .datom_member_lines(members[skipped$i])
    } else {
      character()
    },
    n_selected = length(at)
  )

  x
}
