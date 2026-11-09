# Guard probes for #155's purity audit after task 8 (point 1: the push before
# publishing, in one place). Each probe applies one deliberate edit to R/, runs
# the named test files in a fresh R process, records what reddened, and restores
# the files from a fixed backup taken once.
# Run from the repo root on the tree of the commit it probes; the edits match
# that code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/audit_guard_probes.R
# or, for some probes only (the control always runs first):
#   Rscript .kiro/specs/interrupted-commands/research/audit_guard_probes.R publish_push
# Copied from task8_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/heal.R", "R/sync.R", "R/utils-sha.R", "R/utils-git.R")
  backup <- file.path(tempdir(), "..", "datom-audit-probe-pristine")
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
  gt <- "R/utils-git.R"
  publish <- "^(heal|heal-publish)$"
  repair <- "^repair$"
  publish_push_line <- "  pushed <- is.na(ahead) || ahead > 0L\n  if (pushed) .datom_git_push(conn$path, pat = conn$github_pat, pull_first = FALSE)\n"
  probes <- list(
    control = list(filter = "^(heal-publish|repair)$", edit = function() sub1(hl,
      "  outcomes <- purrr::map(names, function(nm) {",
      "  # probe control: a comment changes nothing\n  outcomes <- purrr::map(names, function(nm) {")),
    # Point 1: the one push before publishing, for every caller (heal's
    # publish, the metadata-only route, the repair).
    publish_push = list(filter = "^(heal|heal-publish|repair|read-write)$", edit = function() sub1(hl,
      publish_push_line,
      "  pushed <- FALSE\n")),
    # ... which does not pull (task 4b's heal_push_does_not_pull, moved).
    publish_push_does_not_pull = list(filter = publish, edit = function() sub1(hl,
      publish_push_line,
      "  pushed <- is.na(ahead) || ahead > 0L\n  if (pushed) .datom_git_push(conn$path, pat = conn$github_pat, pull_first = TRUE)\n")),
    # Heal's gate decided by the manifests alone (task 4b's gate_ignores_ahead,
    # restated: the clone being ahead must not open it).
    gate_ignores_ahead = list(filter = publish, edit = function() sub1(hl,
      "  if (length(differ) == 0L) {\n    return(invisible(list(published = character(), pushed = pushed)))",
      "  if (isTRUE(.datom_git_ahead(conn$path) == 0L) && length(differ) == 0L) {\n    return(invisible(list(published = character(), pushed = pushed)))")),
    # The early push with no upstream branch, before storage is read.
    no_upstream_early_push = list(filter = publish, edit = function() sub1(hl,
      "  pushed <- is.na(.datom_git_ahead(conn$path))\n  if (pushed) .datom_git_push(conn$path, pat = conn$github_pat, pull_first = FALSE)\n",
      "  pushed <- FALSE\n")),
    # Task 7's restore_before_heal, retargeted: the repair's payload restore
    # moved after heal's publish.
    restore_before_heal = list(filter = repair, edit = function() {
      sub1(sy, "  .datom_repair_restore_payloads(conn, names_now)\n", "")
      sub1(sy, "  heal_publish <- .datom_heal_publish(conn, all = TRUE)\n",
           "  heal_publish <- .datom_heal_publish(conn, all = TRUE)\n  .datom_repair_restore_payloads(conn, names_now)\n")
    }),
    # Point 2: the one stop for unfinished work. The teammate line ...
    p2_teammate_line = list(filter = publish, edit = function() sub1(hl,
      "      if (isTRUE(teammate)) {",
      "      if (FALSE) {")),
    # ... asked for by heal's publish, whose stored rows can be a teammate's ...
    p2_teammate_caller = list(filter = publish, edit = function() sub1(hl,
      "      teammate = TRUE\n",
      "      teammate = FALSE\n")),
    # ... the way out with no artifact to name ...
    p2_manifest_only_way_out = list(filter = publish, edit = function() sub1(hl,
      "  way_out <- if (n == 0L) {",
      "  way_out <- if (FALSE) {")),
    # ... the pull's own class kept beside the shared one ...
    p2_extra_class = list(filter = publish, edit = function() sub1(hl,
      "    class = c(class, \"datom_unfinished_work\")",
      "    class = \"datom_unfinished_work\"")),
    # ... and the shared class on every caller.
    p2_shared_class = list(filter = publish, edit = function() sub1(hl,
      "    class = c(class, \"datom_unfinished_work\")",
      "    class = class %||% \"datom_unfinished_work\"")),
    # Point 3: the one line saying what happened, in the shared stop ...
    p3_unfinished_line = list(filter = "^(heal|repo-unfinished)$", edit = function() sub1(hl,
      "      purrr::set_names(details, rep(\"*\", length(details))),\n      \"i\" = \"Nothing was published.\",",
      "      purrr::set_names(details, rep(\"*\", length(details))),")),
    # ... in the merge-conflict stop, from the pull and from the merge check ...
    p3_merge_conflict_line = list(filter = "^(heal|manifest-conflict|utils-git)$", edit = function() sub1(hl,
      "      \"i\" = \"Nothing was published.\",\n      \"i\" = rerun",
      "      \"i\" = rerun")),
    # ... and in the fetch failure.
    p3_fetch_line = list(filter = "^heal$", edit = function() sub1(gt,
      "      \"i\" = \"Nothing was published.\",\n      \"i\" = \"Check your connection",
      "      \"i\" = \"Check your connection"))
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
  writeLines(results, file.path(log_dir, "audit-probes.log"))
}
main()
