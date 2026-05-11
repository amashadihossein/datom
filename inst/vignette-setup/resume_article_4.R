# inst/vignette-setup/resume_article_4.R
#
# Rebuild the end state of Article 3 ("A Folder of Extracts") so a reader can
# begin Article 4 ("Promoting to S3") with a working LOCAL-backend conn.
#
# Article 4 itself decommissions the local project, re-establishes on S3,
# and attaches governance via datom_attach_gov(). This script does NOT
# touch S3 and does NOT prepare any gov state -- it only ensures the
# local-era state is present.
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
      "i" = "Run Articles 1--3 first, or set {.envvar DATOM_VIGNETTE_DIR}."
    ))
  }

  cli::cli_alert_info("Resuming from Article 3 state at {.path {dev_dir}}.")

  cfg <- yaml::read_yaml(project_yaml)
  data_cfg <- cfg$storage$data
  if (!identical(data_cfg$type, "local")) {
    cli::cli_abort(c(
      "Article 4 resume expects a local-backend project (pre-promotion).",
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

  # --- Verify the four expected tables are present --------------------------
  tables_now <- tryCatch(
    datom::datom_list(conn),
    error = function(e) NULL
  )
  present <- if (is.null(tables_now)) character() else tables_now$name
  expected <- c("dm", "ex", "lb", "ae")

  missing <- setdiff(expected, present)
  if (length(missing) > 0L) {
    cli::cli_alert_warning(
      "Missing tables: {.val {missing}}. Writing month-3 extracts..."
    )
    cutoff <- "2026-03-28"
    for (nm in missing) {
      datom::datom_write(
        conn,
        data    = datom::datom_example_data(nm, cutoff_date = cutoff),
        name    = nm,
        message = paste0("Initial ", nm, " extract through ", cutoff)
      )
    }
  } else {
    cli::cli_alert_success(
      "Article 3 state intact: {.val {expected}} all present."
    )
  }

  invisible(list(
    conn      = conn,
    dev_dir = as.character(dev_dir)
  ))
})
