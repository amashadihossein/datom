# Reading a set: the getter, the two kind refusals, the integrity gate, the
# representation normalization, and the member link.
#
# Most of these run against a real git repo, a real bare remote and a real local
# store with nothing mocked, because the claims are about the COMPOSITION --
# resolve, download, verify, parse, normalize, link -- rather than about any one
# function.
#
# FOUR THINGS BELOW ARE THE TESTS A NAIVE IMPLEMENTATION PASSES EVERYTHING ELSE
# WHILE FAILING.
#
#   * The integrity gate is proved with a DIFFERENT BUT VALID JSON document at
#     the payload's address. Garbage bytes would fail the parse too, so they
#     cannot show that the refusal came from the hash check.
#   * A missing `document_sha` must be an ERROR. Copying `parquet_sha`'s
#     `if (!is.null(x) && nzchar(x))` guard makes it a silent skip, and every
#     other test still passes.
#   * The read must not TIDY. `.datom_tidy_set_payload()` changes nothing on a
#     payload the write canonicalized, so a tidying read looks correct until a
#     repair re-uploads reshaped bytes over an object whose recorded hash
#     describes different bytes. The never-tidy tests therefore hand-write a
#     payload that is deliberately NOT in canonical form.
#   * The link's purity is asserted on the SERIALIZED BYTES. An
#     `environment(link)` check passes on the broken shape, because there the
#     connection sits one frame further up.


# --- fixture ------------------------------------------------------------------

#' Real product project: git repo + bare remote + local store + product config.
#'
#' Mirrors `local_set_project()` in `test-write-set.R`; duplicated because
#' testthat does not share definitions between test files. The connection carries
#' a fake PAT, which is what the link purity test looks for in the bytes.
local_get_set_project <- function(set_name = "product-a", env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)

  repo_dir <- fs::path(root, "repo")
  store_dir <- fs::path(root, "store")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, store_dir, bare_dir))

  git2r::init(bare_dir, bare = TRUE)
  repo <- git2r::init(repo_dir)
  git2r::config(repo, user.name = "Set Test", user.email = "set@test.com")
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
  conn$project_name <- "set-project"
  conn$github_pat <- "SUPER-SECRET-TOKEN-XYZ"

  write_product_config(repo_dir, "set-project", set_name)

  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir,
       repo = repo, set_name = set_name)
}

gs_data <- function(n = 3L) {
  data.frame(id = seq_len(n), val = letters[seq_len(n)],
             stringsAsFactors = FALSE)
}

# Write a table and return the version just minted, which is what a member pins.
gs_table <- function(fx, name, n = 3L) {
  suppressMessages(datom_write(fx$conn, data = gs_data(n), name = name))
  datom_history(fx$conn, name, short_hash = FALSE)$version[[1L]]
}

gs_write <- function(fx, members, ...) {
  suppressMessages(datom_write_set(fx$conn, members, ...))
}

# A set with one table member, written and ready to read.
gs_one_member_set <- function(fx, tags = list(description = "one member")) {
  version <- gs_table(fx, "dm")
  members <- list(datom_member(fx$conn, "dm", version,
                               tags = list(type = "input")))
  gs_write(fx, members, tags = tags)
  invisible(version)
}

# Located through the package's own path resolution, so a storage-layout change
# breaks the code rather than quietly passing a test that looks elsewhere.
gs_stored <- function(fx, key) .datom_local_path(fx$conn, key)

gs_payload_key <- function(fx, data_sha, name = fx$set_name) {
  .datom_artifact_payload_key(name, data_sha, "set")
}

gs_edit_json <- function(path, f) {
  doc <- jsonlite::read_json(path)
  jsonlite::write_json(f(doc), path, auto_unbox = TRUE, pretty = TRUE)
  invisible(path)
}

#' Put a hand-built payload at a set version's address and re-pin it.
#'
#' The only way to test what a reader does with a payload `datom_write_set()`
#' cannot produce -- an uncanonical spelling, a malformed `id`, a member pointing
#' at a set that does not exist. The recorded `document_sha` is updated to the new
#' bytes so the integrity gate passes and the test observes the behaviour it is
#' actually about; `data_sha` is deliberately left alone, which is also what shows
#' the read does not recompute it.
gs_replace_payload <- function(fx, data_sha, payload, name = fx$set_name) {
  path <- gs_stored(fx, gs_payload_key(fx, data_sha, name))
  jsonlite::write_json(payload, path, auto_unbox = TRUE, pretty = TRUE)

  gs_edit_json(
    gs_stored(fx, .datom_artifact_meta_key(name, "metadata")),
    function(doc) {
      doc$document_sha <- digest::digest(file = path, algo = "sha256")
      doc
    }
  )

  invisible(path)
}

