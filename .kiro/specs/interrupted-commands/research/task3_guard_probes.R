# Guard probes for #155 task 3. Each probe applies one deliberate edit (to R/
# or to a test file), runs the named test files in a fresh R process, records
# what reddened, and restores the files from a fixed backup taken once.
# Run from the repo root on the tree of task 3's commit; the edits match that
# code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/task3_guard_probes.R
# Copied from task2_guard_probes.R; only the file list and the probes differ.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/set.R", "R/read_write.R", "R/utils-s3.R", "R/sync.R",
             "tests/testthat/test-validate-sets.R")
  backup <- file.path(tempdir(), "..", "datom-task3-probe-pristine")
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

  st <- "R/set.R"
  rw <- "R/read_write.R"
  s3 <- "R/utils-s3.R"
  sy <- "R/sync.R"
  tvs <- "tests/testthat/test-validate-sets.R"
  all5 <- "^(interrupted-set|write-set|validate-sets|read-write|utils-s3)$"

  probes <- list(
    control = list(filter = all5, edit = function() sub1(st,
      "  payload_tmp <- tempfile(fileext = \".json\")",
      "  # probe control: a comment changes nothing\n  payload_tmp <- tempfile(fileext = \".json\")")),

    # The payload stored before anything in the clone changes: write set.json
    # into the clone first, as the old order did.
    clone_before_upload = list(filter = "^interrupted-set$", edit = function() sub1(st,
      "  document_decision <- .datom_resolve_document_sha(",
      "  fs::dir_create(fs::path(conn$path, name)); .datom_write_set_payload(payload, fs::path(conn$path, name, \"set.json\"))\n  document_decision <- .datom_resolve_document_sha(")),

    # R1.5: set.json takes the stored bytes when the recorded hash is another
    # spelling's.
    no_stored_spelling = list(filter = "^(interrupted-set|write-set)$", edit = function() sub1(st,
      "    .datom_storage_download(\n      conn, .datom_artifact_payload_key(name, data_sha, \"set\"), payload_tmp\n    )",
      "    NULL")),

    # The S3 upload sends the hash it is given rather than hashing again.
    s3_ignores_passed_hash = list(filter = "^utils-s3$", edit = function() sub1(s3,
      "  digest_raw <- if (is.null(sha256)) {",
      "  digest_raw <- if (TRUE) {")),

    # Each resolver hands the upload the hash it records (both share one helper).
    resolver_passes_no_hash = list(filter = "^(read-write|write-set)$", edit = function() sub1(rw,
      "  outcome <- .datom_storage_upload_absent(conn, tmp_path, key, sha256 = fresh_sha)",
      "  outcome <- .datom_storage_upload_absent(conn, tmp_path, key)")),

    # The set resolver's history branch (AC29b, now counting upload calls).
    set_no_history_branch = list(filter = "^write-set$", edit = function() sub1(rw,
      "  reused <- .datom_lookup_history_document_sha(conn, name, data_sha)",
      "  reused <- NULL")),

    # The restore reports nothing when the upload finds the payload stored.
    restore_claims_raced_payload = list(filter = "^validate-sets$", edit = function() sub1(sy,
      "  if (identical(outcome, \"exists\")) return(character())\n",
      "")),

    # The re-pointed repair counter (AC29c). (a) the restore calls the upload
    # for a payload that is present: the counter must catch it. (b) the same
    # edit with the counter left on the old function: it cannot.
    restore_uploads_present_a = list(filter = "^validate-sets$", edit = function() sub1(sy,
      "  if (.datom_storage_exists(conn, key)) return(character())\n",
      "")),

    restore_uploads_present_b_old_counter = list(filter = "^validate-sets$", edit = function() {
      sub1(sy, "  if (.datom_storage_exists(conn, key)) return(character())\n", "")
      sub1(tvs, "  upload <- mock_upload_absent(NULL)\n  local_mocked_bindings(.datom_storage_upload_absent = upload$fn)\n\n  fs::file_delete(vs_stored(fx, \".metadata/manifest.json\"))",
                "  old_keys <- character()\n  real_upload <- .datom_storage_upload\n  local_mocked_bindings(.datom_storage_upload = function(conn, lp, k) { old_keys <<- c(old_keys, k); real_upload(conn, lp, k) })\n\n  fs::file_delete(vs_stored(fx, \".metadata/manifest.json\"))")
      sub1(tvs, "  expect_identical(upload$keys(), character())\n})", "  expect_identical(old_keys, character())\n})")
    })
  )

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
    line <- sprintf("%-38s %s", nm, res)
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
  writeLines(results, file.path(log_dir, "task3-probes.log"))
}
main()
