# Syncing a product repo's set against its source projects: map what the sources
# hold, review it as a data frame, apply it. The same shape table sync has on an
# ordinary repo, reached through the same two verbs -- `datom_sync_manifest()`
# and `datom_sync()` branch once, at the top, on what `.datom/project.yaml`
# declares. This file is the product-repo half; `R/sync.R` holds the branch.
#
# THE LOAD-BEARING RULES HERE:
#
#   1. "NO SET YET" IS DECIDED BY A PRESENCE PROBE, NEVER BY A FAILED READ. A
#      set read aborts the same way for a missing document and for storage that
#      cannot be reached, so catching its error would report "first version --
#      every artifact new" when storage is down. The probe answers absence; its own
#      failure, and any failure after it answers "present", propagates.
#
#   2. EVERY MEMBER LANDS IN EXACTLY ONE PLACE. An output (the repo's own
#      project) gets no row; a member of a project not passed is `not_checked`;
#      a member whose artifact left its source is named in the messages; one
#      filtered out by `pattern` is `excluded`; the rest are the rows the
#      sources produce. So the frame accounts for every member of every source,
#      and nothing is silently ignored. Tables and sets are treated alike
#      throughout: a set built from sets is what sets are for, and a preview
#      that skipped set members would leave sync the one edit verb unable to
#      move one.
#
#   3. MEMBERS ARE MATCHED TO SOURCES ON THE CONNECTION'S LABEL, AND THE LABEL IS
#      CHECKED AGAINST THE SOURCE'S OWN MANIFEST. A wrong label would otherwise
#      show every artifact as new and every member as not checked, and fail only
#      later. The manifest read is one the preview makes anyway, so the check
#      costs no IO; a manifest that records no name is not checked.
#
#   4. NOTHING HERE WRITES. The preview is a report, so it needs no confirmation
#      prompt, and a refusal anywhere leaves nothing behind. Apply hands back an
#      edited set; `datom_write_set()` stays the only thing that stores one.
#
#   5. APPLY TRUSTS THE FRAME'S SHAPE, NEVER ITS FACTS. It takes any rows with
#      the right columns -- a subset, a hand-built frame -- so every fact a row
#      states is re-checked before it lands: the member it moves must still be
#      where the preview saw it (else the preview is stale, like a push refused
#      because the remote moved), and a new member is read from its source,
#      which confirms its version exists and records its project and kind. Every
#      check that needs no read runs before the first read.


#' Refuse `sources =` (or Another Set-Path Argument) on an Ordinary Repo
#'
#' @param arg The argument that was supplied.
#' @return Does not return; aborts with class `datom_sync_sources_on_ordinary`.
#' @keywords internal
.datom_refuse_sources_on_ordinary <- function(arg) {
  cli::cli_abort(
    c(
      "{.arg {arg}} is for a product repo, and this repo does not declare \\
       {.code mode: product}.",
      "i" = "Sets live in product repos. There, the sync verbs map the repo's \\
             set against the source projects passed in {.arg sources}.",
      "i" = "Here they import source files. Drop {.arg {arg}} to do that."
    ),
    class = "datom_sync_sources_on_ordinary"
  )
}


#' Refuse a File-Import Argument on a Product Repo
#'
#' Silently ignoring it would let a caller believe the argument did something.
#'
#' @param arg The argument that was supplied.
#' @return Does not return; aborts with class `datom_sync_file_arg_on_product`.
#' @keywords internal
.datom_refuse_file_arg_on_product <- function(arg) {
  cli::cli_abort(
    c(
      "{.arg {arg}} is for importing source files, and this repo declares \\
       {.code mode: product}.",
      "i" = "On a product repo the sync verbs map the repo's set against the \\
             projects in {.arg sources}; they read no files.",
      "i" = "Drop {.arg {arg}}."
    ),
    class = "datom_sync_file_arg_on_product"
  )
}