# One member record as the payload holds it, built by hand.
gs_raw_member <- function(project = "set-project", name = "dm",
                          kind = "table", version = strrep("a", 64L),
                          tags = NULL) {
  m <- list(id = list(project = project, name = name, kind = kind,
                      version = version))
  if (!is.null(tags)) m$tags <- tags
  m
}


# === what comes back ==========================================================

test_that("a set reads back as the six identifying facts, classed datom_set", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  x <- datom_get_set(fx$conn, "product-a")

  expect_s3_class(x, "datom_set")
  # A single class name, matching datom_conn and datom_summary. "list" in the
  # vector would open *.list dispatch for no gain.
  expect_identical(class(x), "datom_set")
  expect_named(x, c("name", "project", "version", "data_sha", "tags", "members"))
  expect_identical(x$name, "product-a")
  expect_identical(x$project, "set-project")
})

test_that("version is the version RECORDED in the history, not a recomputed one", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  x <- datom_get_set(fx$conn, "product-a")

  expect_identical(
    x$version,
    datom_history(fx$conn, "product-a", short_hash = FALSE)$version[[1L]]
  )
})

test_that("an 8-character prefix returns the full recorded version", {
  # A set exists to be citable, so a caller who pinned a short version must be
  # able to say which version they actually got.
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  full <- datom_get_set(fx$conn, "product-a")$version
  short <- datom_get_set(fx$conn, "product-a", version = substr(full, 1L, 8L))

  expect_identical(short$version, full)
})

test_that("a pinned version reads that version's payload, not the current one", {
  fx <- local_get_set_project()
  v_dm <- gs_table(fx, "dm")
  v_lb <- gs_table(fx, "lb")

  first <- gs_write(fx, list(datom_member(fx$conn, "dm", v_dm)))
  gs_write(fx, list(datom_member(fx$conn, "dm", v_dm),
                    datom_member(fx$conn, "lb", v_lb)))

  old <- datom_get_set(fx$conn, "product-a", version = first$metadata_sha)
  current <- datom_get_set(fx$conn, "product-a")

  expect_length(old$members, 1L)
  expect_length(current$members, 2L)
  expect_identical(old$version, first$metadata_sha)
})

test_that("members is a flat, unnamed list in the payload's own order", {
  # Not name-keyed, and the reasons are all silent if got wrong: one name at two
  # versions is a legal pair of members, two projects may both hold a `dm`, and
  # R's `$` partial-matches on lists.
  fx <- local_get_set_project()
  v_dm <- gs_table(fx, "dm")
  v_lb <- gs_table(fx, "lb")
  gs_write(fx, list(datom_member(fx$conn, "lb", v_lb),
                    datom_member(fx$conn, "dm", v_dm)))

  x <- datom_get_set(fx$conn, "product-a")
  file_order <- vapply(
    jsonlite::read_json(fs::path(fx$repo_dir, "product-a", "set.json"))$members,
    function(m) m$id$name, character(1L)
  )

  expect_null(names(x$members))
  expect_identical(
    vapply(x$members, function(m) m$id$name, character(1L)),
    file_order
  )
})

test_that("set-level and member tags come back as the labels that were written", {
  fx <- local_get_set_project()
  version <- gs_table(fx, "dm")
  gs_write(
    fx,
    list(datom_member(fx$conn, "dm", version,
                      tags = list(type = "output",
                                  domain = c("safety", "labs")))),
    tags = list(description = "ADaM datasets", owner = "stats")
  )

  x <- datom_get_set(fx$conn, "product-a")

  # A single label is one string, several are a character vector: two shapes in
  # R, one meaning in the document.
  expect_identical(x$tags$description, "ADaM datasets")
  expect_identical(x$members[[1L]]$tags$type, "output")
  expect_identical(x$members[[1L]]$tags$domain, c("labs", "safety"))
})

test_that("a set with no tags carries no tags key, and an untagged member none either", {
  # The presence axis is never invented: absent stays absent, not character(0)
  # and not NA.
  fx <- local_get_set_project()
  version <- gs_table(fx, "dm")
  gs_write(fx, list(datom_member(fx$conn, "dm", version)))

  x <- datom_get_set(fx$conn, "product-a")

  expect_null(x$tags)
  expect_false("tags" %in% names(x$members[[1L]]))
})

test_that("a set reads with no git clone at all (AC1a)", {
  # Storage-only readers are the primary consumer of a set. Nothing on this path
  # may touch conn$path.
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  reader <- fx$conn
  reader$path <- NULL
  reader$role <- "reader"

  x <- datom_get_set(reader, "product-a")

  expect_length(x$members, 1L)
  expect_identical(x$name, "product-a")
})

test_that("the arguments are validated, and there are only three of them", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  expect_error(datom_get_set(list(), "product-a"), "datom_conn")
  expect_error(datom_get_set(fx$conn, "../escape"), "must start with a letter")
  expect_error(
    datom_get_set(fx$conn, "product-a", version = strrep("f", 64L)),
    "not found in history"
  )
  # `context` and `...` are dead parameters on datom_read(); a new export does
  # not inherit them.
  expect_named(formals(datom_get_set), c("conn", "name", "version"))
})


