# Syncing a product repo's set against its sources: the preview,
# `datom_sync_manifest(conn, sources = )`.
#
# REAL REPOS AND REAL LOCAL STORES, two of them at least: the product repo that
# owns the set, and a source project whose tables become its inputs. The preview
# reads the source's manifest from storage and the set from the product repo's
# storage, so both have to exist for real. A few set-member cases use a
# hand-built set (swapping the set reader for one returning it) to pin a version
# or a missing artifact cheaply; the set-of-sets test at the bottom covers the
# same comparison with three real projects and no mocks.
#
# THREE OF THESE ARE THE TESTS A PLAUSIBLE IMPLEMENTATION PASSES EVERYTHING ELSE
# WHILE FAILING.
#
#   * "No set yet" is tested through a store that FAILS, not one that is empty:
#     catching the set read's error would report "first version" whether storage
#     is empty or down, and an empty-store test cannot tell them apart.
#   * The mislabelled-source test uses a source whose manifest really records
#     another project name. With label and manifest agreeing, the check can be
#     deleted and the test stays green.
#   * Refusal classes are asserted with `inherit = FALSE`, because the source
#     loop must hand them to the caller unwrapped.

ss_project <- function(project_name, set_name = NULL, prefix = "proj",
                       env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)

  repo_dir <- fs::path(root, "repo")
  store_dir <- fs::path(root, "store")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, store_dir, bare_dir))

  git2r::init(bare_dir, bare = TRUE)
  repo <- git2r::init(repo_dir)
  git2r::config(repo, user.name = "Sync Test", user.email = "sync@test.com")
  writeLines("init", fs::path(repo_dir, "README.md"))
  git2r::add(repo, "README.md")
  git2r::commit(repo, "Initial commit")
  git2r::remote_add(repo, name = "origin", url = as.character(bare_dir))
  git2r::push(repo, name = "origin", refspec = test_head_refspec(repo),
              set_upstream = TRUE)

  conn <- mock_datom_conn(list(), root = as.character(store_dir),
                          prefix = prefix)
  conn$backend <- "local"
  conn$role <- "developer"
  conn$path <- as.character(repo_dir)
  conn$project_name <- project_name
  conn$github_pat <- "SUPER-SECRET-TOKEN-XYZ"

  if (is.null(set_name)) {
    fs::dir_create(fs::path(repo_dir, ".datom"))
    yaml::write_yaml(list(project_name = project_name),
                     fs::path(repo_dir, ".datom", "project.yaml"))
  } else {
    write_product_config(repo_dir, project_name, set_name)
  }

  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir, repo = repo,
       set_name = set_name, project_name = project_name)
}

ss_data <- function(n = 3L) {
  data.frame(id = seq_len(n), val = letters[seq_len(n)],
             stringsAsFactors = FALSE)
}

# Write a table and return the version just minted.
ss_table <- function(fx, name, n = 3L) {
  suppressMessages(datom_write(fx$conn, data = ss_data(n), name = name))
  datom_history(fx$conn, name, short_hash = FALSE)$version[[1L]]
}

ss_member <- function(fx, name, version, tags = list(type = "input")) {
  datom_member(fx$conn, name, version, tags = tags)
}

ss_write_set <- function(product, members) {
  suppressMessages(datom_write_set(product$conn, members))
}

ss_preview <- function(...) suppressMessages(datom_sync_manifest(...))

ss_messages <- function(expr) {
  cli::ansi_strip(paste(testthat::capture_messages(expr), collapse = ""))
}

ss_row <- function(m, name, project = NULL) {
  keep <- m$name == name
  if (!is.null(project)) keep <- keep & m$project == project
  m[keep, , drop = FALSE]
}

# Edit a source's stored manifest in place, the way a half-finished write or an
# older datom would leave it.
ss_edit_manifest <- function(fx, fn) {
  key <- ".metadata/manifest.json"
  manifest <- .datom_storage_read_json(fx$conn, key)
  .datom_storage_write_json(fx$conn, key, fn(manifest))
}

# The usual pair: a product repo, and one source with `dm` and `lb` written.
ss_pair <- function(env = parent.frame()) {
  product <- ss_project("liver-safety", "liver-set", "pp", env = env)
  source <- ss_project("imported", prefix = "ps", env = env)
  v_dm <- ss_table(source, "dm", 3L)
  v_lb <- ss_table(source, "lb", 4L)
  list(product = product, source = source, v_dm = v_dm, v_lb = v_lb)
}

preview_cols <- c("project", "name", "kind", "version_from", "version_to",
                  "status")


# === which context the call is in =============================================

test_that("new arguments come last, so positional calls keep working", {
  expect_identical(names(formals(datom_sync_manifest)),
                   c("conn", "path", "pattern", "sources"))
})

test_that("a product repo without sources stops and names the argument", {
  fx <- ss_pair()
  err <- expect_error(datom_sync_manifest(fx$product$conn),
                      class = "datom_import_on_product")
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "sources = ", fixed = TRUE)
  expect_match(msg, "datom_sync_manifest")
  expect_match(msg, "datom_write")
  expect_match(msg, "datom_write_set")
  expect_match(msg, "liver-set")
})

test_that("an ordinary repo given sources stops, before scanning anything", {
  # No `input_files/` here: without the refusal the scan would fail with its own
  # "not found" message instead.
  fx <- ss_pair()
  expect_false(fs::dir_exists(fs::path(fx$source$repo_dir, "input_files")))

  err <- expect_error(
    datom_sync_manifest(fx$source$conn, sources = fx$product$conn),
    class = "datom_sync_sources_on_ordinary"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "product repo")
})

test_that("a product repo given a file path stops rather than ignoring it", {
  fx <- ss_pair()
  expect_error(
    datom_sync_manifest(fx$product$conn, path = tempdir(),
                        sources = fx$source$conn),
    class = "datom_sync_file_arg_on_product"
  )
})

test_that("a product repo that names no set stops", {
  fx <- ss_pair()
  cfg_path <- fs::path(fx$product$repo_dir, ".datom", "project.yaml")
  cfg <- yaml::read_yaml(cfg_path)
  cfg$set <- NULL
  yaml::write_yaml(cfg, cfg_path)

  expect_error(
    datom_sync_manifest(fx$product$conn, sources = fx$source$conn),
    class = "datom_set_undeclared"
  )
})

test_that("the context comes from the config file, not the connection", {
  # The connection says nothing about a mode; only the file does.
  fx <- ss_pair()
  expect_null(fx$product$conn$mode)
  m <- ss_preview(fx$product$conn, sources = fx$source$conn)
  expect_identical(names(m), preview_cols)
})