#' The Product Repo's Declared Set Name, or an Abort Saying There Is None
#'
#' @param set_name What `.datom/project.yaml` declares under `set`.
#' @return The set name.
#' @keywords internal
.datom_sync_set_name <- function(set_name) {
  if (!.datom_is_text_scalar(set_name)) {
    cli::cli_abort(
      c(
        "This repo declares {.code mode: product} but names no set.",
        "i" = "Add {.code set: <name>} to {.file .datom/project.yaml}.",
        "i" = "Without it there is no set to map the sources against."
      ),
      class = "datom_set_undeclared"
    )
  }

  .datom_validate_name(set_name)

  set_name
}


#' The Repo's Set As Stored, or an Empty One When It Has Never Been Written
#'
#' See point 1 of this file's header. The probe is on the set's current-state
#' document, which is what [datom_get_set()] reads first. `FALSE` means the set
#' has never been written; `TRUE` means read it, and any error from that read is
#' the caller's to see. An error from the probe itself is never absence: an
#' unreachable store cannot report that a file is missing.
#'
#' @param conn The product repo's developer connection.
#' @param name The set's name.
#' @return A `datom_set`.
#' @keywords internal
.datom_sync_read_set <- function(conn, name) {
  key <- .datom_artifact_meta_key(name, "metadata")

  if (!isTRUE(.datom_storage_exists(conn, key))) {
    return(.datom_empty_set(name, conn$project_name))
  }

  datom_get_set(conn, name)
}


