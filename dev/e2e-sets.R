# dev/e2e-sets.R
# -----------------------------------------------------------------------------
# The set lifecycle, end to end -- FULLY OFFLINE. No GitHub PAT, no AWS, no
# network. Built in the style of dev/e2e-cv1-identity.R: a real git repo with a
# real LOCAL BARE REMOTE plus a real `backend = "local"` store inside tempdir(),
# so everything from the public verbs inward is the production code path.
#
# WHY THIS SCRIPT EXISTS, given that the unit suite is large. A set's value is a
# LIFECYCLE, and the unit tests each hold one moment of it. The failures this
# catches are the ones that live between two moments: a set that writes but whose
# members cannot be resolved back; an edit verb whose output the write verb will
# not take; a commit message that is right in isolation and says nothing useful
# after two edits are chained.
#
# The walk is the one a product actually does:
#
#   1. a product repo, with foreign content datom does not own -- `R/`, `dp/`
#      and `renv.lock`, all committed, so a later edit to one is an uncommitted
#      change to a TRACKED file rather than an untracked stray
#   2. two input tables written, then a set assembled in steps and written with
#      `include_paths` -- ONE joint commit carrying the payload, the metadata and
#      the caller's own files, with storage receiving datom artifacts only
#   3. the set read back with a STORAGE-ONLY connection -- no clone, no git --
#      and one member resolved to its data through the link it carries
#   4. re-writing the identical set: no commit, no version, and the foreign files
#      left dirty in the working tree
#   5. an input moves. `datom_update_members()` repoints it and reports the move;
#      `datom_remove_members()` drops a retired one; the two edits are CHAINED,
#      so the write's commit message has to name both
#   6. the second write: a new version, and the new pins readable at it while the
#      first version still reads as it always did
#   7. a refresh that finds nothing: no version minted
#
# Every claim is asserted and the script exits non-zero if any fails (AC12).
#
#   Rscript ~/projects/dev/datom/dev/e2e-sets.R
#   # or interactively:
#   source("~/projects/dev/datom/dev/e2e-sets.R")
#
# CAVEAT -- what this does NOT exercise, and it is the same one
# dev/e2e-cv1-identity.R carries. The connection is assembled directly as a
# `datom_conn` and `project.yaml` is written by hand rather than by
# datom_init_repo() + datom_get_conn(). That is what removes the PAT
# requirement, and it means GitHub repo creation and ref resolution are skipped.
# The config IS read by the production code here -- the product-mode gate and the
# config-format check both read this file -- so `mode` and `set` are exercised
# even though nothing created them for us. For the full entry path use
# dev/e2e-solo-local.R, which needs a PAT.
#
# Artefacts live in tempdir() and vanish with the R session; the path is printed
# at the end if you want to poke at it first.
# -----------------------------------------------------------------------------

.datom_pkg_dir <- path.expand("~/projects/dev/datom")
if (!exists("datom_write_set")) {
  devtools::load_all(.datom_pkg_dir, quiet = TRUE)
}

options(crayon.enabled = FALSE)

.failures <- 0L
hr <- function(x) cat("\n\n==========", x, "==========\n")

# Assert-and-report, same contract as dev/e2e-cv1-identity.R: prints the claim
# with its verdict so the transcript reads as a walkthrough, and records a
# failure rather than aborting, so one bad line does not hide the rest.
claim <- function(label, actual, expected) {
  actual <- unname(actual)
  ok <- identical(actual, expected)
  if (!ok) .failures <<- .failures + 1L
  cat(sprintf("%-58s %-10s %s\n", label,
              if (is.logical(actual) || is.numeric(actual)) {
                as.character(actual)
              } else {
                paste(as.character(actual), collapse = ",")
              },
              if (ok) "" else paste0("<< FAIL, expected ",
                                     paste(as.character(expected),
                                           collapse = ","))))
  invisible(ok)
}

quiet <- function(expr) suppressMessages(expr)

head_sha <- function(repo) as.character(git2r::revparse_single(repo, "HEAD")$sha)

# Every path in a commit's tree, recursively, as repo-relative strings.
tree_paths <- function(repo, sha) {
  entries <- git2r::ls_tree(repo = repo,
                            tree = git2r::tree(git2r::lookup(repo, sha)))
  paste0(entries$path, entries$name)
}

unstaged <- function(repo) unlist(git2r::status(repo)$unstaged, use.names = FALSE)

