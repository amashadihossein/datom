# Throwaway: is "the merge brings in the remote branch" a structural test that
# needs no marker? For each kind of merge in progress, compare MERGE_HEAD with
# the upstream tip as last fetched (equal, or the tip descends from it).
main <- function() {
  root <- tempfile("merge-source-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  git <- function(dir, ...) suppressWarnings(system2("git", c("-C", dir, ...), stdout = TRUE, stderr = TRUE))
  ident <- function(r) git2r::config(r, user.name = "t", user.email = "t@t")
  from_remote <- function(r, dir) {
    mh <- git2r::lookup(r, readLines(file.path(dir, ".git", "MERGE_HEAD"))[1])
    tip <- git2r::lookup(r, git2r::branch_target(git2r::branch_get_upstream(git2r::repository_head(r))))
    identical(git2r::sha(mh), git2r::sha(tip)) || git2r::descendant_of(tip, mh)
  }

  bare <- file.path(root, "remote.git")
  dir.create(bare); git2r::init(bare, bare = TRUE)
  a <- file.path(root, "a"); git2r::clone(bare, a)
  ra <- git2r::repository(a); ident(ra)
  writeLines("base", file.path(a, "manifest.json"))
  git2r::add(ra, "manifest.json"); git2r::commit(ra, "base")
  git(a, "push", "-q", "origin", "HEAD:refs/heads/main")
  git(a, "branch", "-q", "--set-upstream-to=origin/main")
  b <- file.path(root, "b"); git2r::clone(bare, b, branch = "main")
  rb <- git2r::repository(b); ident(rb)
  diverge <- function(tag) {
    writeLines(paste("theirs", tag), file.path(b, "manifest.json"))
    git2r::add(rb, "manifest.json"); git2r::commit(rb, paste("theirs", tag))
    git(b, "push", "-q", "origin", "HEAD:main")
    writeLines(paste("ours", tag), file.path(a, "manifest.json"))
    git2r::add(ra, "manifest.json"); git2r::commit(ra, paste("ours", tag))
  }
  reset <- function() { git(a, "merge", "--abort"); git(a, "reset", "-q", "--hard", "origin/main") }

  diverge("1")
  git2r::fetch(ra, "origin")
  up <- git2r::branch_get_upstream(git2r::repository_head(ra))
  git2r::merge(ra, up$name, merger = git2r::default_signature(ra))
  cat("datom's pull (git2r merge of upstream), conflicted:", from_remote(ra, a), "\n")
  writeLines("later", file.path(b, "other.json"))
  git2r::add(rb, "other.json"); git2r::commit(rb, "later")
  git(b, "push", "-q", "origin", "HEAD:main")
  git(a, "fetch", "-q")
  cat("  same, after a later fetch moved the upstream tip:", from_remote(ra, a), "\n")
  reset()

  diverge("2")
  git(a, "pull", "--no-rebase", "-q")
  cat("user's git pull, conflicted:", from_remote(ra, a), "\n")
  reset()

  git(a, "checkout", "-q", "-b", "feature")
  writeLines("feature", file.path(a, "app.R"))
  git2r::add(ra, "app.R"); git2r::commit(ra, "feature work")
  git(a, "checkout", "-q", "main")
  git(a, "merge", "--no-commit", "--no-ff", "feature")
  cat("user's git merge --no-commit feature:", from_remote(ra, a), "\n")
  git(a, "merge", "--abort")

  other <- file.path(root, "other.git")
  dir.create(other); git2r::init(other, bare = TRUE)
  git(a, "push", "-q", other, "feature:main")
  git(a, "remote", "add", "other", other)
  git(a, "fetch", "-q", "other")
  git(a, "merge", "--no-commit", "--no-ff", "other/main")
  cat("user's merge of another remote's branch:", from_remote(ra, a), "\n")
}
main()
