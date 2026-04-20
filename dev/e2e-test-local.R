# dev/e2e-test-local.R
# ──────────────────────────────────────────────────────────────────────────────
# End-to-end test for local filesystem backend
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
# ──────────────────────────────────────────────────────────────────────────────

# --- Configuration -----------------------------------------------------------

local_storage_dir <- fs::path_abs("../datom-local-e2e")
local_gov_dir <- fs::path_abs("../datom-local-e2e-gov")
repo_name <- paste0("datom-local-e2e-", format(Sys.time(), "%Y%m%d%H%M%S"))
project_name <- "LOCAL_E2E"

# --- Build local store -------------------------------------------------------

store <- sandbox_store_local(
  path       = local_storage_dir,
  gov_path   = local_gov_dir,
  prefix     = "e2e/",
  github_org = NULL
)

cat("Store built:\n")
print(store)

# --- Init datom repo with local storage -------------------------------------

local_repo_path <- fs::path_abs(paste0("../", repo_name))

cli::cli_h2("Initializing local-backend datom repo")

datom::datom_init_repo(

  path         = local_repo_path,
  project_name = project_name,
  store        = store,
  create_repo  = TRUE,
  repo_name    = repo_name
)

cli::cli_alert_success("Init complete at {.path {local_repo_path}}")

# --- Get connection ----------------------------------------------------------

conn <- datom::datom_get_conn(path = local_repo_path, store = store)

cat("\nConnection:\n")
print(conn)

stopifnot(conn$backend == "local")
stopifnot(conn$role == "developer")

# --- Write a table -----------------------------------------------------------

cli::cli_h2("Writing table")

test_data <- data.frame(
  USUBJID = paste0("SUBJ-", 1:10),
  AGE     = sample(20:80, 10, replace = TRUE),
  SEX     = sample(c("M", "F"), 10, replace = TRUE),
  stringsAsFactors = FALSE
)

datom::datom_write(
  conn    = conn,
  data    = test_data,
  name    = "demographics",
  message = "Initial demographics data"
)

# --- Read it back ------------------------------------------------------------

cli::cli_h2("Reading table")

result <- datom::datom_read(conn, "demographics")

stopifnot(is.data.frame(result))
stopifnot(nrow(result) == 10L)
stopifnot(all(c("USUBJID", "AGE", "SEX") %in% names(result)))

cli::cli_alert_success("Read back {nrow(result)} rows, {ncol(result)} cols")

# --- List tables -------------------------------------------------------------

cli::cli_h2("Listing tables")

tbl_list <- datom::datom_list(conn)
print(tbl_list)

stopifnot("demographics" %in% tbl_list$table)

# --- History -----------------------------------------------------------------

cli::cli_h2("Version history")

hist <- datom::datom_history(conn, "demographics")
print(hist)

stopifnot(nrow(hist) >= 1L)

# --- Write updated data (change detection) -----------------------------------

cli::cli_h2("Writing updated table")

test_data_v2 <- rbind(test_data, data.frame(
  USUBJID = "SUBJ-11",
  AGE     = 55L,
  SEX     = "F",
  stringsAsFactors = FALSE
))

datom::datom_write(
  conn    = conn,
  data    = test_data_v2,
  name    = "demographics",
  message = "Added SUBJ-11"
)

result_v2 <- datom::datom_read(conn, "demographics")
stopifnot(nrow(result_v2) == 11L)

hist_v2 <- datom::datom_history(conn, "demographics")
stopifnot(nrow(hist_v2) == 2L)

cli::cli_alert_success("Version 2: {nrow(result_v2)} rows, {nrow(hist_v2)} versions")

# --- Validate ----------------------------------------------------------------

cli::cli_h2("Validating")

datom::datom_validate(conn)

# --- Status ------------------------------------------------------------------

cli::cli_h2("Status")

datom::datom_status(conn)

# --- Sync (import CSV files) -------------------------------------------------

cli::cli_h2("Sync: importing CSV")

input_dir <- fs::path(local_repo_path, "input_files")
write.csv(
  data.frame(STUDYID = "TEST", DOMAIN = "AE", AETERM = c("Headache", "Nausea")),
  fs::path(input_dir, "ae.csv"),
  row.names = FALSE
)

manifest <- datom::datom_sync_manifest(conn)
print(manifest)

if (any(manifest$status %in% c("new", "changed"))) {
  datom::datom_sync(conn, manifest, continue_on_error = FALSE)
}

ae <- datom::datom_read(conn, "ae")
stopifnot(nrow(ae) == 2L)

cli::cli_alert_success("Sync imported ae table: {nrow(ae)} rows")

# --- Final summary -----------------------------------------------------------

cli::cli_h2("E2E Local Backend: ALL CHECKS PASSED")

cat("\nStorage root:", conn$root, "\n")
cat("Repo path:   ", conn$path, "\n")
cat("Backend:     ", conn$backend, "\n")
cat("Tables:      ", paste(datom::datom_list(conn)$table, collapse = ", "), "\n")

# --- Teardown ----------------------------------------------------------------
# Uncomment to clean up:
#
# env <- list(
#   config = list(
#     project_name = project_name,
#     repo_name = repo_name,
#     github_org = NULL
#   ),
#   store = store,
#   local_path = local_repo_path
# )
# class(env) <- "datom_sandbox"
#
# # Delete GitHub repo
# .sandbox_check_gh()
# .sandbox_gh("repo", "delete", paste0(.sandbox_gh("api", "user", "-q", ".login")$output, "/", repo_name), "--yes")
#
# # Delete local dirs
# fs::dir_delete(local_repo_path)
# fs::dir_delete(local_storage_dir)
#
# cli::cli_alert_success("Teardown complete")
