#' Pull Latest Changes from Remote
#'
#' Fetches and merges the latest git changes from the remote repository.
#' This is the recommended entry point at the start of each work session
#' to ensure the local state is current before syncing or writing tables.
#'
#' Git is the source of truth for all metadata (manifest, dispatch, table
#' metadata). The manifest and other metadata files live in git and are
#' pulled along with any other committed changes.
#'
#' Requires developer role (readers have no git access).
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param finish_merge `TRUE` to let datom finish a merge in progress that it
#'   did not start, once nothing but `.datom/manifest.json` conflicts: it
#'   rebuilds the manifest and commits the merge. With no merge in progress it
#'   changes nothing. Default `FALSE`, under which such a merge stops the pull.
#'
#' @return Invisibly, a list with:
#'   \describe{
#'     \item{`commits_pulled`}{Integer count of new commits merged.}
#'     \item{`branch`}{Current branch name.}
#'   }
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
#'     data_repo_url = remote # a folder remote needs no token
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   # Nothing new on the remote yet, so this is a no-op.
#'   datom_pull(conn)
#'
#'   unlink(tmp, recursive = TRUE)
#' }
#' @export
datom_pull <- function(conn, finish_merge = FALSE) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (!isTRUE(finish_merge) && !isFALSE(finish_merge)) {
    cli::cli_abort("{.arg finish_merge} must be {.code TRUE} or {.code FALSE}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Pull requires {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Pull requires a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  repo_path <- conn$path

  # Record HEAD SHA before pulling
  repo <- git2r::repository(repo_path)
  head_before <- as.character(git2r::revparse_single(repo, "HEAD")$sha)
  branch_name <- .datom_git_branch(repo_path)

  # Git pull (the merge check, fetch, merge)
  .datom_git_pull(repo_path, pat = conn$github_pat, finish_merge = finish_merge)

  # Count commits pulled by comparing HEAD before/after
  head_after <- as.character(git2r::revparse_single(repo, "HEAD")$sha)
  commits_pulled <- 0L
  if (!identical(head_before, head_after)) {
    commits_pulled <- tryCatch({
      ab <- git2r::ahead_behind(
        git2r::revparse_single(repo, head_before),
        git2r::revparse_single(repo, "HEAD")
      )
      as.integer(ab[[2]])  # how far old HEAD is behind new HEAD
    }, error = function(e) NA_integer_)
  }

  if (is.na(commits_pulled) || commits_pulled > 0L) {
    n_msg <- if (is.na(commits_pulled)) "new" else commits_pulled
    cli::cli_alert_success("Pulled {n_msg} commit{?s} on {.val {branch_name}} (data repo).")
  } else {
    cli::cli_alert_info("Already up to date on {.val {branch_name}} (data repo).")
  }

  invisible(list(
    commits_pulled = commits_pulled,
    branch = branch_name
  ))
}


#' The Repair: Finish Every Artifact's Unfinished Work and Publish It All
#'
#' Brings storage in line with git for **every artifact of either kind**
#' ([.datom_clone_artifact_names()]), in this order (requirements R5):
#'
#' 1. heal's reset and the pull, on every artifact (`all = TRUE`): datom's
#'    files an interrupted write left uncommitted are put back to the last
#'    commit, never published (each such artifact gets a warning: that write is
#'    not run again); the clone is pulled;
#' 2. a set's payload missing from storage is restored from the clone
#'    ([.datom_restore_set_payload()]), before anything publishes the set's
#'    documents: a set's data file first. One that cannot be restored stops the
#'    repair before anything is published;
#' 3. heal's publish: a committed version storage lacks is pushed and
#'    published. Where a write stops on another artifact's work, the repair
#'    acts: calling it is the consent. A stored version this clone has never
#'    seen is replaced by the clone's, and a stored row for an artifact the
#'    clone lacks is dropped, each with a warning ([.datom_heal_publish()]);
#'    then any commit the git remote still lacks is pushed, without pulling
#'    again: heal pushes only to finish a differing manifest row, and storage
#'    must never name a document the remote does not have;
#' 4. every artifact is published through the one publish path,
#'    [.datom_publish_artifacts()]: the snapshot, the history, `metadata.json`
#'    last, then the manifest, and the manifest only if every artifact
#'    published, so a failure leaves the manifest naming versions whose
#'    documents are in storage.
#'
#' Republishing every artifact, not only those whose manifest row differs, is
#' what corrects two publishes that crossed (the stored manifest naming one
#' version while the stored `metadata.json` holds another), and what puts back
#' a current version's snapshot storage lost. The artifacts heal finds behind
#' are published twice, once by heal and once here: both write the same
#' committed documents, and heal stays the same on every route.
#'
#' **Two public routes reach this**, and both behave the same:
#' `datom_write(conn)` with no `data` and no `name` (the mirror-everything
#' route, which asks first), and `datom_validate(fix = TRUE)`. Heal runs here,
#' after the prompt, and nowhere else on either route, so answering "no"
#' changes nothing.
#'
#' Data-only: governance files (dispatch.json, ref.json, migration_history.json)
#' are not touched here. Governance sync is owned by the governance layer
#' (`gov_sync_dispatch()`).
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param .confirm If `TRUE` (default), requires interactive confirmation
#'   before proceeding. Set to `FALSE` for non-interactive use.
#'
#' @return Invisibly, a list with `repo_files` (`".metadata/manifest.json"`
#'   when the manifest was published, else empty), `manifest` (what
#'   [.datom_publish_artifacts()] reports for it) and `tables`: per artifact,
#'   named by artifact, a list with `name`, `action` (`"published"` or
#'   `"error"`), `version` (the version published, or `NULL`), `reset` and
#'   `pushed` (logical) and `error` (the failure's text, or `NULL`). An
#'   artifact whose never-committed first write was reset is listed with
#'   `action = "reset"`: there is nothing of it to publish.
#' @keywords internal
.datom_sync_data_metadata <- function(conn, .confirm = TRUE) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "The repair requires {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "The repair requires a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # The write entry, here rather than only at datom_write()'s door, because this
  # function has a second caller that does not go through that door:
  # `datom_validate(fix = TRUE)` calls it directly (`R/validate.R`). Left
  # ungated there, a build the repo has declared too old could still publish this
  # repo's documents to storage -- through a command that reads as a repair.
  #
  # It runs on the datom_write() route too, where the door has already run. That
  # is deliberate: every step is a local file read and none of them mutates
  # anything, so the cost of the second pass is nothing, and gating the function
  # rather than each caller means the next caller cannot forget.
  #
  # `NULL` because this route touches every artifact in the clone, not one.
  .datom_check_write_entry(conn, NULL)

  repo_path <- conn$path
  table_names <- .datom_clone_artifact_names(conn)

  # Interactive confirmation, before heal: answering "no" must change nothing.
  if (isTRUE(.confirm)) {
    if (!interactive()) {
      cli::cli_abort(c(
        "Interactive confirmation required.",
        "i" = "Use {.code .confirm = FALSE} for non-interactive use."
      ))
    }

    # "artifact", not "table": discovery is kind-agnostic, so this count has
    # included sets since sets existed -- and for a set the operation can upload
    # a payload as well as documents, which a prompt saying "metadata" hides.
    cli::cli_alert_warning(
      "This will bring data storage in line with git for \\
       {length(table_names)} artifact{?s}: put back datom's files that an \\
       interrupted write left uncommitted, pull, push any commits the git \\
       remote lacks, then publish every artifact's documents and the \\
       manifest, restoring any set payload storage is missing."
    )

    answer <- readline("Proceed? [y/N] ")
    if (!tolower(answer) %in% c("y", "yes")) {
      cli::cli_alert_info("Cancelled. Nothing was changed.")
      return(invisible(list(
        repo_files = character(), manifest = "not_reached", tables = list()
      )))
    }
  }

  # Heal, on every artifact: the only place this route runs it. Its reset and
  # the pull first ...
  healed <- .datom_heal(conn, all = TRUE)
  .datom_pull_before_write(conn, reset = healed$reset)

  # Again after them: the reset removes a first write that never committed, and
  # the pull can bring in a teammate's new artifact.
  names_now <- .datom_clone_artifact_names(conn)

  # ... then a set's data file, before anything publishes its documents,
  # heal's publish included. A payload is named by nothing until its documents
  # are published, so putting it back first is safe; one that cannot be put
  # back stops the repair before anything is published.
  .datom_repair_restore_payloads(conn, names_now)

  unpushed <- .datom_pushed_artifacts(repo_path)
  heal_publish <- .datom_heal_publish(conn, all = TRUE)
  pushed <- isTRUE(heal_publish$pushed) || .datom_repair_push(conn)

  publish <- .datom_publish_artifacts(conn, names_now, on_failure = "return")
  failed <- publish$failed

  table_results <- .datom_repair_results(
    names_now, healed$reset, publish$published, failed,
    pushed = if (pushed) unpushed else character()
  )
  .datom_report_repair(table_results, publish$manifest, failed)

  invisible(list(
    repo_files = if (identical(publish$manifest, "published")) {
      ".metadata/manifest.json"
    } else {
      character()
    },
    manifest = publish$manifest,
    tables = table_results
  ))
}


