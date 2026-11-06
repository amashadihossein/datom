# A write to dm breaks; the next command is a write to a DIFFERENT table, lb.
# What does lb's write do with dm's unfinished state?
# Break dm at the commit (its files written, not committed) or at the push
# (committed, not pushed). A row counts only if its break fired. Then write lb
# and report whether it stopped (and on what), and, for dm:
#   - the version git's manifest names, at the remote's HEAD
#   - the version dm/metadata.json holds, at the remote's HEAD
#   - the version the stored manifest names, and the stored metadata.json
# Folder git remote + local storage; no AWS, no GitHub. Nothing in R/ is edited.
#
# Since task 4a (#155): a write heals only the artifact it is writing, so after
# dm broke before its commit lb's write stops, naming dm and
# `datom_validate(fix = TRUE)`, with nothing changed. After a break at dm's push
# (committed, not pushed) lb's write still goes ahead until task 4b.
#
# Run from the repo root:
#   Rscript .kiro/specs/interrupted-commands/research/other_command_probe.R
main <- function() {
  repo_root <- local({
    f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
    if (length(f)) normalizePath(file.path(dirname(f), "..", "..", "..", "..")) else getwd()
  })
  devtools::load_all(repo_root, quiet = TRUE)
  ns <- asNamespace("datom")
  a <- datom_example_data("dm")
  b <- a
  b[[1]][1] <- paste0(b[[1]][1], "-changed")
  lb <- datom_example_data("lb")

  short <- function(x) if (is.null(x)) "none" else substr(x, 1, 8)

  for (step in c("commit", "push")) {
    home <- file.path(tempdir(), paste0("other-", step))
    unlink(home, recursive = TRUE)
    dir.create(home)
    remote <- file.path(home, "remote.git")
    store <- datom_store(
      data = datom_store_local(path = file.path(home, "storage")),
      data_repo_url = remote
    )
    ws <- file.path(home, "ws")
    suppressMessages(datom_init_repo(ws, project_name = "P", store = store,
                                     create_repo = TRUE))
    conn <- suppressMessages(datom_get_conn(path = ws, store = store))
    suppressMessages(datom_write(conn, data = a, name = "dm", message = "dm v1"))

    mock <- if (step == "commit") {
      list(.datom_git_commit = function(...) stop("simulated break"))
    } else {
      list(.datom_git_push = function(...) stop("simulated break"))
    }
    broke <- try(do.call(testthat::with_mocked_bindings, c(mock, list(
      code = quote(suppressMessages(
        datom_write(conn, data = b, name = "dm", message = "dm v2")
      )),
      .package = "datom"
    ))), silent = TRUE)
    fired <- inherits(broke, "try-error") &&
      grepl("simulated break", conditionMessage(attr(broke, "condition")))

    head_before <- as.character(git2r::revparse_single(git2r::repository(ws), "HEAD")$sha)
    lb_result <- tryCatch(
      { suppressMessages(datom_write(conn, data = lb, name = "lb", message = "lb v1")); "wrote lb" },
      error = function(e) {
        paste0("STOPPED [", class(e)[1], "]: ",
               gsub("\\s+", " ", cli::ansi_strip(conditionMessage(e))))
      }
    )
    head_after <- as.character(git2r::revparse_single(git2r::repository(ws), "HEAD")$sha)

    # Read the remote's HEAD directly from the bare repo, with the git CLI.
    git_remote <- function(...) {
      system2("git", c(paste0("--git-dir=", remote), ...), stdout = TRUE)
    }
    blob_at <- function(path) {
      txt <- git_remote("show", paste0("HEAD:", path))
      jsonlite::fromJSON(paste(txt, collapse = "\n"), simplifyVector = FALSE)
    }
    remote_manifest <- blob_at(".datom/manifest.json")
    remote_meta <- blob_at("dm/metadata.json")
    stored_manifest <- ns$.datom_storage_read_json(conn, ".metadata/manifest.json")
    stored_meta <- ns$.datom_storage_read_json(conn, "dm/.metadata/metadata.json")
    lb_stored <- ns$.datom_storage_exists(conn, "lb/.metadata/metadata.json")

    remote_meta_sha <- ns$.datom_compute_metadata_sha(remote_meta)
    stored_meta_sha <- ns$.datom_compute_metadata_sha(stored_meta)

    cat(sprintf("\ndm broke at %-6s | break fired: %s\n", step, fired))
    if (!fired) {
      cat("   ROW NOT COUNTED: the break did not fire.\n")
      next
    }
    cat("   lb's write:", lb_result, "\n")
    cat(sprintf(
      "   clone HEAD moved during lb's write: %s | lb metadata in storage: %s\n",
      !identical(head_before, head_after), lb_stored
    ))
    cat(sprintf(
      "   GitHub manifest: dm %s | GitHub dm/metadata.json: %s | stored manifest: dm %s | stored metadata.json: %s\n",
      short(remote_manifest$artifacts$dm$current_version),
      short(remote_meta_sha),
      short(stored_manifest$artifacts$dm$current_version),
      short(stored_meta_sha)
    ))
    cat("   GitHub log:", paste(git_remote("log", "--format=%s", "-3"), collapse = " | "), "\n")
  }
  invisible(NULL)
}
`%||%` <- function(x, y) if (is.null(x)) y else x
main()
