# --- Helper: create a temporary git repo with config + initial commit ---------
create_test_repo <- function(name = "Test User", email = "test@example.com",
                            env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  repo <- git2r::init(dir)
  git2r::config(repo, user.name = name, user.email = email)

  # Need at least one commit for branch operations
  writeLines("init", fs::path(dir, "README.md"))
  git2r::add(repo, "README.md")
  git2r::commit(repo, "Initial commit")

  list(path = dir, repo = repo)
}

# Alias — all test repos have an initial commit
create_test_repo_with_commit <- create_test_repo
# =============================================================================
# .datom_check_git2r()
# =============================================================================

test_that(".datom_check_git2r succeeds when git2r is available", {
  # git2r is installed in dev environment

  expect_true(.datom_check_git2r())
  expect_invisible(.datom_check_git2r())
})

test_that(".datom_check_git2r aborts when git2r is missing", {
  local_mocked_bindings(
    requireNamespace = function(...) FALSE,
    .package = "base"
  )
  expect_error(.datom_check_git2r(), "git2r.*required")
})


# =============================================================================
# .datom_git_author()
# =============================================================================

test_that(".datom_git_author returns name and email from local config", {
  info <- create_test_repo(name = "Jane Doe", email = "jane@lab.org")
  result <- .datom_git_author(info$path)

  expect_type(result, "list")
  expect_equal(result$name, "Jane Doe")
  expect_equal(result$email, "jane@lab.org")
})

test_that(".datom_git_author aborts on non-git directory", {
  dir <- withr::local_tempdir()
  expect_error(.datom_git_author(dir), "Not a git repository")
})

test_that(".datom_git_author aborts when user.name missing", {
  dir <- withr::local_tempdir()
  repo <- git2r::init(dir)
  # Set only email, not name
  git2r::config(repo, user.email = "only@email.com")

  # Need a commit — use system git to bypass git2r's own validation
  writeLines("init", fs::path(dir, "README.md"))
  system2("git", c("-C", dir, "add", "README.md"), stdout = FALSE, stderr = FALSE)
  withr::with_envvar(
    c(GIT_AUTHOR_NAME = "tmp", GIT_COMMITTER_NAME = "tmp"),
    system2("git", c("-C", dir, "commit", "-m", "init"), stdout = FALSE, stderr = FALSE)
  )

  # Mock global config to ensure it doesn't fall back
  local_mocked_bindings(
    config = function(...) list(local = list(user.email = "only@email.com"), global = list()),
    .package = "git2r"
  )

  expect_error(.datom_git_author(dir), "user\\.name.*not set")
})

test_that(".datom_git_author aborts when user.email missing", {
  dir <- withr::local_tempdir()
  repo <- git2r::init(dir)
  git2r::config(repo, user.name = "Only Name")

  writeLines("init", fs::path(dir, "README.md"))
  system2("git", c("-C", dir, "add", "README.md"), stdout = FALSE, stderr = FALSE)
  withr::with_envvar(
    c(GIT_AUTHOR_EMAIL = "tmp@tmp.com", GIT_COMMITTER_EMAIL = "tmp@tmp.com"),
    system2("git", c("-C", dir, "commit", "-m", "init"), stdout = FALSE, stderr = FALSE)
  )

  local_mocked_bindings(
    config = function(...) list(local = list(user.name = "Only Name"), global = list()),
    .package = "git2r"
  )

  expect_error(.datom_git_author(dir), "user\\.email.*not set")
})

test_that(".datom_git_author aborts when both name and email missing", {
  dir <- withr::local_tempdir()
  repo <- git2r::init(dir)

  writeLines("init", fs::path(dir, "README.md"))
  system2("git", c("-C", dir, "add", "README.md"), stdout = FALSE, stderr = FALSE)
  withr::with_envvar(
    c(GIT_AUTHOR_NAME = "tmp", GIT_COMMITTER_NAME = "tmp",
      GIT_AUTHOR_EMAIL = "t@t.com", GIT_COMMITTER_EMAIL = "t@t.com"),
    system2("git", c("-C", dir, "commit", "-m", "init"), stdout = FALSE, stderr = FALSE)
  )

  local_mocked_bindings(
    config = function(...) list(local = list(), global = list()),
    .package = "git2r"
  )

  expect_error(.datom_git_author(dir), "user\\.name.*user\\.email")
})

