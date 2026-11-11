# Guard probes for the test coverage review before #155 task 10 (2026-11-09).
# Each probe applies one deliberate edit to R/, runs the named test files in a
# fresh R process, records what reddened, and restores the files from a fixed
# backup taken once. The checks probed had no recorded probe: heal's publish on
# a stored manifest it cannot read (a write stops; the repair warns and
# publishes everything), the stop when heal cannot finish publishing an earlier
# write, the stop on a project.yaml that does not parse, and "./" before a path
# given to datom_repo_commit().
# Run from the repo root on the tree of the commit it probes; the edits match
# that code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/coverage_guard_probes.R
# or, for some probes only (the control always runs first):
#   Rscript .kiro/specs/interrupted-commands/research/coverage_guard_probes.R g1_write_stop
# Copied from task9_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/heal.R", "R/forward-compat.R")
  backup <- file.path(tempdir(), "..", "datom-coverage-probe-pristine")
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
  fc <- "R/forward-compat.R"
  publish <- "^heal-publish$"
  probes <- list(
    control = list(filter = "^(heal-publish|repair)$", edit = function() sub1(hl,
      "#' Stop When the Stored Manifest Cannot Be Read",
      "# probe control: a comment changes nothing\n#' Stop When the Stored Manifest Cannot Be Read")),
    # A write stops when the stored manifest cannot be read ...
    g1_write_stop = list(filter = publish, edit = function() sub1(hl,
      "    if (!isTRUE(all)) .datom_stop_stored_manifest_unreadable(stored$error)\n",
      "")),
    # ... whether storage could not be reached to look for it ...
    g1_exists_error_unreadable = list(filter = publish, edit = function() sub1(hl,
      "    return(list(status = \"unreadable\", rows = list(), error = present))",
      "    return(list(status = \"absent\", rows = list(), error = NULL))")),
    # ... or the file is there and does not parse.
    g1_read_error_unreadable = list(filter = publish, edit = function() sub1(hl,
      "    return(list(status = \"unreadable\", rows = list(), error = read$error))",
      "    return(list(status = \"absent\", rows = list(), error = NULL))")),
    # The repair does not stop on it ...
    g1_repair_carries_on = list(filter = "^repair$", edit = function() sub1(hl,
      "    if (!isTRUE(all)) .datom_stop_stored_manifest_unreadable(stored$error)",
      "    if (TRUE) .datom_stop_stored_manifest_unreadable(stored$error)")),
    # ... and says what it does instead.
    g1_repair_warns = list(filter = "^repair$", edit = function() sub1(hl,
      "    cli::cli_warn(\n      c(\n        \"Could not read the stored manifest, so every artifact",
      "    if (FALSE) cli::cli_warn(\n      c(\n        \"Could not read the stored manifest, so every artifact")),
    # Heal's publish failing stops the command before its own work.
    g2a_publish_failed_stops = list(filter = publish, edit = function() sub1(hl,
      "  if (length(result$failed) > 0L) .datom_stop_publish_failed(result$failed)\n",
      "")),
    # A project.yaml that does not parse is not treated as no floor.
    g2b_config_unreadable_stops = list(filter = "^(heal|forward-compat)$", edit = function() sub1(fc,
      "    reason <- if (inherits(cfg, \"error\")) {",
      "    return(invisible(NULL))\n    reason <- if (inherits(cfg, \"error\")) {")),
    # "./dm" given to datom_repo_commit() is the folder dm.
    g3_dot_slash = list(filter = "^repo-unfinished$", edit = function() sub1(hl,
      "  p <- sub(\"^(\\\\./)+\", \"\", p)\n",
      ""))
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
    line <- sprintf("%-28s %s", nm, res)
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
  writeLines(results, file.path(log_dir, "coverage-probes.log"))
}
main()
