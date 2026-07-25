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


# --- S3: the re-export loop (Requirement 9.3) ---------------------------------

test_that("Feature: datom-cv1, S3 -- a re-export with identical content is metadata_only, carries parquet_sha forward, and settles", {
  fx <- local_identity_project()
  csv <- fs::path(fx$input_dir, "dm.csv")
  df <- data.frame(
    id = 1:3,
    grp = c("a", "b", "c"),
    score = c(1.5, 2.5, 3.5),
    stringsAsFactors = FALSE
  )

  identity_write_csv(csv, df, quote = TRUE)
  bytes_before <- readBin(csv, "raw", fs::file_size(csv))
  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))

  meta1 <- identity_metadata(fx, "dm")
  stored1 <- identity_stored_parquet(fx, "dm")
  backdated <- as.POSIXct("2001-01-01 00:00:00", tz = "UTC")
  fs::file_touch(stored1, modification_time = backdated)

  # Re-export the same content with different bytes (quoting only). This is the
  # loop that used to mint a spurious full write on every export.
  identity_write_csv(csv, df, quote = FALSE)
  bytes_after <- readBin(csv, "raw", fs::file_size(csv))
  expect_false(identical(bytes_before, bytes_after))

  manifest <- suppressMessages(datom_sync_manifest(fx$conn))
  expect_identical(manifest$status, "changed")

  # The user-visible report names the classification. (Nested so the expected
  # message is asserted and the remaining sync chatter stays out of the log.)
  suppressMessages(expect_message(datom_sync(fx$conn, manifest), "metadata_only"))

  meta2 <- identity_metadata(fx, "dm")

  # Content identity is unchanged; the file's identity is not.
  expect_identical(meta2$data_sha, meta1$data_sha)
  expect_false(identical(meta2$original_file_sha, meta1$original_file_sha))
  expect_identical(
    meta2$original_file_sha,
    .datom_compute_original_file_sha(csv)
  )

  # parquet_sha is carried forward from the current metadata, not recomputed
  # from the fresh serialization -- the stored object is the one it pins.
  expect_identical(meta2$parquet_sha, meta1$parquet_sha)
  expect_true(nzchar(meta2$parquet_sha))

  # No upload: same single object, untouched mtime.
  expect_identical(identity_stored_parquet(fx, "dm"), stored1)
  expect_equal(
    as.numeric(fs::file_info(stored1)$modification_time),
    as.numeric(backdated)
  )
  expect_identical(
    digest::digest(file = stored1, algo = "sha256"),
    meta2$parquet_sha
  )

  # A new version was recorded (the file provenance changed) over the same data.
  history <- identity_history(fx, "dm")
  expect_length(history, 2L)
  expect_identical(history[[1]]$data_sha, history[[2]]$data_sha)
  expect_false(identical(history[[1]]$version, history[[2]]$version))
  expect_identical(history[[1]]$parquet_sha, meta1$parquet_sha)
  expect_identical(history[[1]]$original_file_sha, meta2$original_file_sha)

  # And the loop closes: the next scan sees nothing to do.
  expect_identical(suppressMessages(datom_sync_manifest(fx$conn))$status,
                   "unchanged")
})

test_that("Feature: datom-cv1, S3 -- the carried-forward parquet_sha still verifies on read", {
  fx <- local_identity_project()
  csv <- fs::path(fx$input_dir, "dm.csv")
  df <- data.frame(id = 1:3, grp = c("a", "b", "c"), stringsAsFactors = FALSE)

  identity_write_csv(csv, df, quote = TRUE)
  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))
  identity_write_csv(csv, df, quote = FALSE)
  suppressMessages(
    datom_sync(fx$conn, suppressMessages(datom_sync_manifest(fx$conn)))
  )

  # The read path resolves the carried-forward parquet_sha and the integrity
  # check passes against the object that was never re-uploaded.
  round_trip <- datom_read(fx$conn, "dm")
  expect_equal(as.data.frame(round_trip), df)

  # Pinning the older version resolves too -- both history entries share the
  # same data_sha and the same recorded parquet_sha.
  history <- identity_history(fx, "dm")
  older <- datom_read(fx$conn, "dm", version = history[[2]]$version)
  expect_equal(as.data.frame(older), df)
})


