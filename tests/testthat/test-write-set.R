# The set write path: two gates, tidy-then-validate, canonical form, the dual
# write, and the manifest row.
#
# Most of these run against a real git repo, a real bare remote and a real local
# store with nothing mocked, because almost every claim here is about the
# COMPOSITION -- canonicalize, hash, write the git copy, commit, push, mirror --
# rather than about any one function. The two that mock do so to observe an
# absence.
#
# Three things below are the tests that a naive implementation passes everything
# else while failing:
#
#   * the canonical form is asserted on the FILE BYTES, not on the return value.
#     Several payload spellings share one `data_sha`, so a hash comparison cannot
#     see whether the stored bytes were normalised.
#   * the metadata document's field set is asserted on the file too, because
#     `jsonlite` writes a NULL element as `{}` -- a `document_sha` left
#     unpopulated would satisfy a names-only check while carrying an empty object.
#   * a payload whose `data_sha` is already in history must not be re-uploaded,
#     proved with a backdated mtime. Byte comparison cannot tell "not
#     re-uploaded" from "re-uploaded identical bytes".


# --- fixture ------------------------------------------------------------------

#' Real product project: git repo + bare remote + local store + product config.
#'
#' Same shape and same reason as `local_identity_project()` in
#' `test-identity-contract.R`; duplicated because testthat does not share
#' definitions between test files. `gov_root` stays NULL so
#' `.datom_check_ref_current()` takes its legacy-conn skip.
local_set_project <- function(set_name = "product-a", env = parent.frame()) {
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

  write_product_config(repo_dir, "set-project", set_name)

  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir,
       repo = repo, set_name = set_name)
}

sw_data <- function(n = 3L) {
  data.frame(id = seq_len(n), val = letters[seq_len(n)],
             stringsAsFactors = FALSE)
}

# Write a table and return the version just minted, which is what a member pins.
sw_table <- function(fx, name, n = 3L) {
  suppressMessages(datom_write(fx$conn, data = sw_data(n), name = name))
  datom_history(fx$conn, name, short_hash = FALSE)$version[[1L]]
}

sw_member <- function(fx, name, version, tags = NULL) {
  datom_member(fx$conn, name, version, tags = tags)
}

sw_write <- function(fx, members, ...) {
  suppressMessages(datom_write_set(fx$conn, members, ...))
}

# The git copy of the payload, parsed the way a reader parses it.
sw_payload <- function(fx, name = fx$set_name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "set.json"))
}

sw_payload_path <- function(fx, name = fx$set_name) {
  fs::path(fx$repo_dir, name, "set.json")
}

sw_payload_text <- function(fx, name = fx$set_name) {
  paste(readLines(sw_payload_path(fx, name), warn = FALSE), collapse = "\n")
}

sw_clone_metadata <- function(fx, name = fx$set_name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "metadata.json"))
}

sw_clone_history <- function(fx, name = fx$set_name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "version_history.json"))
}

sw_clone_manifest <- function(fx) {
  jsonlite::read_json(fs::path(fx$repo_dir, ".datom", "manifest.json"))
}

sw_stored_manifest <- function(fx) {
  .datom_storage_read_json(fx$conn, ".metadata/manifest.json")
}

# Located through the package's own path resolution, so a storage-layout change
# breaks the code rather than quietly passing a test that looks elsewhere.
sw_stored_payload_path <- function(fx, data_sha, name = fx$set_name) {
  .datom_local_path(
    fx$conn, .datom_artifact_payload_key(name, data_sha, "set")
  )
}

# A repo with one table already in it, and one member pinning it.
sw_one_member <- function(fx, tags = list(type = "input")) {
  version <- sw_table(fx, "dm")
  list(sw_member(fx, "dm", version, tags = tags))
}


# === the two gates ============================================================
#
# What they buy: "one repo = one set = one product" is only true if something
# checks, and the second gate is also what establishes the set's own identity,
# which the self-reference refusal further down depends on.

test_that("a repo that does not declare mode: product refuses a set write", {
  fx <- local_set_project()
  members <- sw_one_member(fx)

  # Take the declaration away, leaving an otherwise healthy datom repo.
  cfg_path <- fs::path(fx$repo_dir, ".datom", "project.yaml")
  cfg <- yaml::read_yaml(cfg_path)
  cfg$mode <- NULL
  yaml::write_yaml(cfg, cfg_path)

  err <- expect_error(
    datom_write_set(fx$conn, members, name = "product-a"),
    class = "datom_set_mode_required"
  )
  # The recourse is the whole message: without the two field names the user has
  # nothing to act on.
  expect_match(conditionMessage(err), "mode: product")
  expect_match(conditionMessage(err), "set:")
})

test_that("a repo declaring some other mode refuses, and says which mode it found", {
  fx <- local_set_project()
  members <- sw_one_member(fx)

  cfg_path <- fs::path(fx$repo_dir, ".datom", "project.yaml")
  cfg <- yaml::read_yaml(cfg_path)
  cfg$mode <- "study"
  yaml::write_yaml(cfg, cfg_path)

  err <- expect_error(
    datom_write_set(fx$conn, members, name = "product-a"),
    class = "datom_set_mode_required"
  )
  expect_match(conditionMessage(err), "study")
})