test_that("apply on a product repo without sources stops and names the argument", {
  fx <- ss_pair()
  frame <- data.frame(
    name = "dm", file = "dm.csv", format = "csv",
    original_file_sha = strrep("a", 64L), status = "new",
    stringsAsFactors = FALSE
  )
  err <- expect_error(datom_sync(fx$product$conn, frame),
                      class = "datom_import_on_product")
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "datom_sync(conn, manifest, sources = ", fixed = TRUE)
  expect_match(msg, "liver-set")
})


# === the rows =================================================================

test_that("first version: every source table is new, with full versions", {
  # AC7, preview half, and R2.8.
  fx <- ss_pair()
  m <- ss_preview(fx$product$conn, sources = fx$source$conn)

  expect_identical(names(m), preview_cols)
  expect_s3_class(m, "data.frame")
  expect_identical(m$name, c("dm", "lb"))
  expect_identical(m$project, c("imported", "imported"))
  expect_identical(m$kind, c("table", "table"))
  expect_identical(m$status, c("new", "new"))
  expect_identical(m$version_from, c(NA_character_, NA_character_))
  expect_identical(m$version_to, c(fx$v_dm, fx$v_lb))
  expect_true(all(nchar(m$version_to) == 64L))
})

test_that("changed, unchanged and new, with from and to versions", {
  # AC2 and AC3: a table added to a source appears as new.
  fx <- ss_pair()
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm),
                                ss_member(fx$source, "lb", fx$v_lb)))
  new_lb <- ss_table(fx$source, "lb", 6L)
  v_ex <- ss_table(fx$source, "ex", 2L)

  m <- ss_preview(fx$product$conn, sources = fx$source$conn)

  expect_identical(m$name, c("dm", "ex", "lb"))

  dm <- ss_row(m, "dm")
  expect_identical(dm$status, "unchanged")
  expect_identical(dm$version_from, fx$v_dm)
  expect_identical(dm$version_to, fx$v_dm)

  lb <- ss_row(m, "lb")
  expect_identical(lb$status, "changed")
  expect_identical(lb$version_from, fx$v_lb)
  expect_identical(lb$version_to, new_lb)

  ex <- ss_row(m, "ex")
  expect_identical(ex$status, "new")
  expect_true(is.na(ex$version_from))
  expect_identical(ex$version_to, v_ex)
})

test_that("the summary line counts each status", {
  fx <- ss_pair()
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm),
                                ss_member(fx$source, "lb", fx$v_lb)))
  ss_table(fx$source, "lb", 6L)
  ss_table(fx$source, "ex", 2L)

  msg <- ss_messages(datom_sync_manifest(fx$product$conn,
                                         sources = fx$source$conn))
  expect_match(msg,
               "Mapped 3 artifacts from 1 source: 1 new, 1 changed, 1 unchanged",
               fixed = TRUE)
})

test_that("a member whose table left its source is reported, never removed", {
  # R2.3. The table is dropped from the source's stored manifest, which is the
  # document the preview reads.
  fx <- ss_pair()
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm),
                                ss_member(fx$source, "lb", fx$v_lb)))
  ss_edit_manifest(fx$source, function(man) {
    man$artifacts$lb <- NULL
    man
  })

  msg <- ss_messages(m <- datom_sync_manifest(fx$product$conn,
                                              sources = fx$source$conn))

  expect_identical(m$name, "dm")
  expect_match(msg, "1 member left pinned")
  expect_match(msg, "lb (table) in imported", fixed = TRUE)
  expect_match(msg, "never removes")
})

test_that("a source table matching no member of an older set is new, not removed", {
  # The preview has no removal status at all.
  fx <- ss_pair()
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm)))

  m <- ss_preview(fx$product$conn, sources = fx$source$conn)
  expect_setequal(m$status, c("unchanged", "new"))
  expect_false(any(m$status %in% c("removed", "remove", "dropped")))
})

test_that("the same table pinned twice is one ambiguous row naming the fix", {
  # AC6 and R2.6: a live lb beside a frozen baseline.
  fx <- ss_pair()
  new_lb <- ss_table(fx$source, "lb", 6L)
  ss_write_set(fx$product, list(
    ss_member(fx$source, "lb", fx$v_lb,
              tags = list(type = "input", release = "baseline")),
    ss_member(fx$source, "lb", new_lb,
              tags = list(type = "input", release = "live"))
  ))
  newest_lb <- ss_table(fx$source, "lb", 7L)

  msg <- ss_messages(m <- datom_sync_manifest(fx$product$conn,
                                              sources = fx$source$conn))

  lb <- ss_row(m, "lb")
  expect_identical(nrow(lb), 1L)
  expect_identical(lb$status, "ambiguous")
  expect_true(is.na(lb$version_from))
  expect_identical(lb$version_to, newest_lb)

  expect_match(msg, "1 artifact is pinned more than once")
  expect_match(msg, substr(fx$v_lb, 1L, 8L), fixed = TRUE)
  expect_match(msg, substr(new_lb, 1L, 8L), fixed = TRUE)
  expect_match(msg, "datom_update_members(x, conn, member = \"lb\", tags = ",
               fixed = TRUE)
  expect_match(msg, "1 ambiguous", fixed = TRUE)
})

test_that("two sources holding the same table name are matched independently", {
  fx <- ss_pair()
  other <- ss_project("imported-b", prefix = "pb")
  v_b <- ss_table(other, "dm", 5L)
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm),
                                ss_member(other, "dm", v_b)))
  new_b <- ss_table(other, "dm", 8L)

  m <- ss_preview(fx$product$conn, sources = list(fx$source$conn, other$conn))

  expect_identical(ss_row(m, "dm", "imported")$status, "unchanged")
  b <- ss_row(m, "dm", "imported-b")
  expect_identical(b$status, "changed")
  expect_identical(b$version_from, v_b)
  expect_identical(b$version_to, new_b)
})

test_that("a pattern filters source tables and a filtered member is excluded", {
  # R2.2's `excluded`: the row confirms the filter left the member alone, so it
  # is counted, not warned about as unchecked.
  fx <- ss_pair()
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm),
                                ss_member(fx$source, "lb", fx$v_lb)))
  ss_table(fx$source, "lb", 6L)

  msg <- ss_messages(m <- datom_sync_manifest(
    fx$product$conn, pattern = "d*", sources = fx$source$conn
  ))

  expect_identical(m$name, c("dm", "lb"))
  expect_identical(ss_row(m, "dm")$status, "unchanged")

  lb <- ss_row(m, "lb")
  expect_identical(lb$status, "excluded")
  expect_identical(lb$version_from, fx$v_lb)
  expect_true(is.na(lb$version_to))

  expect_match(msg, "1 excluded by pattern", fixed = TRUE)
  expect_no_match(msg, "not checked")
})