#' Put Back Every Set Payload Storage Has Lost, or Stop
#'
#' The repair's step before anything is published: a set's data file before
#' its documents. A payload that cannot be put back (storage unreachable, or
#' refusing the upload) stops the repair before anything is published, naming
#' the set and the error: publishing the set's documents would name a payload
#' storage lacks, and the other artifacts would most likely fail on the same
#' outage.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param names The artifacts in the clone.
#' @return Invisibly, the storage keys uploaded.
#' @keywords internal
.datom_repair_restore_payloads <- function(conn, names) {
  keys <- purrr::map(names, function(nm) {
    tryCatch(
      .datom_restore_set_payload(conn, nm),
      error = function(e) .datom_stop_payload_restore_failed(nm, e)
    )
  })
  invisible(unlist(keys) %||% character())
}


#' Stop When the Repair Cannot Put Back a Set's Payload
#'
#' @param name The set.
#' @param e The upload's condition.
#' @return Does not return.
#' @keywords internal
.datom_stop_payload_restore_failed <- function(name, e) {
  why <- .datom_one_line(e)
  cli::cli_abort(
    c(
      "Could not put back the stored payload of set {.val {name}}, so the \\
       repair stopped before publishing anything.",
      "x" = "{why}",
      "i" = "Re-run {.code datom_validate(fix = TRUE)} once storage is \\
             reachable."
    ),
    class = "datom_payload_restore_failed",
    parent = e
  )
}


# Bindings for base functions the repair's prompt calls, so a test can answer
# the prompt (`testthat::local_mocked_bindings()` cannot replace a function in
# base). A call skips a binding that is not a function, so these change
# nothing at run time.
interactive <- NULL
readline <- NULL


#' The Repair's Push of Commits the Remote Lacks
#'
#' Heal's publish pushes only to finish a manifest row that differs from
#' storage's, so a commit whose row agrees (a document committed outside datom,
#' or an artifact's commit whose publish already landed) can still be unpushed
#' when the repair is about to republish every artifact. Pushed here first,
#' without pulling again: the repair pulled moments ago, and a remote that moved
#' since makes git refuse the push, which stops the repair before storage
#' changes.
#'
#' @param conn A `datom_conn` object with a local path.
#' @return `TRUE` when it pushed.
#' @keywords internal
.datom_repair_push <- function(conn) {
  ahead <- .datom_git_ahead(conn$path)
  # NA (no upstream branch) does not reach here unpushed: heal's publish pushes
  # first in that case.
  if (is.na(ahead) || ahead == 0L) return(FALSE)
  .datom_git_push(conn$path, pat = conn$github_pat, pull_first = FALSE)
  TRUE
}


#' What the Repair Did, Per Artifact
#'
#' @param names The artifacts in the clone after heal.
#' @param reset The artifacts heal's reset put back.
#' @param published The versions published, named by artifact.
#' @param failed The failures, named by artifact.
#' @param pushed The artifacts whose commits the repair (or heal) pushed.
#' @return A list of per-artifact records, named by artifact; see
#'   [.datom_sync_data_metadata()].
#' @keywords internal
.datom_repair_results <- function(names, reset, published, failed, pushed) {
  record <- function(nm) {
    error <- failed[[nm]]
    list(
      name = nm,
      action = if (!is.null(error)) "error" else "published",
      version = if (nm %in% names(published)) unname(published[[nm]]),
      reset = nm %in% reset,
      pushed = nm %in% pushed,
      # Without styling: a returned field gets printed as data.
      error = if (!is.null(error)) .datom_one_line(error)
    )
  }
  # A first write that never committed: put back means removed.
  gone <- setdiff(reset, names)
  gone_records <- purrr::map(gone, function(nm) {
    list(name = nm, action = "reset", version = NULL, reset = TRUE,
         pushed = FALSE, error = NULL)
  })

  stats::setNames(
    c(purrr::map(names, record), gone_records),
    c(names, gone)
  )
}


#' Say What the Repair Did, Per Artifact
#'
#' One line per artifact (requirements R5.3), then what became of the
#' manifest. A failure names its file and its error, and the way out.
#'
#' @param results What [.datom_repair_results()] returned.
#' @param manifest What [.datom_publish_artifacts()] reported for the manifest.
#' @param failed The failures, named by artifact.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_report_repair <- function(results, manifest, failed) {
  lines <- purrr::map_chr(results, function(r) {
    done <- c(if (isTRUE(r$reset)) "reset", if (isTRUE(r$pushed)) "pushed")
    if (identical(r$action, "reset")) {
      return(cli::format_inline(
        "{.val {r$name}}: reset; it had never been committed, so nothing is \\
         left to publish"
      ))
    }
    if (identical(r$action, "error")) {
      key <- failed[[r$name]]$datom_storage_key
      where <- if (!is.null(key)) cli::format_inline(" at {.file {key}}") else ""
      return(cli::format_inline(
        "{.val {r$name}}: {paste(c(done, 'failed'), collapse = ', ')}{where}: \\
         {r$error}"
      ))
    }
    version <- substr(r$version %||% "", 1L, 8L)
    cli::format_inline(
      "{.val {r$name}}: {paste(c(done, 'published'), collapse = ', ')} \\
       version {.val {version}}"
    )
  })
  bullets <- purrr::set_names(
    lines,
    ifelse(purrr::map_chr(results, "action") == "error", "x", "*")
  )

  n <- length(results)
  manifest_line <- switch(manifest,
    published = c("v" = "Published the manifest."),
    not_reached = c(
      "!" = "Did not publish the manifest, because {cli::qty(length(failed))}\\
             {?an artifact/some artifacts} failed: readers still see the \\
             versions it names.",
      "i" = "Re-run {.code datom_validate(fix = TRUE)} once storage is \\
             reachable."
    ),
    character()
  )

  cli::cli_inform(
    c(
      "Repair of {n} artifact{?s}:",
      bullets,
      manifest_line
    ),
    class = "datom_repair_report"
  )
  invisible(NULL)
}


#' Put a Set's Payload Back When Storage Has Lost It
#'
#' A set write stores its payload before anything in the clone changes, so a
#' write of this release never leaves a committed version without one. A write
#' by datom 0.2.0 or earlier can (it uploaded after the push, so a break between
#' the two left the payload only in the clone), and so can a payload deleted
#' from storage by hand. For a set that is repairable: git holds
#' `{name}/set.json`, and those are the same bytes the upload would have sent.
#'
#' **It restores, and never overwrites.** The bytes at `{name}/{data_sha}.json`
#' are written once: the recorded `document_sha` pins them, and putting a fresh
#' spelling at that address would leave a valid version refusing its own payload
#' on read. So the upload happens only when the stored object is **absent**, and
#' only when the clone's bytes hash to the hash already recorded -- which is
#' read, never recomputed. Both conditions are needed: refusing only the
#' recompute still permits the worst outcome, an overwritten object keeping the
#' old hash. The absence is checked first, so a stored payload is never hashed
#' against the clone, and checked again by the upload itself
#' ([.datom_storage_upload_absent()]), so a payload another writer stores in
#' between is kept and nothing is reported as restored.
#'
#' **Declining is loud.** A silent decline is indistinguishable from a repair
#' that worked, which is the failure the whole check exists to remove.
#'
#' @param conn A `datom_conn` object with a local path.
#' @param name Artifact name. A table returns immediately -- it has no
#'   `set.json`.
#' @return The storage key uploaded, or `character()` when nothing was.
#' @noRd
.datom_restore_set_payload <- function(conn, name) {
  payload_path <- fs::path(conn$path, name, "set.json")
  if (!fs::file_exists(payload_path)) return(character())

  meta_path <- fs::path(conn$path, name, "metadata.json")
  if (!fs::file_exists(meta_path)) return(character())

  meta <- tryCatch(
    jsonlite::read_json(meta_path, simplifyVector = TRUE),
    error = function(e) NULL
  )

  # Declared kind rather than "there is a set.json here": the file is evidence,
  # the document is the statement.
  if (!identical(.datom_declared_artifact_kind(meta), "set")) return(character())

  if (!.datom_is_text_scalar(meta$data_sha) ||
      !.datom_is_text_scalar(meta$document_sha)) {
    return(character())
  }

  key <- tryCatch(
    .datom_artifact_payload_key(name, meta$data_sha, "set"),
    error = function(e) NULL
  )
  if (is.null(key)) return(character())

  if (.datom_storage_exists(conn, key)) return(character())

  actual <- digest::digest(file = payload_path, algo = "sha256")
  if (!identical(actual, meta$document_sha)) {
    cli::cli_alert_warning(
      "The payload in the clone for set {.val {name}} does not match the hash \\
       its metadata records, so it was not uploaded."
    )
    cli::cli_alert_info(
      "Publish the current payload by writing the set again with \\
       {.fn datom_write_set}."
    )
    return(character())
  }

  outcome <- .datom_storage_upload_absent(conn, payload_path, key, sha256 = actual)
  if (identical(outcome, "exists")) return(character())

  cli::cli_alert_success(
    "Restored the stored payload for set {.val {name}} from the clone."
  )

  key
}


