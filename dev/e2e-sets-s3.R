# dev/e2e-sets-s3.R
# -----------------------------------------------------------------------------
# Sets against real infrastructure: two real GitHub repos and a real S3 bucket.
# Sibling of dev/e2e-sets.R, which walks the same ground fully offline.
#
# THE SHAPE, and it is Case A from datom-sets design.md section 20 -- the common
# one: a single study, one bucket, onboarding under the empty prefix and the
# product under a prefix beside it.
#
#   s3://<bucket>/<run>/imported/datom/   repo 1  STUDY_001   onboarded tables
#   s3://<bucket>/<run>/adam/datom/       repo 2  STUDY_ADAM  the SET + derived
#
#   repo 1  onboards CSVs with datom_sync(), exactly as vignette("start-on-s3").
#   repo 2  is a product repo in its own directory under prefix "<run>/adam". It
#           onboards nothing; it holds a SET citing repo 1's tables by version.
#
# BOTH PREFIXES ARE NAMED, and "imported" is not decoration: it is the word the
# table's own record uses (`table_type = "imported"` versus `"derived"`), so the
# folder and the metadata agree. The earlier draft put onboarding at the bare
# prefix, which meant the segment `datom/` appeared at two depths meaning the
# same thing and read at the top level like a container for everything below it.
# The prefix is a plain string -- `raw/`, `edc/`, `sdtm/` are equally valid; this
# is a convention, not a contract.
#
# Two repos rather than one, because a product repo REFUSES datom_sync() -- it
# builds its artifacts, it does not import them. So a set's members come from
# somewhere else, and here that is a sibling prefix in the SAME bucket: the
# ordinary "one study, its raw data plus its product" layout, not a cross-bucket
# pool (that is Case B, and it is a later vignette).
#
# WHAT THIS COVERS THAT THE OFFLINE SCRIPT CANNOT:
#   1. GitHub repo creation through the API
#   2. S3 as the store, not a local directory
#   3. ref.json resolution against a real store
#   4. a reader with S3 credentials and NO PAT and NO clone
#   5. a member whose project is not the set's project
#
# It does NOT re-assert set semantics -- 4292 unit tests and the offline
# script's 51 claims cover those.
#
# NEEDS:
#   - GITHUB_PAT with repo + delete_repo scope:
#       Sys.setenv(GITHUB_PAT = system("gh auth token", intern = TRUE))
#   - AWS credentials for the bucket below, which must already exist.
#     The bucket is yours and is never deleted; only this run's prefixes are.
#   - gh CLI, used only to check the repos are gone afterwards.
#
# RUN, two ways:
#
#   # 1. one shot -- walk, assert, tear down, report
#   Rscript ~/projects/dev/datom/dev/e2e-sets-s3.R
#
#   # 2. leave it standing so you can query it, then clean up by hand.
#   #    Source it rather than Rscript it, or the session exits with the objects.
#   Sys.setenv(DATOM_E2E_KEEP = "1")
#   source("~/projects/dev/datom/dev/e2e-sets-s3.R")
#   # ... poke at in_conn / pr_conn / reader ...
#   e2e_teardown()
#
# NAMES ARE FIXED, and the script CLEANS UP BEFORE IT STARTS as well as after.
# So a run that died half way leaves at most one set of leftovers, the next run
# clears them, and anything sitting in your account or bucket is named plainly
# enough to delete by eye. Timestamped names were the earlier approach; they
# isolate runs but accumulate orphans that nothing ever collects, which is the
# quieter failure.
#
# Teardown removes both repos, both prefixes and both clones, then PROVES it by
# listing what is left -- sandbox_down() reports success whether or not anything
# was there, so its return value is not evidence.
#
# TEARDOWN IS A SEPARATE STEP, not a `finally`. The walk leaves a live product
# repo citing a live inputs repo, which is worth querying -- and on a failure it
# is the state you need in order to understand the failure.
#
# Not in CI: it costs real resources. Every claim is asserted; non-zero exit on
# any mismatch.
# -----------------------------------------------------------------------------

