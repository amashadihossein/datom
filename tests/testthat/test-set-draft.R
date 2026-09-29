# Assembling a set in steps: `datom_assemble_set()`, the add verb, and the write
# of what they build -- including the write's refusal of a set that belongs to
# another repo.
#
# Almost everything here runs against a real git repo, a real bare remote and a
# real local store, because what this path claims is about the COMPOSITION -- the
# payload it produces has to be byte-identical to the one the direct form
# produces, and that cannot be checked against a mock of the write.
#
# FOUR OF THESE ARE THE TESTS A PLAUSIBLE IMPLEMENTATION PASSES EVERYTHING ELSE
# WHILE FAILING.
#
#   * AN ASSEMBLED SET HOLDS NO CONNECTION. Asserted on the serialized bytes, for
#     a token value the fixture invents, so a connection smuggled back onto the
#     object reddens it however it is named.
#   * THREE ROUTES, ONE `data_sha` -- a plain list, a set read back, and an
#     assembled set. They reach the write through one argument now, and a change
#     to the unpack that drops a route leaves every other test green.
#   * A SET FROM ANOTHER REPO STOPS AT THE WRITE. The project half needs two
#     product repos declaring the SAME set name: with different names the name
#     check fires first and removing the project check leaves the test green.
#   * EVERY ADD IS LOGGED, so an assembled set's first write names its adds.
#     Asserted on the commit, since the write's return value cannot tell a
#     logged add from an unlogged one.


# --- fixture ------------------------------------------------------------------

#' Real product project: git repo + bare remote + local store + product config.
#'
#' Same shape and same reason as the fixtures in `test-write-set.R` and
#' `test-set-members.R`; duplicated because testthat does not share definitions
#' between test files. Parameterised on project name, set name and storage prefix
#' so a second, genuinely separate project can be built for the cross-project
#' cases. `gov_root` stays NULL so `.datom_check_ref_current()` takes its
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
sd_add <- function(...) suppressMessages(datom_add_member(...))

sd_payload <- function(fx, name = fx$set_name) {
  jsonlite::read_json(fs::path(fx$repo_dir, name, "set.json"))
}

# Everything a write could leave behind: the commit, every file in the clone
# (datom's dot-directories included), and every object in the store.
sd_state <- function(fx) {
  files <- function(dir) {
    all <- fs::dir_ls(dir, recurse = TRUE, all = TRUE, type = "file")
    sort(as.character(all[!grepl("/\\.git/", all)]))
  }
  list(
    head = git2r::sha(git2r::last_commit(fx$repo)),
    repo = files(fx$repo_dir),
    store = files(fx$store_dir)
  )
}


# === datom_assemble_set =======================================================

test_that("assembling returns an empty datom_set, shaped like a read one", {
  fx <- local_draft_project()
  x <- datom_assemble_set(fx$conn, tags = list(description = "Two tables"))

  expect_s3_class(x, "datom_set")
  expect_false(inherits(x, "datom_set_draft"))
  expect_length(x$members, 0L)
  expect_identical(x$tags, list(description = "Two tables"))
  expect_identical(x$project, "set-project")
  expect_null(x$version)
  expect_null(x$data_sha)
  # NULL, not the declared name: the repo's declaration is read at write time,
  # by the same gate a direct write goes through.
  expect_null(x$name)
  # The same fields, in the same order, as `datom_get_set()` returns.
  expect_identical(
    names(x), c("name", "project", "version", "data_sha", "tags", "members")
  )

  # No tags: the field is still there, empty.
  bare <- datom_assemble_set(fx$conn)
  expect_true("tags" %in% names(bare))
  expect_null(bare$tags)
})

test_that("an assembled set holds no connection, even once members are added", {
  # A connection may carry a credential, so it is passed on each call and never
  # kept on a value that can be saved. Searched for the token VALUE the fixture
  # invents, in the serialized bytes, so no field name can hide it.
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")
  x <- datom_assemble_set(fx$conn) |> sd_add("dm", v, conn = fx$conn)

  expect_false("conn" %in% names(x))
  bytes <- serialize(x, NULL)
  expect_length(grepRaw("SUPER-SECRET-TOKEN-XYZ", bytes, fixed = TRUE), 0L)
})

test_that("assembling needs a connection, and the message says why", {
  err <- expect_error(
    datom_assemble_set("not-a-conn"),
    class = "datom_not_a_conn"
  )
  expect_match(conditionMessage(err), "records the project")
})

