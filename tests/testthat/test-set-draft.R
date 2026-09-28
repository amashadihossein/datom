# Assembling a set in steps: the draft, the add verb, its print method, and the
# widening that lets a pipe end at the write.
#
# Almost everything here runs against a real git repo, a real bare remote and a
# real local store, because what this path claims is about the COMPOSITION -- the
# payload it produces has to be byte-identical to the one the direct form
# produces, and that cannot be checked against a mock of the write.
#
# FOUR OF THESE ARE THE TESTS A PLAUSIBLE IMPLEMENTATION PASSES EVERYTHING ELSE
# WHILE FAILING.
#
#   * `datom_write_set(draft)` on its own. `members` is MISSING there, not NULL,
#     so an implementation reaching for `is.null(members)` errors with R's own
#     "argument is missing" on the correct call rather than the incorrect one.
#   * THREE ROUTES, ONE `data_sha` -- a plain list, a set read back, and a draft.
#     The two widenings sit on two different parameters, and a change that
#     collapses them into one branch drops a route while every other test passes.
#   * A CROSS-PROJECT MEMBER added as a record: a draft holds one connection, so
#     without `conn =` a name only reaches its own project. Asserted on the
#     written payload, which is where the other project's name has to survive.
#   * A DRAFT'S PRINT METHOD MUST NOT REACH THE CONNECTION'S TOKEN. The fixture
#     puts a recognisable one on the conn so the assertion is real rather than
#     vacuous.


# --- fixture ------------------------------------------------------------------

#' Real product project: git repo + bare remote + local store + product config.
#'
#' Same shape and same reason as the fixtures in `test-write-set.R` and
#' `test-set-members.R`; duplicated because testthat does not share definitions
#' between test files. Parameterised on project name, set name and storage prefix
#' so a second, genuinely separate project can be built for the cross-project
#' case. `gov_root` stays NULL so `.datom_check_ref_current()` takes its
#' legacy-conn skip.
local_draft_project <- function(project_name = "set-project",
                                set_name = "product-a",
                                prefix = "proj",
                                env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)

  repo_dir <- fs::path(root, "repo")
  store_dir <- fs::path(root, "store")
  bare_dir <- fs::path(root, "remote.git")
  fs::dir_create(c(repo_dir, store_dir, bare_dir))

  git2r::init(bare_dir, bare = TRUE)
  repo <- git2r::init(repo_dir)
  git2r::config(repo, user.name = "Draft Test", user.email = "draft@test.com")
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

  write_product_config(repo_dir, project_name, set_name)

  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir,
       repo = repo, set_name = set_name)
}

sd_data <- function(n = 3L) {
  data.frame(id = seq_len(n), val = letters[seq_len(n)],
             stringsAsFactors = FALSE)
}

# Write a table and return the version just minted, which is what a member pins.
sd_table <- function(fx, name, n = 3L) {
  suppressMessages(datom_write(fx$conn, data = sd_data(n), name = name))
  datom_history(fx$conn, name, short_hash = FALSE)$version[[1L]]
}

sd_write <- function(...) suppressMessages(datom_write_set(...))

sd_payload <- function(fx, name = fx$set_name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "set.json"))
}


# === datom_assemble_set =======================================================

test_that("a draft opens empty, carrying its connection, name and tags", {
  fx <- local_draft_project()
  draft <- datom_assemble_set(fx$conn, tags = list(description = "Two tables"))

  expect_s3_class(draft, "datom_set_draft")
  expect_length(draft$members, 0L)
  expect_identical(draft$conn, fx$conn)
  expect_identical(draft$tags, list(description = "Two tables"))
  # NULL, not the declared name: the repo's declaration is read at write time,
  # by the same gate a direct write goes through.
  expect_null(draft$name)
})

test_that("a draft needs a connection, and the message says why", {
  err <- expect_error(
    datom_assemble_set("not-a-conn"),
    class = "datom_not_a_conn"
  )
  # The reason is what stops somebody "fixing" this by dropping the argument:
  # per-entry validation reads the member's snapshot through this connection.
  expect_match(conditionMessage(err), "validates each member")
})

