# Identity-contract integration tests (Feature: datom-cv1)
#
# The S1-S6 scenarios of Requirement 9, exercised end-to-end on the local
# backend (Requirement 16.5). Unlike the unit tests in test-read-write.R --
# which mock `.datom_has_changes()` to isolate one branch -- these tests mock
# NOTHING in the datom stack. Each fixture builds a real git repo with a real
# local bare remote (so commit/push/pull are genuine) plus a real
# `backend = "local"` store, so change classification, parquet upload,
# `metadata.json` / `version_history.json`, and read-back all run for real.
# That is the point: S1-S6 are behaviors of the *composition*, not of any one
# function.
#
# Everything stays on the filesystem, so the suite-wide fail-closed network
# guard in setup.R (Requirement 16.6) is never tripped and no test here needs
# `DATOM_ALLOW_REAL_NETWORK`.


# --- fixture ------------------------------------------------------------------

#' Build a real developer project: git repo + bare remote + local store.
#'
#' Returns the conn plus the paths, and registers cleanup on `env`. The only
#' departure from a production project is that the conn is assembled directly
#' (via `mock_datom_conn()` + field overrides, the prevailing suite idiom)
#' rather than through `datom_init_repo()` / `datom_get_conn()`, which would
#' drag in project.yaml + ref resolution that these scenarios do not exercise.
#' `gov_root` stays NULL, so `.datom_check_ref_current()` skips (legacy conn).
local_identity_project <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)

  repo_dir <- fs::path(root, "repo")
  store_dir <- fs::path(root, "store")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, store_dir, bare_dir))

  git2r::init(bare_dir, bare = TRUE)
  repo <- git2r::init(repo_dir)
  git2r::config(repo, user.name = "Identity Test", user.email = "id@test.com")
  writeLines("init", fs::path(repo_dir, "README.md"))
  git2r::add(repo, "README.md")
  git2r::commit(repo, "Initial commit")
  git2r::remote_add(repo, name = "origin", url = as.character(bare_dir))
  git2r::push(repo, name = "origin", refspec = "refs/heads/master",
              set_upstream = TRUE)

  conn <- mock_datom_conn(list(), root = as.character(store_dir),
                          prefix = "proj")
  conn$backend <- "local"
  conn$role <- "developer"
  conn$path <- as.character(repo_dir)

  input_dir <- fs::path(repo_dir, "input_files")
  fs::dir_create(input_dir)

  list(
    conn = conn,
    repo = repo,
    repo_dir = repo_dir,
    store_dir = store_dir,
    input_dir = input_dir
  )
}

# Current git HEAD sha of the fixture repo (to prove a no-op made no commit).
identity_head_sha <- function(fx) {
  as.character(git2r::revparse_single(git2r::repository(fx$repo_dir), "HEAD")$sha)
}

# Stored parquet objects, via the package's own key resolution so the test does
# not hard-code the `{prefix}/datom/` storage layout.
identity_stored_parquet <- function(fx, name) {
  dir <- fs::path_dir(.datom_local_path(fx$conn, paste0(name, "/x.parquet")))
  if (!fs::dir_exists(dir)) return(character())
  as.character(fs::dir_ls(dir, type = "file", glob = "*.parquet"))
}

# Local git copies of the metadata the write path just produced.
identity_metadata <- function(fx, name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "metadata.json"))
}

identity_history <- function(fx, name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "version_history.json"))
}

# Write a CSV whose bytes differ by quoting but whose parsed content does not.
identity_write_csv <- function(path, data, quote = TRUE) {
  utils::write.csv(data, path, row.names = FALSE, quote = quote)
}


# --- S1: unchanged input is skipped before any parse (Requirement 9.1) --------

