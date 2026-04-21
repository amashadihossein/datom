# dev/e2e-test-local.R
# ──────────────────────────────────────────────────────────────────────────────
# End-to-end test for local filesystem backend
#
# Mirrors dev/e2e-test.R exactly — same data workflow, same assertions —
# using the local backend instead of S3.
#
# Usage:
#   devtools::load_all()
#   source("dev/dev-sandbox.R")
#   source("dev/e2e-test-local.R")
#
# Prerequisites:
#   - GITHUB_PAT (via keyring or env var)
#   - `gh` CLI for teardown only
#   - No AWS credentials needed!
#
# All artefacts land under ~/projects/dev/datom-test/:
#   datom-test/local-e2e-data/       ← parquet data store
#   datom-test/local-e2e-data-gov/   ← governance store
#   datom-test/datom-local-e2e/      ← git repo (cloned locally)
# ──────────────────────────────────────────────────────────────────────────────

# --- Build local store -------------------------------------------------------

base_dir      <- fs::path_expand("~/projects/dev/datom-test")
local_storage_dir <- fs::path(base_dir, "local-e2e-data")

store <- sandbox_store_local(
  path       = local_storage_dir,
  prefix     = NULL,
  github_org = NULL
)

# --- Stand up sandbox --------------------------------------------------------

env <- sandbox_up(
  store,
  project_name = "LOCAL_E2E",
  repo_name    = "datom-local-e2e",
  base_dir     = base_dir,
  populate     = TRUE,
  n_months     = 2L
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

datom_write(
  conn,
  data    = summary_trt_by_sex,
  name    = "summary_trt_by_sex",
  message = "Derived: summary of treatment by sex",
  parents = list(
    list(source = "LOCAL_E2E", table = "dm", version = dm_meta$version[1]),
    list(source = "LOCAL_E2E", table = "ex", version = ex_meta$version[1])
  )
)

# --- Verify lineage ----------------------------------------------------------

datom_list(conn)
datom_get_parents(conn, "summary_trt_by_sex")
datom_history(conn, "summary_trt_by_sex")

# --- Validate and status -----------------------------------------------------

datom_validate(conn)
datom_status(conn)

# --- Recover env (if you lost the session) -----------------------------------
# If you closed R without tearing down, re-source the sandbox helpers,
# build a store, and recover the env object:
#
#   devtools::load_all()
#   source("dev/dev-sandbox.R")
#
#   store <- sandbox_store_local(
#     path = fs::path("~/projects/dev/datom-test", "local-e2e-data"),
#     prefix = NULL
#   )
#
#   env <- sandbox_recover(
#     store,
#     project_name = "LOCAL_E2E",
#     repo_name    = "datom-local-e2e",
#     base_dir     = fs::path_expand("~/projects/dev/datom-test")
#   )

# --- Tear down ---------------------------------------------------------------
# Uncomment to clean up (deletes GitHub repo, git dir, and all local storage):
#
# sandbox_down(env)
