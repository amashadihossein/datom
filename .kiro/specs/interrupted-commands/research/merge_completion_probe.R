# Can datom complete a merge through git2r after rewriting a conflicted
# .datom/manifest.json itself (R3.8)? Two clones write different tables without
# pulling in between; the second clone's pull conflicts on the manifest only.
# The probe then overwrites the manifest, stages it, commits, and pushes, and
# reports: the parents of the new commit, whether MERGE_HEAD is gone, whether
# the push lands, and what a third, fresh clone sees.
# Folder git remote + local storage; no AWS, no GitHub. Nothing in R/ is edited.
#
# Run: Rscript .kiro/specs/interrupted-commands/research/merge_completion_probe.R
main <- function() {
  devtools::load_all("~/projects/dev/datom", quiet = TRUE)
  ns <- asNamespace("datom")
  home <- file.path(tempdir(), "merge-completion")
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

  suppressMessages(datom_write(conn_a, data = datom_example_data("ae"), name = "ae"))

  # B writes lb but its push is made to fail, so B holds one unpushed commit.
  try(testthat::with_mocked_bindings(
    .datom_git_push = function(...) stop("simulated break"),
    suppressMessages(datom_write(conn_b, data = datom_example_data("lb"), name = "lb")),
    .package = "datom"
  ), silent = TRUE)
  repo_b <- git2r::repository(ws_b)
  cat("B ahead before pull:", ns$.datom_git_ahead(ws_b), "\n")

  # The pull B's re-run would make (R3.7).
  r <- try(ns$.datom_git_pull(ws_b), silent = TRUE)
  cat("pull raised:", inherits(r, "try-error"), "\n")
  st <- git2r::status(repo_b)
  cat("conflicted:", paste(unlist(st$unstaged$conflicted), collapse = " "), "\n")
  merge_head <- file.path(ws_b, ".git", "MERGE_HEAD")
  cat("MERGE_HEAD present after conflict:", file.exists(merge_head), "\n")

  # Stand-in for the rebuild: union of both sides' artifact rows, written whole.
  theirs <- jsonlite::fromJSON(paste(system2("git", c("-C", ws_b, "show",
    "MERGE_HEAD:.datom/manifest.json"), stdout = TRUE), collapse = "\n"),
    simplifyVector = FALSE)
  ours <- jsonlite::fromJSON(paste(system2("git", c("-C", ws_b, "show",
    "HEAD:.datom/manifest.json"), stdout = TRUE), collapse = "\n"),
    simplifyVector = FALSE)
  merged <- theirs
  merged$artifacts <- utils::modifyList(theirs$artifacts, ours$artifacts)
  jsonlite::write_json(merged, file.path(ws_b, ".datom", "manifest.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  git2r::add(repo_b, ".datom/manifest.json")
  st2 <- git2r::status(repo_b)
  cat("conflicted after add:", length(unlist(st2$unstaged$conflicted)), "\n")
  sig <- ns$.datom_git_signature(repo_b)
  c2 <- try(git2r::commit(repo_b, message = "Merge (manifest rebuilt)",
                          author = sig, committer = sig), silent = TRUE)
  if (inherits(c2, "try-error")) {
    cat("commit FAILED:", conditionMessage(attr(c2, "condition")), "\n")
    return(invisible(NULL))
  }
  parents <- git2r::parents(c2)
  cat("merge commit parents:", length(parents), "\n")
  cat("MERGE_HEAD present after commit:", file.exists(merge_head), "\n")

  p <- try(ns$.datom_git_push(ws_b), silent = TRUE)
  cat("push raised:", inherits(p, "try-error"),
      if (inherits(p, "try-error")) conditionMessage(attr(p, "condition")) else "", "\n")

  ws_c <- file.path(home, "c")
  conn_c <- suppressMessages(datom_clone(ws_c, store = store))
  m <- jsonlite::read_json(file.path(ws_c, ".datom", "manifest.json"))
  cat("fresh clone manifest artifacts:", paste(sort(names(m$artifacts)), collapse = " "), "\n")
  cat("fresh clone has lb/metadata.json:", file.exists(file.path(ws_c, "lb", "metadata.json")),
      "| ae/metadata.json:", file.exists(file.path(ws_c, "ae", "metadata.json")), "\n")
  invisible(NULL)
}
main()
