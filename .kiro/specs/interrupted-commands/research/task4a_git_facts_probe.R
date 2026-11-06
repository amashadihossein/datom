# Throwaway (task 4a, 2026-11-04): git2r facts task 4a's code relies on.
#
# 1. Unstaging chosen paths with git2r::reset(repo, path = ) (design section 10,
#    item 1): a staged edit of a tracked file, and a staged new file.
# 2. git2r::merge(commit_on_success = FALSE) of a local branch with nothing
#    conflicted: does it leave MERGE_HEAD, like `git merge --no-commit`?
# 3. The error text of a push git rejects because the remote holds commits the
#    clone lacks, with and without an upstream branch.
# 4. git2r::stash(untracked = TRUE) and stash_pop() set aside and restore an
#    untracked file and a modified one.
#
# Rerun from the repo root:
#   Rscript .kiro/specs/interrupted-commands/research/task4a_git_facts_probe.R
main <- function() {
  suppressMessages(library(git2r))
  cat("git2r", as.character(packageVersion("git2r")), "\n")
  root <- tempfile("task4a-git-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  ident <- function(r) config(r, user.name = "t", user.email = "t@t")
  st <- function(r) {
    s <- status(r, staged = TRUE, unstaged = TRUE, untracked = TRUE)
    paste0("staged{", paste(names(s$staged), unlist(s$staged), collapse = ","),
           "} unstaged{", paste(names(s$unstaged), unlist(s$unstaged), collapse = ","),
           "} untracked{", paste(unlist(s$untracked), collapse = ","), "}")
  }

  bare <- file.path(root, "remote.git"); dir.create(bare); init(bare, bare = TRUE)
  a <- file.path(root, "a"); clone(bare, a, progress = FALSE)
  ra <- repository(a); ident(ra)
  dir.create(file.path(a, "dm"))
  writeLines("v1", file.path(a, "dm", "metadata.json"))
  add(ra, "dm/metadata.json"); commit(ra, "c1")
  push(ra, "origin", paste0("refs/heads/", repository_head(ra)$name))
  branch_set_upstream(repository_head(ra), paste0("origin/", repository_head(ra)$name))

  # --- 1. Unstaging --------------------------------------------------------------
  writeLines("v2", file.path(a, "dm", "metadata.json"))
  dir.create(file.path(a, "lb"))
  writeLines("new", file.path(a, "lb", "metadata.json"))
  add(ra, c("dm/metadata.json", "lb/metadata.json"))
  cat("\n1. after staging an edit and a new file:", st(ra), "\n")
  reset(ra, path = c("dm/metadata.json", "lb/metadata.json"))
  cat("   after reset(path =):", st(ra), "\n")
  checkout(ra, path = "dm/metadata.json", force = TRUE)
  cat("   after checkout(force) of dm:", st(ra),
      " dm content:", readLines(file.path(a, "dm", "metadata.json")), "\n")
  unlink(file.path(a, "lb"), recursive = TRUE)

  # --- 2. merge(commit_on_success = FALSE) of a local branch --------------------
  main_branch <- repository_head(ra)$name
  checkout(ra, branch = "feature", create = TRUE)
  writeLines("feature", file.path(a, "app.R")); add(ra, "app.R"); commit(ra, "feature")
  checkout(ra, branch = main_branch)
  res <- merge(ra, "feature", commit_on_success = FALSE, merger = default_signature(ra))
  cat("\n2. merge(feature, commit_on_success = FALSE): fast_forward =", format(res$fast_forward),
      " conflicts =", format(res$conflicts),
      " MERGE_HEAD:", file.exists(file.path(a, ".git", "MERGE_HEAD")), " status:", st(ra), "\n")
  writeLines("x", file.path(a, "other.R")); add(ra, "other.R"); commit(ra, "own")
  checkout(ra, branch = "feature")
  writeLines("feature2", file.path(a, "app2.R")); add(ra, "app2.R"); commit(ra, "feature2")
  checkout(ra, branch = main_branch)
  res <- merge(ra, "feature", commit_on_success = FALSE, merger = default_signature(ra))
  cat("   diverged: fast_forward =", format(res$fast_forward),
      " conflicts =", format(res$conflicts),
      " MERGE_HEAD:", file.exists(file.path(a, ".git", "MERGE_HEAD")), " status:", st(ra), "\n")
  if (file.exists(file.path(a, ".git", "MERGE_MSG"))) {
    cat("   MERGE_MSG first line:", readLines(file.path(a, ".git", "MERGE_MSG"))[1], "\n")
  }
  system2("git", c("-C", a, "merge", "--abort"), stdout = FALSE, stderr = FALSE)
  system2("git", c("-C", a, "reset", "-q", "--hard", paste0("origin/", main_branch)))

  # --- 3. A rejected push ---------------------------------------------------------
  b <- file.path(root, "b"); clone(bare, b, branch = main_branch, progress = FALSE)
  rb <- repository(b); ident(rb)
  writeLines("b", file.path(b, "b.R")); add(rb, "b.R"); commit(rb, "b")
  push(rb, "origin", paste0("refs/heads/", main_branch))
  writeLines("a", file.path(a, "a.R")); add(ra, "a.R"); commit(ra, "a own")
  e <- tryCatch(push(ra, "origin", paste0("refs/heads/", main_branch)), error = function(e) e)
  cat("\n3. push of a clone behind, before a fetch:", conditionMessage(e), "\n")
  fetch(ra, "origin", verbose = FALSE)
  e <- tryCatch(push(ra, "origin", paste0("refs/heads/", main_branch)), error = function(e) e)
  cat("   push of a clone behind, after a fetch (upstream set):", conditionMessage(e), "\n")
  branch_set_upstream(repository_head(ra), NULL)
  cat("   upstream now:", format(is.null(branch_get_upstream(repository_head(ra)))), "\n")
  e <- tryCatch(push(ra, "origin", paste0("refs/heads/", main_branch)), error = function(e) e)
  cat("   push of the same clone with no upstream:", conditionMessage(e), "\n")
  branch_set_upstream(repository_head(ra), paste0("origin/", main_branch))
  cat("   set upstream back to origin/", main_branch, ": ",
      format(!is.null(branch_get_upstream(repository_head(ra)))), "\n", sep = "")

  # --- 4. stash -u and pop through git2r ----------------------------------------
  writeLines("local edit", file.path(a, "a.R"))
  writeLines("untracked", file.path(a, "u.R"))
  cat("\n4. before stash:", st(ra), "\n")
  stash(ra, message = "probe", untracked = TRUE, stasher = default_signature(ra))
  cat("   after stash(untracked = TRUE):", st(ra), "\n")
  stash_pop(ra)
  cat("   after stash_pop():", st(ra), "\n")
}
main()
