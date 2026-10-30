# DD3: a colleague imports a file first; you built your sync preview before
# pulling, then datom_sync() pulls (stand-in: datom_pull(), which heal's pull
# will do) and applies the stale preview. What does your sync do with that row?
# Folder git remote + local storage; no AWS, no GitHub. Nothing in R/ is edited.
#
# Run: Rscript .kiro/specs/interrupted-commands/research/stale_preview_probe.R
main <- function() {
  devtools::load_all("~/projects/dev/datom", quiet = TRUE)
  home <- file.path(tempdir(), "stale-preview")
  unlink(home, recursive = TRUE)
  dir.create(home)
  store <- datom_store(
    data = datom_store_local(path = file.path(home, "storage")),
    data_repo_url = file.path(home, "remote.git")
  )
  ws_you <- file.path(home, "you")
  ws_col <- file.path(home, "colleague")
  suppressMessages(datom_init_repo(ws_you, project_name = "P", store = store,
                                   create_repo = TRUE))
  you <- datom_get_conn(path = ws_you, store = store)
  col <- suppressMessages(datom_clone(ws_col, store = store))

  csv <- system.file("extdata", "dm.csv", package = "datom")
  file.copy(csv, file.path(ws_you, "input_files", "dm.csv"))
  # input_files/ is git-ignored, so a fresh clone does not have the folder.
  dir.create(file.path(ws_col, "input_files"), showWarnings = FALSE)
  file.copy(csv, file.path(ws_col, "input_files", "dm.csv"))

  # You build the preview first, before the colleague syncs.
  m <- suppressMessages(datom_sync_manifest(you))
  cat("your preview says:", m$status, "\n")

  # The colleague imports the same file and pushes.
  r_col <- suppressMessages(datom_sync(col, datom_sync_manifest(col)))
  cat("colleague's sync:", r_col$result, "\n")
  head_before <- system2("git", c("-C", ws_you, "rev-parse", "--short", "HEAD"), stdout = TRUE)

  # The pull heal will make, then your sync with the stale preview.
  suppressMessages(datom_pull(you))
  out <- capture.output(r <- datom_sync(you, m), type = "message")
  cat("your sync result:", r$result, "\n")
  cat("your sync said:", paste(grep("No changes|synced|Wrote",
                                    cli::ansi_strip(out), value = TRUE), collapse = " | "), "\n")
  hist <- datom_history(you, "dm")
  cat("versions of dm:", nrow(hist), "\n")
  log <- system2("git", c("-C", ws_you, "log", "--format=%s", "-3"), stdout = TRUE)
  cat("your git log:", paste(log, collapse = " | "), "\n")
  invisible(NULL)
}
main()
