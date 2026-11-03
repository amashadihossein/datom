# Throwaway (design spot-check before task 4a, 2026-10-31): what git2r's merge
# does when the user's own uncommitted files are in the way of incoming commits,
# and whether the `git stash -u` recipe recovers.
#
# Part 1, git2r only: for each case, fetch then git2r::merge() the upstream, and
# report merge()'s fields, whether HEAD moved, and whether HEAD now contains the
# upstream tip (equal, or descends from it).
# Part 2, the recipe, with the git CLI and datom_pull(): a real datom project,
# two clones, the second behind with a file in the way; then
# `git stash -u`, datom_pull(conn), `git stash pop`, and what pop reports.
#
# Rerun from the repo root:
#   Rscript .kiro/specs/interrupted-commands/research/dirty_pull_probe.R
main <- function() {
  suppressMessages(library(git2r))
  git <- function(dir, ...) suppressWarnings(
    system2("git", c("-C", dir, ...), stdout = TRUE, stderr = TRUE)
  )
  contains <- function(repo, a_sha, b_sha) {
    identical(a_sha, b_sha) ||
      git2r::descendant_of(git2r::lookup(repo, a_sha), git2r::lookup(repo, b_sha))
  }

  # --- Part 1 -----------------------------------------------------------------
  setup <- function(root) {
    bare <- file.path(root, "r.git"); dir.create(bare); init(bare, bare = TRUE)
    a <- file.path(root, "a"); dir.create(a)
    ra <- clone(bare, a, progress = FALSE)
    config(ra, user.name = "A", user.email = "a@x")
    writeLines("v1", file.path(a, "app.R")); writeLines("n1", file.path(a, "notes.R"))
    add(ra, c("app.R", "notes.R")); commit(ra, "c1")
    git(a, "push", "-q", "origin", "HEAD:refs/heads/main")
    git(a, "branch", "-q", "--set-upstream-to=origin/main")
    b <- file.path(root, "b")
    rb <- clone(bare, b, branch = "main", progress = FALSE)
    config(rb, user.name = "B", user.email = "b@x")
    writeLines("v2", file.path(b, "app.R")); writeLines("b-new", file.path(b, "new.R"))
    add(rb, c("app.R", "new.R")); commit(rb, "b2")
    git(b, "push", "-q", "origin", "HEAD:main")
    list(a = a, ra = ra)
  }
  cases <- list(
    "control: nothing uncommitted" = function(a, ra) NULL,
    "modified file the remote did not change" = function(a, ra)
      writeLines("local", file.path(a, "notes.R")),
    "modified file the remote changed" = function(a, ra)
      writeLines("local", file.path(a, "app.R")),
    "STAGED edit to a file the remote changed" = function(a, ra) {
      writeLines("local", file.path(a, "app.R")); add(ra, "app.R")
    },
    "untracked file where the remote adds one" = function(a, ra)
      writeLines("local", file.path(a, "new.R")),
    "own commit (diverged) + modified file the remote changed" = function(a, ra) {
      writeLines("mine", file.path(a, "mine.R")); add(ra, "mine.R"); commit(ra, "a-own")
      writeLines("local", file.path(a, "app.R"))
    },
    "own commit (diverged), nothing in the way (control)" = function(a, ra) {
      writeLines("mine", file.path(a, "mine.R")); add(ra, "mine.R"); commit(ra, "a-own")
    }
  )
  cat("git2r", as.character(packageVersion("git2r")), "\n")
  for (label in names(cases)) {
    root <- tempfile("dirty-pull-"); dir.create(root)
    s <- setup(root)
    cases[[label]](s$a, s$ra)
    fetch(s$ra, "origin", verbose = FALSE)
    up <- branch_get_upstream(repository_head(s$ra))
    before <- revparse_single(s$ra, "HEAD")$sha
    res <- tryCatch(merge(s$ra, up$name, merger = default_signature(s$ra)),
                    error = function(e) e)
    after <- revparse_single(s$ra, "HEAD")$sha
    tip <- branch_target(branch_get_upstream(repository_head(s$ra)))
    cat("\n==", label, "\n")
    if (inherits(res, "error")) {
      cat("  merge() ERROR:", conditionMessage(res), "\n")
    } else {
      cat("  merge(): up_to_date =", format(res$up_to_date),
          " fast_forward =", format(res$fast_forward),
          " conflicts =", format(res$conflicts), " sha =", format(res$sha), "\n")
    }
    cat("  HEAD moved:", !identical(before, after),
        "  HEAD contains upstream tip:", contains(s$ra, after, tip),
        "  MERGE_HEAD:", file.exists(file.path(s$a, ".git", "MERGE_HEAD")), "\n")
    unlink(root, recursive = TRUE)
  }

  # --- Part 2: the recipe through datom ----------------------------------------
  repo_root <- local({
    f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
    if (length(f)) normalizePath(file.path(dirname(f), "..", "..", "..", "..")) else getwd()
  })
  suppressMessages(devtools::load_all(repo_root, quiet = TRUE))

  recipe <- function(label, in_the_way, include_untracked = TRUE) {
    root <- tempfile("dirty-recipe-"); dir.create(root)
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    remote <- file.path(root, "remote.git")
    store <- datom_store(data = datom_store_local(file.path(root, "storage")),
                         data_repo_url = remote)
    suppressMessages(datom_init_repo(file.path(root, "a"), "p", store, create_repo = TRUE))
    a <- file.path(root, "a")
    writeLines("v1", file.path(a, "app.R"))
    git(a, "add", "app.R"); git(a, "-c", "user.name=A", "-c", "user.email=a@x",
                                "commit", "-q", "-m", "app-v1")
    git(a, "push", "-q")
    b <- file.path(root, "b")
    git(root, "clone", "-q", remote, b)
    writeLines("v2 from b", file.path(b, "app.R")); writeLines("b-new", file.path(b, "new.R"))
    git(b, "add", "app.R", "new.R")
    git(b, "-c", "user.name=B", "-c", "user.email=b@x", "commit", "-q", "-m", "b2")
    git(b, "push", "-q")
    in_the_way(a)
    conn <- suppressMessages(datom_get_conn(a, store))
    cat("\n== recipe:", label, "\n")
    stash <- if (include_untracked) c("stash", "-u") else c("stash")
    cat("  git", paste(stash, collapse = " "), ":", git(a, stash)[1], "\n")
    pulled <- tryCatch({ suppressMessages(datom_pull(conn)); "ok" },
                       error = function(e) paste("ERROR", conditionMessage(e)))
    head <- git(a, "rev-parse", "HEAD"); tip <- git(a, "rev-parse", "@{u}")
    cat("  datom_pull():", pulled, "  caught up:", identical(head, tip), "\n")
    pop <- git(a, "stash", "pop")
    cat("  git stash pop:\n", paste0("    ", pop, collapse = "\n"), "\n")
    cat("  stash kept:", length(git(a, "stash", "list")) > 0L,
        "  app.R:", paste(readLines(file.path(a, "app.R")), collapse = " | "), "\n")
  }
  recipe("modified app.R (remote changed it)",
         function(a) writeLines("local", file.path(a, "app.R")))
  recipe("untracked new.R (remote adds it)",
         function(a) writeLines("local", file.path(a, "new.R")))
  recipe("untracked new.R, PLAIN git stash",
         function(a) writeLines("local", file.path(a, "new.R")),
         include_untracked = FALSE)
}
main()