#' Refuse the File-Import Path on a Product Repo
#'
#' A `mode: product` repo **builds** its artifacts: derived tables written from
#' data frames, and one set collecting them. It never onboards source files, so
#' the two import verbs refuse instead of answering. Before this they answered
#' unhelpfully -- `input_files/` exists and is empty on such a repo, so the scan
#' reported "no files found" and handed back a zero-row frame, which describes a
#' repo with nothing to import rather than a repo that does not import.
#'
#' **Read from the file, not from the connection**, and the rule behind that is
#' worth carrying: a check that **authorises a write** must see the config as it
#' is *now*, because a hand edit or a pull can replace it after the connection was
#' built. Only [datom_status()], which reports rather than decides, reads the mode
#' off the connection. A future site applies the same test: does it authorise a
#' write? Then it reads the file.
#'
#' **Three steps in one place, and the middle one is easy to leave out.** Parsing
#' this file makes this a new *gated* parse: every site that reads
#' `.datom/project.yaml` checks its declared format first, or a build that cannot
#' interpret the file acts on fields it has misread. Skipping that step here would
#' reopen exactly that hole, on a path that writes.
#'
#' **Called from both sync verbs, not only the first.** [datom_sync()] takes a
#' manifest data frame, so a caller can hand it rows that a refusing
#' [datom_sync_manifest()] would never have produced.
#'
#' **Above the input-file scan, never in its empty branch.** A product repo with a
#' file dropped into `input_files/` by accident would otherwise be imported, which
#' is the thing this exists to prevent; the unhelpful no-op only happened when the
#' directory was empty.
#'
#' Both verbs have a set route on a product repo, reached by passing
#' `sources =`, so the message names that route rather than only the write
#' verbs.
#'
#' @param verb Name of the sync verb being refused, for the message.
#' @param context What [.datom_sync_context()] read, so one call makes one gated
#'   parse.
#' @return Invisibly `NULL`. Aborts with class `datom_import_on_product` when the
#'   repo declares `mode: product`.
#' @keywords internal
.datom_refuse_import_on_product <- function(verb, context) {
  # Unreachable today, and kept on purpose: both callers only call this on a
  # product repo, so no test can reach this line. It keeps the helper correct for
  # a future caller that skips that check.
  if (!isTRUE(context$product)) return(invisible(NULL))

  declared_set <- context$set
  set_line <- if (.datom_is_text_scalar(declared_set)) {
    "This repo's set is {.val {declared_set}}."
  } else {
    "This repo declares no {.field set}; add {.code set: <name>} to \\
     {.file .datom/project.yaml}."
  }

  # The apply verb also takes the preview it applies, so its call shape differs.
  call_hint <- if (identical(verb, "datom_sync")) {
    "datom_sync(conn, manifest, sources = list(conn_source))"
  } else {
    paste0(verb, "(conn, sources = list(conn_source))")
  }

  cli::cli_abort(
    c(
      "This repo declares {.code mode: product}, so {.fn {verb}} works on its \\
       set against source projects rather than importing files, and no \\
       {.arg sources} was given.",
      "i" = "Pass one connection per project the set's inputs come from: \\
             {.code {call_hint}}.",
      "i" = "Outputs are not mapped: write a derived table with \\
             {.fn datom_write}, then collect the versions into the repo's \\
             set with {.fn datom_write_set}.",
      "i" = set_line
    ),
    class = "datom_import_on_product"
  )
}


#' Which Context a Sync Call Is In: an Ordinary Repo or a Product Repo
#'
#' The two sync verbs do different jobs depending on the repo: an ordinary repo
#' imports source files, a product repo maps its one set against source
#' projects. This reads which, once per call, so every branch below it acts on
#' one answer.
#'
#' **Read from `.datom/project.yaml`, not from the connection**, for the reason
#' [.datom_refuse_import_on_product()] gives: the answer can authorise a write,
#' and a hand edit or a pull can change the file after the connection was built.
#' And the parse is gated -- the file's declared format is checked before `mode`
#' or `set` is read out of it.
#'
#' @param conn A `datom_conn` object with a local path.
#' @return A list of `product` (`TRUE` for a `mode: product` repo) and `set`
#'   (the declared set name as written, possibly `NULL`). A repo with no config
#'   is reported as ordinary: the file path then fails with its own message about
#'   an uninitialised repo.
#' @keywords internal
.datom_sync_context <- function(conn) {
  yaml_path <- fs::path(conn$path, ".datom", "project.yaml")

  if (!fs::file_exists(yaml_path)) return(list(product = FALSE, set = NULL))

  cfg <- yaml::read_yaml(yaml_path)
  .datom_check_project_schema(cfg, source = yaml_path, operation = "write")

  list(
    product = identical(as.character(cfg$mode %||% ""), "product"),
    set = cfg$set
  )
}


