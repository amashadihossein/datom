# Guard probes for #155 task 7 (the repair). Each probe applies one deliberate
# edit to R/, runs the named test files in a fresh R process, records what
# reddened, and restores the files from a fixed backup taken once.
# Run from the repo root on the tree of task 7's commit; the edits match that
# code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/task7_guard_probes.R
# or, for some probes only (the control always runs first):
#   Rscript .kiro/specs/interrupted-commands/research/task7_guard_probes.R repair_push
# Copied from task6_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/heal.R", "R/sync.R", "R/validate.R", "R/read_write.R")
  backup <- file.path(tempdir(), "..", "datom-task7-probe-pristine")
  backup <- normalizePath(backup, mustWork = FALSE)
  if (!dir.exists(backup)) {
    for (f in files) parse(file.path(root, f))  # refuse a tree that does not parse
    dir.create(backup, recursive = TRUE)
    for (f in files) file.copy(file.path(root, f), file.path(backup, basename(f)))
  }
  restore <- function() {
    for (f in files) file.copy(file.path(backup, basename(f)), file.path(root, f), overwrite = TRUE)
  }
  restore()  # start from the pristine copy

  sub1 <- function(path, old, new) {
    txt <- paste(readLines(file.path(root, path), warn = FALSE), collapse = "\n")
    n <- lengths(regmatches(txt, gregexpr(old, txt, fixed = TRUE)))
    if (n != 1L) stop("edit for ", path, " matched ", n, " times: ", substr(old, 1, 60))
    writeLines(sub(old, new, txt, fixed = TRUE), file.path(root, path))
  }

  run_tests <- function(filter) {
    code <- sprintf(paste(
      "suppressMessages(devtools::load_all(quiet = TRUE));",
      "r <- as.data.frame(devtools::test(filter = '%s', reporter = 'silent', stop_on_failure = FALSE));",
      "bad <- unique(r$test[r$failed > 0 | r$error]);",
      "cat('RESULT failed=', sum(r$failed), ' error=', sum(r$error), ' nb=', sum(r$nb), ' :: ', paste(bad, collapse = ' | '), '\\n', sep = '')"
    ), filter)
    out <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(code)),
                   stdout = TRUE, stderr = TRUE)
    line <- grep("^RESULT", out, value = TRUE)
    if (length(line) == 0L) paste("DID NOT RUN:", paste(utils::tail(out, 5), collapse = " / ")) else line
  }

  hl <- "R/heal.R"
  sy <- "R/sync.R"
  va <- "R/validate.R"
  rw <- "R/read_write.R"
  repair <- "^repair$"

  probes <- list(
    control = list(filter = repair, edit = function() sub1(sy,
      "  names_now <- .datom_clone_artifact_names(conn)",
      "  # probe control: a comment changes nothing\n  names_now <- .datom_clone_artifact_names(conn)")),

    # The reset before publishing (R5.1, P4): no heal reset on the repair.
    reset_first = list(filter = repair, edit = function() sub1(sy,
      "  healed <- .datom_heal(conn, all = TRUE)\n",
      "  healed <- list(reset = character())\n")),

    # fix = TRUE runs the repair whether or not a check found something.
    fix_ungated = list(filter = repair, edit = function() sub1(va,
      "  if (isTRUE(fix)) {",
      "  if (!is_valid && isTRUE(fix)) {")),

    # The repair's own push of commits heal's publish leaves (R5.2).
    repair_push = list(filter = repair, edit = function() sub1(sy,
      "  pushed <- isTRUE(heal_publish$pushed) || .datom_repair_push(conn)",
      "  pushed <- isTRUE(heal_publish$pushed)")),

    # Heal after the prompt, so "no" changes nothing.
    heal_after_prompt = list(filter = repair, edit = function() sub1(sy,
      "  # Interactive confirmation, before heal: answering \"no\" must change nothing.\n",
      "  .datom_heal_publish(conn, all = TRUE)\n")),

    # A set's payload first (data file first): restore after every publish
    # instead.
    payload_first = list(filter = repair, edit = function() {
      sub1(sy, "  .datom_repair_restore_payloads(conn, names_now)\n", "")
      sub1(sy, "  failed <- publish$failed",
           "  .datom_repair_restore_payloads(conn, names_now)\n  failed <- publish$failed")
    }),

    # Added from the review of 9284ca9: the restore before heal's publish ...
    restore_before_heal = list(filter = repair, edit = function() {
      sub1(sy, "  .datom_repair_restore_payloads(conn, names_now)\n", "")
      sub1(sy, "  pushed <- isTRUE(heal_publish$pushed) || .datom_repair_push(conn)",
           "  pushed <- isTRUE(heal_publish$pushed) || .datom_repair_push(conn)\n  .datom_repair_restore_payloads(conn, names_now)")
    }),

    # ... a restore that fails stops the repair ...
    restore_stops = list(filter = repair, edit = function() sub1(sy,
      "      error = function(e) .datom_stop_payload_restore_failed(nm, e)",
      "      error = function(e) character()")),

    # ... validate checks the same artifacts the repair acts on ...
    validate_discovery = list(filter = repair, edit = function() sub1(va,
      "  table_names <- .datom_clone_artifact_names(conn)",
      "  table_names <- fs::path_file(fs::dir_ls(conn$path, type = \"directory\"))\n  table_names <- table_names[fs::file_exists(fs::path(conn$path, table_names, \"metadata.json\"))]")),

    # ... and a stop in the repair comes through datom_validate() unchanged.
    stop_through = list(filter = "^(repair|validate)$", edit = function() sub1(va,
      "    repair <- .datom_sync_data_metadata(conn, .confirm = FALSE)",
      "    repair <- tryCatch(.datom_sync_data_metadata(conn, .confirm = FALSE),\n      error = function(e) list(tables = list(list(action = \"error\"))))")),

    # metadata.json last within each artifact.
    metadata_last = list(filter = repair, edit = function() sub1(rw,
      "  .datom_storage_write_json_at(conn, s3_versioned_key, metadata)\n  .datom_storage_write_json_at(conn, s3_history_key, history)\n  .datom_storage_write_json_at(conn, s3_metadata_key, metadata)",
      "  .datom_storage_write_json_at(conn, s3_metadata_key, metadata)\n  .datom_storage_write_json_at(conn, s3_versioned_key, metadata)\n  .datom_storage_write_json_at(conn, s3_history_key, history)")),

    # The manifest only if every artifact's documents went up (P7).
    manifest_after_failure = list(filter = repair, edit = function() sub1(hl,
      "  manifest <- if (length(failed) == 0L) {",
      "  manifest <- if (TRUE) {")),

    # manifest_mismatch_s3: the comparison itself (R5.5).
    mismatch_compare = list(filter = repair, edit = function() sub1(va,
      "  !identical(stored_rows[[name]]$current_version, version)",
      "  FALSE")),

    # The document's own version (owner's option (a)), against the revert test.
    own_version = list(filter = "^(repair|manifest-conflict)$", edit = function() sub1(hl,
      "    if (own %in% .datom_history_versions(history %||% list())) return(own)\n",
      "")),

    # The placeability check, against the unplaceable-field test.
    placeable = list(filter = repair, edit = function() sub1(hl,
      "  placeable <- all(names(meta) %in% .datom_metadata_known_fields())",
      "  placeable <- TRUE"))
  )

  # Probe names on the command line run only those (the control is always run
  # first); none runs them all.
  wanted <- commandArgs(trailingOnly = TRUE)
  if (length(wanted) > 0L) {
    unknown <- setdiff(wanted, names(probes))
    if (length(unknown) > 0L) stop("no such probe: ", paste(unknown, collapse = ", "))
    probes <- probes[unique(c("control", wanted))]
  }

  results <- character()
  for (nm in names(probes)) {
    restore()
    applied <- tryCatch({ probes[[nm]]$edit(); TRUE }, error = function(e) conditionMessage(e))
    res <- if (isTRUE(applied)) {
      tryCatch(run_tests(probes[[nm]]$filter), error = function(e) paste("HARNESS ERROR:", conditionMessage(e)))
    } else {
      paste("PROBE DID NOT APPLY:", applied)
    }
    restore()
    line <- sprintf("%-24s %s", nm, res)
    results <- c(results, line)
    cat(line, "\n")
  }
  restore()
  same <- vapply(files, function(f) {
    identical(readLines(file.path(root, f)), readLines(file.path(backup, basename(f))))
  }, logical(1))
  cat("tree restored to the pristine copy:", all(same), "\n")
  # A backup left behind would be "restored" over newer code by the next run,
  # so remove it once the tree is known to match it. After a crash it stays,
  # and the next run restores from it, which is the point of a fixed path.
  if (all(same)) unlink(backup, recursive = TRUE)
  log_dir <- file.path(root, ".agents", "tasks")
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(results, file.path(log_dir, "task7-probes.log"))
}
main()