test_that(".datom_git_author falls back to global config", {
  dir <- withr::local_tempdir()
  repo <- git2r::init(dir)

  writeLines("init", fs::path(dir, "README.md"))
  system2("git", c("-C", dir, "add", "README.md"), stdout = FALSE, stderr = FALSE)
  withr::with_envvar(
    c(GIT_AUTHOR_NAME = "tmp", GIT_COMMITTER_NAME = "tmp",
      GIT_AUTHOR_EMAIL = "t@t.com", GIT_COMMITTER_EMAIL = "t@t.com"),
    system2("git", c("-C", dir, "commit", "-m", "init"), stdout = FALSE, stderr = FALSE)
  )

  # Mock: no local config, values in global
  local_mocked_bindings(
    config = function(...) list(
      local = list(),
      global = list(user.name = "Global User", user.email = "global@cfg.com")
    ),
    .package = "git2r"
  )

  result <- .datom_git_author(dir)
  expect_equal(result$name, "Global User")
  expect_equal(result$email, "global@cfg.com")
})


# =============================================================================
# .datom_git_branch()
# =============================================================================

test_that(".datom_git_branch returns branch name", {
  info <- create_test_repo()
  result <- .datom_git_branch(info$path)

  expect_type(result, "character")
  expect_length(result, 1)
  # Default branch is "main" or "master" depending on git config
  expect_true(result %in% c("main", "master"))
})

test_that(".datom_git_branch aborts on non-git directory", {
  dir <- withr::local_tempdir()
  expect_error(.datom_git_branch(dir), "Not a git repository")
})

test_that(".datom_git_branch aborts on repo with no commits", {
  dir <- withr::local_tempdir()
  git2r::init(dir)
  expect_error(.datom_git_branch(dir), "no commits")
})

test_that(".datom_git_branch returns correct name after branch switch", {
  info <- create_test_repo()
  git2r::branch_create(git2r::last_commit(info$repo), name = "feature-x")
  git2r::checkout(info$repo, branch = "feature-x")

  expect_equal(.datom_git_branch(info$path), "feature-x")
})

test_that(".datom_git_branch aborts on detached HEAD", {
  info <- create_test_repo()

  # Create a second commit
  writeLines("v2", fs::path(info$path, "README.md"))
  git2r::add(info$repo, "README.md")
  commit2 <- git2r::commit(info$repo, "Second commit")

  # Detach HEAD by checking out the first commit
  first_commit <- git2r::commits(info$repo)[[2]]
  git2r::checkout(first_commit)

  expect_error(.datom_git_branch(info$path), "detached")
})


# =============================================================================
# .datom_git_commit()
# =============================================================================

test_that(".datom_git_commit stages and commits files, returns SHA", {
  info <- create_test_repo_with_commit()
  writeLines("data", file.path(info$path, "table.json"))

  sha <- .datom_git_commit(info$path, "table.json", "Add table")

  expect_type(sha, "character")
  expect_equal(nchar(sha), 40L)

  # Verify commit is in log
  log <- git2r::commits(info$repo)
  expect_equal(log[[1]]$sha, sha)
  expect_equal(log[[1]]$message, "Add table")
})

test_that(".datom_git_commit handles multiple files", {
  info <- create_test_repo_with_commit()
  writeLines("a", file.path(info$path, "file_a.txt"))
  writeLines("b", file.path(info$path, "file_b.txt"))

  sha <- .datom_git_commit(info$path, c("file_a.txt", "file_b.txt"), "Add two files")

  expect_type(sha, "character")
  # Verify nothing left unstaged/untracked for these files
  status <- git2r::status(info$repo)
  untracked <- unlist(status$untracked, use.names = FALSE)
  expect_false("file_a.txt" %in% untracked)
  expect_false("file_b.txt" %in% untracked)
})

test_that(".datom_git_commit handles files in subdirectories", {
  info <- create_test_repo_with_commit()
  fs::dir_create(file.path(info$path, "customers"))
  writeLines("{}", file.path(info$path, "customers", "metadata.json"))

  sha <- .datom_git_commit(info$path, "customers/metadata.json", "Add metadata")

  expect_type(sha, "character")
  expect_equal(nchar(sha), 40L)
})