test_that("a pattern matching nothing gives a zero-row frame with the columns", {
  fx <- ss_pair()
  m <- ss_preview(fx$product$conn, pattern = "zz*", sources = fx$source$conn)

  expect_identical(nrow(m), 0L)
  expect_identical(names(m), preview_cols)
  expect_true(all(vapply(m, is.character, logical(1L))))
})


# === members the call does not compare ========================================

test_that("a member from a project not passed is not_checked, with the fix", {
  # R2.7 and AC5.
  fx <- ss_pair()
  other <- ss_project("imported-b", prefix = "pb")
  v_b <- ss_table(other, "ae", 5L)
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm),
                                ss_member(other, "ae", v_b)))

  msg <- ss_messages(m <- datom_sync_manifest(fx$product$conn,
                                              sources = fx$source$conn))

  ae <- ss_row(m, "ae")
  expect_identical(ae$status, "not_checked")
  expect_identical(ae$project, "imported-b")
  expect_identical(ae$version_from, v_b)
  expect_true(is.na(ae$version_to))

  expect_match(msg, "1 member not checked")
  expect_match(msg, "imported-b")
  expect_match(msg, "build the preview again with every source")
})

test_that("a member that is a set, in a source project, is compared like a table", {
  # R2.1a and AC17. The source's manifest lists the set at a newer version than
  # the member pins, so a preview that skipped set members could not produce
  # `changed`. The real end-to-end case is the set-of-sets test at the bottom.
  fx <- ss_pair()
  ss_edit_manifest(fx$source, function(man) {
    man$artifacts$bundle <- list(kind = "set",
                                 current_version = strrep("d", 64L))
    man$artifacts$frozen <- list(kind = "set",
                                 current_version = strrep("e", 64L))
    man
  })
  hand_set <- .datom_empty_set("liver-set", "liver-safety")
  hand_set$members <- list(
    list(id = list(project = "imported", name = "bundle", kind = "set",
                   version = strrep("c", 64L))),
    list(id = list(project = "imported", name = "frozen", kind = "set",
                   version = strrep("e", 64L)))
  )
  local_mocked_bindings(.datom_sync_read_set = function(conn, name) hand_set)

  msg <- ss_messages(m <- datom_sync_manifest(fx$product$conn,
                                              sources = fx$source$conn))

  bundle <- ss_row(m, "bundle")
  expect_identical(nrow(bundle), 1L)
  expect_identical(bundle$status, "changed")
  expect_identical(bundle$kind, "set")
  expect_identical(bundle$version_from, strrep("c", 64L))
  expect_identical(bundle$version_to, strrep("d", 64L))

  frozen <- ss_row(m, "frozen")
  expect_identical(frozen$status, "unchanged")
  expect_identical(frozen$kind, "set")

  expect_false("not_checked" %in% m$status)
  expect_no_match(msg, "not checked")
  expect_match(msg, "Mapped 4 artifacts", fixed = TRUE)
})

test_that("a set member whose set left its source is reported, never removed", {
  fx <- ss_pair()
  hand_set <- .datom_empty_set("liver-set", "liver-safety")
  hand_set$members <- list(
    list(id = list(project = "imported", name = "bundle", kind = "set",
                   version = strrep("c", 64L)))
  )
  local_mocked_bindings(.datom_sync_read_set = function(conn, name) hand_set)

  msg <- ss_messages(m <- datom_sync_manifest(fx$product$conn,
                                              sources = fx$source$conn))

  expect_false("bundle" %in% m$name)
  expect_match(msg, "1 member left pinned")
  expect_match(msg, "bundle (set) in imported", fixed = TRUE)
})

test_that("a set held by a source gets a row with its kind", {
  fx <- ss_pair()
  ss_edit_manifest(fx$source, function(man) {
    man$artifacts$bundle <- list(kind = "set",
                                 current_version = strrep("c", 64L))
    man
  })

  m <- ss_preview(fx$product$conn, sources = fx$source$conn)
  expect_identical(m$name, c("bundle", "dm", "lb"))

  bundle <- ss_row(m, "bundle")
  expect_identical(bundle$kind, "set")
  expect_identical(bundle$status, "new")
  expect_identical(bundle$version_to, strrep("c", 64L))
  expect_identical(ss_row(m, "dm")$kind, "table")
})

test_that("a source entry of a kind this build does not know gets no row", {
  # Nothing here could compare or move it; a newer datom's kind is its concern.
  fx <- ss_pair()
  ss_edit_manifest(fx$source, function(man) {
    man$artifacts$future <- list(kind = "view",
                                 current_version = strrep("c", 64L))
    man
  })

  m <- ss_preview(fx$product$conn, sources = fx$source$conn)
  expect_identical(m$name, c("dm", "lb"))
})

test_that("an output in the set's own project gets no row and no message", {
  fx <- ss_pair()
  v_out <- ss_table(fx$product, "liver_flags", 3L)
  ss_write_set(fx$product, list(
    ss_member(fx$source, "dm", fx$v_dm),
    ss_member(fx$product, "liver_flags", v_out, tags = list(type = "output"))
  ))

  msg <- ss_messages(m <- datom_sync_manifest(fx$product$conn,
                                              sources = fx$source$conn))

  expect_false("liver_flags" %in% m$name)
  expect_no_match(msg, "liver_flags")
  expect_no_match(msg, "not checked")
})

test_that("a source table recording no current version gets no row and is named", {
  fx <- ss_pair()
  ss_edit_manifest(fx$source, function(man) {
    man$artifacts$lb$current_version <- NULL
    man
  })

  msg <- ss_messages(m <- datom_sync_manifest(fx$product$conn,
                                              sources = fx$source$conn))

  expect_identical(m$name, "dm")
  expect_match(msg, "lb in imported", fixed = TRUE)
  expect_match(msg, "no current version")
})