test_that("a malformed set-level tag map aborts when the draft is opened", {
  # Not at the write. Validating here is what puts the error on the line that
  # wrote the label.
  fx <- local_draft_project()
  expect_error(
    datom_assemble_set(fx$conn, tags = list(description = 42L)),
    "must be text"
  )
  expect_error(
    datom_assemble_set(fx$conn, tags = list(description = "")),
    "empty label"
  )
})

test_that("a supplied set name is validated when the draft is opened", {
  fx <- local_draft_project()
  expect_error(datom_assemble_set(fx$conn, name = "Not A Name!"))
})


# === datom_add_member =========================================================

test_that("adding by name resolves the artifact and appends one member", {
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")

  draft <- datom_assemble_set(fx$conn) |>
    datom_add_member("dm", v, tags = list(type = "input"))

  expect_s3_class(draft, "datom_set_draft")
  expect_length(draft$members, 1L)
  expect_identical(draft$members[[1L]]$id$name, "dm")
  expect_identical(draft$members[[1L]]$id$version, v)
  expect_identical(draft$members[[1L]]$id$project, "set-project")
  expect_identical(draft$members[[1L]]$tags, list(type = "input"))
})

test_that("a missing version aborts naming the member, not at the write", {
  # `version` is required because inferring "current" would make a build script
  # produce a different set on each run from byte-identical source.
  fx <- local_draft_project()
  sd_table(fx, "dm")

  err <- expect_error(
    datom_add_member(datom_assemble_set(fx$conn), "dm"),
    class = "datom_member_version_required"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "dm")
  expect_match(msg, "datom_history")
})

test_that("a malformed tag map aborts at its own datom_add_member() call", {
  # The whole reason this path exists: the error names the member that caused it,
  # and the draft built so far is untouched.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  v_lb <- sd_table(fx, "lb")

  draft <- datom_assemble_set(fx$conn) |> datom_add_member("dm", v_dm)

  expect_error(
    datom_add_member(draft, "lb", v_lb, tags = list(type = 1L)),
    "must be text"
  )
  expect_length(draft$members, 1L)
})

test_that("a member that does not exist aborts on the line that added it", {
  fx <- local_draft_project()
  expect_error(
    datom_add_member(datom_assemble_set(fx$conn), "dm", strrep("a", 64L)),
    "not found"
  )
})

test_that("a record and a link are accepted in place of a name", {
  # Both shapes reach the same member, and the record shape is what a
  # cross-project member and a read-modify-write loop both travel on.
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")
  record <- datom_member(fx$conn, "dm", v, tags = list(type = "input"))

  sd_write(fx$conn, list(record))
  x <- datom_get_set(fx$conn, fx$set_name)

  by_record <- datom_assemble_set(fx$conn) |> datom_add_member(record)
  by_link <- datom_assemble_set(fx$conn) |>
    datom_add_member(x$members[[1L]]$fetch)
  by_read <- datom_assemble_set(fx$conn) |>
    datom_add_member(x$members[[1L]])

  # A record is appended exactly as supplied, so this one compares whole.
  expect_identical(by_record$members[[1L]], record)

  # These two are compared field by field instead, because the write sorts each
  # `id`'s keys -- so a record that has been through a write and a read carries
  # the same four facts in alphabetical order. Nothing about what is written or
  # hashed changes, since the encoder sorts keys itself, which is exactly why the
  # assertion has to name the fields rather than compare records.
  same_pointer <- function(m) {
    expect_identical(m$id[c("project", "name", "kind", "version")], record$id)
    expect_identical(m$tags, record$tags)
  }
  same_pointer(by_link$members[[1L]])
  # A read member carries a callable `fetch`; it is stripped, so what lands in the
  # draft is payload-shaped rather than a link inside a member.
  same_pointer(by_read$members[[1L]])
  expect_false("fetch" %in% names(by_read$members[[1L]]))
})

