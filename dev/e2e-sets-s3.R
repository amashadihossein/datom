# dev/e2e-sets-s3.R
# -----------------------------------------------------------------------------
# Sets against real infrastructure: two real GitHub repos and a real S3 bucket.
# Sibling of dev/e2e-sets.R, which walks the same ground fully offline.
#
# THE SHAPE, and it is the shape a real project has:
#
#   repo 1  STUDY_001   an ordinary data repo. Onboards CSVs with datom_sync().
#                       This is exactly what vignette("start-on-s3") walks you
#                       through.
#   repo 2  TRIAL_PROD  a product repo, in its own directory. Onboards nothing.
#                       It holds a SET that cites repo 1's tables by version.
#
# Two repos rather than one, because a product repo REFUSES datom_sync() -- it
# builds its artifacts, it does not import them. So a set's members have to come
# from somewhere else, and "somewhere else" is the case sets exist for: a
# citation that crosses projects.
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
# RUN:
#   Rscript ~/projects/dev/datom/dev/e2e-sets-s3.R
#
# Each run gets its own timestamped prefixes, repo names and directories, so
# runs never collide. Teardown removes both repos, both prefixes and both
# clones, then PROVES it by listing what is left -- sandbox_down() reports
# success whether or not anything was there, so its return value is not
# evidence.
#
# Not in CI: it costs real resources. Every claim is asserted; non-zero exit on
# any mismatch.
# -----------------------------------------------------------------------------

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
if (!nzchar(Sys.getenv("GITHUB_PAT"))) {
  stop("GITHUB_PAT is not set. It needs repo + delete_repo scope. See the header.",
       call. = FALSE)
}
if (!nzchar(Sys.getenv("AWS_ACCESS_KEY_ID")) ||
    !nzchar(Sys.getenv("AWS_SECRET_ACCESS_KEY"))) {
  cat("NOTE: AWS keys are not in the environment; paws may still find them in",
      "~/.aws.\n")
}
gh_ok <- system2("gh", "--version", stdout = FALSE, stderr = FALSE) == 0L
if (!gh_ok) cat("NOTE: no gh CLI -- the repos-are-gone check will be skipped.\n")

# --- run identity ------------------------------------------------------------
stamp    <- format(Sys.time(), "%Y%m%d%H%M%S")
bucket   <- "datom-test"
set_name <- "trial_product"

in_proj   <- "STUDY_001"
in_repo   <- paste0("datom-sets-e2e-inputs-", stamp)
in_prefix <- paste0("sets-e2e-inputs-", stamp, "/")

pr_proj   <- "TRIAL_PROD"
pr_repo   <- paste0("datom-sets-e2e-product-", stamp)
pr_prefix <- paste0("sets-e2e-product-", stamp, "/")

base_dir <- fs::path_expand(fs::path("~/projects/dev/datom-test",
                                     paste0("sets-e2e-s3-", stamp)))
if (fs::dir_exists(base_dir)) fs::dir_delete(base_dir)
fs::dir_create(base_dir)

cat("\nrun:    ", stamp,
    "\ninputs: ", in_repo, " -> s3://", bucket, "/", in_prefix,
    "\nproduct:", pr_repo, " -> s3://", bucket, "/", pr_prefix,
    "\nlocal:  ", as.character(base_dir), "\n", sep = "")

in_store <- sandbox_store(bucket = bucket, prefix = in_prefix,
                          region = "us-east-1")
pr_store <- sandbox_store(bucket = bucket, prefix = pr_prefix,
                          region = "us-east-1")

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
  reader_store <- datom_store(
    data = datom_store_s3(bucket = bucket, prefix = pr_prefix,
                          region = "us-east-1", validate = FALSE),
    github_pat = NULL, validate = FALSE)
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

  in_reader_store <- datom_store(
    data = datom_store_s3(bucket = bucket, prefix = in_prefix,
                          region = "us-east-1", validate = FALSE),
    github_pat = NULL, validate = FALSE)
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
}, finally = {
  hr("9. teardown, then check what is left")
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
})

hr("summary")
if (.failures == 0L && ok) {
  cat("All claims held.\nSETS_E2E_S3_RESULT: SUCCESS\n")
} else {
  cat(.failures, "claim(s) FAILED -- see the << FAIL markers above.\n")
  stop("SETS_E2E_S3_RESULT: FAILED (teardown attempted).", call. = FALSE)
}
