# Guard probes for #155 task 8 (the git and config commands). Each probe applies
# one deliberate edit to R/, runs the named test files in a fresh R process,
# records what reddened, and restores the files from a fixed backup taken once.
# Run from the repo root on the tree of task 8's commit; the edits match that
# code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/task8_guard_probes.R
# or, for some probes only (the control always runs first):
#   Rscript .kiro/specs/interrupted-commands/research/task8_guard_probes.R stop_staged
# Copied from task7_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/heal.R", "R/repo.R")
  backup <- file.path(tempdir(), "..", "datom-task8-probe-pristine")
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
  rp <- "R/repo.R"
  own <- "^repo-unfinished$"
  own_fc <- "^(repo-unfinished|foreign-content)$"

  probes <- list(
    control = list(filter = own, edit = function() sub1(rp,
      "  .datom_stop_commit_of_unfinished(conn, paths)\n",
      "  # probe control: a comment changes nothing\n  .datom_stop_commit_of_unfinished(conn, paths)\n")),

    # The merge check in datom_repo_commit() (R3.9).
    merge_check = list(filter = own, edit = function() sub1(rp,
      "  .datom_check_merge(conn$path)\n  .datom_stop_commit_of_unfinished(conn, paths)\n",
      "  .datom_stop_commit_of_unfinished(conn, paths)\n")),

    # The stop on datom's own uncommitted files, as a whole (R3.5).
    commit_stop = list(filter = own_fc, edit = function() sub1(rp,
      "  .datom_stop_commit_of_unfinished(conn, paths)\n",
      "")),

    # ... with paths = NULL ...
    stop_null = list(filter = own_fc, edit = function() sub1(hl,
      "  if (is.null(paths)) return(rep(TRUE, length(files)))",
      "  if (is.null(paths)) return(rep(FALSE, length(files)))")),

    # ... a folder holding a datom file ...
    stop_folder = list(filter = own, edit = function() sub1(hl,
      "    everything || any(f == p | startsWith(f, paste0(p, \"/\")))",
      "    everything || any(f == p)")),

    # ... "." ...
    stop_everything = list(filter = own, edit = function() sub1(hl,
      "    everything || any(f == p | startsWith(f, paste0(p, \"/\")))",
      "    any(f == p | startsWith(f, paste0(p, \"/\")))")),

    # ... and a datom file already staged.
    stop_staged = list(filter = own, edit = function() sub1(hl,
      "  taken <- unfinished[unfinished %in% staged |\n                        .datom_paths_take(paths, unfinished)]",
      "  taken <- unfinished[.datom_paths_take(paths, unfinished)]")),

    # The R3.6 names are taken before the push, while the commits are the
    # clone's alone (datom_repo_push()).
    names_before_push = list(filter = own, edit = function() sub1(rp,
      "  pushed <- .datom_pushed_artifacts(conn$path)\n  .datom_git_push(conn$path, pat = conn$github_pat)\n\n  # Deliberately",
      "  .datom_git_push(conn$path, pat = conn$github_pat)\n  pushed <- .datom_pushed_artifacts(conn$path)\n\n  # Deliberately")),

    # The R3.6 message in each of the other three commands.
    commit_note = list(filter = own, edit = function() sub1(rp,
      "      .datom_note_pushed_unpublished(pushed)\n    } else {",
      "    } else {")),
    gov_note = list(filter = own, edit = function() sub1(rp,
      "{.val {project_name}}.\"\n  )\n  .datom_note_pushed_unpublished(pushed)",
      "{.val {project_name}}.\"\n  )")),
    store_note = list(filter = own, edit = function() sub1(rp,
      "{.val {conn$project_name}}.\"\n  )\n  .datom_note_pushed_unpublished(pushed)",
      "{.val {conn$project_name}}.\"\n  )")),

    # Added from task 8's checkpoint review: both checks in the two config
    # commands, each alone.
    store_merge = list(filter = own, edit = function() sub1(rp,
      "  .datom_check_merge(conn$path)\n  .datom_stop_commit_of_unfinished(conn, \".datom/project.yaml\")",
      "  .datom_stop_commit_of_unfinished(conn, \".datom/project.yaml\")")),
    store_staged = list(filter = own, edit = function() sub1(rp,
      "  .datom_stop_commit_of_unfinished(conn, \".datom/project.yaml\")\n",
      "")),
    gov_merge = list(filter = own, edit = function() sub1(rp,
      "  .datom_check_merge(conn$path)\n  .datom_stop_commit_of_unfinished(conn, \".datom/governance.json\")",
      "  .datom_stop_commit_of_unfinished(conn, \".datom/governance.json\")")),
    gov_staged = list(filter = own, edit = function() sub1(rp,
      "  .datom_stop_commit_of_unfinished(conn, \".datom/governance.json\")\n",
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
  writeLines(results, file.path(log_dir, "task8-probes.log"))
}
main()
