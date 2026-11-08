# Guard probes for #155 task 6. Each probe applies one deliberate edit to R/,
# runs the named test files in a fresh R process, records what reddened, and
# restores the files from a fixed backup taken once.
# Run from the repo root on the tree of task 6's commit; the edits match that
# code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/task6_guard_probes.R
# or, for some probes only (the control always runs first):
#   Rscript .kiro/specs/interrupted-commands/research/task6_guard_probes.R left_head
# Copied from task5_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/heal.R", "R/sync.R")
  backup <- file.path(tempdir(), "..", "datom-task6-probe-pristine")
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
  both <- "^sync(-heal)?$"

  probes <- list(
    control = list(filter = both, edit = function() sub1(hl,
      "  .datom_git_head_sha(git2r::repository(path))",
      "  # probe control: a comment changes nothing\n  .datom_git_head_sha(git2r::repository(path))")),

    # The stop's first sign: HEAD moved (the write committed).
    left_head = list(filter = both, edit = function() sub1(hl,
      "  if (!identical(.datom_clone_head(conn$path), head_before)) return(TRUE)\n",
      "")),

    # Its second sign: datom's files left uncommitted.
    left_files = list(filter = both, edit = function() sub1(hl,
      "  length(.datom_unfinished_files(conn)) > 0L",
      "  FALSE")),

    # A failure that left the clone untouched carries on: make every failure stop.
    left_always = list(filter = both, edit = function() sub1(hl,
      ".datom_write_left_changes <- function(conn, head_before) {",
      ".datom_write_left_changes <- function(conn, head_before) {\n  return(TRUE)")),

    # The stop itself: the loop goes on after a write that changed the clone.
    stop_break = list(filter = both, edit = function() sub1(sy,
      "    if (!is.null(stopped_at)) break",
      "    if (FALSE) break")),

    # The scan compares with the last commit (R4.1), not the working tree.
    scan_head = list(filter = both, edit = function() sub1(sy,
      "  read <- .datom_read_manifest(conn, \"head\")",
      "  read <- .datom_read_manifest(conn, \"clone\")")),

    # The unpushed status (R4.2).
    unpushed_check = list(filter = both, edit = function() sub1(sy,
      "    result$status[unpushed] <- \"unpushed\"",
      "    invisible(unpushed)")),

    # `unpushed` measured from the commit shared with the remote, not its tip.
    pushed_from_base = list(filter = both, edit = function() sub1(hl,
      "  base <- git2r::merge_base(head_commit, git2r::lookup(repo, tip))",
      "  base <- git2r::lookup(repo, tip)")),

    # The format check on every preview table, before the sync's one heal.
    door_check = list(filter = both, edit = function() sub1(sy,
      "  .datom_check_write_entry(conn, own)\n",
      "")),

    # Heal once per sync: each table's write heals again.
    heal_once = list(filter = both, edit = function() sub1(sy,
      "        .original_format = tbl_format,\n        .healed = TRUE",
      "        .original_format = tbl_format")),

    # Heal may reset only the rows the sync writes again.
    rewrite_list = list(filter = both, edit = function() sub1(sy,
      "  rewrite <- unique(manifest$name[manifest$status %in% c(\"new\", \"changed\")])",
      "  rewrite <- own")),

    # An unpushed row, finished by heal, comes back success (R4.3).
    unpushed_success = list(filter = both, edit = function() sub1(sy,
      "  manifest$result[finished] <- \"success\"",
      "  invisible(finished)")),

    # Added from the checkpoint review of c24b17f: a held-back manifest stops
    # the sync. The handler that notices it ...
    held_back_handler = list(filter = both, edit = function() sub1(sy,
      "          held_back <<- as.character(w$disagree %||% character())",
      "          invisible(w)")),

    # ... and the stop it sets.
    held_back_stop = list(filter = both, edit = function() sub1(sy,
      "    if (!is.null(held_back) && is.null(stopped_at)) stopped_at <- tbl_name",
      "    if (FALSE) stopped_at <- tbl_name"))
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
    line <- sprintf("%-20s %s", nm, res)
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
  writeLines(results, file.path(log_dir, "task6-probes.log"))
}
main()