# === the two kind refusals ====================================================
#
# Both directions of one invariant, so both full messages are asserted: the word
# selection also picks which verb is suggested, and without the converse a
# healthy table read as a set is reported as a missing payload.

test_that("datom_read() on a set aborts pointing at datom_get_set() (AC6)", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  err <- expect_error(
    datom_read(fx$conn, "product-a"),
    class = "datom_artifact_kind_conflict"
  )
  expect_match(conditionMessage(err), '"product-a" is a set, not a table\\.')
  expect_match(conditionMessage(err), "datom_get_set")
})

test_that("datom_get_set() on a table aborts pointing at datom_read() (AC14)", {
  fx <- local_get_set_project()
  gs_table(fx, "dm")

  err <- expect_error(
    datom_get_set(fx$conn, "dm"),
    class = "datom_artifact_kind_conflict"
  )
  expect_match(conditionMessage(err), '"dm" is a table, not a set\\.')
  expect_match(conditionMessage(err), "datom_read")
})

test_that("the read-side wording is selected by operation, and the write side is unchanged", {
  current <- list(kind = "set")

  read_err <- expect_error(
    .datom_check_artifact_kind(current, "p", "table", operation = "read"),
    class = "datom_artifact_kind_conflict"
  )
  write_err <- expect_error(
    .datom_check_artifact_kind(current, "p", "table"),
    class = "datom_artifact_kind_conflict"
  )

  expect_match(conditionMessage(read_err), "is a set, not a table")
  expect_match(conditionMessage(read_err), "datom_get_set")
  expect_match(conditionMessage(write_err), "already exists in this project")
  expect_match(conditionMessage(write_err), "datom_write_set")
  # One condition class for one invariant: a second would let a test key on one
  # direction only.
  expect_identical(class(read_err)[[1L]], class(write_err)[[1L]])
})

test_that("a matching kind passes at both operations, and an absent kind reads as table", {
  expect_silent(
    .datom_check_artifact_kind(list(kind = "set"), "p", "set", operation = "read")
  )
  expect_silent(
    .datom_check_artifact_kind(list(data_sha = "x"), "dm", "table",
                              operation = "read")
  )
  expect_silent(.datom_check_artifact_kind(NULL, "dm", "set", operation = "read"))
})


# === the integrity gate =======================================================

test_that("a different but valid payload at the same address is refused before parsing (AC28a)", {
  # Valid JSON on purpose: garbage bytes would fail the parse too, so they could
  # not show that the refusal came from the hash check.
  fx <- local_get_set_project()
  gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  imposter <- gs_stored(fx, gs_payload_key(fx, x$data_sha))
  jsonlite::write_json(list(members = list(gs_raw_member())), imposter,
                       auto_unbox = TRUE, pretty = TRUE)

  err <- expect_error(
    datom_get_set(fx$conn, "product-a"),
    class = "datom_set_integrity_failure"
  )
  expect_match(conditionMessage(err), "document_sha")
  expect_match(conditionMessage(err), "Do not trust this set")
})

test_that("a version recording no document_sha is an error, not a skipped check (AC28b)", {
  # The half a naive copy of .datom_read_parquet()'s guard gets wrong: its
  # skip-on-absent branch is a grace for metadata written before parquet_sha
  # existed, and a set has no such population.
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  gs_edit_json(
    gs_stored(fx, .datom_artifact_meta_key("product-a", "metadata")),
    function(doc) doc[names(doc) != "document_sha"]
  )

  expect_error(
    datom_get_set(fx$conn, "product-a"),
    class = "datom_set_document_sha_missing"
  )
})

test_that("an empty document_sha is refused the same way as an absent one (AC28b)", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  gs_edit_json(
    gs_stored(fx, .datom_artifact_meta_key("product-a", "metadata")),
    function(doc) {
      doc$document_sha <- ""
      doc
    }
  )

  expect_error(
    datom_get_set(fx$conn, "product-a"),
    class = "datom_set_document_sha_missing"
  )
})

test_that("a pinned version whose history entry records no document_sha is refused (AC28b)", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)
  version <- datom_get_set(fx$conn, "product-a")$version

  gs_edit_json(
    gs_stored(fx, .datom_artifact_meta_key("product-a", "version_history")),
    function(doc) lapply(doc, function(e) e[names(e) != "document_sha"])
  )

  expect_error(
    datom_get_set(fx$conn, "product-a", version = version),
    class = "datom_set_document_sha_missing"
  )
})

