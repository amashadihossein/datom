# Editing a set that already exists: repointing members at newer versions.
#
# TWO KINDS OF FIXTURE, for the reason the other set files use two. Repointing
# reads real documents -- a project manifest to learn what is current, then the
# new version's own snapshot -- so most of this runs against a real repo, a real
# bare remote and a real local store. A few cases can only be built by hand: a
# member recorded in a project nobody supplied a connection for, a label whose
# value is empty, an artifact that is not in the manifest at all.
#
# FOUR OF THESE ARE THE TESTS A PLAUSIBLE IMPLEMENTATION PASSES EVERYTHING ELSE
# WHILE FAILING.
#
#   * The labels test asserts BYTE-IDENTITY and carries a key whose value is
#     empty. The obvious spelling -- rebuild the pointer with the old labels --
#     drops that key silently, and every payload datom wrote is tidied already,
#     so an ordinary fixture cannot see it. The test asserts the naive route
#     really does lose it, so the assertion cannot rot into a tautology.
#   * The link test resolves the repointed member to DATA and counts rows. A
#     member whose `id` moved while its `fetch` did not contradicts itself
#     silently, and every assertion on `id` still passes.
#   * The mislabelled-connection test needs TWO stores. One store cannot tell a
#     wrong label from a right one, because the member and the store then agree.
#   * The no-op test asserts through the WRITE, because "this refresh was free"
#     is observable there and nowhere else.

local_edit_project <- function(project_name = "edit-project",
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
  git2r::config(repo, user.name = "Edit Test", user.email = "edit@test.com")
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
       repo = repo, set_name = set_name, project_name = project_name)
}

se_data <- function(n = 3L) {
  data.frame(id = seq_len(n), val = letters[seq_len(n)],
             stringsAsFactors = FALSE)
}

# Write a table and return the version just minted, which is what a member pins.
se_table <- function(fx, name, n = 3L) {
  suppressMessages(datom_write(fx$conn, data = se_data(n), name = name))
  datom_history(fx$conn, name, short_hash = FALSE)$version[[1L]]
}

se_write <- function(...) suppressMessages(datom_write_set(...))

se_update <- function(...) suppressMessages(datom_update_members(...))

# A hand-built set over a real project, which is how the cases a writer refuses
# are reached.
se_member <- function(name, version, project = "edit-project",
                      kind = "table", tags = NULL) {
  m <- list(id = list(project = project, name = name, kind = kind,
                      version = version))
  if (!is.null(tags)) m$tags <- tags
  m
}

se_set <- function(..., name = "product-a", project = "edit-project") {
  structure(
    list(name = name, project = project, version = strrep("f", 64L),
         data_sha = strrep("e", 64L), tags = NULL, members = list(...)),
    class = "datom_set"
  )
}

se_versions <- function(fx, name) {
  datom_history(fx$conn, name, short_hash = FALSE)$version
}

se_messages <- function(expr) {
  cli::ansi_strip(paste(testthat::capture_messages(expr), collapse = ""))
}


# === labels ====================================================================

test_that("a repointed member's labels are byte-identical, empty key included", {
  # AC40(a). The obvious spelling is
  # `datom_member(conn, name, new_version, tags = old$tags)`, and `datom_member()`
  # drops a key whose value is empty -- so the set's identity would move for a
  # reason nobody asked for.
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  labels <- list(type = "output", domain = character(0))
  x <- se_set(se_member("dm", v1, tags = labels))
  v2 <- se_table(fx, "dm", 4L)

  out <- se_update(x, fx$conn)

  expect_identical(out$members[[1L]]$id$version, v2)
  expect_identical(out$members[[1L]]$tags, labels)

  # The naive route really does lose it, so the assertion above is not a
  # tautology that survives a rewrite.
  expect_false(
    identical(datom_member(fx$conn, "dm", v2, tags = labels)$tags, labels)
  )
})

test_that("a member with no labels does not grow a tags field", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))
  se_table(fx, "dm", 4L)

  out <- se_update(x, fx$conn)
  expect_identical(names(out$members[[1L]]), "id")
})


# === the report ================================================================

