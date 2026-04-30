# inst/vignette-setup/resume_article_5.R
#
# Build a READER conn against the S3-backed STUDY_001 from Article 4. This
# script is run from the statistician's perspective: no local data clone,
# no GitHub PAT for the data repo, just S3 + gov-repo read access.
#
# Continuity contract: requires that Article 4 has already promoted the
# project to S3. Discovers bucket/prefix/region by reading the engineer's
# project.yaml from the data clone (a real-world handoff would communicate
# these values out-of-band; using the clone here keeps the vignette
# self-contained).
#
# Returns invisible(list(conn, study_dir, gov_clone_path, bucket, prefix, region)).

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
      "Article 5 expects the project to be on S3 (Article 4 outcome).",
      "i" = "Current backend in {.file project.yaml} is {.val {data_cfg$type}}.",
      "i" = "Run Article 4 first."
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
    "Building reader conn for {.val {cfg$project_name}} on bucket {.val {data_cfg$root}}."
  )

  # Reader's S3 store component
  region <- if (is.null(data_cfg$region) || !nzchar(data_cfg$region)) "us-east-1" else data_cfg$region

  data_s3 <- datom::datom_store_s3(
    bucket     = data_cfg$root,
    prefix     = data_cfg$prefix,
    region     = region,
    access_key = keyring::key_get("AWS_ACCESS_KEY_ID"),
    secret_key = keyring::key_get("AWS_SECRET_ACCESS_KEY")
  )

  # Reuse engineer's local gov store path for vignette continuity. A reader
  # on a different machine would either point to a shared gov store (S3) or
  # clone the gov repo themselves.
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

  reader_store <- datom::datom_store(
    governance     = gov_component,
    data           = data_s3,
    github_pat     = keyring::key_get("GITHUB_PAT"),
    gov_repo_url   = cfg$repos$governance$remote_url,
    gov_local_path = gov_clone_path
  )

  reader_conn <- datom::datom_get_conn(
    store        = reader_store,
    project_name = cfg$project_name
  )

  invisible(list(
    conn           = reader_conn,
    study_dir      = as.character(study_dir),
    gov_clone_path = as.character(gov_clone_path),
    bucket         = data_cfg$root,
    prefix         = data_cfg$prefix,
    region         = region
  ))
})
