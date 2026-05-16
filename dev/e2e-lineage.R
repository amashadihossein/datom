# dev/e2e-lineage.R
# ──────────────────────────────────────────────────────────────────────────────
# E2E test: Phase 20 source_lineage
#
# Prerequisites:
#   - GITHUB_PAT set in environment (keyring or env var)
#   - gh CLI available (for teardown only)
#
# Run from the tbit project root in an R session:
#   devtools::load_all()
#   source("dev/dev-sandbox.R")
#   source("dev/e2e-lineage.R")
# ──────────────────────────────────────────────────────────────────────────────

cat("=== Phase 20 E2E: source_lineage ===\n\n")

# --- Stand up sandbox --------------------------------------------------------

base_dir <- fs::path_expand("~/projects/dev/datom-test")

store <- sandbox_store_local(
  path       = fs::path(base_dir, "local-e2e-lineage"),
  prefix     = NULL,
  github_org = NULL
)

env <- sandbox_up(store,
  project_name  = "LOCAL_E2E_LIN",
  repo_name     = "datom-local-e2e-lineage",
  gov_repo_name = "datom-local-e2e-lineage-gov",
  base_dir      = base_dir,
  populate      = TRUE,
  n_months      = 1L
)

conn <- env$conn

# --- Confirm imported tables have self-lineage -------------------------------

cat("\n--- Imported table lineage (datom_sync auto-self) ---\n")
dm_lineage <- datom_get_lineage(conn, "dm", depth = "source")
ex_lineage <- datom_get_lineage(conn, "ex", depth = "source")

stopifnot("dm self-lineage has 1 entry" = length(dm_lineage) == 1L)
stopifnot("ex self-lineage has 1 entry" = length(ex_lineage) == 1L)
stopifnot("dm entry has project field"  = nzchar(dm_lineage[[1]]$project))
stopifnot("dm entry table == dm"        = dm_lineage[[1]]$table == "dm")
stopifnot("dm entry has version_sha"    = nzchar(dm_lineage[[1]]$version_sha))

cat("dm source_lineage: project =", dm_lineage[[1]]$project,
    "| table =", dm_lineage[[1]]$table,
    "| version_sha =", substr(dm_lineage[[1]]$version_sha, 1, 8), "...\n")
cat("ex source_lineage: project =", ex_lineage[[1]]$project,
    "| table =", ex_lineage[[1]]$table,
    "| version_sha =", substr(ex_lineage[[1]]$version_sha, 1, 8), "...\n")

# --- Write a derived table with parents + source_lineage ---------------------

cat("\n--- Writing derived table with parents + source_lineage ---\n")

dm_meta      <- datom_history(conn, "dm")
ex_meta      <- datom_history(conn, "ex")
dm_data      <- datom_read(conn, "dm")
ex_data      <- datom_read(conn, "ex")
full_lineage <- c(dm_lineage, ex_lineage)

derived <- ex_data |>
  dplyr::select(STUDYID, USUBJID, EXTRT) |>
  dplyr::left_join(dm_data, by = c("STUDYID", "USUBJID")) |>
  dplyr::group_by(SEX, EXTRT) |>
  dplyr::summarise(n = dplyr::n(), .groups = "drop")

datom_write(conn,
  data           = derived,
  name           = "summary_trt_by_sex",
  message        = "Derived: treatment by sex",
  parents        = list(
    list(source = "LOCAL_E2E_LIN", table = "dm", version = dm_meta$version[1]),
    list(source = "LOCAL_E2E_LIN", table = "ex", version = ex_meta$version[1])
  ),
  source_lineage = full_lineage
)
cat("datom_write() OK\n")

# --- Verify datom_get_lineage ------------------------------------------------

cat("\n--- datom_get_lineage() ---\n")
src <- datom_get_lineage(conn, "summary_trt_by_sex", depth = "source")
par <- datom_get_lineage(conn, "summary_trt_by_sex", depth = "parents")

cat("source depth entries:", length(src), "\n")
cat("parents depth entries:", length(par), "\n")

stopifnot("source has 2 entries"  = length(src) == 2L)
stopifnot("parents has 2 entries" = length(par) == 2L)

tables_in_src <- vapply(src, `[[`, character(1), "table")
stopifnot("dm in source_lineage" = "dm" %in% tables_in_src)
stopifnot("ex in source_lineage" = "ex" %in% tables_in_src)
cat("Tables in source_lineage:", paste(sort(tables_in_src), collapse = ", "), "\n")

# --- Verify datom_validate_lineage -------------------------------------------

cat("\n--- datom_validate_lineage() ---\n")
val <- datom_validate_lineage(conn, "summary_trt_by_sex")

cat("status:        ", val$status, "\n")
cat("missing:       ", length(val$missing), "\n")
cat("extra:         ", length(val$extra), "\n")
cat("wrong_version: ", length(val$wrong_version), "\n")
cat("message:       ", val$message, "\n")

stopifnot("validate status is ok"    = val$status == "ok")
stopifnot("no missing entries"       = length(val$missing) == 0L)
stopifnot("no extra entries"         = length(val$extra) == 0L)
stopifnot("no wrong_version entries" = length(val$wrong_version) == 0L)

# --- Structural mandate: parents without source_lineage -> error --------------

cat("\n--- Structural mandate: parents without source_lineage -> error ---\n")
caught <- tryCatch(
  datom_write(conn,
    data    = derived,
    name    = "bad_table",
    message = "Should fail",
    parents = list(list(source = "LOCAL_E2E_LIN", table = "dm", version = dm_meta$version[1]))
  ),
  error = function(e) e
)
stopifnot("mandate error is raised" = inherits(caught, "error"))
cat("Mandate correctly raised error:", conditionMessage(caught), "\n")

# --- Tear down ---------------------------------------------------------------

cat("\n--- Tear down ---\n")
sandbox_down(env)

cat("\n=== E2E PASS ===\n")
