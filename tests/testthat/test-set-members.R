# Finding and shaping a set's members: the three verbs over a `datom_set`.
#
# Two kinds of fixture, deliberately. The two shaping verbs do no IO at all, so
# they are tested against a set built by hand -- which is also the only way to
# construct the cases a writer refuses (two members of one name, a member
# carrying the bucket's own name as a label). `datom_fetch_member()` runs against
# a real repo, a real bare remote and a real local store, because what it claims
# is about the composition rather than about any one function.
#
# THREE OF THESE ARE THE TESTS A PLAUSIBLE IMPLEMENTATION PASSES EVERYTHING ELSE
# WHILE FAILING.
#
#   * The two-branch test asserts the LEAF COUNT EXCEEDS THE MEMBER COUNT. Taking
#     the first value of a multi-valued tag is silent and passes any test that
#     only checks a member is somewhere.
#   * The zero-row frame is proved by `rbind()`ing it onto a populated one. A
#     frame built from zero rows loses its columns, and nothing notices until
#     somebody binds two results -- which is exactly how this defect reached
#     `datom_list()` twice.
#   * The project hint is proved BOTH WAYS: it appears when the names differ, and
#     the original condition is re-signalled with its own class when they agree.
#     A rewrap that always fires would reword failures that have nothing to do
#     with projects, and every other test here still passes.


# --- hand-built sets ----------------------------------------------------------

sm_version <- function(k) strrep(letters[[k]], 64L)

sm_member <- function(name, tags = NULL, project = "study001",
                      kind = "table", version = sm_version(1L)) {
  m <- list(id = list(project = project, name = name, kind = kind,
                      version = version))
  if (!is.null(tags)) m$tags <- tags
  m
}

sm_set <- function(..., tags = NULL, name = "study001-adam") {
  structure(
    list(
      name = name, project = "study001", version = sm_version(26L),
      data_sha = sm_version(25L), tags = tags, members = list(...)
    ),
    class = "datom_set"
  )
}

# The two-member set most tests below shape: one member with three labels across
# two keys, one with none at all.
sm_mixed_set <- function() {
  sm_set(
    sm_member("adsl", tags = list(type = "output",
                                  domain = c("safety", "efficacy"))),
    sm_member("dm", version = sm_version(2L))
  )
}


# === datom_list_members =======================================================

test_that("one row per member per label, with the identifying columns", {
  m <- datom_list_members(sm_mixed_set())

  expect_s3_class(m, "data.frame")
  expect_identical(
    names(m),
    c("name", "project", "version", "kind", "key", "value")
  )
  # adsl: one row for type, two for domain. dm: one row for having no labels.
  expect_identical(nrow(m), 4L)
  expect_identical(sort(unique(m$name)), c("adsl", "dm"))
  expect_identical(unique(m$project), "study001")
  expect_identical(unique(m$kind), "table")
})

test_that("an untagged member still gets a row, so the name list is complete", {
  m <- datom_list_members(sm_mixed_set())
  row <- m[m$name == "dm", ]

  expect_identical(nrow(row), 1L)
  expect_true(is.na(row$key))
  expect_true(is.na(row$value))
  # The point of the NA row: this is the complete member list, not the tagged
  # part of it.
  expect_true("dm" %in% unique(m$name))
})

test_that("a tag map carrying one key twice keeps both labels", {
  # THE READ SIDE VALIDATES NO TAG MAP -- `.datom_validate_tag_map()`, which is
  # what refuses a duplicate key, runs only on a write. So a duplicate arrives
  # from a hand edit or a foreign writer -- NOT from a newer datom, which would
  # still write an array for two labels -- and `jsonlite` parses
  # `{"type": "output", "type": "baseline"}` into two same-named elements rather
  # than collapsing them.
  #
  # Read by name, `tags[["type"]]` returns the first match both times: the
  # listing showed `output` twice and lost `baseline` entirely. Built from the
  # JSON rather than from `list()` so the fixture is the shape that actually
  # arrives.
  dup <- jsonlite::fromJSON('{"type": "output", "type": "baseline"}',
                            simplifyVector = FALSE)
  expect_length(dup, 2L)

  m <- datom_list_members(sm_set(sm_member("adsl", tags = dup)))

  expect_identical(nrow(m), 2L)
  expect_identical(sort(m$value), c("baseline", "output"))
})