#' Preview What a Sync Will Change
#'
#' Looks at the files in the project's `input_files/` folder and returns one
#' row per file, saying whether it is new, changed, unchanged since it was last
#' synced, saved but not yet pushed, or in a format datom cannot read. Nothing
#' is written. Review the result, drop any rows you do not want, then pass it to
#' [datom_sync()].
#'
#' A file counts as changed when its bytes differ from the file last synced
#' under that name, as recorded in the clone's last commit. A sync that stopped
#' before committing a table therefore leaves it `changed`, and the next
#' [datom_sync()] saves it again.
#'
#' The scan reads this clone only: no network, no storage. It cannot see what
#' readers see, so a table pushed to GitHub but not yet **published** (readers
#' get a version once its metadata and the project's manifest in storage name
#' it) shows `unchanged`, and the next [datom_sync()], or a write of that table,
#' publishes it.
#'
#' Files whose format is outside datom's ingestion allowlist (flat tabular
#' formats only) are flagged `"unsupported_format"` up front, without blocking
#' their allowlisted siblings.
#'
#' On a product repo (`mode: product`) it maps the repo's set against source
#' projects instead -- see "On a product repo" below.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param path Optional path to input files directory. Defaults to
#'   `input_files/` inside the repo. Not accepted on a product repo, which reads
#'   no files.
#' @param pattern Glob pattern for file matching. Default `"*"`. On a product
#'   repo it filters source artifact names instead.
#' @param sources On a product repo only, and required there: one `datom_conn`,
#'   or a list of them, for the projects the set's inputs come from. Each
#'   connection's project name is what members are matched on. Refused on an
#'   ordinary repo.
#'
#' @section On a product repo:
#' A product repo owns one set (named in `.datom/project.yaml`), and this call
#' compares that set, as stored, with what each source project holds now. It
#' reads one manifest per source and the stored set; it writes nothing.
#'
#' Tables and sets are treated alike: a set a source holds gets a row, and a
#' member that is a set is compared exactly as a table member is, so a set built
#' from other sets syncs the same way.
#'
#' One row per artifact in the sources whose name matches `pattern`:
#' * `new` -- no member points at it (every row, when the set has no version
#'   yet);
#' * `changed` / `unchanged` -- one member points at it, at an older / the
#'   current version;
#' * `ambiguous` -- two or more members point at it (a live table beside a
#'   frozen baseline, say), so neither will move. Move one with
#'   [datom_update_members()], narrowing by `member` and `tags`.
#'
#' Plus one row for each member the call did not compare:
#' * `excluded` -- its artifact is in a source but does not match `pattern`;
#' * `not_checked` -- its project was not passed in `sources`.
#'
#' The preview never proposes removing a member. A member whose artifact is no
#' longer listed in its source is named in the messages and left pinned. Members
#' in the repo's own project are outputs and get no row: re-derive them, then
#' move them with [datom_update_members()].
#'
#' It stops when `sources` includes the repo's own project, and when a source
#' connection's project name differs from the name that project's own manifest
#' records.
#'
#' **Tables and sets are saved at different points.** On an ordinary repo,
#' [datom_sync()] writes each table as it syncs. On a product repo it hands the
#' edited set back, and the set is saved only by [datom_write_set()] -- one
#' version for the whole edit, which you can look at or add to first.
#'
#' @return On an ordinary repo, a data frame with columns: name, file, format,
#'   original_file_sha, status, one of:
#'   * `"new"` -- no table of that name has been saved;
#'   * `"changed"` -- the file differs from the one last synced;
#'   * `"unpushed"` -- the file matches, but the version saved from it is in
#'     commits this clone has not pushed (a sync that stopped at its push, for
#'     example), so readers cannot see it yet. [datom_sync()] pushes and
#'     publishes it without reading the file again;
#'   * `"unchanged"` -- the file matches, and the version saved from it has been
#'     pushed. It is published too, unless an earlier sync stopped after its
#'     push; the next [datom_sync()] then publishes it;
#'   * `"unsupported_format"` -- the format is outside datom's ingestion
#'     allowlist.
#'
#'   On a product repo, a data frame with columns `project`, `name`, `kind`,
#'   `version_from` (`NA` for a new artifact), `version_to` (`NA` for a member that
#'   was not compared) and `status` (one of `"new"`, `"changed"`,
#'   `"unchanged"`, `"ambiguous"`, `"not_checked"`, `"excluded"`). Versions are
#'   full 64-character strings.
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
#'     data_repo_url = remote # a folder remote needs no token
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   # Drop a source file into the repo's input_files/ directory.
#'   file.copy(
#'     system.file("extdata", "dm.csv", package = "datom"),
#'     file.path(tmp, "repo", "input_files", "dm.csv")
#'   )
#'
#'   manifest <- datom_sync_manifest(conn)
#'   print(manifest[, c("name", "format", "status")])
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_sync_manifest <- function(conn,
                               path = NULL,
                               pattern = "*",
                               sources = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Sync operations require {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Sync operations require a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # The repo decides which job this call does, and the arguments must agree with
  # it. Above the input-directory resolution, so a file accidentally left in
  # `input_files/` on a product repo is never scanned, let alone imported.
  context <- .datom_sync_context(conn)

  if (isTRUE(context$product)) {
    if (is.null(sources)) {
      .datom_refuse_import_on_product("datom_sync_manifest", context)
    }
    if (!is.null(path)) .datom_refuse_file_arg_on_product("path")

    return(.datom_sync_set_preview(conn, context$set, sources, pattern))
  }

  if (!is.null(sources)) .datom_refuse_sources_on_ordinary("sources")

  # Resolve input directory
  input_dir <- if (is.null(path)) {
    fs::path(conn$path, "input_files")
  } else {
    fs::path_abs(path)
  }

  if (!fs::dir_exists(input_dir)) {
    cli::cli_abort(c(
      "Input directory not found: {.path {input_dir}}",
      "i" = "Create it and place source files inside."
    ))
  }

  # Validate flat directory (no subdirectories)
  subdirs <- fs::dir_ls(input_dir, type = "directory")
  if (length(subdirs) > 0L) {
    cli::cli_abort(c(
      "Input directory must be flat (no subdirectories).",
      "x" = "Found {length(subdirs)} subdirector{?y/ies}: {.path {fs::path_file(subdirs)}}"
    ))
  }

  # List files matching pattern
  all_files <- fs::dir_ls(input_dir, type = "file")
  if (pattern != "*") {
    rx <- utils::glob2rx(pattern)
    all_files <- all_files[grepl(rx, fs::path_file(all_files))]
  }

  if (length(all_files) == 0L) {
    cli::cli_alert_info("No files found in {.path {input_dir}} matching {.val {pattern}}.")
    return(data.frame(
      name = character(),
      file = character(),
      format = character(),
      original_file_sha = character(),
      status = character(),
      stringsAsFactors = FALSE
    ))
  }

  # The manifest as last committed, not the working tree's: a write that stopped
  # before its commit has already rewritten the working tree's row, and the
  # table must still show as changed so the sync writes it again (R4.1).
  # .datom_read_manifest() also checks the declared schema version, because the
  # clone can be ahead of this build (a collaborator wrote with a newer datom and
  # this developer pulled) and the comparison below would otherwise run against a
  # shape this build does not understand.
  read <- .datom_read_manifest(conn, "head")

  # No manifest yet means every input file is new. A manifest that exists but
  # will not parse keeps failing exactly as before -- re-signalled unchanged
  # rather than reworded.
  if (!read$ok && !read$absent) stop(read$error)

  current_manifest <- if (read$ok) read$manifest else .datom_manifest_skeleton()

  # Build manifest rows
  rows <- purrr::map(all_files, function(fp) {
    file_name <- fs::path_file(fp)
    table_name <- fs::path_ext_remove(file_name)
    file_format <- fs::path_ext(fp)
    original_file_sha <- .datom_compute_original_file_sha(fp)

    # Compare against current manifest. A non-allowlisted format is flagged up
    # front and never reaches the new/changed comparison -- it is not
    # actionable regardless of whether its bytes moved.
    existing <- current_manifest$artifacts[[table_name]]
    status <- if (!tolower(file_format) %in% .datom_import_formats) {
      "unsupported_format"
    } else if (is.null(existing)) {
      "new"
    } else if (!identical(existing$original_file_sha, original_file_sha)) {
      "changed"
    } else {
      "unchanged"
    }

    data.frame(
      name = table_name,
      file = as.character(fp),
      format = file_format,
      original_file_sha = original_file_sha,
      status = status,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, rows)
  rownames(result) <- NULL

  # A table whose input file matches its last commit, but whose version is in
  # commits not yet pushed (a sync or write that stopped at its push). Read from
  # the clone alone: no fetch and no storage read (R4.2). Asked only when some
  # row is unchanged, which a repo with no commits never has.
  unchanged <- result$status == "unchanged"
  if (any(unchanged)) {
    unpushed <- unchanged & result$name %in% .datom_pushed_artifacts(conn$path)
    result$status[unpushed] <- "unpushed"
  }

  n_new <- sum(result$status == "new")
  n_changed <- sum(result$status == "changed")
  n_unpushed <- sum(result$status == "unpushed")
  n_unchanged <- sum(result$status == "unchanged")
  n_unsupported <- sum(result$status == "unsupported_format")

  # The common scan's line is unchanged; `unpushed` is named only when present.
  unpushed_part <- if (n_unpushed > 0L) paste0(", ", n_unpushed, " unpushed") else ""
  cli::cli_alert_info(
    "Scanned {nrow(result)} file{?s}: {n_new} new, {n_changed} changed{unpushed_part}, {n_unchanged} unchanged."
  )

  if (n_unsupported > 0L) {
    unsupported_names <- result$name[result$status == "unsupported_format"]
    cli::cli_alert_warning(
      "{n_unsupported} file{?s} in an unsupported format: {.val {unsupported_names}}."
    )
  }

  result
}


#' Bring New and Changed Files Into a Project
#'
#' Takes the preview from [datom_sync_manifest()] and saves each new or changed
#' file as a version of a table named after the file; unchanged files are
#' skipped. This is the usual way to bring files into datom. To save a data
#' frame you built in R, use [datom_write()].
#'
#' Reading files needs the rio package (`install.packages("rio")`).
#'
#' Rows flagged `"unsupported_format"` by [datom_sync_manifest()] are reported
#' as `result = "error"` with the recourse in the `error` column; the rest of
#' the batch still processes.
#'
#' **A sync that stops partway finishes when run again.** Before the first
#' table it brings the clone up to date with GitHub, and finishes any table in
#' the preview that an earlier run left unfinished: it pushes and publishes a
#' table saved but not pushed (`"unpushed"` in the preview) or pushed but not
#' published, and sets back the files of a table it is about to write again.
#' If another table has unfinished work, or a preview row it does not write has
#' changes to datom's files that were never committed, it stops before
#' changing anything and names [datom_validate()]`(fix = TRUE)`. A failed
#' fetch stops it too.
#'
#' **Two people syncing at once.** When one table's push brings in a teammate's
#' commit whose files are not in storage yet, that table's write publishes the
#' table but not the project's manifest, and warns. The sync then stops: the
#' tables after it come back `"skipped"`, whatever `continue_on_error` says.
#' Run [datom_validate()]`(fix = TRUE)`, then the same call again, with the
#' same preview.
#'
#' On a product repo (`mode: product`) it applies a preview of the repo's set
#' instead -- see "On a product repo" below.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param manifest Data frame from [datom_sync_manifest()]. On an ordinary repo,
#'   with columns `name`, `file`, `format`, `original_file_sha`, `status`. On a
#'   product repo, the set preview: `project`, `name`, `kind`, `version_from`,
#'   `version_to`, `status`. Any subset of its rows will do.
#' @param continue_on_error If `TRUE` (default), continues processing
#'   remaining tables when one fails, as long as the failure left the clone
#'   untouched: a file that does not import, a data frame datom refuses, or the
#'   data file's upload. A table whose write fails after it has begun changing
#'   the clone (written its files, or committed, for example on a dropped
#'   connection at the push) stops the sync there: the tables after it come
#'   back `"skipped"`, because their writes would carry its unfinished version
#'   into git or storage. Run the same call again, with the same preview, to
#'   finish it and sync the rest. If `FALSE`, stops on first error. Not
#'   accepted on a product repo, where one failure stops the call and nothing
#'   has been written.
#' @param sources On a product repo only, and required there: one `datom_conn`,
#'   or a list of them, for the projects named by the rows being applied -- the
#'   same connections the preview was built with. Refused on an ordinary repo.
#' @param tags On a product repo only: the labels given to members added by
#'   `new` rows. Default `list(type = "input")`. A repointed member keeps its
#'   own labels. Refused on an ordinary repo.
#' @param x On a product repo only: the `datom_set` to apply the preview to,
#'   from [datom_get_set()] or [datom_assemble_set()]. Omitted, the repo's
#'   stored set is read, or an empty one used when it has never been written.
#'   Refused on an ordinary repo.
#'
#' @section On a product repo:
#' A product repo owns one set, and this call applies a preview from
#' [datom_sync_manifest()] to it: each `new` row adds a member at `version_to`,
#' labelled with `tags`, and each `changed` row repoints the member it names
#' from `version_from` to `version_to`, keeping that member's labels exactly.
#' Rows of any other status do nothing. Filter the preview first to apply only
#' part of it -- `subset(m, name != "lb")` -- or build the frame by hand with the
#' same columns.
#'
#' **Nothing is written.** The set comes back edited, and it is stored only when
#' you pass it to [datom_write_set()]; the call ends by saying so. The write's
#' default commit message then names what was added and repointed.
#'
#' This is the one difference from syncing files, where each table is written
#' as it syncs. A set is saved in one step, so the edit becomes one version, and
#' you can look at the set, or add to it, before it does.
#'
#' Every member added is read from its source first, which confirms the version
#' exists and records the project that wrote it. The call stops, before
#' changing anything, when:
#' * the set has moved since the preview was built -- a `changed` row's member
#'   is no longer at `version_from`, or a `new` row's artifact is already in the
#'   set. Build the preview again from the current set;
#' * a row's `kind` or `project` disagrees with the artifact it names;
#' * a `new` or `changed` row names a project with no connection in `sources`,
#'   or the same artifact appears in two such rows;
#' * `sources` includes the repo's own project, whose members are outputs.
#'
#' @return On an ordinary repo, the manifest data frame augmented with `result`
#'   and `error` columns. `result` is `"success"`, `"skipped"`, or `"error"`.
#'   An `"unpushed"` row, and an `"unchanged"` row whose table this call
#'   published for an earlier run, come back `"success"` without the file being
#'   read. A row whose write found nothing to save (a teammate synced the same
#'   file first) is `"success"` too, and the call says it was already up to
#'   date. Rows not attempted because the sync stopped carry the reason in
#'   `error`.
#'
#'   On a product repo, the updated `datom_set`, with what changed appended to
#'   its `datom_edits` attribute. Its `version` and `data_sha` are emptied when
#'   any row was applied.
#' @export
#'
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage. File import needs the optional
#' # rio package.
#' if (requireNamespace("git2r", quietly = TRUE) &&
#'     requireNamespace("rio", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     data_repo_url = remote # a folder remote needs no token
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   file.copy(
#'     system.file("extdata", "dm.csv", package = "datom"),
#'     file.path(tmp, "repo", "input_files", "dm.csv")
#'   )
#'
#'   manifest <- datom_sync_manifest(conn)
#'   result <- datom_sync(conn, manifest)
#'   print(result[, c("name", "status", "result")])
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_sync <- function(conn,
                      manifest,
                      continue_on_error = TRUE,
                      sources = NULL,
                      tags = list(type = "input"),
                      x = NULL) {

  # --- validation ---
  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Sync operations require {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Sync operations require a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # The repo decides which job this call does, and the arguments must agree with
  # it. Above the manifest column check, so a product repo handed any frame
  # without `sources` gets the refusal naming `sources =`, not a list of
  # file-import columns. Independently of datom_sync_manifest(), because this
  # verb takes a data frame: a caller can hand it rows a refusing scan would
  # never have produced.
  context <- .datom_sync_context(conn)

  if (isTRUE(context$product)) {
    if (is.null(sources)) .datom_refuse_import_on_product("datom_sync", context)
    # `missing()`, not a value test: the default is a real value, so only
    # whether the caller typed it says they believed it would do something.
    if (!missing(continue_on_error)) {
      .datom_refuse_file_arg_on_product("continue_on_error")
    }

    return(.datom_sync_set_apply(conn, context$set, manifest, sources, tags, x))
  }

  if (!is.null(sources)) .datom_refuse_sources_on_ordinary("sources")
  if (!missing(tags)) .datom_refuse_sources_on_ordinary("tags")
  if (!is.null(x)) .datom_refuse_sources_on_ordinary("x")

  if (!is.data.frame(manifest)) {
    cli::cli_abort("{.arg manifest} must be a data frame from {.fn datom_sync_manifest}.")
  }

  required_cols <- c("name", "file", "format", "original_file_sha", "status")
  missing_cols <- setdiff(required_cols, names(manifest))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "Manifest missing required columns: {.val {missing_cols}}.",
      "i" = "Use {.fn datom_sync_manifest} to generate a valid manifest."
    ))
  }

  .datom_check_rio()

  # --- the start of every write: the format check, heal and the pull ---
  # Once for the whole batch, so the sync pulls and reads the stored manifest
  # once (R3.7, R3.4), and each table's write below skips them (`.healed`).
  # Every table in the preview is the sync's own: heal pushes and publishes any
  # of them an earlier run committed and storage lacks (an `unpushed` row, or one
  # pushed but not published), and puts back the uncommitted files of the rows
  # it writes again (`new`, `changed`). Unfinished work on any other table, or
  # uncommitted edits of a row it does not write, stops the sync here, before
  # anything changes (R4.4). The format check comes first, on every table heal
  # may act on, as `datom_write()`'s door does for its one table.
  own <- unique(manifest$name)
  rewrite <- unique(manifest$name[manifest$status %in% c("new", "changed")])
  .datom_check_write_entry(conn, own)
  healed <- .datom_heal(conn, artifact = own, rewrite = rewrite)
  .datom_pull_before_write(conn, reset = healed$reset)
  published <- names(.datom_heal_publish(conn, artifact = own)$published)

  # --- filter to actionable rows ---
  actionable <- manifest$status %in% c("new", "changed")
  manifest$result <- ifelse(actionable, NA_character_, "skipped")
  manifest$error <- NA_character_

  # An `unpushed` row is work, and heal has just done it: pushed and published
  # without importing the file again (R4.3). So is an `unchanged` row whose
  # table heal published (pushed by an earlier run, not published). Heal's own
  # message has named each one it published.
  finished <- manifest$status == "unpushed" |
    (manifest$status == "unchanged" & manifest$name %in% published)
  manifest$result[finished] <- "success"
  purrr::walk(
    setdiff(manifest$name[manifest$status == "unpushed"], published),
    function(nm) cli::cli_alert_info("{.val {nm}} was already up to date.")
  )

  # Non-allowlisted formats are reported as errors carrying the same recourse
  # .datom_import_file() would abort with -- one bad file does not block its
  # allowlisted siblings.
  unsupported <- manifest$status == "unsupported_format"
  if (any(unsupported)) {
    manifest$result[unsupported] <- "error"
    manifest$error[unsupported] <- paste(
      .datom_import_format_recourse(), collapse = " "
    )
    n_unsupported <- sum(unsupported)
    unsupported_names <- manifest$name[unsupported]
    cli::cli_alert_danger(
      "{n_unsupported} file{?s} in an unsupported format, not synced: {.val {unsupported_names}}."
    )
  }

  n_todo <- sum(actionable)
  if (n_todo == 0L) {
    cli::cli_alert_info("No new or changed files. Nothing to sync.")
    return(manifest)
  }

  cli::cli_alert_info("Syncing {n_todo} table{?s}...")

  # --- process each actionable table ---
  todo_idx <- which(actionable)
  stopped_at <- NULL
  held_back <- NULL

  for (i in todo_idx) {
    tbl_name <- manifest$name[i]
    tbl_file <- manifest$file[i]
    tbl_format <- manifest$format[i]
    tbl_original_file_sha <- manifest$original_file_sha[i]

    # For telling, if this table's write fails, whether it had begun changing
    # the clone (R4.6).
    head_before <- .datom_clone_head(conn$path)

    tryCatch({
      # Import file -> data frame
      data <- .datom_import_file(tbl_file, tbl_format)

      # Build self-lineage for imported (raw) tables.
      # version_sha uses data_sha (content-addressed, independent of metadata_sha)
      # so there is no circular dependency with the metadata construction.
      tbl_data_sha <- .datom_compute_data_sha(data)
      self_lineage <- list(list(
        project     = conn$project_name,
        table       = tbl_name,
        version_sha = tbl_data_sha
      ))

      # Write via datom_write (handles manifest update internally). Heal and the
      # pull ran once above, for the whole batch. A write whose push brought in
      # a teammate's version storage lacks holds back the manifest and warns;
      # the warning goes through to the caller, and the sync stops after it
      # (R4.6), since no later write checks the stored manifest again.
      write_result <- withCallingHandlers(
        datom_write(
          conn,
          data = data,
          name = tbl_name,
          message = paste0("Sync ", tbl_name, " (", manifest$status[i], ")"),
          .source_lineage = self_lineage,
          .table_type = "imported",
          .original_file_sha = tbl_original_file_sha,
          .original_format = tbl_format,
          .healed = TRUE
        ),
        datom_manifest_held_back = function(w) {
          held_back <<- list(
            disagree = as.character(w$disagree %||% character()),
            unreadable = w$unreadable
          )
        }
      )

      manifest$result[i] <- "success"

      # A stale preview (DD3): a teammate imported the same file, the pull above
      # brought it in, and the write found nothing to save.
      if (identical(write_result$action, "none")) {
        cli::cli_alert_info("{.val {tbl_name}} was already up to date.")
      } else {
        cli::cli_alert_success("{.val {tbl_name}} synced ({manifest$status[i]}).")
      }

    }, error = function(e) {
      manifest$result[i] <<- "error"
      # ansi_strip: this is a data frame column the caller prints, so cli's
      # colour and hyperlink escape codes would show up as literal text.
      manifest$error[i] <<- cli::ansi_strip(conditionMessage(e))
      left_changes <- .datom_write_left_changes(conn, head_before)

      if (!continue_on_error) {
        hint <- if (left_changes) {
          "Run the same {.fn datom_sync} call again, with the same preview, to \\
           finish {.val {tbl_name}} and sync the rest."
        } else {
          "Set {.code continue_on_error = TRUE} to skip failures."
        }
        cli::cli_abort(c(
          "Failed to sync {.val {tbl_name}}.",
          "x" = conditionMessage(e),
          "i" = hint
        ))
      }

      cli::cli_alert_danger("Failed to sync {.val {tbl_name}}: {conditionMessage(e)}")
      if (left_changes) stopped_at <<- tbl_name
    })

    # No later table may be written (R4.6) when this one's write:
    # - failed after it had begun changing the clone: a later commit would take
    #   its uncommitted manifest row, and a later manifest upload would name a
    #   version storage lacks;
    # - held back the manifest: a later write, whose own push brings in
    #   nothing, would upload the whole manifest unchecked, naming the
    #   teammate's version before its files are in storage.
    # A held-back manifest is not an error, so this holds under either setting
    # of `continue_on_error`.
    if (!is.null(held_back) && is.null(stopped_at)) stopped_at <- tbl_name
    if (!is.null(stopped_at)) break
  }

  not_run <- todo_idx[is.na(manifest$result[todo_idx])]
  if (!is.null(stopped_at) && length(not_run) > 0L) {
    why <- if (is.null(held_back)) "failed partway" else "held back the manifest"
    manifest$result[not_run] <- "skipped"
    manifest$error[not_run] <- cli::ansi_strip(cli::format_inline(
      "Not attempted: the sync stopped after the write of {.val {stopped_at}} \\
       {why}."
    ))
    .datom_inform_sync_stopped(stopped_at, manifest$name[not_run], held_back)
  }

  # --- summary ---
  n_ok <- sum(manifest$result == "success", na.rm = TRUE)
  n_err <- sum(manifest$result == "error", na.rm = TRUE)
  n_skip <- sum(manifest$result == "skipped", na.rm = TRUE)

  cli::cli_alert_info(
    "Sync complete: {n_ok} succeeded, {n_err} failed, {n_skip} skipped."
  )

  manifest
}


#' Say That a Sync Stopped Partway
#'
#' Requirements R4.6, for its two reasons. The way out is the same
#' [datom_sync()] call again, with the same preview, so rows the user dropped
#' from the preview stay dropped; it was traced for each:
#' - **a write that failed after changing the clone**: before its commit, heal
#'   puts the table's files back and the sync writes it again; at or after its
#'   push, heal pushes and publishes the committed version, and the table's
#'   write then finds nothing to save;
#' - **a write that held back the manifest** (its push brought in a teammate's
#'   version storage lacks): run [datom_validate()]`(fix = TRUE)` first, which
#'   publishes what the clone holds, so the same call then finds the held-back
#'   table up to date and writes the rest. Without it, the same call stops on
#'   the teammate's table, outside the preview, naming that fix.
#'
#' @param stopped_at The table whose write failed or held back the manifest.
#' @param not_run The tables after it, not attempted.
#' @param held_back `NULL` when the write failed. When it held back the
#'   manifest, what the warning carried: `disagree` (the artifacts it named)
#'   and `unreadable` (the read error on one line, when storage's manifest could
#'   not be read to check them, else `NULL`).
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_inform_sync_stopped <- function(stopped_at, not_run, held_back = NULL) {
  if (is.null(held_back)) {
    cli::cli_inform(
      c(
        "x" = "Stopped the sync after the write of {.val {stopped_at}} failed \\
               partway: it had already changed this clone, and a later table's \\
               write would have carried its unfinished version into git or \\
               storage.",
        "i" = "Not attempted: {.val {not_run}}.",
        "i" = "Run the same {.fn datom_sync} call again, with the same \\
               preview: it finishes {.val {stopped_at}} and syncs the rest."
      ),
      class = "datom_sync_stopped"
    )
    return(invisible(NULL))
  }

  why <- held_back$unreadable
  if (!is.null(why)) {
    cli::cli_inform(
      c(
        "x" = "Stopped the sync after the write of {.val {stopped_at}} held \\
               back the manifest: its push brought in commits, storage's \\
               manifest could not be read to check them, and a later table's \\
               write would have published the manifest anyway.",
        "x" = "{why}",
        "i" = "Not attempted: {.val {not_run}}.",
        "i" = "Once storage is reachable, run \\
               {.code datom_validate(fix = TRUE)} to publish the manifest, then \\
               the same {.fn datom_sync} call again, with the same preview, to \\
               sync the rest."
      ),
      class = "datom_sync_stopped"
    )
    return(invisible(NULL))
  }

  disagree <- held_back$disagree
  n <- length(disagree)
  cli::cli_inform(
    c(
      "x" = "Stopped the sync after the write of {.val {stopped_at}} held back \\
             the manifest: its push brought in commits naming \\
             {cli::qty(n)}{?a version/versions} of {.val {disagree}} that \\
             storage does not hold yet, and a later table's write would have \\
             published the manifest anyway.",
      "i" = "Not attempted: {.val {not_run}}.",
      "i" = "Run {.code datom_validate(fix = TRUE)} to publish \\
             {cli::qty(n)}{?it/them} and the manifest, then the same \\
             {.fn datom_sync} call again, with the same preview, to sync the \\
             rest."
    ),
    class = "datom_sync_stopped"
  )
  invisible(NULL)
}


# --- Shared manifest access ----------------------------------------------------

#' The Artifacts Present in the Local Clone
#'
#' A top-level folder is a datom artifact when **the manifest names it** (as
#' committed in HEAD, or in the working tree), or when **its `metadata.json`
#' parses and declares a datom `hash_algo`** (`datom-cv1` for a table,
#' `datom-sv1` for a set). The second rule catches an artifact's first write
#' broken before its manifest row, and keeps the answer independent of the
#' manifest when the manifest is the document under suspicion.
#'
#' A folder that merely holds a `metadata.json` is not enough: a joint repo can
#' carry a user's own `app/metadata.json`, and heal's reset would then discard
#' its edits, the repair would publish it, and the format check would refuse a
#' write over the user's own fields.
#'
#' Three callers, and they must agree: heal's reset ([.datom_heal()]) puts back
#' exactly these artifacts' files, the data-side metadata sync mirrors exactly
#' these artifacts to storage, and the write-entry check inspects exactly the
#' documents that route is about to write.
#'
#' The directory filter is the pre-existing one: dotfiles out, plus the fixed
#' list of non-artifact directories a joint repo carries (`R/`, `tests/`,
#' `renv/`, and so on). It saves reading their files; the two rules above are
#' what decide.
#'
#' @param conn A `datom_conn` object with a local path.
#' @return Character vector of artifact names, possibly empty.
#' @keywords internal
.datom_clone_artifact_names <- function(conn) {
  if (is.null(conn$path) || !nzchar(conn$path)) return(character())
  if (!fs::dir_exists(conn$path)) return(character())

  dirs <- fs::dir_ls(conn$path, type = "directory")
  dirs <- dirs[!grepl("^\\.", fs::path_file(dirs))]
  dirs <- dirs[!fs::path_file(dirs) %in%
    c("input_files", "renv", "man", "R", "tests", "vignettes", "src")]
  if (length(dirs) == 0L) return(character())

  named <- union(
    .datom_manifest_names_at(conn$path, "HEAD"),
    .datom_manifest_names_at(conn$path)
  )

  dirs <- dirs[purrr::map_lgl(dirs, function(d) {
    if (fs::path_file(d) %in% named) return(TRUE)
    meta_path <- fs::path(d, "metadata.json")
    if (!fs::file_exists(meta_path)) return(FALSE)
    meta <- tryCatch(jsonlite::read_json(meta_path), error = function(e) NULL)
    is.list(meta) && isTRUE(meta$hash_algo %in% c("datom-cv1", "datom-sv1"))
  })]

  as.character(fs::path_file(dirs))
}


#' The Artifact Names a Manifest Lists
#'
#' @param path Repository path.
#' @param head `NULL` for the working tree's `.datom/manifest.json`, or a commit
#'   to read it from (`"HEAD"`, `"MERGE_HEAD"`).
#' @return Character vector, empty when there is no manifest or it does not
#'   parse.
#' @keywords internal
.datom_manifest_names_at <- function(path, head = NULL) {
  text <- if (is.null(head)) {
    manifest_path <- fs::path(path, ".datom", "manifest.json")
    if (fs::file_exists(manifest_path)) {
      paste(readLines(manifest_path, warn = FALSE), collapse = "\n")
    }
  } else {
    .datom_git_head_file(path, ".datom/manifest.json", head = head)
  }
  as.character(names(.datom_manifest_rows(text)))
}


#' Select the Artifacts of One Kind
#'
#' The one place the artifact list is filtered by `kind`. Four counters need it
#' -- two in the manifest's stored `summary` block, plus the numbers
#' [datom_summary()] and [datom_status()] count for themselves -- and a
#' predicate written out at each of them is a predicate that can differ at one
#' of them.
#'
#' **An entry that is not a named list is skipped rather than dereferenced.**
#' The upgrade step deliberately passes such an entry through untouched, because
#' it has no shape to convert; without the check here, that preserved entry
#' reaches `entry$kind` and aborts with "$ operator is invalid for atomic
#' vectors". [datom_status()] is the one that must not do that: it exists to
#' describe a connection when the manifest cannot be trusted, and this count
#' sits outside the error handling that gives it that tolerance. A hand-edited
#' manifest is exactly the document most likely to reach it.
#'
#' Skipping is not the same as tolerating a **missing** `kind`, which stays
#' deliberately uncounted: a typed entry with no type means the conversion was
#' skipped, and a visibly wrong count is the intended signal for that.
#'
#' @param artifacts The manifest's `artifacts` list, or `NULL`.
#' @param kind `"table"` or `"set"`.
#' @return The entries of that kind, names preserved.
#' @keywords internal
.datom_artifacts_of_kind <- function(artifacts, kind) {
  purrr::keep(artifacts %||% list(), function(entry) {
    is.list(entry) && identical(entry$kind, kind)
  })
}


#' Say That a Manifest's Format Was Moved Forward
#'
#' Called from the two places that **persist** a converted manifest: the entry
#' updater, which rewrites the git-tracked file, and the data-side metadata sync,
#' which mirrors the converted document to storage. Reads convert too and stay
#' silent, deliberately -- a read changes nothing, and a line on every
#' [datom_list()] call would be noise nobody can act on.
#'
#' Why say anything: conversion is one-way for everybody else. Once this repo's
#' manifest declares the newer format, a collaborator on an older datom no longer
#' finds the artifact list where their build looks for it, and their
#' `datom_list()` reports an empty repo **without erroring**. Their
#' [datom_read()] keeps working, because the data path never touches the
#' manifest. That is a real consequence of a command whose stated job was
#' something else -- `datom_validate(fix = TRUE)` in particular reads as a
#' repair -- and an unannounced one is the silent degradation the whole schema
#' contract exists to remove.
#'
#' No-op when the document was already current, which is every ordinary write.
#'
#' @param declared The version the document declared before conversion, as
#'   returned by [.datom_check_schema_version()].
#' @param where Human-readable name of the copy being written.
#' @return Invisibly `NULL`.
#' @keywords internal
.datom_notify_manifest_upgraded <- function(declared, where) {
  if (as.integer(declared) >= .datom_supported_schema) return(invisible(NULL))

  cli::cli_alert_info(c(
    "Manifest format moved from v{as.integer(declared)} to ",
    "v{(.datom_supported_schema)} in {where}."
  ))
  cli::cli_bullets(c(
    "i" = paste0(
      "Collaborators on an older datom will list this repo as empty until they ",
      "upgrade; reading a known table still works. See {.field NEWS} for which ",
      "release supports which format."
    )
  ))

  invisible(NULL)
}


#' Empty Manifest Skeleton
#'
#' The one shape of an empty manifest. Callers that need a manifest when none
#' exists yet build it here rather than inline, so a later change to the
#' manifest's shape has a single place to land.
#'
#' `artifacts` is a **named** empty list on purpose: `jsonlite` serializes an
#' empty bare list as a JSON array (`[]`) and an empty named list as an object
#' (`{}`), and a manifest's artifact block must be an object. Inert today, since
#' nothing writes a manifest that still has zero entries, and correct for the one
#' case where it would.
#'
#' The skeleton declares `schema_version` itself, so no repo ever exists in a
#' state that declares no format at all -- not even between being created and
#' receiving its first artifact. This covers only the built-from-nothing path:
#' a document read from disk in an older shape gets its version from
#' [.datom_manifest_upgrade()] instead, because the skeleton is unreachable
#' whenever a manifest file exists.
#'
#' @param project_name Project name, or `NULL` to omit the field (callers that
#'   only need somewhere to look up entries have no project name to hand).
#' @return A list with `schema_version`, `project_name` (when supplied),
#'   `artifacts` and `summary`.
#' @keywords internal
.datom_manifest_skeleton <- function(project_name = NULL) {
  skeleton <- list(schema_version = .datom_supported_schema)
  if (!is.null(project_name)) skeleton$project_name <- project_name
  skeleton$artifacts <- structure(list(), names = character(0))
  skeleton$summary <- list()
  skeleton
}


#' The Manifest's Summary Block, Counted From Its Artifact Rows
#'
#' The one place the counters are computed, for the three writers of a whole
#' manifest: a write's row update (`.datom_update_manifest_entry()`), a reader's
#' rebuild from storage ([.datom_rebuild_manifest()]) and the rebuild of a
#' manifest a merge left in conflict ([.datom_resolve_manifest_conflict()]).
#'
#' Every counter but `total_sets` keeps its original meaning, which is tables
#' only, so each one selects by kind. An entry with no kind is counted by none
#' of them, deliberately (see [.datom_artifacts_of_kind()]).
#'
#' @param artifacts The manifest's `artifacts` list.
#' @return The `summary` block: `total_tables`, `total_size_bytes`,
#'   `total_versions` and `total_sets`.
#' @keywords internal
.datom_manifest_summary <- function(artifacts) {
  tables <- .datom_artifacts_of_kind(artifacts, "table")
  sets <- .datom_artifacts_of_kind(artifacts, "set")

  list(
    total_tables = length(tables),
    total_size_bytes = sum(purrr::map_dbl(
      tables, ~ as.numeric(.x$size_bytes %||% 0L)
    )),
    total_versions = sum(purrr::map_int(
      tables, ~ as.integer(.x$version_count %||% 0L)
    )),
    total_sets = length(sets)
  )
}


#' Read a Manifest and Check Its Schema Version
#'
#' The single manifest read. Every reader that takes a manifest *into* datom
#' goes through this, so the compatibility check happens once and cannot be
#' softened by a caller's error handling.
#'
#' Two kinds of failure, handled deliberately differently:
#'
#' * **An IO failure is returned as data** (`ok = FALSE`), because each caller
#'   has its own policy: `datom_list()` and `datom_summary()` abort,
#'   `datom_status()` reports the manifest unavailable and carries on, and the
#'   clone readers fall back to an empty manifest when the file does not exist
#'   yet.
#' * **A schema refusal is thrown**, so the "upgrade datom" message reaches the
#'   user intact. Placed inside a caller's `tryCatch` it would be reworded as
#'   "could not read manifest" at two sites and downgraded to a warning at a
#'   third. Throwing from in here means there is no handler for a caller to put
#'   it inside.
#'
#' **And one document that is not a failure at all.** When the artifact list is
#' missing from where this build looks for it -- either because the format is
#' newer than this build knows, or because the key is simply not there after the
#' conversion has run -- the index is **reconstructed from storage** and a warning
#' says so. The manifest summarises documents that each hold the same facts, so it
#' is the one datom-owned file with something to rebuild it from. A **writer**
#' meeting either condition is refused instead
#' ([.datom_check_write_entry()]): reads limp, writes stop.
#'
#' @param conn A `datom_conn` object.
#' @param scope `"storage"` for the copy in data storage
#'   (`.metadata/manifest.json`), `"clone"` for the git-tracked copy as the
#'   working tree holds it (`.datom/manifest.json`), `"head"` for that copy as
#'   committed in HEAD. They can differ, and which one a caller wants is a real
#'   choice rather than a default: the scan compares input files with what was
#'   last committed, so a write that stopped before its commit leaves the table
#'   `changed` rather than `unchanged` ([datom_sync_manifest()]).
#' @param operation What the caller is about to do with the document --
#'   `"read"` (default) or `"write"`. Passed through to
#'   [.datom_check_schema_version()], where it only selects a word in the
#'   refusal message, so that a write stopped at the door does not report the
#'   format as one this build "cannot read".
#' @return A list with:
#'   * `ok` -- `TRUE` when the manifest was read and parsed.
#'   * `absent` -- `TRUE` only when the document is *known* not to exist. That
#'     is decided for `scope = "clone"` and `scope = "head"`, where looking is
#'     free (for `"head"`, HEAD holds no manifest, or the path is not a git
#'     repo).
#'     For `scope = "storage"` it is always `FALSE`, meaning "not known to be
#'     absent": separating a missing object from an unreachable store would
#'     cost an extra request on every read and no caller distinguishes them.
#'   * `manifest` -- the parsed document **in current shape**, or `NULL` when
#'     `ok` is `FALSE`. A document written in an older shape is converted in
#'     memory on the way through ([.datom_manifest_upgrade()]); one whose artifact
#'     list this build cannot reach is reconstructed from storage
#'     ([.datom_rebuild_manifest()]). Neither modifies the file on disk or in
#'     storage. So no caller ever sees a pre-current shape and none needs a
#'     fallback for one.
#'   * `error` -- the condition that stopped the read, or `NULL`. The whole
#'     condition rather than its text, so a caller can re-signal the original
#'     failure unchanged instead of manufacturing a look-alike.
#'   * `declared` -- the version the document declared **before** conversion, or
#'     `NA_integer_` when nothing was read. Held so a caller that goes on to
#'     write the converted document can say the format moved, without
#'     re-deriving the comparison or reading the file twice.
#' @keywords internal
.datom_read_manifest <- function(conn,
                                 scope = c("storage", "clone", "head"),
                                 operation = c("read", "write")) {
  scope <- match.arg(scope)
  operation <- match.arg(operation)

  source <- switch(scope,
    storage = ".metadata/manifest.json",
    clone = ".datom/manifest.json",
    head = ".datom/manifest.json (last commit)"
  )
  absent <- list(
    ok = FALSE, absent = TRUE, manifest = NULL, error = NULL,
    declared = NA_integer_
  )

  if (scope == "clone" &&
      !fs::file_exists(fs::path(conn$path, ".datom", "manifest.json"))) {
    return(absent)
  }

  head_text <- if (scope == "head") {
    .datom_git_head_file(conn$path, ".datom/manifest.json")
  }
  if (scope == "head" && is.null(head_text)) return(absent)

  # The handler covers the read ONLY. The schema check below must stay outside
  # it: inside, a refusal would come back as an IO failure and every caller's
  # tolerance would apply to it.
  read <- tryCatch(
    list(
      ok = TRUE,
      absent = FALSE,
      # `fromJSON(simplifyVector = FALSE)` is what `read_json()` does to a file,
      # so the committed copy parses exactly as the working tree's would.
      manifest = switch(scope,
        storage = .datom_storage_read_json(conn, ".metadata/manifest.json"),
        clone = jsonlite::read_json(fs::path(conn$path, ".datom", "manifest.json")),
        head = jsonlite::fromJSON(head_text, simplifyVector = FALSE)
      ),
      error = NULL,
      declared = NA_integer_
    ),
    error = function(e) {
      list(
        ok = FALSE, absent = FALSE, manifest = NULL, error = e,
        declared = NA_integer_
      )
    }
  )

  if (!read$ok) return(read)

  # A format above what this build supports is a refusal for a writer and a
  # rebuild for a reader -- same evidence, opposite responses, because reads limp
  # and writes stop. The refusal is caught here ONLY on the read path, and the
  # condition is kept: if the rebuild then turns out to be impossible, the
  # original refusal is what the user gets, never an IO failure wearing its
  # clothes.
  too_new <- NULL
  declared <- if (operation == "read") {
    tryCatch(
      .datom_check_schema_version(read$manifest, source, operation = operation),
      datom_schema_unsupported = function(cnd) {
        too_new <<- cnd
        NA_integer_
      }
    )
  } else {
    .datom_check_schema_version(read$manifest, source, operation = operation)
  }

  # `datom_schema_invalid` is deliberately NOT caught above: a value that is not
  # a schema version at all means a corrupt or hand-edited document, and a
  # corrupt manifest has to keep failing visibly rather than being quietly
  # reconstructed.

  if (is.null(too_new)) {
    # The check runs first and the upgrade only on what survives it: there is no
    # step for a version this build does not know, so the dispatcher must never
    # see one.
    read$manifest <- .datom_manifest_upgrade(read$manifest, declared)
    read$declared <- declared
  } else {
    # Held for callers that report which format the document was in. The number
    # is taken off the raw document because the check threw instead of returning
    # it.
    read$declared <- suppressWarnings(as.integer(read$manifest$schema_version))
  }

  # Writers never reach a rebuild, on either trigger. A writer meeting a manifest
  # whose artifact list it cannot reach is refused at the door instead
  # (`.datom_check_write_entry()`), because overwriting an index this build cannot
  # account for leaves the repo wrong for everybody, where a reader's guess costs
  # one person one session.
  if (operation != "read") return(read)

  reason <- if (!is.null(too_new)) {
    "schema"
  } else if (is.list(read$manifest) && !("artifacts" %in% names(read$manifest))) {
    # Absent, never merely empty. An empty artifact list is what a brand-new repo
    # looks like, so rebuilding on empty would cost a storage listing on every
    # call against every healthy repo and would hide a truncated document behind
    # a plausible answer.
    "shape"
  } else {
    NULL
  }

  if (is.null(reason)) return(read)

  attempt <- tryCatch(
    list(ok = TRUE, manifest = .datom_rebuild_manifest(conn, read$manifest)),
    error = function(e) list(ok = FALSE, manifest = NULL, error = e)
  )

  # A per-artifact document this build cannot read stops the rebuild rather than
  # being softened into a missing row: that document is stamped and not
  # reconstructible, so there is nothing to salvage. Survivability is available
  # exactly when the break was manifest-only.
  #
  # Re-signalled from OUT HERE, not from a handler beside the one above. A
  # `stop(cnd)` inside one `tryCatch()` handler is caught by that same
  # `tryCatch()`'s `error` handler -- verified, and the opposite of what the
  # syntax suggests -- so the two-handler spelling of this silently turned every
  # refusal below into an IO failure.
  if (!isTRUE(attempt$ok) &&
      inherits(attempt$error,
               c("datom_schema_unsupported", "datom_schema_invalid"))) {
    stop(attempt$error)
  }

  if (isTRUE(attempt$ok)) {
    .datom_warn_manifest_rebuilt(
      source, reason, read$declared, length(attempt$manifest$artifacts)
    )
    read$manifest <- attempt$manifest
    return(read)
  }

  # The rebuild could not be done. For a too-new document the original refusal
  # stands -- reporting it as an unreadable manifest is the one thing the schema
  # contract forbids at every reader. For an unreachable shape the document was
  # readable, so the failure is the storage one and each caller keeps its own
  # policy for that.
  if (!is.null(too_new)) stop(too_new)

  read$ok <- FALSE
  read$manifest <- NULL
  read$error <- attempt$error

  read
}


# --- Internal helpers for datom_sync -------------------------------------------

# Formats datom_sync will onboard. Flat tabular only: the sync path must produce
# a data frame whose columns are all hashable, so container formats (.rds,
# .json, .xml) and anything else outside this list are refused. The escape hatch
# is explicit -- the user reads the file themselves and calls datom_write().
.datom_import_formats <- c(
  "csv", "tsv", "txt", "psv", "parquet",
  "sas7bdat", "xpt", "sav", "zsav", "por", "dta",
  "xls", "xlsx"
)


#' Canonical recourse for a non-allowlisted ingestion format
#'
#' Single source for the two advice lines shared by the `.datom_import_file()`
#' abort and the `error` column `datom_sync()` reports on an
#' `unsupported_format` row, so the two can never drift. Returns already-
#' rendered plain text (no cli markup left in it), which makes it safe to
#' splice into a cli bullet or into a data frame cell.
#' @noRd
.datom_import_format_recourse <- function() {
  c(
    cli::format_inline(
      "datom_sync onboards flat tabular formats only: {.val {(.datom_import_formats)}}."
    ),
    cli::format_inline(
      paste0(
        "Convert the file to CSV or parquet, or read it yourself and pass the ",
        "resulting data frame to {.fn datom_write}."
      )
    )
  )
}


#' Check rio availability
#' @noRd
.datom_check_rio <- function() {
  if (!requireNamespace("rio", quietly = TRUE)) {
    cli::cli_abort(c(
      "Package {.pkg rio} is required for file import during sync.",
      "i" = "Install with {.code install.packages(\"rio\")}"
    ))
  }
  invisible(TRUE)
}


#' Import a file to data frame via rio
#' @noRd
.datom_import_file <- function(file, format) {
  fmt <- tolower(format)

  # Allowlist gate: refuse before touching the file at all.
  if (!fmt %in% .datom_import_formats) {
    recourse <- .datom_import_format_recourse()
    cli::cli_abort(c(
      "Cannot import {.file {file}}: format {.val {format}} is not a supported datom ingestion format.",
      "i" = recourse[1],
      "i" = recourse[2]
    ))
  }

  # Parquet goes through arrow directly (more reliable than rio for parquet)
  if (fmt == "parquet") {
    return(arrow::read_parquet(file))
  }

  data <- rio::import(file)

  if (!is.data.frame(data)) {
    cli::cli_abort("Imported file {.path {file}} did not produce a data frame.")
  }

  data
}


#' Update a single artifact entry in local .datom/manifest.json
#'
#' `kind` is a parameter rather than a constant because both write verbs land
#' here, and the two kinds do not carry the same counters: a table's row declares
#' `size_bytes`, a set's declares `member_count` **instead**. Not both -- a set
#' row carrying `size_bytes = 0` reads as an artifact of zero bytes, and the
#' summary's tables-only byte total would then be right by luck rather than by
#' rule.
#'
#' @param member_count Required for a `"set"` row: the count **after** tidying,
#'   which is the canonical member count and can differ from what the caller
#'   passed, because tidying drops an exact duplicate member.
#' @noRd
.datom_update_manifest_entry <- function(conn, name, metadata_sha, data_sha,
                                        original_file_sha = NULL,
                                        format = NULL,
                                        kind = "table",
                                        member_count = NULL) {
  manifest_path <- fs::path(conn$path, ".datom", "manifest.json")
  fs::dir_create(fs::path_dir(manifest_path))

  # Read stays direct rather than going through .datom_read_manifest(): this is
  # mid-write, and a compatibility refusal belongs at the front door, before any
  # work starts, not partway through. Only the empty shape is shared.
  #
  # A document read from disk is converted before it is edited, so a new entry
  # is never added under the current key while an older key sits untouched
  # beside it -- that leaves a repo of twelve tables reporting one, in a file
  # half in each format. The declared version comes from the same check every
  # reader uses: it is the only thing that knows how to read the number, and it
  # cannot fire here for a write that came through datom_write(), which refuses
  # a too-new manifest at the door before any hashing.
  declared <- .datom_supported_schema
  manifest <- if (fs::file_exists(manifest_path)) {
    from_disk <- jsonlite::read_json(manifest_path)
    declared <- .datom_check_schema_version(from_disk, manifest_path, operation = "write")
    .datom_manifest_upgrade(from_disk, declared)
  } else {
    .datom_manifest_skeleton(conn$project_name)
  }

  # Count versions from version_history.json, through the shared reader of
  # datom's own files in the clone.
  vh <- .datom_read_clone_json(conn$path, paste0(name, "/version_history.json"))
  version_count <- if (is.null(vh)) 1L else length(vh)

  entry <- list(
    kind = kind,
    current_version = metadata_sha,
    current_data_sha = data_sha,
    last_updated = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )

  if (identical(kind, "set")) {
    if (is.null(member_count)) {
      cli::cli_abort(
        "{.arg member_count} is required for a {.val set} manifest entry."
      )
    }
    entry$member_count <- as.integer(member_count)
  } else {
    # Read size_bytes from local metadata.json (already written at this point).
    # A set's metadata has no size_bytes at all, which is why this read sits on
    # the table branch: reading it there would default a real absence to 0.
    meta_path <- fs::path(conn$path, name, "metadata.json")
    # as.numeric (not as.integer): tables > 2 GB overflow the 2^31 integer
    # limit, yielding NA that then poisons summary$total_size_bytes.
    entry$size_bytes <- if (fs::file_exists(meta_path)) {
      m <- jsonlite::read_json(meta_path)
      as.numeric(m$size_bytes %||% 0)
    } else {
      0
    }
  }

  entry$version_count <- as.integer(version_count)

  if (!is.null(original_file_sha)) entry$original_file_sha <- original_file_sha
  if (!is.null(format)) entry$original_format <- format

  # The row above was rebuilt from scratch, so a field this build cannot place
  # would be deleted from it. Carry those forward. The existing row is taken from
  # the already-converted document, so an upgrade step that moved or typed it has
  # run first.
  #
  # The document's TOP level needs nothing equivalent, and that is worth knowing
  # before restructuring this function: it is read from disk, three keys are
  # edited, and it is written back, so an unfamiliar key beside `artifacts`
  # survives because it is never touched. Rebuilding the document here instead of
  # editing it would silently end that.
  entry <- .datom_carry_unknown_fields(
    entry,
    manifest$artifacts[[name]],
    .datom_manifest_entry_known_fields
  )

  manifest$artifacts[[name]] <- entry

  # By here the document has been through the upgrade, which types every entry,
  # so an untyped entry means the conversion was skipped, and the visibly wrong
  # count the summary then gives is the point.
  manifest$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  manifest$summary <- .datom_manifest_summary(manifest$artifacts)

  .datom_notify_manifest_upgraded(declared, "this repo's manifest")

  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)

  invisible(manifest)
}
