# inst/vignette-setup/resume_article_2.R
#
# Rebuild the end state of Article 1 ("First Extract") so a reader can begin
# Article 2 ("Month 2 Arrives") with a working conn.
#
# Contract:
#   - No arguments. Honors env var DATOM_VIGNETTE_DIR; defaults to a
#     tempdir() subdir.
#   - Idempotent: if state from Article 1 already exists, this is a no-op.
#   - Continuity-only: if no prior state is found at the expected paths,
#     aborts with instructions. Re-creating GitHub repos from scratch is not
#     attempted (see phase_16_vignettes "Open Items").
#   - Article 1 has no governance attached; gov is opt-in and arrives in
#     Article 4 via datom_attach_gov().
#   - Returns invisible(list(conn = ..., dev_dir = ...)).
#
# Usage:
#   state <- source(
#     system.file("vignette-setup", "resume_article_2.R", package = "datom")
#   )$value
#   conn <- state$conn

local({
  dev_dir <- Sys.getenv(
    "DATOM_VIGNETTE_DIR",
    fs::path(tempdir(), "study_001_dev")
  )

  # --- Continuity check -----------------------------------------------------
  project_yaml <- fs::path(dev_dir, ".datom", "project.yaml")
  if (!fs::file_exists(project_yaml)) {
    cli::cli_abort(c(
      "No Article 1 state found at {.path {dev_dir}}.",
      "i" = "Run Article 1 first, or set {.envvar DATOM_VIGNETTE_DIR} to a directory containing prior state.",
      "i" = "Resume scripts in this release require the prior article's local clone to be present."
    ))
  }

  cli::cli_alert_info("Resuming from Article 1 state at {.path {dev_dir}}.")

  cfg <- yaml::read_yaml(project_yaml)
  data_cfg <- cfg$storage$data
  if (!identical(data_cfg$type, "local")) {
    cli::cli_abort(c(
      "Article 2 resume expects a local-backend project.",
      "i" = "Current backend is {.val {data_cfg$type}}. Use the matching resume script."
    ))
  }

  store <- datom::datom_store(
    governance = NULL,
    data       = datom::datom_store_local(path = data_cfg$root),
    github_pat = keyring::key_get("GITHUB_PAT"),
    data_repo_url = cfg$repos$data$remote_url
  )

  # --- Rebuild conn ---------------------------------------------------------
  conn <- datom::datom_get_conn(path = dev_dir, store = store)

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
    conn      = conn,
    dev_dir = as.character(dev_dir)
  ))
})