test_that("a duplicated key puts the member under both branches", {
  # The same defect in the grouped view: one branch instead of two, silently.
  # Duplicate keys mean what one multi-valued key means, so they behave the same.
  dup <- jsonlite::fromJSON('{"type": "output", "type": "baseline"}',
                            simplifyVector = FALSE)
  dp <- datom_structure_members(sm_set(sm_member("adsl", tags = dup)),
                                by = "type")

  expect_true(all(c("output", "baseline") %in% names(dp)))
  expect_s3_class(dp$output$adsl, "datom_link")
  expect_s3_class(dp$baseline$adsl, "datom_link")
})

test_that("a duplicated key is findable by either of its labels", {
  # The third face of it, and the one that reads as missing data: filtering used
  # to report not-found on a label the document says the member carries.
  dup <- jsonlite::fromJSON('{"type": "output", "type": "baseline"}',
                            simplifyVector = FALSE)
  x <- sm_set(sm_member("adsl", tags = dup))

  expect_identical(
    .datom_member_record(x$members, "adsl", tags = list(type = "baseline"))$id$name,
    "adsl"
  )
  expect_identical(
    .datom_member_record(x$members, "adsl", tags = list(type = "output"))$id$name,
    "adsl"
  )
})

test_that("a blank tag key is reported rather than read as no key", {
  # `tags[[""]]` matches no name and returns NULL, so a by-name read gave this
  # key an NA value and nothing crashed. By position it reports what is there.
  x <- sm_set(sm_member("adsl", tags = stats::setNames(list("output"), "")))
  m <- datom_list_members(x)

  expect_identical(nrow(m), 1L)
  expect_identical(m$key, "")
  expect_identical(m$value, "output")
})

test_that("a multi-valued label becomes one row per value", {
  m <- datom_list_members(sm_mixed_set())
  domains <- m[!is.na(m$key) & m$key == "domain", ]

  expect_identical(nrow(domains), 2L)
  expect_identical(sort(domains$value), c("efficacy", "safety"))
  expect_identical(unique(domains$name), "adsl")
})

test_that("value is a plain character column, never a list-column", {
  # Only possible because the tag grammar is text-only. If it ever widened, this
  # verb is one of the things that would have to change.
  m <- datom_list_members(sm_mixed_set())

  expect_type(m$value, "character")
  expect_false(is.list(m$value))
})

test_that("a set with no members returns a zero-row frame with every column", {
  m <- datom_list_members(sm_set())

  expect_identical(nrow(m), 0L)
  expect_identical(
    names(m),
    c("name", "project", "version", "kind", "key", "value")
  )
})

test_that("an empty listing binds onto a populated one", {
  # The assertion that caught the second half of the same defect in
  # datom_list(): a zero-row frame built from zero rows loses its columns, and
  # nothing fails until two results are combined.
  populated <- datom_list_members(sm_mixed_set())
  empty <- datom_list_members(sm_set())

  bound <- rbind(populated, empty)
  expect_identical(nrow(bound), nrow(populated))
  expect_identical(names(bound), names(populated))

  expect_identical(nrow(rbind(empty, populated)), nrow(populated))
})

test_that("filtering by label is plain R", {
  m <- datom_list_members(sm_mixed_set())

  safety <- subset(m, !is.na(key) & key == "domain" & value == "safety")
  expect_identical(safety$name, "adsl")
})

test_that("a reader-side set is what these verbs take, and nothing else", {
  expect_error(datom_list_members(list(members = list())),
               class = "datom_not_a_set")
  expect_error(datom_structure_members(mtcars, by = "type"),
               class = "datom_not_a_set")
})


# === datom_structure_members ==================================================

test_that("the view nests axis values then the member's own name", {
  dp <- datom_structure_members(sm_mixed_set(), by = "type")

  expect_true("output" %in% names(dp))
  expect_true("adsl" %in% names(dp$output))
  expect_s3_class(dp$output$adsl, "datom_link")
  expect_true(is.function(dp$output$adsl))
})

