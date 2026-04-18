# Tests for repository validation
# Phase 1, Chunk 4

# Helper: scaffold a minimal valid datom repo structure inside a temp dir
scaffold_datom_repo <- function(path,
                               git = TRUE,
                               project_yaml = TRUE,
                               dispatch_json = TRUE,
                               manifest_json = TRUE,
                               renv = TRUE) {
  if (git) fs::dir_create(fs::path(path, ".git"))
  if (project_yaml) {
    fs::dir_create(fs::path(path, ".datom"))
    fs::file_create(fs::path(path, ".datom", "project.yaml"))
  }
  if (dispatch_json) {
    fs::dir_create(fs::path(path, ".datom"))
    fs::file_create(fs::path(path, ".datom", "dispatch.json"))
  }
  if (manifest_json) {
    fs::dir_create(fs::path(path, ".datom"))
    fs::file_create(fs::path(path, ".datom", "manifest.json"))
  }
  if (renv) fs::dir_create(fs::path(path, "renv"))

  invisible(path)
}


# --- datom_repository_check() --------------------------------------------------

test_that("returns all TRUE for fully scaffolded repo", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd())
    dx <- datom_repository_check(getwd())

    expect_type(dx, "list")
    expect_named(dx, c("git_initialized", "datom_initialized", "datom_dispatch",
                        "datom_manifest", "renv_initialized"))
    purrr::walk(dx, ~ expect_true(.x))
  })
})

test_that("detects missing .git", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd(), git = FALSE)
    dx <- datom_repository_check(getwd())

    expect_false(dx$git_initialized)
    expect_true(dx$datom_initialized)
    expect_true(dx$datom_dispatch)
    expect_true(dx$datom_manifest)
    expect_true(dx$renv_initialized)
  })
})

test_that("detects missing project.yaml", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd(), project_yaml = FALSE)
    dx <- datom_repository_check(getwd())

    expect_true(dx$git_initialized)
    expect_false(dx$datom_initialized)
    expect_true(dx$datom_dispatch)
  })
})

test_that("detects missing dispatch.json", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd(), dispatch_json = FALSE)
    dx <- datom_repository_check(getwd())

    expect_true(dx$datom_initialized)
    expect_false(dx$datom_dispatch)
    expect_true(dx$datom_manifest)
  })
})

test_that("detects missing manifest.json", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd(), manifest_json = FALSE)
    dx <- datom_repository_check(getwd())

    expect_true(dx$datom_dispatch)
    expect_false(dx$datom_manifest)
    expect_true(dx$renv_initialized)
  })
})

test_that("detects missing renv", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd(), renv = FALSE)
    dx <- datom_repository_check(getwd())

    expect_true(dx$datom_manifest)
    expect_false(dx$renv_initialized)
  })
})

test_that("all FALSE for empty directory", {
  withr::with_tempdir({
    dx <- datom_repository_check(getwd())
    purrr::walk(dx, ~ expect_false(.x))
  })
})

test_that("resolves relative path", {
  withr::with_tempdir({
    fs::dir_create("sub")
    scaffold_datom_repo(fs::path(getwd(), "sub"))
    dx <- datom_repository_check("sub")

    purrr::walk(dx, ~ expect_true(.x))
  })
})


# --- is_valid_datom_repo() -----------------------------------------------------

test_that("returns TRUE for fully scaffolded repo", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd())
    expect_true(is_valid_datom_repo(getwd()))
  })
})

test_that("returns FALSE for empty directory", {
  withr::with_tempdir({
    expect_false(is_valid_datom_repo(getwd()))
  })
})

test_that("returns FALSE when any component is missing", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd(), git = FALSE)
    expect_false(is_valid_datom_repo(getwd()))
  })
})

# Selective checks: checks = "git"
test_that("checks = 'git' only evaluates git_initialized", {
  withr::with_tempdir({
    # Only .git present, no datom or renv
    fs::dir_create(".git")
    expect_true(is_valid_datom_repo(getwd(), checks = "git"))
  })
})

test_that("checks = 'git' returns FALSE when .git missing", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd(), git = FALSE)
    expect_false(is_valid_datom_repo(getwd(), checks = "git"))
  })
})

# Selective checks: checks = "datom"
test_that("checks = 'datom' only evaluates datom components", {
  withr::with_tempdir({
    # Only datom files, no git or renv
    fs::dir_create(".datom")
    fs::file_create(fs::path(".datom", "project.yaml"))
    fs::file_create(fs::path(".datom", "dispatch.json"))
    fs::file_create(fs::path(".datom", "manifest.json"))
    expect_true(is_valid_datom_repo(getwd(), checks = "datom"))
  })
})

test_that("checks = 'datom' returns FALSE when dispatch.json missing", {
  withr::with_tempdir({
    fs::dir_create(".datom")
    fs::file_create(fs::path(".datom", "project.yaml"))
    fs::file_create(fs::path(".datom", "manifest.json"))
    expect_false(is_valid_datom_repo(getwd(), checks = "datom"))
  })
})