test_that("a preview with nothing to report says only its summary line", {
  # Every source artifact has a version and every member is compared, so no
  # warning applies. Found by the vignette dry run: the no-current-version
  # warning fired on every clean preview, naming one blank artifact.
  fx <- ss_pair()
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm)))

  # One message per cli line, so a count is exact where a match is not.
  msgs <- cli::ansi_strip(testthat::capture_messages(
    m <- datom_sync_manifest(fx$product$conn, sources = fx$source$conn)
  ))

  expect_identical(sort(m$name), c("dm", "lb"))
  expect_length(msgs, 1L)
  expect_match(msgs[[1L]], "Mapped 2 artifacts from 1 source")
  expect_no_match(paste(msgs, collapse = ""), "no current version")
})


# === refusals =================================================================

test_that("the set's own project as a source stops, before any read", {
  # R2.5 and AC5. Every storage read fails here, so a refusal placed after the
  # set read or a source read would surface as that failure instead.
  fx <- ss_pair()
  local_mocked_bindings(
    .datom_storage_exists = function(conn, key) stop("no read expected"),
    .datom_storage_read_json = function(conn, key) stop("no read expected")
  )

  err <- expect_error(
    datom_sync_manifest(fx$product$conn,
                        sources = list(fx$source$conn, fx$product$conn)),
    class = "datom_sync_own_project_source"
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "liver-safety")
  expect_match(msg, "datom_update_members")
})

test_that("a source whose label disagrees with its manifest stops, naming both", {
  # R2.10 and AC5. The precondition is what makes this test able to fail: the
  # source's manifest really does record a different name from the label.
  fx <- ss_pair()
  expect_identical(
    .datom_storage_read_json(fx$source$conn,
                             ".metadata/manifest.json")$project_name,
    "imported"
  )
  mislabelled <- fx$source$conn
  mislabelled$project_name <- "imported-typo"

  err <- expect_error(
    datom_sync_manifest(fx$product$conn, sources = mislabelled),
    class = "datom_sync_source_mislabelled", inherit = FALSE
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "imported-typo")
  expect_match(msg, "\"imported\"", fixed = TRUE)
})

test_that("a manifest recording no project name is not checked against the label", {
  fx <- ss_pair()
  ss_edit_manifest(fx$source, function(man) {
    man$project_name <- NULL
    man
  })
  relabelled <- fx$source$conn
  relabelled$project_name <- "renamed"

  m <- ss_preview(fx$product$conn, sources = relabelled)
  expect_identical(unique(m$project), "renamed")
})

test_that("an unreadable source manifest stops with its own class", {
  fx <- ss_pair()
  empty <- ss_project("empty-source", prefix = "pe")

  expect_error(
    datom_sync_manifest(fx$product$conn,
                        sources = list(fx$source$conn, empty$conn)),
    class = "datom_edit_manifest_unreadable", inherit = FALSE
  )
})

test_that("sources must be connections, one per project", {
  fx <- ss_pair()
  expect_error(
    datom_sync_manifest(fx$product$conn, sources = list("not a conn")),
    class = "datom_not_a_conn"
  )
  expect_error(
    datom_sync_manifest(fx$product$conn,
                        sources = list(fx$source$conn, fx$source$conn)),
    class = "datom_edit_conn_duplicate"
  )
})


# === "no set yet" versus "could not look" =====================================

test_that("a set probe that fails is an error, not a first version", {
  fx <- ss_pair()
  local_mocked_bindings(
    .datom_storage_exists = function(conn, key) stop("storage unreachable")
  )

  expect_error(
    datom_sync_manifest(fx$product$conn, sources = fx$source$conn),
    "storage unreachable"
  )
})

test_that("a stored set that cannot be read is an error, not a first version", {
  # The probe says the set is there; the read then fails. Catching that failure
  # would report every table as new -- the defect this test exists for.
  fx <- ss_pair()
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm)))

  real_read <- .datom_storage_read_json
  set_key <- .datom_artifact_meta_key("liver-set", "metadata")
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      if (identical(key, set_key)) stop("storage unreachable")
      real_read(conn, key)
    }
  )

  expect_error(
    datom_sync_manifest(fx$product$conn, sources = fx$source$conn),
    "storage unreachable"
  )
})


# === it saves nothing =========================================================

test_that("the preview writes nothing to storage or git", {
  # R2.9.
  fx <- ss_pair()
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm)))
  ss_table(fx$source, "lb", 6L)

  snapshot <- function() {
    files <- fs::dir_ls(c(fx$product$store_dir, fx$source$store_dir,
                          fx$product$repo_dir), recurse = TRUE, all = TRUE,
                        type = "file")
    files <- files[!grepl("/\\.git/", files)]
    stats::setNames(tools::md5sum(files), files)
  }
  head_of <- function(fx) {
    as.character(git2r::revparse_single(fx$repo, "HEAD")$sha)
  }

  before <- snapshot()
  heads <- c(head_of(fx$product), head_of(fx$source))

  ss_preview(fx$product$conn, sources = fx$source$conn)

  expect_identical(snapshot(), before)
  expect_identical(c(head_of(fx$product), head_of(fx$source)), heads)
})


# === a set built from a stored set ============================================

test_that("a set pinning a stored set writes, reads back, validates and syncs", {
  # AC17. Three real projects, no mocks: `imported` holds a table; `inner-proj`
  # is a product repo whose set pins it; `outer-proj` is a product repo whose set
  # pins the inner SET. Then the inner set moves, and the outer preview has to
  # see it as `changed`.
  source <- ss_project("imported", prefix = "ps")
  inner <- ss_project("inner-proj", "inner-set", "pi")
  outer <- ss_project("outer-proj", "outer-set", "po")

  v_dm <- ss_table(source, "dm", 3L)
  ss_write_set(inner, list(ss_member(source, "dm", v_dm)))
  v_inner <- datom_get_set(inner$conn, "inner-set")$version

  pin <- datom_member(inner$conn, "inner-set", v_inner,
                      tags = list(type = "input"))
  expect_identical(pin$id$kind, "set")
  ss_write_set(outer, list(pin))

  got <- datom_get_set(outer$conn, "outer-set")
  expect_length(got$members, 1L)
  expect_identical(got$members[[1L]]$id$project, "inner-proj")
  expect_identical(got$members[[1L]]$id$name, "inner-set")
  expect_identical(got$members[[1L]]$id$kind, "set")
  expect_identical(got$members[[1L]]$id$version, v_inner)

  # Fetching a set member hands back the inner set, not its data.
  fetched <- suppressMessages(datom_fetch_member(inner$conn, got, "inner-set"))
  expect_s3_class(fetched, "datom_set")
  expect_identical(fetched$version, v_inner)

  outer_check <- suppressMessages(datom_validate(outer$conn))
  expect_true(outer_check$valid)
  inner_check <- suppressMessages(datom_validate(inner$conn))
  expect_true(inner_check$valid)

  # The inner set moves: a new table joins it.
  v_lb <- ss_table(source, "lb", 4L)
  ss_write_set(inner, list(ss_member(source, "dm", v_dm),
                           ss_member(source, "lb", v_lb)))
  v_inner_2 <- datom_get_set(inner$conn, "inner-set")$version
  expect_false(identical(v_inner_2, v_inner))

  m <- ss_preview(outer$conn, sources = inner$conn)
  expect_identical(nrow(m), 1L)
  expect_identical(m$project, "inner-proj")
  expect_identical(m$name, "inner-set")
  expect_identical(m$kind, "set")
  expect_identical(m$status, "changed")
  expect_identical(m$version_from, v_inner)
  expect_identical(m$version_to, v_inner_2)
})