test_that("a multi-valued axis puts one member under EVERY branch", {
  # R4.6: a folder holds an item once and a label does not, which is the only
  # reason arrays exist in the tag grammar. The silent wrong spelling is taking
  # the first value.
  x <- sm_set(sm_member("adsl", tags = list(domain = c("safety", "efficacy"))))
  dp <- datom_structure_members(x, by = "domain")

  expect_true(all(c("safety", "efficacy") %in% names(dp)))
  expect_s3_class(dp$safety$adsl, "datom_link")
  expect_s3_class(dp$efficacy$adsl, "datom_link")

  # In two places at once, made observable rather than inferred: one member, two
  # leaves.
  leaves <- sum(vapply(dp, length, integer(1L)))
  expect_identical(length(x$members), 1L)
  expect_gt(leaves, length(x$members))
})

test_that("both branches point at the same member, not at copies of a guess", {
  x <- sm_set(sm_member("adsl", tags = list(domain = c("safety", "efficacy"))))
  dp <- datom_structure_members(x, by = "domain")

  expect_identical(
    attr(dp$safety$adsl, "datom_member"),
    attr(dp$efficacy$adsl, "datom_member")
  )
})

test_that("a member with no value for the axis goes under the named bucket", {
  dp <- datom_structure_members(sm_mixed_set(), by = "type")

  # Named, never dropped: a dropped member is one the consumer cannot find and
  # cannot see is absent.
  expect_true("untagged" %in% names(dp))
  expect_s3_class(dp$untagged$dm, "datom_link")
})

test_that("the bucket name is the caller's to choose", {
  dp <- datom_structure_members(sm_mixed_set(), by = "type",
                                missing = "(none)")

  expect_true("(none)" %in% names(dp))
  expect_false("untagged" %in% names(dp))
})

test_that("a bucket name that is also a real label value is refused", {
  # Same class of defect as the leaf collision below, arriving by a different
  # door: the bucket is a branch NAME, so it would merge with the real branch.
  x <- sm_set(
    sm_member("adsl", tags = list(type = "untagged")),
    sm_member("dm", version = sm_version(2L))
  )

  err <- expect_error(
    datom_structure_members(x, by = "type"),
    class = "datom_structure_missing_collision"
  )
  expect_match(conditionMessage(err), "untagged")
  expect_match(conditionMessage(err), "type")

  # And the remedy works.
  dp <- datom_structure_members(x, by = "type", missing = "(none)")
  expect_true(all(c("untagged", "(none)") %in% names(dp)))
})

test_that("refusing the bucket name does not wait for a member to need it", {
  # Every member carries the key here, so nothing would merge today. Refused
  # anyway: making it conditional means the projection starts failing the day a
  # member without the key is added, silently at authoring time.
  x <- sm_set(sm_member("adsl", tags = list(type = "untagged")))

  expect_error(
    datom_structure_members(x, by = "type"),
    class = "datom_structure_missing_collision"
  )
})

test_that("two members asking for one leaf name abort, naming both", {
  # Legal payload, refused projection: the same artifact at two versions is a
  # current table beside a locked baseline (R2.14a), and both carrying
  # type = "output" asks for two leaves with one name.
  x <- sm_set(
    sm_member("adsl", tags = list(type = "output"), version = sm_version(1L)),
    sm_member("adsl", tags = list(type = "output"), version = sm_version(2L))
  )

  err <- expect_error(
    datom_structure_members(x, by = "type"),
    class = "datom_structure_leaf_collision"
  )
  msg <- conditionMessage(err)

  # Both members, with the versions that tell them apart -- free, because a read
  # member's version is the full recorded string.
  expect_match(msg, substr(sm_version(1L), 1L, 8L))
  expect_match(msg, substr(sm_version(2L), 1L, 8L))
  expect_match(msg, "output / adsl", fixed = TRUE)
  expect_match(msg, "Add an axis")
})

test_that("adding an axis is a remedy that actually works", {
  x <- sm_set(
    sm_member("adsl", tags = list(type = "output", release = "current"),
              version = sm_version(1L)),
    sm_member("adsl", tags = list(type = "output", release = "baseline"),
              version = sm_version(2L))
  )

  dp <- datom_structure_members(x, by = c("type", "release"))

  expect_s3_class(dp$output$current$adsl, "datom_link")
  expect_s3_class(dp$output$baseline$adsl, "datom_link")
})