# --- credentials -------------------------------------------------------------
# ENVIRONMENT VARIABLES ONLY. This script deliberately does NOT touch keyring.
#
# Why: on macOS, keychain access is authorised per application binary, so R.app,
# RStudio's R and the `Rscript` binary each need their own grant -- and a named
# (non-login) keychain locks on its own timer on top of that. The result is a
# password prompt on almost every run, which is what this used to do. Reading the
# environment cannot prompt, so it cannot surprise you.
#
# SET THEM ONCE in ~/.Renviron, which R reads at startup in every context -- the
# console, RStudio, and Rscript -- with no prompt, ever:
#
#   AWS_ACCESS_KEY_ID=AKIA...
#   AWS_SECRET_ACCESS_KEY=...
#
# Then `usethis::edit_r_environ()` to edit it, and restart R once. Treat that file
# the way you treat ~/.aws/credentials: user-readable only (chmod 600), never
# committed. If you would rather not put them on disk, set them for the session
# instead:
#
#   Sys.setenv(AWS_ACCESS_KEY_ID = "...", AWS_SECRET_ACCESS_KEY = "...")
#
# Pulling them out of a keychain is fine too -- just do it in YOUR session before
# sourcing this file, so the prompt happens once where you expect it, rather than
# inside a script you run repeatedly.
#
# GITHUB_PAT needs no setup: it comes from `gh auth token` when the gh CLI is
# logged in, which needs no keychain of its own and already carries the
# delete_repo scope teardown requires.
.e2e_pat_from_gh <- function() {
  if (nzchar(Sys.getenv("GITHUB_PAT"))) return("environment")
  if (system2("gh", "--version", stdout = FALSE, stderr = FALSE) != 0L) {
    return(NA_character_)
  }
  tok <- tryCatch(paste(system2("gh", c("auth", "token"), stdout = TRUE,
                                stderr = FALSE), collapse = ""),
                  error = function(e) "")
  if (!nzchar(tok)) return(NA_character_)
  Sys.setenv(GITHUB_PAT = tok)
  "gh auth token"
}

.e2e_sources <- c(
  GITHUB_PAT            = .e2e_pat_from_gh(),
  AWS_ACCESS_KEY_ID     = if (nzchar(Sys.getenv("AWS_ACCESS_KEY_ID")))
                            "environment" else NA_character_,
  AWS_SECRET_ACCESS_KEY = if (nzchar(Sys.getenv("AWS_SECRET_ACCESS_KEY")))
                            "environment" else NA_character_
)

.datom_pkg_dir <- path.expand("~/projects/dev/datom")
if (!exists("sandbox_up")) {
  devtools::load_all(.datom_pkg_dir, quiet = TRUE)
  source(file.path(.datom_pkg_dir, "dev", "dev-sandbox.R"))
}
options(crayon.enabled = FALSE)

hr <- function(x) cat("\n\n==========", x, "==========\n")
.failures <- 0L
claim <- function(label, actual, expected) {
  actual <- unname(actual)
  ok <- identical(actual, expected)
  if (!ok) .failures <<- .failures + 1L
  cat(sprintf("%-58s %-14s %s\n", label,
              paste(as.character(actual), collapse = ","),
              if (ok) "" else paste0("<< FAIL, expected ",
                                     paste(as.character(expected), collapse = ","))))
  invisible(ok)
}
quiet <- function(expr) suppressMessages(expr)
head_sha <- function(repo) as.character(git2r::revparse_single(repo, "HEAD")$sha)
tree_paths <- function(repo, sha) {
  e <- git2r::ls_tree(repo = repo, tree = git2r::tree(git2r::lookup(repo, sha)))
  paste0(e$path, e$name)
}
# A member's pinned version, off the record a read hands back.
pin_of <- function(x, nm) {
  hit <- Filter(function(m) identical(m$id$name, nm), x$members)
  if (length(hit) != 1L) return(NA_character_)
  hit[[1L]]$id$version
}
proj_of <- function(x, nm) {
  hit <- Filter(function(m) identical(m$id$name, nm), x$members)
  if (length(hit) != 1L) return(NA_character_)
  hit[[1L]]$id$project
}

