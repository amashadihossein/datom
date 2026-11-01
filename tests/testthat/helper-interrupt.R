# Test helpers for interrupted commands (#155) -- loaded automatically by testthat.
#
# A real project (folder git remote, local store; no AWS, no GitHub) and a way
# to break one command at one named step, so a test can re-run the command and
# check what a reader sees. The mechanics follow the probes in
# `.kiro/specs/interrupted-commands/research/`.


#' A real datom project for break-and-re-run tests.
#'
#' Built through `datom_init_repo()` and `datom_get_conn()`, as a user would, so
#' commit, push and storage all run for real. `reader` is a connection with no
#' clone, which sees only what storage publishes: the observer every
#' break-and-re-run test asks.
#'
#' @param project_name Project name.
#' @param ... Passed to `datom_init_repo()`, e.g. `mode = "product", set =` for
#'   a product repo that writes a set.
#' @param env Frame whose exit removes the project.
#' @return A list with `root`, `store`, `repo` (the clone's path), `conn` (the
#'   developer connection) and `reader`.
local_interrupt_project <- function(project_name = "P", ..., env = parent.frame()) {
  skip_if_no_git2r()
  root <- withr::local_tempdir(.local_envir = env)
  storage <- file.path(root, "storage")
  store <- datom_store(
    data = datom_store_local(storage),
    data_repo_url = file.path(root, "remote.git")
  )
  repo <- file.path(root, "repo")
  suppressMessages(datom_init_repo(repo, project_name, store, create_repo = TRUE, ...))
  conn <- suppressMessages(datom_get_conn(repo, store))
  reader <- suppressMessages(datom_get_conn(
    store = datom_store(data = datom_store_local(storage)),
    project_name = project_name
  ))
  list(root = root, store = store, repo = repo, conn = conn, reader = reader)
}


#' The condition a simulated break raises.
#'
#' Its own class, so a test can assert that the break it set up is the error
#' the command stopped on. A break that never fires (because the code stopped
#' calling the function it replaces) then fails the test instead of quietly
#' turning a break-and-re-run test into a plain write test.
#'
#' @param step The step name, for the message.
#' @return A condition of class `datom_test_break`.
datom_test_break <- function(step) {
  structure(
    class = c("datom_test_break", "error", "condition"),
    list(message = paste0("simulated break at ", step), call = NULL)
  )
}


#' Break a write at one named step, for the rest of the calling frame.
#'
#' Each step is a mocked binding that raises `datom_test_break`. Steps, in the
#' order a table write or a set write runs them:
#'
#' * `"upload"` -- the data file upload (a table's parquet, a set's payload),
#'   `.datom_storage_upload_absent()`;
#' * `"clone_files"` -- after `metadata.json` and `version_history.json` (and a
#'   set's `set.json`) are written in the clone, before its manifest row
#'   (`.datom_update_manifest_entry()`);
#' * `"commit"` -- `.datom_git_commit()`;
#' * `"push"` -- `.datom_git_push()`;
#' * `"metadata"` -- the whole metadata upload, `.datom_push_metadata_s3()`;
#' * `"history"` -- inside it, at the upload of the stored `version_history.json`
#'   (the snapshot is already up, `metadata.json` not yet);
#' * `"metadata_json"` -- inside it, at the upload of the stored `metadata.json`
#'   (snapshot and history already up);
#' * `"manifest"` -- the stored manifest upload.
#'
#' Scope it with `local()` or a small function, so the re-run that follows runs
#' unbroken.
#'
#' @param step One of the names above.
#' @param name The artifact being written, for the steps keyed on its files.
#' @param env Frame the break lasts for.
#' @return Invisibly `NULL`.
local_break_at <- function(step, name = NULL, env = parent.frame()) {
  real_write_json <- get(".datom_storage_write_json", envir = asNamespace("datom"))
  boom <- function(...) stop(datom_test_break(step))
  at_key <- function(wanted) {
    function(conn, key, data) {
      if (identical(key, wanted)) stop(datom_test_break(step))
      real_write_json(conn, key, data)
    }
  }
  needs_name <- c("history", "metadata_json")
  if (step %in% needs_name && is.null(name)) {
    stop("local_break_at(\"", step, "\") needs the artifact `name`.", call. = FALSE)
  }

  bindings <- switch(step,
    upload = list(.datom_storage_upload_absent = boom),
    clone_files = list(.datom_update_manifest_entry = boom),
    commit = list(.datom_git_commit = boom),
    push = list(.datom_git_push = boom),
    metadata = list(.datom_push_metadata_s3 = boom),
    history = list(.datom_storage_write_json =
                     at_key(.datom_artifact_meta_key(name, "version_history"))),
    metadata_json = list(.datom_storage_write_json =
                           at_key(.datom_artifact_meta_key(name, "metadata"))),
    manifest = list(.datom_storage_write_json = at_key(".metadata/manifest.json")),
    stop("local_break_at(): unknown step \"", step, "\".", call. = FALSE)
  )

  do.call(testthat::local_mocked_bindings, c(bindings, list(.env = env)))
  invisible(NULL)
}