#' Refuse the Set's Own Project as a Source
#'
#' The set's own project holds its outputs, which are derived from the inputs
#' and move only once they are re-derived. Checked on the labels, before any
#' read.
#'
#' @param own The set's own project name.
#' @param labels The project names of the source connections.
#' @return Invisibly `NULL`; aborts with class `datom_sync_own_project_source`.
#' @keywords internal
.datom_refuse_own_project_source <- function(own, labels) {
  if (!isTRUE(own %in% labels)) return(invisible(NULL))

  cli::cli_abort(
    c(
      "{.arg sources} includes this repo's own project, {.val {own}}.",
      "i" = "Tables in the set's own project are its outputs, derived from the \\
             inputs, so sync does not map or move them.",
      "i" = "Re-derive an output, write it, then move it with \\
             {.code datom_update_members(x, conn, tags = list(type = \"output\"))}."
    ),
    class = "datom_sync_own_project_source"
  )
}


#' One Source's Artifacts, After Checking Its Label Against Its Own Manifest
#'
#' See point 3 of this file's header.
#'
#' @param conn A source connection.
#' @return The `artifacts` frame from [.datom_current_artifacts()].
#' @keywords internal
.datom_sync_source_artifacts <- function(conn) {
  current <- .datom_current_artifacts(conn)

  declared <- current$project_name
  if (!is.null(declared) && !identical(declared, conn$project_name)) {
    label <- conn$project_name
    cli::cli_abort(
      c(
        "A connection in {.arg sources} is labelled {.val {label}}, and the \\
         project it reads calls itself {.val {declared}}.",
        "i" = "Members are matched to sources by project name, so with the \\
               wrong label every artifact would look new and every member \\
               unchecked.",
        "i" = "Open the connection for project {.val {declared}} with \\
               {.fn datom_get_conn}, or pass the store for {.val {label}}."
      ),
      class = "datom_sync_source_mislabelled"
    )
  }

  current$artifacts
}


#' Does a Name Match a Sync Glob?
#'
#' The same glob rule the file scan applies to file names.
#'
#' @param names Artifact names.
#' @param pattern A glob, `"*"` for everything.
#' @return A logical vector.
#' @keywords internal
.datom_sync_name_matches <- function(names, pattern) {
  if (identical(pattern, "*")) return(rep(TRUE, length(names)))
  grepl(utils::glob2rx(pattern), names)
}


#' Map a Product Repo's Set Against Its Sources
#'
#' The product-repo route of [datom_sync_manifest()]. Three kinds of read: the
#' stored set (or none), one manifest per source, nothing per artifact.
#'
#' @param conn The product repo's developer connection.
#' @param set_name The set name `.datom/project.yaml` declares.
#' @param sources One `datom_conn` or a list of them.
#' @param pattern Glob filtering source artifact names.
#' @return The preview data frame; see [datom_sync_manifest()].
#' @keywords internal
.datom_sync_set_preview <- function(conn, set_name, sources, pattern) {
  set_name <- .datom_sync_set_name(set_name)
  conns <- .datom_edit_conns(sources, arg = "sources")

  own <- conn$project_name
  .datom_refuse_own_project_source(own, names(conns))

  x <- .datom_sync_read_set(conn, set_name)
  members <- .datom_edit_members(x)

  # `lapply()`, not `purrr::map()`: the mislabelled-source and unreadable-manifest
  # refusals are dispatched on by class, and purrr would re-wrap them.
  # Tables and sets both; an entry whose kind this build does not know gets no
  # row, since nothing here could compare or move it.
  arts <- lapply(names(conns), function(p) {
    art <- .datom_sync_source_artifacts(conns[[p]])
    art <- art[art$kind %in% .datom_artifact_kinds, , drop = FALSE]
    art <- art[order(art$name, method = "radix"), , drop = FALSE]
    art$project <- rep(p, nrow(art))
    art
  })
  arts <- do.call(rbind, arts)
  arts$matches <- .datom_sync_name_matches(arts$name, pattern)

  ids <- lapply(members, .datom_member_id)
  mem <- data.frame(
    i = seq_along(members),
    project = vapply(ids, function(id) id$project, character(1L)),
    name = vapply(ids, function(id) id$name, character(1L)),
    kind = vapply(ids, function(id) id$kind, character(1L)),
    version = vapply(ids, function(id) id$version, character(1L)),
    stringsAsFactors = FALSE
  )

  # "\r" as the key separator, for the reason `datom_update_members()` uses it:
  # an artifact name may hold a printable separator.
  # Keyed on (project, name) and not kind: one project is one namespace, so a
  # name there is one artifact. A row's `kind` is the source's; apply checks it
  # against the member it moves.
  art_key <- paste(arts$project, arts$name, sep = "\r")
  mem_key <- paste(mem$project, mem$name, sep = "\r")

  # Where each member goes -- point 2 of this file's header.
  is_output <- mem$project == own
  is_unpassed <- !is_output & !(mem$project %in% names(conns))
  is_compared <- !is_output & !is_unpassed

  at <- match(mem_key, art_key)
  is_gone <- is_compared & is.na(at)
  is_excluded <- is_compared & !is_gone & !arts$matches[at]

  # The rows the sources produce: artifacts that match the pattern and record a
  # current version.
  listed <- arts[arts$matches & !is.na(arts$current_version), , drop = FALSE]
  listed_key <- paste(listed$project, listed$name, sep = "\r")

  pinned <- lapply(listed_key, function(k) which(is_compared & mem_key == k))
  n_pinned <- lengths(pinned)

  version_from <- vapply(
    seq_along(pinned),
    function(k) {
      if (n_pinned[[k]] == 1L) mem$version[[pinned[[k]]]] else NA_character_
    },
    character(1L)
  )

  status <- ifelse(
    n_pinned == 0L, "new",
    ifelse(n_pinned > 1L, "ambiguous",
           ifelse(version_from == listed$current_version, "unchanged",
                  "changed"))
  )

  source_rows <- data.frame(
    project = listed$project,
    name = listed$name,
    kind = listed$kind,
    version_from = version_from,
    version_to = listed$current_version,
    status = as.character(status),
    stringsAsFactors = FALSE
  )

  member_rows <- function(which_rows, status) {
    data.frame(
      project = mem$project[which_rows],
      name = mem$name[which_rows],
      kind = mem$kind[which_rows],
      version_from = mem$version[which_rows],
      version_to = rep(NA_character_, sum(which_rows)),
      status = rep(status, sum(which_rows)),
      stringsAsFactors = FALSE
    )
  }

  result <- rbind(
    source_rows,
    member_rows(is_excluded, "excluded"),
    member_rows(is_unpassed, "not_checked")
  )
  rownames(result) <- NULL

  ambiguous_at <- which(n_pinned > 1L)
  ambiguous_lines <- unlist(lapply(
    ambiguous_at,
    function(k) {
      paste0(.datom_member_lines(members[mem$i[pinned[[k]]]]), "  in ",
             listed$project[[k]])
    }
  ))

  # A member pinned to one of these is reported here, and only here: its
  # artifact matches the pattern, so it is not `excluded`, and it has no current
  # version to compare against, so it has no row.
  # `sprintf()`, not `paste0()`: with nothing unversioned, `paste0()` recycles
  # the empty vectors to "" and returns one " in ", which reads as one artifact.
  unversioned <- arts$matches & is.na(arts$current_version)
  unversioned_names <- sprintf("%s in %s", arts$name[unversioned],
                               arts$project[unversioned])

  .datom_report_sync_preview(
    result = result,
    n_sources = length(conns),
    ambiguous_lines = ambiguous_lines,
    ambiguous_first = if (length(ambiguous_at) > 0L) {
      listed$name[[ambiguous_at[[1L]]]]
    },
    unpassed = mem[is_unpassed, , drop = FALSE],
    gone = mem[is_gone, , drop = FALSE],
    unversioned = unversioned_names
  )

  result
}


#' Say What the Set Sync Preview Found
#'
#' One summary line, then one warning per group of rows or members the caller
#' has to know about, each with its remedy.
#'
#' @param result The preview frame.
#' @param n_sources How many sources were mapped.
#' @param ambiguous_lines One line per member behind an `ambiguous` row.
#' @param ambiguous_first The name of the first ambiguous artifact, for the
#'   remedy, or `NULL`.
#' @param unpassed,gone Member rows (`project`, `name`, `kind`, `version`) for
#'   members of a project not passed, and members whose artifact is no longer
#'   listed in their source.
#' @param unversioned `"name in project"` for artifacts whose manifest entry
#'   records no current version.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_report_sync_preview <- function(result, n_sources, ambiguous_lines,
                                       ambiguous_first, unpassed, gone,
                                       unversioned) {
  count <- function(s) sum(result$status == s)
  n_mapped <- sum(result$status %in% c("new", "changed", "unchanged",
                                       "ambiguous"))
  n_ambiguous <- count("ambiguous")
  n_excluded <- count("excluded")

  extra <- paste0(
    if (n_ambiguous > 0L) paste0(", ", n_ambiguous, " ambiguous"),
    if (n_excluded > 0L) paste0("; ", n_excluded, " excluded by pattern")
  )
  cli::cli_alert_info(
    "Mapped {n_mapped} artifact{?s} from {n_sources} source{?s}: \\
     {count('new')} new, {count('changed')} changed, \\
     {count('unchanged')} unchanged{extra}."
  )

  if (n_ambiguous > 0L) {
    lines <- ambiguous_lines
    hint <- sprintf(
      "datom_update_members(x, conn, member = \"%s\", tags = list(release = \"live\"))",
      ambiguous_first
    )
    cli::cli_alert_warning(
      "{n_ambiguous} artifact{?s} {?is/are} pinned more than once in the set, so \\
       no member for {?it/them} will move:"
    )
    cli::cli_verbatim(paste0("  ", lines))
    cli::cli_alert_info(
      "That is legal -- a live table beside a frozen baseline, say -- and only \\
       the labels say which is which."
    )
    cli::cli_alert_info("Move one deliberately: {.code {hint}}.")
  }

  if (nrow(unpassed) > 0L) {
    n <- nrow(unpassed)
    projects <- unique(unpassed$project)
    n_projects <- length(projects)
    cli::cli_alert_warning(
      "{n} member{?s} not checked: {n_projects} project{?s} {?is/are} not in \\
       {.arg sources}: {.val {projects}}."
    )
    cli::cli_alert_info(
      "They keep their versions. If that is a mistake, build the preview again \\
       with every source: \\
       {.code datom_sync_manifest(conn, sources = list(conn_a, conn_b))}."
    )
  }

  if (nrow(gone) > 0L) {
    n <- nrow(gone)
    cli::cli_alert_warning(
      "{n} member{?s} left pinned: {?its artifact is/their artifacts are} no \\
       longer listed in {?its/their} source."
    )
    cli::cli_verbatim(sprintf("  %s (%s) in %s", gone$name, gone$kind,
                              gone$project))
    cli::cli_alert_info(
      "The preview never removes a member. The pin still reads -- a version is \\
       immutable -- and {.fn datom_remove_members} drops one deliberately."
    )
  }

  if (length(unversioned) > 0L) {
    n <- length(unversioned)
    cli::cli_alert_warning(
      "{n} artifact{?s} {?has/have} no row: {?its/their} source manifest records \\
       no current version."
    )
    cli::cli_verbatim(paste0("  ", unversioned))
    cli::cli_alert_info("Check that project with {.fn datom_validate}.")
  }

  invisible(NULL)
}


# --- applying a preview -----------------------------------------------------------

#' The Columns a Set Sync Preview Carries, in Order
#'
#' @return A character vector.
#' @keywords internal
.datom_sync_preview_cols <- function() {
  c("project", "name", "kind", "version_from", "version_to", "status")
}


#' A Preview Frame Checked for Shape and Values, as Plain Text Columns
#'
#' Columns and values only, never where the frame came from: a subset or a
#' hand-built frame is as good as the preview itself. Every check runs before
#' any read.
#'
#' Values are checked only on the rows apply acts on (`new`, `changed`); the
#' others do nothing, so a hand-trimmed `not_checked` row is harmless. A short
#' `version_from` would otherwise fail the exact comparison later and stop as
#' stale, naming the wrong problem.
#'
#' @param manifest What the caller passed.
#' @return A data frame of the six preview columns, each character.
#' @keywords internal
.datom_sync_apply_frame <- function(manifest) {
  cols <- .datom_sync_preview_cols()
  remedy <- "Build it with {.code datom_sync_manifest(conn, sources = )}."

  if (!is.data.frame(manifest)) {
    cli::cli_abort(
      c(
        "{.arg manifest} must be a data frame: the set preview from \\
         {.fn datom_sync_manifest}, or any subset of its rows.",
        "i" = "You passed {.cls {class(manifest)}}.",
        "i" = remedy
      ),
      class = "datom_sync_manifest_invalid"
    )
  }

  missing_cols <- setdiff(cols, names(manifest))
  if (length(missing_cols) > 0L) {
    file_shaped <- all(c("file", "format") %in% names(manifest))
    cli::cli_abort(
      c(
        "{.arg manifest} is missing column{?s} {.val {missing_cols}}.",
        "i" = if (file_shaped) {
          "It looks like a file-import manifest, which is what an ordinary \\
           repo's sync takes. This is a product repo, so sync applies a \\
           preview of its set."
        },
        "i" = "A set preview has columns {.val {cols}}.",
        "i" = remedy
      ),
      class = "datom_sync_manifest_invalid"
    )
  }

  rows <- data.frame(
    lapply(manifest[cols], as.character),
    stringsAsFactors = FALSE
  )
  names(rows) <- cols
  rownames(rows) <- NULL

  statuses <- c("new", "changed", "unchanged", "ambiguous", "not_checked",
                "excluded")
  is_full <- function(v) !is.na(v) & grepl("^[0-9a-f]{64}$", v)
  is_text <- function(v) !is.na(v) & nzchar(v)

  acts <- rows$status %in% c("new", "changed")
  changed <- rows$status %in% "changed"

  problems <- list(
    list(bad = !rows$status %in% statuses,
         what = paste0("status is not one of ",
                       paste(statuses, collapse = ", "))),
    list(bad = acts & !is_text(rows$project), what = "project is empty"),
    list(bad = acts & !is_text(rows$name), what = "name is empty"),
    list(bad = acts & !rows$kind %in% .datom_artifact_kinds,
         what = "kind is not table or set"),
    list(bad = acts & !is_full(rows$version_to),
         what = "version_to is not a full 64-character version"),
    list(bad = changed & !is_full(rows$version_from),
         what = "version_from is not a full 64-character version"),
    list(bad = changed & is_full(rows$version_from) &
           rows$version_from == rows$version_to,
         what = "a changed row's version_to equals its version_from")
  )

  lines <- unlist(lapply(problems, function(p) {
    at <- which(p$bad)
    if (length(at) == 0L) return(character())
    sprintf("row %d (%s): %s", at, rows$name[at], p$what)
  }))

  if (length(lines) > 0L) {
    n <- length(lines)
    cli::cli_abort(
      c(
        "{.arg manifest} has {n} unusable value{?s}:",
        .datom_line_bullets(lines),
        "i" = "Versions are recorded whole, so a {.code new} or \\
               {.code changed} row needs full 64-character versions, as the \\
               preview gives them.",
        "i" = remedy
      ),
      class = "datom_sync_manifest_invalid"
    )
  }

  rows
}


#' Refuse Two Applied Rows for One Artifact
#'
#' A preview never produces them. Without this the second row would stop as
#' stale, which names the wrong problem.
#'
#' @param todo The `new` and `changed` rows.
#' @return Invisibly `NULL`; aborts with class `datom_sync_manifest_duplicate_row`.
#' @keywords internal
.datom_sync_refuse_duplicate_rows <- function(todo) {
  key <- paste(todo$project, todo$name, sep = "\r")
  dup <- unique(key[duplicated(key)])
  if (length(dup) == 0L) return(invisible(NULL))

  at <- match(dup, key)
  lines <- sprintf("%s in %s", todo$name[at], todo$project[at])
  cli::cli_abort(
    c(
      "{.arg manifest} has more than one {.code new} or {.code changed} row \\
       for the same artifact:",
      .datom_line_bullets(lines),
      "i" = "One row per artifact says where its member goes; two could only \\
             disagree.",
      "i" = "Keep one of them, or build the preview again with \\
             {.fn datom_sync_manifest}."
    ),
    class = "datom_sync_manifest_duplicate_row"
  )
}


#' Refuse Applied Rows Whose Project Has No Connection
#'
#' Only `new` and `changed` rows: they are the only ones apply acts on, and a
#' full preview's `not_checked` rows belong by definition to projects not in
#' `sources`, so checking every row would make an unedited preview impossible
#' to apply.
#'
#' @param todo The `new` and `changed` rows.
#' @param labels The project names of the source connections.
#' @return Invisibly `NULL`; aborts with class `datom_sync_source_missing`.
#' @keywords internal
.datom_sync_refuse_missing_source <- function(todo, labels) {
  unknown <- setdiff(unique(todo$project), labels)
  if (length(unknown) == 0L) return(invisible(NULL))

  cli::cli_abort(
    c(
      "{.arg manifest} has rows to apply for project{?s} {.val {unknown}}, \\
       and {.arg sources} has no connection for {?it/them}.",
      "i" = "Each added or repointed member is read from its own project first, \\
             so apply needs the connection the preview was built with.",
      "i" = "Pass the same sources to both calls: \\
             {.code datom_sync(conn, m, sources = list(conn_a, conn_b))}."
    ),
    class = "datom_sync_source_missing"
  )
}


#' Refuse a Preview the Set Has Moved Away From
#'
#' A `changed` row must find exactly one member for its artifact, at
#' `version_from`; a `new` row must find none. Anything else means the set was
#' edited after the preview was built, and acting anyway would leave a removed
#' member removed, move a member the preview never showed, or add a second
#' member for one artifact.
#'
#' @param todo The `new` and `changed` rows.
#' @param hits For each row of `todo`, the positions of the set's members with
#'   that project and name.
#' @param members The set's member list.
#' @param x_given Whether the caller passed the set, which changes the remedy:
#'   the preview always compares against the stored set.
#' @return Invisibly `NULL`; aborts with class `datom_sync_manifest_stale`.
#' @keywords internal
.datom_sync_refuse_stale <- function(todo, hits, members, x_given) {
  short <- function(v) substr(v, 1L, 8L)

  lines <- unlist(lapply(seq_len(nrow(todo)), function(k) {
    row <- todo[k, , drop = FALSE]
    at <- hits[[k]]
    where <- sprintf("%s in %s", row$name, row$project)

    if (identical(row$status, "new")) {
      if (length(at) == 0L) return(character())
      return(sprintf("%s: the preview says new, and the set now holds it",
                     where))
    }

    if (length(at) != 1L) {
      return(sprintf(
        "%s: the preview saw one member, and the set now holds %d",
        where, length(at)
      ))
    }

    pinned <- .datom_id_text(members[[at]]$id, "version")
    if (identical(pinned, row$version_from)) return(character())
    sprintf("%s: the preview saw it at %s, and the set now pins %s",
            where, short(row$version_from), short(pinned))
  }))

  if (length(lines) == 0L) return(invisible(NULL))

  n <- length(lines)
  cli::cli_abort(
    c(
      "The set has moved since this preview was built, so {n} row{?s} no \\
       longer describe{?s/} it:",
      .datom_line_bullets(lines),
      "i" = "Nothing was changed.",
      "i" = if (x_given) {
        "The preview compares against the stored set, and the set you passed \\
         differs from it there. Write that set first and build the preview \\
         again, or apply the preview without {.arg x}."
      } else {
        "Build the preview again from the current set: \\
         {.code m <- datom_sync_manifest(conn, sources = )}."
      }
    ),
    class = "datom_sync_manifest_stale"
  )
}


#' Refuse a Row Whose Kind Disagrees With the Artifact
#'
#' @param row One preview row.
#' @param found The kind the member or the snapshot records.
#' @return Invisibly `NULL`; aborts with class `datom_sync_kind_mismatch`.
#' @keywords internal
.datom_sync_check_kind <- function(row, found) {
  if (identical(row$kind, found)) return(invisible(NULL))

  where <- row$name
  cli::cli_abort(
    c(
      "The row for {.val {where}} in project {.val {row$project}} says kind \\
       {.val {row$kind}}, and the artifact is a {.val {found}}.",
      "i" = "A row names what was reviewed, so a disagreement means it is not \\
             the artifact the preview showed.",
      "i" = "Build the preview again with {.fn datom_sync_manifest}."
    ),
    class = "datom_sync_kind_mismatch"
  )
}


#' Build the Member a `new` Row Adds, From Its Source
#'
#' Read through [datom_member()], which confirms the version exists and records
#' the project the artifact's own metadata declares. That project and the kind
#' are then checked against the row: the connection's label is what routed the
#' read, and nothing verifies a label.
#'
#' @param row One `new` row.
#' @param conn The connection for the row's project.
#' @param tags Labels for the new member.
#' @return A member record.
#' @keywords internal
.datom_sync_new_member <- function(row, conn, tags) {
  record <- datom_member(conn, row$name, row$version_to, tags = tags)

  declared <- record$id$project
  if (!identical(declared, row$project)) {
    where <- row$name
    cli::cli_abort(
      c(
        "Adding {.val {where}} would add it from project {.val {declared}}, \\
         and the row says project {.val {row$project}}.",
        "i" = "A connection's project name is a label nothing checks against \\
               the repo, so the connection used here is labelled \\
               {.val {row$project}} while its store holds project \\
               {.val {declared}}.",
        "i" = "Open a connection whose store really is project \\
               {.val {row$project}}'s and retry."
      ),
      class = "datom_update_project_mismatch"
    )
  }

  .datom_sync_check_kind(row, record$id$kind)

  record
}


#' Say What Apply Did, and That Nothing Was Written
#'
#' @param todo The `new` and `changed` rows that were applied.
#' @param n Maximum number of lines to print before truncating.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_report_sync_apply <- function(todo, n = 20L) {
  if (nrow(todo) == 0L) {
    cli::cli_alert_info("Nothing to apply: no new or changed rows.")
    return(invisible(NULL))
  }

  n_rows <- nrow(todo)
  n_add <- sum(todo$status == "new")
  n_repoint <- sum(todo$status == "changed")
  cli::cli_alert_success(
    "Applied {n_rows} row{?s}: {n_add} added, {n_repoint} repointed."
  )

  edits <- data.frame(
    action = ifelse(todo$status == "new", "add", "repoint"),
    project = todo$project,
    name = todo$name,
    kind = todo$kind,
    from = todo$version_from,
    to = todo$version_to,
    stringsAsFactors = FALSE
  )
  lines <- .datom_edit_lines(edits)
  if (length(lines) > n) {
    extra <- length(lines) - n
    lines <- c(lines[seq_len(n)], paste0("... and ", extra, " more"))
  }
  cli::cli_verbatim(lines)

  cli::cli_alert_info(
    "Nothing has been written. Write the set with \\
     {.code datom_write_set(conn, x)}."
  )

  invisible(NULL)
}


#' Apply a Set Sync Preview to a Product Repo's Set
#'
#' The product-repo route of [datom_sync()]. See point 5 of this file's header:
#' every check that needs no read comes first, then the set is read (when not
#' passed), then the stale and kind checks against it, and only then one
#' snapshot read per applied row.
#'
#' @param conn The product repo's developer connection.
#' @param set_name The set name `.datom/project.yaml` declares.
#' @param manifest The preview, or any frame with its columns.
#' @param sources One `datom_conn` or a list of them.
#' @param tags Labels for members added by `new` rows.
#' @param x A `datom_set`, or `NULL` to read the stored one.
#' @return The edited `datom_set`.
#' @keywords internal
.datom_sync_set_apply <- function(conn, set_name, manifest, sources, tags, x) {
  set_name <- .datom_sync_set_name(set_name)
  rows <- .datom_sync_apply_frame(manifest)
  conns <- .datom_edit_conns(sources, arg = "sources")

  own <- conn$project_name
  .datom_refuse_own_project_source(own, names(conns))

  # Tidy, then validate, as `datom_member()` does.
  tags <- .datom_drop_empty_tags(tags)
  .datom_validate_tag_map(
    tags, "tags",
    remedy = "They label the members {.code new} rows add, e.g. \\
              {.code list(type = \"input\")}."
  )

  x_given <- !is.null(x)

  todo <- rows[rows$status %in% c("new", "changed"), , drop = FALSE]
  rownames(todo) <- NULL
  .datom_sync_refuse_duplicate_rows(todo)
  .datom_sync_refuse_missing_source(todo, names(conns))

  # --- the first read ---
  if (!x_given) x <- .datom_sync_read_set(conn, set_name)
  members <- .datom_edit_members(x)

  ids <- lapply(members, .datom_member_id)
  mem_key <- vapply(
    ids, function(id) paste(id$project, id$name, sep = "\r"), character(1L)
  )
  todo_key <- paste(todo$project, todo$name, sep = "\r")
  hits <- lapply(todo_key, function(k) which(mem_key == k))

  .datom_sync_refuse_stale(todo, hits, members, x_given)

  # A changed row's kind is checked against the member it moves -- no read.
  lapply(which(todo$status == "changed"), function(k) {
    .datom_sync_check_kind(todo[k, , drop = FALSE],
                           ids[[hits[[k]]]]$kind)
  })

  # --- one snapshot read per applied row ---
  # Positions in `hits` stay valid: a repoint replaces in place and an add
  # appends. The refusals raised in here reach the caller with their own class
  # (tested with `inherit = FALSE`): `purrr::reduce()` does not re-wrap errors
  # the way `purrr::map()` does.
  x <- purrr::reduce(
    .x = seq_len(nrow(todo)),
    .init = x,
    .f = function(x, k) {
      row <- todo[k, , drop = FALSE]
      src <- conns[[row$project]]

      if (identical(row$status, "new")) {
        return(.datom_set_add_record(x, .datom_sync_new_member(row, src, tags)))
      }

      at <- hits[[k]]
      x$members[[at]] <- .datom_repoint_member(x$members[[at]], src,
                                               row$version_to)
      x <- .datom_forget_set_identity(x)
      .datom_append_edits(x, data.frame(
        action = "repoint",
        project = row$project,
        name = row$name,
        kind = row$kind,
        from = row$version_from,
        to = row$version_to,
        stringsAsFactors = FALSE
      ))
    }
  )

  .datom_report_sync_apply(todo)

  x
}
