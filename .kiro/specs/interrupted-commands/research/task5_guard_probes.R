# Guard probes for #155 task 5. Each probe applies one deliberate edit to R/,
# runs the named test files in a fresh R process, records what reddened, and
# restores the files from a fixed backup taken once.
# Run from the repo root on the tree of task 5's commit; the edits match that
# code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/task5_guard_probes.R
# or, for some probes only (the control always runs first):
#   Rscript .kiro/specs/interrupted-commands/research/task5_guard_probes.R finish_merge
# Copied from task4b_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/heal.R", "R/utils-git.R", "R/sync.R")
  backup <- file.path(tempdir(), "..", "datom-task5-probe-pristine")
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
  sy <- "R/sync.R"
  mc <- "^manifest-conflict$"

  probes <- list(
    control = list(filter = "^(manifest-conflict|heal|utils-git)$", edit = function() sub1(hl,
      "  manifest_path <- fs::path(path, rel)\n  writeBin(",
      "  # probe control: a comment changes nothing\n  manifest_path <- fs::path(path, rel)\n  writeBin(")),

    # The manifest-only condition at the pull: never resolved.
    manifest_only_never = list(filter = mc, edit = function() sub1(gt,
      "    if (identical(.datom_git_conflicted(repo), \".datom/manifest.json\")) {",
      "    if (FALSE) {")),

    # ... and resolved whenever the manifest is among the conflicted files.
    manifest_only_among = list(filter = "^(manifest-conflict|heal)$", edit = function() sub1(gt,
      "    if (identical(.datom_git_conflicted(repo), \".datom/manifest.json\")) {",
      "    if (\".datom/manifest.json\" %in% .datom_git_conflicted(repo)) {")),

    # The row-against-files comparison: only a missing row is rebuilt, so a row
    # present in the merged-in copy but naming another version stays stale.
    row_against_files = list(filter = mc, edit = function() sub1(hl,
      "  if (is.list(row) && identical(row$current_version, version)) return(NULL)",
      "  if (is.list(row)) return(NULL)")),

    # The version the files describe: the history's record alone.
    files_version_recorded_only = list(filter = mc, edit = function() sub1(hl,
      "  if (own %in% .datom_history_versions(history %||% list())) return(own)\n",
      "")),

    # The rebuild starts from the merged-in side's copy, not HEAD's.
    start_from_merge_head = list(filter = mc, edit = function() sub1(hl,
      "      .datom_git_head_file(path, rel, head = \"MERGE_HEAD\"),\n      .datom_git_head_file(path, rel)\n",
      "      .datom_git_head_file(path, rel)\n")),

    # The format check before the rebuild writes anything.
    format_check_before_rebuild = list(filter = mc, edit = function() sub1(hl,
      "  if (!is.null(refused)) .datom_stop_merge_refused(refused, data_file_stored)",
      "  if (FALSE) .datom_stop_merge_refused(refused, data_file_stored)")),

    # The merge check's finishing branch: the 4a behaviour, stopping instead.
    merge_check_finishes = list(filter = mc, edit = function() sub1(hl,
      "  .datom_resolve_manifest_conflict(path)\n  invisible(TRUE)",
      "  .datom_stop_merge_conflict(path)\n  invisible(TRUE)")),

    # finish_merge: a merge datom did not start is finished when asked.
    finish_merge = list(filter = mc, edit = function() sub1(hl,
      "  if (!of_upstream && !isTRUE(finish_merge)) .datom_stop_other_merge(repo)",
      "  if (!of_upstream) .datom_stop_other_merge(repo)")),

    # ... and datom_pull() passes it to the pull.
    finish_merge_passed = list(filter = mc, edit = function() sub1(sy,
      "  .datom_git_pull(repo_path, pat = conn$github_pat, finish_merge = finish_merge)",
      "  .datom_git_pull(repo_path, pat = conn$github_pat)")),

    # Under finish_merge, a merge datom did not start that still conflicts gets
    # the other-merge stop, not the remote branch's recipe.
    other_merge_stop_while_conflicting = list(filter = mc, edit = function() sub1(hl,
      "    if (!of_upstream) .datom_stop_other_merge(repo)\n    .datom_stop_merge_conflict(path)",
      "    .datom_stop_merge_conflict(path)"))
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
    line <- sprintf("%-36s %s", nm, res)
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
  writeLines(results, file.path(log_dir, "task5-probes.log"))
}
main()