test_that("Feature: datom-cv1, S1 -- an unchanged input is skipped before parsing", {
  fx <- local_identity_project()
  df <- data.frame(id = 1:3, grp = c("a", "b", "c"), stringsAsFactors = FALSE)
  identity_write_csv(fs::path(fx$input_dir, "dm.csv"), df)

  # First sync: genuinely new, so it imports and writes.
  first <- suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))
  expect_identical(first$result, "success")

  # Re-scan with the file untouched: the manifest reports it unchanged.
  manifest <- suppressMessages(datom_sync_manifest(fx$conn))
  expect_identical(manifest$status, "unchanged")

  # Sync again with the importer replaced by a tripwire. Zero calls is the
  # assertion: the skip happens on the manifest status, before any parse.
  import_calls <- 0L
  mockery::stub(datom_sync, ".datom_import_file", function(file, format) {
    import_calls <<- import_calls + 1L
    stop("`.datom_import_file()` must not be called for an unchanged input.")
  })

  head_before <- identity_head_sha(fx)
  result <- suppressMessages(datom_sync(fx$conn, manifest))

  expect_identical(import_calls, 0L)
  expect_identical(result$result, "skipped")
  expect_true(is.na(result$error))
  # A no-op leaves git and storage untouched.
  expect_identical(identity_head_sha(fx), head_before)
  expect_length(identity_stored_parquet(fx, "dm"), 1L)
})

test_that("Feature: datom-cv1, S1 -- an unchanged sibling is skipped while a changed one syncs", {
  fx <- local_identity_project()
  keep <- data.frame(id = 1:2, v = c("x", "y"), stringsAsFactors = FALSE)
  move <- data.frame(id = 1:2, v = c("p", "q"), stringsAsFactors = FALSE)
  identity_write_csv(fs::path(fx$input_dir, "keep.csv"), keep)
  identity_write_csv(fs::path(fx$input_dir, "move.csv"), move)

  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))

  # Only move.csv changes -- content too, so it is a real full write.
  identity_write_csv(
    fs::path(fx$input_dir, "move.csv"),
    data.frame(id = 1:3, v = c("p", "q", "r"), stringsAsFactors = FALSE)
  )

  manifest <- suppressMessages(datom_sync_manifest(fx$conn))
  expect_identical(manifest$status[manifest$name == "keep"], "unchanged")
  expect_identical(manifest$status[manifest$name == "move"], "changed")

  imported <- character()
  real_import <- .datom_import_file
  mockery::stub(datom_sync, ".datom_import_file", function(file, format) {
    imported <<- c(imported, fs::path_file(file))
    real_import(file, format)
  })

  result <- suppressMessages(datom_sync(fx$conn, manifest))

  # The unchanged sibling never reaches the importer; the changed one does.
  expect_identical(imported, "move.csv")
  expect_identical(result$result[result$name == "keep"], "skipped")
  expect_identical(result$result[result$name == "move"], "success")
})


# --- S2 / S5 / S6: change classification (Requirements 9.2, 9.5, 9.6) --------

test_that("Feature: datom-cv1, S2 -- bytes and content both change: full write at the new data_sha", {
  fx <- local_identity_project()
  csv <- fs::path(fx$input_dir, "dm.csv")
  v1 <- data.frame(id = 1:3, v = c("a", "b", "c"), stringsAsFactors = FALSE)
  identity_write_csv(csv, v1)

  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))
  meta1 <- identity_metadata(fx, "dm")
  stored1 <- identity_stored_parquet(fx, "dm")
  expect_identical(fs::path_file(stored1), paste0(meta1$data_sha, ".parquet"))

  # A real content change (an extra row) -- bytes and canonical content both move.
  identity_write_csv(
    csv,
    rbind(v1, data.frame(id = 4L, v = "d", stringsAsFactors = FALSE))
  )

  manifest <- suppressMessages(datom_sync_manifest(fx$conn))
  expect_identical(manifest$status, "changed")
  result <- suppressMessages(datom_sync(fx$conn, manifest))
  expect_identical(result$result, "success")

  meta2 <- identity_metadata(fx, "dm")
  expect_false(identical(meta2$data_sha, meta1$data_sha))
  expect_identical(meta2$nrow, 4L)

  # The new content is addressed by its own data_sha, alongside the old object.
  stored2 <- identity_stored_parquet(fx, "dm")
  expect_length(stored2, 2L)
  expect_setequal(
    fs::path_file(stored2),
    paste0(c(meta1$data_sha, meta2$data_sha), ".parquet")
  )

  # A new version was recorded, newest first, keyed by the new metadata_sha.
  history <- identity_history(fx, "dm")
  expect_length(history, 2L)
  expect_identical(history[[1]]$version, .datom_compute_metadata_sha(meta2))
  expect_identical(history[[1]]$data_sha, meta2$data_sha)
  expect_identical(history[[2]]$data_sha, meta1$data_sha)
})