test_that("a version or tags beside a record or a link is refused, not ignored", {
  # Ignoring them would add a member pinned to a version the caller did not ask
  # for, and report success.
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")
  record <- datom_member(fx$conn, "dm", v)
  draft <- datom_assemble_set(fx$conn)

  err <- expect_error(
    datom_add_member(draft, record, version = v),
    class = "datom_member_declared_twice"
  )
  expect_match(conditionMessage(err), "a member record")

  expect_error(
    datom_add_member(draft, record, tags = list(type = "input")),
    class = "datom_member_declared_twice"
  )

  sd_write(fx$conn, list(record))
  x <- datom_get_set(fx$conn, fx$set_name)
  err_link <- expect_error(
    datom_add_member(draft, x$members[[1L]]$fetch, version = v),
    class = "datom_member_declared_twice"
  )
  expect_match(conditionMessage(err_link), "a link")
})

test_that("the count a draft reports is the count the write produces", {
  # An exact repeat is dropped by the write, silently, because the digest it
  # dedupes on covers tags. A draft that appended it would print one number and
  # write another -- and the printed number is the one a caller inspects mid-pipe.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  v_lb <- sd_table(fx, "lb")

  draft <- datom_assemble_set(fx$conn) |>
    datom_add_member("dm", v_dm, tags = list(type = "input")) |>
    datom_add_member("lb", v_lb)

  expect_message(
    draft <- datom_add_member(draft, "dm", v_dm, tags = list(type = "input")),
    "already in this draft"
  )
  expect_length(draft$members, 2L)

  res <- sd_write(draft)
  expect_identical(res$member_count, length(draft$members))
})

test_that("two spellings of one label set are one member, not a conflict", {
  # The write tidies before it dedupes, so `c("a", "b")` and `c("b", "a")` are one
  # member to it. A hand-written comparison here would read them as a conflict and
  # refuse what the write accepts, which is why the check digests both sides after
  # tidying.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")

  draft <- datom_assemble_set(fx$conn) |>
    datom_add_member("dm", v_dm, tags = list(domain = c("safety", "efficacy")))

  expect_message(
    draft <- datom_add_member(
      draft, "dm", v_dm, tags = list(domain = c("efficacy", "safety"))
    ),
    "already in this draft"
  )
  expect_length(draft$members, 1L)
})

test_that("the same version with different labels aborts on its own line", {
  # Already an error at the write; this only moves it to where this path says
  # errors belong, and the message names both label sets.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")

  draft <- datom_assemble_set(fx$conn) |>
    datom_add_member("dm", v_dm, tags = list(type = "input"))

  err <- expect_error(
    datom_add_member(draft, "dm", v_dm, tags = list(type = "output")),
    class = "datom_set_member_conflict"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "type=input")
  expect_match(msg, "type=output")
  # The draft is left as it was, so the caller can fix the line and carry on.
  expect_length(draft$members, 1L)
})

test_that("two different versions of one artifact are two members", {
  # The narrowing must not reach this: a current table beside a locked baseline is
  # a legal pair of members, and the write keeps both.
  fx <- local_draft_project()
  v1 <- sd_table(fx, "dm", 3L)
  v2 <- sd_table(fx, "dm", 5L)

  draft <- datom_assemble_set(fx$conn) |>
    datom_add_member("dm", v1, tags = list(release = "baseline")) |>
    datom_add_member("dm", v2, tags = list(release = "current"))

  expect_length(draft$members, 2L)
  res <- sd_write(draft)
  expect_identical(res$member_count, 2L)
})

test_that("a malformed record is refused as it is added", {
  fx <- local_draft_project()
  draft <- datom_assemble_set(fx$conn)

  # An id field this build cannot place: the write-side contract, run per entry.
  bad <- list(id = list(project = "p", name = "dm", kind = "table",
                        version = strrep("a", 64L), extra = "x"))
  expect_error(datom_add_member(draft, bad), "unexpected")

  # And a member that is not a member at all.
  expect_error(
    datom_add_member(draft, 42L),
    class = "datom_member_unusable"
  )
})

