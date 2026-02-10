# Tests for repository validation
# Phase 1, Chunk 4

# Helper: scaffold a minimal valid tbit repo structure inside a temp dir
scaffold_tbit_repo <- function(path,
                               git = TRUE,
                               project_yaml = TRUE,
                               routing_json = TRUE,
                               manifest_json = TRUE,
                               renv = TRUE) {
  if (git) fs::dir_create(fs::path(path, ".git"))
  if (project_yaml) {
    fs::dir_create(fs::path(path, ".tbit"))
    fs::file_create(fs::path(path, ".tbit", "project.yaml"))
  }
  if (routing_json) {
    fs::dir_create(fs::path(path, ".tbit"))
    fs::file_create(fs::path(path, ".tbit", "routing.json"))
  }
  if (manifest_json) {
    fs::dir_create(fs::path(path, ".tbit"))
    fs::file_create(fs::path(path, ".tbit", "manifest.json"))
  }
  if (renv) fs::dir_create(fs::path(path, "renv"))

  invisible(path)
}


# --- tbit_repository_check() --------------------------------------------------

test_that("returns all TRUE for fully scaffolded repo", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd())
    dx <- tbit_repository_check(getwd())

    expect_type(dx, "list")
    expect_named(dx, c("git_initialized", "tbit_initialized", "tbit_routing",
                        "tbit_manifest", "renv_initialized"))
    purrr::walk(dx, ~ expect_true(.x))
  })
})

test_that("detects missing .git", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd(), git = FALSE)
    dx <- tbit_repository_check(getwd())

    expect_false(dx$git_initialized)
    expect_true(dx$tbit_initialized)
    expect_true(dx$tbit_routing)
    expect_true(dx$tbit_manifest)
    expect_true(dx$renv_initialized)
  })
})

test_that("detects missing project.yaml", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd(), project_yaml = FALSE)
    dx <- tbit_repository_check(getwd())

    expect_true(dx$git_initialized)
    expect_false(dx$tbit_initialized)
    expect_true(dx$tbit_routing)
  })
})

test_that("detects missing routing.json", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd(), routing_json = FALSE)
    dx <- tbit_repository_check(getwd())

    expect_true(dx$tbit_initialized)
    expect_false(dx$tbit_routing)
    expect_true(dx$tbit_manifest)
  })
})

test_that("detects missing manifest.json", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd(), manifest_json = FALSE)
    dx <- tbit_repository_check(getwd())

    expect_true(dx$tbit_routing)
    expect_false(dx$tbit_manifest)
    expect_true(dx$renv_initialized)
  })
})

test_that("detects missing renv", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd(), renv = FALSE)
    dx <- tbit_repository_check(getwd())

    expect_true(dx$tbit_manifest)
    expect_false(dx$renv_initialized)
  })
})

test_that("all FALSE for empty directory", {
  withr::with_tempdir({
    dx <- tbit_repository_check(getwd())
    purrr::walk(dx, ~ expect_false(.x))
  })
})

test_that("resolves relative path", {
  withr::with_tempdir({
    fs::dir_create("sub")
    scaffold_tbit_repo(fs::path(getwd(), "sub"))
    dx <- tbit_repository_check("sub")

    purrr::walk(dx, ~ expect_true(.x))
  })
})


# --- is_valid_tbit_repo() -----------------------------------------------------

test_that("returns TRUE for fully scaffolded repo", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd())
    expect_true(is_valid_tbit_repo(getwd()))
  })
})

test_that("returns FALSE for empty directory", {
  withr::with_tempdir({
    expect_false(is_valid_tbit_repo(getwd()))
  })
})

test_that("returns FALSE when any component is missing", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd(), git = FALSE)
    expect_false(is_valid_tbit_repo(getwd()))
  })
})

# Selective checks: checks = "git"
test_that("checks = 'git' only evaluates git_initialized", {
  withr::with_tempdir({
    # Only .git present, no tbit or renv
    fs::dir_create(".git")
    expect_true(is_valid_tbit_repo(getwd(), checks = "git"))
  })
})

test_that("checks = 'git' returns FALSE when .git missing", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd(), git = FALSE)
    expect_false(is_valid_tbit_repo(getwd(), checks = "git"))
  })
})

# Selective checks: checks = "tbit"
test_that("checks = 'tbit' only evaluates tbit components", {
  withr::with_tempdir({
    # Only tbit files, no git or renv
    fs::dir_create(".tbit")
    fs::file_create(fs::path(".tbit", "project.yaml"))
    fs::file_create(fs::path(".tbit", "routing.json"))
    fs::file_create(fs::path(".tbit", "manifest.json"))
    expect_true(is_valid_tbit_repo(getwd(), checks = "tbit"))
  })
})

test_that("checks = 'tbit' returns FALSE when routing.json missing", {
  withr::with_tempdir({
    fs::dir_create(".tbit")
    fs::file_create(fs::path(".tbit", "project.yaml"))
    fs::file_create(fs::path(".tbit", "manifest.json"))
    expect_false(is_valid_tbit_repo(getwd(), checks = "tbit"))
  })
})

# Selective checks: checks = "renv"
test_that("checks = 'renv' only evaluates renv_initialized", {
  withr::with_tempdir({
    fs::dir_create("renv")
    expect_true(is_valid_tbit_repo(getwd(), checks = "renv"))
  })
})

test_that("checks = 'renv' returns FALSE when renv missing", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd(), renv = FALSE)
    expect_false(is_valid_tbit_repo(getwd(), checks = "renv"))
  })
})

# Multiple selective checks
test_that("checks = c('git', 'tbit') ignores renv", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd(), renv = FALSE)
    expect_true(is_valid_tbit_repo(getwd(), checks = c("git", "tbit")))
  })
})

# Verbose output
test_that("verbose = TRUE produces cli output for passing checks", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd())
    output <- capture.output(
      invisible(is_valid_tbit_repo(getwd(), verbose = TRUE)),
      type = "message"
    )
    expect_true(any(grepl("git_initialized", output)))
    expect_true(any(grepl("tbit_initialized", output)))
  })
})

test_that("verbose = TRUE produces cli output for failing checks", {
  withr::with_tempdir({
    output <- capture.output(
      invisible(is_valid_tbit_repo(getwd(), verbose = TRUE)),
      type = "message"
    )
    expect_true(any(grepl("git_initialized", output)))
  })
})

test_that("verbose = FALSE produces no cli output", {
  withr::with_tempdir({
    scaffold_tbit_repo(getwd())
    output <- capture.output(
      invisible(is_valid_tbit_repo(getwd(), verbose = FALSE)),
      type = "message"
    )
    expect_length(output, 0)
  })
})