test_that("data_sha is not recomputed from the parsed payload", {
  # It is the address the payload was fetched from, so recomputing catches
  # nothing document_sha did not -- and it would refuse a payload a newer datom
  # wrote, because the sv1 encoder aborts on a top-level key it does not know.
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  gs_replace_payload(fx, x$data_sha, list(
    tags = list(description = "edited by hand"),
    members = list(gs_raw_member(version = version)),
    future_payload_field = "written by a newer datom"
  ))

  y <- datom_get_set(fx$conn, "product-a")

  expect_identical(y$data_sha, x$data_sha)
  expect_identical(y$tags$description, "edited by hand")
})


# === representation normalization, and nothing more ===========================

test_that("the three R shapes of one JSON string array become one character vector", {
  expect_identical(.datom_read_string_array(list("a", "b")), c("a", "b"))
  expect_identical(.datom_read_string_array(list("a")), "a")
  expect_identical(.datom_read_string_array("a"), "a")
  expect_identical(.datom_read_string_array(c("a", "b")), c("a", "b"))
})

test_that("normalization preserves order and count -- it does not canonicalize", {
  expect_identical(.datom_read_string_array(list("b", "a", "b")),
                   c("b", "a", "b"))
})

test_that("anything that is not an all-text array is returned untouched", {
  expect_identical(.datom_read_string_array(list(1, 2)), list(1, 2))
  expect_identical(.datom_read_string_array(list("a", 2)), list("a", 2))
  expect_identical(.datom_read_string_array(list(k = "a")), list(k = "a"))
  expect_identical(.datom_read_string_array(list()), list())
  expect_null(.datom_read_string_array(NULL))
})

test_that("a one-element array in a stored payload comes back as one string", {
  # Written by hand because the writer unboxes: `["a"]` is what another producer
  # emits for a single label, and it means the same thing.
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  path <- gs_stored(fx, gs_payload_key(fx, x$data_sha))
  writeLines(sprintf(
    '{"tags":{"description":["one"]},"members":[{"id":{"project":"set-project","name":"dm","kind":"table","version":"%s"},"tags":{"domain":["labs"]}}]}',
    version
  ), path)
  gs_edit_json(
    gs_stored(fx, .datom_artifact_meta_key("product-a", "metadata")),
    function(doc) {
      doc$document_sha <- digest::digest(file = path, algo = "sha256")
      doc
    }
  )

  y <- datom_get_set(fx$conn, "product-a")

  expect_identical(y$tags$description, "one")
  expect_identical(y$members[[1L]]$tags$domain, "labs")
})

test_that("an empty tag map in the document stays an empty tag map", {
  # Dropping it would remove a key the document contains, which is not a spelling
  # difference.
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  path <- gs_stored(fx, gs_payload_key(fx, x$data_sha))
  writeLines(sprintf(
    '{"members":[{"id":{"project":"set-project","name":"dm","kind":"table","version":"%s"},"tags":{}}]}',
    version
  ), path)
  gs_edit_json(
    gs_stored(fx, .datom_artifact_meta_key("product-a", "metadata")),
    function(doc) {
      doc$document_sha <- digest::digest(file = path, algo = "sha256")
      doc
    }
  )

  y <- datom_get_set(fx$conn, "product-a")

  expect_true("tags" %in% names(y$members[[1L]]))
  expect_length(y$members[[1L]]$tags, 0L)
})


# === the read never tidies ====================================================
#
# .datom_tidy_set_payload() run on a healthy payload changes nothing, so reaching
# for it passes every other test here. These payloads are deliberately NOT in
# canonical form, which is the only way to see the difference.

test_that("an uncanonical payload is reported as it is, not reshaped", {
  fx <- local_get_set_project()
  v_dm <- gs_table(fx, "dm")
  v_lb <- gs_table(fx, "lb")
  gs_write(fx, list(datom_member(fx$conn, "dm", v_dm),
                    datom_member(fx$conn, "lb", v_lb)))
  x <- datom_get_set(fx$conn, "product-a")

  gs_replace_payload(fx, x$data_sha, list(
    # Keys out of order, values out of order, a duplicate label, and a key
    # pointing at nothing: every one of them a thing the WRITE normalises.
    tags = list(zeta = "last", alpha = list("b", "a", "b"),
                empty = list()),
    members = list(
      gs_raw_member(name = "lb", version = v_lb),
      gs_raw_member(name = "dm", version = v_dm)
    )
  ))

  y <- datom_get_set(fx$conn, "product-a")

  expect_identical(names(y$tags), c("zeta", "alpha", "empty"))
  expect_identical(y$tags$alpha, c("b", "a", "b"))
  expect_true("empty" %in% names(y$tags))
  expect_identical(
    vapply(y$members, function(m) m$id$name, character(1L)),
    c("lb", "dm")
  )
})

test_that("a member's own uncanonical tag map survives the read", {
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  gs_replace_payload(fx, x$data_sha, list(
    members = list(gs_raw_member(
      version = version,
      tags = list(z = "one", a = list("c", "b"))
    ))
  ))

  y <- datom_get_set(fx$conn, "product-a")

  expect_identical(names(y$members[[1L]]$tags), c("z", "a"))
  expect_identical(y$members[[1L]]$tags$a, c("c", "b"))
})