test_that("a two-axis view expands on the first axis before nesting on the second", {
  # The failure this guards: expanding only at the last level puts a two-domain
  # member under one domain.
  x <- sm_set(
    sm_member("adsl", tags = list(domain = c("safety", "efficacy"),
                                  type = "output"))
  )

  dp <- datom_structure_members(x, by = c("domain", "type"))

  expect_s3_class(dp$safety$output$adsl, "datom_link")
  expect_s3_class(dp$efficacy$output$adsl, "datom_link")
})

test_that("the axis argument is validated, and a repeated key is refused", {
  x <- sm_mixed_set()

  expect_error(datom_structure_members(x, by = character()),
               class = "datom_structure_by_invalid")
  expect_error(datom_structure_members(x, by = NA_character_),
               class = "datom_structure_by_invalid")
  expect_error(datom_structure_members(x, by = ""),
               class = "datom_structure_by_invalid")
  expect_error(datom_structure_members(x, by = 1L),
               class = "datom_structure_by_invalid")
  expect_error(datom_structure_members(x, by = c("type", "type")),
               class = "datom_structure_by_invalid")
  expect_error(datom_structure_members(x, by = "type", missing = c("a", "b")),
               class = "datom_structure_by_invalid")
})

test_that("an axis no member uses puts everything in the bucket", {
  dp <- datom_structure_members(sm_mixed_set(), by = "nobody-uses-this")

  expect_identical(names(dp), "untagged")
  expect_true(all(c("adsl", "dm") %in% names(dp$untagged)))
})

test_that("a set with no members structures to an empty list", {
  expect_identical(datom_structure_members(sm_set(), by = "type"), list())
})

test_that("a member whose pointer is unusable is reported as that", {
  x <- sm_set(list(id = list(project = "study001", name = "adsl")))

  expect_error(datom_structure_members(x, by = "type"),
               class = "datom_member_unusable")
})


# === datom_fetch_member: the real thing =======================================

#' Real product project, mirroring the fixture in `test-get-set.R`.
#'
#' Duplicated rather than shared because testthat does not share definitions
#' between test files, and the two files want different set contents.
local_member_project <- function(env = parent.frame()) {
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

  write_product_config(repo_dir, "set-project", "product-a")

  list(conn = conn, repo_dir = repo_dir, store_dir = store_dir,
       repo = repo, set_name = "product-a")
}

fm_data <- function(n = 3L) {
  data.frame(id = seq_len(n), val = letters[seq_len(n)],
             stringsAsFactors = FALSE)
}

fm_table <- function(fx, name, n = 3L) {
  suppressMessages(datom_write(fx$conn, data = fm_data(n), name = name))
  datom_history(fx$conn, name, short_hash = FALSE)$version[[1L]]
}

# A set with one table member, written and read back.
fm_read_one <- function(fx) {
  version <- fm_table(fx, "dm")
  suppressMessages(datom_write_set(
    fx$conn,
    list(datom_member(fx$conn, "dm", version, tags = list(type = "input")))
  ))
  list(x = datom_get_set(fx$conn, "product-a"), version = version)
}

test_that("a member fetches by name, and it is exactly what datom_read() gives", {
  fx <- local_member_project()
  got <- fm_read_one(fx)

  expect_identical(
    datom_fetch_member(fx$conn, got$x, "dm"),
    datom_read(fx$conn, "dm", version = got$version)
  )
})

test_that("all three shapes of the third argument reach the same fetch", {
  # A name, a member record and a link -- so a console call and a loop use one
  # verb rather than two spellings that agree today.
  fx <- local_member_project()
  got <- fm_read_one(fx)
  expected <- datom_read(fx$conn, "dm", version = got$version)

  by_name <- datom_fetch_member(fx$conn, got$x, "dm")
  by_record <- datom_fetch_member(fx$conn, got$x, got$x$members[[1L]])
  by_link <- datom_fetch_member(fx$conn, got$x, got$x$members[[1L]]$fetch)

  expect_identical(by_name, expected)
  expect_identical(by_record, expected)
  expect_identical(by_link, expected)
})

