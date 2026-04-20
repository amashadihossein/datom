# --- datom_conn S3 class -------------------------------------------------------

#' Create a datom Connection Object
#'
#' Internal constructor for the `datom_conn` S3 class. Two modes:
#' - **Developer**: has `path` to local repo + git access
#' - **Reader**: S3-only access, no local repo
#'
#' The primary fields (`root`, `prefix`, `region`, `client`) refer to
#' the **data store**. Governance store fields are prefixed with `gov_`.
#'
#' @param project_name Project name string.
#' @param root Storage root (S3 bucket name or local directory path).
#' @param prefix Storage prefix (can be NULL).
#' @param region AWS region string (data store). Ignored for local backend.
#' @param client A storage client (paws S3 client or NULL for local).
#' @param path Local repo path (NULL for readers).
#' @param role One of `"developer"` or `"reader"`.
#' @param endpoint Optional S3 endpoint URL (e.g., for S3 access points). NULL for default.
#' @param gov_root Governance storage root (can be NULL for legacy conns).
#' @param gov_prefix Governance prefix (can be NULL).
#' @param gov_region Governance region (can be NULL).
#' @param gov_client Governance storage client (can be NULL).
#'
#' @return A `datom_conn` object.
#' @keywords internal
new_datom_conn <- function(project_name,
                          root,
                          prefix = NULL,
                          region = "us-east-1",
                          client,
                          path = NULL,
                          role = c("reader", "developer"),
                          endpoint = NULL,
                          gov_root = NULL,
                          gov_prefix = NULL,
                          gov_region = NULL,
                          gov_client = NULL) {
  role <- match.arg(role)

  if (!is.character(project_name) || length(project_name) != 1L ||
      is.na(project_name) || !nzchar(project_name)) {
    cli::cli_abort("{.arg project_name} must be a single non-empty string.")
  }

  if (!is.character(root) || length(root) != 1L ||
      is.na(root) || !nzchar(root)) {
    cli::cli_abort("{.arg root} must be a single non-empty string.")
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
      backend = "s3",
      root = root,
      prefix = prefix,
      region = region,
      client = client,
      path = path,
      role = role,
      endpoint = endpoint,
      gov_root = gov_root,
      gov_prefix = gov_prefix,
      gov_region = gov_region,
      gov_client = gov_client
    ),
    class = "datom_conn"
  )
}