# === malformed documents ======================================================

test_that("an id value that is not a text scalar aborts, naming the member", {
  # The read is the only place a payload's `id` is ever checked:
  # .datom_validate_members() runs on write only, and these values are spliced
  # into storage keys and compared against project names.
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  gs_replace_payload(fx, x$data_sha, list(
    members = list(
      gs_raw_member(version = version),
      gs_raw_member(name = list("dm", "lb"), version = version)
    )
  ))

  err <- expect_error(
    datom_get_set(fx$conn, "product-a"),
    class = "datom_set_member_malformed"
  )
  expect_match(conditionMessage(err), "members\\[\\[2\\]\\]")
  expect_match(conditionMessage(err), "id\\$name")
})

test_that("a member missing an id field of its own aborts", {
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  member <- gs_raw_member(version = version)
  member$id$kind <- NULL
  gs_replace_payload(fx, x$data_sha, list(members = list(member)))

  err <- expect_error(
    datom_get_set(fx$conn, "product-a"),
    class = "datom_set_member_malformed"
  )
  expect_match(conditionMessage(err), "id\\$kind")
})

test_that("a payload whose members are not a list of records aborts", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  gs_replace_payload(fx, x$data_sha, list(tags = list(a = "b")))

  expect_error(
    datom_get_set(fx$conn, "product-a"),
    class = "datom_set_payload_malformed"
  )
})

test_that("an id field a newer datom added is carried, not refused", {
  # Reads limp: this build never reads the extra field, so refusing it would
  # block the direction that has to keep working.
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  member <- gs_raw_member(version = version)
  member$id$future_field <- "from a newer datom"
  gs_replace_payload(fx, x$data_sha, list(members = list(member)))

  y <- datom_get_set(fx$conn, "product-a")

  expect_identical(y$members[[1L]]$id$future_field, "from a newer datom")
})


# === the member link ==========================================================

test_that("a table member's link resolves to exactly what datom_read() returns (AC1b)", {
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)

  x <- datom_get_set(fx$conn, "product-a")
  link <- x$members[[1L]]$fetch

  expect_s3_class(link, "datom_link")
  expect_true(is.function(link))
  expect_identical(link(fx$conn), datom_read(fx$conn, "dm", version = version))
})

test_that("a link pins the version it was read at -- it never drifts to the latest", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  # The member table moves on after the set was read.
  suppressMessages(datom_write(fx$conn, data = gs_data(9L), name = "dm"))

  expect_identical(nrow(x$members[[1L]]$fetch(fx$conn)), 3L)
  expect_identical(nrow(datom_read(fx$conn, "dm")), 9L)
})

test_that("the link carries its own member record, and it is pure data", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  m <- datom_get_set(fx$conn, "product-a")$members[[1L]]

  expect_identical(attr(m$fetch, "datom_member"), m[c("id", "tags")])
  expect_false("fetch" %in% names(attr(m$fetch, "datom_member")))
})

test_that("a serialized link contains no connection, so no credentials", {
  # Asserted on the BYTES. An environment(link) check passes on the broken shape,
  # where the connection sits one frame further up -- which is why the factory is
  # a namespace-level function with every argument forced.
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  m <- datom_get_set(fx$conn, "product-a")$members[[1L]]

  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(m$fetch, path, compress = FALSE)
  bytes <- readBin(path, "raw", file.size(path))

  # The fixture's token value, not a field name: a dev-loaded package keeps
  # source references, so the serialized closure carries the text of R/set.R --
  # which mentions `github_pat` in an example. The token appears in no source
  # file, so finding it can only mean a connection came along. Verified to catch
  # the broken shape: the same code with the factory nested inside the read verb
  # puts this exact string in the bytes.
  #
  # grepRaw rather than a string search: serialized R objects hold embedded NULs,
  # which rawToChar refuses.
  expect_length(grepRaw("SUPER-SECRET-TOKEN-XYZ", bytes, fixed = TRUE), 0L)

  # The frame check, as a complement rather than the guard: `environment(link)`
  # alone passes on the broken shape, because the connection is one frame up --
  # so the whole chain up to the namespace is walked.
  reachable <- list()
  e <- environment(m$fetch)
  while (!is.null(e) && !identical(e, globalenv()) &&
         !identical(e, emptyenv()) && !isNamespace(e)) {
    reachable <- c(reachable, as.list(e, all.names = TRUE))
    e <- parent.env(e)
  }
  expect_false(any(vapply(reachable, inherits, logical(1L), "datom_conn")))
})

test_that("a link survives a save/load round trip, callable and intact", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  m <- datom_get_set(fx$conn, "product-a")$members[[1L]]

  path <- withr::local_tempfile(fileext = ".rds")
  saveRDS(m$fetch, path)
  restored <- readRDS(path)

  expect_s3_class(restored, "datom_link")
  expect_identical(attr(restored, "datom_member"), attr(m$fetch, "datom_member"))
  expect_identical(restored(fx$conn), m$fetch(fx$conn))
})