test_that("a malformed set-level tag map aborts when the set is started", {
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

test_that("a supplied set name is validated when the set is started", {
  fx <- local_draft_project()
  expect_error(datom_assemble_set(fx$conn, name = "Not A Name!"))
})


# === datom_add_member =========================================================

test_that("adding by name resolves the artifact and appends one linked member", {
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")

  x <- datom_assemble_set(fx$conn) |>
    sd_add("dm", v, tags = list(type = "input"), conn = fx$conn)

  expect_s3_class(x, "datom_set")
  expect_length(x$members, 1L)
  m <- x$members[[1L]]
  expect_identical(m$id$name, "dm")
  expect_identical(m$id$version, v)
  expect_identical(m$id$project, "set-project")
  expect_identical(m$tags, list(type = "input"))
  # Like every member of a set read back, it resolves with one call.
  expect_true(is.function(m$fetch))
  expect_identical(nrow(m$fetch(fx$conn)), 3L)
})

test_that("every add prints the not-written line, the first one included", {
  # There is one rule for every edit verb: say that nothing has been written.
  # A set just assembled is no exception, since it has not been written either.
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")

  expect_message(
    datom_add_member(datom_assemble_set(fx$conn), "dm", v, conn = fx$conn),
    "Nothing has been written"
  )
})

test_that("every add is logged, the first one included", {
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  v_lb <- sd_table(fx, "lb")

  x <- datom_assemble_set(fx$conn) |>
    sd_add("dm", v_dm, conn = fx$conn) |>
    sd_add("lb", v_lb, conn = fx$conn)

  edits <- attr(x, "datom_edits")
  expect_identical(edits$action, c("add", "add"))
  expect_identical(edits$name, c("dm", "lb"))
  expect_identical(edits$to, c(v_dm, v_lb))
  expect_true(all(is.na(edits$from)))
})

test_that("a name added without conn stops, whichever set it is added to", {
  # A set holds no connection, so there is no fallback to reach for.
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")

  err <- expect_error(
    datom_add_member(datom_assemble_set(fx$conn), "dm", v),
    class = "datom_member_conn_required"
  )
  expect_match(conditionMessage(err), "conn = conn", fixed = TRUE)
})

test_that("a missing version aborts naming the member, not at the write", {
  # `version` is required because inferring "current" would make a build script
  # produce a different set on each run from byte-identical source.
  fx <- local_draft_project()
  sd_table(fx, "dm")

  err <- expect_error(
    datom_add_member(datom_assemble_set(fx$conn), "dm", conn = fx$conn),
    class = "datom_member_version_required"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "dm")
  expect_match(msg, "datom_history")
})

test_that("a malformed tag map aborts at its own datom_add_member() call", {
  # The whole reason this path exists: the error names the member that caused it,
  # and the set built so far is untouched.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  v_lb <- sd_table(fx, "lb")

  x <- datom_assemble_set(fx$conn) |> sd_add("dm", v_dm, conn = fx$conn)

  expect_error(
    datom_add_member(x, "lb", v_lb, tags = list(type = 1L), conn = fx$conn),
    "must be text"
  )
  expect_length(x$members, 1L)
})

test_that("a member that does not exist aborts on the line that added it", {
  fx <- local_draft_project()
  expect_error(
    datom_add_member(datom_assemble_set(fx$conn), "dm", strrep("a", 64L),
                     conn = fx$conn),
    "not found"
  )
})

test_that("a record and a link are accepted in place of a name, with no conn", {
  # Both shapes reach the same member, and the record shape is what a
  # cross-project member and a read-modify-write loop both travel on.
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")
  record <- datom_member(fx$conn, "dm", v, tags = list(type = "input"))

  sd_write(fx$conn, list(record))
  x <- datom_get_set(fx$conn, fx$set_name)

  by_record <- datom_assemble_set(fx$conn) |> sd_add(record)
  by_link <- datom_assemble_set(fx$conn) |> sd_add(x$members[[1L]]$fetch)
  by_read <- datom_assemble_set(fx$conn) |> sd_add(x$members[[1L]])

  # A record is appended exactly as supplied, plus its link.
  expect_identical(.datom_strip_member_links(by_record$members)[[1L]], record)

  # These two are compared field by field instead, because the write sorts each
  # `id`'s keys -- so a record that has been through a write and a read carries
  # the same four facts in alphabetical order. Nothing about what is written or
  # hashed changes, since the encoder sorts keys itself, which is exactly why the
  # assertion has to name the fields rather than compare records.
  same_pointer <- function(m) {
    expect_identical(m$id[c("project", "name", "kind", "version")], record$id)
    expect_identical(m$tags, record$tags)
    expect_true(is.function(m$fetch))
  }
  same_pointer(by_link$members[[1L]])
  same_pointer(by_read$members[[1L]])
  # The read member's own link is replaced by one built for the new set, so no
  # link travels between sets unrebuilt.
  expect_false(identical(by_read$members[[1L]]$fetch, x$members[[1L]]$fetch))
})

test_that("a version or tags beside a record or a link is refused, not ignored", {
  # Ignoring them would add a member pinned to a version the caller did not ask
  # for, and report success.
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")
  record <- datom_member(fx$conn, "dm", v)
  x <- datom_assemble_set(fx$conn)

  err <- expect_error(
    datom_add_member(x, record, version = v),
    class = "datom_member_declared_twice"
  )
  expect_match(conditionMessage(err), "a member record")

  expect_error(
    datom_add_member(x, record, tags = list(type = "input")),
    class = "datom_member_declared_twice"
  )

  sd_write(fx$conn, list(record))
  read <- datom_get_set(fx$conn, fx$set_name)
  err_link <- expect_error(
    datom_add_member(x, read$members[[1L]]$fetch, version = v),
    class = "datom_member_declared_twice"
  )
  expect_match(conditionMessage(err_link), "a link")
})

test_that("the count a set reports is the count the write produces", {
  # An exact repeat is dropped by the write, silently, because the digest it
  # dedupes on covers tags. A set that appended it would print one number and
  # write another -- and the printed number is the one a caller inspects mid-pipe.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  v_lb <- sd_table(fx, "lb")

  x <- datom_assemble_set(fx$conn) |>
    sd_add("dm", v_dm, tags = list(type = "input"), conn = fx$conn) |>
    sd_add("lb", v_lb, conn = fx$conn)

  msgs <- testthat::capture_messages(
    x <- datom_add_member(x, "dm", v_dm, tags = list(type = "input"),
                          conn = fx$conn)
  )
  expect_match(paste(msgs, collapse = " "), "already in this set")
  # A skipped repeat changes nothing, so it prints only its own note.
  expect_false(any(grepl("Nothing has been written", msgs)))
  expect_length(x$members, 2L)
  expect_identical(nrow(attr(x, "datom_edits")), 2L)

  res <- sd_write(fx$conn, x)
  expect_identical(res$member_count, length(x$members))
})

test_that("two spellings of one label set are one member, not a conflict", {
  # The write tidies before it dedupes, so `c("a", "b")` and `c("b", "a")` are one
  # member to it. A hand-written comparison here would read them as a conflict and
  # refuse what the write accepts, which is why the check digests both sides.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")

  x <- datom_assemble_set(fx$conn) |>
    sd_add("dm", v_dm, tags = list(domain = c("safety", "efficacy")),
           conn = fx$conn)

  expect_message(
    x <- datom_add_member(
      x, "dm", v_dm, tags = list(domain = c("efficacy", "safety")),
      conn = fx$conn
    ),
    "already in this set"
  )
  expect_length(x$members, 1L)
})

test_that("the same version with different labels aborts on its own line", {
  # Already an error at the write; this only moves it to where this path says
  # errors belong, and the message names both label sets.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")

  x <- datom_assemble_set(fx$conn) |>
    sd_add("dm", v_dm, tags = list(type = "input"), conn = fx$conn)

  err <- expect_error(
    datom_add_member(x, "dm", v_dm, tags = list(type = "output"),
                     conn = fx$conn),
    class = "datom_set_member_conflict"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "already in this set")
  expect_match(msg, "type=input")
  expect_match(msg, "type=output")
  # The set is left as it was, so the caller can fix the line and carry on.
  expect_length(x$members, 1L)
})

test_that("two different versions of one artifact are two members", {
  # The narrowing must not reach this: a current table beside a locked baseline is
  # a legal pair of members, and the write keeps both.
  fx <- local_draft_project()
  v1 <- sd_table(fx, "dm", 3L)
  v2 <- sd_table(fx, "dm", 5L)

  x <- datom_assemble_set(fx$conn) |>
    sd_add("dm", v1, tags = list(release = "baseline"), conn = fx$conn) |>
    sd_add("dm", v2, tags = list(release = "current"), conn = fx$conn)

  expect_length(x$members, 2L)
  res <- sd_write(fx$conn, x)
  expect_identical(res$member_count, 2L)
})

test_that("a malformed record is refused as it is added", {
  fx <- local_draft_project()
  x <- datom_assemble_set(fx$conn)

  # An id field this build cannot place: the write-side contract, run per entry.
  bad <- list(id = list(project = "p", name = "dm", kind = "table",
                        version = strrep("a", 64L), extra = "x"))
  expect_error(datom_add_member(x, bad), "unexpected")

  # And a member that is not a member at all.
  expect_error(
    datom_add_member(x, 42L),
    class = "datom_member_unusable"
  )
})

test_that("the add verb needs a set, and points at how to start one", {
  fx <- local_draft_project()
  err <- expect_error(
    datom_add_member(fx$conn, "dm", strrep("a", 64L)),
    class = "datom_not_a_set"
  )
  expect_match(conditionMessage(err), "datom_assemble_set")
})

test_that("conn must be a connection", {
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")
  expect_error(
    datom_add_member(datom_assemble_set(fx$conn), "dm", v, conn = "nope"),
    class = "datom_not_a_conn"
  )
})


# === the other set verbs take an assembled set ================================

test_that("an assembled set lists, structures and fetches like a read one", {
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  v_lb <- sd_table(fx, "lb", 4L)

  x <- datom_assemble_set(fx$conn) |>
    sd_add("dm", v_dm, tags = list(type = "input"), conn = fx$conn) |>
    sd_add("lb", v_lb, tags = list(type = "output"), conn = fx$conn)

  listed <- datom_list_members(x)
  expect_identical(listed$name, c("dm", "lb"))
  expect_identical(listed$value, c("input", "output"))

  tree <- datom_structure_members(x, by = "type")
  expect_setequal(names(tree), c("input", "output"))

  expect_identical(nrow(datom_fetch_member(fx$conn, x, "lb")), 4L)
})

test_that("an assembled set prints, saying where its name will come from", {
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  v_lb <- sd_table(fx, "lb")

  x <- datom_assemble_set(fx$conn, tags = list(description = "Two")) |>
    sd_add("dm", v_dm, tags = list(type = "input"), conn = fx$conn) |>
    sd_add("lb", v_lb, conn = fx$conn)

  out <- paste(cli::cli_fmt(print(x)), collapse = " ")
  # No name was supplied, which is the usual case, so the header says where the
  # name will come from rather than printing a blank.
  expect_match(out, "the set this repo declares")
  expect_match(out, "set-project")
  expect_match(out, "Version: NA")
  expect_match(out, "dm \\(table\\)")
  expect_match(out, "type=input")
  expect_match(out, "description=Two")
  # An untagged member reads as `-` rather than as a blank the eye skips.
  expect_match(out, "lb \\(table\\)\\s+-")

  named <- paste(
    cli::cli_fmt(print(datom_assemble_set(fx$conn, name = "product-a"))),
    collapse = " "
  )
  expect_match(named, "product-a")
  expect_false(grepl("the set this repo declares", named))
})


# === writing an assembled set =================================================

test_that("an assembled set pipes through the add and list verbs to the write", {
  # The pipe as documented: `conn` on every name, `conn =` on the write, and one
  # member from another project by name. `x |> datom_write_set(conn = conn)`
  # binds `x` to `members` by argument matching.
  fx_a <- local_draft_project("project-a", "product-a", prefix = "proj-a")
  fx_b <- local_draft_project("project-b", "product-b", prefix = "proj-b")
  v_dm <- sd_table(fx_a, "dm")
  v_ae <- sd_table(fx_b, "ae")

  x <- datom_assemble_set(fx_a$conn, tags = list(description = "Piped")) |>
    sd_add("dm", v_dm, tags = list(type = "output"), conn = fx_a$conn) |>
    sd_add("ae", v_ae, tags = list(type = "input"), conn = fx_b$conn)

  expect_setequal(datom_list_members(x)$project, c("project-a", "project-b"))

  res <- x |> sd_write(conn = fx_a$conn)
  expect_identical(res$name, "product-a")
  expect_identical(res$member_count, 2L)
  expect_identical(res$action, "full")

  payload <- sd_payload(fx_a)
  expect_identical(payload$tags$description, "Piped")
  back <- datom_get_set(fx_a$conn, "product-a")
  expect_setequal(
    vapply(back$members, function(m) m$id$name, character(1L)),
    c("dm", "ae")
  )
})

test_that("an assembled set's first write commits the adds it names", {
  # Decided with the owner: the first version's commit says what it holds, with
  # whole versions in the body, rather than a bare `Update {name}`.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  v_lb <- sd_table(fx, "lb")

  x <- datom_assemble_set(fx$conn) |>
    sd_add("dm", v_dm, conn = fx$conn) |>
    sd_add("lb", v_lb, conn = fx$conn)
  sd_write(fx$conn, x)

  commit <- git2r::commits(fx$repo)[[1L]]$message
  expect_match(commit, "Update product-a: add 2 members", fixed = TRUE)
  expect_match(commit, paste0("dm  added at ", v_dm), fixed = TRUE)
  expect_match(commit, paste0("lb  added at ", v_lb), fixed = TRUE)

  recorded <- datom_history(fx$conn, "product-a")$commit_message[[1L]]
  expect_identical(recorded, "Update product-a: add 2 members")
})

test_that("three routes to one write produce the same data_sha", {
  # A plain list, a set read back, and an assembled set, all through `members`.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  record <- datom_member(fx$conn, "dm", v_dm, tags = list(type = "input"))
  tags <- list(description = "One way or another")

  by_list <- sd_write(fx$conn, list(record), tags = tags)

  x <- datom_get_set(fx$conn, fx$set_name)
  by_set <- sd_write(fx$conn, x)

  assembled <- datom_assemble_set(fx$conn, tags = tags) |> sd_add(record)
  by_assembled <- sd_write(fx$conn, assembled)

  expect_identical(by_set$data_sha, by_list$data_sha)
  expect_identical(by_assembled$data_sha, by_list$data_sha)
  # Identical content, so the two later writes mint nothing.
  expect_identical(by_set$action, "none")
  expect_identical(by_assembled$action, "none")
})

test_that("tags supplied beside an assembled set win over its own", {
  # The set's tags are DEFAULTS: an explicit value wins, so a set can be written
  # under different labels without rebuilding it.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")

  x <- datom_assemble_set(fx$conn, tags = list(description = "From the set")) |>
    sd_add("dm", v_dm, conn = fx$conn)

  sd_write(fx$conn, x, tags = list(description = "From the call"),
           name = "product-a")

  expect_identical(sd_payload(fx)$tags$description, "From the call")
})

test_that("an assembled set goes through the gates exactly as a direct write", {
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  x <- datom_assemble_set(fx$conn) |> sd_add("dm", v_dm, conn = fx$conn)

  cfg_path <- fs::path(fx$repo_dir, ".datom", "project.yaml")
  cfg <- yaml::read_yaml(cfg_path)
  cfg$mode <- NULL
  yaml::write_yaml(cfg, cfg_path)

  expect_error(datom_write_set(fx$conn, x), class = "datom_set_mode_required")
})

test_that("a set in the connection's place is refused, showing the call shape", {
  # The call a caller used to type, `datom_write_set(x)`, lands here. The message
  # shows both spellings of the one that works.
  fx <- local_draft_project()
  v_dm <- sd_table(fx, "dm")
  x <- datom_assemble_set(fx$conn) |> sd_add("dm", v_dm, conn = fx$conn)

  err <- expect_error(datom_write_set(x))
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "datom_conn")
  expect_match(msg, "datom_write_set(conn, x)", fixed = TRUE)
  expect_match(msg, "x |> datom_write_set(conn = conn)", fixed = TRUE)
})


# === a set is written into its own repo =======================================

test_that("a set named for another repo's set stops at the write, writing nothing", {
  fx_a <- local_draft_project("project-a", "product-a", prefix = "proj-a")
  fx_b <- local_draft_project("project-b", "product-b", prefix = "proj-b")
  v_b <- sd_table(fx_b, "ae")
  sd_write(fx_b$conn, list(datom_member(fx_b$conn, "ae", v_b)))
  x_b <- datom_get_set(fx_b$conn, "product-b")

  before <- sd_state(fx_a)
  expect_error(
    datom_write_set(fx_a$conn, x_b),
    class = "datom_set_name_mismatch", inherit = FALSE
  )
  expect_identical(sd_state(fx_a), before)
})

test_that("a name argument that disagrees with the set's own name stops the write", {
  # Same project and a name that matches the repo, so only this check can fire:
  # the set says one name, the call another, and preferring either would write
  # under a name one of them did not say.
  fx <- local_draft_project()
  v <- sd_table(fx, "dm")
  x <- datom_assemble_set(fx$conn, name = "not-this-one") |>
    sd_add("dm", v, conn = fx$conn)

  before <- sd_state(fx)
  err <- expect_error(
    datom_write_set(fx$conn, x, name = "product-a"),
    class = "datom_set_name_mismatch", inherit = FALSE
  )
  expect_match(conditionMessage(err), "the set you passed")
  expect_identical(sd_state(fx), before)
})

test_that("a set from another project stops the write, even under the same name", {
  # Two studies, each with a set called `adam`: the name check passes, so only
  # the project check can stop B's set being re-homed into A.
  fx_a <- local_draft_project("project-a", "adam", prefix = "proj-a")
  fx_b <- local_draft_project("project-b", "adam", prefix = "proj-b")
  v_b <- sd_table(fx_b, "ae")
  sd_write(fx_b$conn, list(datom_member(fx_b$conn, "ae", v_b)))
  x_b <- datom_get_set(fx_b$conn, "adam")

  before <- sd_state(fx_a)
  err <- expect_error(
    datom_write_set(fx_a$conn, x_b),
    class = "datom_set_project_mismatch", inherit = FALSE
  )
  msg <- conditionMessage(err)
  expect_match(msg, "project-a")
  expect_match(msg, "project-b")
  expect_identical(sd_state(fx_a), before)

  # An assembled set is held to the same rule: its project is the connection it
  # was started on.
  assembled <- datom_assemble_set(fx_b$conn) |>
    sd_add("ae", v_b, conn = fx_b$conn)
  expect_error(
    datom_write_set(fx_a$conn, assembled),
    class = "datom_set_project_mismatch", inherit = FALSE
  )
  expect_identical(sd_state(fx_a), before)

  # The remedy the message gives works: the members alone carry no project
  # claim, so they build A's own set.
  res <- sd_write(fx_a$conn, x_b$members)
  expect_identical(res$action, "full")
  expect_identical(
    datom_get_set(fx_a$conn, "adam")$members[[1L]]$id$project, "project-b"
  )
})


# === cross-project members ====================================================

test_that("a member of another project is added as a record, and is written", {
  # A record built on the other project's connection needs no `conn`, and the
  # written payload has to record B.
  fx_a <- local_draft_project("project-a", "product-a", prefix = "proj-a")
  fx_b <- local_draft_project("project-b", "product-b", prefix = "proj-b")

  v_a <- sd_table(fx_a, "dm")
  v_b <- sd_table(fx_b, "ae")

  other <- datom_member(fx_b$conn, "ae", v_b, tags = list(type = "input"))
  expect_identical(other$id$project, "project-b")

  res <- datom_assemble_set(fx_a$conn) |>
    sd_add("dm", v_a, conn = fx_a$conn) |>
    sd_add(other) |>
    sd_write(conn = fx_a$conn)
  expect_identical(res$member_count, 2L)

  projects <- vapply(
    sd_payload(fx_a)$members, function(m) m$id$project, character(1L)
  )
  expect_setequal(projects, c("project-a", "project-b"))

  # By name through the WRONG project's connection it is unreachable: A's
  # storage holds no "ae".
  expect_error(
    datom_add_member(datom_assemble_set(fx_a$conn), "ae", v_b,
                     conn = fx_a$conn),
    "not found"
  )
})

test_that("conn = resolves one name in the project it is for", {
  fx_a <- local_draft_project("project-a", "product-a", prefix = "proj-a")
  fx_b <- local_draft_project("project-b", "product-b", prefix = "proj-b")
  v_b <- sd_table(fx_b, "ae")

  x <- datom_assemble_set(fx_a$conn) |>
    sd_add("ae", v_b, tags = list(type = "input"), conn = fx_b$conn)

  expect_identical(x$members[[1L]]$id$project, "project-b")
  expect_identical(x$members[[1L]]$id$version, v_b)
  expect_identical(x$members[[1L]]$tags, list(type = "input"))
  # The set is still A's: the connection used for one name is not kept.
  expect_identical(x$project, "project-a")
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

test_that("a connection placed on a set by hand is not borrowed", {
  # A set holds none, so one found there was put there by hand, and using it
  # would resolve a name through a connection nobody passed.
  fx <- local_draft_project()
  x <- sd_saved_set(fx)
  v_lb <- sd_table(fx, "lb")

  x$conn <- fx$conn
  expect_error(
    datom_add_member(x, "lb", v_lb),
    class = "datom_member_conn_required"
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

  err <- expect_error(
    datom_add_member(x, "dm", v_dm, tags = list(type = "output"),
                     conn = fx$conn),
    class = "datom_set_member_conflict"
  )
  expect_match(conditionMessage(err), "already in this set")
})