test_that("the add verb needs a draft, and points at how to open one", {
  fx <- local_draft_project()
  err <- expect_error(
    datom_add_member(fx$conn, "dm", strrep("a", 64L)),
    class = "datom_not_a_draft"
  )
  expect_match(conditionMessage(err), "datom_assemble_set")
})


# === print.datom_set_draft ====================================================

test_that("a draft prints its members and says it is not written yet", {
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  v_lb <- sd_table(fx, "lb")

  draft <- datom_assemble_set(fx$conn, tags = list(description = "Two")) |>
    datom_add_member("dm", v_dm, tags = list(type = "input")) |>
    datom_add_member("lb", v_lb)

  out <- paste(cli::cli_fmt(print(draft)), collapse = " ")
  expect_match(out, "draft")
  expect_match(out, "set-project")
  # No name was supplied, which is the usual case, so the header says where the
  # name will come from rather than quoting a sentence as if it were one.
  expect_match(out, "the set this repo declares")
  named <- paste(
    cli::cli_fmt(print(datom_assemble_set(fx$conn, name = "product-a"))),
    collapse = " "
  )
  expect_match(named, "product-a")
  expect_match(out, "dm \\(table\\)")
  expect_match(out, "type=input")
  expect_match(out, "description=Two")
  # An untagged member reads as `-` rather than as a blank the eye skips.
  expect_match(out, "lb \\(table\\)\\s+-")
  expect_match(out, "Not written yet")
  # The rule that a draft is transient lives in the docs, but the print method is
  # where a user actually meets a draft.
  expect_match(out, "memory only")
})

test_that("a draft's print method never reaches the connection's token", {
  # The method names every field it shows and is handed no object to summarise --
  # the same allowlist shape `print.datom_conn` has, so a credential added to a
  # connection later cannot leak through it.
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")
  draft <- datom_assemble_set(fx$conn) |> datom_add_member("dm", v)

  out <- paste(cli::cli_fmt(print(draft)), collapse = " ")
  expect_false(grepl("SUPER-SECRET-TOKEN-XYZ", out, fixed = TRUE))
})

test_that("printing a draft returns it invisibly", {
  fx <- local_draft_project()
  draft <- datom_assemble_set(fx$conn)
  cli::cli_fmt(shown <- withVisible(print(draft)))
  expect_false(shown$visible)
  expect_identical(shown$value, draft)
})

test_that("a long member list is truncated with a count of the rest", {
  fx <- local_draft_project()
  draft <- datom_assemble_set(fx$conn)
  draft$members <- lapply(1:30, function(i) {
    list(id = list(project = "p", name = paste0("t", i), kind = "table",
                   version = strrep("c", 64L)))
  })
  out <- paste(cli::cli_fmt(print(draft, n = 5L)), collapse = " ")
  expect_match(out, "t5 \\(table\\)")
  expect_false(grepl("t6 \\(table\\)", out))
  expect_match(out, "and 25 more")
})


# === datom_write_set() accepts a draft ========================================

test_that("a pipe ends at the write with nothing typed", {
  # `members` is MISSING on this call, not NULL: an implementation testing
  # `is.null(members)` errors here, on the correct call.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")

  res <- suppressMessages(
    datom_assemble_set(fx$conn, tags = list(description = "Piped")) |>
      datom_add_member("dm", v_dm, tags = list(type = "input")) |>
      datom_write_set()
  )

  expect_identical(res$name, "product-a")
  expect_identical(res$member_count, 1L)
  expect_identical(res$action, "full")

  payload <- sd_payload(fx)
  expect_identical(payload$tags$description, "Piped")
  expect_length(payload$members, 1L)
  expect_identical(payload$members[[1L]]$id$name, "dm")
})

