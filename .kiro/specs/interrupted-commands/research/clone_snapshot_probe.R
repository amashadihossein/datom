# Does any datom command put {name}/.metadata/ in the clone? A real project:
# folder git remote, local store. Writes a table, a metadata-only version,
# and a set, then lists every file in the clone and the stored snapshots.
main <- function() {
  suppressMessages(devtools::load_all(quiet = TRUE))  # run from the datom repo root
  tmp <- tempfile("clone-snap-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  store <- datom_store(data = datom_store_local(file.path(tmp, "storage")),
                       data_repo_url = file.path(tmp, "remote.git"))
  suppressMessages(datom_init_repo(file.path(tmp, "repo"), "SNAP", store, create_repo = TRUE))
  conn <- suppressMessages(datom_get_conn(file.path(tmp, "repo"), store))

  dm <- datom_example_data("dm")
  suppressMessages(datom_write(conn, data = dm, name = "dm"))
  suppressMessages(datom_write(conn, data = dm, name = "dm", metadata = list(note = "v2")))
  suppressMessages(datom_write(conn, data = dm, name = "dm", metadata = list(note = "v3")))

  cat("--- every file under the clone's dm/ (dotfiles included) ---\n")
  print(as.character(fs::path_rel(fs::dir_ls(file.path(tmp, "repo", "dm"), recurse = TRUE, all = TRUE),
                                  file.path(tmp, "repo"))))
  cat("dm/.metadata exists in the clone:", dir.exists(file.path(tmp, "repo", "dm", ".metadata")), "\n")

  cat("--- tracked files in git ---\n")
  print(system2("git", c("-C", file.path(tmp, "repo"), "ls-files"), stdout = TRUE))

  cat("--- stored keys under dm/ ---\n")
  keys <- datom_storage_list(conn)
  print(keys[grepl("/dm/", keys)])

  hist <- jsonlite::read_json(file.path(tmp, "repo", "dm", "version_history.json"))
  versions <- vapply(hist, function(e) e$version, character(1))
  cat("versions in the clone's history:", length(versions), "\n")
  cat("each version's snapshot stored:",
      vapply(versions, function(v) .datom_storage_exists(conn, .datom_artifact_snapshot_key("dm", v)), logical(1)), "\n")

  # The repair, on this clone: which keys does it write? (Until #155 task 7 this
  # called the per-artifact copy, `.datom_sync_one_artifact()`, which never
  # wrote a snapshot; the repair now publishes through the one publish path.)
  written <- character()
  real <- get(".datom_storage_write_json", asNamespace("datom"))
  out <- testthat::with_mocked_bindings(
    suppressMessages(.datom_sync_data_metadata(conn, .confirm = FALSE)),
    .datom_storage_write_json = function(conn, key, data) {
      written <<- c(written, key)
      real(conn, key, data)
    },
    .package = "datom"
  )
  cat("--- keys the repair wrote ---\n")
  print(written)
  current <- jsonlite::read_json(file.path(tmp, "repo", ".datom", "manifest.json"))$artifacts$dm$current_version
  cat("the repair wrote the current version's snapshot:",
      .datom_artifact_snapshot_key("dm", current) %in% written, "\n")
}
main()
