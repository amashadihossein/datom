# dev/e2e-solo-lineage.R
# ──────────────────────────────────────────────────────────────────────────────
# Solo-project end-to-end test: source_lineage (local backend, NO governance).
#
# Lineage is a pure data-side feature, so it runs fully standalone after the
# gov-seam lift-out. This is the solo conversion of the old gov-attached
# dev/e2e-lineage.R.
#
# Exercises:
#   - imported tables (dm, ex) get an auto self-entry in source_lineage
#   - a derived table written with parents + unioned source_lineage round-trips
#   - datom_get_lineage(depth = "source" | "parents")
#   - datom_validate_lineage() == "ok"
#   - structural mandate: datom_write(parents=...) without source_lineage errors
#
# Usage (manual) -- works from ANY working directory:
#   source("~/projects/dev/datom/dev/e2e-solo-lineage.R")
# Ensure a GitHub PAT is visible first, e.g.:
#   Sys.setenv(GITHUB_PAT = system("gh auth token", intern = TRUE))
#
# No AWS needed (local backend). Artefacts land under
# ~/projects/dev/datom-test/solo-e2e-lineage/ and are removed on teardown.
# ──────────────────────────────────────────────────────────────────────────────

.datom_pkg_dir <- path.expand("~/projects/dev/datom")
if (!exists("sandbox_up")) {
  devtools::load_all(.datom_pkg_dir)
  source(file.path(.datom_pkg_dir, "dev", "dev-sandbox.R"))
}

cat("=== Solo E2E: source_lineage ===\n\n")

base_dir  <- fs::path_expand("~/projects/dev/datom-test/solo-e2e-lineage")
if (fs::dir_exists(base_dir)) fs::dir_delete(base_dir)
fs::dir_create(base_dir)

proj      <- "SOLO_E2E_LIN"
repo_name <- paste0("datom-solo-e2e-lineage-", format(Sys.time(), "%Y%m%d%H%M%S"))
store_dir <- fs::path(base_dir, "solo-e2e-lineage-data")

store <- sandbox_store_local(
  path       = store_dir,
  prefix     = NULL,
  github_org = NULL
)
stopifnot("store unexpectedly has governance" = is.null(store$governance))

env <- NULL
ok  <- FALSE

tryCatch({
  env <- sandbox_up(
    store,
    project_name = proj,
    repo_name    = repo_name,
    base_dir     = base_dir,
    populate     = TRUE,
    n_months     = 1L
  )
  conn <- env$conn
  stopifnot("conn should be solo (gov_root NULL)" = is.null(conn$gov_root))

  # ---- Imported tables have self-lineage ----
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

  # ---- Write a derived table with parents + source_lineage ----
  # NOTE: a benign warning "Could not resolve data_sha for parent ..." is
  # expected here -- datom_write() prepends the project name when locating
  # same-project parent metadata (pre-existing; see issue #52). The write
  # succeeds and validate_lineage() is unaffected.
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
      list(source = proj, table = "dm", version = dm_meta$version[1]),
      list(source = proj, table = "ex", version = ex_meta$version[1])
    ),
    source_lineage = full_lineage
  )
  cat("datom_write() OK\n")

  # ---- Verify datom_get_lineage ----
  cat("\n--- datom_get_lineage() ---\n")
  src <- datom_get_lineage(conn, "summary_trt_by_sex", depth = "source")
  par <- datom_get_lineage(conn, "summary_trt_by_sex", depth = "parents")
  stopifnot("source has 2 entries"  = length(src) == 2L)
  stopifnot("parents has 2 entries" = length(par) == 2L)
  tables_in_src <- vapply(src, `[[`, character(1), "table")
  stopifnot("dm in source_lineage" = "dm" %in% tables_in_src)
  stopifnot("ex in source_lineage" = "ex" %in% tables_in_src)
  cat("Tables in source_lineage:", paste(sort(tables_in_src), collapse = ", "), "\n")

  # ---- Verify datom_validate_lineage ----
  cat("\n--- datom_validate_lineage() ---\n")
  val <- datom_validate_lineage(conn, "summary_trt_by_sex")
  cat("status:", val$status, "| missing:", length(val$missing),
      "| extra:", length(val$extra), "| wrong_version:", length(val$wrong_version), "\n")
  stopifnot("validate status is ok"    = val$status == "ok")
  stopifnot("no missing entries"       = length(val$missing) == 0L)
  stopifnot("no extra entries"         = length(val$extra) == 0L)
  stopifnot("no wrong_version entries" = length(val$wrong_version) == 0L)

  # ---- Structural mandate: parents without source_lineage -> error ----
  cat("\n--- Structural mandate: parents without source_lineage -> error ---\n")
  caught <- tryCatch(
    datom_write(conn,
      data    = derived,
      name    = "bad_table",
      message = "Should fail",
      parents = list(list(source = proj, table = "dm", version = dm_meta$version[1]))
    ),
    error = function(e) e
  )
  stopifnot("mandate error is raised" = inherits(caught, "error"))
  cat("Mandate correctly raised error:", conditionMessage(caught), "\n")

  ok <- TRUE
  cat("\n=== ALL SOLO LINEAGE E2E ASSERTIONS PASSED ===\n")
}, finally = {
  cat("\n--- Tear down (sandbox_down -> datom_repo_delete) ---\n")
  if (!is.null(env)) try(sandbox_down(env, confirm = FALSE), silent = FALSE)
  if (fs::dir_exists(base_dir)) try(fs::dir_delete(base_dir), silent = TRUE)
})

if (!ok) stop("SOLO_E2E_LINEAGE_RESULT: FAILED (see messages above; teardown attempted).")
cat("\nSOLO_E2E_LINEAGE_RESULT: SUCCESS\n")
