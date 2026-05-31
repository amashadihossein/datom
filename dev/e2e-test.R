# dev/e2e-test.R
# ──────────────────────────────────────────────────────────────────────────────
# End-to-end test script for datom (S3 backend, gov-attached)
#
# Drives the full gov-attached workflow:
#   datom_init_gov() -> datom_init_repo() -> datom_write() ->
#   datom_sync_dispatch() -> datom_decommission()
#
# Usage:
#   devtools::load_all()
#   source("dev/dev-sandbox.R")
#   source("dev/e2e-test.R")
#
# Prerequisites:
#   - AWS credentials (via keyring, env vars, or any source)
#   - GITHUB_PAT
#   - S3 buckets exist (data + governance)
#   - `gh` CLI for teardown only
# ──────────────────────────────────────────────────────────────────────────────

# --- Build store -------------------------------------------------------------
# sandbox_store() constructs a datom_store from keyring credentials.
# Override arguments for different buckets, orgs, etc.

store <- sandbox_store(
  bucket     = "datom-test",
  gov_bucket = "datom-gov-test",
  prefix     = NULL,
  region     = "us-east-1"
)

# --- Stand up sandbox --------------------------------------------------------
# sandbox_up() now (Phase 15) calls datom_init_gov() first to bootstrap the
# governance repo + storage, then datom_init_repo() for the data project.

env <- sandbox_up(
  store,
  project_name  = "STUDY_001",
  repo_name     = "study-001-data",
  gov_repo_name = "datom-gov-test",
  populate      = TRUE,
  n_months      = 2L
)

conn <- env$conn

# --- Explore imported tables -------------------------------------------------

datom_list(conn)

dm <- datom_read(conn, "dm")
head(dm)

datom_history(conn, "dm")

# Parents should be NULL for imported tables
datom_get_parents(conn, "dm")

# --- Write a derived table with parents --------------------------------------

ex <- datom_read(conn, "ex")
dm_meta <- datom_history(conn, "dm")
ex_meta <- datom_history(conn, "ex")

summary_trt_by_sex <- ex |>
  dplyr::select(STUDYID, USUBJID, EXTRT) |>
  dplyr::left_join(x = dm) |>
  dplyr::group_by(SEX, EXTRT) |>
  dplyr::summarise(n = dplyr::n(), .groups = "drop")

# Fetch source_lineage from each imported parent and union them
dm_lineage <- datom_get_lineage(conn, "dm", depth = "source")
ex_lineage <- datom_get_lineage(conn, "ex", depth = "source")

datom_write(
  conn,
  data           = summary_trt_by_sex,
  name           = "summary_trt_by_sex",
  message        = "Derived: summary of treatment by sex",
  parents        = list(
    list(source = "STUDY_001", table = "dm", version = dm_meta$version[1]),
    list(source = "STUDY_001", table = "ex", version = ex_meta$version[1])
  ),
  source_lineage = c(dm_lineage, ex_lineage)
)

# --- Verify lineage ---------------------------------------------------------

datom_list(conn)
datom_get_parents(conn, "summary_trt_by_sex")
datom_get_lineage(conn, "summary_trt_by_sex", depth = "source")   # should show dm + ex raw SHAs
datom_get_lineage(conn, "summary_trt_by_sex", depth = "parents")  # should show dm + ex versions
datom_history(conn, "summary_trt_by_sex")
stopifnot(datom_validate_lineage(conn, "summary_trt_by_sex")$status == "ok")

# --- Sync dispatch (gov-side commit + push) ---------------------------------
# dispatch.json lives in the governance repo at
# projects/{project_name}/dispatch.json. datom_sync_dispatch() commits and
# pushes the gov clone, leaving the data clone untouched.

datom_sync_dispatch(conn, .confirm = FALSE)

# --- Validate and status -----------------------------------------------------

datom_validate(conn)
datom_status(conn)

# --- Phase 21: governance.json verification ----------------------------------
# Verify governance.json was written to both git clone and S3 mirror.

local({
  gov_json_git <- fs::path(env$local_path, ".datom", "governance.json")
  stopifnot("governance.json absent from git clone" = fs::file_exists(gov_json_git))
  gj <- jsonlite::read_json(gov_json_git)
  stopifnot("gov_repo_url missing"    = nzchar(gj$gov_repo_url))
  stopifnot("gov_storage absent"      = !is.null(gj$gov_storage))
  stopifnot("gov_storage root absent" = nzchar(gj$gov_storage$root))
  # governance.json is a governance pointer; project_name lives in project.yaml
  proj_yaml <- yaml::read_yaml(fs::path(env$local_path, ".datom", "project.yaml"))
  stopifnot("project.yaml project_name mismatch" =
              identical(proj_yaml$project_name, env$config$project_name))

  storage_gj <- datom:::.datom_storage_read_json(conn, ".metadata/governance.json")
  stopifnot("governance.json storage mirror absent"    = !is.null(storage_gj))
  stopifnot("storage mirror gov_repo_url missing"      = nzchar(storage_gj$gov_repo_url))
  stopifnot("storage mirror gov_storage root missing"  = nzchar(storage_gj$gov_storage$root))

  cat("governance.json OK: present in git clone and S3 mirror.\n")
})

# --- Phase 21: reader with credentials-only data store (issue #24) -----------
# This is the central scenario: a reader connects using only their credentials.
# They do NOT know the data bucket, prefix, or region -- that comes from
# ref.json in the governance repo at connection time.

reader_store <- datom::datom_store(
  governance = datom::datom_store_s3(
    bucket     = env$store$governance$bucket,
    prefix     = env$store$governance$prefix,
    region     = env$store$governance$region,
    access_key = Sys.getenv("AWS_ACCESS_KEY_ID"),
    secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY"),
    validate   = FALSE
  ),
  data = datom::datom_store_s3_creds(
    access_key = Sys.getenv("AWS_ACCESS_KEY_ID"),
    secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY")
  )
  # No github_pat: readers have no git access; role = "reader" is auto-derived
)

reader_conn <- datom::datom_get_conn(
  project_name = env$config$project_name,
  store        = reader_store
)

# Reader should be able to list and read tables
reader_tables <- datom::datom_list(reader_conn)
stopifnot("reader sees no tables" = nrow(reader_tables) > 0)

dm_reader <- datom::datom_read(reader_conn, "dm")
stopifnot("reader got empty dm" = nrow(dm_reader) > 0)

cat("Phase 21 reader OK: connected via governance + read", nrow(dm_reader), "rows from 'dm'.\n")
cat("  Data bucket resolved from ref.json:", reader_conn$root, "\n")

# --- Recover env (if you lost the session) -----------------------------------
# If you closed R without tearing down, re-source the sandbox helpers,
# build a store, and recover the env object:
#
# devtools::load_all("~/projects/dev/tbit/")
# source("~/projects/dev/tbit/dev/dev-sandbox.R")

#   store <- sandbox_store(bucket = "datom-test", prefix = NULL, region = "us-east-1")

#   env <- sandbox_recover(
#     store,
#     project_name  = "STUDY_001",
#     repo_name     = "study-001-data",
#     gov_repo_name = "datom-gov-test"
#   )

# --- Tear down ---------------------------------------------------------------
# sandbox_down() with default scope = "all" decommissions the data project
# then destroys the gov repo:
#   sandbox_down(env, scope = "project")  # data project only
#   sandbox_down(env, scope = "gov")      # gov only (refuses if projects remain)
#   sandbox_down(env, scope = "all")      # project then gov (default)
#
# sandbox_down(env)
