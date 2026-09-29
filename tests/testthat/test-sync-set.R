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

test_that("apply still refuses a product repo until it learns sources", {
  fx <- ss_pair()
  frame <- data.frame(
    name = "dm", file = "dm.csv", format = "csv",
    original_file_sha = strrep("a", 64L), status = "new",
    stringsAsFactors = FALSE
  )
  err <- expect_error(datom_sync(fx$product$conn, frame),
                      class = "datom_import_on_product")
  # No route named that the verb does not take yet.
  expect_no_match(cli::ansi_strip(conditionMessage(err)), "sources =",
                  fixed = TRUE)
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