# ==============================================================================
# Applying a preview: `datom_sync(conn, manifest, sources = , tags = , x = )`.
#
# Apply writes nothing, so "did it act" is read off the returned set and its
# edit log, and "did it stop before any read" is tested by making every storage
# read fail after the preview is built -- a check placed after a read would then
# surface as that failure instead of its own class.
# ==============================================================================

ss_apply <- function(...) suppressMessages(datom_sync(...))

ss_ids <- function(x) {
  do.call(rbind, lapply(x$members, function(m) {
    data.frame(project = m$id$project, name = m$id$name, kind = m$id$kind,
               version = m$id$version, stringsAsFactors = FALSE)
  }))
}

ss_no_reads <- function(env = parent.frame()) {
  local_mocked_bindings(
    .datom_storage_exists = function(conn, key) stop("no read expected"),
    .datom_storage_read_json = function(conn, key) stop("no read expected"),
    .env = env
  )
}

# The usual pair with a stored set: dm unchanged, lb changed, ex new.
ss_moved <- function(env = parent.frame()) {
  fx <- ss_pair(env = env)
  ss_write_set(fx$product, list(
    ss_member(fx$source, "dm", fx$v_dm),
    ss_member(fx$source, "lb", fx$v_lb,
              tags = list(type = "input", domain = c("lab", "safety")))
  ))
  fx$new_lb <- ss_table(fx$source, "lb", 6L)
  fx$v_ex <- ss_table(fx$source, "ex", 2L)
  fx$m <- ss_preview(fx$product$conn, sources = fx$source$conn)
  fx
}


# === which context the call is in =============================================

test_that("apply's new arguments come last, so positional calls keep working", {
  expect_identical(
    names(formals(datom_sync)),
    c("conn", "manifest", "continue_on_error", "sources", "tags", "x")
  )
})

test_that("a set-shaped frame without sources gets the sources refusal", {
  # The branch sits above the file-column check, or this would be told it is
  # missing `file` and `format`.
  fx <- ss_moved()
  expect_error(datom_sync(fx$product$conn, fx$m),
               class = "datom_import_on_product")
})

test_that("an ordinary repo given sources, tags or x stops before the column check", {
  fx <- ss_moved()
  conn <- fx$source$conn
  expect_error(datom_sync(conn, fx$m, sources = fx$product$conn),
               class = "datom_sync_sources_on_ordinary")
  expect_error(datom_sync(conn, fx$m, tags = list(type = "input")),
               class = "datom_sync_sources_on_ordinary")
  err <- expect_error(
    datom_sync(conn, fx$m, x = .datom_empty_set("s", "p")),
    class = "datom_sync_sources_on_ordinary"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "`x`", fixed = TRUE)
})

test_that("apply on a product repo that names no set stops, before any read", {
  # The preview's refusal is tested above; this is apply's own call to it.
  # Without it apply would read storage for a set with no name.
  fx <- ss_moved()
  cfg_path <- fs::path(fx$product$repo_dir, ".datom", "project.yaml")
  cfg <- yaml::read_yaml(cfg_path)
  cfg$set <- NULL
  yaml::write_yaml(cfg, cfg_path)
  ss_no_reads()

  expect_error(
    datom_sync(fx$product$conn, fx$m, sources = fx$source$conn),
    class = "datom_set_undeclared"
  )
})

test_that("a product repo given continue_on_error stops rather than ignoring it", {
  fx <- ss_moved()
  expect_error(
    datom_sync(fx$product$conn, fx$m, continue_on_error = TRUE,
               sources = fx$source$conn),
    class = "datom_sync_file_arg_on_product"
  )
})


# === what apply does ==========================================================

test_that("first version: every row joins a versionless set with the declared name", {
  # AC7, apply half.
  fx <- ss_pair()
  m <- ss_preview(fx$product$conn, sources = fx$source$conn)
  x <- ss_apply(fx$product$conn, m, sources = fx$source$conn)

  expect_s3_class(x, "datom_set")
  expect_identical(x$name, "liver-set")
  expect_identical(x$project, "liver-safety")
  expect_null(x$version)
  expect_null(x$data_sha)

  ids <- ss_ids(x)
  expect_identical(ids$name, c("dm", "lb"))
  expect_identical(ids$project, c("imported", "imported"))
  expect_identical(ids$version, c(fx$v_dm, fx$v_lb))
  expect_true(all(vapply(x$members, function(mm) {
    identical(mm$tags, list(type = "input"))
  }, logical(1L))))
  expect_true(all(vapply(x$members, function(mm) is.function(mm$fetch),
                         logical(1L))))
})

test_that("new rows add, changed rows repoint, every other row does nothing", {
  # R3.2 and P3: the repointed member's labels are identical before and after.
  fx <- ss_moved()
  before <- datom_get_set(fx$product$conn, "liver-set")
  lb_tags <- before$members[[2L]]$tags

  x <- ss_apply(fx$product$conn, fx$m, sources = fx$source$conn)

  ids <- ss_ids(x)
  expect_identical(ids$name, c("dm", "lb", "ex"))
  expect_identical(ids$version, c(fx$v_dm, fx$new_lb, fx$v_ex))
  expect_identical(x$members[[2L]]$tags, lb_tags)
  expect_identical(x$members[[1L]], before$members[[1L]])
  expect_identical(x$members[[3L]]$tags, list(type = "input"))

  # The repointed member's link follows its record.
  expect_identical(attr(x$members[[2L]]$fetch, "datom_member")$id$version,
                   fx$new_lb)

  edits <- attr(x, "datom_edits")
  # In the preview's row order, which sorts names.
  expect_identical(edits$action, c("add", "repoint"))
  expect_identical(edits$name, c("ex", "lb"))
  expect_identical(edits$from, c(NA_character_, fx$v_lb))
  expect_identical(edits$to, c(fx$v_ex, fx$new_lb))

  expect_null(x$version)
  expect_null(x$data_sha)
})