# --- S4: no duplicate version on re-syncing an older file (Requirement 9.4) ---

test_that("Feature: datom-cv1, S4 -- re-syncing an older content-matching file appends no duplicate version", {
  fx <- local_identity_project()
  csv <- fs::path(fx$input_dir, "dm.csv")
  df <- data.frame(id = 1:3, grp = c("a", "b", "c"), stringsAsFactors = FALSE)

  # V1: the original export.
  identity_write_csv(csv, df, quote = TRUE)
  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))
  v1 <- identity_history(fx, "dm")[[1]]$version
  file_sha_v1 <- identity_metadata(fx, "dm")$original_file_sha
  stored <- identity_stored_parquet(fx, "dm")
  backdated <- as.POSIXct("2001-01-01 00:00:00", tz = "UTC")
  fs::file_touch(stored, modification_time = backdated)

  # V2: a re-export -- different bytes, same content.
  identity_write_csv(csv, df, quote = FALSE)
  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))
  v2 <- identity_history(fx, "dm")[[1]]$version
  expect_false(identical(v1, v2))
  expect_length(identity_history(fx, "dm"), 2L)

  # Now the developer syncs the OLDER file again (restored from a backup, or a
  # colleague's copy). Its metadata is byte-for-byte the semantic metadata of
  # V1, so metadata_sha comes back to V1 -- the case that used to append a
  # second entry with the same version and make datom_read(version=) ambiguous.
  identity_write_csv(csv, df, quote = TRUE)
  manifest <- suppressMessages(datom_sync_manifest(fx$conn))
  expect_identical(manifest$status, "changed")
  result <- suppressMessages(datom_sync(fx$conn, manifest))
  expect_identical(result$result, "success")

  meta3 <- identity_metadata(fx, "dm")
  expect_identical(.datom_compute_metadata_sha(meta3), v1)
  expect_identical(meta3$original_file_sha, file_sha_v1)

  # The current pointer moved back to V1; history did NOT grow, and V1 appears
  # exactly once (Requirement 12.3).
  history <- identity_history(fx, "dm")
  expect_length(history, 2L)
  versions <- vapply(history, function(e) e$version, character(1))
  expect_identical(sum(versions == v1), 1L)
  expect_setequal(versions, c(v1, v2))

  # No upload for a metadata-only revisit.
  expect_identical(identity_stored_parquet(fx, "dm"), stored)
  expect_equal(
    as.numeric(fs::file_info(stored)$modification_time),
    as.numeric(backdated)
  )

  # The regression symptom: version resolution stays unambiguous, both for the
  # full sha and for a short prefix.
  expect_equal(as.data.frame(datom_read(fx$conn, "dm", version = v1)), df)
  expect_equal(
    as.data.frame(datom_read(fx$conn, "dm", version = substr(v1, 1, 8))),
    df
  )
  expect_error(datom_read(fx$conn, "dm", version = v1), NA)
})

test_that("Feature: datom-cv1, S4 -- the dedup guard scans the whole history, not just the latest entry", {
  fx <- local_identity_project()
  csv <- fs::path(fx$input_dir, "dm.csv")
  df_a <- data.frame(id = 1:3, grp = c("a", "b", "c"), stringsAsFactors = FALSE)
  df_b <- data.frame(id = 1:4, grp = c("a", "b", "c", "d"),
                     stringsAsFactors = FALSE)

  # A (V1), then a genuinely different content B (V2), then A again. A's version
  # is now two entries deep, so a latest-only guard would re-append it.
  identity_write_csv(csv, df_a, quote = TRUE)
  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))
  v1 <- identity_history(fx, "dm")[[1]]$version

  identity_write_csv(csv, df_b, quote = TRUE)
  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))

  identity_write_csv(csv, df_a, quote = TRUE)
  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))

  history <- identity_history(fx, "dm")
  versions <- vapply(history, function(e) e$version, character(1))
  expect_length(history, 2L)
  expect_identical(sum(versions == v1), 1L)
  # Two contents, two content-addressed objects, and V1 still resolves to A.
  expect_length(identity_stored_parquet(fx, "dm"), 2L)
  expect_equal(as.data.frame(datom_read(fx$conn, "dm", version = v1)), df_a)
})


