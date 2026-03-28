# --- tbit_conn S3 class -------------------------------------------------------

#' Create a tbit Connection Object
#'
#' Internal constructor for the `tbit_conn` S3 class. Two modes:
#' - **Developer**: has `path` to local repo + git access
#' - **Reader**: S3-only access, no local repo
#'
#' @param project_name Project name string.
#' @param bucket S3 bucket name.
#' @param prefix S3 prefix (can be NULL).
#' @param region AWS region string.
#' @param s3_client A `paws.storage` S3 client.
#' @param path Local repo path (NULL for readers).
#' @param role One of `"developer"` or `"reader"`.
#' @param endpoint Optional S3 endpoint URL (e.g., for S3 access points). NULL for default.
#'
#' @return A `tbit_conn` object.
#' @keywords internal
new_tbit_conn <- function(project_name,
                          bucket,
                          prefix = NULL,
                          region = "us-east-1",
                          s3_client,
                          path = NULL,
                          role = c("reader", "developer"),
                          endpoint = NULL) {
  role <- match.arg(role)

  if (!is.character(project_name) || length(project_name) != 1L ||
      is.na(project_name) || !nzchar(project_name)) {
    cli::cli_abort("{.arg project_name} must be a single non-empty string.")
  }

  if (!is.character(bucket) || length(bucket) != 1L ||
      is.na(bucket) || !nzchar(bucket)) {
    cli::cli_abort("{.arg bucket} must be a single non-empty string.")
  }

  if (!is.null(prefix)) {
    if (!is.character(prefix) || length(prefix) != 1L || is.na(prefix)) {
      cli::cli_abort("{.arg prefix} must be a single string or NULL.")
    }
  }

  if (!is.character(region) || length(region) != 1L ||
      is.na(region) || !nzchar(region)) {
    cli::cli_abort("{.arg region} must be a single non-empty string.")
  }

  if (!is.null(path)) {
    if (!is.character(path) || length(path) != 1L || is.na(path)) {
      cli::cli_abort("{.arg path} must be a single string or NULL.")
    }
  }

  if (role == "developer" && is.null(path)) {
    cli::cli_abort("Developer connections require a {.arg path} to the local repo.")
  }

  structure(
    list(
      project_name = project_name,
      bucket = bucket,
      prefix = prefix,
      region = region,
      s3_client = s3_client,
      path = path,
      role = role,
      endpoint = endpoint
    ),
    class = "tbit_conn"
  )
}


#' Check if Object is a tbit Connection
#'
#' @param x Object to test.
#' @return TRUE or FALSE.
#' @keywords internal
is_tbit_conn <- function(x) {
  inherits(x, "tbit_conn")
}


#' Print a tbit Connection
#'
#' Displays a clean summary without exposing credentials or the S3 client.
#'
#' @param x A `tbit_conn` object.
#' @param ... Ignored.
#' @return Invisible `x`.
#' @export
print.tbit_conn <- function(x, ...) {
  cli::cli_h3("tbit connection")
  cli::cli_ul()
  cli::cli_li("Project: {.val {x$project_name}}")
  cli::cli_li("Role: {.val {x$role}}")
  cli::cli_li("Bucket: {.val {x$bucket}}")

  if (!is.null(x$prefix)) {
    cli::cli_li("Prefix: {.val {x$prefix}}")
  }

  cli::cli_li("Region: {.val {x$region}}")

  if (!is.null(x$endpoint)) {
    cli::cli_li("Endpoint: {.val {x$endpoint}}")
  }

  if (!is.null(x$path)) {
    cli::cli_li("Path: {.path {x$path}}")
  }

  cli::cli_end()
  invisible(x)
}


# --- Exported connection functions --------------------------------------------