test_that("the report names every moved member, old -> new, grouped by project", {
  # AC40(b).
  fx <- local_edit_project()
  v_dm <- se_table(fx, "dm", 3L)
  v_lb <- se_table(fx, "lb", 3L)
  x <- se_set(se_member("dm", v_dm), se_member("lb", v_lb))
  new_dm <- se_table(fx, "dm", 4L)
  new_lb <- se_table(fx, "lb", 5L)

  msg <- se_messages(out <- datom_update_members(x, fx$conn))

  expect_match(msg, "edit-project")
  expect_match(msg, paste0("dm  ", substr(v_dm, 1L, 8L), " -> ",
                           substr(new_dm, 1L, 8L)), fixed = TRUE)
  expect_match(msg, paste0("lb  ", substr(v_lb, 1L, 8L), " -> ",
                           substr(new_lb, 1L, 8L)), fixed = TRUE)
  expect_match(msg, "2 members")
  # The report IS the dry run, so it has to say the obvious thing.
  expect_match(msg, "Nothing has been written")
})

test_that("a refresh that finds nothing says so and reports no moves", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))

  msg <- se_messages(out <- datom_update_members(x, fx$conn))
  expect_match(msg, "No member moved")
  expect_identical(out$members[[1L]]$id$version, v1)
  expect_null(attr(out, "datom_updates"))
})


# === nothing is written ========================================================

test_that("an update that finds nothing new mints no version at the write", {
  # AC40(c), asserted THROUGH the write: "this refresh was free" is observable
  # there and nowhere else.
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1,
                                      tags = list(type = "input"))))
  x <- datom_get_set(fx$conn, "product-a")
  before <- se_versions(fx, "product-a")

  out <- se_update(x, fx$conn)
  result <- se_write(fx$conn, out)

  expect_identical(result$action, "none")
  expect_identical(se_versions(fx, "product-a"), before)
})

test_that("a repointed set writes a new version, and its members are the new ones", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1,
                                      tags = list(type = "input"))))
  x <- datom_get_set(fx$conn, "product-a")
  v2 <- se_table(fx, "dm", 4L)

  out <- se_update(x, fx$conn)
  result <- se_write(fx$conn, out)

  expect_false(identical(result$action, "none"))
  again <- datom_get_set(fx$conn, "product-a")
  expect_identical(again$members[[1L]]$id$version, v2)
  expect_identical(again$members[[1L]]$tags, list(type = "input"))
})


# === selecting ==================================================================

test_that("selecting by label repoints only those members", {
  # AC40(d).
  fx <- local_edit_project()
  v_dm <- se_table(fx, "dm", 3L)
  v_lb <- se_table(fx, "lb", 3L)
  x <- se_set(
    se_member("dm", v_dm, tags = list(type = "input")),
    se_member("lb", v_lb, tags = list(type = "output"))
  )
  new_dm <- se_table(fx, "dm", 4L)
  se_table(fx, "lb", 5L)

  out <- se_update(x, fx$conn, tags = list(type = "input"))

  expect_identical(out$members[[1L]]$id$version, new_dm)
  expect_identical(out$members[[2L]]$id$version, v_lb)
  expect_identical(nrow(attr(out, "datom_updates")), 1L)
})

test_that("selecting one member by name repoints only it", {
  fx <- local_edit_project()
  v_dm <- se_table(fx, "dm", 3L)
  v_lb <- se_table(fx, "lb", 3L)
  x <- se_set(se_member("dm", v_dm), se_member("lb", v_lb))
  new_dm <- se_table(fx, "dm", 4L)
  se_table(fx, "lb", 5L)

  out <- se_update(x, fx$conn, member = "dm")

  expect_identical(out$members[[1L]]$id$version, new_dm)
  expect_identical(out$members[[2L]]$id$version, v_lb)
})

test_that("a member record and a link both select the member they name", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1)))
  x <- datom_get_set(fx$conn, "product-a")
  v2 <- se_table(fx, "dm", 4L)

  by_record <- se_update(x, fx$conn, member = x$members[[1L]])
  by_link <- se_update(x, fx$conn, member = x$members[[1L]]$fetch)

  expect_identical(by_record$members[[1L]]$id$version, v2)
  expect_identical(by_link$members[[1L]]$id$version, v2)
})