test_that(".datom_git_commit errors on empty files vector", {
  info <- create_test_repo_with_commit()
  expect_error(.datom_git_commit(info$path, character(0), "Nothing"), "No files")
})

test_that(".datom_git_commit errors on non-existent files", {
  info <- create_test_repo_with_commit()
  expect_error(
    .datom_git_commit(info$path, "ghost.txt", "Nope"),
    "do not exist"
  )
})

test_that(".datom_git_commit returns HEAD SHA when files are unchanged", {
  info <- create_test_repo_with_commit()
  # README.md is already committed and unchanged — should return HEAD SHA
  result <- .datom_git_commit(info$path, "README.md", "No change")
  head_sha <- as.character(git2r::revparse_single(info$repo, "HEAD")$sha)
  expect_equal(result, head_sha)
})

test_that(".datom_git_commit errors on non-git directory", {
  dir <- withr::local_tempdir()
  writeLines("x", file.path(dir, "file.txt"))
  expect_error(.datom_git_commit(dir, "file.txt", "Nope"), "Not a git repository")
})

test_that(".datom_git_commit uses author from git config", {
  info <- create_test_repo_with_commit()
  git2r::config(info$repo, user.name = "Committer X", user.email = "cx@lab.org")
  writeLines("new", file.path(info$path, "new.txt"))

  sha <- .datom_git_commit(info$path, "new.txt", "New file")

  commit_obj <- git2r::lookup(info$repo, sha)
  expect_equal(commit_obj$author$name, "Committer X")
  expect_equal(commit_obj$author$email, "cx@lab.org")
})

test_that(".datom_git_commit can update an existing file", {
  info <- create_test_repo_with_commit()
  # Modify README.md (already tracked)
  writeLines("updated", file.path(info$path, "README.md"))

  sha <- .datom_git_commit(info$path, "README.md", "Update readme")

  expect_type(sha, "character")
  log <- git2r::commits(info$repo)
  expect_equal(log[[1]]$message, "Update readme")
})


# =============================================================================
# .datom_git_push()
# =============================================================================

# --- Helper: create a repo pair (working + bare remote) -----------------------
create_repo_with_remote <- function(name = "Test User", email = "test@example.com",
                                    env = parent.frame()) {
  # Create a bare repo to act as "remote"
  bare_dir <- withr::local_tempdir(.local_envir = env)
  bare_repo <- git2r::init(bare_dir, bare = TRUE)

  # Create working repo
  work_dir <- withr::local_tempdir(.local_envir = env)
  work_repo <- git2r::init(work_dir)
  git2r::config(work_repo, user.name = name, user.email = email)

  # Initial commit in working repo
  writeLines("init", fs::path(work_dir, "README.md"))
  git2r::add(work_repo, "README.md")
  git2r::commit(work_repo, "Initial commit")

  # Add bare repo as remote "origin"
  git2r::remote_add(work_repo, name = "origin", url = bare_dir)

  # Push initial commit to set up tracking
  git2r::push(work_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(work_repo)$name}"),
              set_upstream = TRUE)

  list(
    work_path = work_dir,
    work_repo = work_repo,
    bare_path = bare_dir,
    bare_repo = bare_repo
  )
}


test_that(".datom_git_push pushes commits to remote", {
  info <- create_repo_with_remote()

  # Make a new commit in working repo
  writeLines("new data", fs::path(info$work_path, "data.json"))
  git2r::add(info$work_repo, "data.json")
  git2r::commit(info$work_repo, "Add data")

  result <- .datom_git_push(info$work_path)

  expect_true(result)
  expect_invisible(.datom_git_push(info$work_path))


  # Verify bare remote received the commit
  bare_log <- git2r::commits(info$bare_repo)
  expect_equal(bare_log[[1]]$message, "Add data")
})

test_that(".datom_git_push is idempotent (no-op when nothing to push)", {
  info <- create_repo_with_remote()

  # Nothing new to push — should succeed silently
  expect_no_error(.datom_git_push(info$work_path))
})