# --- 0. Check credentials before creating anything ---------------------------
hr("0. preflight")
for (nm in names(.e2e_sources)) {
  cat(sprintf("%-24s %s\n", nm,
              if (is.na(.e2e_sources[[nm]])) "NOT FOUND"
              else .e2e_sources[[nm]]))
}
if (!nzchar(Sys.getenv("GITHUB_PAT"))) {
  stop("GITHUB_PAT is not set and `gh auth token` gave nothing.\n",
       "  Fix: run `gh auth login` (the token needs repo + delete_repo), or\n",
       "  Sys.setenv(GITHUB_PAT = \"...\") before sourcing this file.",
       call. = FALSE)
}
if (!nzchar(Sys.getenv("AWS_ACCESS_KEY_ID")) ||
    !nzchar(Sys.getenv("AWS_SECRET_ACCESS_KEY"))) {
  stop("AWS credentials are not in the environment.\n",
       "  Easiest fix, once, no prompts ever again -- put these two lines in\n",
       "  ~/.Renviron (usethis::edit_r_environ()) and restart R:\n\n",
       "    AWS_ACCESS_KEY_ID=...\n",
       "    AWS_SECRET_ACCESS_KEY=...\n\n",
       "  Or for this session only:\n",
       "    Sys.setenv(AWS_ACCESS_KEY_ID = \"...\", AWS_SECRET_ACCESS_KEY = \"...\")\n\n",
       "  This script does not read your keychain on purpose -- see the header.",
       call. = FALSE)
}
gh_ok <- system2("gh", "--version", stdout = FALSE, stderr = FALSE) == 0L
if (!gh_ok) cat("NOTE: no gh CLI -- the repos-are-gone check will be skipped.\n")

# Keep the repos and the S3 prefixes standing after the walk, so they can be
# queried. Teardown then becomes an explicit `e2e_teardown()` call.
KEEP <- nzchar(Sys.getenv("DATOM_E2E_KEEP"))
cat("teardown:", if (KEEP) "DEFERRED -- call e2e_teardown() when done"
    else "automatic at the end", "\n")

# --- run identity ------------------------------------------------------------
stamp    <- format(Sys.time(), "%Y%m%d%H%M%S")
bucket   <- "datom-test"
set_name <- "trial_product"

# Case A layout: one bucket, one root, both projects at NAMED prefixes beneath
# it. Uniform depth, so every project is at <root>/<name>/datom/.
#
# FIXED NAMES, NOT TIMESTAMPED, and the pre-clean below is what makes that safe.
# Timestamps isolate runs, but they make a failed run leave an orphan repo and an
# orphan prefix that nothing will ever collect -- and orphans are quiet, while a
# name collision is loud. Fixed names plus delete-if-exists means at most one set
# of leftovers can exist, the next run clears it, and anything left behind is
# named so you can find it by eye. The trade given up is concurrent runs, which a
# script one person runs by hand does not need.
run_root  <- "sets-e2e"

in_proj   <- "STUDY_001"
in_repo   <- "datom-sets-e2e-inputs"
in_prefix <- paste0(run_root, "/imported/")

pr_proj   <- "STUDY_ADAM"
pr_repo   <- "datom-sets-e2e-product"
pr_prefix <- paste0(run_root, "/adam/")

# Fixed too, and emptied by the pre-clean below rather than here, so there is one
# place that decides what a leftover is.
base_dir <- fs::path_expand("~/projects/dev/datom-test/sets-e2e-s3")

cat("\nstarted:", stamp,
    "\ninputs: ", in_repo, " -> s3://", bucket, "/", in_prefix,
    "\nproduct:", pr_repo, " -> s3://", bucket, "/", pr_prefix,
    "\nlocal:  ", as.character(base_dir), "\n", sep = "")

in_store <- sandbox_store(bucket = bucket, prefix = in_prefix,
                          region = "us-east-1")
pr_store <- sandbox_store(bucket = bucket, prefix = pr_prefix,
                          region = "us-east-1")

# --- 0b. Pre-clean: make a failed previous run harmless ----------------------
# The names are fixed, so a leftover from a failed run would otherwise block
# `datom_init_repo()` (GitHub refuses a duplicate name) and trip the
# namespace-occupied check (storage still holds another project's manifest).
#
# Both halves matter and they fail differently: the repo is refused loudly, the
# prefix is refused loudly too, but a HALF-cleaned pair is the state that
# confuses -- so clean both every time rather than checking whether the last run
# succeeded. Reuses the sandbox's own helpers, so there is one implementation of
# "remove a GitHub repo" and one of "wipe a namespace".
hr("0b. pre-clean anything a previous run left behind")
for (nm in c(in_repo, pr_repo)) {
  full <- tryCatch(.sandbox_repo_full_name(list(github_org = NULL),
                                           repo_name = nm),
                   error = function(e) NA_character_)
  if (is.na(full)) next
  exists_rc <- system2("gh", c("repo", "view", shQuote(full)),
                       stdout = FALSE, stderr = FALSE)
  if (exists_rc == 0L) {
    cat("found leftover repo", full, "-- deleting\n")
    try(.sandbox_gh_repo_delete(full, "leftover data repo"), silent = FALSE)
  } else {
    cat("no leftover repo", full, "\n")
  }
}
for (s in list(list(st = pr_store, lab = "product"),
               list(st = in_store, lab = "imported"))) {
  try(quiet(.sandbox_wipe_storage(s$st, s$lab)), silent = FALSE)
}
if (fs::dir_exists(base_dir)) fs::dir_delete(base_dir)
fs::dir_create(base_dir)