test_that("a product repo that names no set refuses", {
  fx <- local_set_project()
  members <- sw_one_member(fx)

  cfg_path <- fs::path(fx$repo_dir, ".datom", "project.yaml")
  cfg <- yaml::read_yaml(cfg_path)
  cfg$set <- NULL
  yaml::write_yaml(cfg, cfg_path)

  expect_error(
    datom_write_set(fx$conn, members, name = "product-a"),
    class = "datom_set_undeclared"
  )
})

test_that("a name that is not the repo's declared set refuses, naming both", {
  fx <- local_set_project(set_name = "product-a")
  members <- sw_one_member(fx)

  err <- expect_error(
    datom_write_set(fx$conn, members, name = "something-else"),
    class = "datom_set_name_mismatch"
  )
  expect_match(conditionMessage(err), "product-a")
  expect_match(conditionMessage(err), "something-else")
})

test_that("the name defaults to the set the repo declares", {
  fx <- local_set_project(set_name = "declared-product")
  members <- sw_one_member(fx)

  res <- sw_write(fx, members)

  expect_identical(res$name, "declared-product")
  expect_true(fs::file_exists(sw_payload_path(fx, "declared-product")))
})

test_that("a refused gate leaves nothing behind -- no payload, no version, no row", {
  # The reason the gates run before any hashing or IO. A write is several steps,
  # and stopping halfway through is worse than the disagreement being prevented.
  fx <- local_set_project()
  members <- sw_one_member(fx)

  before <- sw_clone_manifest(fx)

  expect_error(
    datom_write_set(fx$conn, members, name = "not-the-set"),
    class = "datom_set_name_mismatch"
  )

  expect_false(fs::dir_exists(fs::path(fx$repo_dir, "not-the-set")))
  expect_false(fs::file_exists(sw_payload_path(fx)))
  expect_setequal(names(sw_clone_manifest(fx)$artifacts),
                  names(before$artifacts))
})

test_that("a repo with no project.yaml refuses before anything else", {
  fx <- local_set_project()
  members <- sw_one_member(fx)
  fs::file_delete(fs::path(fx$repo_dir, ".datom", "project.yaml"))

  expect_error(
    datom_write_set(fx$conn, members, name = "product-a"),
    class = "datom_set_config_missing"
  )
})

test_that("a reader connection is refused, and so is one with no clone", {
  fx <- local_set_project()
  members <- sw_one_member(fx)

  reader <- fx$conn
  reader$role <- "reader"
  expect_error(datom_write_set(reader, members), "developer")

  clone_less <- fx$conn
  clone_less$path <- NULL
  expect_error(datom_write_set(clone_less, members), "local git repo path")
})

test_that("a non-conn first argument is refused", {
  expect_error(datom_write_set(list(), list()), "datom_conn")
})


# === the forward-compatibility door ===========================================
#
# A new write verb inherits nothing from the three routes that already call the
# entry check. Left out, the writer floor, the format check and the vocabulary
# check are all silently skipped for every set write -- which is the same
# route-was-the-gap finding that has now landed in four consecutive tasks.

test_that("a set write goes through the write entry check", {
  fx <- local_set_project()
  members <- sw_one_member(fx)

  # A field in the clone's manifest that this build cannot place. A write that
  # rewrote this document would delete it while recomputing identity around it.
  manifest_path <- fs::path(fx$repo_dir, ".datom", "manifest.json")
  doc <- jsonlite::read_json(manifest_path)
  doc$future_top_field <- "written by a newer datom"
  jsonlite::write_json(doc, manifest_path, auto_unbox = TRUE, pretty = TRUE)

  err <- expect_error(
    datom_write_set(fx$conn, members, name = "product-a"),
    class = "datom_vocabulary_unknown"
  )
  expect_match(conditionMessage(err), "future_top_field")
  expect_false(fs::file_exists(sw_payload_path(fx)))
})

test_that("a set write respects the repo's declared writer floor", {
  fx <- local_set_project()
  members <- sw_one_member(fx)

  fx$conn$min_writer_version <- "99.0.0"

  expect_error(
    datom_write_set(fx$conn, members, name = "product-a"),
    class = "datom_writer_floor"
  )
})


# === the payload-level refusals ===============================================
#
# The cases only a whole-payload view can see. Each is a separate test, so a
# regression names which one leaked rather than only that one of them did.

test_that("a set with zero members is refused", {
  fx <- local_set_project()

  expect_error(
    datom_write_set(fx$conn, list(), name = "product-a"),
    class = "datom_set_empty"
  )
  expect_error(
    datom_write_set(fx$conn, NULL, name = "product-a"),
    class = "datom_set_empty"
  )
})

test_that("a one-member set is legal and hashes normally", {
  fx <- local_set_project()
  members <- sw_one_member(fx)

  res <- sw_write(fx, members)

  expect_identical(res$action, "full")
  expect_identical(res$member_count, 1L)
  expect_match(res$data_sha, "^[0-9a-f]{64}$")
})

test_that("the same id listed twice with different tags is refused", {
  # Deduplication does NOT catch this: a member's digest covers its tags, so both
  # entries survive and the payload holds one member twice with conflicting
  # labels. Refused rather than tidied because both ways to tidy it guess.
  fx <- local_set_project()
  version <- sw_table(fx, "dm")

  members <- list(
    sw_member(fx, "dm", version, tags = list(type = "input")),
    sw_member(fx, "dm", version, tags = list(type = "output"))
  )

  err <- expect_error(
    datom_write_set(fx$conn, members, name = "product-a"),
    class = "datom_set_member_conflict"
  )
  expect_match(conditionMessage(err), "dm")
  # The remedy is the multi-valued form, which the model already supports.
  expect_match(conditionMessage(err), "input")
})