test_that(".datom_git_push fetches and merges upstream changes", {
  info <- create_repo_with_remote()

  # Simulate another user by cloning the bare repo
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  # Other user commits + pushes
  writeLines("other work", fs::path(other_dir, "other.txt"))
  git2r::add(other_repo, "other.txt")
  git2r::commit(other_repo, "Other user commit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Original user makes a non-conflicting commit
  writeLines("my work", fs::path(info$work_path, "mine.txt"))
  git2r::add(info$work_repo, "mine.txt")
  git2r::commit(info$work_repo, "My commit")

  # Push should fetch, merge, then push
  expect_no_error(.datom_git_push(info$work_path))

  # Both commits should be in remote
  bare_log <- git2r::commits(info$bare_repo)
  messages <- purrr::map_chr(bare_log, ~ .x$message)
  expect_true("Other user commit" %in% messages)
  expect_true("My commit" %in% messages)
})

test_that(".datom_git_push aborts on merge conflict", {
  info <- create_repo_with_remote()

  # Simulate another user modifying README.md
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  writeLines("other version", fs::path(other_dir, "README.md"))
  git2r::add(other_repo, "README.md")
  git2r::commit(other_repo, "Other edit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Original user modifies the same file differently
  writeLines("my version", fs::path(info$work_path, "README.md"))
  git2r::add(info$work_repo, "README.md")
  git2r::commit(info$work_repo, "My conflicting edit")

  # Should abort with conflict message
  expect_error(.datom_git_push(info$work_path), "conflict|merge", ignore.case = TRUE)
})

test_that(".datom_git_push aborts when no remote configured", {
  info <- create_test_repo()

  expect_error(.datom_git_push(info$path), "No remote")
})

test_that(".datom_git_push aborts on non-git directory", {
  dir <- withr::local_tempdir()
  expect_error(.datom_git_push(dir), "Not a git repository")
})

test_that(".datom_git_push returns invisible TRUE", {
  info <- create_repo_with_remote()

  writeLines("more", fs::path(info$work_path, "extra.txt"))
  git2r::add(info$work_repo, "extra.txt")
  git2r::commit(info$work_repo, "Extra commit")

  result <- .datom_git_push(info$work_path)
  expect_true(result)
})


# =============================================================================
# .datom_git_credentials()
# =============================================================================

test_that(".datom_git_credentials returns cred_user_pass for HTTPS with PAT", {
  withr::local_envvar(GITHUB_PAT = "ghp_testtoken123", GITHUB_TOKEN = NA)

  cred <- .datom_git_credentials("https://github.com/org/repo.git")
  expect_s3_class(cred, "cred_user_pass")
})

test_that(".datom_git_credentials falls back to GITHUB_TOKEN", {
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = "ghp_fallback456")

  cred <- .datom_git_credentials("https://github.com/org/repo.git")
  expect_s3_class(cred, "cred_user_pass")
})

test_that(".datom_git_credentials returns NULL for SSH remotes", {
  withr::local_envvar(GITHUB_PAT = "ghp_testtoken123")

  cred <- .datom_git_credentials("git@github.com:org/repo.git")
  expect_null(cred)
})

test_that(".datom_git_credentials returns NULL when no PAT is set", {
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)

  cred <- .datom_git_credentials("https://github.com/org/repo.git")
  expect_null(cred)
})

test_that(".datom_git_credentials handles empty PAT strings", {
  withr::local_envvar(GITHUB_PAT = "", GITHUB_TOKEN = "")

  cred <- .datom_git_credentials("https://github.com/org/repo.git")
  expect_null(cred)
})


# =============================================================================
# .datom_git_pull()
# =============================================================================

