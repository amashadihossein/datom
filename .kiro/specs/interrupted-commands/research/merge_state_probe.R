# Throwaway: what git2r reports for a merge in progress, before and after the
# user resolves one of two conflicted files with `git checkout --theirs` + `git add`.
main <- function() {
  root <- tempfile("merge-state-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  git <- function(dir, ...) system2("git", c("-C", dir, ...), stdout = TRUE, stderr = TRUE)
  ident <- function(r) git2r::config(r, user.name = "t", user.email = "t@t")

  bare <- file.path(root, "remote.git")
  dir.create(bare); git2r::init(bare, bare = TRUE)
  a <- file.path(root, "a")
  git2r::clone(bare, a)
  ra <- git2r::repository(a); ident(ra)
  writeLines("base", file.path(a, "x.json"))
  writeLines("base", file.path(a, "manifest.json"))
  writeLines("base", file.path(a, "y.json"))
  git2r::add(ra, c("x.json", "manifest.json", "y.json"))
  git2r::commit(ra, "base")
  git(a, "push", "-q", "origin", "HEAD:refs/heads/main")
  git(a, "branch", "-q", "--set-upstream-to=origin/main")

  b <- file.path(root, "b")
  git2r::clone(bare, b, branch = "main")
  rb <- git2r::repository(b); ident(rb)

  # Colleague (b): changes x and the manifest, pushes.
  writeLines("theirs", file.path(b, "x.json"))
  writeLines("theirs", file.path(b, "manifest.json"))
  git2r::add(rb, c("x.json", "manifest.json"))
  git2r::commit(rb, "theirs")
  git(b, "push", "-q", "origin", "HEAD:main")

  # You (a): change x, y and the manifest, commit, then merge.
  writeLines("ours", file.path(a, "x.json"))
  writeLines("ours", file.path(a, "manifest.json"))
  writeLines("ours", file.path(a, "y.json"))
  git2r::add(ra, c("x.json", "manifest.json", "y.json"))
  git2r::commit(ra, "ours")
  git2r::fetch(ra, "origin")
  m <- git2r::merge(ra, "origin/main")
  cat("merge conflicts:", isTRUE(m$conflicts), "\n")

  gitdir <- file.path(a, ".git")
  show <- function(label) {
    st <- git2r::status(ra)
    cat("\n--", label, "--\n")
    cat("MERGE_HEAD present:", file.exists(file.path(gitdir, "MERGE_HEAD")), "\n")
    cat("git2r::status names:", paste(names(st), collapse = ", "), "\n")
    for (nm in names(st)) {
      v <- unlist(st[[nm]])
      if (length(v)) cat(" ", nm, ":", paste(names(v), v, sep = "=", collapse = "; "), "\n")
    }
    cat("git CLI unmerged:", paste(git(a, "diff", "--name-only", "--diff-filter=U"), collapse = ", "), "\n")
  }
  show("after the merge")

  git(a, "checkout", "--theirs", "x.json")
  git(a, "add", "x.json")
  show("after `git checkout --theirs x.json` + `git add x.json`")

  # The reviewer's recovery would also keep the remote manifest and commit:
  git(a, "checkout", "--theirs", "manifest.json")
  git(a, "add", "manifest.json")
  git(a, "commit", "-q", "-m", "merge")
  cat("\n-- after keeping the remote manifest and `git commit` --\n")
  cat("y.json:", readLines(file.path(a, "y.json")), " manifest.json:", readLines(file.path(a, "manifest.json")), "\n")
}
main()
