# Guard probes for #155 task 9 (datom_init_repo() interrupted). Each probe
# applies one deliberate edit to R/, runs the named test files in a fresh R
# process, records what reddened, and restores the files from a fixed backup
# taken once.
# Run from the repo root on the tree of the commit it probes; the edits match
# that code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/task9_guard_probes.R
# or, for some probes only (the control always runs first):
#   Rscript .kiro/specs/interrupted-commands/research/task9_guard_probes.R p9_way_out
# Copied from audit_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/conn.R")
  backup <- file.path(tempdir(), "..", "datom-task9-probe-pristine")
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

  cn <- "R/conn.R"
  init <- "^(init-interrupted|conn)$"
  probes <- list(
    control = list(filter = init, edit = function() sub1(cn,
      "  # --- Mirror manifest to data storage ----------------------------------------",
      "  # probe control: a comment changes nothing\n  # --- Mirror manifest to data storage ----------------------------------------")),
    # The storage connection built inside the handler, so its failure gets the
    # way out too.
    p9_conn_inside = list(filter = init, edit = function() {
      sub1(cn, "  tryCatch({\n    data_conn <- .datom_build_init_conn(",
           "  data_conn <- .datom_build_init_conn(")
      sub1(cn, "      github_api_url = store$github_api_url\n    )\n    .datom_storage_write_json(data_conn, \".metadata/manifest.json\", manifest)",
           "      github_api_url = store$github_api_url\n    )\n  tryCatch({\n    .datom_storage_write_json(data_conn, \".metadata/manifest.json\", manifest)")
    }),
    # The way out spelled for someone with no connection yet.
    p9_way_out = list(filter = init, edit = function() sub1(cn,
      "               with {.code {connect_cmd}} and run \\\\",
      "               with your connection and run \\\\")),
    # The rollback before the push (kept as it was).
    p9_rollback = list(filter = init, edit = function() sub1(cn,
      "    if (!.init_success && !.git_pushed) {",
      "    if (FALSE) {")),
    # Checkpoint review: the folder check before anything touches the remote
    # (moved back to after the namespace check, where it was) ...
    p9r_check_early = list(filter = init, edit = function() {
      sub1(cn, "  path <- fs::path_abs(path)\n  .datom_check_init_folder_free(path)\n", "")
      sub1(cn, "  # --- Create directory structure",
           "  path <- fs::path_abs(path)\n  .datom_check_init_folder_free(path)\n\n  # --- Create directory structure")
    }),
    # ... and its repair line.
    p9r_repair_line = list(filter = init, edit = function() sub1(cn,
      "             {.code datom_validate(conn, fix = TRUE)} instead: it uploads the \\\\\n             manifest.\",",
      "             something.\","))
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
  writeLines(results, file.path(log_dir, "task9-probes.log"))
}
main()
