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
# .tbit_check_git2r()
# =============================================================================

test_that(".tbit_check_git2r succeeds when git2r is available", {
  # git2r is installed in dev environment

  expect_true(.tbit_check_git2r())
  expect_invisible(.tbit_check_git2r())
})

test_that(".tbit_check_git2r aborts when git2r is missing", {
  local_mocked_bindings(
    requireNamespace = function(...) FALSE,
    .package = "base"
  )
  expect_error(.tbit_check_git2r(), "git2r.*required")
})


# =============================================================================
# .tbit_git_author()
# =============================================================================

test_that(".tbit_git_author returns name and email from local config", {
  info <- create_test_repo(name = "Jane Doe", email = "jane@lab.org")
  result <- .tbit_git_author(info$path)

  expect_type(result, "list")
  expect_equal(result$name, "Jane Doe")
  expect_equal(result$email, "jane@lab.org")
})

test_that(".tbit_git_author aborts on non-git directory", {
  dir <- withr::local_tempdir()
  expect_error(.tbit_git_author(dir), "Not a git repository")
})

test_that(".tbit_git_author aborts when user.name missing", {
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

  expect_error(.tbit_git_author(dir), "user\\.name.*not set")
})

test_that(".tbit_git_author aborts when user.email missing", {
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

  expect_error(.tbit_git_author(dir), "user\\.email.*not set")
})

test_that(".tbit_git_author aborts when both name and email missing", {
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

  expect_error(.tbit_git_author(dir), "user\\.name.*user\\.email")
})

test_that(".tbit_git_author falls back to global config", {
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

  result <- .tbit_git_author(dir)
  expect_equal(result$name, "Global User")
  expect_equal(result$email, "global@cfg.com")
})


# =============================================================================
# .tbit_git_branch()
# =============================================================================

test_that(".tbit_git_branch returns branch name", {
  info <- create_test_repo()
  result <- .tbit_git_branch(info$path)

  expect_type(result, "character")
  expect_length(result, 1)
  # Default branch is "main" or "master" depending on git config
  expect_true(result %in% c("main", "master"))
})

test_that(".tbit_git_branch aborts on non-git directory", {
  dir <- withr::local_tempdir()
  expect_error(.tbit_git_branch(dir), "Not a git repository")
})

test_that(".tbit_git_branch aborts on repo with no commits", {
  dir <- withr::local_tempdir()
  git2r::init(dir)
  expect_error(.tbit_git_branch(dir), "no commits")
})

test_that(".tbit_git_branch returns correct name after branch switch", {
  info <- create_test_repo()
  git2r::branch_create(git2r::last_commit(info$repo), name = "feature-x")
  git2r::checkout(info$repo, branch = "feature-x")

  expect_equal(.tbit_git_branch(info$path), "feature-x")
})

test_that(".tbit_git_branch aborts on detached HEAD", {
  info <- create_test_repo()

  # Create a second commit
  writeLines("v2", fs::path(info$path, "README.md"))
  git2r::add(info$repo, "README.md")
  commit2 <- git2r::commit(info$repo, "Second commit")

  # Detach HEAD by checking out the first commit
  first_commit <- git2r::commits(info$repo)[[2]]
  git2r::checkout(first_commit)

  expect_error(.tbit_git_branch(info$path), "detached")
})


# =============================================================================
# .tbit_git_commit()
# =============================================================================

test_that(".tbit_git_commit stages and commits files, returns SHA", {
  info <- create_test_repo_with_commit()
  writeLines("data", file.path(info$path, "table.json"))

  sha <- .tbit_git_commit(info$path, "table.json", "Add table")

  expect_type(sha, "character")
  expect_equal(nchar(sha), 40L)

  # Verify commit is in log
  log <- git2r::commits(info$repo)
  expect_equal(log[[1]]$sha, sha)
  expect_equal(log[[1]]$message, "Add table")
})

test_that(".tbit_git_commit handles multiple files", {
  info <- create_test_repo_with_commit()
  writeLines("a", file.path(info$path, "file_a.txt"))
  writeLines("b", file.path(info$path, "file_b.txt"))

  sha <- .tbit_git_commit(info$path, c("file_a.txt", "file_b.txt"), "Add two files")

  expect_type(sha, "character")
  # Verify nothing left unstaged/untracked for these files
  status <- git2r::status(info$repo)
  untracked <- unlist(status$untracked, use.names = FALSE)
  expect_false("file_a.txt" %in% untracked)
  expect_false("file_b.txt" %in% untracked)
})

test_that(".tbit_git_commit handles files in subdirectories", {
  info <- create_test_repo_with_commit()
  fs::dir_create(file.path(info$path, "customers"))
  writeLines("{}", file.path(info$path, "customers", "metadata.json"))

  sha <- .tbit_git_commit(info$path, "customers/metadata.json", "Add metadata")

  expect_type(sha, "character")
  expect_equal(nchar(sha), 40L)
})

test_that(".tbit_git_commit errors on empty files vector", {
  info <- create_test_repo_with_commit()
  expect_error(.tbit_git_commit(info$path, character(0), "Nothing"), "No files")
})

test_that(".tbit_git_commit errors on non-existent files", {
  info <- create_test_repo_with_commit()
  expect_error(
    .tbit_git_commit(info$path, "ghost.txt", "Nope"),
    "do not exist"
  )
})

test_that(".tbit_git_commit errors when files are unchanged", {
  info <- create_test_repo_with_commit()
  # README.md is already committed and unchanged
  expect_error(
    .tbit_git_commit(info$path, "README.md", "No change"),
    "unchanged"
  )
})

test_that(".tbit_git_commit errors on non-git directory", {
  dir <- withr::local_tempdir()
  writeLines("x", file.path(dir, "file.txt"))
  expect_error(.tbit_git_commit(dir, "file.txt", "Nope"), "Not a git repository")
})

test_that(".tbit_git_commit uses author from git config", {
  info <- create_test_repo_with_commit()
  git2r::config(info$repo, user.name = "Committer X", user.email = "cx@lab.org")
  writeLines("new", file.path(info$path, "new.txt"))

  sha <- .tbit_git_commit(info$path, "new.txt", "New file")

  commit_obj <- git2r::lookup(info$repo, sha)
  expect_equal(commit_obj$author$name, "Committer X")
  expect_equal(commit_obj$author$email, "cx@lab.org")
})

test_that(".tbit_git_commit can update an existing file", {
  info <- create_test_repo_with_commit()
  # Modify README.md (already tracked)
  writeLines("updated", file.path(info$path, "README.md"))

  sha <- .tbit_git_commit(info$path, "README.md", "Update readme")

  expect_type(sha, "character")
  log <- git2r::commits(info$repo)
  expect_equal(log[[1]]$message, "Update readme")
})
