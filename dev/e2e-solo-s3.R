# dev/e2e-solo-s3.R
# ──────────────────────────────────────────────────────────────────────────────
# Solo-project end-to-end test (S3 backend, NO governance).
#
# Confirms datom is fully functional standalone on S3 after the gov-seam
# lift-out:
#   init -> write -> read -> derived table (parents + source_lineage) ->
#   validate / status -> datom_repo_delete (via sandbox_down)
#
# Mirrors the data-side feature coverage of the old gov-attached dev/e2e-test.R,
# minus everything that now lives in datomanager (datom_init_gov,
# datom_sync_dispatch, datom_decommission, governance.json, reader-via-gov).
#
# Usage (manual) -- works from ANY working directory:
#   source("~/projects/dev/datom/dev/e2e-solo-s3.R")
# Ensure credentials are visible first, e.g.:
#   Sys.setenv(GITHUB_PAT = system("gh auth token", intern = TRUE))
#   # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in the environment or keyring
#
# Prerequisites:
#   - GITHUB_PAT (repo create/delete scope)
#   - AWS credentials with access to the data bucket below
#   - An existing S3 bucket (default: datom-test)
#
# A unique prefix isolates each run; teardown wipes the run's datom/ namespace
# under that prefix (the bucket itself -- caller-owned -- is never deleted) and
# deletes the GitHub repo + local clone. The local clone lands under
# ~/projects/dev/datom-test/solo-e2e-s3/.
# ──────────────────────────────────────────────────────────────────────────────

.datom_pkg_dir <- path.expand("~/projects/dev/datom")
if (!exists("sandbox_up")) {
  devtools::load_all(.datom_pkg_dir)
  source(file.path(.datom_pkg_dir, "dev", "dev-sandbox.R"))
}

base_dir  <- fs::path_expand("~/projects/dev/datom-test/solo-e2e-s3")
if (fs::dir_exists(base_dir)) fs::dir_delete(base_dir)
fs::dir_create(base_dir)

stamp     <- format(Sys.time(), "%Y%m%d%H%M%S")
proj      <- "SOLO_E2E_S3"
repo_name <- paste0("datom-solo-e2e-s3-", stamp)
bucket    <- "datom-test"
prefix    <- paste0("solo-e2e-s3-", stamp, "/")   # isolate this run

store <- sandbox_store(
  bucket     = bucket,
  prefix     = prefix,
  region     = "us-east-1",
  github_org = NULL
)
stopifnot("store unexpectedly has governance" = is.null(store$governance))

env <- NULL
ok  <- FALSE

tryCatch({
  # ---- INIT + WRITE (populate two months of example data) ----
  cat("\n=== INIT + WRITE (sandbox_up, solo S3, populate) ===\n")
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
  stopifnot("conn backend should be s3" = identical(conn$backend, "s3"))

  # ---- READ imported tables ----
  cat("\n=== READ imported tables ===\n")
  tbls <- datom_list(conn)
  print(tbls)
  stopifnot("expected dm + ex tables" = all(c("dm", "ex") %in% tbls$name))

  dm <- datom_read(conn, "dm")
  ex <- datom_read(conn, "ex")
  cat("dm rows:", nrow(dm), " | ex rows:", nrow(ex), "\n")
  stopifnot("dm should have rows" = nrow(dm) > 0)

  # Imported tables: parents NULL, source_lineage self-entry present
  stopifnot("imported dm should have NULL parents" = is.null(datom_get_parents(conn, "dm")))
  dm_lineage <- datom_get_lineage(conn, "dm", depth = "source")
  ex_lineage <- datom_get_lineage(conn, "ex", depth = "source")
  stopifnot("dm self-lineage has 1 entry" = length(dm_lineage) == 1L)
  stopifnot("ex self-lineage has 1 entry" = length(ex_lineage) == 1L)

  # ---- WRITE a derived table with parents + source_lineage ----
  # NOTE: a benign warning "Could not resolve data_sha for parent ..." is
  # expected here -- datom_write() prepends the project name when locating
  # same-project parent metadata (pre-existing; see issue #52). The write
  # succeeds and validate_lineage() is unaffected.
  cat("\n=== WRITE derived table (parents + source_lineage) ===\n")
  dm_meta <- datom_history(conn, "dm")
  ex_meta <- datom_history(conn, "ex")

  summary_trt_by_sex <- ex |>
    dplyr::select(STUDYID, USUBJID, EXTRT) |>
    dplyr::left_join(x = dm) |>
    dplyr::group_by(SEX, EXTRT) |>
    dplyr::summarise(n = dplyr::n(), .groups = "drop")

  datom_write(
    conn,
    data           = summary_trt_by_sex,
    name           = "summary_trt_by_sex",
    message        = "Derived: summary of treatment by sex",
    parents        = list(
      list(source = proj, table = "dm", version = dm_meta$version[1]),
      list(source = proj, table = "ex", version = ex_meta$version[1])
    ),
    source_lineage = c(dm_lineage, ex_lineage)
  )

  # ---- VERIFY lineage ----
  cat("\n=== VERIFY lineage ===\n")
  src <- datom_get_lineage(conn, "summary_trt_by_sex", depth = "source")
  par <- datom_get_lineage(conn, "summary_trt_by_sex", depth = "parents")
  stopifnot("source has 2 entries"  = length(src) == 2L)
  stopifnot("parents has 2 entries" = length(par) == 2L)
  stopifnot("validate_lineage ok" =
              datom_validate_lineage(conn, "summary_trt_by_sex")$status == "ok")

  # ---- VALIDATE / STATUS ----
  cat("\n=== VALIDATE + STATUS ===\n")
  datom_validate(conn)
  datom_status(conn)

  # ---- datom_projects must fail cleanly on a solo conn (no governance) ----
  # By design (.datom_require_gov), the guard names datomanager as guidance --
  # it points the user to gov_attach() in the companion package. This is the
  # spec-sanctioned UX (design Component 8 / Task 5.2), distinct from C1's
  # "no hard dependency on datomanager".
  cat("\n=== datom_projects() on solo conn (expect clean gov guard) ===\n")
  pe <- tryCatch({ datom_projects(conn); NA_character_ },
                 error = function(e) conditionMessage(e))
  cat("datom_projects error:", pe, "\n")
  stopifnot("datom_projects should error on solo conn" = !is.na(pe))
  stopifnot("gov error should mention governance" =
              grepl("governance", pe, ignore.case = TRUE))
  stopifnot("gov error should point to gov_attach" =
              grepl("gov_attach", pe, fixed = TRUE))

  ok <- TRUE
  cat("\n=== ALL SOLO S3 E2E ASSERTIONS PASSED ===\n")
}, finally = {
  cat("\n=== TEARDOWN (sandbox_down -> datom_repo_delete + S3 namespace wipe) ===\n")
  if (!is.null(env)) try(sandbox_down(env, confirm = FALSE), silent = FALSE)
  if (fs::dir_exists(base_dir)) try(fs::dir_delete(base_dir), silent = TRUE)
})

if (!ok) stop("SOLO_E2E_S3_RESULT: FAILED (see messages above; teardown attempted).")
cat("\nSOLO_E2E_S3_RESULT: SUCCESS\n")