test_that("the same project and name at two different versions is ALLOWED", {
  # Its own test because `project` + `name` looks like the natural duplicate key,
  # and the first reader to tighten the check to it would break a legitimate use
  # silently: a product carrying a current table beside a locked baseline.
  fx <- local_set_project()
  baseline <- sw_table(fx, "dm", n = 3L)
  current <- sw_table(fx, "dm", n = 4L)
  expect_false(identical(baseline, current))

  res <- sw_write(fx, list(
    sw_member(fx, "dm", current, tags = list(release = "current")),
    sw_member(fx, "dm", baseline, tags = list(release = "baseline"))
  ))

  expect_identical(res$member_count, 2L)

  payload <- sw_payload(fx)
  expect_length(payload$members, 2L)
  expect_setequal(
    vapply(payload$members, function(m) m$id$version, character(1L)),
    c(baseline, current)
  )
})

test_that("a set listing itself is refused at write time", {
  # A nonsense check, not cycle detection: cycles are structurally impossible,
  # because a member pins a version that already exists. So there is deliberately
  # no cycle test and no depth test beside this one.
  fx <- local_set_project()
  members <- sw_one_member(fx)

  self <- list(id = list(
    project = "set-project", name = "product-a", kind = "set",
    version = strrep("a", 64L)
  ))

  err <- expect_error(
    datom_write_set(fx$conn, c(members, list(self)), name = "product-a"),
    class = "datom_set_self_reference"
  )
  expect_match(conditionMessage(err), "product-a")
})

test_that("a set naming another project's set of the same name is not self-reference", {
  # The refusal keys on project AND name. A different project's artifact that
  # happens to share this set's name is an ordinary member.
  fx <- local_set_project()
  members <- sw_one_member(fx)

  elsewhere <- list(id = list(
    project = "another-project", name = "product-a", kind = "set",
    version = strrep("a", 64L)
  ))

  res <- sw_write(fx, c(members, list(elsewhere)))
  expect_identical(res$member_count, 2L)
})

test_that("set-level tags go through the tag grammar", {
  fx <- local_set_project()
  members <- sw_one_member(fx)

  # Set-level tags never pass through datom_member(), so this is the only place
  # their grammar is enforced.
  expect_error(
    datom_write_set(fx$conn, members, tags = list(description = ""),
                    name = "product-a"),
    "empty label"
  )
  expect_error(
    datom_write_set(fx$conn, members, tags = list(count = 500),
                    name = "product-a"),
    "text"
  )
  expect_error(
    datom_write_set(fx$conn, members, tags = list(x = NA_character_),
                    name = "product-a"),
    "NA"
  )
  expect_error(
    datom_write_set(fx$conn, members, tags = list("unnamed"),
                    name = "product-a"),
    "named list"
  )
})

test_that("a hand-assembled member list is refused, pointing at datom_member()", {
  fx <- local_set_project()
  sw_table(fx, "dm")

  err <- expect_error(
    datom_write_set(
      fx$conn,
      list(list(id = list(project = "set-project", name = "dm"))),
      name = "product-a"
    ),
    "missing required"
  )
  expect_match(conditionMessage(err), "datom_member")
})


# === canonical form, asserted on the file bytes ================================

test_that("a supplied payload is normalised before it reaches the file", {
  # Assert on the FILE, not the return value: several spellings share one
  # `data_sha`, so a hash comparison cannot see whether the bytes were normalised
  # -- and `document_sha` hashes the bytes, so two spellings at one address would
  # make it unverifiable.
  fx <- local_set_project()
  v_dm <- sw_table(fx, "dm")
  v_lb <- sw_table(fx, "lb")

  sw_write(fx, list(
    # Members out of order (lb before dm), a tag value out of order and
    # duplicated, a single value written as a one-element array, and a key
    # pointing at nothing.
    sw_member(fx, "lb", v_lb, tags = list(
      domain = c("safety", "efficacy", "safety"),
      type = c("output"),
      unused = character(0)
    )),
    sw_member(fx, "dm", v_dm, tags = list(type = "input"))
  ), tags = list(zz_last = "z", aa_first = "a"))

  payload <- sw_payload(fx)

  # Members sorted by name, so dm comes first.
  expect_identical(
    vapply(payload$members, function(m) m$id$name, character(1L)),
    c("dm", "lb")
  )

  lb <- payload$members[[2L]]
  # Tag values sorted and deduplicated.
  expect_identical(unlist(lb$tags$domain), c("efficacy", "safety"))
  # A one-element value written as a bare string, not an array.
  expect_identical(lb$tags$type, "output")
  # A key pointing at nothing is dropped, because "no labels" IS omitting it.
  expect_false("unused" %in% names(lb$tags))
  # Tag keys and id keys radix-sorted.
  expect_identical(names(lb$tags), c("domain", "type"))
  expect_identical(names(lb$id), c("kind", "name", "project", "version"))
  # Set-level tag keys too.
  expect_identical(names(payload$tags), c("aa_first", "zz_last"))

  # The bytes themselves, so the unboxing claim is about the file and not about
  # how jsonlite happened to parse it back.
  text <- sw_payload_text(fx)
  expect_match(text, '"type": "output"', fixed = TRUE)
  expect_match(text, '"domain": ["efficacy", "safety"]', fixed = TRUE)
})