test_that("three routes to one write produce the same data_sha", {
  # A plain list, a set read back, and a draft. The last two are widenings of two
  # DIFFERENT parameters -- `members` and `conn` -- so a change that collapses
  # them into one branch drops a route.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  record <- datom_member(fx$conn, "dm", v_dm, tags = list(type = "input"))
  tags <- list(description = "One way or another")

  by_list <- sd_write(fx$conn, list(record), tags = tags)

  x <- datom_get_set(fx$conn, fx$set_name)
  by_set <- sd_write(fx$conn, x)

  draft <- datom_assemble_set(fx$conn, tags = tags) |>
    datom_add_member(record)
  by_draft <- sd_write(draft)

  expect_identical(by_set$data_sha, by_list$data_sha)
  expect_identical(by_draft$data_sha, by_list$data_sha)
  # Identical content, so the two later writes mint nothing.
  expect_identical(by_set$action, "none")
  expect_identical(by_draft$action, "none")
})

test_that("a draft together with a member list is refused", {
  # With the draft in the `conn` position, `members` is still a formal argument,
  # so this parses. Preferring either one writes a set the caller did not
  # describe.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  record <- datom_member(fx$conn, "dm", v_dm)
  draft <- datom_assemble_set(fx$conn) |> datom_add_member(record)

  expect_error(
    datom_write_set(draft, list(record)),
    class = "datom_draft_members_conflict"
  )
})

test_that("tags and a name supplied beside a draft win over the draft's own", {
  # The draft's are DEFAULTS, exactly as a read set's tags are: an explicit value
  # wins, so a draft can be written under different labels without rebuilding it.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")

  draft <- datom_assemble_set(fx$conn, tags = list(description = "From draft")) |>
    datom_add_member("dm", v_dm)

  sd_write(draft, tags = list(description = "From the call"),
           name = "product-a")

  expect_identical(sd_payload(fx)$tags$description, "From the call")
})

test_that("a draft goes through the gates exactly as a direct write does", {
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  draft <- datom_assemble_set(fx$conn) |> datom_add_member("dm", v_dm)

  cfg_path <- fs::path(fx$repo_dir, ".datom", "project.yaml")
  cfg <- yaml::read_yaml(cfg_path)
  cfg$mode <- NULL
  yaml::write_yaml(cfg, cfg_path)

  expect_error(datom_write_set(draft), class = "datom_set_mode_required")
})

test_that("the conn guard names both shapes it accepts", {
  # It is the message a mistyped pipe lands on, so it is the one that most needs
  # to say a draft is legal there.
  err <- expect_error(datom_write_set("not-a-conn", list()))
  msg <- conditionMessage(err)
  expect_match(msg, "datom_conn")
  expect_match(msg, "datom_set_draft")
})


# === one draft, one connection ================================================

test_that("a member of another project is added as a record, and is", {
  # A draft holds ONE connection and a name is resolved through it unless the
  # call brings its own `conn` (tested below). A record built on the other
  # project's connection needs neither, and the written payload has to record B.
  fx_a <- local_draft_project("project-a", "product-a", prefix = "proj-a")
  fx_b <- local_draft_project("project-b", "product-b", prefix = "proj-b")

  v_a <- sd_table(fx_a, "dm")
  v_b <- sd_table(fx_b, "ae")

  other <- datom_member(fx_b$conn, "ae", v_b, tags = list(type = "input"))
  expect_identical(other$id$project, "project-b")

  res <- suppressMessages(
    datom_assemble_set(fx_a$conn) |>
      datom_add_member("dm", v_a) |>
      datom_add_member(other) |>
      datom_write_set()
  )
  expect_identical(res$member_count, 2L)

  projects <- vapply(
    sd_payload(fx_a)$members, function(m) m$id$project, character(1L)
  )
  expect_setequal(projects, c("project-a", "project-b"))

  # By name WITHOUT `conn` it is unreachable: the draft's connection looks in
  # project A's storage, where "ae" does not exist.
  expect_error(
    datom_add_member(datom_assemble_set(fx_a$conn), "ae", v_b),
    "not found"
  )
})

