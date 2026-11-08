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


#' A teammate's clone of an interrupt project.
#'
#' Made with `datom_clone()`, as a teammate joins, so its branch tracks the
#' remote's. Two clones of one project are how a test makes one of them behind,
#' or gives the remote commits a clone lacks.
#'
#' @param fx A project from `local_interrupt_project()`.
#' @param name Folder name under the project's root.
#' @return A list with `repo` (the clone's path) and `conn`.
local_second_clone <- function(fx, name = "repo2") {
  path <- file.path(fx$root, name)
  conn <- suppressMessages(datom_clone(path, fx$store))
  list(repo = path, conn = conn)
}


#' Everything a test compares to say a command changed nothing in a clone.
#'
#' HEAD, whether a merge is in progress, `git status`, and the bytes of every
#' file in the working tree. `.git/` is left out of the file list on purpose: a
#' fetch rewrites `FETCH_HEAD` and the remote-tracking refs, which is reading
#' the remote, not changing the project.
#'
#' @param path The clone's path.
#' @return A list to compare with `expect_identical()`.
snapshot_clone <- function(path) {
  repo <- git2r::repository(path)
  files <- fs::dir_ls(path, recurse = TRUE, all = TRUE, type = "file")
  files <- files[!grepl("(^|/)\\.git(/|$)", fs::path_rel(files, path))]
  status <- git2r::status(repo, staged = TRUE, unstaged = TRUE, untracked = TRUE)
  list(
    head = as.character(git2r::revparse_single(repo, "HEAD")$sha),
    merging = fs::file_exists(fs::path(repo$path, "MERGE_HEAD")),
    status = lapply(unclass(status), function(x) sort(unlist(x))),
    files = stats::setNames(
      unname(tools::md5sum(files)),
      as.character(fs::path_rel(files, path))
    )[order(as.character(fs::path_rel(files, path)))]
  )
}


#' The branch tips of a project's bare remote.
#'
#' @param fx A project from `local_interrupt_project()`.
#' @return A named character vector, branch name to SHA.
snapshot_remote <- function(fx) {
  bare <- git2r::repository(file.path(fx$root, "remote.git"))
  heads <- git2r::branches(bare, flags = "local")
  tips <- vapply(heads, git2r::branch_target, character(1))
  tips[order(names(tips))]
}


#' Every file in a project's storage, with its bytes' hash.
#'
#' @param fx A project from `local_interrupt_project()`.
#' @return A named character vector, path to MD5.
snapshot_storage <- function(fx) {
  dir <- file.path(fx$root, "storage")
  files <- fs::dir_ls(dir, recurse = TRUE, all = TRUE, type = "file")
  rel <- as.character(fs::path_rel(files, dir))
  stats::setNames(unname(tools::md5sum(files)), rel)[order(rel)]
}


#' Commit and push files in a clone with git2r, outside datom.
#'
#' How a test makes a teammate's commit that datom did not write: a user file,
#' a hand-edited `project.yaml`, or a document "from a newer datom".
#'
#' @param path The clone's path.
#' @param files Repo-relative paths, already written.
#' @param message Commit message.
#' @param push Push to the remote too (default).
#' @return Invisibly the new commit's SHA.
git_commit_files <- function(path, files, message, push = TRUE) {
  repo <- git2r::repository(path)
  git2r::add(repo, files)
  sig <- .datom_git_signature(repo)
  commit <- git2r::commit(repo, message, author = sig, committer = sig)
  if (push) {
    git2r::push(repo, name = "origin", refspec = test_head_refspec(repo))
  }
  invisible(as.character(commit$sha))
}


#' Count calls to heal's two halves, the reset and the publish.
#'
#' Each call passes through to the real function.
#'
#' @param env Frame the counting lasts for.
#' @return A function returning `c(reset = , publish = )`.
local_heal_counter <- function(env = parent.frame()) {
  calls <- c(reset = 0L, publish = 0L)
  real_reset <- get(".datom_heal", envir = asNamespace("datom"))
  real_publish <- get(".datom_heal_publish", envir = asNamespace("datom"))
  testthat::local_mocked_bindings(
    .datom_heal = function(...) {
      calls[["reset"]] <<- calls[["reset"]] + 1L
      real_reset(...)
    },
    .datom_heal_publish = function(...) {
      calls[["publish"]] <<- calls[["publish"]] + 1L
      real_publish(...)
    },
    .env = env
  )
  function() calls
}


#' Count reads of the stored manifest, `.metadata/manifest.json`.
#'
#' Each read passes through to the real function (requirements R3.4: finding
#' unpublished work costs one read per command).
#'
#' @param env Frame the counting lasts for.
#' @return A function returning the number of reads so far.
local_stored_manifest_reads <- function(env = parent.frame()) {
  reads <- 0L
  real <- get(".datom_storage_read_json", envir = asNamespace("datom"))
  testthat::local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (identical(key, ".metadata/manifest.json")) reads <<- reads + 1L
      real(conn, key)
    },
    .env = env
  )
  function() reads
}