test_that(".datom_git_pull fetches and merges upstream changes", {
  info <- create_repo_with_remote()

  # Simulate another user by cloning the bare repo
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  # Other user commits + pushes
  writeLines("upstream work", fs::path(other_dir, "upstream.txt"))
  git2r::add(other_repo, "upstream.txt")
  git2r::commit(other_repo, "Upstream commit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Pull should bring in the upstream commit
  result <- .datom_git_pull(info$work_path)

  expect_true(result)
  expect_true(fs::file_exists(fs::path(info$work_path, "upstream.txt")))

  log <- git2r::commits(info$work_repo)
  messages <- purrr::map_chr(log, ~ .x$message)
  expect_true("Upstream commit" %in% messages)
})

test_that(".datom_git_pull is no-op when already up to date", {
  info <- create_repo_with_remote()

  # Nothing upstream — should succeed silently
  expect_no_error(.datom_git_pull(info$work_path))
  expect_true(.datom_git_pull(info$work_path))
})

test_that(".datom_git_pull aborts on merge conflict", {
  info <- create_repo_with_remote()

  # Simulate another user modifying README.md
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  writeLines("other version of readme", fs::path(other_dir, "README.md"))
  git2r::add(other_repo, "README.md")
  git2r::commit(other_repo, "Other edit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Local user modifies the same file differently
  writeLines("my conflicting version", fs::path(info$work_path, "README.md"))
  git2r::add(info$work_repo, "README.md")
  git2r::commit(info$work_repo, "My conflicting edit")

  expect_error(.datom_git_pull(info$work_path), "conflict|merge", ignore.case = TRUE)
})

test_that(".datom_git_pull aborts when no remote configured", {
  info <- create_test_repo()

  expect_error(.datom_git_pull(info$path), "No remote")
})

test_that(".datom_git_pull aborts on non-git directory", {
  dir <- withr::local_tempdir()
  expect_error(.datom_git_pull(dir), "Not a git repository")
})

test_that(".datom_git_pull returns invisible TRUE", {
  info <- create_repo_with_remote()
  result <- .datom_git_pull(info$work_path)
  expect_true(result)
  expect_invisible(.datom_git_pull(info$work_path))
})


# =============================================================================
# .datom_check_git_current()
# =============================================================================

test_that(".datom_check_git_current passes when up to date", {
  info <- create_repo_with_remote()

  # No upstream changes — should pass silently
  result <- .datom_check_git_current(info$work_path)
  expect_true(result)
  expect_invisible(.datom_check_git_current(info$work_path))
})

test_that(".datom_check_git_current aborts when behind remote", {
  info <- create_repo_with_remote()

  # Simulate another user pushing a commit
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")

  writeLines("new upstream data", fs::path(other_dir, "new_file.txt"))
  git2r::add(other_repo, "new_file.txt")
  git2r::commit(other_repo, "New upstream commit")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  # Local repo is now behind — should abort
  expect_error(.datom_check_git_current(info$work_path), "behind remote")
})

test_that(".datom_check_git_current error message suggests datom_pull", {
  info <- create_repo_with_remote()

  # Push upstream commit
  other_dir <- withr::local_tempdir()
  other_repo <- git2r::clone(info$bare_path, other_dir)
  git2r::config(other_repo, user.name = "Other User", user.email = "other@lab.org")
  writeLines("data", fs::path(other_dir, "upstream.txt"))
  git2r::add(other_repo, "upstream.txt")
  git2r::commit(other_repo, "Upstream")
  git2r::push(other_repo, name = "origin",
              refspec = glue::glue("refs/heads/{git2r::repository_head(other_repo)$name}"))

  expect_error(.datom_check_git_current(info$work_path), "datom_pull")
})

test_that(".datom_check_git_current passes when no remote configured", {
  info <- create_test_repo()

  # No remote = can't be behind → passes
  result <- .datom_check_git_current(info$path)
  expect_true(result)
})

test_that(".datom_check_git_current passes when no upstream branch", {
  info <- create_repo_with_remote()

  # Create a new local-only branch with no upstream
  git2r::branch_create(git2r::last_commit(info$work_repo), "feature-branch")
  git2r::checkout(info$work_repo, "feature-branch")

  result <- .datom_check_git_current(info$work_path)
  expect_true(result)
})

test_that(".datom_check_git_current passes when ahead of remote", {
  info <- create_repo_with_remote()

  # Make a local commit that hasn't been pushed
  writeLines("local only", fs::path(info$work_path, "local.txt"))
  git2r::add(info$work_repo, "local.txt")
  git2r::commit(info$work_repo, "Local commit")

  # Ahead, not behind — should pass
  result <- .datom_check_git_current(info$work_path)
  expect_true(result)
})

test_that(".datom_check_git_current tolerates network errors gracefully", {
  info <- create_test_repo()

  # Add a fake remote that will fail on fetch
  git2r::remote_add(info$repo, name = "origin", url = "https://invalid.example.com/repo.git")

  # Network error should warn but not abort
  expect_no_error(.datom_check_git_current(info$path))
})

test_that(".datom_check_git_current aborts on non-git directory", {
  dir <- withr::local_tempdir()
  expect_error(.datom_check_git_current(dir), "Not a git repository")
})
