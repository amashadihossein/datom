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
# Returns invisible(list(conn, study_dir)).

local({
  study_dir <- Sys.getenv(
    "DATOM_VIGNETTE_DIR",
    fs::path(tempdir(), "study_001_data")
  )

  project_yaml <- fs::path(study_dir, ".datom", "project.yaml")
  if (!fs::file_exists(project_yaml)) {
    cli::cli_abort(c(
      "No prior vignette state found at {.path {study_dir}}.",
      "i" = "Run Articles 1--3 first, or set {.envvar DATOM_VIGNETTE_DIR}."
    ))
  }

  cli::cli_alert_info("Resuming from Article 3 state at {.path {study_dir}}.")

  conn <- datom::datom_get_conn(path = study_dir)

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
    study_dir = as.character(study_dir)
  ))
})
