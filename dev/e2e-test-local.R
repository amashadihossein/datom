# dev/e2e-test-local.R
# ──────────────────────────────────────────────────────────────────────────────
# End-to-end test for local filesystem backend.
#
# Drives the gov-attached workflow:
#   datom_init_gov() -> datom_init_repo() -> datom_write() ->
#   datom_sync_dispatch() -> datom_decommission()
#
# A second block (commented out) exercises the Phase-18 no-gov path:
#   datom_init_repo() (no gov) -> datom_write() -> datom_attach_gov() ->
#   datom_sync_dispatch() -> datom_decommission()
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
#   datom-test/local-e2e-data/      <- parquet data store
#   datom-test/local-e2e-data-gov/  <- governance store (filesystem)
#   datom-test/datom-local-e2e/     <- data git clone
#   datom-test/datom-local-e2e-gov/ <- gov git clone
# ──────────────────────────────────────────────────────────────────────────────

# =============================================================================
# A: Gov-attached path (default)
# =============================================================================

# --- Build local store -------------------------------------------------------

base_dir          <- fs::path_expand("~/projects/dev/datom-test")
local_storage_dir <- fs::path(base_dir, "local-e2e-data")

store <- sandbox_store_local(
  path       = local_storage_dir,
  prefix     = NULL,
  github_org = NULL
)

# --- Stand up sandbox --------------------------------------------------------

env <- sandbox_up(
  store,
  project_name  = "LOCAL_E2E",
  repo_name     = "datom-local-e2e",
  gov_repo_name = "datom-local-e2e-gov",
  base_dir      = base_dir,
  populate      = TRUE,
  n_months      = 2L
)

conn <- env$conn

# --- Explore imported tables -------------------------------------------------

datom_list(conn)

dm <- datom_read(conn, "dm")
head(dm)

datom_history(conn, "dm")

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

# --- Sync dispatch (gov-side commit + push) ---------------------------------

datom_sync_dispatch(conn, .confirm = FALSE)

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
#     project_name  = "LOCAL_E2E",
#     repo_name     = "datom-local-e2e",
#     gov_repo_name = "datom-local-e2e-gov",
#     base_dir      = fs::path_expand("~/projects/dev/datom-test")
#   )

# --- Tear down ---------------------------------------------------------------
# sandbox_down() with default scope = "all" decommissions the data project
# then destroys the gov repo:
#   sandbox_down(env, scope = "project")  # data project only
#   sandbox_down(env, scope = "gov")      # gov only (refuses if projects remain)
#   sandbox_down(env, scope = "all")      # project then gov (default)
#
# sandbox_down(env)


# =============================================================================
# B: No-gov path (Phase 18) -- uncomment to exercise
# =============================================================================
#
# store_nogov <- sandbox_store_local(
#   path       = fs::path(base_dir, "local-e2e-nogov-data"),
#   prefix     = NULL,
#   github_org = NULL,
#   attach_gov = FALSE
# )
#
# env_nogov <- sandbox_up(
#   store_nogov,
#   project_name  = "LOCAL_E2E_NOGOV",
#   repo_name     = "datom-local-e2e-nogov",
#   gov_repo_name = "datom-local-e2e-nogov-gov",
#   base_dir      = base_dir,
#   populate      = TRUE,
#   n_months      = 2L
# )
#
# conn_nogov <- env_nogov$conn
# stopifnot(is.null(conn_nogov$gov_root))
#
# datom_list(conn_nogov)
# datom_write(conn_nogov, data.frame(x = 1L), name = "nogov_table")
# stopifnot("nogov_table" %in% datom_list(conn_nogov)$name)
#
# # datom_projects() should fail clearly (no gov attached)
# tryCatch(datom_projects(conn_nogov), error = function(e) message("Expected: ", conditionMessage(e)))
#
# # Promote to gov-attached
# gov_store_for_promote <- datom_store_local(
#   path     = fs::path(base_dir, "local-e2e-nogov-data-gov"),
#   validate = FALSE
# )
# env_nogov <- sandbox_promote_gov(env_nogov, gov_store_for_promote)
# conn_nogov <- env_nogov$conn
# stopifnot(!is.null(conn_nogov$gov_root))
#
# # Gov-only commands now work
# datom_sync_dispatch(conn_nogov, .confirm = FALSE)
# datom_validate(conn_nogov)
#
# # Tear down
# sandbox_down(env_nogov)