test_that("conn = resolves one name in another project and leaves the draft's", {
  # The draft still holds exactly one connection afterwards: `conn` is used for
  # that one lookup and never stored.
  fx_a <- local_draft_project("project-a", "product-a", prefix = "proj-a")
  fx_b <- local_draft_project("project-b", "product-b", prefix = "proj-b")
  v_b <- sd_table(fx_b, "ae")

  draft <- datom_assemble_set(fx_a$conn) |>
    datom_add_member("ae", v_b, tags = list(type = "input"), conn = fx_b$conn)

  expect_s3_class(draft, "datom_set_draft")
  expect_identical(draft$members[[1L]]$id$project, "project-b")
  expect_identical(draft$members[[1L]]$id$version, v_b)
  expect_identical(draft$members[[1L]]$tags, list(type = "input"))
  expect_identical(draft$conn, fx_a$conn)
})


# === datom_add_member() on a set read back ====================================

# A product holding one input, written and read back: the object a caller has in
# hand when they add an output to a set that already exists.
sd_saved_set <- function(fx) {
  v_dm <- sd_table(fx, "dm")
  sd_write(fx$conn, list(
    datom_member(fx$conn, "dm", v_dm, tags = list(type = "input"))
  ))
  datom_get_set(fx$conn, fx$set_name)
}

sd_add <- function(...) suppressMessages(datom_add_member(...))

test_that("adding by name with conn to a saved set returns an edited set", {
  fx <- local_draft_project()
  x <- sd_saved_set(fx)
  expect_false(is.null(x$version))
  v_lb <- sd_table(fx, "lb")

  expect_message(
    out <- datom_add_member(x, "lb", v_lb, tags = list(type = "output"),
                            conn = fx$conn),
    "Nothing has been written"
  )

  expect_s3_class(out, "datom_set")
  expect_length(out$members, 2L)
  added <- out$members[[2L]]
  expect_identical(added$id$name, "lb")
  expect_identical(added$id$version, v_lb)
  expect_identical(added$id$project, "set-project")
  expect_identical(added$tags, list(type = "output"))

  # The version it was read as no longer describes what it holds.
  expect_null(out$version)
  expect_null(out$data_sha)
  expect_true(all(c("version", "data_sha") %in% names(out)))

  # Like every other member of a set read back, it resolves with one call.
  expect_true(is.function(added$fetch))
  expect_identical(nrow(added$fetch(fx$conn)), 3L)

  edits <- attr(out, "datom_edits")
  expect_identical(nrow(edits), 1L)
  expect_identical(edits$action, "add")
  expect_identical(edits$name, "lb")
  expect_identical(edits$kind, "table")
  expect_identical(edits$project, "set-project")
  expect_true(is.na(edits$from))
  expect_identical(edits$to, v_lb)
})

test_that("adding a record to a saved set needs no conn and records the add", {
  fx <- local_draft_project()
  x <- sd_saved_set(fx)
  v_lb <- sd_table(fx, "lb")
  record <- datom_member(fx$conn, "lb", v_lb, tags = list(type = "output"))

  out <- sd_add(x, record)

  expect_s3_class(out, "datom_set")
  expect_length(out$members, 2L)
  expect_identical(out$members[[2L]]$id$version, v_lb)
  expect_identical(attr(out, "datom_edits")$action, "add")
})

test_that("a name added to a saved set without conn is refused, naming conn", {
  fx <- local_draft_project()
  x <- sd_saved_set(fx)
  v_lb <- sd_table(fx, "lb")

  err <- expect_error(
    datom_add_member(x, "lb", v_lb),
    class = "datom_member_conn_required"
  )
  expect_match(conditionMessage(err), "conn")
})