# --- parquet_sha integrity, revert-to-older, provenance ----------------------
# Requirements 5.5, 8.3, 8.4, 16.5, 16.6.

test_that("Feature: datom-cv1, read-time integrity -- a corrupted stored object aborts the read", {
  fx <- local_identity_project()
  df <- data.frame(id = 1:5, v = letters[1:5], stringsAsFactors = FALSE)
  suppressMessages(datom_write(fx$conn, data = df, name = "tbl"))

  stored <- identity_stored_parquet(fx, "tbl")
  expect_length(stored, 1L)
  expect_equal(as.data.frame(datom_read(fx$conn, "tbl")), df)

  # Flip one byte in the middle of the stored object.
  bytes <- readBin(stored, "raw", fs::file_size(stored))
  mid <- floor(length(bytes) / 2)
  bytes[mid] <- as.raw(xor(as.integer(bytes[mid]), 1L))
  writeBin(bytes, stored)

  expect_error(datom_read(fx$conn, "tbl"), "integrity check")
})

test_that("Feature: datom-cv1, read-time integrity -- a swapped-in valid parquet is caught before parsing", {
  fx <- local_identity_project()
  df <- data.frame(id = 1:5, v = letters[1:5], stringsAsFactors = FALSE)
  suppressMessages(datom_write(fx$conn, data = df, name = "tbl"))
  stored <- identity_stored_parquet(fx, "tbl")

  # Substitute a DIFFERENT but perfectly readable parquet. Nothing downstream
  # would complain: arrow parses it happily and the caller would silently get
  # the wrong table. Only the parquet_sha check can catch this, so the abort
  # proves verification precedes the parse rather than riding on a parse error.
  imposter <- withr::local_tempfile(fileext = ".parquet")
  arrow::write_parquet(data.frame(id = 99L, v = "z", stringsAsFactors = FALSE),
                       imposter)
  fs::file_copy(imposter, stored, overwrite = TRUE)
  expect_s3_class(arrow::read_parquet(stored), "data.frame")

  err <- expect_error(datom_read(fx$conn, "tbl"), "integrity check")
  msg <- conditionMessage(err)
  expect_match(msg, "tbl", fixed = TRUE)
  expect_match(msg, "tampered")
})

test_that("Feature: datom-cv1, read-time integrity -- legacy metadata without parquet_sha still reads", {
  fx <- local_identity_project()
  df <- data.frame(id = 1:3, v = c("a", "b", "c"), stringsAsFactors = FALSE)
  suppressMessages(datom_write(fx$conn, data = df, name = "tbl"))

  # Age the stored metadata into a pre-cv1 shape: drop parquet_sha from the
  # copy datom_read() actually consults (the storage one, not the git one).
  meta_key <- "tbl/.metadata/metadata.json"
  stored_meta <- .datom_storage_read_json(fx$conn, meta_key)
  expect_true(nzchar(stored_meta$parquet_sha %||% ""))
  stored_meta$parquet_sha <- NULL
  .datom_local_write_json(fx$conn, meta_key, stored_meta)

  # No expected hash -> the check is skipped, not failed (Requirement 8.4).
  expect_equal(as.data.frame(datom_read(fx$conn, "tbl")), df)
})