in_env <- NULL; pr_env <- NULL; ok <- FALSE
in_full <- NA_character_; pr_full <- NA_character_

tryCatch({

  # --- 1. Repo 1: onboard data, the way start-on-s3 does --------------------
  hr("1. inputs repo: onboard two files from CSV")
  in_env <- quiet(sandbox_up(
    in_store, project_name = in_proj, repo_name = in_repo,
    base_dir = as.character(base_dir), populate = TRUE, n_months = 1L
  ))
  in_conn <- quiet(datom_get_conn(path = in_env$local_path, store = in_store))
  in_repo_obj <- git2r::repository(in_env$local_path)
  in_full <- .sandbox_repo_full_name(
    in_env$config, repo_url = git2r::remote_url(in_repo_obj, "origin"))

  claim("inputs backend is s3", in_conn$backend, "s3")
  claim("ref resolution found the bucket", in_conn$root, bucket)
  claim("ref resolution found the prefix", in_conn$prefix, in_prefix)
  claim("two tables onboarded", sort(datom_list(in_conn)$name), c("dm", "ex"))

  v_dm1 <- datom_history(in_conn, "dm")$version[1]
  v_ex1 <- datom_history(in_conn, "ex")$version[1]

  # --- 2. Repo 2: the product repo, its own directory -----------------------
  hr("2. product repo: declares mode product, onboards nothing")
  pr_env <- quiet(sandbox_up(
    pr_store, project_name = pr_proj, repo_name = pr_repo,
    base_dir = as.character(base_dir), populate = FALSE,
    mode = "product", set = set_name
  ))
  pr_conn <- quiet(datom_get_conn(path = pr_env$local_path, store = pr_store))
  pr_repo_obj <- git2r::repository(pr_env$local_path)
  pr_full <- .sandbox_repo_full_name(
    pr_env$config, repo_url = git2r::remote_url(pr_repo_obj, "origin"))

  cfg <- yaml::read_yaml(fs::path(pr_env$local_path, ".datom", "project.yaml"))
  claim("product repo declares mode", cfg$mode, "product")
  claim("product repo names its set", cfg$set, set_name)
  claim("the two repos are separate directories",
        !identical(in_env$local_path, pr_env$local_path), TRUE)

  # A product repo refuses to import. Asserted because it is the reason there
  # are two repos at all.
  refused <- tryCatch({ quiet(datom_sync_manifest(pr_conn)); NULL },
                      condition = identity)
  claim("the product repo refuses to onboard files",
        inherits(refused, "datom_import_on_product"), TRUE)

  # --- 3. The set cites the other project's tables --------------------------
  hr("3. a set in the product repo, citing the inputs project")
  draft <- quiet(datom_assemble_set(
    pr_conn, tags = list(description = "Trial data cut, month 1")))
  draft <- quiet(datom_add_member(
    draft, datom_member(in_conn, "dm", v_dm1,
                        tags = list(type = "input", domain = "safety"))))
  draft <- quiet(datom_add_member(
    draft, datom_member(in_conn, "ex", v_ex1,
                        tags = list(type = "input", domain = "exposure"))))

  # The caller's own code, committed into the same commit as the set.
  fs::dir_create(fs::path(pr_env$local_path, "R"))
  writeLines("build <- function() 'v1'",
             fs::path(pr_env$local_path, "R", "build.R"))
  writeLines('{"R": {"Version": "4.4.1"}}',
             fs::path(pr_env$local_path, "renv.lock"))

  head_before <- head_sha(pr_repo_obj)
  first <- quiet(datom_write_set(
    draft, include_paths = c("R/build.R", "renv.lock")))
  in_tree <- tree_paths(pr_repo_obj, head_sha(pr_repo_obj))

  claim("the set was written", first$action, "full")
  claim("it has two members", first$member_count, 2L)
  claim("HEAD moved once", !identical(head_sha(pr_repo_obj), head_before), TRUE)
  claim("one commit holds the payload",
        paste0(set_name, "/set.json") %in% in_tree, TRUE)
  claim("the same commit holds the build code", "R/build.R" %in% in_tree, TRUE)
  claim("the same commit holds the lockfile", "renv.lock" %in% in_tree, TRUE)

  pr_keys <- datom_storage_list(pr_conn)
  # Keys come back with the `datom/` namespace segment on the front, so this is
  # not anchored at the start. The payload sits at {set}/{data_sha}.json; the
  # versioned metadata snapshot has the same shape one level deeper under
  # .metadata/, which is why that is excluded rather than matched loosely.
  is_payload <- grepl(paste0("/", set_name, "/[0-9a-f]+\\.json$"), pr_keys) &
    !grepl("\\.metadata/", pr_keys)
  claim("the product store holds the set payload", any(is_payload), TRUE)
  claim("the product store holds no build code",
        any(grepl("build\\.R|renv\\.lock", pr_keys)), FALSE)
  claim("no table data landed in the product store",
        any(grepl("\\.parquet$", pr_keys)), FALSE)

  # --- 4. A reader with no clone and no PAT ---------------------------------
  hr("4. the citation resolves for a reader with S3 only")
  # Reuse the store COMPONENT the run already built rather than constructing a
  # fresh one: `datom_store_s3()` has no credential defaults, so rebuilding it
  # here duplicates the credential plumbing and drifts from whatever
  # sandbox_store() resolved. Dropping the PAT is the only difference that
  # matters -- that is what makes this a reader.
  reader_store <- datom_store(data = pr_store$data, github_pat = NULL,
                              validate = FALSE)
  reader <- quiet(datom_get_conn(store = reader_store, project_name = pr_proj))
  claim("the reader has no clone", is.null(reader$path), TRUE)
  claim("the reader is a reader", reader$role, "reader")

  x <- quiet(datom_get_set(reader, set_name))
  claim("the reader resolved the set", length(x$members), 2L)
  claim("the set is the version just written", x$version, first$metadata_sha)
  claim("the set belongs to the product project", x$project, pr_proj)
  claim("its members belong to the inputs project", proj_of(x, "dm"), in_proj)
  claim("dm is pinned at month 1", pin_of(x, "dm"), v_dm1)

  # Reading a member's data needs a connection to the MEMBER's project. The
  # product reader alone cannot do it, and that is the point: a product is
  # citable by someone entitled to none of its data.
  no_access <- tryCatch({ quiet(datom_fetch_member(reader, x, "dm")); NULL },
                        condition = identity)
  claim("the product reader cannot reach the data on its own",
        !is.null(no_access), TRUE)

  in_reader_store <- datom_store(data = in_store$data, github_pat = NULL,
                                 validate = FALSE)
  in_reader <- quiet(datom_get_conn(store = in_reader_store,
                                    project_name = in_proj))
  dm_data <- quiet(datom_fetch_member(in_reader, x, "dm"))
  claim("with the inputs project's credentials, the data resolves",
        nrow(dm_data) > 0L, TRUE)

  # --- 5. An input moves in the other project ------------------------------
  hr("5. month 2 arrives in the inputs repo; the product repoints")
  cutoffs <- datom_example_cutoffs()
  write.csv(datom_example_data("dm", cutoff_date = cutoffs[[2]]),
            fs::path(in_env$local_path, "input_files", "dm.csv"),
            row.names = FALSE)
  mf <- quiet(datom_sync_manifest(in_conn))
  quiet(datom_sync(in_conn, mf, continue_on_error = FALSE))
  v_dm2 <- datom_history(in_conn, "dm")$version[1]
  claim("dm has a new version", !identical(v_dm2, v_dm1), TRUE)

  y <- quiet(datom_get_set(pr_conn, set_name))
  y <- quiet(datom_update_members(y, in_conn))
  claim("the set now pins dm at month 2", pin_of(y, "dm"), v_dm2)
  claim("ex was left alone", pin_of(y, "ex"), v_ex1)

  # --- 6. Drop a member, then write both edits at once ---------------------
  hr("6. drop a member; one commit message for both edits")
  y <- quiet(datom_remove_members(y, "ex"))
  claim("one member left", length(y$members), 1L)

  second <- quiet(datom_write_set(pr_conn, y))
  claim("the second write happened", second$action, "full")
  claim("the version moved",
        !identical(second$metadata_sha, first$metadata_sha), TRUE)
  msg <- git2r::commits(pr_repo_obj, n = 1L)[[1L]]$message
  claim("the message names the repoint", grepl("repoint", msg), TRUE)
  claim("the message names the removal", grepl("drop", msg), TRUE)

  # --- 7. The old citation still means what it meant -----------------------
  hr("7. the first version is unchanged")
  old <- quiet(datom_get_set(reader, set_name, version = first$metadata_sha))
  claim("it still has two members", length(old$members), 2L)
  claim("it still pins dm at month 1", pin_of(old, "dm"), v_dm1)

  # --- 8. Refreshing an up-to-date set is free -----------------------------
  hr("8. a refresh that finds nothing writes nothing")
  z <- quiet(datom_get_set(pr_conn, set_name))
  z <- quiet(datom_update_members(z, in_conn))
  third <- quiet(datom_write_set(pr_conn, z))
  claim("no write happened", third$action, "none")
  claim("the version is unchanged", third$metadata_sha, second$metadata_sha)

  ok <- TRUE
}, error = function(e) {
  cat("\nERROR:", conditionMessage(e), "\n")
  .failures <<- .failures + 1L
})