test_that("a row subset changes exactly the members its rows name", {
  # P2 and AC4.
  fx <- ss_moved()
  x <- ss_apply(fx$product$conn, subset(fx$m, name != "lb"),
                sources = fx$source$conn)

  ids <- ss_ids(x)
  expect_identical(ids$name, c("dm", "lb", "ex"))
  expect_identical(ids$version, c(fx$v_dm, fx$v_lb, fx$v_ex))
  expect_identical(attr(x, "datom_edits")$action, "add")
})

test_that("a hand-built frame with the right columns applies", {
  # AC4: columns and values are checked, never where the frame came from.
  fx <- ss_moved()
  frame <- data.frame(
    project = "imported", name = "lb", kind = "table",
    version_from = fx$v_lb, version_to = fx$new_lb, status = "changed",
    stringsAsFactors = TRUE
  )
  x <- ss_apply(fx$product$conn, frame, sources = fx$source$conn)
  expect_identical(ss_ids(x)$version, c(fx$v_dm, fx$new_lb))
  # A repoint alone moves the set off the version it was read as.
  expect_null(x$version)
  expect_null(x$data_sha)
})

test_that("tags label the new members only", {
  # R3.3.
  fx <- ss_moved()
  lb_tags <- datom_get_set(fx$product$conn, "liver-set")$members[[2L]]$tags
  x <- ss_apply(fx$product$conn, fx$m, sources = fx$source$conn,
                tags = list(type = "input", origin = "month-4"))

  expect_identical(x$members[[3L]]$tags,
                   list(type = "input", origin = "month-4"))
  expect_identical(x$members[[2L]]$tags, lb_tags)
})

test_that("malformed tags stop before any read", {
  fx <- ss_moved()
  ss_no_reads()
  expect_error(
    datom_sync(fx$product$conn, fx$m, sources = fx$source$conn,
               tags = list(type = 1)),
    "tags"
  )
})

test_that("apply saves nothing and says so", {
  # AC8 and R2.9's counterpart for apply (I2).
  fx <- ss_moved()

  snapshot <- function() {
    files <- fs::dir_ls(c(fx$product$store_dir, fx$source$store_dir,
                          fx$product$repo_dir), recurse = TRUE, all = TRUE,
                        type = "file")
    files <- files[!grepl("/\\.git/", files)]
    stats::setNames(tools::md5sum(files), files)
  }
  head_of <- function(f) as.character(git2r::revparse_single(f$repo, "HEAD")$sha)

  before <- snapshot()
  heads <- c(head_of(fx$product), head_of(fx$source))

  msg <- ss_messages(datom_sync(fx$product$conn, fx$m,
                                sources = fx$source$conn))

  expect_identical(snapshot(), before)
  expect_identical(c(head_of(fx$product), head_of(fx$source)), heads)

  expect_match(msg, "Applied 2 rows: 1 added, 1 repointed.", fixed = TRUE)
  expect_match(msg, "ex  added at", fixed = TRUE)
  expect_match(msg, "Nothing has been written. Write the set with `datom_write_set(conn, x)`.",
               fixed = TRUE)
  expect_identical(lengths(regmatches(msg, gregexpr("Nothing has been written",
                                                    msg))), 1L)
})

test_that("with no row to apply it says so, and returns the set unedited", {
  fx <- ss_moved()
  keep <- fx$m[fx$m$status == "unchanged", , drop = FALSE]
  before <- datom_get_set(fx$product$conn, "liver-set")

  msg <- ss_messages(x <- datom_sync(fx$product$conn, keep,
                                     sources = fx$source$conn))

  expect_match(msg, "Nothing to apply: no new or changed rows.", fixed = TRUE)
  expect_no_match(msg, "Nothing has been written")
  expect_identical(x$version, before$version)
  expect_null(attr(x, "datom_edits"))
})

test_that("the next set write's commit message names the adds and repoints", {
  # AC8 and R3.7.
  fx <- ss_moved()
  x <- ss_apply(fx$product$conn, fx$m, sources = fx$source$conn)
  ss_write_set(fx$product, x)

  msg <- git2r::commits(fx$product$repo, n = 1L)[[1L]]$message
  expect_match(msg, "Update liver-set: add 1 member, repoint 1 member",
               fixed = TRUE)
  expect_match(msg, paste0("ex  added at ", fx$v_ex), fixed = TRUE)
  expect_match(msg, paste0("lb  ", fx$v_lb, " -> ", fx$new_lb), fixed = TRUE)
})

test_that("apply, write, preview again: nothing new or changed", {
  # P1 (idempotence) and P5 (the round trip returns what the preview promised).
  fx <- ss_moved()
  promised <- fx$m[fx$m$status %in% c("new", "changed", "unchanged"), ]

  x <- ss_apply(fx$product$conn, fx$m, sources = fx$source$conn)
  ss_write_set(fx$product, x)

  got <- ss_ids(datom_get_set(fx$product$conn, "liver-set"))
  key <- function(p, n, v) paste(p, n, v)
  expect_setequal(key(got$project, got$name, got$version),
                  key(promised$project, promised$name, promised$version_to))

  again <- ss_preview(fx$product$conn, sources = fx$source$conn)
  expect_false(any(again$status %in% c("new", "changed")))
  expect_true(all(again$status == "unchanged"))
})

test_that("x applies the preview to a set in hand, and keeps what the set holds", {
  # R3.5, the top-up case: an output added in memory survives the sync.
  fx <- ss_moved()
  v_out <- ss_table(fx$product, "liver_flags", 3L)
  x <- datom_get_set(fx$product$conn, "liver-set")
  x <- suppressMessages(datom_add_member(
    x, "liver_flags", v_out, tags = list(type = "output"),
    conn = fx$product$conn
  ))

  x <- ss_apply(fx$product$conn, fx$m, sources = fx$source$conn, x = x)

  expect_identical(ss_ids(x)$name, c("dm", "lb", "liver_flags", "ex"))
  expect_identical(attr(x, "datom_edits")$action, c("add", "add", "repoint"))
})

