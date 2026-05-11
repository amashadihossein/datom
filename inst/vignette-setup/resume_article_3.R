# inst/vignette-setup/resume_article_3.R
#
# Rebuild the end state of Article 2 ("Month 2 Arrives") so a reader can begin
# Article 3 ("A Folder of Extracts") with a working conn.
#
# Contract: see resume_article_2.R header.
#
# Returns invisible(list(conn, dev_dir)).

local({
  dev_dir <- Sys.getenv(
    "DATOM_VIGNETTE_DIR",
    fs::path(tempdir(), "study_001_dev")
  )

  project_yaml <- fs::path(dev_dir, ".datom", "project.yaml")
  if (!fs::file_exists(project_yaml)) {
    cli::cli_abort(c(
      "No prior vignette state found at {.path {dev_dir}}.",
      "i" = "Run Articles 1 and 2 first, or set {.envvar DATOM_VIGNETTE_DIR} to a directory containing prior state."
    ))
  }

  cli::cli_alert_info("Resuming from Article 2 state at {.path {dev_dir}}.")

  cfg <- yaml::read_yaml(project_yaml)
  data_cfg <- cfg$storage$data
  if (!identical(data_cfg$type, "local")) {
    cli::cli_abort(c(
      "Article 3 resume expects a local-backend project.",
      "i" = "Current backend is {.val {data_cfg$type}}. Use the matching resume script."
    ))
  }

  store <- datom::datom_store(
    governance = NULL,
    data       = datom::datom_store_local(path = data_cfg$root),
    github_pat = keyring::key_get("GITHUB_PAT"),
    data_repo_url = cfg$repos$data$remote_url
  )

  conn <- datom::datom_get_conn(path = dev_dir, store = store)

  # --- Verify dm has both month-1 and month-2 versions ----------------------
  dm_history <- tryCatch(
    datom::datom_history(conn, "dm"),
    error = function(e) NULL
  )

  needs_m1 <- is.null(dm_history) || nrow(dm_history) < 1L
  needs_m2 <- is.null(dm_history) || nrow(dm_history) < 2L

  if (needs_m1) {
    cli::cli_alert_warning("Writing Article 1 month-1 DM extract...")
    dm_m1 <- datom::datom_example_data("dm", cutoff_date = "2026-01-28")
    datom::datom_write(
      conn,
      data    = dm_m1,
      name    = "dm",
      message = "Initial DM extract through 2026-01-28"
    )
  }

  if (needs_m2) {
    cli::cli_alert_warning("Writing Article 2 month-2 DM extract...")
    dm_m2 <- datom::datom_example_data("dm", cutoff_date = "2026-02-28")
    datom::datom_write(
      conn,
      data    = dm_m2,
      name    = "dm",
      message = "DM extract through 2026-02-28"
    )
  }

  if (!needs_m1 && !needs_m2) {
    cli::cli_alert_success("Article 2 state intact: {.val dm} has 2 versions.")
  }

  invisible(list(
    conn      = conn,
    dev_dir = as.character(dev_dir)
  ))
})