# --- 9. Teardown, as its own step -------------------------------------------
# Separated deliberately. The walk above leaves two live repos and two live S3
# prefixes, and that state is worth querying -- so teardown is a function you
# call, not something that fires in a `finally`.
e2e_teardown <- function() {
  hr("teardown, then check what is left")
  for (e in list(pr_env, in_env)) {
    if (!is.null(e)) try(quiet(sandbox_down(e, confirm = FALSE)), silent = FALSE)
  }
  if (fs::dir_exists(base_dir)) try(fs::dir_delete(base_dir), silent = TRUE)

  left_pr <- tryCatch(datom_storage_list(pr_conn), error = function(e) character())
  left_in <- tryCatch(datom_storage_list(in_conn), error = function(e) character())
  claim("product prefix is empty", length(left_pr), 0L)
  claim("inputs prefix is empty", length(left_in), 0L)
  claim("both clones are gone", fs::dir_exists(base_dir), FALSE)

  if (gh_ok) {
    for (nm in c(pr_full, in_full)) {
      if (is.na(nm)) next
      rc <- system2("gh", c("repo", "view", shQuote(nm)),
                    stdout = FALSE, stderr = FALSE)
      claim(paste0("repo gone: ", nm), rc != 0L, TRUE)
    }
  } else {
    cat("SKIPPED: no gh CLI, cannot check the repos are gone.\n")
  }
  invisible(.failures)
}