test_that("a record or a link refuses a filter beside it", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1, tags = list(type = "input")))

  expect_error(
    datom_update_members(x, fx$conn, member = x$members[[1L]],
                         tags = list(type = "input")),
    class = "datom_member_filter_ignored"
  )
  expect_error(
    datom_update_members(x, fx$conn, member = x$members[[1L]],
                         version_from = substr(v1, 1L, 8L)),
    class = "datom_member_filter_ignored"
  )
})

test_that("a selection matching no member aborts, and an empty set says so", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))

  expect_error(
    datom_update_members(x, fx$conn, tags = list(nope = "nothing")),
    class = "datom_member_not_found"
  )
  expect_error(
    datom_update_members(se_set(), fx$conn),
    class = "datom_member_not_found"
  )
  expect_error(
    datom_update_members(x, fx$conn, member = "no-such-member"),
    class = "datom_member_not_found"
  )
})

test_that("a member not in the set is reported as absent, not repointed", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))

  expect_error(
    datom_update_members(x, fx$conn,
                         member = se_member("lb", strrep("a", 64L))),
    class = "datom_member_not_found"
  )
})


# === the four ways it declines to act ===========================================

test_that("a member whose project has no connection refuses the whole call", {
  # AC41(a). Not a partial update: whether that member moved is unknowable, and
  # leaving it alone silently would report a refresh that did not happen.
  fx <- local_edit_project()
  v_dm <- se_table(fx, "dm", 3L)
  x <- se_set(
    se_member("dm", v_dm),
    se_member("ae", strrep("a", 64L), project = "other-study")
  )
  se_table(fx, "dm", 4L)

  err <- expect_error(
    datom_update_members(x, fx$conn),
    class = "datom_update_conn_missing"
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "other-study")
  # The refusal is actionable, which is what earns it: the offline enumeration.
  expect_match(msg, "datom_list_members")
})

test_that("a project with no connection is fine when nothing selects it", {
  # The other half of the same rule: the refusal is about the SELECTION, so
  # naming one member of the project you hold does not require the others'.
  fx <- local_edit_project()
  v_dm <- se_table(fx, "dm", 3L)
  x <- se_set(
    se_member("dm", v_dm),
    se_member("ae", strrep("a", 64L), project = "other-study")
  )
  new_dm <- se_table(fx, "dm", 4L)

  out <- se_update(x, fx$conn, member = "dm")
  expect_identical(out$members[[1L]]$id$version, new_dm)
  expect_identical(out$members[[2L]]$id$version, strrep("a", 64L))
})

test_that("a member whose artifact is gone is reported and left, and still writes", {
  # AC41(b). The answer is known and the pin still reads, so refusing a whole
  # refresh over one retired input would be the wrong trade.
  fx <- local_edit_project()
  v_dm <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v_dm), se_member("ghost", strrep("a", 64L)))
  new_dm <- se_table(fx, "dm", 4L)

  msg <- se_messages(out <- datom_update_members(x, fx$conn))

  expect_match(msg, "ghost")
  expect_match(msg, "pinned")
  expect_identical(out$members[[1L]]$id$version, new_dm)
  expect_identical(out$members[[2L]]$id$version, strrep("a", 64L))

  # And the set is still writable, which is the point of leaving the pin.
  result <- se_write(fx$conn, out)
  expect_identical(result$member_count, 2L)
})

test_that("a manifest that cannot be read refuses rather than reporting its members gone", {
  # "Not there" and "could not look" are different answers. The manifest is what
  # says which version is current, so a read that failed leaves every member's
  # state unknown -- which is the same situation as a missing connection, and
  # NOT the known answer the test above reports.
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))

  manifest <- fs::path(fx$store_dir, "proj", "datom", ".metadata",
                       "manifest.json")
  expect_true(fs::file_exists(manifest))
  writeLines("{ not json", manifest)

  err <- expect_error(
    datom_update_members(x, fx$conn),
    class = "datom_edit_manifest_unreadable"
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "edit-project")
})