test_that("the file orders members by name, not by digest", {
  # The two sort keys are deliberately different, and this is the test that keeps
  # them different. The hash orders member DIGESTS, which is what keeps the encoder
  # from having to know what an `id` looks like. The file orders by
  # `project` || `name` || `version`, which is what keeps an entry in place when
  # its tags change.
  #
  # The fixture is pinned rather than arbitrary: for these five names at this one
  # version, digest order is the exact REVERSE of name order. So a file sorted by
  # digest cannot pass here by luck, which is what an arbitrary fixture allows --
  # sorting two members by digest agrees with name order half the time.
  mk <- function(nm) {
    list(id = list(project = "p", name = nm, kind = "table",
                   version = strrep("a", 64L)))
  }
  members <- lapply(c("cc", "aa", "ee", "bb", "dd"), mk)

  digest_order <- vapply(
    members, function(m) .datom_sv1_hex(.datom_sv1_member(m)), character(1L)
  )
  by_digest <- vapply(
    members[order(digest_order, method = "radix")],
    function(m) m$id$name, character(1L)
  )
  expect_identical(by_digest, c("ee", "dd", "cc", "bb", "aa"))

  ordered <- .datom_order_set_members(members)
  expect_identical(
    vapply(ordered, function(m) m$id$name, character(1L)),
    c("aa", "bb", "cc", "dd", "ee")
  )
})

test_that("the file sort key includes version, so two versions of one name have a defined order", {
  # Two versions of one artifact are legal members, and without `version` in the
  # key their relative order would be undefined -- so the canonical byte form
  # would not be well defined either.
  mk <- function(ver) {
    list(id = list(project = "p", name = "dm", kind = "table", version = ver))
  }
  ordered <- .datom_order_set_members(list(mk(strrep("f", 64L)),
                                           mk(strrep("0", 64L))))

  expect_identical(
    vapply(ordered, function(m) m$id$version, character(1L)),
    c(strrep("0", 64L), strrep("f", 64L))
  )
})

test_that("editing one member's tags leaves its entry where it was in the file", {
  # This is what digest order in the file would undo, and the loss is not
  # cosmetic: the entry would RELOCATE, so `git diff` would report a delete plus
  # an insert in a different place -- with every entry between them shifting --
  # instead of one changed field.
  fx <- local_set_project()
  versions <- vapply(
    c("aa", "bb", "cc", "dd", "ee"),
    function(nm) sw_table(fx, nm),
    character(1L)
  )
  build <- function(ee_tag) {
    lapply(names(versions), function(nm) {
      sw_member(fx, nm, versions[[nm]],
                tags = if (identical(nm, "ee")) list(type = ee_tag) else NULL)
    })
  }

  sw_write(fx, build("before"))
  before <- vapply(sw_payload(fx)$members, function(m) m$id$name, character(1L))

  sw_write(fx, build("after"))
  after <- vapply(sw_payload(fx)$members, function(m) m$id$name, character(1L))

  expect_identical(before, c("aa", "bb", "cc", "dd", "ee"))
  expect_identical(after, before)
})

test_that("a member record's own keys are canonicalized, not just its id's", {
  # Found by review. The encoder reaches both member slots BY NAME, so
  # `list(tags = , id = )` hashes identically to `list(id = , tags = )` and
  # serialises to different bytes -- two byte spellings of one `data_sha`, which is
  # the state `document_sha` cannot survive.
  #
  # Where it bites: on a revert to content already in history, the clone's payload
  # is rewritten from the current spelling while the stored object is deliberately
  # reused. Git would then hold bytes that do not match the recorded hash while
  # storage holds bytes that do -- a refused read of a valid version, from the
  # copy that looks canonical.
  #
  # Reachable only from a hand-built record, because `datom_member()` emits `id`
  # first and a JSON round trip preserves that. A member is documented as pure
  # data, so a hand-built record is supported input rather than misuse.
  fx <- local_set_project()
  version <- sw_table(fx, "dm")

  reversed <- list(tags = list(type = "input"),
                   id = list(project = "set-project", name = "dm",
                             kind = "table", version = version))

  res <- sw_write(fx, list(reversed))

  expect_identical(names(sw_payload(fx)$members[[1L]]), c("id", "tags"))

  # `id` before `tags` is what datom_member() already emits, so the canonical
  # form is unchanged for every payload written so far -- asserted rather than
  # claimed, by writing the constructor's spelling of the same member and getting
  # a no-op.
  again <- sw_write(fx, list(sw_member(fx, "dm", version,
                                       tags = list(type = "input"))))

  expect_identical(again$action, "none")
  expect_identical(again$data_sha, res$data_sha)
})

test_that("the tidy step leaves a member with no names for the validator to report", {
  # `order(NULL)` is `integer(0)`, so an unguarded sort of the record's keys would
  # EMPTY a malformed record rather than leaving it recognisable -- and the
  # validator's message is the one that names what is wrong.
  out <- .datom_tidy_set_payload(list(members = list(list("no names at all"))))

  expect_length(out$members[[1L]], 1L)
  expect_error(.datom_validate_members(out$members), "named list")
})

test_that("an exact duplicate member collapses to one entry, silently", {
  fx <- local_set_project()
  version <- sw_table(fx, "dm")
  member <- sw_member(fx, "dm", version, tags = list(type = "input"))

  res <- expect_no_error(sw_write(fx, list(member, member)))

  expect_identical(res$member_count, 1L)
  expect_length(sw_payload(fx)$members, 1L)
})