hr("summary")
if (.failures == 0L && ok) {
  cat("All claims held so far.\n")
} else {
  cat(.failures, "claim(s) FAILED -- see the << FAIL markers above.\n")
}

if (KEEP) {
  cat("\n--- LEFT STANDING for you to poke at (DATOM_E2E_KEEP is set) ---\n")
  # Guarded: on an early failure one or both sandboxes may not exist, and this
  # block must still print the teardown instruction rather than erroring over it.
  cat("inputs repo :", if (is.null(in_env)) "(not created)" else in_env$local_path, "\n")
  cat("product repo:", if (is.null(pr_env)) "(not created)" else pr_env$local_path, "\n")
  cat("s3          : s3://", bucket, "/", in_prefix, "  and  ",
      pr_prefix, "\n", sep = "")
  cat("\nobjects in this session:\n")
  cat("  in_conn, pr_conn        developer connections to each repo\n")
  cat("  reader, in_reader       storage-only connections, no PAT, no clone\n")
  cat("  set_name                \"", set_name, "\"\n", sep = "")
  cat("\nthings to try:\n")
  cat('  x <- datom_get_set(pr_conn, set_name); print(x)\n')
  cat('  datom_list_members(x)\n')
  cat('  datom_structure_members(x, by = "type")\n')
  cat('  datom_history(pr_conn, set_name)\n')
  cat('  datom_list(in_conn)\n')
  cat('  datom_validate(pr_conn)\n')
  cat('  datom_fetch_member(in_reader, x, "dm")   # data needs the inputs project\n')
  cat("\nWHEN DONE -- this leaves real repos and real objects behind:\n")
  cat("  e2e_teardown()\n")
  if (!interactive()) {
    cat("\nNOTE: run non-interactively, so this session is about to exit and\n",
        "      those objects go with it. Source the script from an R session\n",
        "      instead if you want to query them:\n",
        '        source("~/projects/dev/datom/dev/e2e-sets-s3.R")\n', sep = "")
  }
} else {
  e2e_teardown()
  hr("final")
  if (.failures == 0L && ok) {
    cat("All claims held.\nSETS_E2E_S3_RESULT: SUCCESS\n")
  } else {
    cat(.failures, "claim(s) FAILED.\n")
    stop("SETS_E2E_S3_RESULT: FAILED (teardown ran).", call. = FALSE)
  }
}
