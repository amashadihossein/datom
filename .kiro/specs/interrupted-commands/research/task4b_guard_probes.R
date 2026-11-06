# Guard probes for #155 task 4b. Each probe applies one deliberate edit to R/,
# runs the named test files in a fresh R process, records what reddened, and
# restores the files from a fixed backup taken once.
# Run from the repo root on the tree of task 4b's commit; the edits match that
# code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/task4b_guard_probes.R
# or, for some probes only (the control always runs first):
#   Rscript .kiro/specs/interrupted-commands/research/task4b_guard_probes.R containment
# Copied from task4a_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/heal.R", "R/utils-git.R", "R/utils-sha.R", "R/read_write.R")
  backup <- file.path(tempdir(), "..", "datom-task4b-probe-pristine")
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
  gt <- "R/utils-git.R"
  us <- "R/utils-sha.R"
  rw <- "R/read_write.R"
  publish <- "^heal-publish$"
  publish_and_breaks <- "^(heal-publish|interrupted-write|interrupted-set)$"

  probes <- list(
    control = list(filter = "^(heal|heal-publish|interrupted-write|interrupted-set)$", edit = function() sub1(hl,
      "  stored <- .datom_stored_manifest(conn)\n  if (identical(stored$status, \"unreadable\")) {",
      "  # probe control: a comment changes nothing\n  stored <- .datom_stored_manifest(conn)\n  if (identical(stored$status, \"unreadable\")) {")),

    # The unpublished-artifact comparison: no clone row ever differs.
    unpublished_comparison = list(filter = publish_and_breaks, edit = function() sub1(hl,
      "    !identical(clone_rows[[nm]]$current_version, stored_rows[[nm]]$current_version)",
      "    FALSE")),

    # A stored row for an artifact the clone lacks counted as differing.
    stored_row_lacking_counts = list(filter = publish, edit = function() sub1(hl,
      "  c(differ, setdiff(names(stored_rows), in_clone))",
      "  differ")),

    # The manifest last: published before the artifacts' documents too.
    manifest_last = list(filter = "^(heal-publish|interrupted-write)$", edit = function() sub1(hl,
      "  outcomes <- purrr::map(names, function(nm) {",
      "  .datom_publish_manifest(conn, names)\n  outcomes <- purrr::map(names, function(nm) {")),

    # The manifest held back after an artifact failed to publish.
    manifest_held_back_after_failure = list(filter = publish, edit = function() sub1(hl,
      "  manifest <- if (length(failed) == 0L) {",
      "  manifest <- if (TRUE) {")),

    # The publish gate (P12).
    publish_gate = list(filter = "^heal$", edit = function() sub1(hl,
      "  if (!ahead && length(differ) == 0L) {",
      "  if (FALSE) {")),

    # The stop on another artifact's differing (or stored-only) row.
    stop_on_other_artifact = list(filter = publish, edit = function() sub1(hl,
      "  if (length(others) > 0L) {\n    .datom_stop_unpublished_others(",
      "  if (FALSE) {\n    .datom_stop_unpublished_others(")),

    # Step d counts `artifact` as the command's own.
    own_is_artifact = list(filter = publish, edit = function() sub1(hl,
      "  own <- if (isTRUE(all)) differ else intersect(differ, artifact)",
      "  own <- if (isTRUE(all)) differ else character()")),

    # The containment check.
    containment = list(filter = publish, edit = function() sub1(hl,
      "      !.datom_history_contains(conn$path, nm, version)",
      "      FALSE")),

    # The containment check as "older": the stored version must sit below the
    # clone's current one in the newest-first history.
    containment_as_older = list(filter = publish, edit = function() sub1(hl,
      "      !.datom_history_contains(conn$path, nm, version)",
      "      !(function(h, cur) { v <- .datom_history_versions(h); i <- match(version, v); j <- match(cur, v); !is.na(i) && !is.na(j) && i > j })(.datom_read_clone_json(conn$path, paste0(nm, \"/version_history.json\")) %||% list(), clone_rows[[nm]]$current_version)")),

    # The repair overrides the containment check.
    repair_override = list(filter = publish, edit = function() sub1(hl,
      "  if (length(unseen) > 0L && !isTRUE(all)) {",
      "  if (length(unseen) > 0L) {")),

    # The manifest upload's agreement check after the push pulled commits in.
    manifest_agreement_check = list(filter = publish, edit = function() sub1(hl,
      "  if (isTRUE(recheck)) {",
      "  if (FALSE) {")),

    # Heal's push does not pull.
    heal_push_does_not_pull = list(filter = publish, edit = function() sub1(hl,
      "  if (ahead) {\n    .datom_git_push(conn$path, pat = conn$github_pat, pull_first = FALSE)",
      "  if (ahead) {\n    .datom_git_push(conn$path, pat = conn$github_pat, pull_first = TRUE)")),

    # The shared reader's stop: a file that does not parse read as absent.
    shared_reader_stop = list(filter = publish, edit = function() sub1(hl,
      "    error = function(e) .datom_stop_clone_file_unreadable(path, rel, e)",
      "    error = function(e) NULL")),

    # The local metadata write reads the history before it writes anything.
    read_history_before_writing = list(filter = publish, edit = function() sub1(rw,
      "  history <- .datom_read_clone_json(repo_path, paste0(name, \"/version_history.json\")) %||%\n    list()\n\n  fs::dir_create(table_dir)\n\n  # metadata.json — current state\n  metadata_path <- fs::path(table_dir, \"metadata.json\")\n  jsonlite::write_json(metadata, metadata_path, auto_unbox = TRUE, pretty = TRUE)\n",
      "  fs::dir_create(table_dir)\n\n  # metadata.json — current state\n  metadata_path <- fs::path(table_dir, \"metadata.json\")\n  jsonlite::write_json(metadata, metadata_path, auto_unbox = TRUE, pretty = TRUE)\n  history <- .datom_read_clone_json(repo_path, paste0(name, \"/version_history.json\")) %||%\n    list()\n")),

    # Step a resets only `rewrite`: the metadata-only route rewrites nothing.
    reset_only_rewrite = list(filter = "^(heal|heal-publish)$", edit = function() sub1(us,
      "  healed <- .datom_heal(conn, artifact = name, rewrite = character())",
      "  healed <- .datom_heal(conn, artifact = name)")),

    # `rewrite` must be a subset of `artifact`.
    rewrite_subset_refusal = list(filter = publish, edit = function() sub1(hl,
      "  if (!isTRUE(all) && length(stray) > 0L) {",
      "  if (FALSE) {")),

    # "datom changed nothing" only when heal reset nothing.
    changed_nothing_line = list(filter = publish, edit = function() sub1(gt,
      "  if (length(reset) == 0L) return(\"datom changed nothing.\")",
      "  return(\"datom changed nothing.\")"))
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
    line <- sprintf("%-34s %s", nm, res)
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
  writeLines(results, file.path(log_dir, "task4b-probes.log"))
}
main()
