# Task 6's plan for datom_sync(): heal once for the whole batch, then write each
# table with datom_write(.healed = TRUE), so no table's write runs heal. What
# happens when table t2's write fails partway and t3's write then succeeds?
# Simulated with datom_write() directly (the same calls the planned sync would
# make), so no input files and no rio are needed. Folder git remote + local
# storage; no AWS, no GitHub. Nothing in R/ is edited.
#
# Written 2026-11-06, after task 5, to check task 6's plan before its code
# (tasks.md, task 6, the open point). Result on 6d622e9:
# - t2 broken at its push, or at its metadata upload: t3's write publishes the
#   clone's whole manifest, which names t2's new version while storage holds
#   t2's old metadata.json. A reader reads t2's old version, and a re-run (heal
#   once, nothing left to write) publishes nothing for t2: heal compares
#   manifest rows, and they agree.
# - t2 broken at its commit: t3's commit takes t2's uncommitted manifest row,
#   so the last commit names t2's new version beside t2's old metadata.json,
#   and t3's publish puts that row in storage (P4: something never committed by
#   t2's write is published).
#
# Run: Rscript .kiro/specs/interrupted-commands/research/sync_batch_probe.R
main <- function() {
  root <- normalizePath(".")
  suppressMessages(devtools::load_all(root, quiet = TRUE))
  ns <- asNamespace("datom")
  tables <- c("t1", "t2", "t3")
  df <- function(n) data.frame(id = seq_len(n), val = rep("a", n))

  for (step in c("push", "metadata", "commit")) {
    home <- file.path(tempdir(), paste0("sync-batch-", step))
    unlink(home, recursive = TRUE)
    dir.create(home)
    store <- datom_store(
      data = datom_store_local(path = file.path(home, "storage")),
      data_repo_url = file.path(home, "remote.git")
    )
    repo <- file.path(home, "repo")
    suppressMessages(datom_init_repo(repo, "P", store, create_repo = TRUE))
    conn <- suppressMessages(datom_get_conn(repo, store))
    for (t in tables) suppressMessages(datom_write(conn, df(3), t))
    v1 <- jsonlite::read_json(file.path(repo, ".datom", "manifest.json"))$artifacts$t2$current_version
    reader <- suppressMessages(datom_get_conn(
      store = datom_store(data = datom_store_local(path = file.path(home, "storage"))),
      project_name = "P"
    ))

    # The planned sync's one heal.
    heal_once <- function(rewrite) {
      healed <- ns$.datom_heal(conn, artifact = tables, rewrite = rewrite)
      ns$.datom_pull_before_write(conn)
      suppressMessages(ns$.datom_heal_publish(conn, artifact = tables))
    }
    broken <- switch(step,
      push = list(.datom_git_push = function(...) stop("simulated break")),
      metadata = list(.datom_push_metadata_s3 = function(...) stop("simulated break")),
      commit = list(.datom_git_commit = function(...) stop("simulated break"))
    )

    cat("== t2 broken at its", step, "\n")
    heal_once(c("t2", "t3"))
    r <- try(do.call(testthat::with_mocked_bindings, c(broken, list(
      code = quote(suppressMessages(datom_write(conn, df(5), "t2", .healed = TRUE))),
      .package = "datom"
    ))), silent = TRUE)
    cat("  t2's write:", if (inherits(r, "try-error")) "failed (the break fired)" else r$action, "\n")
    r <- suppressMessages(datom_write(conn, df(5), "t3", .healed = TRUE))
    cat("  t3's write:", r$action, "\n")

    stored <- ns$.datom_storage_read_json(conn, ".metadata/manifest.json")
    stored_meta <- ns$.datom_storage_read_json(conn, ns$.datom_artifact_meta_key("t2", "metadata"))
    head_manifest <- jsonlite::fromJSON(ns$.datom_git_head_file(repo, ".datom/manifest.json"),
                                        simplifyVector = FALSE)
    head_meta <- jsonlite::fromJSON(ns$.datom_git_head_file(repo, "t2/metadata.json"),
                                    simplifyVector = FALSE)
    cat("  last commit: manifest names t2's new version:",
        !identical(head_manifest$artifacts$t2$current_version, v1),
        "| t2/metadata.json is the new version:",
        !identical(ns$.datom_compute_metadata_sha(head_meta), v1), "\n")
    cat("  storage: manifest names t2's new version:",
        !identical(stored$artifacts$t2$current_version, v1),
        "| t2's metadata.json is the new version:",
        !identical(ns$.datom_compute_metadata_sha(stored_meta), v1), "\n")
    cat("  a reader reads t2:", nrow(as.data.frame(suppressMessages(datom_read(reader, "t2")))),
        "rows (3 = old, 5 = new)\n")

    if (step != "commit") {
      heal_once(character())
      stored_meta <- ns$.datom_storage_read_json(conn, ns$.datom_artifact_meta_key("t2", "metadata"))
      cat("  after a re-run (heal once, nothing left to write): t2's stored metadata.json is new:",
          !identical(ns$.datom_compute_metadata_sha(stored_meta), v1), "\n")
    }
  }
  invisible(NULL)
}
main()
