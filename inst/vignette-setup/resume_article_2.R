# inst/vignette-setup/resume_article_2.R
#
# Rebuild the end state of Article 1 ("First Extract") so a reader can begin
# Article 2 ("Month 2 Arrives") with a working conn.
#
# Contract:
#   - No arguments. Honors env vars DATOM_VIGNETTE_DIR and
#     DATOM_VIGNETTE_GOV_CLONE; defaults to tempdir() subdirs.
#   - Idempotent: if state from Article 1 already exists, this is a no-op.
#   - Continuity-only: if no prior state is found at the expected paths,
#     aborts with instructions. Re-creating GitHub repos from scratch is not
#     attempted (see phase_16_vignettes "Open Items").
#   - Returns invisible(list(conn = ..., study_dir = ..., gov_clone_path = ...)).
#
# Usage:
#   state <- source(
#     system.file("vignette-setup", "resume_article_2.R", package = "datom")
#   )$value
#   conn <- state$conn

local({
  study_dir <- Sys.getenv(
    "DATOM_VIGNETTE_DIR",
    fs::path(tempdir(), "study_001_data")
  )
  gov_clone_path <- Sys.getenv(
    "DATOM_VIGNETTE_GOV_CLONE",
    fs::path(tempdir(), "study_001_gov_clone")
  )

  # --- Continuity check -----------------------------------------------------
  project_yaml <- fs::path(study_dir, ".datom", "project.yaml")
  if (!fs::file_exists(project_yaml)) {
    cli::cli_abort(c(
      "No Article 1 state found at {.path {study_dir}}.",
      "i" = "Run Article 1 first, or set {.envvar DATOM_VIGNETTE_DIR} to a directory containing prior state.",
      "i" = "Resume scripts in this release require the prior article's local clone to be present."
    ))
  }
  if (!fs::dir_exists(gov_clone_path)) {
    cli::cli_abort(c(
      "No governance clone found at {.path {gov_clone_path}}.",
      "i" = "Set {.envvar DATOM_VIGNETTE_GOV_CLONE} or re-run Article 1 in this session."
    ))
  }

  cli::cli_alert_info("Resuming from Article 1 state at {.path {study_dir}}.")

  # --- Rebuild conn ---------------------------------------------------------
  conn <- datom::datom_get_conn(path = study_dir)

  # --- Verify expected end state of Article 1 -------------------------------
  tables <- tryCatch(datom::datom_list(conn), error = function(e) NULL)
  if (is.null(tables) || !"dm" %in% tables$name) {
    cli::cli_alert_warning(
      "Table {.val dm} not found. Writing Article 1 month-1 extract..."
    )
    dm_m1 <- datom::datom_example_data("dm", cutoff_date = "2026-01-28")
    datom::datom_write(
      conn,
      data    = dm_m1,
      name    = "dm",
      message = "Initial DM extract through 2026-01-28"
    )
  } else {
    cli::cli_alert_success("Article 1 state intact: {.val dm} present.")
  }

  invisible(list(
    conn           = conn,
    study_dir      = as.character(study_dir),
    gov_clone_path = as.character(gov_clone_path)
  ))
})