#' Initialize a tbit Repository
#'
#' One-time setup for data developers. Creates folder structure, initializes
#' git with remote, sets up renv, and creates configuration files.
#'
#' @param path Path to the project folder. Defaults to current directory.
#' @param project_name Project name, used to auto-generate credential env var
#'   names (`TBIT_{PROJECT_NAME}_*`).
#' @param remote_url GitHub remote URL.
#' @param bucket S3 bucket name.
#' @param prefix Optional prefix for bucket organization.
#' @param region AWS region. If NULL, uses AWS_DEFAULT_REGION.
#' @param max_file_size_gb Maximum file size limit in GB. Default 1000 (1TB).
#' @param git_ignore Character vector of patterns to add to .gitignore.
#'
#' @return Invisible TRUE on success.
#' @export
tbit_init_repo <- function(path = ".",
                           project_name,
                           remote_url,
                           bucket,
                           prefix = NULL,
                           region = NULL,
                           max_file_size_gb = 1000,
                           git_ignore = c(
                             ".Rprofile", ".Renviron", ".Rhistory",
                             ".Rapp.history", ".Rproj.user/",
                             ".DS_Store", "*.csv", "*.tsv",
                             "*.rds", "*.txt", "*.parquet",
                             "*.sas7bdat", ".RData", ".RDataTmp",
                             "*.html", "*.png", "*.pdf",
                             ".vscode/", "rsconnect/"
                           )) {
  .tbit_check_git2r()

  # --- Input validation -------------------------------------------------------
  .tbit_validate_name(project_name)

  if (!is.character(remote_url) || length(remote_url) != 1L ||
      is.na(remote_url) || !nzchar(remote_url)) {
    cli::cli_abort("{.arg remote_url} must be a single non-empty string.")
  }

  if (!is.character(bucket) || length(bucket) != 1L ||
      is.na(bucket) || !nzchar(bucket)) {
    cli::cli_abort("{.arg bucket} must be a single non-empty string.")
  }

  if (!is.null(prefix)) {
    if (!is.character(prefix) || length(prefix) != 1L || is.na(prefix)) {
      cli::cli_abort("{.arg prefix} must be a single string or NULL.")
    }
  }

  if (!is.numeric(max_file_size_gb) || length(max_file_size_gb) != 1L ||
      is.na(max_file_size_gb) || max_file_size_gb <= 0) {
    cli::cli_abort("{.arg max_file_size_gb} must be a positive number.")
  }

  region <- region %||% Sys.getenv("AWS_DEFAULT_REGION", unset = "us-east-1")

  # --- Credential validation (developer role required) ------------------------
  .tbit_check_credentials(project_name, role = "developer")

  # --- Path setup -------------------------------------------------------------
  path <- fs::path_abs(path)

  if (fs::file_exists(fs::path(path, ".tbit", "project.yaml"))) {
    cli::cli_abort(c(
      "A tbit repository already exists at {.path {path}}.",
      "i" = "Delete {.path {fs::path(path, '.tbit')}} to re-initialize."
    ))
  }

  # --- Create directory structure ---------------------------------------------
  # Track what we create so we can clean up on failure (but never delete
  # pre-existing content).
  tbit_dir   <- fs::path(path, ".tbit")
  input_dir  <- fs::path(path, "input_files")
  gitignore  <- fs::path(path, ".gitignore")
  readme_file <- fs::path(path, "README.md")
  git_dir    <- fs::path(path, ".git")

  path_existed   <- fs::dir_exists(path)
  tbit_existed   <- fs::dir_exists(tbit_dir)
  input_existed  <- fs::dir_exists(input_dir)
  gi_existed     <- fs::file_exists(gitignore)
  readme_existed <- fs::file_exists(readme_file)
  git_existed    <- fs::dir_exists(git_dir)

  .safe_delete <- function(p, is_dir = TRUE) {
    tryCatch(
      if (is_dir) fs::dir_delete(p) else fs::file_delete(p),
      error = function(e) NULL
    )
  }

  .init_success <- FALSE
  on.exit({
    if (!.init_success) {
      if (!tbit_existed  && fs::dir_exists(tbit_dir))   .safe_delete(tbit_dir)
      if (!input_existed && fs::dir_exists(input_dir))   .safe_delete(input_dir)
      if (!gi_existed    && fs::file_exists(gitignore))  .safe_delete(gitignore, is_dir = FALSE)
      if (!readme_existed && fs::file_exists(readme_file)) .safe_delete(readme_file, is_dir = FALSE)
      if (!git_existed   && fs::dir_exists(git_dir))     .safe_delete(git_dir)
      # Remove the path directory itself if we created it and it's now empty
      if (!path_existed && fs::dir_exists(path) &&
          length(fs::dir_ls(path, all = TRUE)) == 0L) {
        .safe_delete(path)
      }
    }
  }, add = TRUE)

  fs::dir_create(tbit_dir)
  fs::dir_create(input_dir)

  # --- Create project.yaml ---------------------------------------------------
  cred_names <- .tbit_derive_cred_names(project_name)

  project_config <- list(
    project_name = project_name,
    project_description = "",
    created_at = format(Sys.Date(), "%Y-%m-%d"),
    tbit_version = as.character(utils::packageVersion("tbit")),
    storage = list(
      type = "s3",
      bucket = bucket,
      prefix = prefix,
      region = region,
      max_file_size_gb = max_file_size_gb,
      credentials = list(
        access_key_env = cred_names[["access_key_env"]],
        secret_key_env = cred_names[["secret_key_env"]]
      )
    ),
    sync = list(
      continue_on_error = TRUE,
      parallel_uploads = 4L
    ),
    renv = FALSE
  )

  yaml::write_yaml(project_config, fs::path(path, ".tbit", "project.yaml"))

  # --- Create routing.json ----------------------------------------------------
  routing <- list(
    methods = list(
      r = list(default = "tbit::tbit_read"),
      python = list(default = "tbit.read")
    )
  )

  jsonlite::write_json(routing, fs::path(path, ".tbit", "routing.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  # --- Create manifest.json ---------------------------------------------------
  manifest <- list(
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    tables = structure(list(), names = character(0)),
    summary = list(
      total_tables = 0L,
      total_size_bytes = 0L,
      total_versions = 0L
    )
  )

  jsonlite::write_json(manifest, fs::path(path, ".tbit", "manifest.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  # --- Create .gitignore ------------------------------------------------------
  # Always include input_files/ to keep data out of git
  ignore_lines <- unique(c(git_ignore, "input_files/"))
  writeLines(ignore_lines, fs::path(path, ".gitignore"))

  # --- Generate README.md -----------------------------------------------------
  readme_content <- .tbit_render_readme(
    project_name = project_name,
    bucket       = bucket,
    prefix       = prefix,
    region       = region,
    remote_url   = remote_url,
    cred_names   = cred_names
  )

  writeLines(readme_content, fs::path(path, "README.md"))

  # --- Git init, remote, commit, push -----------------------------------------
  repo <- git2r::init(path)

  # Configure author from global git config or fallback
  git_cfg <- git2r::config()$global
  author_name <- git_cfg$user.name %||% "tbit"
  author_email <- git_cfg$user.email %||% "tbit@noreply"

  # Set local config so default_signature works in fresh repos
  git2r::config(repo, user.name = author_name, user.email = author_email)

  git2r::remote_add(repo, name = "origin", url = remote_url)

  # Stage all created files
  git2r::add(repo, c(
    ".tbit/project.yaml",
    ".tbit/routing.json",
    ".tbit/manifest.json",
    ".gitignore",
    "README.md"
  ))

  git2r::commit(
    repo,
    message = "Initialize tbit repository",
    author = git2r::default_signature(repo)
  )

  # Push initial commit
  .tbit_git_push(path)

  # Push repo-level files to S3
  tryCatch({
    s3_client <- .tbit_s3_client(cred_names, region = region)
    init_conn <- new_tbit_conn(
      project_name, bucket, prefix, region,
      s3_client, path, "developer"
    )
    .tbit_s3_write_json(init_conn, ".metadata/routing.json", routing)
    .tbit_s3_write_json(init_conn, ".metadata/manifest.json", manifest)
  }, error = function(e) {
    cli::cli_alert_warning(
      "Git push succeeded but S3 upload failed: {conditionMessage(e)}"
    )
    cli::cli_alert_info("Run {.fn tbit_sync_routing} to fix.")
  })

  .init_success <- TRUE

  cli::cli_alert_success(
    "Initialized tbit repository {.val {project_name}} at {.path {path}}"
  )

  invisible(TRUE)
}


#' Get a tbit Connection
#'
#' Flexible connection for both developers and readers. Developers provide a
#' path to read from `.tbit/project.yaml`. Readers provide bucket, prefix, and
#' project_name directly.
#'
#' @param path Path to tbit repository. If provided, reads config from
#'   `.tbit/project.yaml`.
#' @param bucket S3 bucket name. Required for readers without local repo.
#' @param prefix Optional S3 prefix.
#' @param project_name Project name for credential lookup. Required for readers.
#' @param endpoint Optional S3 endpoint URL (e.g., for S3 access points). NULL for default.
#'
#' @return A `tbit_conn` object.
#' @export
tbit_get_conn <- function(path = NULL,
                          bucket = NULL,
                          prefix = NULL,
                          project_name = NULL,
                          endpoint = NULL) {

  has_path <- !is.null(path)
  has_direct <- !is.null(bucket) || !is.null(project_name)

  if (!has_path && !has_direct) {
    cli::cli_abort(c(
      "Must provide either {.arg path} or {.arg bucket} + {.arg project_name}.",
      "i" = "Developers: {.code tbit_get_conn(path = \"my_project\")}",
      "i" = "Readers: {.code tbit_get_conn(bucket = \"...\", project_name = \"...\")}"
    ))
  }

  if (has_path && has_direct) {
    cli::cli_abort(
      "Provide either {.arg path} or {.arg bucket}/{.arg project_name}, not both."
    )
  }

  if (has_path) {
    .tbit_get_conn_developer(path, endpoint = endpoint)
  } else {
    .tbit_get_conn_reader(bucket, prefix, project_name, endpoint = endpoint)
  }
}


# --- Internal connection builders ---------------------------------------------

#' Build Connection from Local Repo (Developer Path)
#'
#' Reads `.tbit/project.yaml` and constructs a connection.
#' Role is auto-detected: developer if GITHUB_PAT is set, reader otherwise.
#'
#' @param path Path to tbit repository.
#' @param endpoint Optional S3 endpoint URL.
#' @return A `tbit_conn` object.
#' @keywords internal
.tbit_get_conn_developer <- function(path, endpoint = NULL) {
  path <- fs::path_abs(path)

  yaml_path <- fs::path(path, ".tbit", "project.yaml")
  if (!fs::file_exists(yaml_path)) {
    cli::cli_abort(c(
      "No tbit config found at {.path {yaml_path}}.",
      "i" = "Run {.code tbit_init_repo()} to initialize, or check your path."
    ))
  }

  cfg <- yaml::read_yaml(yaml_path)

  project_name <- cfg$project_name
  if (is.null(project_name) || !nzchar(project_name)) {
    cli::cli_abort("Invalid {.file project.yaml}: missing {.field project_name}.")
  }

  storage <- cfg$storage
  if (is.null(storage)) {
    cli::cli_abort("Invalid {.file project.yaml}: missing {.field storage} section.")
  }

  bucket <- storage$bucket
  if (is.null(bucket) || !nzchar(bucket)) {
    cli::cli_abort("Invalid {.file project.yaml}: missing {.field storage.bucket}.")
  }

  prefix <- storage$prefix  # can be NULL
  region <- storage$region %||% Sys.getenv("AWS_DEFAULT_REGION", unset = "us-east-1")

  # Auto-detect role
  role <- if (nzchar(Sys.getenv("GITHUB_PAT", unset = ""))) "developer" else "reader"

  # Validate credentials for the detected role
  cred_names <- .tbit_check_credentials(project_name, role = role)

  # Create S3 client
  s3_client <- .tbit_s3_client(cred_names, region = region, endpoint = endpoint)

  new_tbit_conn(
    project_name = project_name,
    bucket = bucket,
    prefix = prefix,
    region = region,
    s3_client = s3_client,
    path = if (role == "developer") as.character(path) else NULL,
    role = role,
    endpoint = endpoint
  )
}


#' Build Connection from Direct Parameters (Reader Path)
#'
#' Constructs a connection from bucket, prefix, and project_name.
#' Role is auto-detected: developer if GITHUB_PAT is set, reader otherwise.
#' Developer role requires a local repo path, so this path only produces
#' reader connections.
#'
#' @param bucket S3 bucket name.
#' @param prefix Optional S3 prefix.
#' @param project_name Project name string.
#' @param endpoint Optional S3 endpoint URL.
#' @return A `tbit_conn` object.
#' @keywords internal
.tbit_get_conn_reader <- function(bucket, prefix, project_name, endpoint = NULL) {
  if (is.null(bucket) || !nzchar(bucket)) {
    cli::cli_abort("{.arg bucket} is required for reader connections.")
  }

  if (is.null(project_name) || !nzchar(project_name)) {
    cli::cli_abort("{.arg project_name} is required for reader connections.")
  }

  region <- Sys.getenv("AWS_DEFAULT_REGION", unset = "us-east-1")

  # Reader path is always reader role (no local repo = can't be developer)
  cred_names <- .tbit_check_credentials(project_name, role = "reader")

  s3_client <- .tbit_s3_client(cred_names, region = region, endpoint = endpoint)

  new_tbit_conn(
    project_name = project_name,
    bucket = bucket,
    prefix = prefix,
    region = region,
    s3_client = s3_client,
    path = NULL,
    role = "reader",
    endpoint = endpoint
  )
}
