# Two clones of one project write DIFFERENT tables without pulling in between.
# Does the second write's push (which pulls, then merges) hit a merge conflict,
# in which files, and does the write finish? Folder git remote + local storage;
# no AWS, no GitHub.
#
# Since task 4a every write pulls before its own work, so "without pulling in
# between" means A's push lands after B's opening pull and before B's own push.
# Updated in task 5 (2026-11-06) to make that happen: A's write runs right after
# B's commit, through a mocked .datom_git_commit() that fires once. The merge
# conflict, if any, is then reported from the git2r log of B's clone.
#
# Run: Rscript .kiro/specs/interrupted-commands/research/two_writers_probe.R
main <- function() {
  root <- normalizePath(".")
  devtools::load_all(root, quiet = TRUE)
  ns <- asNamespace("datom")
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

  # B writes lb; right after B's commit, A writes ae and pushes.
  real_commit <- ns$.datom_git_commit
  fired <- FALSE
  a_wrote <- FALSE
  notes <- character()
  r <- try(testthat::with_mocked_bindings(
    .datom_git_commit = function(...) {
      sha <- real_commit(...)
      if (!fired) {
        fired <<- TRUE
        suppressMessages(datom_write(conn_a, data = datom_example_data("ae"), name = "ae"))
        a_wrote <<- TRUE
      }
      sha
    },
    withCallingHandlers(
      datom_write(conn_b, data = datom_example_data("lb"), name = "lb"),
      message = function(m) {
        if (inherits(m, "datom_merge_finished")) {
          notes <<- c(notes, gsub("\\s+", " ", cli::ansi_strip(conditionMessage(m))))
        }
        invokeRestart("muffleMessage")
      }
    ),
    .package = "datom"
  ), silent = TRUE)

  cat("A's write ran between B's commit and B's push:", a_wrote, "\n")
  if (inherits(r, "try-error")) {
    cat("B's write: FAILED:",
        gsub("\n", " ", cli::ansi_strip(conditionMessage(attr(r, "condition")))), "\n")
    st <- git2r::status(git2r::repository(ws_b))
    cat("conflicted files in B:", paste(unlist(st$unstaged$conflicted), collapse = " "), "\n")
    return(invisible(NULL))
  }
  cat("B's write:", r$action, "\n")
  cat("datom said:", if (length(notes)) notes else "(nothing about a merge)", "\n")
  head_b <- git2r::last_commit(git2r::repository(ws_b))
  cat("B's last commit:", head_b$message, "| parents:", length(git2r::parents(head_b)), "\n")
  cat("MERGE_HEAD left in B:", file.exists(file.path(ws_b, ".git", "MERGE_HEAD")), "\n")
  stored <- ns$.datom_storage_read_json(conn_a, ".metadata/manifest.json")
  cat("stored manifest names:", paste(sort(names(stored$artifacts)), collapse = " "), "\n")
  reader <- suppressMessages(datom_get_conn(
    store = datom_store(data = datom_store_local(path = file.path(home, "storage"))),
    project_name = "P"
  ))
  cat("a reader reads lb:", nrow(as.data.frame(suppressMessages(datom_read(reader, "lb")))),
      "rows; ae:", nrow(as.data.frame(suppressMessages(datom_read(reader, "ae")))), "rows\n")
  invisible(NULL)
}
main()