test_that("an untagged member omits the tags key rather than carrying an empty object", {
  # No hash and no golden can tell the difference -- an absent tag map and an
  # empty one encode identically -- so the guard has to be on the emitted bytes.
  fx <- local_set_project()
  version <- sw_table(fx, "dm")

  sw_write(fx, list(sw_member(fx, "dm", version)))

  expect_false(grepl("{}", sw_payload_text(fx), fixed = TRUE))
  expect_identical(names(sw_payload(fx)$members[[1L]]), "id")
})

test_that("a set with no set-level tags omits the payload's tags key", {
  fx <- local_set_project()
  members <- sw_one_member(fx)

  sw_write(fx, members)

  expect_identical(names(sw_payload(fx)), "members")
  expect_false(grepl("{}", sw_payload_text(fx), fixed = TRUE))
})

test_that("tidying happens before validation, so a spelling that tidies never aborts", {
  # The ordering is load-bearing in both directions: validating first would make
  # every tidy rule dead code, and the validator deliberately PASSES a key whose
  # value is empty because that is a tidy case rather than an error.
  fx <- local_set_project()
  version <- sw_table(fx, "dm")

  res <- expect_no_error(sw_write(
    fx,
    list(sw_member(fx, "dm", version)),
    tags = list(domain = character(0), description = c("b", "a", "a"))
  ))

  payload <- sw_payload(fx)
  expect_false("domain" %in% names(payload$tags))
  expect_identical(unlist(payload$tags$description), c("a", "b"))
  expect_identical(res$action, "full")
})

test_that("a non-conforming tag value is refused rather than mangled by the tidy step", {
  # Tidy normalises only what it recognises as text; anything else passes through
  # untouched so the validator reports it, naming the key and the allowed types.
  # A tidy step that reached for sort() would fail with a base-R message naming
  # nothing.
  fx <- local_set_project()
  version <- sw_table(fx, "dm")
  member <- sw_member(fx, "dm", version)

  err <- expect_error(
    datom_write_set(fx$conn, list(member),
                    tags = list(nested = list(a = "b")), name = "product-a")
  )
  expect_match(conditionMessage(err), "nested")

  expect_error(
    datom_write_set(fx$conn, list(member), tags = list(flag = TRUE),
                    name = "product-a"),
    "text"
  )
})

test_that("the canonical form is what a re-parse of the file produces again", {
  # R2.5's write/read agreement, at payload level: the `data_sha` computed from
  # the in-memory payload equals the one recomputed after the payload has been
  # stored and read back.
  fx <- local_set_project()
  v_dm <- sw_table(fx, "dm")
  v_lb <- sw_table(fx, "lb")

  res <- sw_write(fx, list(
    sw_member(fx, "lb", v_lb, tags = list(domain = c("b", "a"))),
    sw_member(fx, "dm", v_dm, tags = list(type = "input"))
  ), tags = list(description = "agreement"))

  from_file <- .datom_canonical_set_hash(sw_payload(fx))
  from_storage <- .datom_canonical_set_hash(
    .datom_storage_read_json(
      fx$conn, .datom_artifact_payload_key(fx$set_name, res$data_sha, "set")
    )
  )

  expect_identical(from_file, res$data_sha)
  expect_identical(from_storage, res$data_sha)
})


# === identity and versions ====================================================

test_that("re-writing an identical payload is a no-op, whatever order it arrives in", {
  fx <- local_set_project()
  v_dm <- sw_table(fx, "dm")
  v_lb <- sw_table(fx, "lb")

  tags <- list(description = "same fact")
  first <- sw_write(fx, list(
    sw_member(fx, "dm", v_dm, tags = list(type = "input")),
    sw_member(fx, "lb", v_lb, tags = list(domain = c("safety", "efficacy")))
  ), tags = tags)

  # Same content, every collection spelled differently.
  again <- sw_write(fx, list(
    sw_member(fx, "lb", v_lb, tags = list(domain = c("efficacy", "safety"))),
    sw_member(fx, "dm", v_dm, tags = list(type = c("input", "input")))
  ), tags = tags)

  expect_identical(again$action, "none")
  expect_identical(again$data_sha, first$data_sha)
  expect_identical(again$metadata_sha, first$metadata_sha)
  expect_length(sw_clone_history(fx), 1L)
})

test_that("an identical member list with a changed description DOES mint a version", {
  # The converse half, and it is the one that matters: a set exists to be cited,
  # so "same citation, different labels" would be a lie to whoever cited it.
  fx <- local_set_project()
  members <- sw_one_member(fx)

  first <- sw_write(fx, members, tags = list(description = "before"))
  second <- sw_write(fx, members, tags = list(description = "after"))

  expect_identical(second$action, "full")
  expect_false(identical(second$data_sha, first$data_sha))
  expect_false(identical(second$metadata_sha, first$metadata_sha))
  expect_length(sw_clone_history(fx), 2L)
})

test_that("a changed per-member tag mints a version too", {
  fx <- local_set_project()
  version <- sw_table(fx, "dm")

  first <- sw_write(fx, list(sw_member(fx, "dm", version,
                                       tags = list(type = "input"))))
  second <- sw_write(fx, list(sw_member(fx, "dm", version,
                                        tags = list(type = "output"))))

  expect_false(identical(second$data_sha, first$data_sha))
  expect_length(sw_clone_history(fx), 2L)
})