# The version one named member is pinned at, and the labels it carries, both read
# through the public listing verb rather than by reaching into `$members`. There
# is no public "give me one member's record" verb -- `datom_fetch_member()` goes
# straight to the data -- so the listing is the public route to a member's facts.
pinned_at <- function(x, nm) {
  rows <- datom_list_members(x)
  unique(rows$version[rows$name == nm])
}
labels_of <- function(x, nm) {
  rows <- datom_list_members(x)
  sort(unique(rows$value[rows$name == nm]))
}

stored_files <- function(store_dir) {
  as.character(fs::dir_ls(fs::path(store_dir, "datom"), recurse = TRUE,
                          type = "file"))
}


# --- 1. A product repo with foreign content ----------------------------------
hr("1. A product repo carrying content datom does not own")

root      <- tempfile("datom_sets_e2e_")
repo_dir  <- fs::path(root, "repo")
store_dir <- fs::path(root, "store")
bare_dir  <- fs::path(root, "remote.git")
fs::dir_create(c(repo_dir, store_dir, bare_dir))

git2r::init(bare_dir, bare = TRUE)
repo <- git2r::init(repo_dir)
git2r::config(repo, user.name = "Tire Kicker", user.email = "you@example.com")

# The foreign content, committed so that editing it later is an uncommitted
# change to a tracked file. `dp/` deliberately: it is not one of the names
# datom's artifact discovery drops by hardcoded list, so nothing here passes by
# that route.
fs::dir_create(fs::path(repo_dir, c("R", "dp")))
writeLines("init", fs::path(repo_dir, "README.md"))
writeLines("build <- function() 'v1'", fs::path(repo_dir, "R", "build.R"))
writeLines("notes v1", fs::path(repo_dir, "dp", "notes.md"))
writeLines('{"R": {"Version": "4.4.1"}}', fs::path(repo_dir, "renv.lock"))
git2r::add(repo, c("README.md", "R/build.R", "dp/notes.md", "renv.lock"))
git2r::commit(repo, "Initial commit")
git2r::remote_add(repo, "origin", as.character(bare_dir))
git2r::push(repo, "origin", refspec = "refs/heads/master", set_upstream = TRUE)

# See the CAVEAT in the header: written by hand so no PAT is needed. The
# production code reads it -- the product gate and the config-format check both
# do -- so the fields below are exercised, not merely present.
fs::dir_create(fs::path(repo_dir, ".datom"))
yaml::write_yaml(
  list(project_name = "SETS_E2E", mode = "product", set = "trial_product",
       schema_version = 1L),
  fs::path(repo_dir, ".datom", "project.yaml")
)

conn <- structure(
  list(project_name = "SETS_E2E", backend = "local",
       root = as.character(store_dir), prefix = NULL, region = NULL,
       client = NULL, path = as.character(repo_dir), role = "developer",
       endpoint = NULL, gov_root = NULL, gov_prefix = NULL,
       gov_region = NULL, gov_backend = NULL, gov_client = NULL),
  class = "datom_conn"
)

claim("foreign files committed, working tree clean",
      length(unstaged(repo)), 0L)
claim("repo declares itself a product",
      yaml::read_yaml(fs::path(repo_dir, ".datom", "project.yaml"))$mode,
      "product")


# --- 2. Two inputs, then a set assembled in steps and written ----------------
hr("2. Inputs written, set assembled in steps, ONE joint commit")

dm <- datom_example_data("dm", cutoff_date = "2026-01-28")
lb <- datom_example_data("lb", cutoff_date = "2026-01-28")
quiet(datom_write(conn, data = dm, name = "dm"))
quiet(datom_write(conn, data = lb, name = "lb"))

v_dm1 <- datom_history(conn, "dm")$version[1]
v_lb1 <- datom_history(conn, "lb")$version[1]

# The draft route rather than a hand-built list: this is the ergonomic path, and
# it is what a build script uses.
draft <- quiet(datom_assemble_set(conn, name = "trial_product",
                                  tags = list(description = "Trial data cut")))
draft <- quiet(datom_add_member(draft, "dm", v_dm1,
                                tags = list(type = "input", domain = "safety")))
draft <- quiet(datom_add_member(draft, "lb", v_lb1,
                                tags = list(type = "input", domain = "safety")))

head_before <- head_sha(repo)
first <- quiet(datom_write_set(
  draft,
  include_paths = c("R/build.R", "dp/notes.md", "renv.lock")
))

commits_after <- head_sha(repo)
in_tree <- tree_paths(repo, commits_after)

