# inst/vignette-setup/resume_article_6.R
#
# Rebuild the original engineer's developer conn against the S3-backed
# STUDY_001 from Article 4. Article 6 simulates a second engineer joining;
# this script provides the original engineer's conn AND the store
# components needed to construct the second engineer's store inside the
# article.
#
# Continuity contract: requires Article 4 has run. Reads project.yaml from
# the engineer's data clone for backend metadata.
#
# Returns invisible(list(
#   conn, study_dir, gov_clone_path,
#   data_s3, gov_component,
#   data_repo_url, gov_repo_url
# )).

local({
  study_dir <- Sys.getenv(
    "DATOM_VIGNETTE_DIR",
    fs::path(tempdir(), "study_001_data")
  )
  gov_clone_path <- Sys.getenv(
    "DATOM_VIGNETTE_GOV_CLONE",
    fs::path(tempdir(), "study_001_gov_clone")
  )

  project_yaml <- fs::path(study_dir, ".datom", "project.yaml")
  if (!fs::file_exists(project_yaml)) {
    cli::cli_abort(c(
      "No Article 4 state found at {.path {study_dir}}.",
      "i" = "Run Article 4 first, or set {.envvar DATOM_VIGNETTE_DIR}."
    ))
  }

  cfg <- yaml::read_yaml(project_yaml)
  data_cfg <- cfg$storage$data
  if (!identical(data_cfg$type, "s3")) {
    cli::cli_abort(c(
      "Article 6 expects the project to be on S3 (Article 4 outcome).",
      "i" = "Current backend is {.val {data_cfg$type}}. Run Article 4 first."
    ))
  }

  required_creds <- c("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "GITHUB_PAT")
  missing_creds <- vapply(required_creds, function(k) {
    inherits(try(keyring::key_get(k), silent = TRUE), "try-error")
  }, logical(1L))
  if (any(missing_creds)) {
    cli::cli_abort(c(
      "Missing keyring credentials: {.val {required_creds[missing_creds]}}.",
      "i" = "Set them with {.code keyring::key_set(\"<NAME>\")} and re-run."
    ))
  }

  cli::cli_alert_info(
    "Resuming engineer conn for {.val {cfg$project_name}} on {.val {data_cfg$root}}."
  )

  region <- if (is.null(data_cfg$region) || !nzchar(data_cfg$region)) "us-east-1" else data_cfg$region

  data_s3 <- datom::datom_store_s3(
    bucket     = data_cfg$root,
    prefix     = data_cfg$prefix,
    region     = region,
    access_key = keyring::key_get("AWS_ACCESS_KEY_ID"),
    secret_key = keyring::key_get("AWS_SECRET_ACCESS_KEY")
  )

  gov_cfg <- cfg$storage$governance
  gov_component <- if (identical(gov_cfg$type, "local")) {
    datom::datom_store_local(path = gov_cfg$root)
  } else {
    gov_region <- if (is.null(gov_cfg$region) || !nzchar(gov_cfg$region)) "us-east-1" else gov_cfg$region
    datom::datom_store_s3(
      bucket     = gov_cfg$root,
      prefix     = gov_cfg$prefix,
      region     = gov_region,
      access_key = keyring::key_get("AWS_ACCESS_KEY_ID"),
      secret_key = keyring::key_get("AWS_SECRET_ACCESS_KEY")
    )
  }

  data_repo_url <- cfg$repos$data$remote_url
  gov_repo_url  <- cfg$repos$governance$remote_url

  store <- datom::datom_store(
    governance     = gov_component,
    data           = data_s3,
    github_pat     = keyring::key_get("GITHUB_PAT"),
    data_repo_url  = data_repo_url,
    gov_repo_url   = gov_repo_url,
    gov_local_path = gov_clone_path
  )

  conn <- datom::datom_get_conn(path = study_dir, store = store)

  invisible(list(
    conn           = conn,
    study_dir      = as.character(study_dir),
    gov_clone_path = as.character(gov_clone_path),
    data_s3        = data_s3,
    gov_component  = gov_component,
    data_repo_url  = data_repo_url,
    gov_repo_url   = gov_repo_url
  ))
})