test_that("Feature: datom-cv1, S5 -- a derived first write is full, data_sha-addressed, with no original_file_sha", {
  fx <- local_identity_project()
  df <- data.frame(
    id = 1:4,
    score = c(1.5, 2.5, 3.5, 4.5),
    grp = c("a", "a", "b", "b"),
    stringsAsFactors = FALSE
  )

  result <- suppressMessages(datom_write(fx$conn, data = df, name = "derived_tbl"))

  expect_identical(result$action, "full")
  expect_identical(result$data_sha, .datom_canonical_hash(df)$data_sha)

  meta <- identity_metadata(fx, "derived_tbl")
  expect_identical(meta$table_type, "derived")
  expect_identical(meta$hash_algo, "datom-cv1")
  # Absent from the object entirely on the derived path -- not present-with-NULL.
  expect_false("original_file_sha" %in% names(meta))

  # Addressed by data_sha in storage.
  stored <- identity_stored_parquet(fx, "derived_tbl")
  expect_identical(fs::path_file(stored), paste0(result$data_sha, ".parquet"))

  # And the version_history entry carries no original_file_sha either.
  history <- identity_history(fx, "derived_tbl")
  expect_length(history, 1L)
  expect_false("original_file_sha" %in% names(history[[1]]))
})

test_that("Feature: datom-cv1, S6 -- an identical re-derive is a no-op: no commit, upload, or history entry", {
  fx <- local_identity_project()

  base <- data.frame(id = 1:3, v = c("a", "b", "c"), stringsAsFactors = FALSE)
  suppressMessages(datom_write(fx$conn, data = base, name = "base"))
  base_version <- identity_history(fx, "base")[[1]]$version
  parent <- datom_parent(fx$conn, "base", base_version)

  agg <- data.frame(grp = c("a", "b"), n = c(2L, 1L), stringsAsFactors = FALSE)
  first <- suppressMessages(
    datom_write(fx$conn, data = agg, name = "agg", parents = list(parent))
  )
  expect_identical(first$action, "full")

  head_before <- identity_head_sha(fx)
  history_before <- identity_history(fx, "agg")
  stored_before <- identity_stored_parquet(fx, "agg")
  # Backdate the stored object so a re-upload (file_copy overwrite) is visible
  # as a changed mtime -- proof of "no upload" that needs no storage mock.
  backdated <- as.POSIXct("2001-01-01 00:00:00", tz = "UTC")
  fs::file_touch(stored_before, modification_time = backdated)

  # Same data, same parents, current unchanged -> none.
  second <- suppressMessages(
    datom_write(fx$conn, data = agg, name = "agg", parents = list(parent))
  )

  expect_identical(second$action, "none")
  expect_identical(second$data_sha, first$data_sha)
  expect_identical(second$metadata_sha, first$metadata_sha)
  expect_null(second$commit_sha)

  # No commit, no history entry, no re-upload.
  expect_identical(identity_head_sha(fx), head_before)
  expect_length(identity_history(fx, "agg"), length(history_before))
  expect_identical(identity_stored_parquet(fx, "agg"), stored_before)
  expect_equal(
    as.numeric(fs::file_info(stored_before)$modification_time),
    as.numeric(backdated)
  )
})
