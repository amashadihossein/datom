# The version-to-commit link: `commit_sha` on the stored version history.
#
# THREE FUNCTIONS UPLOAD `version_history.json`, and each one is a chance to
# erase the field, because the clone's copy can never carry it -- that file is
# inside the commit it would name. So there is one test per upload route, and
# each was confirmed to redden when ONLY that route's merge is removed:
#
#   the ordinary write     `.datom_push_metadata_s3()`   -> "the ordinary write ..."
#   the repair             `.datom_sync_one_artifact()`  -> "datom_validate(fix = TRUE) ..."
#   the metadata-only sync `.datom_sync_metadata()`      -> "the metadata-only route ..."
#
# A single "after a repair the field is still there" test satisfies none of the
# three: the ordinary write is the route that loses the field FIRST, on the second
# write of an artifact, with no repair involved.
#
# Nothing here mocks the datom stack. Real git repo, real bare remote, real local
# store, because every claim is about the composition of commit, push and upload.
# --- fixture ------------------------------------------------------------------
#' Real product project: git repo + bare remote + local store + product config.
#'
#' Same shape and same reason as `local_set_project()` in `test-write-set.R`;
#' duplicated because testthat does not share definitions between test files.
local_commit_link_project <- function(set_name = "product-a", env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  repo_dir <- fs::path(root, "repo")
  store_dir <- fs::path(root, "store")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, store_dir, bare_dir))
  git2r::init(bare_dir, bare = TRUE)
  repo <- git2r::init(repo_dir)
  git2r::config(repo, user.name = "Link Test", user.email = "link@test.com")
  writeLines("init", fs::path(repo_dir, "README.md"))
  git2r::add(repo, "README.md")
  git2r::commit(repo, "Initial commit")
  git2r::remote_add(repo, name = "origin", url = as.character(bare_dir))
  git2r::push(repo, name = "origin", refspec = test_head_refspec(repo),
              set_upstream = TRUE)
  conn <- mock_datom_conn(list(), root = as.character(store_dir),
                          prefix = "proj")
  conn$backend <- "local"
  conn$role <- "developer"
  conn$path <- as.character(repo_dir)
  conn$project_name <- "link-project"
  write_product_config(repo_dir, "link-project", set_name)
  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir,
       repo = repo, set_name = set_name)
}
vc_data <- function(n = 3L) {
  data.frame(id = seq_len(n), val = letters[seq_len(n)],
             stringsAsFactors = FALSE)
}
vc_write <- function(fx, name, n = 3L) {
  suppressMessages(datom_write(fx$conn, data = vc_data(n), name = name))
}
vc_head <- function(fx) {
  as.character(git2r::revparse_single(git2r::repository(fx$repo_dir), "HEAD")$sha)
}
vc_history_key <- function(name) {
  .datom_artifact_meta_key(name, "version_history")
}
vc_stored_history <- function(fx, name) {
  .datom_storage_read_json(fx$conn, vc_history_key(name))
}
vc_stored_history_text <- function(fx, name) {
  path <- .datom_local_path(fx$conn, vc_history_key(name))
  paste(readLines(path, warn = FALSE), collapse = "\n")
}
vc_clone_history <- function(fx, name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "version_history.json"))
}
# version -> commit_sha, `NA` where the entry carries none. Named so a test can
# ask about a specific version rather than about a row position.
vc_links <- function(history) {
  stats::setNames(
    vapply(history, function(e) e$commit_sha %||% NA_character_, character(1)),
    vapply(history, function(e) e$version, character(1))
  )
}
# What an older datom that has never heard of the field does through any of the
# three routes: upload the clone's copy verbatim. Nothing refuses it -- version
# history entries have no field vocabulary -- which is why the value has to be
# recomputable.
vc_strip_stored_links <- function(fx, name) {
  .datom_storage_write_json(
    fx$conn, vc_history_key(name), vc_clone_history(fx, name)
  )
  invisible(NULL)
}
# === door 1: the ordinary write ================================================
test_that("the ordinary write keeps `commit_sha` on every stored version, not just the newest", {
  fx <- local_commit_link_project()

  vc_write(fx, "dm", 3L)
  first_commit <- vc_head(fx)
  after_one <- vc_stored_history(fx, "dm")
  expect_length(after_one, 1L)
  v1 <- after_one[[1L]]$version
  expect_identical(after_one[[1L]]$commit_sha, first_commit)

  # The second write is where a naive implementation fails. It uploads the
  # clone's `version_history.json` WHOLESALE, and the clone's copy cannot carry
  # the field, so without a merge the first version's commit id is gone -- long
  # before any repair verb is involved.
  vc_write(fx, "dm", 5L)
  second_commit <- vc_head(fx)
  expect_false(identical(first_commit, second_commit))

  links <- vc_links(vc_stored_history(fx, "dm"))
  expect_length(links, 2L)
  v2 <- setdiff(names(links), v1)
  expect_identical(links[[v1]], first_commit)
  expect_identical(links[[v2]], second_commit)
})
test_that("reverting to earlier content leaves that version's recorded commit alone", {
  # The recorded commit is the one that FIRST produced a version. Reverting a
  # table to earlier content is the route that tests it: the version already
  # exists, so no history entry is appended, but a NEW commit is made and handed
  # to the uploader. Repointing the entry at it would make the field answer
  # "which commit last rewrote this" -- a different and much less useful question.
  fx <- local_commit_link_project()

  vc_write(fx, "dm", 3L)
  first_commit <- vc_head(fx)
  v1 <- vc_stored_history(fx, "dm")[[1L]]$version

  vc_write(fx, "dm", 5L)
  vc_write(fx, "dm", 3L)
  revert_commit <- vc_head(fx)
  expect_false(identical(revert_commit, first_commit))

  links <- vc_links(vc_stored_history(fx, "dm"))
  expect_length(links, 2L)
  expect_identical(links[[v1]], first_commit)
})
test_that("the clone's version history never gains `commit_sha`", {
  fx <- local_commit_link_project()
  vc_write(fx, "dm", 3L)
  vc_write(fx, "dm", 5L)

  # The field is added on the way to storage and the tracked file is left as
  # committed. Two separate claims: the file on disk has no such key, and the
  # write left nothing uncommitted behind it.
  clone <- vc_clone_history(fx, "dm")
  expect_length(clone, 2L)
  expect_true(all(vapply(clone, function(e) is.null(e$commit_sha), logical(1))))

  status <- git2r::status(git2r::repository(fx$repo_dir),
                          staged = TRUE, unstaged = TRUE, untracked = FALSE)
  expect_length(unlist(status$staged, use.names = FALSE), 0L)
  expect_length(unlist(status$unstaged, use.names = FALSE), 0L)
})
# === door 2: the repair ========================================================
test_that("datom_validate(fix = TRUE) re-derives `commit_sha` instead of stripping it", {
  fx <- local_commit_link_project()
  vc_write(fx, "dm", 3L)
  vc_write(fx, "dm", 5L)
  expected <- vc_links(vc_stored_history(fx, "dm"))
  expect_false(anyNA(expected))

  # Two separate losses, so the repair has to both re-upload and re-derive: the
  # stored history is gone (which is what makes the repo invalid, so `fix` runs
  # at all), and the clone's copy it will upload carries no commit ids.
  fs::file_delete(.datom_local_path(fx$conn, vc_history_key("dm")))

  result <- suppressMessages(datom_validate(fx$conn, fix = TRUE))
  expect_false(result$valid)
  expect_true(result$fixed)

  expect_identical(vc_links(vc_stored_history(fx, "dm")), expected)
})
# === door 3: the metadata-only sync ============================================
test_that("the metadata-only route re-derives `commit_sha` that storage has lost", {
  fx <- local_commit_link_project()
  vc_write(fx, "dm", 3L)
  vc_write(fx, "dm", 5L)
  expected <- vc_links(vc_stored_history(fx, "dm"))

  vc_strip_stored_links(fx, "dm")
  expect_true(all(is.na(vc_links(vc_stored_history(fx, "dm")))))

  # This route exists for a metadata edit made by hand in the clone. `custom` is
  # hashed into the version, so the edit changes the version while leaving
  # `data_sha` alone -- which is exactly the `metadata_only` classification the
  # route needs in order to do anything at all.
  meta_path <- fs::path(fx$repo_dir, "dm", "metadata.json")
  meta <- jsonlite::read_json(meta_path, simplifyVector = TRUE)
  meta$custom <- list(note = "hand-edited")
  jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE)

  result <- suppressMessages(datom_write(fx$conn, data = NULL, name = "dm"))
  expect_identical(result$action, "metadata_only")

  # Both pre-existing versions get their commit ids back, worked out from git.
  links <- vc_links(vc_stored_history(fx, "dm"))
  expect_identical(links[names(expected)], expected)
})
# === what the derivation answers ===============================================
test_that("a code-only commit produces no version, so it is nobody's `commit_sha`", {
  fx <- local_commit_link_project()
  vc_write(fx, "dm", 3L)
  write_commit <- vc_head(fx)

  # A commit that touches only the caller's own files leaves `dm/metadata.json`
  # untouched, so it is not in the walk at all.
  fs::dir_create(fs::path(fx$repo_dir, "R"))
  writeLines("f <- function() 1", fs::path(fx$repo_dir, "R", "build.R"))
  .datom_git_commit(fx$repo_dir, "R/build.R", "Add build code")
  expect_false(identical(vc_head(fx), write_commit))

  derived <- .datom_git_commit_shas_by_version(fx$repo_dir, "dm")
  expect_length(derived, 1L)
  expect_identical(unname(derived), write_commit)
})
test_that("the derivation names the FIRST commit that produced a version", {
  # A plain git repo, not a datom project: the claim is about the walk, and one
  # version has to be produced twice for the claim to have any content. Reaching
  # that state through datom's own writes is not possible -- an unchanged write is
  # a no-op that makes no commit.
  root <- withr::local_tempdir()
  repo <- git2r::init(root)
  git2r::config(repo, user.name = "Walk Test", user.email = "walk@test.com")
  fs::dir_create(fs::path(root, "dm"))
  meta_path <- fs::path(root, "dm", "metadata.json")

  doc_a <- list(kind = "table", data_sha = "aaa", nrow = 1L, ncol = 1L,
                colnames = list("id"), table_type = "derived", hash_algo = "sha256")
  doc_b <- utils::modifyList(doc_a, list(data_sha = "bbb"))

  commit_doc <- function(doc, message) {
    jsonlite::write_json(doc, meta_path, auto_unbox = TRUE, pretty = TRUE)
    git2r::add(repo, "dm/metadata.json")
    as.character(git2r::commit(repo, message)$sha)
  }
  first_a <- commit_doc(doc_a, "A")
  commit_doc(doc_b, "B")
  second_a <- commit_doc(doc_a, "A again")
  expect_false(identical(first_a, second_a))

  derived <- .datom_git_commit_shas_by_version(root, "dm")
  version_a <- .datom_compute_metadata_sha(
    jsonlite::fromJSON(jsonlite::toJSON(doc_a, auto_unbox = TRUE))
  )
  expect_identical(derived[[version_a]], first_a)
})
test_that("a commit that cannot be worked out omits the field rather than writing an empty object", {
  # `jsonlite` writes a NULL element as `{}`, so "no commit id" has to be spelled
  # by an absent key. Asserted on the stored BYTES: a parsed check cannot tell an
  # absent key from one holding an empty object without saying so explicitly, and
  # this is the trap that has already been corrected in four other places.
  fx <- local_commit_link_project()

  meta <- list(kind = "table", data_sha = "aaa", nrow = 1L, ncol = 1L,
               colnames = list("id"), table_type = "derived", hash_algo = "sha256",
               created_at = "2026-01-01T00:00:00Z")
  version <- .datom_compute_metadata_sha(meta)

  # Local files only, and no commit: nothing in git history describes this
  # artifact, so no commit can be derived for it.
  .datom_write_metadata_local(fx$conn, "ghost", meta, version, message = "ghost")
  .datom_push_metadata_s3(fx$conn, "ghost", meta, version, commit_sha = NULL)

  text <- vc_stored_history_text(fx, "ghost")
  expect_false(grepl("commit_sha", text, fixed = TRUE))
  expect_length(vc_stored_history(fx, "ghost"), 1L)
})
test_that("a commit id storage holds but git cannot reproduce survives the next upload", {
  # The half of the design that derivation cannot cover. A shallow clone or a
  # rewritten history leaves a recorded commit id that nothing can recompute, so
  # an upload that derived everything and kept nothing would throw it away. The
  # same fixture as above stands in for that: an artifact with no commits at all.
  fx <- local_commit_link_project()

  meta <- list(kind = "table", data_sha = "aaa", nrow = 1L, ncol = 1L,
               colnames = list("id"), table_type = "derived", hash_algo = "sha256",
               created_at = "2026-01-01T00:00:00Z")
  version <- .datom_compute_metadata_sha(meta)
  .datom_write_metadata_local(fx$conn, "ghost", meta, version, message = "ghost")
  .datom_push_metadata_s3(fx$conn, "ghost", meta, version, commit_sha = NULL)

  stored <- vc_stored_history(fx, "ghost")
  stored[[1L]]$commit_sha <- strrep("d", 40L)
  .datom_storage_write_json(fx$conn, vc_history_key("ghost"), stored)

  .datom_push_metadata_s3(fx$conn, "ghost", meta, version, commit_sha = NULL)
  expect_identical(vc_links(vc_stored_history(fx, "ghost"))[[version]],
                   strrep("d", 40L))
})
# === a change that alters no content alters no version =========================
test_that("a code-only change mints no version and leaves the recorded commit alone", {
  fx <- local_commit_link_project()
  vc_write(fx, "dm", 3L)
  version <- datom_history(fx$conn, "dm", short_hash = FALSE)$version[[1L]]
  member <- datom_member(fx$conn, "dm", version, tags = list(type = "input"))

  fs::dir_create(fs::path(fx$repo_dir, "R"))
  code_path <- fs::path(fx$repo_dir, "R", "build.R")
  writeLines("build <- function() 1", code_path)

  first <- suppressMessages(
    datom_write_set(fx$conn, list(member), include_paths = "R")
  )
  set_commit <- vc_head(fx)
  before <- vc_links(vc_stored_history(fx, fx$set_name))
  expect_length(before, 1L)
  expect_identical(before[[first$metadata_sha]], set_commit)

  # The refactor: different code, identical members and tags.
  writeLines(c("# tidied", "build <- function() {", "  1", "}"), code_path)
  second <- suppressMessages(
    datom_write_set(fx$conn, list(member), include_paths = "R")
  )

  expect_identical(second$metadata_sha, first$metadata_sha)
  expect_identical(second$action, "none")
  expect_identical(vc_head(fx), set_commit)
  expect_identical(vc_links(vc_stored_history(fx, fx$set_name)), before)
})
# === datom_history() surfaces it ===============================================
test_that("datom_history() reports commit_sha, and NA where there is none", {
  history <- list(
    list(version = "v1", data_sha = "s1", timestamp = "t1",
         commit_message = "one", commit_sha = "cafebabe1234"),
    list(version = "v2", data_sha = "s2", timestamp = "t2",
         commit_message = "two")
  )
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) history
  )
  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "dm", short_hash = FALSE)
  expect_true("commit_sha" %in% names(result))
  expect_identical(result$commit_sha[[1L]], "cafebabe1234")
  expect_true(is.na(result$commit_sha[[2L]]))
})
test_that("datom_history() abbreviates commit_sha under short_hash", {
  history <- list(
    list(version = strrep("a", 64L), data_sha = strrep("b", 64L),
         timestamp = "t1", commit_sha = strrep("c", 40L))
  )
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) history
  )
  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "dm", short_hash = TRUE)
  expect_identical(result$commit_sha, strrep("c", 8L))
})
test_that("the zero-row history frame carries the commit_sha column too", {
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) list()
  )
  conn <- mock_datom_conn(list())
  result <- datom_history(conn, "dm")
  expect_identical(nrow(result), 0L)
  expect_true("commit_sha" %in% names(result))
})