test_that("a set member's link resolves through datom_get_set(), not datom_read()", {
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  gs_replace_payload(fx, x$data_sha, list(members = list(
    gs_raw_member(name = "inner-product", kind = "set", version = version)
  )))
  y <- datom_get_set(fx$conn, "product-a")

  # Mocked after the outer read, so the outer call is the real one and only the
  # link's own dispatch is observed.
  local_mocked_bindings(
    datom_get_set = function(conn, name, version = NULL) {
      list(routed_to = "datom_get_set", name = name)
    }
  )

  expect_identical(y$members[[1L]]$fetch(fx$conn)$routed_to, "datom_get_set")
})

test_that("a kind this build cannot resolve aborts when the link is called, not before", {
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  gs_replace_payload(fx, x$data_sha, list(members = list(
    gs_raw_member(kind = "cube", version = version)
  )))

  # The read itself succeeds: an unknown kind is still a pointer, and reporting
  # it costs nothing.
  y <- datom_get_set(fx$conn, "product-a")
  expect_identical(y$members[[1L]]$id$kind, "cube")

  err <- expect_error(
    y$members[[1L]]$fetch(fx$conn),
    class = "datom_member_kind_unknown"
  )
  expect_match(conditionMessage(err), "upgrade datom")
})

test_that("a link does not gate on the connection's project name, and must not (AC1b)", {
  # A project comparison inside the link looks free -- both names are in hand --
  # and it would refuse working reads. For a READER connection, which is the
  # primary consumer of a set, `project_name` is a label passed to
  # datom_get_conn(): the namespace comes from the store's root and prefix and
  # nothing validates the label against the repo. The member's OWN side of that
  # comparison is trustworthy now -- its project is recorded by the writer -- but
  # comparing a verified value against an unverified one still refuses working
  # reads, so the mismatch below is the ordinary case and this test is what
  # reddens if somebody adds the gate. A hint on an already-failed fetch is a
  # different thing and lives in `.datom_link_failure()`.
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  mislabelled <- fx$conn
  mislabelled$path <- NULL
  mislabelled$role <- "reader"
  mislabelled$project_name <- "a-label-nobody-validated"

  x <- datom_get_set(mislabelled, "product-a")

  expect_identical(x$members[[1L]]$id$project, "set-project")
  expect_identical(nrow(x$members[[1L]]$fetch(mislabelled)), 3L)
})

test_that("both the set's project and a member's come from the repo, not the label", {
  # INVERTED DELIBERATELY, and this is not a regression. This test used to pin the
  # opposite -- that a mislabelled reader saw its own label as the set's project --
  # because no document recorded which project an artifact belonged to, so the two
  # facts were of different quality: a member's project was recorded when the
  # member was declared, the set's was whatever the connection said. Both are now
  # recorded by the writer, from the writing repo's own project.yaml, so a label
  # nobody validated no longer reaches either one.
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  mislabelled <- fx$conn
  mislabelled$path <- NULL
  mislabelled$role <- "reader"
  mislabelled$project_name <- "a-label-nobody-validated"

  x <- datom_get_set(mislabelled, "product-a")

  expect_identical(x$project, "set-project")
  expect_identical(x$members[[1L]]$id$project, "set-project")
})

test_that("a set written before the field falls back to the connection's name", {
  # The only route to the fallback, and it is unreachable through any released
  # build: sets and the recorded project name ship in the same release. Kept
  # because the fallback exists in the code, so something has to say what it does.
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  gs_edit_json(
    gs_stored(fx, .datom_artifact_meta_key("product-a", "metadata")),
    function(doc) {
      doc$project <- NULL
      doc
    }
  )

  reader <- fx$conn
  reader$path <- NULL
  reader$role <- "reader"
  reader$project_name <- "whatever-the-caller-said"

  expect_identical(
    datom_get_set(reader, "product-a")$project,
    "whatever-the-caller-said"
  )
})

test_that("the set read reaches the project name without reading the manifest", {
  # The data path never touches the manifest -- which is why a build too old for
  # the current manifest shape can still read data -- and the project-name cascade
  # must not be what changes that. A member's cascade DOES read it, deliberately,
  # because that value is durable and hashed; this one is an echo for display.
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  read_keys <- character(0)
  real_read <- .datom_storage_read_json
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, key) {
      read_keys <<- c(read_keys, key)
      real_read(conn, key)
    }
  )

  datom_get_set(fx$conn, "product-a")

  expect_false(any(grepl("manifest", read_keys, fixed = TRUE)))
})