test_that("two members sharing a name are skipped and reported, never collapsed", {
  # AC41(c). Only the caller's labels say which of a live table and a frozen
  # baseline is which, so choosing would be a guess -- and refusing the whole
  # sweep would make the first update on such a set an error.
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  v2 <- se_table(fx, "dm", 4L)
  v_lb <- se_table(fx, "lb", 3L)
  x <- se_set(
    se_member("dm", v1, tags = list(release = "baseline")),
    se_member("dm", v2, tags = list(release = "live")),
    se_member("lb", v_lb)
  )
  v3 <- se_table(fx, "dm", 5L)
  new_lb <- se_table(fx, "lb", 6L)

  msg <- se_messages(out <- datom_update_members(x, fx$conn))

  expect_match(msg, "Skipped 1 member|Skipped 2 members")
  expect_match(msg, substr(v1, 1L, 8L), fixed = TRUE)
  expect_match(msg, substr(v2, 1L, 8L), fixed = TRUE)
  # Neither dm moved, and neither was collapsed onto one version.
  expect_identical(out$members[[1L]]$id$version, v1)
  expect_identical(out$members[[2L]]$id$version, v2)
  # The rest of the sweep still ran.
  expect_identical(out$members[[3L]]$id$version, new_lb)
  expect_false(identical(v3, v2))
})

test_that("the skip is escapable the two ways the report names", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  v2 <- se_table(fx, "dm", 4L)
  x <- se_set(
    se_member("dm", v1, tags = list(release = "baseline")),
    se_member("dm", v2, tags = list(release = "live"))
  )
  v3 <- se_table(fx, "dm", 5L)

  by_label <- se_update(x, fx$conn, tags = list(release = "live"))
  expect_identical(by_label$members[[1L]]$id$version, v1)
  expect_identical(by_label$members[[2L]]$id$version, v3)

  by_version <- se_update(x, fx$conn, version_from = substr(v1, 1L, 8L))
  expect_identical(by_version$members[[1L]]$id$version, v3)
  expect_identical(by_version$members[[2L]]$id$version, v2)
})

test_that("an explicitly named ambiguous member aborts rather than skipping", {
  # The asymmetry with the sweep above, and it is the consequence rather than the
  # taste: a caller who named one member asked for something that cannot be done.
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  v2 <- se_table(fx, "dm", 4L)
  x <- se_set(se_member("dm", v1), se_member("dm", v2))

  expect_error(
    datom_update_members(x, fx$conn, member = "dm"),
    class = "datom_member_ambiguous"
  )
})

test_that("a same name in two projects is not ambiguous and both move", {
  # Keyed on project AND name: two projects may both hold a `dm`, and there is
  # nothing to guess between them.
  a <- local_edit_project("study-a", "product-a", "pa")
  b <- local_edit_project("study-b", "product-b", "pb")
  v_a <- se_table(a, "dm", 3L)
  v_b <- se_table(b, "dm", 4L)
  x <- se_set(
    se_member("dm", v_a, project = "study-a"),
    se_member("dm", v_b, project = "study-b")
  )
  new_a <- se_table(a, "dm", 5L)
  new_b <- se_table(b, "dm", 6L)

  out <- se_update(x, list(a$conn, b$conn))

  expect_identical(out$members[[1L]]$id$version, new_a)
  expect_identical(out$members[[2L]]$id$version, new_b)
})

test_that("a connection whose store is another project's is refused", {
  # AC41(d), and it needs two stores: with one, the member and the store agree
  # and only the label differs, which is the opposite case. The label chooses the
  # route; the rebuilt member's recorded project confirms it.
  a <- local_edit_project("study-a", "product-a", "pa")
  b <- local_edit_project("study-b", "product-b", "pb")
  se_table(a, "dm", 3L)
  v_b <- se_table(b, "dm", 4L)

  mislabelled <- a$conn
  mislabelled$project_name <- "study-b"

  x <- se_set(se_member("dm", v_b, project = "study-b"))

  err <- expect_error(
    datom_update_members(x, mislabelled),
    class = "datom_update_project_mismatch"
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "study-a")
  expect_match(msg, "study-b")
})