#' Create a Governance-Scoped Connection
#'
#' Returns a lightweight connection that routes S3 operations to the governance
#' store. The storage dispatch layer (`.datom_storage_write_json`, etc.)
#' read `conn$root`, `conn$prefix`, and `conn$client` — this swaps in the
#' governance equivalents so the helpers work transparently.
#'
#' @param conn A `datom_conn` object with governance fields populated.
#' @return A list with `root`, `prefix`, `client` pointing to the
#'   governance store.
#' @keywords internal
.datom_gov_conn <- function(conn) {
  structure(
    list(
      project_name = conn$project_name,
      backend      = conn$backend,
      root         = conn$gov_root,
      prefix       = conn$gov_prefix,
      region       = conn$gov_region,
      client    = conn$gov_client,
      path         = conn$path,
      role         = conn$role,
      endpoint     = conn$endpoint
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
  cli::cli_li("Data root: {.val {x$root}}")

  if (!is.null(x$prefix)) {
    cli::cli_li("Data prefix: {.val {x$prefix}}")
  }

  cli::cli_li("Data region: {.val {x$region}}")

  if (!is.null(x$gov_root)) {
    cli::cli_li("Gov root: {.val {x$gov_root}}")
    if (!is.null(x$gov_prefix)) {
      cli::cli_li("Gov prefix: {.val {x$gov_prefix}}")
    }
    if (!is.null(x$gov_region) && !identical(x$gov_region, x$region)) {
      cli::cli_li("Gov region: {.val {x$gov_region}}")
    }
  }

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
#' @param repo_name GitHub repo name when `create_repo = TRUE`. Defaults to
#'   `project_name`. Useful when the project name (e.g., `"STUDY_001"`) isn't
#'   a good GitHub repo name.
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
                           repo_name = project_name,
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
      repo_name = repo_name,
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

  # --- S3 namespace safety check ----------------------------------------------
  # Use data component for S3 operations (where manifest lives)
  bucket <- store$data$bucket
  prefix <- store$data$prefix
  region <- store$data$region

  if (!isTRUE(.force)) {
    tryCatch({
      s3_check_client <- .datom_s3_client(
        store$data$access_key, store$data$secret_key,
        region = region
      )
      check_conn <- new_datom_conn(
        project_name, bucket, prefix, region,
        s3_check_client, NULL, "reader"
      )
      .datom_check_namespace_free(check_conn)
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
        root = store$governance$bucket,
        prefix = store$governance$prefix,
        region = store$governance$region
      ),
      data = list(
        type = "s3",
        root = store$data$bucket,
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

  # --- Create dispatch.json ----------------------------------------------------
  dispatch <- list(
    methods = list(
      r = list(default = "datom::datom_read"),
      python = list(default = "datom.read")
    )
  )

  jsonlite::write_json(dispatch, fs::path(path, ".datom", "dispatch.json"),
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

  # --- Create ref.json --------------------------------------------------------
  ref <- .datom_create_ref(store$data)

  jsonlite::write_json(ref, fs::path(path, ".datom", "ref.json"),
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
    remote_url   = remote_url
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
    ".datom/dispatch.json",
    ".datom/manifest.json",
    ".datom/ref.json",
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

  # Push repo-level files to S3 (dispatch → governance, manifest → data)
  tryCatch({
    data_s3 <- .datom_s3_client(
      store$data$access_key, store$data$secret_key,
      region = region
    )
    data_conn <- new_datom_conn(
      project_name, bucket, prefix, region,
      data_s3, path, "developer"
    )
    gov_s3 <- .datom_s3_client(
      store$governance$access_key, store$governance$secret_key,
      region = store$governance$region
    )
    gov_conn <- new_datom_conn(
      project_name, bucket, prefix, region,
      data_s3, path, "developer",
      gov_root = store$governance$bucket,
      gov_prefix = store$governance$prefix,
      gov_region = store$governance$region,
      gov_client = gov_s3
    )
    .datom_storage_write_json(.datom_gov_conn(gov_conn), ".metadata/dispatch.json", dispatch)
    .datom_storage_write_json(.datom_gov_conn(gov_conn), ".metadata/ref.json", ref)
    .datom_storage_write_json(data_conn, ".metadata/manifest.json", manifest)
  }, error = function(e) {
    cli::cli_alert_warning(
      "Git push succeeded but S3 upload failed: {conditionMessage(e)}"
    )
    cli::cli_alert_info("Run {.fn datom_sync_dispatch} to fix.")
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

  conn <- datom_get_conn(path = path, store = store)

  cli::cli_alert_success(
    "Cloned {.val {conn$project_name}} to {.path {path}}"
  )

  conn
}


#' Get a datom Connection
#'
#' Flexible connection for both developers and readers.
#'
#' **Developer** (local repo + store): provide `path` and `store`. Reads
#' project identity from `.datom/project.yaml`; uses store for credentials and
#' S3 config. Cross-checks bucket/prefix between yaml and store.
#'
#' **Reader** (no local repo): provide `store` and `project_name`. Store
#' provides everything.
#'
#' @param path Path to datom repository. If provided, reads config from
#'   `.datom/project.yaml`.
#' @param store A `datom_store` object. Required for all connections.
#'   The data component provides bucket, prefix, region, and credentials.
#' @param project_name Project name. Required for readers (no local repo).
#'   Ignored when `path` is provided (read from yaml).
#' @param endpoint Optional S3 endpoint URL (e.g., for S3 access points). NULL for default.
#'
#' @return A `datom_conn` object.
#' @export
datom_get_conn <- function(path = NULL,
                          store = NULL,
                          project_name = NULL,
                          endpoint = NULL) {

  if (is.null(store)) {
    cli::cli_abort(c(
      "{.arg store} is required.",
      "i" = "Create one with {.code datom_store(governance = datom_store_s3(...), data = datom_store_s3(...))}."
    ))
  }

  if (!is_datom_store(store)) {
    cli::cli_abort("{.arg store} must be a {.cls datom_store} object.")
  }

  if (!is.null(path)) {
    .datom_get_conn_developer(path, store, endpoint = endpoint)
  } else {
    .datom_get_conn_reader(store, project_name, endpoint = endpoint)
  }
}


# --- Internal connection builders ---------------------------------------------

#' Build Connection from Local Repo + Store (Developer Path)
#'
#' Reads `.datom/project.yaml` for project identity and cross-checks against
#' the store's S3 config. Uses the store for credentials.
#'
#' @param path Path to datom repository.
#' @param store A `datom_store` object.
#' @param endpoint Optional S3 endpoint URL.
#' @return A `datom_conn` object.
#' @keywords internal
.datom_get_conn_developer <- function(path, store, endpoint = NULL) {
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

  # Use store for credentials and S3 config
  bucket <- store$data$bucket
  prefix <- store$data$prefix
  region <- store$data$region

  # Cross-check: yaml root must match store bucket (if yaml has storage config)
  storage <- cfg$storage
  if (!is.null(storage)) {
    data_storage <- storage$data %||% storage
    yaml_root <- data_storage$root
    if (!is.null(yaml_root) && !identical(yaml_root, bucket)) {
      cli::cli_abort(c(
        "Store/config mismatch: store data root is {.val {bucket}} but {.file project.yaml} says {.val {yaml_root}}.",
        "i" = "Ensure the store matches the project configuration."
      ))
    }
  }

  # Role from store
  role <- store$role

  # Create S3 client from store credentials
  client <- .datom_s3_client(
    store$data$access_key, store$data$secret_key,
    region = region, endpoint = endpoint,
    session_token = store$data$session_token
  )

  # Create governance S3 client
  gov_bucket <- store$governance$bucket
  gov_prefix <- store$governance$prefix
  gov_region <- store$governance$region
  gov_client <- .datom_s3_client(
    store$governance$access_key, store$governance$secret_key,
    region = gov_region, endpoint = endpoint,
    session_token = store$governance$session_token
  )

  new_datom_conn(
    project_name = project_name,
    root = bucket,
    prefix = prefix,
    region = region,
    client = client,
    path = if (role == "developer") as.character(path) else NULL,
    role = role,
    endpoint = endpoint,
    gov_root = gov_bucket,
    gov_prefix = gov_prefix,
    gov_region = gov_region,
    gov_client = gov_client
  )
}


#' Build Connection from Store (Reader Path)
#'
#' Constructs a connection from a store object and project_name.
#' Uses the data component of the store for S3 configuration.
#'
#' @param store A `datom_store` object.
#' @param project_name Project name string.
#' @param endpoint Optional S3 endpoint URL.
#' @return A `datom_conn` object.
#' @keywords internal
.datom_get_conn_reader <- function(store, project_name, endpoint = NULL) {
  if (is.null(project_name) || !nzchar(project_name)) {
    cli::cli_abort("{.arg project_name} is required for reader connections (no local repo).")
  }

  bucket <- store$data$bucket
  prefix <- store$data$prefix
  region <- store$data$region
  role <- store$role

  client <- .datom_s3_client(
    store$data$access_key, store$data$secret_key,
    region = region, endpoint = endpoint,
    session_token = store$data$session_token
  )

  # Create governance S3 client
  gov_bucket <- store$governance$bucket
  gov_prefix <- store$governance$prefix
  gov_region <- store$governance$region
  gov_client <- .datom_s3_client(
    store$governance$access_key, store$governance$secret_key,
    region = gov_region, endpoint = endpoint,
    session_token = store$governance$session_token
  )

  new_datom_conn(
    project_name = project_name,
    root = bucket,
    prefix = prefix,
    region = region,
    client = client,
    path = NULL,
    role = role,
    endpoint = endpoint,
    gov_root = gov_bucket,
    gov_prefix = gov_prefix,
    gov_region = gov_region,
    gov_client = gov_client
  )
}