# Selective checks: checks = "renv"
test_that("checks = 'renv' only evaluates renv_initialized", {
  withr::with_tempdir({
    fs::dir_create("renv")
    expect_true(is_valid_datom_repo(getwd(), checks = "renv"))
  })
})

test_that("checks = 'renv' returns FALSE when renv missing", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd(), renv = FALSE)
    expect_false(is_valid_datom_repo(getwd(), checks = "renv"))
  })
})

# Multiple selective checks
test_that("checks = c('git', 'datom') ignores renv", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd(), renv = FALSE)
    expect_true(is_valid_datom_repo(getwd(), checks = c("git", "datom")))
  })
})

# Verbose output
test_that("verbose = TRUE produces cli output for passing checks", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd())
    output <- capture.output(
      invisible(is_valid_datom_repo(getwd(), verbose = TRUE)),
      type = "message"
    )
    expect_true(any(grepl("git_initialized", output)))
    expect_true(any(grepl("datom_initialized", output)))
  })
})

test_that("verbose = TRUE produces cli output for failing checks", {
  withr::with_tempdir({
    output <- capture.output(
      invisible(is_valid_datom_repo(getwd(), verbose = TRUE)),
      type = "message"
    )
    expect_true(any(grepl("git_initialized", output)))
  })
})

test_that("verbose = FALSE produces no cli output", {
  withr::with_tempdir({
    scaffold_datom_repo(getwd())
    output <- capture.output(
      invisible(is_valid_datom_repo(getwd(), verbose = FALSE)),
      type = "message"
    )
    expect_length(output, 0)
  })
})


# --- datom_validate() ----------------------------------------------------------

test_that("datom_validate rejects non-datom_conn", {
  expect_error(datom_validate("not_conn"), "datom_conn")
})

test_that("datom_validate rejects reader role", {
  conn <- mock_datom_conn(list())
  conn$role <- "reader"
  conn$path <- "/tmp"
  expect_error(datom_validate(conn), "developer")
})

test_that("datom_validate rejects conn without path", {
  conn <- mock_datom_conn(list())
  conn$role <- "developer"
  conn$path <- NULL
  expect_error(datom_validate(conn), "local git repo")
})

test_that("datom_validate returns valid when everything consistent", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    # Repo-level files
    fs::dir_create(".datom")
    jsonlite::write_json(list(), ".datom/dispatch.json", auto_unbox = TRUE)
    jsonlite::write_json(list(), ".datom/manifest.json", auto_unbox = TRUE)

    # Table with metadata
    fs::dir_create("customers")
    jsonlite::write_json(
      list(data_sha = "abc123"),
      "customers/metadata.json", auto_unbox = TRUE
    )
    jsonlite::write_json(list(), "customers/version_history.json",
                         auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) TRUE
    )

    result <- datom_validate(conn)

    expect_true(result$valid)
    expect_true(all(result$repo_files$status == "ok"))
    expect_true(all(result$tables$status == "ok"))
    expect_false(result$fixed)
  })
})

test_that("datom_validate detects repo-level files missing from S3", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")
    jsonlite::write_json(list(), ".datom/dispatch.json", auto_unbox = TRUE)
    jsonlite::write_json(list(), ".datom/manifest.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) FALSE
    )

    result <- datom_validate(conn)

    expect_false(result$valid)
    expect_true(all(result$repo_files$status == "missing_s3"))
  })
})

test_that("datom_validate detects table metadata missing from S3", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")
    jsonlite::write_json(list(), ".datom/dispatch.json", auto_unbox = TRUE)

    fs::dir_create("orders")
    jsonlite::write_json(
      list(data_sha = "d123"),
      "orders/metadata.json", auto_unbox = TRUE
    )

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) {
        # Repo-level files exist, but table metadata does not
        grepl("^\\.metadata/", s3_key)
      }
    )

    result <- datom_validate(conn)

    expect_false(result$valid)
    expect_match(result$tables$status[1], "metadata_missing_s3")
  })
})

test_that("datom_validate detects data parquet missing from S3", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")

    fs::dir_create("tbl")
    jsonlite::write_json(
      list(data_sha = "abc"),
      "tbl/metadata.json", auto_unbox = TRUE
    )
    jsonlite::write_json(list(), "tbl/version_history.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) {
        # metadata files exist, but parquet does not
        !grepl("\\.parquet$", s3_key)
      }
    )

    result <- datom_validate(conn)

    expect_false(result$valid)
    expect_match(result$tables$status[1], "data_missing_s3")
  })
})

test_that("datom_validate ignores non-table directories", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")
    fs::dir_create("input_files")
    fs::dir_create("renv")
    fs::dir_create("R")
    fs::dir_create(".git")

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) TRUE
    )

    result <- datom_validate(conn)

    expect_true(result$valid)
    expect_equal(nrow(result$tables), 0)
  })
})