test_that("a member record with no link on it is accepted", {
  # The payload shape: what stripping a read set produces, and what a caller
  # holding the output of datom_member() has. Saying no would mean this verb and
  # datom_write_set() disagree about what a member is.
  fx <- local_member_project()
  got <- fm_read_one(fx)

  bare <- .datom_strip_member_links(got$x$members)[[1L]]
  expect_false("fetch" %in% names(bare))

  expect_identical(
    datom_fetch_member(fx$conn, got$x, bare),
    datom_read(fx$conn, "dm", version = got$version)
  )
})

test_that("a set member fetches through datom_get_set(), not datom_read()", {
  fx <- local_member_project()
  got <- fm_read_one(fx)

  x <- got$x
  x$members[[1L]]$id$kind <- "set"
  x$members[[1L]]$id$name <- "inner-product"

  local_mocked_bindings(
    datom_get_set = function(conn, name, version = NULL) {
      list(routed_to = "datom_get_set", name = name)
    }
  )

  fetched <- datom_fetch_member(fx$conn, x, "inner-product")
  expect_identical(fetched$routed_to, "datom_get_set")
})

test_that("an ambiguous name aborts and lists the candidates", {
  fx <- local_member_project()
  v1 <- fm_table(fx, "dm", 3L)
  v2 <- fm_table(fx, "dm", 5L)
  suppressMessages(datom_write_set(fx$conn, list(
    datom_member(fx$conn, "dm", v1, tags = list(release = "baseline")),
    datom_member(fx$conn, "dm", v2, tags = list(release = "current"))
  )))
  x <- datom_get_set(fx$conn, "product-a")

  err <- expect_error(
    datom_fetch_member(fx$conn, x, "dm"),
    class = "datom_member_ambiguous"
  )
  msg <- conditionMessage(err)

  expect_match(msg, substr(v1, 1L, 8L))
  expect_match(msg, substr(v2, 1L, 8L))
  expect_match(msg, "release=baseline")
  expect_match(msg, "release=current")
  # Both ways to narrow, with labels named first because that is the axis people
  # navigate by.
  expect_match(msg, "tags = list")
  expect_match(msg, "version = ")
})

test_that("a label narrows an ambiguous name to one member", {
  fx <- local_member_project()
  v1 <- fm_table(fx, "dm", 3L)
  v2 <- fm_table(fx, "dm", 5L)
  suppressMessages(datom_write_set(fx$conn, list(
    datom_member(fx$conn, "dm", v1, tags = list(release = "baseline")),
    datom_member(fx$conn, "dm", v2, tags = list(release = "current"))
  )))
  x <- datom_get_set(fx$conn, "product-a")

  baseline <- datom_fetch_member(fx$conn, x, "dm",
                                 tags = list(release = "baseline"))
  expect_identical(nrow(baseline), 3L)

  current <- datom_fetch_member(fx$conn, x, "dm",
                               tags = list(release = "current"))
  expect_identical(nrow(current), 5L)
})

test_that("a version prefix narrows an ambiguous name to one member", {
  fx <- local_member_project()
  v1 <- fm_table(fx, "dm", 3L)
  v2 <- fm_table(fx, "dm", 5L)
  suppressMessages(datom_write_set(fx$conn, list(
    datom_member(fx$conn, "dm", v1),
    datom_member(fx$conn, "dm", v2)
  )))
  x <- datom_get_set(fx$conn, "product-a")

  expect_identical(
    nrow(datom_fetch_member(fx$conn, x, "dm", version = substr(v2, 1L, 8L))),
    5L
  )
})

test_that("one label of a multi-valued tag is enough to narrow", {
  # Narrowing by one label of `domain = c("safety", "efficacy")` is the ordinary
  # case, since multi-valued tags are the point.
  x <- sm_set(
    sm_member("adsl", tags = list(domain = c("safety", "efficacy"))),
    sm_member("adsl", tags = list(domain = "labs"), version = sm_version(2L))
  )

  record <- .datom_member_record(x$members, "adsl",
                                 tags = list(domain = "safety"))
  expect_identical(record$id$version, sm_version(1L))
})

test_that("narrowing to nothing says so, and lists what the name does have", {
  x <- sm_set(sm_member("adsl", tags = list(release = "current")))

  err <- expect_error(
    .datom_member_record(x$members, "adsl",
                         tags = list(release = "baseline")),
    class = "datom_member_not_found"
  )
  expect_match(conditionMessage(err), "release=current")
})