test_that("x may be a freshly assembled set", {
  fx <- ss_pair()
  m <- ss_preview(fx$product$conn, sources = fx$source$conn)
  x <- ss_apply(fx$product$conn, m, sources = fx$source$conn,
                x = datom_assemble_set(fx$product$conn))

  expect_null(x$name)
  expect_identical(ss_ids(x)$name, c("dm", "lb"))

  ss_write_set(fx$product, x)
  expect_identical(ss_ids(datom_get_set(fx$product$conn, "liver-set"))$name,
                   c("dm", "lb"))
})

test_that("x must be a set", {
  fx <- ss_moved()
  ss_no_reads()
  expect_error(
    datom_sync(fx$product$conn, fx$m, sources = fx$source$conn,
               x = list(members = list())),
    class = "datom_not_a_set"
  )
})

test_that("a full preview with not_checked rows applies without their project", {
  # Only new and changed rows need a connection.
  fx <- ss_pair()
  other <- ss_project("imported-b", prefix = "pb")
  v_b <- ss_table(other, "ae", 5L)
  ss_write_set(fx$product, list(ss_member(fx$source, "dm", fx$v_dm),
                                ss_member(other, "ae", v_b)))
  m <- ss_preview(fx$product$conn, sources = fx$source$conn)
  expect_true("not_checked" %in% m$status)

  x <- ss_apply(fx$product$conn, m, sources = fx$source$conn)
  expect_identical(ss_ids(x)$name, c("dm", "ae", "lb"))
})

test_that("a set member moved by sync writes, reads back and validates", {
  # AC17, apply half: the inner set moves and the outer set follows it.
  source <- ss_project("imported", prefix = "ps")
  inner <- ss_project("inner-proj", "inner-set", "pi")
  outer <- ss_project("outer-proj", "outer-set", "po")

  v_dm <- ss_table(source, "dm", 3L)
  ss_write_set(inner, list(ss_member(source, "dm", v_dm)))

  m <- ss_preview(outer$conn, sources = inner$conn)
  expect_identical(m$kind, "set")
  ss_write_set(outer, ss_apply(outer$conn, m, sources = inner$conn))

  v_lb <- ss_table(source, "lb", 4L)
  ss_write_set(inner, list(ss_member(source, "dm", v_dm),
                           ss_member(source, "lb", v_lb)))
  v_inner_2 <- datom_get_set(inner$conn, "inner-set")$version

  m <- ss_preview(outer$conn, sources = inner$conn)
  expect_identical(m$status, "changed")
  ss_write_set(outer, ss_apply(outer$conn, m, sources = inner$conn))

  got <- datom_get_set(outer$conn, "outer-set")
  expect_identical(got$members[[1L]]$id$kind, "set")
  expect_identical(got$members[[1L]]$id$version, v_inner_2)
  expect_true(suppressMessages(datom_validate(outer$conn))$valid)
})


# === the set moved since the preview ==========================================

test_that("a changed row whose member has moved stops as stale", {
  # AC9, first half.
  fx <- ss_moved()
  newest <- ss_table(fx$source, "lb", 7L)
  x <- datom_get_set(fx$product$conn, "liver-set")
  x <- suppressMessages(datom_update_members(x, fx$source$conn, member = "lb",
                                             version_to = newest))
  ss_write_set(fx$product, x)

  err <- expect_error(
    datom_sync(fx$product$conn, fx$m, sources = fx$source$conn),
    class = "datom_sync_manifest_stale", inherit = FALSE
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "lb in imported", fixed = TRUE)
  expect_match(msg, substr(newest, 1L, 8L), fixed = TRUE)
  expect_match(msg, "datom_sync_manifest(conn, sources = )", fixed = TRUE)
})

test_that("a new row whose artifact the set has since gained stops as stale", {
  # AC9, second half, and open point B.
  fx <- ss_moved()
  x <- datom_get_set(fx$product$conn, "liver-set")
  x <- suppressMessages(datom_add_member(x, "ex", fx$v_ex,
                                         conn = fx$source$conn))
  ss_write_set(fx$product, x)

  err <- expect_error(
    datom_sync(fx$product$conn, fx$m, sources = fx$source$conn),
    class = "datom_sync_manifest_stale", inherit = FALSE
  )
  expect_match(cli::ansi_strip(conditionMessage(err)),
               "ex in imported: the preview says new", fixed = TRUE)
})

test_that("a changed row whose member was removed, or doubled, stops as stale", {
  fx <- ss_moved()
  lb <- fx$m[fx$m$name == "lb", , drop = FALSE]

  x <- datom_get_set(fx$product$conn, "liver-set")
  gone <- suppressMessages(datom_remove_members(x, member = "lb"))
  expect_error(
    datom_sync(fx$product$conn, lb, sources = fx$source$conn, x = gone),
    class = "datom_sync_manifest_stale", inherit = FALSE
  )

  doubled <- suppressMessages(datom_add_member(
    x, "lb", fx$new_lb, tags = list(release = "live"), conn = fx$source$conn
  ))
  err <- expect_error(
    datom_sync(fx$product$conn, lb, sources = fx$source$conn, x = doubled),
    class = "datom_sync_manifest_stale", inherit = FALSE
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "now holds 2", fixed = TRUE)
  # The set was passed, so rebuilding the preview alone would not help.
  expect_match(msg, "without `x`", fixed = TRUE)
})

test_that("a stale row stops the whole call before any member is read", {
  fx <- ss_moved()
  x <- datom_get_set(fx$product$conn, "liver-set")
  x <- suppressMessages(datom_remove_members(x, member = "lb"))

  ss_no_reads()
  expect_error(
    datom_sync(fx$product$conn, fx$m, sources = fx$source$conn, x = x),
    class = "datom_sync_manifest_stale", inherit = FALSE
  )
})


# === a row that disagrees with the artifact ===================================

test_that("a changed row whose kind disagrees with the member stops, before any read", {
  fx <- ss_moved()
  lb <- fx$m[fx$m$name == "lb", , drop = FALSE]
  lb$kind <- "set"
  x <- datom_get_set(fx$product$conn, "liver-set")

  ss_no_reads()
  err <- expect_error(
    datom_sync(fx$product$conn, lb, sources = fx$source$conn, x = x),
    class = "datom_sync_kind_mismatch", inherit = FALSE
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "\"set\"", fixed = TRUE)
})

test_that("a new row whose kind disagrees with the snapshot stops", {
  fx <- ss_moved()
  ex <- fx$m[fx$m$name == "ex", , drop = FALSE]
  ex$kind <- "set"

  expect_error(
    datom_sync(fx$product$conn, ex, sources = fx$source$conn),
    class = "datom_sync_kind_mismatch", inherit = FALSE
  )
})