claim("the set write reports a full write", first$action, "full")
claim("member count is 2", first$member_count, 2L)
claim("exactly ONE new commit",
      length(git2r::commits(repo, n = 2L)) == 2L &&
        !identical(commits_after, head_before), TRUE)
claim("commit holds the set payload",
      "trial_product/set.json" %in% in_tree, TRUE)
claim("commit holds the set metadata",
      "trial_product/metadata.json" %in% in_tree, TRUE)
claim("commit holds the caller's code",
      "R/build.R" %in% in_tree, TRUE)
claim("commit holds the caller's lockfile",
      "renv.lock" %in% in_tree, TRUE)
claim("commit holds the caller's notes",
      "dp/notes.md" %in% in_tree, TRUE)

# The other half of the joint-commit contract: git carries the caller's files,
# storage never sees them.
mirrored <- stored_files(store_dir)
claim("storage holds datom artifacts only",
      any(grepl("build\\.R$|notes\\.md$|renv\\.lock$", mirrored)), FALSE)
claim("storage holds the set payload",
      any(grepl("trial_product/", mirrored)), TRUE)


# --- 3. Read it back with NO CLONE, and resolve one member -------------------
hr("3. A storage-only reader: references without a clone, then data")

# The primary consumer of a set. No `path`, so nothing on the read path may go
# looking for git; role "reader", so nothing may try to write.
reader <- conn
reader$path <- NULL
reader$role <- "reader"

x <- quiet(datom_get_set(reader, "trial_product"))

claim("a set reads with no clone at all", inherits(x, "datom_set"), TRUE)
claim("it reports the project the repo recorded", x$project, "SETS_E2E")
claim("both members come back", length(x$members), 2L)
claim("the set's own labels come back",
      x$tags$description, "Trial data cut")
claim("a member's labels come back",
      sort(unlist(x$members[[1L]]$tags, use.names = FALSE)),
      sort(c("input", "safety")))

# Resolving a member is a SEPARATE, deliberate step, and it needs a connection
# scoped to that member's project -- here the same one, since the inputs are
# local to this product.
dm_back <- quiet(datom_fetch_member(reader, x, "dm"))
claim("a member resolves to exactly its table",
      identical(dim(dm_back), dim(dm)), TRUE)
# One row per member per label, which is the shape a build script filters on.
listing <- quiet(datom_list_members(x))
claim("the listing carries the identifying columns",
      names(listing),
      c("name", "project", "version", "kind", "key", "value"))
claim("both members appear in the listing",
      sort(unique(listing$name)), c("dm", "lb"))


# --- 4. Re-writing the identical set, with the foreign files dirty -----------
hr("4. An unchanged set is free, even with the caller's files edited")

writeLines("build <- function() 'v2-WIP'", fs::path(repo_dir, "R", "build.R"))
claim("the caller's file is dirty before the write",
      "R/build.R" %in% unstaged(repo), TRUE)

head_before <- head_sha(repo)
versions_before <- datom_history(conn, "trial_product")$version
msgs <- capture.output(
  again <- datom_write_set(conn, x$members, name = "trial_product",
                           tags = x$tags,
                           include_paths = "R/build.R"),
  type = "message"
)

claim("the write reports no change", again$action, "none")
claim("no commit was made", head_sha(repo), head_before)
claim("no version was minted",
      datom_history(conn, "trial_product")$version, versions_before)
claim("the caller is told which verb commits their files",
      any(grepl("datom_repo_commit", msgs)), TRUE)
# A write that "helpfully" cleaned the working tree would pass the HEAD claim
# and lose the developer's work.
claim("the caller's edit is still dirty afterwards",
      "R/build.R" %in% unstaged(repo), TRUE)
claim("the caller's edit is still on disk",
      readLines(fs::path(repo_dir, "R", "build.R")),
      "build <- function() 'v2-WIP'")


# --- 5. An input moves: repoint one, drop one, CHAINED -----------------------
hr("5. An input moves -- repoint it, drop a retired one, in one chain")

# `lb` advances; `dm` does not. So a refresh must move exactly one member.
lb2 <- datom_example_data("lb", cutoff_date = "2026-02-28")
quiet(datom_write(conn, data = lb2, name = "lb"))
v_lb2 <- datom_history(conn, "lb")$version[1]
claim("lb really did advance", identical(v_lb1, v_lb2), FALSE)