test_that("a name no member carries aborts, naming the ones that exist", {
  x <- sm_mixed_set()

  err <- expect_error(.datom_member_record(x$members, "nope"),
                      class = "datom_member_not_found")
  expect_match(conditionMessage(err), "adsl")
  expect_match(conditionMessage(err), "dm")
})

test_that("a filter beside a record or a link is refused, not ignored", {
  # Ignoring it would resolve a different version than the one asked for and
  # report success.
  x <- sm_mixed_set()

  expect_error(
    .datom_member_record(x$members, x$members[[1L]],
                         version = sm_version(9L)),
    class = "datom_member_filter_ignored"
  )
  expect_error(
    .datom_member_record(x$members, x$members[[1L]],
                         tags = list(type = "output")),
    class = "datom_member_filter_ignored"
  )
})

test_that("the third argument refuses a shape that is none of the three", {
  x <- sm_mixed_set()

  expect_error(.datom_member_record(x$members, 42),
               class = "datom_member_unusable")
  expect_error(.datom_member_record(x$members, character()),
               class = "datom_member_unusable")
})

test_that("the arguments are validated", {
  fx <- local_member_project()
  got <- fm_read_one(fx)

  expect_error(datom_fetch_member("nope", got$x, "dm"), "datom_conn")
  expect_error(datom_fetch_member(fx$conn, list(), "dm"),
               class = "datom_not_a_set")
  expect_error(
    datom_fetch_member(fx$conn, got$x, "dm", tags = list("unnamed")),
    "named list"
  )
  expect_error(datom_fetch_member(fx$conn, got$x, "dm", version = 1L),
               "single non-empty string")
})


# === the project hint =========================================================

test_that("a failed fetch of another project's member names that project", {
  # The highest-value message in the design: without it, per-project access
  # presents as a confusing missing-object error instead of "this member lives
  # somewhere else".
  fx <- local_member_project()
  x <- sm_set(sm_member("dm", project = "some-other-project"))

  err <- expect_error(
    datom_fetch_member(fx$conn, x, "dm"),
    class = "datom_member_project_mismatch"
  )
  msg <- conditionMessage(err)

  expect_match(msg, "some-other-project")
  expect_match(msg, "set-project")
})

test_that("the hint reaches a leaf of a projection too, not just the named verb", {
  # After datom_structure_members() a leaf is a link, so a hint implemented only
  # in datom_fetch_member() would miss the route people actually use. This is
  # what pins the check to the shared link core.
  fx <- local_member_project()
  x <- sm_set(sm_member("dm", project = "some-other-project",
                        tags = list(type = "input")))

  dp <- datom_structure_members(x, by = "type")

  expect_error(dp$input$dm(fx$conn),
               class = "datom_member_project_mismatch")
})

test_that("a failure with matching projects is re-signalled untouched", {
  # The other half, and the one a rewrap-always implementation fails: a fetch
  # that broke for its own reasons must keep its own class, because callers
  # dispatch on it.
  fx <- local_member_project()
  x <- sm_set(sm_member("no-such-table", project = "set-project"))

  err <- expect_error(datom_fetch_member(fx$conn, x, "no-such-table"))
  expect_false(inherits(err, "datom_member_project_mismatch"))
})

test_that("an unresolvable kind keeps its own class through the hint path", {
  fx <- local_member_project()
  x <- sm_set(sm_member("dm", kind = "cube", project = "set-project"))

  expect_error(datom_fetch_member(fx$conn, x, "dm"),
               class = "datom_member_kind_unknown")
})

test_that("a mismatched label alone does not refuse a fetch that works", {
  # The no-gate rule, from this verb's side. A reader's project name is a label
  # nobody validated, so a mismatch is ordinary -- the hint fires on failure and
  # never before it.
  fx <- local_member_project()
  got <- fm_read_one(fx)

  mislabelled <- fx$conn
  mislabelled$path <- NULL
  mislabelled$role <- "reader"
  mislabelled$project_name <- "a-label-nobody-validated"

  x <- datom_get_set(mislabelled, "product-a")
  expect_identical(x$members[[1L]]$id$project, "set-project")

  expect_identical(
    nrow(datom_fetch_member(mislabelled, x, "dm")),
    3L
  )
})
