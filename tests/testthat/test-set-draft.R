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
#   * A CROSS-PROJECT MEMBER, which is the capability the record shape exists for
#     rather than a convenience: a draft holds one connection, so a member of
#     another project cannot be declared by name at all. Asserted on the written
#     payload, which is where the other project's name has to survive.
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

  expect_identical(by_record$members[[1L]], record)

  # Compared field by field, not with `identical()`: the write sorts each `id`'s
  # keys, so a record that has been through a write and a read carries the same
  # four facts in alphabetical order. That costs nothing -- the hash does not
  # depend on key order, and the write re-canonicalises -- but it is why these two
  # assertions name the fields.
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

test_that("a member of another project can only be added as a record, and is", {
  # THE CAPABILITY THE RECORD SHAPE EXISTS FOR, not a convenience. A draft holds
  # ONE connection and a name is resolved through it, so a member of another
  # project cannot be declared by name at all -- `datom_member(conn_b, ...)` is
  # the only route, and the written payload has to record B.
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

  # By name it is unreachable: the draft's connection looks in project A's
  # storage, where "ae" does not exist.
  expect_error(
    datom_add_member(datom_assemble_set(fx_a$conn), "ae", v_b),
    "not found"
  )
})