test_that("two reads of one set are not identical(), and the records are", {
  # Closures compare by environment. datom_read()'s own example asserts
  # identical() for a table, so the asymmetry gets met by anyone reading both
  # help pages -- hence the note in the docs and this pin.
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  a <- datom_get_set(fx$conn, "product-a")
  b <- datom_get_set(fx$conn, "product-a")

  expect_false(identical(a, b))
  expect_true(identical(a, b, ignore.environment = TRUE))
  expect_identical(a$members[[1L]][c("id", "tags")],
                   b$members[[1L]][c("id", "tags")])
})

test_that("a link prints what it points at and how to resolve it", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)

  m <- datom_get_set(fx$conn, "product-a")$members[[1L]]
  out <- cli::cli_fmt(print(m$fetch))

  expect_match(paste(out, collapse = " "), "dm")
  expect_match(paste(out, collapse = " "), "table")
  expect_match(paste(out, collapse = " "), "set-project")
  expect_match(paste(out, collapse = " "), "type=input")
  expect_match(paste(out, collapse = " "), "link\\(conn\\)")
})


# === one level only ===========================================================

test_that("a member that is itself a set comes back as a pointer, not traversed (AC15)", {
  # The inner set does not exist in storage at all, so a traversing implementation
  # errors rather than quietly flattening -- a louder signal than a count.
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  gs_replace_payload(fx, x$data_sha, list(members = list(
    gs_raw_member(name = "does-not-exist", kind = "set", version = version)
  )))

  y <- datom_get_set(fx$conn, "product-a")

  expect_length(y$members, 1L)
  expect_identical(y$members[[1L]]$id$kind, "set")
  expect_identical(y$members[[1L]]$id$name, "does-not-exist")
})

test_that("read cost is this set's own documents only, whatever its members are (AC15)", {
  fx <- local_get_set_project()
  version <- gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  gs_replace_payload(fx, x$data_sha, list(members = list(
    gs_raw_member(name = "inner-a", kind = "set", version = version),
    gs_raw_member(name = "inner-b", kind = "set", version = version)
  )))

  read_keys <- character()
  real_read_json <- .datom_storage_read_json
  local_mocked_bindings(
    .datom_storage_read_json = function(conn, s3_key) {
      read_keys <<- c(read_keys, s3_key)
      real_read_json(conn, s3_key)
    }
  )

  datom_get_set(fx$conn, "product-a")

  expect_setequal(
    read_keys,
    c("product-a/.metadata/metadata.json",
      "product-a/.metadata/version_history.json")
  )
})


# === print.datom_set ==========================================================

test_that("printing a set names its members, their kinds and their tags", {
  fx <- local_get_set_project()
  v_dm <- gs_table(fx, "dm")
  v_lb <- gs_table(fx, "lb")
  gs_write(
    fx,
    list(datom_member(fx$conn, "dm", v_dm, tags = list(type = "input")),
         datom_member(fx$conn, "lb", v_lb)),
    tags = list(description = "Two members")
  )

  x <- datom_get_set(fx$conn, "product-a")
  out <- paste(cli::cli_fmt(print(x)), collapse = " ")

  expect_match(out, "product-a")
  expect_match(out, "set-project")
  expect_match(out, "dm \\(table\\)")
  expect_match(out, "type=input")
  expect_match(out, "description=Two members")
  # An untagged member reads as `-`, not as a blank the eye skips.
  expect_match(out, "lb \\(table\\)\\s+-")
  # The named verb, which is the route a reader can type from what they just
  # read above. This pointed at the link form until that verb existed; the link
  # form still works and is what the leaf of a projection gives you.
  expect_match(out, 'datom_fetch_member\\(conn, x, "dm"\\)')
})

test_that("printing returns its input invisibly", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)
  x <- datom_get_set(fx$conn, "product-a")

  cli::cli_fmt(shown <- withVisible(print(x)))
  expect_false(shown$visible)
  expect_identical(shown$value, x)
})

test_that("a long member list is truncated with a count of the rest", {
  x <- structure(
    list(
      name = "big", project = "p", version = strrep("a", 64L),
      data_sha = strrep("b", 64L), tags = NULL,
      members = lapply(1:30, function(i) {
        list(id = list(project = "p", name = paste0("t", i), kind = "table",
                       version = strrep("c", 64L)))
      })
    ),
    class = "datom_set"
  )

  out <- paste(cli::cli_fmt(print(x, n = 5L)), collapse = " ")

  expect_match(out, "t5 \\(table\\)")
  expect_false(grepl("t6 \\(table\\)", out))
  expect_match(out, "and 25 more")
})


# === writing a read set back ==================================================

test_that("datom_write_set() accepts a datom_set and carries its tags forward", {
  # Without the carry-forward, read-append-write silently drops the set's
  # description and mints a version without it.
  fx <- local_get_set_project()
  gs_one_member_set(fx, tags = list(description = "kept"))

  x <- datom_get_set(fx$conn, "product-a")
  res <- gs_write(fx, x)

  expect_identical(res$action, "none")
  expect_identical(res$metadata_sha, x$version)
  expect_identical(datom_get_set(fx$conn, "product-a")$tags$description, "kept")
})

