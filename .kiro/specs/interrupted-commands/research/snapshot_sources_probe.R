# Which routes on today's code leave a current version without its snapshot?
# A: the metadata-only route publishing a hand edit of metadata.json.
# B: a write broken at its metadata upload, then datom_validate(fix = TRUE).
main <- function() {
  suppressMessages(devtools::load_all(quiet = TRUE))  # run from the datom repo root
  ns <- asNamespace("datom")

  project <- function(label) {
    tmp <- tempfile(paste0("snap-", label, "-"))
    dir.create(tmp)
    store <- datom_store(data = datom_store_local(file.path(tmp, "storage")),
                         data_repo_url = file.path(tmp, "remote.git"))
    suppressMessages(datom_init_repo(file.path(tmp, "repo"), "SNAP", store, create_repo = TRUE))
    conn <- suppressMessages(datom_get_conn(file.path(tmp, "repo"), store))
    reader <- suppressMessages(datom_get_conn(
      store = datom_store(data = datom_store_local(file.path(tmp, "storage"))),
      project_name = "SNAP"))
    list(tmp = tmp, conn = conn, reader = reader)
  }

  report <- function(p, label) {
    stored_meta <- .datom_storage_read_json(p$conn, .datom_artifact_meta_key("dm", "metadata"))
    stored_hist <- .datom_storage_read_json(p$conn, .datom_artifact_meta_key("dm", "version_history"))
    v <- .datom_compute_metadata_sha(stored_meta)
    in_hist <- v %in% vapply(stored_hist, function(e) e$version, character(1))
    snap <- .datom_storage_exists(p$conn, .datom_artifact_snapshot_key("dm", v))
    recorded <- .datom_recorded_current_version(stored_meta, stored_hist)
    pinned <- tryCatch({ datom_read(p$reader, "dm", version = v); "reads" },
                       error = function(e) "FAILS")
    cat(sprintf("\n[%s]\n  stored metadata.json hashes to %s\n  that version in the stored history: %s\n  its snapshot stored: %s\n  version a reader is told is current: %s\n  datom_read(version = <that hash>): %s\n",
                label, substr(v, 1, 8), in_hist, snap,
                if (is.null(recorded)) "none" else substr(recorded, 1, 8), pinned))
  }

  dm <- datom_example_data("dm")

  # A. Hand edit, published by the metadata-only route.
  a <- project("A")
  on.exit(unlink(a$tmp, recursive = TRUE), add = TRUE)
  suppressMessages(datom_write(a$conn, data = dm, name = "dm"))
  mpath <- file.path(a$tmp, "repo", "dm", "metadata.json")
  m <- jsonlite::read_json(mpath)
  m$custom <- list(note = "edited by hand")
  jsonlite::write_json(m, mpath, auto_unbox = TRUE, pretty = TRUE)
  res <- suppressMessages(datom_write(a$conn, name = "dm"))
  cat("\nA: metadata-only route action:", res$action, "\n")
  report(a, "A: hand edit published by datom_write(conn, name = 'dm')")

  # B. Write broken at its metadata upload, then the repair.
  b <- project("B")
  on.exit(unlink(b$tmp, recursive = TRUE), add = TRUE)
  suppressMessages(datom_write(b$conn, data = dm, name = "dm"))
  dm2 <- dm
  dm2$AGE <- dm2$AGE + 1L
  broke <- tryCatch({
    testthat::with_mocked_bindings(
      suppressMessages(datom_write(b$conn, data = dm2, name = "dm")),
      .datom_push_metadata_s3 = function(...) stop("simulated break"),
      .package = "datom")
    FALSE
  }, error = function(e) TRUE)
  cat("\nB: break fired:", broke, "\n")
  suppressMessages(datom_validate(b$conn, fix = TRUE))
  report(b, "B: write broken at its metadata upload, then datom_validate(fix = TRUE)")
}
main()
