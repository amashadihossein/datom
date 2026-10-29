# Two clones of one project write DIFFERENT tables without pulling in between.
# Does the second write's push (which pulls, then merges) hit a merge conflict,
# and in which files? Folder git remote + local storage; no AWS, no GitHub.
#
# Run: Rscript .kiro/specs/interrupted-commands/research/two_writers_probe.R
main <- function() {
  devtools::load_all("~/projects/dev/datom", quiet = TRUE)
  home <- file.path(tempdir(), "two-writers")
  unlink(home, recursive = TRUE)
  dir.create(home)
  remote <- file.path(home, "remote.git")
  store <- datom_store(
    data = datom_store_local(path = file.path(home, "storage")),
    data_repo_url = remote
  )
  ws_a <- file.path(home, "a")
  ws_b <- file.path(home, "b")
  suppressMessages(datom_init_repo(ws_a, project_name = "P", store = store,
                                   create_repo = TRUE))
  conn_a <- datom_get_conn(path = ws_a, store = store)
  suppressMessages(datom_write(conn_a, data = datom_example_data("dm"), name = "dm"))
  conn_b <- suppressMessages(datom_clone(ws_b, store = store))

  # A writes ae and pushes; B, not having pulled, writes lb.
  suppressMessages(datom_write(conn_a, data = datom_example_data("ae"), name = "ae"))
  r <- try(suppressMessages(
    datom_write(conn_b, data = datom_example_data("lb"), name = "lb")
  ), silent = TRUE)

  if (inherits(r, "try-error")) {
    cat("B's write:", "FAILED:",
        gsub("\n", " ", cli::ansi_strip(conditionMessage(attr(r, "condition")))), "\n")
    st <- git2r::status(git2r::repository(ws_b))
    cat("conflicted files in B:", paste(unlist(st$unstaged$conflicted), collapse = " "), "\n")
  } else {
    cat("B's write:", r$action, "(no conflict)\n")
  }
  invisible(NULL)
}
main()