test_that("a new row read through a mislabelled connection stops as a project mismatch", {
  # The snapshot records the project that wrote it, and that is what the row's
  # project is checked against -- the connection's label only routed the read.
  fx <- ss_moved()
  relabelled <- fx$source$conn
  relabelled$project_name <- "renamed"
  ex <- fx$m[fx$m$name == "ex", , drop = FALSE]
  ex$project <- "renamed"

  err <- expect_error(
    datom_sync(fx$product$conn, ex, sources = relabelled),
    class = "datom_update_project_mismatch", inherit = FALSE
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "Adding", fixed = TRUE)
  expect_match(msg, "\"imported\"", fixed = TRUE)
})

test_that("a new row pinning a version that does not exist stops", {
  fx <- ss_moved()
  ex <- fx$m[fx$m$name == "ex", , drop = FALSE]
  ex$version_to <- strrep("0", 64L)

  expect_error(
    ss_apply(fx$product$conn, ex, sources = fx$source$conn),
    "not found"
  )
})


# === refusals before any read =================================================

test_that("the set's own project in sources stops apply, before any read", {
  fx <- ss_moved()
  ss_no_reads()
  err <- expect_error(
    datom_sync(fx$product$conn, fx$m,
               sources = list(fx$source$conn, fx$product$conn)),
    class = "datom_sync_own_project_source"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)),
               "sync does not map or move them", fixed = TRUE)
})

test_that("a row to apply whose project has no connection stops, before any read", {
  fx <- ss_moved()
  other <- ss_project("imported-b", prefix = "pb")
  frame <- rbind(fx$m, data.frame(
    project = "imported-c", name = "ae", kind = "table", version_from = NA,
    version_to = strrep("a", 64L), status = "new", stringsAsFactors = FALSE
  ))

  ss_no_reads()
  err <- expect_error(
    datom_sync(fx$product$conn, frame,
               sources = list(fx$source$conn, other$conn)),
    class = "datom_sync_source_missing"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "imported-c")
})

test_that("two rows to apply for one artifact stop, before any read", {
  fx <- ss_moved()
  frame <- rbind(fx$m, fx$m[fx$m$name == "ex", , drop = FALSE])

  ss_no_reads()
  err <- expect_error(
    datom_sync(fx$product$conn, frame, sources = fx$source$conn),
    class = "datom_sync_manifest_duplicate_row"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "ex in imported",
               fixed = TRUE)
})

test_that("duplicate rows among statuses that do nothing are harmless", {
  fx <- ss_moved()
  frame <- rbind(fx$m, fx$m[fx$m$name == "dm", , drop = FALSE])
  x <- ss_apply(fx$product$conn, frame, sources = fx$source$conn)
  expect_identical(ss_ids(x)$name, c("dm", "lb", "ex"))
})

test_that("sources must be connections, one per project, for apply too", {
  fx <- ss_moved()
  ss_no_reads()
  expect_error(
    datom_sync(fx$product$conn, fx$m, sources = list("not a conn")),
    class = "datom_not_a_conn"
  )
  expect_error(
    datom_sync(fx$product$conn, fx$m,
               sources = list(fx$source$conn, fx$source$conn)),
    class = "datom_edit_conn_duplicate"
  )
})

test_that("a set probe that fails is an error at apply, not a first version", {
  fx <- ss_moved()
  local_mocked_bindings(
    .datom_storage_exists = function(conn, key) stop("storage unreachable")
  )
  expect_error(
    datom_sync(fx$product$conn, fx$m, sources = fx$source$conn),
    "storage unreachable"
  )
})


# === the frame's shape and values =============================================

test_that("a frame that is not a set preview stops, before any read", {
  fx <- ss_moved()
  ss_no_reads()
  conn <- fx$product$conn
  src <- fx$source$conn

  expect_error(datom_sync(conn, list(a = 1), sources = src),
               class = "datom_sync_manifest_invalid")
  # A plain list carrying every column is still not a frame.
  err <- expect_error(datom_sync(conn, as.list(fx$m), sources = src),
                      class = "datom_sync_manifest_invalid")
  expect_match(cli::ansi_strip(conditionMessage(err)), "must be a data frame")

  err <- expect_error(
    datom_sync(conn, fx$m[, c("project", "name")], sources = src),
    class = "datom_sync_manifest_invalid"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "version_to")

  file_frame <- data.frame(
    name = "dm", file = "dm.csv", format = "csv",
    original_file_sha = strrep("a", 64L), status = "new",
    stringsAsFactors = FALSE
  )
  err <- expect_error(datom_sync(conn, file_frame, sources = src),
                      class = "datom_sync_manifest_invalid")
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "file-import manifest")
  expect_match(msg, "datom_sync_manifest(conn, sources = )", fixed = TRUE)
})

test_that("each unusable value on a row to apply stops, naming the row", {
  fx <- ss_moved()
  ss_no_reads()
  conn <- fx$product$conn
  src <- fx$source$conn
  lb <- fx$m[fx$m$name == "lb", , drop = FALSE]
  ex <- fx$m[fx$m$name == "ex", , drop = FALSE]

  refuse <- function(frame, pattern) {
    err <- expect_error(datom_sync(conn, frame, sources = src),
                        class = "datom_sync_manifest_invalid")
    expect_match(cli::ansi_strip(conditionMessage(err)), pattern,
                 fixed = TRUE)
  }

  bad <- ex; bad$status <- "added"
  refuse(bad, "status is not one of")
  bad <- ex; bad$project <- ""
  refuse(bad, "project is empty")
  bad <- ex; bad$name <- NA_character_
  refuse(bad, "name is empty")
  bad <- ex; bad$kind <- "view"
  refuse(bad, "kind is not table or set")
  bad <- ex; bad$version_to <- substr(ex$version_to, 1L, 8L)
  refuse(bad, "row 1 (ex): version_to is not a full 64-character version")
  bad <- lb; bad$version_from <- substr(lb$version_from, 1L, 8L)
  refuse(bad, "version_from is not a full 64-character version")
  bad <- lb; bad$version_to <- lb$version_from
  refuse(bad, "version_to equals its version_from")
})

test_that("values on rows that do nothing are not checked", {
  fx <- ss_moved()
  frame <- fx$m
  frame$version_to[frame$status == "unchanged"] <- "junk"
  frame$kind[frame$status == "unchanged"] <- "view"
  x <- ss_apply(fx$product$conn, frame, sources = fx$source$conn)
  expect_identical(ss_ids(x)$name, c("dm", "lb", "ex"))
})
