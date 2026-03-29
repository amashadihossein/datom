# dev/e2e-test.R
# ──────────────────────────────────────────────────────────────────────────────
# End-to-end test script for datom
#
# Usage:
#   devtools::load_all()
#   source("dev/dev-sandbox.R")
#   source("dev/e2e-test.R")
#
# Prerequisites:
#   - `gh` CLI installed and authenticated
#   - AWS credentials (via keyring, env vars, or any source)
#   - GITHUB_PAT
#   - S3 bucket exists
# ──────────────────────────────────────────────────────────────────────────────

# --- Credentials -------------------------------------------------------------
# sandbox_credentials enforces the project_name <-> env var coupling.
# Swap keyring calls for plain strings if you prefer.

sandbox_credentials(
  project_name = "STUDY_001",
  access_key   = keyring::key_get("AWS_ACCESS_KEY", "datom-developer", "remotes"),
  secret_key   = keyring::key_get("AWS_SECRET_KEY", "datom-developer", "remotes"),
  github_pat   = keyring::key_get("GITHUB_PAT", "kol", "remotes")
)

# --- Stand up sandbox --------------------------------------------------------

env <- sandbox_up(
  project_name = "STUDY_001",
  repo_name    = "study-001-data",
  bucket       = "datom-test",
  prefix       = NULL,
  region       = "us-east-1",
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
    list(source = "STUDY_001", table = "dm", version = dm_meta$version[1]),
    list(source = "STUDY_001", table = "ex", version = ex_meta$version[1])
  )
)

# --- Verify Phase 8 fields --------------------------------------------------

datom_list(conn)
datom_get_parents(conn, "summary_trt_by_sex")
datom_history(conn, "summary_trt_by_sex")

# --- Validate and status -----------------------------------------------------

datom_validate(conn)
datom_status(conn)

# --- Tear down ---------------------------------------------------------------
# sandbox_down(env)
