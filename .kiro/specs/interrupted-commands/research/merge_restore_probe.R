# Throwaway: in a conflicted merge, does `git checkout MERGE_HEAD -- <files>` take the
# remote copy of a conflicted file AND a cleanly merged one, where --theirs fails on the latter?
main <- function() {
  root <- tempfile("merge-restore-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  git <- function(dir, ...) system2("git", c("-C", dir, ...), stdout = TRUE, stderr = TRUE)
  ident <- function(r) git2r::config(r, user.name = "t", user.email = "t@t")

  bare <- file.path(root, "remote.git"); dir.create(bare); git2r::init(bare, bare = TRUE)
  a <- file.path(root, "a"); git2r::clone(bare, a); ra <- git2r::repository(a); ident(ra)
  dir.create(file.path(a, "dm"))
  writeLines("base", file.path(a, "dm", "version_history.json"))
  writeLines("base", file.path(a, "dm", "metadata.json"))
  git2r::add(ra, c("dm/version_history.json", "dm/metadata.json"))
  git2r::commit(ra, "base")
  git(a, "push", "-q", "origin", "HEAD:refs/heads/main")
  git(a, "branch", "-q", "--set-upstream-to=origin/main")

  b <- file.path(root, "b"); git2r::clone(bare, b, branch = "main"); rb <- git2r::repository(b); ident(rb)
  writeLines("theirs", file.path(b, "dm", "version_history.json"))   # history: both change
  git2r::add(rb, "dm/version_history.json"); git2r::commit(rb, "theirs")
  git(b, "push", "-q", "origin", "HEAD:main")

  writeLines("ours", file.path(a, "dm", "version_history.json"))
  writeLines("ours", file.path(a, "dm", "metadata.json"))             # metadata: only ours changes
  git2r::add(ra, c("dm/version_history.json", "dm/metadata.json")); git2r::commit(ra, "ours")
  git2r::fetch(ra, "origin")
  m <- git2r::merge(ra, "origin/main")
  cat("conflicts:", isTRUE(m$conflicts), " unmerged:", git(a, "diff", "--name-only", "--diff-filter=U"), "\n")

  cat("--theirs on the clean file:", git(a, "checkout", "--theirs", "dm/metadata.json"), "\n")
  out <- git(a, "checkout", "MERGE_HEAD", "--", "dm/metadata.json", "dm/version_history.json")
  cat("checkout MERGE_HEAD -- both:", if (length(out)) out else "ok", "\n")
  cat("after: metadata =", readLines(file.path(a, "dm", "metadata.json")),
      " history =", readLines(file.path(a, "dm", "version_history.json")),
      " still unmerged:", length(git(a, "diff", "--name-only", "--diff-filter=U")), "\n")
  git(a, "commit", "-q", "-m", "merge")
  cat("MERGE_HEAD after commit:", file.exists(file.path(a, ".git", "MERGE_HEAD")), "\n")
}
main()