test_that("the member list alone works too, with tags the caller's to supply", {
  fx <- local_get_set_project()
  gs_one_member_set(fx, tags = list(description = "kept"))
  x <- datom_get_set(fx$conn, "product-a")

  res <- gs_write(fx, x$members, tags = x$tags)

  expect_identical(res$action, "none")
})

test_that("tags supplied explicitly override the ones the read set carried", {
  fx <- local_get_set_project()
  gs_one_member_set(fx, tags = list(description = "old"))
  x <- datom_get_set(fx$conn, "product-a")

  res <- gs_write(fx, x, tags = list(description = "new"))

  # A set's identity covers the whole payload, tags included, so a changed
  # description is new content and not a metadata-only edit.
  expect_identical(res$action, "full")
  expect_identical(datom_get_set(fx$conn, "product-a")$tags$description, "new")
})

test_that("read, append a member, write back mints a version with both members", {
  fx <- local_get_set_project()
  gs_one_member_set(fx)
  v_lb <- gs_table(fx, "lb")

  x <- datom_get_set(fx$conn, "product-a")
  x$members <- c(x$members, list(datom_member(fx$conn, "lb", v_lb)))
  res <- gs_write(fx, x)

  expect_identical(res$action, "full")
  expect_identical(res$member_count, 2L)
  expect_length(datom_get_set(fx$conn, "product-a")$members, 2L)
})

test_that("a hand-built fetch that is not a function still aborts", {
  # Only a callable is stripped, so a typo cannot pass as a member field.
  fx <- local_get_set_project()
  version <- gs_table(fx, "dm")
  member <- datom_member(fx$conn, "dm", version)
  member$fetch <- "junk"

  expect_error(
    datom_write_set(fx$conn, list(member)),
    "unexpected"
  )
})

test_that("stripping a link touches nothing else about the member", {
  member <- list(id = list(project = "p", name = "dm", kind = "table",
                           version = "abc123"),
                 tags = list(type = "input"))
  linked <- c(member, list(fetch = function(conn) NULL))

  expect_identical(.datom_strip_member_links(list(linked)), list(member))
  expect_identical(.datom_strip_member_links(list(member)), list(member))
  expect_identical(.datom_strip_member_links(list()), list())
})


# === .datom_resolve_version()'s field argument =================================

test_that("field selects which recorded stored-object hash comes back", {
  metadata_list <- list(
    current = list(data_sha = "sha_c", parquet_sha = "pq_c",
                   document_sha = "doc_c"),
    history = list(
      list(version = "v_2", data_sha = "sha_c", document_sha = "doc_c",
           timestamp = "t2"),
      list(version = "v_1", data_sha = "sha_1", document_sha = "doc_1")
    )
  )

  expect_identical(
    .datom_resolve_version(metadata_list, field = "document_sha")$object_sha,
    "doc_c"
  )
  expect_identical(
    .datom_resolve_version(metadata_list, field = "parquet_sha")$object_sha,
    "pq_c"
  )
  expect_identical(
    .datom_resolve_version(metadata_list, version = "v_1",
                           field = "document_sha")$object_sha,
    "doc_1"
  )
})

test_that("a document that never recorded the field resolves object_sha NULL, not an error", {
  # `doc[[field]]` on a list without the name is a subscript error rather than
  # NULL, and every document written before the field existed lacks it.
  metadata_list <- list(
    current = list(data_sha = "sha_c"),
    history = list(list(version = "v_1", data_sha = "sha_c"))
  )

  expect_null(.datom_resolve_version(metadata_list, field = "document_sha")$object_sha)
  expect_null(
    .datom_resolve_version(metadata_list, version = "v_1",
                           field = "document_sha")$object_sha
  )
})

test_that("the resolved version is the recorded one, from either route", {
  metadata_list <- list(
    current = list(data_sha = "sha_c", created_at = "t2"),
    history = list(
      list(version = strrep("2", 64L), data_sha = "sha_c", timestamp = "t2"),
      list(version = strrep("1", 64L), data_sha = "sha_1", timestamp = "t1")
    )
  )

  expect_identical(
    .datom_resolve_version(metadata_list)$version,
    strrep("2", 64L)
  )
  # A prefix goes in, the full recorded version comes out.
  expect_identical(
    .datom_resolve_version(metadata_list, version = "111")$version,
    strrep("1", 64L)
  )
})

test_that("a history that records nothing for the current state resolves version NULL", {
  # A manufactured version would be a wrong statement rather than a missing one;
  # datom_validate() owns the inconsistency.
  metadata_list <- list(
    current = list(data_sha = "sha_c"),
    history = list(list(version = "v_1", data_sha = "something_else"))
  )

  expect_null(.datom_resolve_version(metadata_list)$version)
})
