# Guard probes for #155 task 2. Each probe applies one deliberate edit (to R/
# or to a test file), runs the named test files in a fresh R process, records
# what reddened, and restores the files from a fixed backup taken once.
# Run from the repo root on the tree of task 2's commit (8185b7c); the edits
# match that code exactly once each and the harness refuses one that does not.
#   Rscript .kiro/specs/interrupted-commands/research/task2_guard_probes.R
# A template for later tasks: copy it, replace the probe list.
main <- function() {
  root <- normalizePath(".")
  files <- c("R/read_write.R", "tests/testthat/test-read-write.R",
             "tests/testthat/test-hashable.R")
  backup <- file.path(tempdir(), "..", "datom-task2-probe-pristine")
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

  rw <- "R/read_write.R"
  trw <- "tests/testthat/test-read-write.R"
  th <- "tests/testthat/test-hashable.R"
  all4 <- "^(interrupted-write|read-write|identity-contract|hashable)$"

  probes <- list(
    control = list(filter = all4, edit = function() sub1(rw,
      '  if (identical(change_type, "metadata_only")) {\n    return(list(parquet_sha = current$parquet_sha, outcome = "carried"))',
      '  # probe control: a comment changes nothing\n  if (identical(change_type, "metadata_only")) {\n    return(list(parquet_sha = current$parquet_sha, outcome = "carried"))')),

    upload_after_clone_files = list(filter = "^interrupted-write$", edit = function() {
      sub1(rw, "  outcome <- .datom_storage_upload_absent(conn, tmp_path, key)",
               "  outcome <- \"uploaded\"")
      sub1(rw, "    original_file_sha = .original_file_sha,\n    format = .original_format\n  )\n",
               paste0("    original_file_sha = .original_file_sha,\n    format = .original_format\n  )\n",
                      "  if (identical(parquet_decision$outcome, \"uploaded\")) .datom_storage_upload_absent(conn, tmp, .datom_artifact_payload_key(name, data_sha, \"table\"))\n"))
    }),

    exists_records_fresh_hash = list(filter = "^(interrupted-write|read-write)$", edit = function() sub1(rw,
      "    .datom_storage_object_sha256(conn, key)\n  } else {",
      "    digest::digest(file = tmp_path, algo = \"sha256\")\n  } else {")),

    no_history_branch = list(filter = "^(identity-contract|read-write)$", edit = function() sub1(rw,
      "  reused <- .datom_lookup_history_parquet_sha(conn, name, data_sha)",
      "  reused <- NULL")),

    metadata_json_first = list(filter = "^interrupted-write$", edit = function() sub1(rw,
      "  .datom_storage_write_json(conn, s3_versioned_key, metadata)\n  .datom_storage_write_json(conn, s3_history_key, history)\n  .datom_storage_write_json(conn, s3_metadata_key, metadata)",
      "  .datom_storage_write_json(conn, s3_metadata_key, metadata)\n  .datom_storage_write_json(conn, s3_history_key, history)\n  .datom_storage_write_json(conn, s3_versioned_key, metadata)")),

    # The counting tests. (a) a code edit that makes the write upload: the
    # re-pointed counter must catch it. (b) the same edit with the test's
    # counter left on the old function: it cannot.
    metadata_only_uploads_a = list(filter = "^read-write$", edit = function() sub1(rw,
      '    return(list(parquet_sha = current$parquet_sha, outcome = "carried"))',
      '    .datom_storage_upload_absent(conn, tmp_path, .datom_artifact_payload_key(name, data_sha, "table"))\n    return(list(parquet_sha = current$parquet_sha, outcome = "carried"))')),

    metadata_only_uploads_b_old_counter = list(filter = "^read-write$", edit = function() {
      sub1(rw, '    return(list(parquet_sha = current$parquet_sha, outcome = "carried"))',
               '    .datom_storage_upload_absent(conn, tmp_path, .datom_artifact_payload_key(name, data_sha, "table"))\n    return(list(parquet_sha = current$parquet_sha, outcome = "carried"))')
      sub1(trw, '    upload <- mock_upload_absent()\n    local_mocked_bindings(\n      .datom_has_changes = function(conn, name, new_data_sha, new_metadata_sha) list(change_type = "metadata_only", current = NULL),\n      .datom_storage_upload_absent = upload$fn,',
                '    old_keys <- character()\n    upload <- mock_upload_absent()\n    local_mocked_bindings(\n      .datom_has_changes = function(conn, name, new_data_sha, new_metadata_sha) list(change_type = "metadata_only", current = NULL),\n      .datom_storage_upload_absent = upload$fn,\n      .datom_storage_upload = function(conn, lp, sk) { old_keys <<- c(old_keys, sk); invisible(TRUE) },')
      sub1(trw, "    # No parquet upload\n    expect_length(upload$keys(), 0)",
                "    # No parquet upload\n    expect_length(old_keys, 0)")
    }),

    refused_uploads_a = list(filter = "^hashable$", edit = function() sub1(rw,
      "  .datom_check_ref_current(conn)\n",
      "  .datom_check_ref_current(conn)\n  .datom_storage_upload_absent(conn, tempfile(), paste0(name, \"/probe.parquet\"))\n")),

    refused_uploads_b_old_counter = list(filter = "^hashable$", edit = function() {
      sub1(rw, "  .datom_check_ref_current(conn)\n",
               "  .datom_check_ref_current(conn)\n  .datom_storage_upload_absent(conn, tempfile(), paste0(name, \"/probe.parquet\"))\n")
      sub1(th, "    upload <- mock_upload_absent()\n    local_mocked_bindings(\n      .datom_storage_upload_absent = upload$fn,",
               "    old_keys <- character()\n    upload <- mock_upload_absent()\n    local_mocked_bindings(\n      .datom_storage_upload_absent = upload$fn,\n      .datom_storage_upload = function(conn, lp, sk) { old_keys <<- c(old_keys, sk); invisible(TRUE) },")
      sub1(th, "    expect_length(upload$keys(), 0L)", "    expect_length(old_keys, 0L)")
    }),

    # The full-write test with its counter left on the old function: it sees no
    # upload at all, so it fails. Test edit only; the code is unchanged.
    full_write_old_counter = list(filter = "^read-write$", edit = function() {
      sub1(trw, '    upload <- mock_upload_absent()\n    local_mocked_bindings(\n      .datom_has_changes = function(conn, name, new_data_sha, new_metadata_sha) list(change_type = "full", current = NULL),\n      .datom_storage_upload_absent = upload$fn,',
                '    old_keys <- character()\n    upload <- mock_upload_absent()\n    local_mocked_bindings(\n      .datom_has_changes = function(conn, name, new_data_sha, new_metadata_sha) list(change_type = "full", current = NULL),\n      .datom_storage_upload_absent = upload$fn,\n      .datom_storage_upload = function(conn, lp, sk) { old_keys <<- c(old_keys, sk); invisible(TRUE) },')
      sub1(trw, "    uploaded_keys <- upload$keys()", "    uploaded_keys <- old_keys")
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
  writeLines(results, file.path(log_dir, "task2-probes.log"))
}
main()