# === the link ====================================================================

test_that("a repointed member's link resolves the NEW data", {
  # A member whose `id` moved while its `fetch` did not contradicts itself
  # silently: `id` says the new version and `$fetch()` returns the old rows.
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1,
                                      tags = list(type = "input"))))
  x <- datom_get_set(fx$conn, "product-a")
  expect_identical(nrow(x$members[[1L]]$fetch(fx$conn)), 3L)

  se_table(fx, "dm", 5L)
  out <- se_update(x, fx$conn)

  expect_identical(nrow(out$members[[1L]]$fetch(fx$conn)), 5L)
  expect_identical(nrow(datom_fetch_member(fx$conn, out, "dm")), 5L)
})

test_that("a repointed member's record and link agree, and carry its labels", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1,
                                      tags = list(type = "input"))))
  x <- datom_get_set(fx$conn, "product-a")
  se_table(fx, "dm", 5L)

  out <- se_update(x, fx$conn)
  carried <- attr(out$members[[1L]]$fetch, "datom_member")

  expect_identical(carried$id, out$members[[1L]]$id)
  expect_identical(carried$tags, out$members[[1L]]$tags)
  expect_identical(names(out$members[[1L]]), c("id", "tags", "fetch"))
})

test_that("a member that had no link does not grow one", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))
  se_table(fx, "dm", 4L)

  out <- se_update(x, fx$conn)
  expect_null(out$members[[1L]]$fetch)
})


# === version_to ==================================================================

test_that("version_to repoints to exactly that version and keeps the labels", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  v2 <- se_table(fx, "dm", 4L)
  se_table(fx, "dm", 5L)
  x <- se_set(se_member("dm", v1, tags = list(type = "input")))

  out <- se_update(x, fx$conn, member = "dm", version_to = v2)

  # Not the current version: a deliberate step to a known-good one.
  expect_identical(out$members[[1L]]$id$version, v2)
  expect_identical(out$members[[1L]]$tags, list(type = "input"))
})

test_that("version_to equal to the current pin moves nothing", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))

  out <- se_update(x, fx$conn, member = "dm", version_to = v1)
  expect_null(attr(out, "datom_updates"))
})

test_that("version_to is refused beside a selection of several members", {
  fx <- local_edit_project()
  v_dm <- se_table(fx, "dm", 3L)
  v_lb <- se_table(fx, "lb", 3L)
  x <- se_set(se_member("dm", v_dm), se_member("lb", v_lb))

  expect_error(
    datom_update_members(x, fx$conn, version_to = v_dm),
    class = "datom_update_target_ambiguous"
  )
})

test_that("version_to refuses a prefix, naming where to get the whole version", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))

  err <- expect_error(
    datom_update_members(x, fx$conn, member = "dm",
                         version_to = substr(v1, 1L, 8L)),
    class = "datom_update_version_to_invalid"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "datom_history")
})


# === what comes back =============================================================

test_that("an edited set stops claiming the version it was read as", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1)))
  x <- datom_get_set(fx$conn, "product-a")
  expect_true(.datom_is_text_scalar(x$version))
  se_table(fx, "dm", 4L)

  out <- se_update(x, fx$conn)

  expect_null(out$version)
  expect_null(out$data_sha)
  # Emptied, NOT removed -- a read set may legitimately report a NULL version,
  # so the field exists and says nothing.
  expect_identical(names(out), names(x))
  expect_s3_class(out, "datom_set")
})

test_that("a set nothing moved in keeps the version it was read as", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1)))
  x <- datom_get_set(fx$conn, "product-a")

  out <- se_update(x, fx$conn)

  expect_identical(out$version, x$version)
  expect_identical(out$data_sha, x$data_sha)
})

test_that("a draft comes back a draft, repointed, with its connection untouched", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  draft <- datom_add_member(datom_assemble_set(fx$conn), "dm", v1,
                            tags = list(type = "input"))
  v2 <- se_table(fx, "dm", 4L)

  out <- se_update(draft, fx$conn)

  expect_s3_class(out, "datom_set_draft")
  expect_identical(out$members[[1L]]$id$version, v2)
  expect_identical(out$members[[1L]]$tags, list(type = "input"))
  expect_null(out$members[[1L]]$fetch)
  expect_identical(out$conn, fx$conn)
})

