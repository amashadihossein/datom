# datom_init_repo() broken at each of its steps (#155, requirements R6).
#
# Before its push init rolls back everything it created, the bare remote
# included, so the same call re-run starts afresh. After the push it cannot
# roll back (the remote may be a GitHub repo, or one the caller supplied), so
# its stop names the repair, which uploads the manifest. A real project: a
# folder git remote and a local store, as in helper-interrupt.R.

# An empty place for one init: the store, the clone's path and the remote's.
ii_place <- function(env = parent.frame()) {
  skip_if_no_git2r()
  root <- withr::local_tempdir(.local_envir = env)
  storage <- file.path(root, "storage")
  list(
    root = root,
    storage = storage,
    repo = file.path(root, "repo"),
    remote = file.path(root, "remote.git"),
    store = datom_store(
      data = datom_store_local(storage),
      data_repo_url = file.path(root, "remote.git")
    )
  )
}

ii_init <- function(p) {
  suppressMessages(datom_init_repo(p$repo, "P", p$store, create_repo = TRUE))
}

ii_stored_manifest <- function(p) {
  file.path(p$storage, "datom", ".metadata", "manifest.json")
}

ii_msg <- function(err) gsub("\\s+", " ", cli::ansi_strip(conditionMessage(err)))

# The bare remote: its HEAD and every file under it.
ii_remote_state <- function(p) {
  repo <- git2r::repository(p$remote)
  files <- fs::dir_ls(p$remote, recurse = TRUE, all = TRUE, type = "file")
  list(
    head = as.character(git2r::revparse_single(repo, "HEAD")$sha),
    files = unname(tools::md5sum(sort(as.character(files))))
  )
}

# A reader with no clone, which sees only what storage publishes.
ii_reader_lists <- function(p) {
  reader <- suppressMessages(datom_get_conn(
    store = datom_store(data = datom_store_local(p$storage)),
    project_name = "P"
  ))
  suppressMessages(datom_list(reader))
}


# === before the push: rolled back, and the same call re-run succeeds =============

test_that("datom_init_repo() broken at its commit or its push leaves nothing, and the same call re-run succeeds (R6.3)", {
  for (step in c("commit", "push")) {
    p <- ii_place()
    err <- local({
      local_break_at(step)
      expect_error(ii_init(p), class = "datom_test_break")
    })
    expect_false(dir.exists(p$repo), label = step)
    expect_false(dir.exists(p$remote), label = step)
    expect_false(file.exists(ii_stored_manifest(p)), label = step)

    expect_no_error(ii_init(p))
    expect_true(file.exists(ii_stored_manifest(p)), label = step)
    expect_identical(nrow(ii_reader_lists(p)), 0L, label = step)
  }
})


# === after the push: the stop names the repair, which finishes ======================

test_that("datom_init_repo() broken at its manifest upload names the repair, and the repair finishes (R6.1)", {
  p <- ii_place()
  err <- local({
    local_break_at("manifest")
    expect_error(ii_init(p), class = "datom_init_manifest_failed")
  })
  msg <- ii_msg(err)
  expect_match(msg, "simulated break at manifest", fixed = TRUE)
  expect_match(msg, paste0("conn <- datom_get_conn(\"", fs::path_abs(p$repo), "\", store)"),
               fixed = TRUE)
  expect_match(msg, "datom_validate(conn, fix = TRUE)", fixed = TRUE)
  expect_match(msg, "again refuses", fixed = TRUE)
  expect_true(file.exists(file.path(p$repo, ".datom", "project.yaml")))
  expect_true(dir.exists(p$remote))
  expect_false(file.exists(ii_stored_manifest(p)))

  # The way out, as the message spells it.
  store <- p$store
  conn <- suppressMessages(datom_get_conn(p$repo, store))
  suppressWarnings(suppressMessages(datom_validate(conn, fix = TRUE)))

  expect_true(file.exists(ii_stored_manifest(p)))
  expect_identical(nrow(ii_reader_lists(p)), 0L)
  checked <- suppressMessages(datom_validate(conn))
  expect_true(checked$valid)
})

test_that("datom_init_repo() whose storage connection fails after the push names the repair too (R6.1)", {
  p <- ii_place()
  err <- local({
    local_mocked_bindings(.datom_build_init_conn = function(project_name, store_component,
                                                            path, ...) {
      if (!is.null(path)) stop("credentials rejected")
      stop("unexpected namespace-check build")
    })
    expect_error(ii_init(p), class = "datom_init_manifest_failed")
  })
  msg <- ii_msg(err)
  expect_match(msg, "credentials rejected", fixed = TRUE)
  expect_match(msg, "datom_validate(conn, fix = TRUE)", fixed = TRUE)
  expect_true(dir.exists(p$remote))
})

ii_expect_folder_taken <- function(err, p) {
  msg <- ii_msg(err)
  expect_match(msg, "A datom repository already exists", fixed = TRUE)
  expect_match(msg, paste0("conn <- datom_get_conn(\"", fs::path_abs(p$repo), "\", store)"),
               fixed = TRUE)
  expect_match(msg, "the same store you passed", fixed = TRUE)
  expect_match(msg, "datom_validate(conn, fix = TRUE)", fixed = TRUE)
  expect_match(msg, "and the git remote's repository", fixed = TRUE)
  # The same refusal meets a re-run in a healthy project, so starting over is
  # labelled for what it costs.
  expect_match(msg, "To abandon this project and start over, which loses its history",
               fixed = TRUE)
}

test_that("datom_init_repo() re-run after a break at its manifest upload refuses with both ways out, changing nothing, whatever the remote (R6.2)", {
  p <- ii_place()
  local({
    local_break_at("manifest")
    expect_error(ii_init(p), class = "datom_init_manifest_failed")
  })
  before <- snapshot_clone(p$repo)
  remote_before <- ii_remote_state(p)

  # A folder remote created by the call, as the first call made it.
  err <- expect_error(ii_init(p), class = "datom_init_folder_taken")
  ii_expect_folder_taken(err, p)

  # The same folder remote, now passed as an existing one.
  err <- expect_error(
    suppressMessages(datom_init_repo(p$repo, "P", p$store)),
    class = "datom_init_folder_taken"
  )
  ii_expect_folder_taken(err, p)

  # A GitHub address supplied by the caller, and one the call would create.
  # Neither reaches GitHub: the folder is refused first.
  github <- datom_store(
    data = datom_store_local(p$storage),
    github_pat = "ghp_fake",
    data_repo_url = "https://github.com/someone/p.git",
    validate = FALSE
  )
  github_create <- datom_store(
    data = datom_store_local(p$storage), github_pat = "ghp_fake", validate = FALSE
  )
  created <- FALSE
  local_mocked_bindings(.datom_create_github_repo = function(...) {
    created <<- TRUE
    "https://github.com/someone/p.git"
  })
  err <- expect_error(
    suppressMessages(datom_init_repo(p$repo, "P", github)),
    class = "datom_init_folder_taken"
  )
  ii_expect_folder_taken(err, p)
  err <- expect_error(
    suppressMessages(datom_init_repo(p$repo, "P", github_create, create_repo = TRUE)),
    class = "datom_init_folder_taken"
  )
  ii_expect_folder_taken(err, p)
  expect_false(created)

  expect_identical(snapshot_clone(p$repo), before)
  expect_identical(ii_remote_state(p), remote_before)
  expect_false(file.exists(ii_stored_manifest(p)))
})