test_that("member versions advancing produces a new data_sha and a new version", {
  # Do not "optimize" this away: the member names are unchanged, so a check that
  # keyed on names alone would report no change.
  fx <- local_set_project()
  v1 <- sw_table(fx, "dm", n = 3L)
  first <- sw_write(fx, list(sw_member(fx, "dm", v1)))

  v2 <- sw_table(fx, "dm", n = 4L)
  second <- sw_write(fx, list(sw_member(fx, "dm", v2)))

  expect_false(identical(v1, v2))
  expect_false(identical(second$data_sha, first$data_sha))
  expect_identical(second$action, "full")
  expect_length(sw_clone_history(fx), 2L)
})


# === the metadata document ====================================================

test_that("a written set's metadata carries exactly seven populated fields", {
  # Asserted on the FILE. `jsonlite` writes a NULL element as `{}` rather than
  # omitting it, so a `document_sha` left unpopulated would satisfy a names-only
  # field-set check while carrying an empty object -- and a later read could
  # neither verify it nor tell it from corruption.
  fx <- local_set_project()
  members <- sw_one_member(fx)
  res <- sw_write(fx, members)

  meta <- sw_clone_metadata(fx)

  expect_setequal(
    names(meta),
    c("schema_version", "kind", "data_sha", "hash_algo", "document_sha",
      "created_at", "datom_version")
  )
  expect_identical(meta$kind, "set")
  expect_identical(meta$hash_algo, "datom-sv1")
  expect_identical(meta$schema_version, 2L)
  expect_identical(meta$data_sha, res$data_sha)

  # A real hash, not an empty object: the character test is what distinguishes
  # them, since `{}` reads back as an empty list.
  expect_true(is.character(meta$document_sha))
  expect_match(meta$document_sha, "^[0-9a-f]{64}$")
  expect_false(grepl("{}", sw_payload_text(fx), fixed = TRUE))
})

test_that("a set's metadata records no lineage, and writing one leaves members alone", {
  fx <- local_set_project()
  version <- sw_table(fx, "dm")
  before <- jsonlite::read_json(fs::path(fx$repo_dir, "dm", "metadata.json"))

  sw_write(fx, list(sw_member(fx, "dm", version)))

  meta <- sw_clone_metadata(fx)
  expect_false("parents" %in% names(meta))
  expect_false("source_lineage" %in% names(meta))
  expect_false("table_type" %in% names(meta))
  expect_false("size_bytes" %in% names(meta))
  expect_false("custom" %in% names(meta))

  expect_identical(
    jsonlite::read_json(fs::path(fx$repo_dir, "dm", "metadata.json")),
    before
  )
})

test_that("document_sha is recorded on the version_history entry", {
  # From day one, so a set read can treat an absent one as an error instead of
  # reproducing the pre-cv1 grace parquet_sha carries.
  fx <- local_set_project()
  members <- sw_one_member(fx)
  res <- sw_write(fx, members)

  entry <- sw_clone_history(fx)[[1L]]
  expect_identical(entry$version, res$metadata_sha)
  expect_identical(entry$data_sha, res$data_sha)
  expect_identical(entry$document_sha, sw_clone_metadata(fx)$document_sha)
  expect_false("parquet_sha" %in% names(entry))
})

test_that("document_sha hashes the bytes actually stored", {
  fx <- local_set_project()
  members <- sw_one_member(fx)
  res <- sw_write(fx, members)

  stored <- sw_stored_payload_path(fx, res$data_sha)
  expect_true(fs::file_exists(stored))
  expect_identical(
    digest::digest(file = stored, algo = "sha256"),
    sw_clone_metadata(fx)$document_sha
  )
  # Git and storage hold one spelling of one data_sha, which is the whole reason
  # document_sha is meaningful.
  expect_identical(
    digest::digest(file = sw_payload_path(fx), algo = "sha256"),
    sw_clone_metadata(fx)$document_sha
  )
})


# === one data_sha, one byte spelling ==========================================

test_that(".datom_resolve_document_sha reuses a recorded hash instead of the fresh one", {
  # The defect this prevents passes every per-chunk test: recomputing the hash
  # from freshly emitted bytes while reusing the stored object records a hash of
  # bytes nobody stored, and it surfaces later as a refused read of a valid
  # version.
  local_mocked_bindings(
    .datom_lookup_history_document_sha =
      function(conn, name, data_sha) "doc_reused"
  )

  res <- .datom_resolve_document_sha(
    mock_datom_conn(list()), "set-a", "sha_a", "doc_new", "full", NULL
  )

  expect_identical(res$document_sha, "doc_reused")
  expect_false(res$upload)
})

test_that(".datom_resolve_document_sha uploads fresh bytes for content never stored", {
  local_mocked_bindings(
    .datom_lookup_history_document_sha = function(conn, name, data_sha) NULL
  )

  res <- .datom_resolve_document_sha(
    mock_datom_conn(list()), "set-a", "sha_a", "doc_new", "full", NULL
  )

  expect_identical(res$document_sha, "doc_new")
  expect_true(res$upload)
})

test_that(".datom_resolve_document_sha carries the current hash forward on a metadata-only change", {
  res <- .datom_resolve_document_sha(
    mock_datom_conn(list()), "set-a", "sha_a", "doc_new", "metadata_only",
    list(data_sha = "sha_a", document_sha = "doc_current")
  )

  expect_identical(res$document_sha, "doc_current")
  expect_false(res$upload)
})