test_that("a repointed draft writes, and the write takes it as one", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  draft <- datom_add_member(datom_assemble_set(fx$conn), "dm", v1)
  v2 <- se_table(fx, "dm", 4L)

  out <- se_update(draft, fx$conn)
  se_write(out)

  again <- datom_get_set(fx$conn, "product-a")
  expect_identical(again$members[[1L]]$id$version, v2)
})


# === the commit message ==========================================================

test_that("the change list becomes the commit message when none was given", {
  # `Update {name}` says nothing in `git log`. The subject is what the version
  # records; the full list, with whole versions, goes in the commit body.
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1)))
  x <- datom_get_set(fx$conn, "product-a")
  v2 <- se_table(fx, "dm", 4L)

  se_write(fx$conn, se_update(x, fx$conn))

  commit <- git2r::commits(fx$repo)[[1L]]$message
  expect_match(commit, "repoint 1 member", fixed = TRUE)
  expect_match(commit, paste0("dm  ", v1, " -> ", v2), fixed = TRUE)

  # One line of it is what the version records, because that is what
  # datom_history() can show.
  recorded <- datom_history(fx$conn, "product-a")$commit_message[[1L]]
  expect_match(recorded, "repoint 1 member", fixed = TRUE)
  expect_false(grepl("\n", recorded, fixed = TRUE))
})

test_that("an explicit message still wins over the change list", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1)))
  x <- datom_get_set(fx$conn, "product-a")
  se_table(fx, "dm", 4L)

  se_write(fx$conn, se_update(x, fx$conn), message = "Refresh for DSMB")

  expect_identical(git2r::commits(fx$repo)[[1L]]$message, "Refresh for DSMB")
})

test_that("a write with no update behind it keeps the plain default", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  se_write(fx$conn, list(datom_member(fx$conn, "dm", v1)))

  expect_identical(git2r::commits(fx$repo)[[1L]]$message, "Update product-a")
})


# === the arguments ================================================================

test_that("x must be a set or a draft, and the message names both", {
  fx <- local_edit_project()
  err <- expect_error(
    datom_update_members(list(), fx$conn),
    class = "datom_not_a_set"
  )
  msg <- cli::ansi_strip(conditionMessage(err))
  expect_match(msg, "datom_get_set")
  expect_match(msg, "datom_assemble_set")
})

test_that("conn takes one connection or a list, and refuses anything else", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))

  expect_error(datom_update_members(x, "nope"), class = "datom_not_a_conn")
  expect_error(datom_update_members(x, list()), class = "datom_not_a_conn")
  expect_error(datom_update_members(x, list(fx$conn, "nope")),
               class = "datom_not_a_conn")

  unlabelled <- fx$conn
  unlabelled$project_name <- NULL
  expect_error(datom_update_members(x, unlabelled),
               class = "datom_not_a_conn")
})

test_that("two connections for one project are refused rather than ordered", {
  # Choosing between them would be a guess, and the wrong one reads a different
  # namespace.
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))

  err <- expect_error(
    datom_update_members(x, list(fx$conn, fx$conn)),
    class = "datom_edit_conn_duplicate"
  )
  expect_match(cli::ansi_strip(conditionMessage(err)), "edit-project")
})

test_that("the filters are validated before anything is read", {
  fx <- local_edit_project()
  v1 <- se_table(fx, "dm", 3L)
  x <- se_set(se_member("dm", v1))

  expect_error(datom_update_members(x, fx$conn, tags = list("unnamed")),
               "named list")
  expect_error(datom_update_members(x, fx$conn, version_from = 1L),
               "single non-empty string")
})

test_that("a member with no usable id is reported as unresolvable", {
  fx <- local_edit_project()
  x <- se_set(list(id = list(project = "edit-project", name = "dm")))

  expect_error(datom_update_members(x, fx$conn),
               class = "datom_member_unusable")
})