test_that("Feature: datom-cv1, revert-to-older content reuses the history parquet_sha without overwriting the object", {
  fx <- local_identity_project()
  content_a <- data.frame(id = 1:3, v = c("a", "b", "c"),
                          stringsAsFactors = FALSE)
  content_b <- data.frame(id = 1:4, v = c("a", "b", "c", "d"),
                          stringsAsFactors = FALSE)

  write_a <- suppressMessages(
    datom_write(fx$conn, data = content_a, name = "tbl")
  )
  history_a <- identity_history(fx, "tbl")
  parquet_sha_a <- history_a[[1]]$parquet_sha
  expect_true(nzchar(parquet_sha_a %||% ""))

  object_a <- .datom_local_path(
    fx$conn, paste0("tbl/", write_a$data_sha, ".parquet")
  )
  expect_true(fs::file_exists(object_a))
  backdated <- as.POSIXct("2001-01-01 00:00:00", tz = "UTC")
  fs::file_touch(object_a, modification_time = backdated)

  suppressMessages(datom_write(fx$conn, data = content_b, name = "tbl"))

  # Back to content A: a full change relative to current (B), but the object is
  # already stored and pinned by A's version.
  write_a2 <- suppressMessages(
    datom_write(fx$conn, data = content_a, name = "tbl")
  )
  expect_identical(write_a2$action, "full")
  expect_identical(write_a2$data_sha, write_a$data_sha)

  meta <- identity_metadata(fx, "tbl")
  expect_identical(meta$parquet_sha, parquet_sha_a)

  # The stored object was not re-uploaded: backdated mtime intact, and its
  # bytes still hash to the parquet_sha A's version pinned.
  expect_equal(
    as.numeric(fs::file_info(object_a)$modification_time),
    as.numeric(backdated)
  )
  expect_identical(
    digest::digest(file = object_a, algo = "sha256"),
    parquet_sha_a
  )
  expect_length(identity_stored_parquet(fx, "tbl"), 2L)

  # Both the current pointer and A's pinned version read back as content A.
  expect_equal(as.data.frame(datom_read(fx$conn, "tbl")), content_a)
  expect_equal(
    as.data.frame(datom_read(fx$conn, "tbl", version = history_a[[1]]$version)),
    content_a
  )
})

test_that("Feature: datom-cv1, provenance -- hash_algo and imported-path original_file_sha are recorded", {
  fx <- local_identity_project()
  csv <- fs::path(fx$input_dir, "dm.csv")
  df <- data.frame(id = 1:3, grp = c("a", "b", "c"), stringsAsFactors = FALSE)
  identity_write_csv(csv, df)

  suppressMessages(datom_sync(fx$conn, suppressMessages(
    datom_sync_manifest(fx$conn)
  )))
  suppressMessages(datom_write(fx$conn, data = df, name = "derived_tbl"))

  imported <- identity_metadata(fx, "dm")
  derived <- identity_metadata(fx, "derived_tbl")

  # hash_algo is unconditional, on both paths and in the storage copy too.
  expect_identical(imported$hash_algo, "datom-cv1")
  expect_identical(derived$hash_algo, "datom-cv1")
  expect_identical(
    .datom_storage_read_json(fx$conn, "dm/.metadata/metadata.json")$hash_algo,
    "datom-cv1"
  )

  # original_file_sha: recorded on the imported path (metadata AND history
  # entry AND the repo manifest), absent on the derived path.
  expect_identical(
    imported$original_file_sha,
    .datom_compute_original_file_sha(csv)
  )
  expect_identical(
    identity_history(fx, "dm")[[1]]$original_file_sha,
    imported$original_file_sha
  )
  manifest_json <- jsonlite::read_json(
    fs::path(fx$repo_dir, ".datom", "manifest.json")
  )
  expect_identical(
    manifest_json$tables$dm$original_file_sha,
    imported$original_file_sha
  )
  expect_identical(imported$table_type, "imported")
  expect_false("original_file_sha" %in% names(derived))
})

test_that("Feature: datom-cv1, the suite runs under the fail-closed network guard", {
  # Requirement 16.6. setup.R replaces both egress chokepoints with aborting
  # stubs unless DATOM_ALLOW_REAL_NETWORK is set; this asserts the guard is
  # actually in force for this file rather than assuming it.
  skip_if(nzchar(Sys.getenv("DATOM_ALLOW_REAL_NETWORK")),
          "Network guard deliberately disabled via DATOM_ALLOW_REAL_NETWORK.")

  expect_error(.datom_s3_client(), "Real network egress blocked")
  expect_error(httr2::req_perform(NULL), "Real network egress blocked")
})
