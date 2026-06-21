# dev/e2e-solo-local.R
# ──────────────────────────────────────────────────────────────────────────────
# Solo-project end-to-end test (local filesystem backend, NO governance).
#
# Confirms datom is fully functional standalone after the gov-seam lift-out:
#   init -> write -> read -> datom_repo_delete
#
# No AWS credentials needed (local backend). A GitHub PAT IS required: every
# datom data repo is git+GitHub-backed (there is no no-remote mode). Teardown
# uses datom_repo_delete() (the solo teardown verb) -- NOT datom_decommission()
# (removed by the lift-out) and NO gov functions.
#
# Usage (manual) -- works from ANY working directory (e.g. ~/projects/dev/datom-test).
# All datom paths below are absolute (~-anchored), so getwd() does not matter:
#   source("~/projects/dev/datom/dev/e2e-solo-local.R")
# Ensure a GitHub PAT is visible first, e.g.:
#   Sys.setenv(GITHUB_PAT = system("gh auth token", intern = TRUE))
#
# Prerequisites:
#   - GITHUB_PAT (env var or keyring) with repo create/delete scope
#   - `gh` CLI not required (datom_repo_delete deletes via httr2)
#
# All artefacts land under ~/projects/dev/datom-test/solo-e2e/ and are removed
# on teardown (including the real GitHub repo created during the run). Nothing
# is written into the datom project folder.
# ──────────────────────────────────────────────────────────────────────────────

.datom_pkg_dir <- path.expand("~/projects/dev/datom")
if (!exists("sandbox_up")) {
  devtools::load_all(.datom_pkg_dir)
  source(file.path(.datom_pkg_dir, "dev", "dev-sandbox.R"))
}

base_dir <- fs::path_expand("~/projects/dev/datom-test/solo-e2e")
if (fs::dir_exists(base_dir)) fs::dir_delete(base_dir)
fs::dir_create(base_dir)

proj      <- "SOLO_E2E"
repo_name <- paste0("datom-solo-e2e-", format(Sys.time(), "%Y%m%d%H%M%S"))
store_dir <- fs::path(base_dir, "solo-e2e-data")

store <- sandbox_store_local(
  path       = store_dir,
  prefix     = NULL,
  github_org = NULL,
  attach_gov = FALSE          # solo project: NO governance
)
stopifnot("store unexpectedly has governance" = is.null(store$governance))

env <- NULL
ok  <- FALSE

teardown <- function() {
  # Solo teardown: datom_repo_delete (GitHub repo + local clone), then wipe the
  # caller-owned local data-store root (datom_repo_delete does not own it).
  if (!is.null(env) && !is.null(env$conn)) {
    cat("\n=== TEARDOWN: datom_repo_delete ===\n")
    try(datom_repo_delete(env$conn, confirm = proj), silent = FALSE)
  }
  try(.sandbox_wipe_local_component(store$data, "data"), silent = TRUE)
  if (fs::dir_exists(base_dir)) try(fs::dir_delete(base_dir), silent = TRUE)
}

tryCatch({
  # ---- INIT + WRITE (populate two months of example data) ----
  cat("\n=== INIT + WRITE (sandbox_up, solo, populate) ===\n")
  env <- sandbox_up(
    store,
    project_name = proj,
    repo_name    = repo_name,
    base_dir     = base_dir,
    populate     = TRUE,
    n_months     = 2L
  )
  conn <- env$conn
  stopifnot("conn should be solo (gov_root NULL)" = is.null(conn$gov_root))
  stopifnot("conn should be solo (gov_backend NULL)" = is.null(conn$gov_backend))

  # ---- READ ----
  cat("\n=== READ ===\n")
  tbls <- datom_list(conn)
  print(tbls)
  stopifnot("expected dm + ex tables" = all(c("dm", "ex") %in% tbls$name))

  dm <- datom_read(conn, "dm")
  cat("dm rows:", nrow(dm), " cols:", ncol(dm), "\n")
  stopifnot("dm should have rows" = nrow(dm) > 0)

  hist_dm <- datom_history(conn, "dm")
  cat("dm history versions:", nrow(hist_dm), "\n")
  stopifnot("dm should have >=1 version" = nrow(hist_dm) >= 1)

  # ---- WRITE a fresh table (exercise write on solo conn directly) ----
  cat("\n=== WRITE (direct datom_write on solo conn) ===\n")
  datom_write(conn, data = data.frame(x = 1:3, y = c("a", "b", "c")),
              name = "solo_extra", message = "solo direct write")
  stopifnot("solo_extra not listed" = "solo_extra" %in% datom_list(conn)$name)
  back <- datom_read(conn, "solo_extra")
  stopifnot("solo_extra round-trip mismatch" = nrow(back) == 3)

  # ---- VALIDATE / STATUS ----
  cat("\n=== VALIDATE + STATUS ===\n")
  datom_validate(conn)
  datom_status(conn)

  # ---- datom_projects must fail cleanly (no gov), without naming datomanager ----
  cat("\n=== datom_projects() on solo conn (expect clean gov error) ===\n")
  pe <- tryCatch({ datom_projects(conn); NA_character_ },
                 error = function(e) conditionMessage(e))
  cat("datom_projects error:", pe, "\n")
  stopifnot("datom_projects should error on solo conn" = !is.na(pe))
  stopifnot("gov error must not name datomanager" =
              !grepl("datomanager", pe, ignore.case = TRUE))

  ok <- TRUE
  cat("\n=== ALL SOLO E2E ASSERTIONS PASSED ===\n")
}, finally = {
  teardown()
})

if (!ok) stop("SOLO_E2E_RESULT: FAILED (see messages above; teardown attempted).")
cat("\nSOLO_E2E_RESULT: SUCCESS\n")