test_that("the history scan finds the newest entry that recorded a document_sha", {
  conn <- mock_datom_conn(list())
  conn$path <- withr::local_tempdir()
  fs::dir_create(fs::path(conn$path, "set-a"))
  jsonlite::write_json(
    list(
      list(version = "v3", data_sha = "sha_b", document_sha = "doc_b"),
      list(version = "v2", data_sha = "sha_a", document_sha = "doc_a2"),
      list(version = "v1", data_sha = "sha_a", document_sha = "doc_a1")
    ),
    fs::path(conn$path, "set-a", "version_history.json"),
    auto_unbox = TRUE
  )

  expect_identical(
    .datom_lookup_history_document_sha(conn, "set-a", "sha_a"), "doc_a2"
  )
  expect_null(.datom_lookup_history_document_sha(conn, "set-a", "sha_zz"))
  # An entry written before the field existed is not a match, and asking for it
  # must not be a subscript error.
  jsonlite::write_json(
    list(list(version = "v1", data_sha = "sha_a")),
    fs::path(conn$path, "set-a", "version_history.json"),
    auto_unbox = TRUE
  )
  expect_null(.datom_lookup_history_document_sha(conn, "set-a", "sha_a"))
})

test_that("re-writing content already in history does not touch the stored payload", {
  # Proved with a backdated mtime: a re-upload goes through fs::file_copy(
  # overwrite = TRUE) and would reset it. Byte comparison cannot distinguish
  # "not re-uploaded" from "re-uploaded identical bytes".
  fx <- local_set_project()
  v_dm <- sw_table(fx, "dm")
  v_lb <- sw_table(fx, "lb")

  only_dm <- list(sw_member(fx, "dm", v_dm))
  first <- sw_write(fx, only_dm)
  recorded_document_sha <- sw_clone_metadata(fx)$document_sha

  sw_write(fx, c(only_dm, list(sw_member(fx, "lb", v_lb))))

  stored <- sw_stored_payload_path(fx, first$data_sha)
  backdated <- as.POSIXct("2020-01-01 00:00:00", tz = "UTC")
  fs::file_touch(stored, modification_time = backdated)

  again <- sw_write(fx, only_dm)

  expect_identical(again$data_sha, first$data_sha)
  expect_equal(
    as.numeric(fs::file_info(stored)$modification_time),
    as.numeric(backdated)
  )
  # The recorded hash is carried forward rather than recomputed.
  expect_identical(sw_clone_metadata(fx)$document_sha, recorded_document_sha)
})


# === where the payload lives ==================================================

test_that("the payload is git-canonical at a stable path and content-addressed in storage", {
  fx <- local_set_project()
  members <- sw_one_member(fx)
  res <- sw_write(fx, members)

  expect_true(fs::file_exists(sw_payload_path(fx)))
  expect_true(fs::file_exists(sw_stored_payload_path(fx, res$data_sha)))

  # The two addresses are different directories from the versioned metadata
  # snapshot, which also ends in .json -- which is exactly why they are easy to
  # confuse.
  expect_true(.datom_storage_exists(
    fx$conn, .datom_artifact_snapshot_key(fx$set_name, res$metadata_sha)
  ))
})

test_that("the git payload stays one file, modified in place, so a diff is member-level", {
  # A content-addressed git filename would make every version a new file: a diff
  # would report "file added" and history would have to be read by listing
  # filenames -- hand-maintaining what git already maintains.
  fx <- local_set_project()
  v_dm <- sw_table(fx, "dm")
  v_lb <- sw_table(fx, "lb")

  first <- sw_write(fx, list(sw_member(fx, "dm", v_dm)))
  second <- sw_write(fx, list(sw_member(fx, "dm", v_dm),
                              sw_member(fx, "lb", v_lb)))

  blobs_in_set_dir <- function(commit_sha) {
    tree <- git2r::tree(git2r::lookup(fx$repo, commit_sha))
    entries <- git2r::ls_tree(tree = tree)
    entries[entries$type == "blob" &
              entries$path == paste0(fx$set_name, "/"), ]
  }

  before <- blobs_in_set_dir(first$commit_sha)
  after <- blobs_in_set_dir(second$commit_sha)

  # One payload file in each commit, at the same path.
  expect_identical(sum(before$name == "set.json"), 1L)
  expect_identical(sum(after$name == "set.json"), 1L)
  # And no content-addressed sibling beside it, in either commit.
  expect_false(any(grepl("^[0-9a-f]{6,}\\.json$", c(before$name, after$name))))

  # Same path, different content: the file was modified, not replaced.
  expect_false(identical(
    before$sha[before$name == "set.json"],
    after$sha[after$name == "set.json"]
  ))

  # Only one payload file in the working tree, too.
  expect_identical(
    sort(fs::path_file(fs::dir_ls(fs::path(fx$repo_dir, fx$set_name)))),
    c("metadata.json", "set.json", "version_history.json")
  )
})

test_that("nothing reaches storage when the git push fails", {
  # Git push is the serialization point, and the ordering is what makes the reuse
  # decision safe against a concurrent writer.
  fx <- local_set_project()
  members <- sw_one_member(fx)

  local_mocked_bindings(
    .datom_git_push = function(path, pat = NULL, pull_first = TRUE) {
      stop("push refused")
    }
  )

  expect_error(datom_write_set(fx$conn, members, name = "product-a"),
               "push refused")

  expect_false(.datom_storage_exists(
    fx$conn, .datom_artifact_meta_key(fx$set_name, "metadata")
  ))
})


