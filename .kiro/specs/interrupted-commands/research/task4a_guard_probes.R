# Guard probes for #155 task 4a. Each probe applies one deliberate edit to R/,
# runs the named test files in a fresh R process, records what reddened, and
# restores the files from a fixed backup taken once.
# Run from the repo root on the tree of task 4a's commits; the edits match that
# code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/task4a_guard_probes.R
# or, for some probes only (the control always runs first):
#   Rscript .kiro/specs/interrupted-commands/research/task4a_guard_probes.R pull_blocked_by_write
# Copied from task3_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/heal.R", "R/utils-git.R", "R/sync.R", "R/read_write.R",
             "R/forward-compat.R")
  backup <- file.path(tempdir(), "..", "datom-task4a-probe-pristine")
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
  rw <- "R/read_write.R"
  fc <- "R/forward-compat.R"
  heal_only <- "^heal$"

  probes <- list(
    control = list(filter = "^(heal|utils-git|forward-compat)$", edit = function() sub1(hl,
      "  merge_head <- trimws(readLines(merge_head_file, n = 1L, warn = FALSE))",
      "  # probe control: a comment changes nothing\n  merge_head <- trimws(readLines(merge_head_file, n = 1L, warn = FALSE))")),

    # The merge check's stop on a merge of the remote branch.
    merge_check_stop = list(filter = heal_only, edit = function() sub1(hl,
      "  .datom_stop_merge_conflict(path)\n}",
      "  invisible(NULL)\n}")),

    # The stop on a merge datom did not start: every merge read as the remote's.
    other_merge_stop = list(filter = heal_only, edit = function() sub1(hl,
      "  if (!.datom_merge_is_of_upstream(repo, merge_head)) .datom_stop_other_merge(repo)\n",
      "")),

    # Each half of "the upstream tip contains MERGE_HEAD", at the merge check's
    # own call: equality only (no descent), then descent only (no equality).
    upstream_equality_only = list(filter = heal_only, edit = function() sub1(hl,
      "  .datom_git_contains(repo, git2r::branch_target(upstream), merge_head)",
      "  identical(git2r::branch_target(upstream), merge_head)")),

    upstream_descent_only = list(filter = heal_only, edit = function() sub1(hl,
      "  .datom_git_contains(repo, git2r::branch_target(upstream), merge_head)",
      "  isTRUE(tryCatch(git2r::descendant_of(git2r::lookup(repo, git2r::branch_target(upstream)), git2r::lookup(repo, merge_head)), error = function(e) FALSE))")),

    # The reset itself: files are not put back (the note is still printed).
    no_reset = list(filter = heal_only, edit = function() sub1(hl,
      "  .datom_restore_files(conn$path, unfinished)\n",
      "")),

    # The stop on another artifact's uncommitted files: heal acts on them instead.
    no_other_artifact_stop = list(filter = heal_only, edit = function() sub1(hl,
      "  if (length(others) > 0L || (unknown_rows && !isTRUE(all))) {",
      "  if (FALSE) {")),

    # The manifest is reset only when every differing row is the command's own.
    no_manifest_row_check = list(filter = heal_only, edit = function() sub1(hl,
      "  rows <- if (manifest_rel %in% unfinished) {",
      "  rows <- if (FALSE) {")),

    # The re-run entry check after a pull that moved HEAD.
    no_recheck_after_merge = list(filter = heal_only, edit = function() sub1(hl,
      "  if (isTRUE(moved)) .datom_check_write_entry(conn, NULL)\n",
      "")),

    # The hash_algo rule for artifact folders.
    no_hash_algo_rule = list(filter = heal_only, edit = function() sub1(sy,
      "    is.list(meta) && isTRUE(meta$hash_algo %in% c(\"datom-cv1\", \"datom-sv1\"))",
      "    FALSE")),

    # The old folder rule: any folder holding a metadata.json is an artifact.
    old_folder_rule = list(filter = heal_only, edit = function() sub1(sy,
      "    if (fs::path_file(d) %in% named) return(TRUE)",
      "    return(fs::file_exists(fs::path(d, \"metadata.json\")))")),

    # Merge only when behind.
    merge_even_when_level = list(filter = "^(heal|utils-git)$", edit = function() sub1(gt,
      "  if (.datom_git_contains(repo, head_before, tip)) return(invisible(FALSE))\n",
      "")),

    # "A merge" includes a fast-forward: decided from merge()'s fields instead.
    fast_forward_not_a_merge = list(filter = heal_only, edit = function() sub1(gt,
      "  invisible(!identical(head_before, head_after))\n}",
      "  invisible(!identical(head_before, head_after) && !isTRUE(merge_result$fast_forward))\n}")),

    # The fetch-failure stop: carry on offline instead.
    fetch_failure_continues = list(filter = heal_only, edit = function() sub1(gt,
      "    .datom_stop_fetch_failed(remote_name, fetched, in_push, data_file_stored)",
      "    return(invisible(FALSE))")),

    # The caught-up check.
    no_caught_up_check = list(filter = heal_only, edit = function() sub1(gt,
      "  if (!.datom_git_contains(repo, head_after, tip)) {\n    .datom_stop_pull_blocked(in_push, data_file_stored, path)\n  }\n",
      "")),

    # Checkpoint review, finding 1: a pull blocked by an unfinished write names
    # it instead of giving the stash recipe.
    pull_blocked_by_write = list(filter = heal_only, edit = function() sub1(gt,
      "  if (length(unfinished) > 0L) {\n    .datom_stop_pull_blocked_by_write(",
      "  if (FALSE) {\n    .datom_stop_pull_blocked_by_write(")),

    # Checkpoint review, finding 2: HEAD's manifest converted to the current
    # format before its rows are compared.
    manifest_rows_raw = list(filter = heal_only, edit = function() sub1(hl,
      "    current = TRUE, source = \".datom/manifest.json (last commit)\"",
      "    current = FALSE, source = \".datom/manifest.json (last commit)\"")),

    # The rejected-push message.
    no_rejected_push_message = list(filter = heal_only, edit = function() sub1(gt,
      "      if (grepl(\"non-fastforwardable|not present locally\", conditionMessage(e))) {",
      "      if (FALSE) {")),

    # The pull before any decision, on the data-frame route.
    no_pull_before_decisions = list(filter = heal_only, edit = function() sub1(rw,
      "    .datom_heal(conn, artifact = name)\n    .datom_pull_before_write(conn)\n  }",
      "    .datom_heal(conn, artifact = name)\n  }")),

    # A refusal check placed before the merge check and heal: heal moved above it.
    heal_before_argument_checks = list(filter = heal_only, edit = function() sub1(rw,
      "  if (!is.data.frame(data)) {\n    cli::cli_abort(\"{.arg data} must be a data frame.\")\n  }",
      "  .datom_heal(conn, artifact = name)\n  if (!is.data.frame(data)) {\n    cli::cli_abort(\"{.arg data} must be a data frame.\")\n  }")),

    # The floor read from project.yaml: read from the connection instead.
    floor_from_connection = list(filter = "^(heal|forward-compat)$", edit = function() sub1(fc,
      "  declared <- cfg$min_writer_version",
      "  declared <- conn$min_writer_version"))
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
    line <- sprintf("%-30s %s", nm, res)
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
  writeLines(results, file.path(log_dir, "task4a-probes.log"))
}
main()
