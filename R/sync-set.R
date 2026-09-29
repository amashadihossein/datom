# Syncing a product repo's set against its source projects: map what the sources
# hold, review it as a data frame, apply it. The same shape table sync has on an
# ordinary repo, reached through the same two verbs -- `datom_sync_manifest()`
# and `datom_sync()` branch once, at the top, on what `.datom/project.yaml`
# declares. This file is the product-repo half; `R/sync.R` holds the branch.
#
# FOUR THINGS HERE ARE LOAD-BEARING.
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
#      prompt, and a refusal anywhere leaves nothing behind.


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
             inputs, so the preview does not map them.",
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
  unversioned <- arts$matches & is.na(arts$current_version)
  unversioned_names <- paste0(arts$name[unversioned], " in ",
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