# === the manifest row =========================================================

test_that("a set's row carries kind and member_count, and no size_bytes", {
  fx <- local_set_project()
  v_dm <- sw_table(fx, "dm")
  v_lb <- sw_table(fx, "lb")

  sw_write(fx, list(sw_member(fx, "dm", v_dm), sw_member(fx, "lb", v_lb)))

  row <- sw_clone_manifest(fx)$artifacts[[fx$set_name]]

  expect_identical(row$kind, "set")
  expect_identical(row$member_count, 2L)
  # Instead of, not beside: a set row carrying size_bytes = 0 reads as an
  # artifact of zero bytes, and the tables-only byte total would be right by luck.
  expect_false("size_bytes" %in% names(row))
  expect_identical(row$version_count, 1L)

  expect_identical(sw_stored_manifest(fx)$artifacts[[fx$set_name]]$member_count,
                   2L)
})

test_that("member_count is the count AFTER tidying, not what the caller passed", {
  # Pinned because tidying drops an exact duplicate, so the two can differ --
  # today they rarely do, which is exactly why an unstated rule would be settled
  # by accident.
  fx <- local_set_project()
  version <- sw_table(fx, "dm")
  member <- sw_member(fx, "dm", version, tags = list(type = "input"))

  sw_write(fx, list(member, member, member))

  expect_identical(
    sw_clone_manifest(fx)$artifacts[[fx$set_name]]$member_count, 1L
  )
})

test_that("the summary counts the set separately and leaves the table totals alone", {
  fx <- local_set_project()
  v_dm <- sw_table(fx, "dm")

  before <- sw_clone_manifest(fx)$summary
  sw_write(fx, list(sw_member(fx, "dm", v_dm)))
  after <- sw_clone_manifest(fx)$summary

  expect_identical(after$total_sets, 1L)
  expect_identical(after$total_tables, before$total_tables)
  expect_identical(after$total_size_bytes, before$total_size_bytes)
  expect_identical(after$total_versions, before$total_versions)

  # And the numbers datom_summary() counts for itself agree with the stored
  # block -- a filter applied to one and not the other is invisible until they
  # are compared.
  summary <- datom_summary(fx$conn)
  expect_identical(summary$set_count, 1L)
  expect_identical(summary$table_count, as.integer(after$total_tables))
})

test_that("a set appears in datom_list typed as a set", {
  fx <- local_set_project()
  v_dm <- sw_table(fx, "dm")
  sw_write(fx, list(sw_member(fx, "dm", v_dm)))

  listed <- datom_list(fx$conn)

  expect_true(fx$set_name %in% listed$name)
  expect_identical(listed$kind[listed$name == fx$set_name], "set")
})

test_that("datom_history reports a set's versions", {
  fx <- local_set_project()
  members <- sw_one_member(fx)
  sw_write(fx, members, tags = list(description = "one"))
  sw_write(fx, members, tags = list(description = "two"))

  history <- datom_history(fx$conn, fx$set_name, short_hash = FALSE)

  expect_identical(nrow(history), 2L)
  expect_identical(history$version[[1L]], sw_clone_history(fx)[[1L]]$version)
})


# === one name is one artifact =================================================

test_that("a set cannot be written over an existing table of the same name", {
  # Checked against the metadata document in STORAGE, not the manifest, which can
  # lag behind a write that got partway through. The realistic collision is a
  # product repo declaring a set name that a table in the same repo already uses.
  fx <- local_set_project(set_name = "dm")
  sw_table(fx, "dm")
  v_lb <- sw_table(fx, "lb")

  err <- expect_error(
    datom_write_set(fx$conn, list(sw_member(fx, "lb", v_lb)), name = "dm"),
    class = "datom_artifact_kind_conflict"
  )
  expect_match(conditionMessage(err), "table")
  expect_match(conditionMessage(err), "datom_write")
})

test_that("a table cannot be written over an existing set of the same name", {
  # The converse, and the more damaging direction: a table write would rewrite
  # the set's metadata and history under the same key.
  fx <- local_set_project()
  members <- sw_one_member(fx)
  sw_write(fx, members)

  err <- expect_error(
    datom_write(fx$conn, data = sw_data(3), name = fx$set_name),
    class = "datom_artifact_kind_conflict"
  )
  expect_match(conditionMessage(err), "set")
  expect_match(conditionMessage(err), "datom_write_set")
})

test_that("an untyped metadata document reads as a table, so an old table still blocks a set", {
  # Every document written before `kind` existed describes a table, because sets
  # did not exist.
  current <- list(data_sha = strrep("a", 64L))

  expect_error(
    .datom_check_artifact_kind(current, "dm", "set"),
    class = "datom_artifact_kind_conflict"
  )
  expect_silent(.datom_check_artifact_kind(current, "dm", "table"))
  expect_silent(.datom_check_artifact_kind(NULL, "dm", "set"))
})

test_that("an unrecognised kind on the document falls through to a usable message", {
  # `found` comes off a document, so a value neither kind uses must not raise a
  # subscript error inside the function that exists to explain the problem.
  expect_error(
    .datom_check_artifact_kind(list(kind = "sculpture"), "dm", "set"),
    class = "datom_artifact_kind_conflict"
  )
})
