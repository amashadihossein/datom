# Two follow-ups to write_steps_probe.R.
# A. datom_sync() broken at the git push (not the upload): does a re-scan and a
#    second sync finish the table?
# B. datom_write() broken at the final manifest mirror: after the re-run (which
#    reports "none"), what does a reader's datom_list() say about the version?
# Folder git remote + local storage; no AWS, no GitHub. Nothing in R/ is edited.
#
# Run: Rscript .kiro/specs/interrupted-commands/research/sync_and_manifest_probe.R
main <- function() {
  devtools::load_all("~/projects/dev/datom", quiet = TRUE)
  ns <- asNamespace("datom")

  setup <- function(label) {
    home <- file.path(tempdir(), paste0("probe2-", label))
    unlink(home, recursive = TRUE)
    dir.create(home)
    store <- datom_store(
      data = datom_store_local(path = file.path(home, "storage")),
      data_repo_url = file.path(home, "remote.git")
    )
    ws <- file.path(home, "ws")
    suppressMessages(datom_init_repo(ws, project_name = "P", store = store,
                                     create_repo = TRUE))
    conn <- datom_get_conn(path = ws, store = store)
    reader <- datom_get_conn(store = datom_store(
      data = datom_store_local(path = file.path(home, "storage"))),
      project_name = "P")
    list(conn = conn, reader = reader, ws = ws)
  }

  # --- A ---------------------------------------------------------------------
  p <- setup("sync-push")
  file.copy(system.file("extdata", "dm.csv", package = "datom"),
            file.path(p$ws, "input_files", "dm.csv"))
  m <- suppressMessages(datom_sync_manifest(p$conn))
  r <- testthat::with_mocked_bindings(
    .datom_git_push = function(...) stop("simulated break"),
    suppressMessages(datom_sync(p$conn, m)),
    .package = "datom"
  )
  cat("A sync 1 result:", r$result, "\n")
  m2 <- suppressMessages(datom_sync_manifest(p$conn))
  cat("A scan 2 status:", m2$status, "\n")
  r2 <- suppressMessages(datom_sync(p$conn, m2))
  cat("A sync 2 result:", r2$result, "\n")
  x <- try(suppressMessages(datom_read(p$reader, "dm")), silent = TRUE)
  cat("A reader:", if (inherits(x, "try-error")) "READ FAILS" else "reads", "\n")

  # --- B ---------------------------------------------------------------------
  p <- setup("manifest")
  a <- datom_example_data("dm")
  b <- a
  b[[1]][1] <- paste0(b[[1]][1], "-changed")
  suppressMessages(datom_write(p$conn, data = a, name = "dm", message = "v1"))
  real <- ns$.datom_storage_write_json
  try(testthat::with_mocked_bindings(
    .datom_storage_write_json = function(conn, key, data) {
      if (identical(key, ".metadata/manifest.json")) stop("simulated break")
      real(conn, key, data)
    },
    suppressMessages(datom_write(p$conn, data = b, name = "dm", message = "v2")),
    .package = "datom"
  ), silent = TRUE)
  r <- suppressMessages(datom_write(p$conn, data = b, name = "dm", message = "v2"))
  cat("B re-run action:", r$action, "\n")
  current <- datom_history(p$conn, "dm")$version[1]
  listed <- suppressMessages(datom_list(p$reader))
  cat("B current version:", substr(current, 1, 8),
      "| reader's list says:", substr(listed$current_version[listed$name == "dm"], 1, 8), "\n")
  invisible(NULL)
}
main()