# Commit the caller's in-flight edit first, so the set write below is not asked
# to carry unfinished work -- and so section 6's commit message is the set's own.
quiet(datom_repo_commit(conn, "Finish the build script", push = FALSE))

updated <- quiet(datom_update_members(x, conn))
claim("exactly one member moved",
      sum(vapply(updated$members,
                 function(m) identical(m$id$version, v_lb2), logical(1L))),
      1L)
claim("the member that did not move kept its pin",
      sum(vapply(updated$members,
                 function(m) identical(m$id$version, v_dm1), logical(1L))),
      1L)
# Labels are content: a repointed member that lost them would move the set's
# identity for a reason nobody asked for.
claim("the repointed member kept its labels",
      labels_of(updated, "lb"), sort(c("input", "safety")))
claim("an edited set stops claiming the version it was read as",
      is.null(updated$version), TRUE)

# Now drop one, on the SAME object, so both edits are in one log. Dropping takes
# no connection at all -- it only has to find a pointer the set already holds.
edited <- quiet(datom_remove_members(updated, member = "dm"))
claim("the dropped member is gone", length(edited$members), 1L)
claim("the survivor is the repointed one",
      edited$members[[1L]]$id$version, v_lb2)


# --- 6. The second write: one commit message naming BOTH edits ---------------
hr("6. The second write -- a new version, and a message that names both edits")

head_before <- head_sha(repo)
second <- quiet(datom_write_set(conn, edited, name = "trial_product"))

claim("the edited set writes a new version", second$action, "full")
claim("a commit was made",
      identical(head_sha(repo), head_before), FALSE)

# The whole point of the shared edit log: a chained edit produces ONE message
# describing all of it, rather than one naming the repoints and silent about the
# removal -- which is the edit a git log reader most wants named.
subject <- git2r::commits(repo, n = 1L)[[1L]]$summary
body <- git2r::commits(repo, n = 1L)[[1L]]$message
claim("the commit subject is not the plain default",
      identical(subject, "Update trial_product"), FALSE)
claim("the subject names the repoint", grepl("repoint", subject), TRUE)
claim("the subject names the removal", grepl("drop", subject), TRUE)
claim("the body lists what changed", grepl("lb|dm", body), TRUE)

versions <- datom_history(conn, "trial_product")$version
claim("the set now has two versions", length(versions), 2L)
# The reader-with-no-clone route to provenance: only the stored copy carries it.
claim("every version records the commit that produced it",
      anyNA(datom_history(conn, "trial_product")$commit_sha), FALSE)

# Both versions still read, and each reads as what it was -- which is the whole
# promise of citing a set by version.
now <- quiet(datom_get_set(reader, "trial_product"))
then <- quiet(datom_get_set(reader, "trial_product",
                            version = versions_before[[1L]]))
claim("the current version has one member", length(now$members), 1L)
claim("the earlier version still has two", length(then$members), 2L)
claim("the earlier version still pins the OLD lb",
      pinned_at(then, "lb"), v_lb1)
claim("the current version pins the new lb",
      pinned_at(now, "lb"), v_lb2)
claim("a member of the earlier version still resolves to data",
      is.data.frame(quiet(datom_fetch_member(reader, then, "dm"))), TRUE)


# --- 7. A refresh that finds nothing is free --------------------------------
hr("7. A refresh that finds nothing mints nothing")

versions_before <- datom_history(conn, "trial_product")$version
head_before <- head_sha(repo)
refreshed <- quiet(datom_update_members(now, conn))
free <- quiet(datom_write_set(conn, refreshed, name = "trial_product"))

claim("the write reports no change", free$action, "none")
claim("no version was minted",
      datom_history(conn, "trial_product")$version, versions_before)
claim("no commit was made", head_sha(repo), head_before)

# And the repo is consistent at the end of all of it.
check <- quiet(datom_validate(conn))
claim("datom_validate reports the repo consistent", check$valid, TRUE)

cat("\n--- repo tree (git) ---\n")
fs::dir_tree(repo_dir, recurse = 2L)
cat("\n--- store tree (one object per distinct content) ---\n")
fs::dir_tree(store_dir, recurse = 3L)


# --- summary ----------------------------------------------------------------
hr("summary")
if (.failures == 0L) {
  cat("All claims held.\n")
  cat("Project left at:", root, "\n")
} else {
  cat(.failures, "claim(s) FAILED -- see the << FAIL markers above.\n")
  cat("Project left at:", root, "\n")
  stop("e2e-sets: ", .failures, " claim(s) failed.", call. = FALSE)
}