test_that("a connection placed on a saved set by hand is not borrowed", {
  # A set read back holds none, so one found there was put there by hand, and
  # using it would resolve a name through a connection nobody passed.
  fx <- local_draft_project()
  x <- sd_saved_set(fx)
  v_lb <- sd_table(fx, "lb")

  x$conn <- fx$conn
  expect_error(
    datom_add_member(x, "lb", v_lb),
    class = "datom_member_conn_required"
  )
})

test_that("conn must be a connection", {
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")
  expect_error(
    datom_add_member(datom_assemble_set(fx$conn), "dm", v, conn = "nope"),
    class = "datom_not_a_conn"
  )
})

test_that("the write's commit message names the add, and full versions", {
  fx <- local_draft_project()
  x <- sd_saved_set(fx)
  v_lb <- sd_table(fx, "lb")

  sd_write(fx$conn, sd_add(x, "lb", v_lb, conn = fx$conn))

  commit <- git2r::commits(fx$repo)[[1L]]$message
  expect_match(commit, "Update product-a: add 1 member", fixed = TRUE)
  expect_match(commit, paste0("lb  added at ", v_lb), fixed = TRUE)

  recorded <- datom_history(fx$conn, "product-a")$commit_message[[1L]]
  expect_identical(recorded, "Update product-a: add 1 member")

  # And it is written: reading back shows both members.
  expect_length(datom_get_set(fx$conn, fx$set_name)$members, 2L)
})

test_that("an add chained with a repoint produces one message naming both", {
  fx <- local_draft_project()
  x <- sd_saved_set(fx)
  v_dm_old <- x$members[[1L]]$id$version
  v_dm_new <- sd_table(fx, "dm", 5L)
  v_lb <- sd_table(fx, "lb")

  edited <- suppressMessages(
    x |>
      datom_update_members(fx$conn) |>
      datom_add_member("lb", v_lb, conn = fx$conn)
  )
  sd_write(fx$conn, edited)

  recorded <- datom_history(fx$conn, "product-a")$commit_message[[1L]]
  # Adds are listed first whichever order the edits happened in.
  expect_identical(recorded, "Update product-a: add 1 member, repoint 1 member")
  commit <- git2r::commits(fx$repo)[[1L]]$message
  expect_match(commit, paste0("dm  ", v_dm_old, " -> ", v_dm_new), fixed = TRUE)
  expect_match(commit, paste0("lb  added at ", v_lb), fixed = TRUE)
})

test_that("adding to a draft logs nothing, so its commit message is unchanged", {
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")

  expect_silent(
    draft <- datom_add_member(datom_assemble_set(fx$conn), "dm", v_dm)
  )
  expect_null(attr(draft, "datom_edits"))

  sd_write(draft)
  expect_identical(git2r::commits(fx$repo)[[1L]]$message, "Update product-a")
})

test_that("a repeat on a saved set is skipped, and a disagreement refused", {
  # The members of a set read back carry `$fetch` links, which the clash check
  # has to look past: the member digest refuses any field but `id` and `tags`.
  fx <- local_draft_project()
  x <- sd_saved_set(fx)
  dm <- x$members[[1L]]
  v_dm <- dm$id$version

  # Exact repeat: skipped with its note only, and nothing about the set changes
  # -- no edit logged, and the version it was read as still describes it.
  msgs <- testthat::capture_messages(
    out <- datom_add_member(x, "dm", v_dm, tags = list(type = "input"),
                            conn = fx$conn)
  )
  expect_match(paste(msgs, collapse = " "), "already in this set")
  expect_false(any(grepl("Nothing has been written", msgs)))
  expect_length(out$members, 1L)
  expect_null(attr(out, "datom_edits"))
  expect_identical(out$version, x$version)

  # Same version, different labels: refused, naming the set rather than a draft.
  err <- expect_error(
    datom_add_member(x, "dm", v_dm, tags = list(type = "output"),
                     conn = fx$conn),
    class = "datom_set_member_conflict"
  )
  expect_match(conditionMessage(err), "already in this set")
})
