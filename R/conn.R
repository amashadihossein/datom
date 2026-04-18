# --- datom_conn S3 class -------------------------------------------------------

#' Create a datom Connection Object
#'
#' Internal constructor for the `datom_conn` S3 class. Two modes:
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
#' @return A `datom_conn` object.
#' @keywords internal
new_datom_conn <- function(project_name,
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
    class = "datom_conn"
  )
}


#' Check if Object is a datom Connection
#'
#' @param x Object to test.
#' @return TRUE or FALSE.
#' @keywords internal
is_datom_conn <- function(x) {
  inherits(x, "datom_conn")
}


#' Print a datom Connection
#'
#' Displays a clean summary without exposing credentials or the S3 client.
#'
#' @param x A `datom_conn` object.
#' @param ... Ignored.
#' @return Invisible `x`.
#' @export
print.datom_conn <- function(x, ...) {
  cli::cli_h3("datom connection")
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

#' Initialize a datom Repository
#'
#' One-time setup for data developers. Creates folder structure, initializes
#' git with remote, sets up configuration files, and pushes to S3.
#'
#' @param path Path to the project folder. Defaults to current directory.
#' @param project_name Project name, used for S3 namespace and git repo.
#' @param store A `datom_store` object (from `datom_store()`). Must have role
#'   `"developer"` (i.e., `github_pat` provided).
#' @param create_repo If `TRUE`, create a GitHub repo via API. Mutually
#'   exclusive with providing `remote_url` on the store.
#' @param max_file_size_gb Maximum file size limit in GB. Default 1000 (1TB).
#' @param git_ignore Character vector of patterns to add to .gitignore.
#' @param .force If `TRUE`, skip the S3 namespace safety check. Use only for
#'   intentional takeover of an existing S3 namespace. Default `FALSE`.
#'
#' @return Invisible TRUE on success.
#' @export
datom_init_repo <- function(path = ".",
                           project_name,
                           store,
                           create_repo = FALSE,
                           max_file_size_gb = 1000,
                           git_ignore = c(
                             ".Rprofile", ".Renviron", ".Rhistory",
                             ".Rapp.history", ".Rproj.user/",
                             ".DS_Store", "*.csv", "*.tsv",
                             "*.rds", "*.txt", "*.parquet",
                             "*.sas7bdat", ".RData", ".RDataTmp",
                             "*.html", "*.png", "*.pdf",
                             ".vscode/", "rsconnect/"
                           ),
                           .force = FALSE) {
  .datom_check_git2r()

  # --- Input validation -------------------------------------------------------
  .datom_validate_name(project_name)

  if (!is_datom_store(store)) {
    cli::cli_abort("{.arg store} must be a {.cls datom_store} object.")
  }

  if (store$role != "developer") {
    cli::cli_abort(c(
      "{.fn datom_init_repo} requires a developer store.",
      "i" = "Provide {.arg github_pat} when creating the store."
    ))
  }

  if (!is.numeric(max_file_size_gb) || length(max_file_size_gb) != 1L ||
      is.na(max_file_size_gb) || max_file_size_gb <= 0) {
    cli::cli_abort("{.arg max_file_size_gb} must be a positive number.")
  }

  # --- Resolve remote_url -----------------------------------------------------
  remote_url <- store$remote_url

  if (isTRUE(create_repo) && !is.null(remote_url)) {
    cli::cli_abort(c(
      "{.arg create_repo} and {.arg remote_url} are mutually exclusive.",
      "i" = "Either set {.code create_repo = TRUE} or provide {.arg remote_url} on the store, not both."
    ))
  }

  if (isTRUE(create_repo)) {
    remote_url <- .datom_create_github_repo(
      repo_name = project_name,
      pat = store$github_pat,
      org = store$github_org
    )
  }

  if (is.null(remote_url)) {
    cli::cli_abort(c(
      "No remote URL available.",
      "i" = "Either provide {.arg remote_url} on the store or set {.code create_repo = TRUE}."
    ))
  }

  # --- Install env var bridge (temporary) -------------------------------------
  .datom_install_store(store, project_name)

  # --- Credential validation (developer role required) ------------------------
  cred_names <- .datom_check_credentials(project_name, role = "developer")

  # --- S3 namespace safety check ----------------------------------------------
  # Use data component for S3 operations (where manifest lives)
  bucket <- store$data$bucket
  prefix <- store$data$prefix
  region <- store$data$region

  if (!isTRUE(.force)) {
    tryCatch({
      s3_check_client <- .datom_s3_client(cred_names, region = region)
      check_conn <- new_datom_conn(
        project_name, bucket, prefix, region,
        s3_check_client, NULL, "reader"
      )
      .datom_check_s3_namespace_free(check_conn)
    }, error = function(e) {
      if (grepl("already occupied", conditionMessage(e))) {
        stop(e)
      }
      cli::cli_alert_warning(
        "Could not verify S3 namespace is free: {conditionMessage(e)}"
      )
    })
  }

  # --- Path setup -------------------------------------------------------------
  path <- fs::path_abs(path)

  if (fs::file_exists(fs::path(path, ".datom", "project.yaml"))) {
    cli::cli_abort(c(
      "A datom repository already exists at {.path {path}}.",
      "i" = "Delete {.path {fs::path(path, '.datom')}} to re-initialize."
    ))
  }

  # --- Create directory structure ---------------------------------------------
  datom_dir   <- fs::path(path, ".datom")
  input_dir  <- fs::path(path, "input_files")
  gitignore  <- fs::path(path, ".gitignore")
  readme_file <- fs::path(path, "README.md")
  git_dir    <- fs::path(path, ".git")

  path_existed   <- fs::dir_exists(path)
  datom_existed   <- fs::dir_exists(datom_dir)
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
      if (!datom_existed  && fs::dir_exists(datom_dir))   .safe_delete(datom_dir)
      if (!input_existed && fs::dir_exists(input_dir))   .safe_delete(input_dir)
      if (!gi_existed    && fs::file_exists(gitignore))  .safe_delete(gitignore, is_dir = FALSE)
      if (!readme_existed && fs::file_exists(readme_file)) .safe_delete(readme_file, is_dir = FALSE)
      if (!git_existed   && fs::dir_exists(git_dir))     .safe_delete(git_dir)
      if (!path_existed && fs::dir_exists(path) &&
          length(fs::dir_ls(path, all = TRUE)) == 0L) {
        .safe_delete(path)
      }
    }
  }, add = TRUE)

  fs::dir_create(datom_dir)
  fs::dir_create(input_dir)

  # --- Create project.yaml (two-component structure) --------------------------

  project_config <- list(
    project_name = project_name,
    project_description = "",
    created_at = format(Sys.Date(), "%Y-%m-%d"),
    datom_version = as.character(utils::packageVersion("datom")),
    storage = list(
      governance = list(
        type = "s3",
        bucket = store$governance$bucket,
        prefix = store$governance$prefix,
        region = store$governance$region
      ),
      data = list(
        type = "s3",
        bucket = store$data$bucket,
        prefix = store$data$prefix,
        region = store$data$region
      ),
      max_file_size_gb = max_file_size_gb
    ),
    git = list(
      remote_url = remote_url
    ),
    sync = list(
      continue_on_error = TRUE,
      parallel_uploads = 4L
    ),
    renv = FALSE
  )

  yaml::write_yaml(project_config, fs::path(path, ".datom", "project.yaml"))

  # --- Create routing.json ----------------------------------------------------
  routing <- list(
    methods = list(
      r = list(default = "datom::datom_read"),
      python = list(default = "datom.read")
    )
  )

  jsonlite::write_json(routing, fs::path(path, ".datom", "routing.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  # --- Create manifest.json ---------------------------------------------------
  manifest <- list(
    project_name = project_name,
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
    tables = structure(list(), names = character(0)),
    summary = list(
      total_tables = 0L,
      total_size_bytes = 0L,
      total_versions = 0L
    )
  )

  jsonlite::write_json(manifest, fs::path(path, ".datom", "manifest.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  # --- Create .gitignore ------------------------------------------------------
  # Always include input_files/ to keep data out of git
  ignore_lines <- unique(c(git_ignore, "input_files/"))
  writeLines(ignore_lines, fs::path(path, ".gitignore"))

  # --- Generate README.md -----------------------------------------------------
  readme_content <- .datom_render_readme(
    project_name = project_name,
    bucket       = store$data$bucket,
    prefix       = store$data$prefix,
    region       = store$data$region,
    remote_url   = remote_url,
    cred_names   = cred_names
  )

  writeLines(readme_content, fs::path(path, "README.md"))

  # --- Git init, remote, commit, push -----------------------------------------
  repo <- git2r::init(path)

  # Configure author from global git config or fallback
  git_cfg <- git2r::config()$global
  author_name <- git_cfg$user.name %||% "datom"
  author_email <- git_cfg$user.email %||% "datom@noreply"

  # Set local config so default_signature works in fresh repos
  git2r::config(repo, user.name = author_name, user.email = author_email)

  git2r::remote_add(repo, name = "origin", url = remote_url)

  # Stage all created files
  git2r::add(repo, c(
    ".datom/project.yaml",
    ".datom/routing.json",
    ".datom/manifest.json",
    ".gitignore",
    "README.md"
  ))

  git2r::commit(
    repo,
    message = "Initialize datom repository",
    author = git2r::default_signature(repo)
  )

  # Push initial commit
  .datom_git_push(path)

  # Push repo-level files to S3
  tryCatch({
    s3_client <- .datom_s3_client(cred_names, region = region)
    init_conn <- new_datom_conn(
      project_name, bucket, prefix, region,
      s3_client, path, "developer"
    )
    .datom_s3_write_json(init_conn, ".metadata/routing.json", routing)
    .datom_s3_write_json(init_conn, ".metadata/manifest.json", manifest)
  }, error = function(e) {
    cli::cli_alert_warning(
      "Git push succeeded but S3 upload failed: {conditionMessage(e)}"
    )
    cli::cli_alert_info("Run {.fn datom_sync_routing} to fix.")
  })

  .init_success <- TRUE

  cli::cli_alert_success(
    "Initialized datom repository {.val {project_name}} at {.path {path}}"
  )

  invisible(TRUE)
}


#' Clone a datom Repository
#'
#' Clones a remote datom repository and returns a connection. This is the
#' recommended way for teammates to join an existing datom project — it wraps
#' `git2r::clone()` and immediately returns a ready-to-use `datom_conn`.
#'
#' @param path Local path to clone into.
#' @param store A `datom_store` object (from `datom_store()`). Must have
#'   `remote_url` set and role `"developer"` (i.e., `github_pat` provided).
#' @param ... Additional arguments passed to [git2r::clone()].
#'
#' @return A `datom_conn` object (developer role).
#'
#' @examples
#' \dontrun{
#' conn <- datom_clone(
#'   path = "study_001_data",
#'   store = my_store
#' )
#' datom_pull(conn)
#' }
#' @export
datom_clone <- function(path, store, ...) {
  .datom_check_git2r()

  if (!is_datom_store(store)) {
    cli::cli_abort("{.arg store} must be a {.cls datom_store} object.")
  }

  if (store$role != "developer") {
    cli::cli_abort(c(
      "{.fn datom_clone} requires a developer store.",
      "i" = "Provide {.arg github_pat} when creating the store."
    ))
  }

  remote_url <- store$remote_url
  if (is.null(remote_url) || !nzchar(remote_url)) {
    cli::cli_abort(c(
      "{.arg store} must have a {.field remote_url} for cloning.",
      "i" = "Provide {.arg remote_url} when creating the store."
    ))
  }

  if (!is.character(path) || length(path) != 1L ||
      is.na(path) || !nzchar(path)) {
    cli::cli_abort("{.arg path} must be a single non-empty string.")
  }

  path <- fs::path_abs(path)

  if (fs::dir_exists(path) && length(fs::dir_ls(path, all = TRUE)) > 0L) {
    cli::cli_abort(c(
      "Target directory {.path {path}} already exists and is not empty.",
      "i" = "Use an empty or non-existent directory."
    ))
  }

  # Clone with git credentials
  cred <- .datom_git_credentials(remote_url)

  tryCatch(
    git2r::clone(url = remote_url, local_path = path, credentials = cred, ...),
    error = function(e) {
      cli::cli_abort(c(
        "Failed to clone {.url {remote_url}}.",
        "x" = conditionMessage(e)
      ))
    }
  )

  # Verify this is actually a datom repo
  yaml_path <- fs::path(path, ".datom", "project.yaml")
  if (!fs::file_exists(yaml_path)) {
    cli::cli_abort(c(
      "Cloned repository is not a datom repository.",
      "i" = "No {.file .datom/project.yaml} found at {.path {path}}.",
      "i" = "Use {.fn datom_init_repo} to initialize a new datom project."
    ))
  }

  # Install store env vars so datom_get_conn can find credentials
  cfg <- yaml::read_yaml(yaml_path)
  .datom_install_store(store, cfg$project_name)

  conn <- datom_get_conn(path = path)

  cli::cli_alert_success(
    "Cloned {.val {conn$project_name}} to {.path {path}}"
  )

  conn
}


#' Get a datom Connection
#'
#' Flexible connection for both developers and readers. Developers provide a
#' path to read from `.datom/project.yaml`. Readers provide a store and
#' project_name directly.
#'
#' @param path Path to datom repository. If provided, reads config from
#'   `.datom/project.yaml`.
#' @param store A `datom_store` object. Required for readers without local repo.
#'   The data component provides bucket, prefix, region, and credentials.
#' @param project_name Project name for credential lookup. Required for readers.
#' @param endpoint Optional S3 endpoint URL (e.g., for S3 access points). NULL for default.
#'
#' @return A `datom_conn` object.
#' @export
datom_get_conn <- function(path = NULL,
                          store = NULL,
                          project_name = NULL,
                          endpoint = NULL) {

  has_path <- !is.null(path)
  has_store <- !is.null(store)

  if (!has_path && !has_store) {
    cli::cli_abort(c(
      "Must provide either {.arg path} or {.arg store} + {.arg project_name}.",
      "i" = "Developers: {.code datom_get_conn(path = \"my_project\")}",
      "i" = "Readers: {.code datom_get_conn(store = my_store, project_name = \"...\")}"
    ))
  }

  if (has_path && has_store) {
    cli::cli_abort(
      "Provide either {.arg path} or {.arg store}/{.arg project_name}, not both."
    )
  }

  if (has_path) {
    .datom_get_conn_developer(path, endpoint = endpoint)
  } else {
    .datom_get_conn_reader(store, project_name, endpoint = endpoint)
  }
}


# --- Internal connection builders ---------------------------------------------

#' Build Connection from Local Repo (Developer Path)
#'
#' Reads `.datom/project.yaml` and constructs a connection.
#' Role is auto-detected: developer if GITHUB_PAT is set, reader otherwise.
#'
#' @param path Path to datom repository.
#' @param endpoint Optional S3 endpoint URL.
#' @return A `datom_conn` object.
#' @keywords internal
.datom_get_conn_developer <- function(path, endpoint = NULL) {
  path <- fs::path_abs(path)

  yaml_path <- fs::path(path, ".datom", "project.yaml")
  if (!fs::file_exists(yaml_path)) {
    cli::cli_abort(c(
      "No datom config found at {.path {yaml_path}}.",
      "i" = "Run {.code datom_init_repo()} to initialize, or check your path."
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

  # Support two-component structure (storage.data.*) and legacy flat (storage.*)
  data_storage <- storage$data %||% storage

  bucket <- data_storage$bucket
  if (is.null(bucket) || !nzchar(bucket)) {
    cli::cli_abort("Invalid {.file project.yaml}: missing {.field storage.data.bucket}.")
  }

  prefix <- data_storage$prefix  # can be NULL
  region <- data_storage$region %||% Sys.getenv("AWS_DEFAULT_REGION", unset = "us-east-1")

  # Auto-detect role
  role <- if (nzchar(Sys.getenv("GITHUB_PAT", unset = ""))) "developer" else "reader"

  # Validate credentials for the detected role
  cred_names <- .datom_check_credentials(project_name, role = role)

  # Create S3 client
  s3_client <- .datom_s3_client(cred_names, region = region, endpoint = endpoint)

  new_datom_conn(
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


#' Build Connection from Store (Reader Path)
#'
#' Constructs a connection from a store object and project_name.
#' Uses the data component of the store for S3 configuration.
#' Always reader role (no local repo = can't be developer).
#'
#' @param store A `datom_store` object.
#' @param project_name Project name string.
#' @param endpoint Optional S3 endpoint URL.
#' @return A `datom_conn` object.
#' @keywords internal
.datom_get_conn_reader <- function(store, project_name, endpoint = NULL) {
  if (!is_datom_store(store)) {
    cli::cli_abort("{.arg store} must be a {.cls datom_store} object.")
  }

  if (is.null(project_name) || !nzchar(project_name)) {
    cli::cli_abort("{.arg project_name} is required for reader connections.")
  }

  # Install env var bridge so .datom_check_credentials finds them
  .datom_install_store(store, project_name)

  bucket <- store$data$bucket
  prefix <- store$data$prefix
  region <- store$data$region

  # Role from store (developer if github_pat provided, reader otherwise)
  role <- store$role

  cred_names <- .datom_check_credentials(project_name, role = role)

  s3_client <- .datom_s3_client(cred_names, region = region, endpoint = endpoint)

  new_datom_conn(
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