test_that("datom_validate returns correct structure", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) TRUE
    )

    result <- datom_validate(conn)

    expect_type(result, "list")
    expect_true("valid" %in% names(result))
    expect_true("repo_files" %in% names(result))
    expect_true("tables" %in% names(result))
    expect_true("fixed" %in% names(result))
    expect_s3_class(result$repo_files, "data.frame")
    expect_s3_class(result$tables, "data.frame")
  })
})

test_that("datom_validate with fix = TRUE calls datom_sync_dispatch on failure", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")
    jsonlite::write_json(list(), ".datom/dispatch.json", auto_unbox = TRUE)

    sync_called <- FALSE

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) FALSE,
      datom_sync_dispatch = function(conn, .confirm = TRUE) {
        sync_called <<- TRUE
        invisible(list(repo_files = character(), tables = list()))
      }
    )

    result <- datom_validate(conn, fix = TRUE)

    expect_true(sync_called)
    expect_true(result$fixed)
  })
})

test_that("datom_validate with fix = TRUE does not call sync when valid", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")

    sync_called <- FALSE

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) TRUE,
      datom_sync_dispatch = function(conn, .confirm = TRUE) {
        sync_called <<- TRUE
        invisible(list(repo_files = character(), tables = list()))
      }
    )

    result <- datom_validate(conn, fix = FALSE)

    expect_false(sync_called)
    expect_false(result$fixed)
  })
})

test_that("datom_validate handles multiple tables with mixed status", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")

    # Good table — everything on S3
    fs::dir_create("good_tbl")
    jsonlite::write_json(
      list(data_sha = "d1"),
      "good_tbl/metadata.json", auto_unbox = TRUE
    )
    jsonlite::write_json(list(), "good_tbl/version_history.json",
                         auto_unbox = TRUE)

    # Bad table — nothing on S3
    fs::dir_create("bad_tbl")
    jsonlite::write_json(
      list(data_sha = "d2"),
      "bad_tbl/metadata.json", auto_unbox = TRUE
    )

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) {
        grepl("good_tbl", s3_key)
      }
    )

    result <- datom_validate(conn)

    expect_false(result$valid)
    expect_equal(result$tables$status[result$tables$table == "good_tbl"], "ok")
    expect_match(result$tables$status[result$tables$table == "bad_tbl"], "missing_s3")
  })
})

test_that("datom_validate handles fix failure gracefully", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")
    jsonlite::write_json(list(), ".datom/dispatch.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) FALSE,
      datom_sync_dispatch = function(conn, .confirm = TRUE) {
        stop("Sync failed")
      }
    )

    result <- datom_validate(conn, fix = TRUE)

    expect_false(result$fixed)
    expect_false(result$valid)
  })
})

test_that("datom_validate skips repo files not present locally", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    # .datom dir exists but no files inside
    fs::dir_create(".datom")

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) TRUE
    )

    result <- datom_validate(conn)

    # No local repo files → empty repo_files df
    expect_equal(nrow(result$repo_files), 0)
    expect_true(result$valid)
  })
})


# --- .datom_validate_project_name() (Phase 7) ---------------------------------

test_that("datom_validate detects project_name mismatch in manifest", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$project_name <- "MY_PROJECT"

    fs::dir_create(".datom")
    jsonlite::write_json(
      list(project_name = "DIFFERENT_PROJECT"),
      ".datom/manifest.json", auto_unbox = TRUE
    )

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) TRUE
    )

    result <- datom_validate(conn)

    expect_false(result$valid)
  })
})

test_that("datom_validate passes when project_name matches", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()
    conn$project_name <- "MY_PROJECT"

    fs::dir_create(".datom")
    jsonlite::write_json(
      list(project_name = "MY_PROJECT"),
      ".datom/manifest.json", auto_unbox = TRUE
    )
    jsonlite::write_json(list(), ".datom/dispatch.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) TRUE
    )

    result <- datom_validate(conn)

    expect_true(result$valid)
  })
})

test_that("datom_validate tolerates pre-Phase-7 manifest without project_name", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")
    jsonlite::write_json(
      list(tables = list()),
      ".datom/manifest.json", auto_unbox = TRUE
    )
    jsonlite::write_json(list(), ".datom/dispatch.json", auto_unbox = TRUE)

    local_mocked_bindings(
      .datom_s3_exists = function(conn, s3_key) TRUE
    )

    result <- datom_validate(conn)

    # No project_name in manifest should be tolerated (not treated as mismatch)
    expect_true(result$valid)
  })
})

test_that(".datom_validate_project_name returns TRUE when no manifest exists", {
  withr::with_tempdir({
    conn <- mock_datom_conn(list())
    conn$role <- "developer"
    conn$path <- getwd()

    fs::dir_create(".datom")
    # No manifest.json file

    expect_true(.datom_validate_project_name(conn))
  })
})
