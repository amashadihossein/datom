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

# --- Phase 21: governance.json verification (Flow 1 + 2) --------------------
# Flow 1 verified in Section B (no-gov sandbox below).
# Flow 2: gov-attached sandbox -- governance.json must exist in both locations.

local({
  gov_json_git <- fs::path(env$local_path, ".datom", "governance.json")
  stopifnot("governance.json absent from git clone" = fs::file_exists(gov_json_git))

  gj <- jsonlite::read_json(gov_json_git)
  stopifnot("gov_repo_url missing" = nzchar(gj$gov_repo_url))
  stopifnot("project_name mismatch" = identical(gj$project_name, "LOCAL_E2E"))

  # Storage mirror
  data_store <- env$store$data
  store_key <- datom:::.datom_build_storage_key(conn, ".metadata/governance.json")
  storage_bytes <- datom:::.datom_storage_read_json(conn, ".metadata/governance.json")
  stopifnot("governance.json storage mirror absent" = !is.null(storage_bytes))
  stopifnot("storage mirror project_name mismatch" =
              identical(storage_bytes$project_name, "LOCAL_E2E"))

  cat("Flow 2 OK: governance.json present in git clone and storage mirror.\n")
})

# --- Phase 21: reader data-first warning (Flow 4) ----------------------------
# Build a reader store with no gov component against the gov-attached project.
# Should warn (not error) that the location may go stale.
local({
  reader_store_no_gov <- datom::datom_store(
    governance = NULL,
    data       = datom::datom_store_local(
      path     = datom:::.datom_store_root(env$store$data),
      prefix   = env$store$data$prefix,
      validate = FALSE
    ),
    github_pat    = env$store$github_pat,
    data_repo_url = env$store$data_repo_url,
    validate      = FALSE
  )

  warns <- character()
  withCallingHandlers(
    {
      reader_conn <- datom::datom_get_conn(
        project_name = "LOCAL_E2E",
        store        = reader_store_no_gov
      )
    },
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  # The data-first probe should have emitted a warning mentioning gov_repo_url
  gov_warn <- grep("gov_repo_url|governance", warns, value = TRUE)
  stopifnot("Flow 4: expected governance warning not emitted" = length(gov_warn) > 0)
  cat("Flow 4 OK: reader data-first emits governance warning.\n")
})

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

# Fetch source_lineage from each imported parent and union them
dm_lineage <- datom_get_lineage(conn, "dm", depth = "source")
ex_lineage <- datom_get_lineage(conn, "ex", depth = "source")
full_lineage <- c(dm_lineage, ex_lineage)

datom_write(
  conn,
  data           = summary_trt_by_sex,
  name           = "summary_trt_by_sex",
  message        = "Derived: summary of treatment by sex",
  parents        = list(
    list(source = "LOCAL_E2E", table = "dm", version = dm_meta$version[1]),
    list(source = "LOCAL_E2E", table = "ex", version = ex_meta$version[1])
  ),
  source_lineage = full_lineage
)

# --- Verify lineage ----------------------------------------------------------

datom_list(conn)
datom_get_parents(conn, "summary_trt_by_sex")
datom_get_lineage(conn, "summary_trt_by_sex", depth = "source")   # should show dm + ex raw SHAs
datom_get_lineage(conn, "summary_trt_by_sex", depth = "parents")  # should show dm + ex versions

result <- datom_validate_lineage(conn, "summary_trt_by_sex")
stopifnot(result$status == "ok")

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
# Phase 21 Flow 6: after sandbox_down() the storage mirror should be gone.
# Capture the storage path before teardown, verify after.
#
# storage_mirror_key <- datom:::.datom_build_storage_key(conn, ".metadata/governance.json")
# sandbox_down(env)
# # (After teardown the storage root is wiped, so the key is implicitly gone.
# #  datom_decommission() deletes it explicitly in step 1b as a belt-and-braces.)
# cat("Flow 6 OK: governance.json storage mirror removed by decommission.\n")
#
# sandbox_down(env)


# =============================================================================
# B: No-gov path (Phase 18) + Phase 21 Flows 1 & 5 -- uncomment to exercise
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
# # Phase 21 Flow 1: no-gov sandbox must have NO governance.json in git or storage.
# gov_json_git_nogov <- fs::path(env_nogov$local_path, ".datom", "governance.json")
# stopifnot("governance.json should be absent for no-gov sandbox" =
#             !fs::file_exists(gov_json_git_nogov))
# cat("Flow 1 OK: governance.json correctly absent for no-gov sandbox.\n")
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
# # Phase 21 Flow 2 (from no-gov): governance.json should now exist in both locations.
# gov_json_after_promote <- fs::path(env_nogov$local_path, ".datom", "governance.json")
# stopifnot("governance.json absent from clone after promote" =
#             fs::file_exists(gov_json_after_promote))
# storage_gj <- datom:::.datom_storage_read_json(conn_nogov, ".metadata/governance.json")
# stopifnot("governance.json storage mirror absent after promote" = !is.null(storage_gj))
# cat("Flow 2 (no-gov->gov): governance.json present after datom_attach_gov.\n")
#
# # Phase 21 Flow 5: simulate "developer pulls after teammate attached gov".
# # Clone the data repo fresh; governance.json should be in the clone (it's in git).
# fresh_clone_path <- fs::path(base_dir, "datom-local-e2e-nogov-fresh")
# if (fs::dir_exists(fresh_clone_path)) fs::dir_delete(fresh_clone_path)
# datom_clone(
#   data_repo_url = conn_nogov$data_repo_url,
#   path          = fresh_clone_path,
#   store         = env_nogov$store,
#   project_name  = "LOCAL_E2E_NOGOV"
# )
# gov_json_fresh <- fs::path(fresh_clone_path, ".datom", "governance.json")
# stopifnot("governance.json absent from fresh clone" = fs::file_exists(gov_json_fresh))
# gj_fresh <- jsonlite::read_json(gov_json_fresh)
# stopifnot("gov_repo_url mismatch in fresh clone" =
#             identical(gj_fresh$gov_repo_url, conn_nogov$gov_repo_url))
# cat("Flow 5 OK: governance.json present in fresh clone after pull.\n")
# fs::dir_delete(fresh_clone_path)
#
# # Gov-only commands now work
# datom_sync_dispatch(conn_nogov, .confirm = FALSE)
# datom_validate(conn_nogov)
#
# # Tear down
# sandbox_down(env_nogov)
