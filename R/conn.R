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
#' @param gov_backend Governance storage backend (`"s3"` or `"local"`), set
#'   from the governance store component. NULL on solo (no-governance) conns.
#'   Independent of `backend` (the data backend): a project may keep data on
#'   one backend and governance on another.
#' @param gov_client Governance storage client (can be NULL).
#' @param gov_local_path Absolute path to the local gov clone (NULL for readers).
#' @param data_repo_url HTTPS URL of the data GitHub repository. Populated at
#'   conn-construction time from the git remote or store. NULL for readers or
#'   when not yet known.
#' @param github_pat GitHub personal access token held in memory only. Sourced
#'   from `store$github_pat` at conn-construction time. Never persisted to disk
#'   and never printed.
#' @param github_api_url GitHub API base URL. Sourced from
#'   `store$github_api_url` at conn-construction time. Defaults to
#'   `"https://api.github.com"` when not set.
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
                          gov_backend = NULL,
                          gov_client = NULL,
                          gov_local_path = NULL,
                          backend = "s3",
                          data_repo_url = NULL,
                          github_pat = NULL,
                          github_api_url = NULL) {
  role <- match.arg(role)
  backend <- match.arg(backend, c("s3", "local"))

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

  # Region required for S3, optional (NULL) for local
  if (backend == "s3") {
    if (!is.character(region) || length(region) != 1L ||
        is.na(region) || !nzchar(region)) {
      cli::cli_abort("{.arg region} must be a single non-empty string.")
    }
  }

  if (!is.null(path)) {
    if (!is.character(path) || length(path) != 1L || is.na(path)) {
      cli::cli_abort("{.arg path} must be a single string or NULL.")
    }
  }

  if (!is.null(gov_local_path)) {
    if (!is.character(gov_local_path) || length(gov_local_path) != 1L ||
        is.na(gov_local_path) || !nzchar(gov_local_path)) {
      cli::cli_abort("{.arg gov_local_path} must be a single non-empty string or NULL.")
    }
  }

  if (role == "developer" && is.null(path)) {
    cli::cli_abort("Developer connections require a {.arg path} to the local repo.")
  }

  structure(
    list(
      project_name  = project_name,
      backend       = backend,
      root          = root,
      prefix        = prefix,
      region        = region,
      client        = client,
      path          = path,
      role          = role,
      endpoint      = endpoint,
      gov_root      = gov_root,
      gov_prefix    = gov_prefix,
      gov_region    = gov_region,
      gov_backend   = gov_backend,
      gov_client    = gov_client,
      gov_local_path = gov_local_path,
      data_repo_url = data_repo_url,
      github_pat    = github_pat,
      github_api_url = github_api_url
    ),
    class = "datom_conn"
  )
}


#' Scope-Selecting Connection Accessor
#'
#' Returns the connection shaped for either the data or governance store.
#' The storage dispatch layer (`.datom_storage_*`) reads `conn$root`,
#' `conn$prefix`, and `conn$client`; this accessor swaps those fields when
#' callers need to operate on the governance store.
#'
#' Single source of truth for "which store am I talking to right now?" --
#' replaces ad-hoc `conn$gov_client` peeking and the prior `.datom_gov_conn()`
#' helper.
#'
#' @param conn A `datom_conn` object.
#' @param scope Either `"data"` (default; returns `conn` unchanged) or
#'   `"gov"` (returns a sub-conn with governance fields swapped in).
#' @return A `datom_conn` object scoped to the requested store.
#' @keywords internal
.datom_conn_for <- function(conn, scope = c("data", "gov")) {
  scope <- match.arg(scope)

  if (scope == "data") return(conn)

  # scope == "gov" -- gov-only callers are responsible for the user-facing
  # "no governance attached" error before reaching here. This accessor is a
  # pure shape transform. The gov sub-conn's backend comes from gov_backend
  # (the governance store's backend), which is independent of conn$backend
  # (the data backend) -- a project may keep data and gov on different backends.
  structure(
    list(
      project_name = conn$project_name,
      backend      = conn$gov_backend,
      root         = conn$gov_root,
      prefix       = conn$gov_prefix,
      region       = conn$gov_region,
      client       = conn$gov_client,
      path         = conn$path,
      role         = conn$role,
      endpoint     = conn$endpoint
    ),
    class = "datom_conn"
  )
}


#' Require Governance Attached on a Connection
#'
#' Guard helper used by gov-only commands (e.g. `datom_projects`) to fail with
#' a single uniform message when called on a no-governance connection.
#'
#' @param conn A `datom_conn` object.
#' @param what Character. The user-facing name of the calling function
#'   (e.g. `"datom_projects()"`), used in the error message.
#' @return Invisible `TRUE` when gov is attached. Aborts otherwise.
#' @keywords internal
.datom_require_gov <- function(conn, what) {
  if (!is.null(conn$gov_root)) return(invisible(TRUE))

  cli::cli_abort(c(
    "{what} requires governance, but this project has no governance attached.",
    "i" = "Use {.fn gov_attach} (from the datomanager package) to enable governance for this project."
  ))
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
  cli::cli_li("Backend: {.val {x$backend}}")
  cli::cli_li("Role: {.val {x$role}}")
  cli::cli_li("Data root: {.val {x$root}}")

  if (!is.null(x$prefix)) {
    cli::cli_li("Data prefix: {.val {x$prefix}}")
  }

  if (!is.null(x$region) && x$backend != "local") {
    cli::cli_li("Data region: {.val {x$region}}")
  }

  if (!is.null(x$gov_root)) {
    cli::cli_li("Gov root: {.val {x$gov_root}}")
    if (!is.null(x$gov_prefix)) {
      cli::cli_li("Gov prefix: {.val {x$gov_prefix}}")
    }
    if (!is.null(x$gov_region) && !identical(x$gov_region, x$region)) {
      cli::cli_li("Gov region: {.val {x$gov_region}}")
    }
  } else {
    cli::cli_li("Governance: not attached")
  }

  if (!is.null(x$endpoint)) {
    cli::cli_li("Endpoint: {.val {x$endpoint}}")
  }

  if (!is.null(x$path)) {
    cli::cli_li("Path: {.path {normalizePath(x$path, mustWork = FALSE)}}")
  }

  if (!is.null(x$data_repo_url)) {
    cli::cli_li("Data repo: {.url {x$data_repo_url}}")
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
#' Initializes the **data repository only**. The project is left as a solo
#' project: `project.yaml` is the location authority, no `governance.json` /
#' `dispatch.json` / `ref.json` is written, and `project.yaml` omits the
#' `storage.governance` and `repos.governance` blocks. A governance store
#' component on `store`, if present, is ignored here. Governance is attached
#' later via the governance layer (`gov_attach()`).
#'
#' @param path Path to the project folder. Defaults to current directory.
#' @param project_name Project name, used for S3 namespace and git repo.
#' @param store A `datom_store` object (from `datom_store()`). Must have role
#'   `"developer"` (i.e., `github_pat` provided).
#' @param create_repo If `TRUE`, create a GitHub repo via API. Mutually
#'   exclusive with providing `data_repo_url` on the store.
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

  # --- Resolve data_repo_url -------------------------------------------------
  remote_url <- store$data_repo_url

  if (isTRUE(create_repo) && !is.null(remote_url)) {
    cli::cli_abort(c(
      "{.arg create_repo} and {.arg data_repo_url} are mutually exclusive.",
      "i" = "Either set {.code create_repo = TRUE} or provide {.arg data_repo_url} on the store, not both."
    ))
  }

  if (isTRUE(create_repo)) {
    remote_url <- .datom_create_github_repo(
      repo_name = repo_name,
      pat = store$github_pat,
      org = store$github_org,
      api_url = store$github_api_url
    )
  }

  if (is.null(remote_url)) {
    cli::cli_abort(c(
      "No remote URL available.",
      "i" = "Either provide {.arg data_repo_url} on the store or set {.code create_repo = TRUE}."
    ))
  }

  # State flags + safe-delete helper used by the data-file rollback on.exit
  # below. datom_init_repo initializes the data repo only -- no gov clone is
  # created or touched here (governance attaches later via the governance layer).
  .git_pushed <- FALSE
  .init_success <- FALSE
  .safe_delete <- function(p, is_dir = TRUE) {
    tryCatch(
      if (is_dir) fs::dir_delete(p) else fs::file_delete(p),
      error = function(e) NULL
    )
  }

  # --- S3 namespace safety check for data store ------------------------------
  # Use data component for storage operations (where manifest lives)
  data_backend <- .datom_store_backend(store$data)
  data_root <- .datom_store_root(store$data)
  data_prefix <- store$data$prefix
  data_region <- .datom_store_region(store$data)

  if (data_backend == "s3" && !isTRUE(.force)) {
    tryCatch({
      s3_check_client <- .datom_s3_client(
        store$data$access_key, store$data$secret_key,
        region = data_region
      )
      check_conn <- new_datom_conn(
        project_name = project_name,
        root         = data_root,
        prefix       = data_prefix,
        region       = data_region,
        client       = s3_check_client,
        path         = NULL,
        role         = "reader"
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

  on.exit({
    if (!.init_success && !.git_pushed) {
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
  # When governance is absent (gov-on-demand: not yet attached), omit
  # storage.governance and repos.governance entirely. The resolver and
  # downstream readers detect a no-gov project by is.null(cfg$storage$governance).
  has_gov <- !is.null(store$governance)

  data_yaml <- list(
    type = data_backend,
    root = data_root,
    prefix = data_prefix
  )
  if (data_backend == "s3") data_yaml$region <- data_region

  storage_block <- list()
  storage_block$data <- data_yaml
  storage_block$max_file_size_gb <- max_file_size_gb

  repos_block <- list(data = list(remote_url = remote_url))

  project_config <- list(
    project_name = project_name,
    project_description = "",
    created_at = format(Sys.Date(), "%Y-%m-%d"),
    datom_version = as.character(utils::packageVersion("datom")),
    storage = storage_block,
    repos = repos_block,
    sync = list(
      continue_on_error = TRUE,
      parallel_uploads = 4L
    ),
    renv = FALSE
  )

  yaml::write_yaml(project_config, fs::path(path, ".datom", "project.yaml"))

  # --- Create manifest.json (data repo only) ----------------------------------
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
    backend      = data_backend,
    root         = data_root,
    prefix       = data_prefix,
    region       = data_region,
    remote_url   = remote_url,
    gov          = store$governance
  )

  writeLines(readme_content, fs::path(path, "README.md"))

  # --- Git init, remote, commit, push -----------------------------------------
  repo <- git2r::init(path)

  # Set local config so default_signature works even without global git config.
  .datom_git_ensure_local_identity(repo)

  git2r::remote_add(repo, name = "origin", url = remote_url)

  # Stage data-repo files only (dispatch.json and ref.json live in gov repo)
  staged_files <- c(
    ".datom/project.yaml",
    ".datom/manifest.json",
    ".gitignore",
    "README.md"
  )
  git2r::add(repo, staged_files)

  git2r::commit(
    repo,
    message = "Initialize datom repository",
    author = git2r::default_signature(repo)
  )

  # Push initial commit (remote is brand-new/empty -- skip pre-push pull)
  .datom_git_push(path, pat = store$github_pat, pull_first = FALSE)
  .git_pushed <- TRUE

  # From this point on, the data git remote has been advertised. Failures
  # below are reported but do NOT roll back local files (user has work to
  # recover) -- they abort with a clear recovery hint.

  data_conn <- .datom_build_init_conn(
    project_name, store$data, path, "developer", NULL,
    gov_store = NULL,
    gov_local_path = NULL,
    data_repo_url = remote_url,
    github_pat    = store$github_pat,
    github_api_url = store$github_api_url
  )

  # --- Mirror manifest to data storage ----------------------------------------
  # Manifest is part of the data-side contract -- readers need it to clone.
  # Failure aborts; user runs datom_sync_manifest after fixing cause.
  tryCatch({
    .datom_storage_write_json(data_conn, ".metadata/manifest.json", manifest)
  }, error = function(e) {
    cli::cli_abort(c(
      "Data repo pushed but manifest upload failed.",
      "x" = conditionMessage(e),
      "i" = "Local data clone is intact at {.path {path}}.",
      "i" = "After fixing the cause (e.g. credentials, connectivity), run {.fn datom_sync_manifest} to upload the manifest."
    ), call = NULL)
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
#' recommended way for teammates to join an existing datom project -- it wraps
#' `git2r::clone()` and immediately returns a ready-to-use `datom_conn`.
#'
#' When `store$gov_repo_url` is set the governance repo is also cloned (or
#' verified if it already exists locally). An existing clone with uncommitted
#' changes causes an error to avoid surprising state.
#'
#' @param path Local path to clone into.
#' @param store A `datom_store` object (from `datom_store()`). Must have
#'   `data_repo_url` set and role `"developer"` (i.e., `github_pat` provided).
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

  remote_url <- store$data_repo_url
  if (is.null(remote_url) || !nzchar(remote_url)) {
    cli::cli_abort(c(
      "{.arg store} must have a {.field data_repo_url} for cloning.",
      "i" = "Provide {.arg data_repo_url} when creating the store."
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

  # Clone with git credentials (PAT from store; no env-var fallback)
  cred <- .datom_git_credentials(remote_url, pat = store$github_pat)

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

  # --- Clone or verify gov repo when gov_repo_url is set ---------------------
  if (!is.null(store$gov_repo_url) && nzchar(store$gov_repo_url)) {
    gov_local_path <- .datom_resolve_or_default_gov_path(store, path)

    # Refuse if the existing gov clone has uncommitted changes
    if (.datom_gov_clone_exists(as.character(gov_local_path))) {
      gov_repo  <- git2r::repository(as.character(gov_local_path))
      gov_status <- git2r::status(gov_repo,
                                   staged   = TRUE,
                                   unstaged = TRUE,
                                   untracked = FALSE)
      if (length(unlist(gov_status)) > 0L) {
        cli::cli_abort(c(
          "Gov clone at {.path {gov_local_path}} has uncommitted changes.",
          "i" = "Commit or stash before cloning."
        ))
      }
    }

    .datom_gov_clone_init(store$gov_repo_url, as.character(gov_local_path))
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

#' Build a datom_conn from Store Components
#'
#' Backend-aware helper that creates the appropriate client (S3 client or NULL)
#' and assembles a `datom_conn`. Used by `datom_init_repo()`,
#' `.datom_get_conn_developer()`, and `.datom_get_conn_reader()`.
#'
#' @param project_name Project name string.
#' @param data_store A store component (datom_store_s3 or datom_store_local).
#' @param path Local repo path (NULL for readers).
#' @param role One of "developer" or "reader".
#' @param endpoint Optional S3 endpoint URL.
#' @param gov_store A store component for governance (can be NULL).
#' @return A `datom_conn` object.
#' @keywords internal
.datom_build_init_conn <- function(project_name, data_store, path, role,
                                   endpoint = NULL, gov_store = NULL,
                                   gov_local_path = NULL,
                                   data_repo_url = NULL,
                                   github_pat = NULL,
                                   github_api_url = NULL) {
  backend <- .datom_store_backend(data_store)
  data_root <- .datom_store_root(data_store)
  data_prefix <- data_store$prefix
  data_region <- .datom_store_region(data_store) %||% "us-east-1"

  # Create client based on backend
  if (backend == "s3") {
    client <- .datom_s3_client(
      data_store$access_key, data_store$secret_key,
      region = data_region, endpoint = endpoint,
      session_token = data_store$session_token
    )
  } else {
    client <- NULL
  }

  # Governance store
  gov_root <- NULL
  gov_prefix <- NULL
  gov_region <- NULL
  gov_backend <- NULL
  gov_client <- NULL

  if (!is.null(gov_store)) {
    gov_backend <- .datom_store_backend(gov_store)
    gov_root <- .datom_store_root(gov_store)
    gov_prefix <- gov_store$prefix
    gov_region <- .datom_store_region(gov_store)

    if (gov_backend == "s3") {
      gov_client <- .datom_s3_client(
        gov_store$access_key, gov_store$secret_key,
        region = gov_region %||% "us-east-1", endpoint = endpoint,
        session_token = gov_store$session_token
      )
    }
  }

  new_datom_conn(
    project_name  = project_name,
    root          = data_root,
    prefix        = data_prefix,
    region        = data_region,
    client        = client,
    path          = path,
    role          = role,
    endpoint      = endpoint,
    gov_root      = gov_root,
    gov_prefix    = gov_prefix,
    gov_region    = gov_region,
    gov_backend   = gov_backend,
    gov_client    = gov_client,
    gov_local_path = gov_local_path,
    backend       = backend,
    data_repo_url = data_repo_url,
    github_pat    = github_pat,
    github_api_url = github_api_url
  )
}


#' Build Connection from Local Repo + Store (Developer Path)
#'
#' Reads `.datom/project.yaml` for project identity and cross-checks against
#' the store config. Uses the store for credentials.
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

  # Extract backend-neutral fields from store
  data_backend <- .datom_store_backend(store$data)
  data_root <- .datom_store_root(store$data)
  prefix <- store$data$prefix
  region <- .datom_store_region(store$data)

  # Cross-check: yaml root must match store root (if yaml has storage config)
  storage <- cfg$storage
  if (!is.null(storage)) {
    data_storage <- storage$data %||% storage
    yaml_root <- data_storage$root
    if (!is.null(yaml_root) && !is.null(data_root) && !identical(yaml_root, data_root)) {
      cli::cli_abort(c(
        "Store/config mismatch: store data root is {.val {data_root}} but {.file project.yaml} says {.val {yaml_root}}.",
        "i" = "Ensure the store matches the project configuration."
      ))
    }
  }

  role <- store$role

  # --- Governance attachment detection (four-state matrix) -------------------
  # governance.json (in the local clone) is the canonical gov-attachment signal.
  # project.yaml carries no governance coordinates after Phase 21 Chunk 2.
  gov_json <- .datom_read_governance_json_local(path)
  has_gov_json  <- !is.null(gov_json)
  has_gov_store <- !is.null(store$governance)

  if (has_gov_json && !has_gov_store) {
    cli::cli_abort(c(
      "Project {.val {project_name}} is gov-attached but no governance store was supplied.",
      "i" = "Add {.code governance = datom_store_*(...)} to your {.fn datom_store} call.",
      "i" = "Supply credentials only -- data location is auto-resolved from {.fn ref.json}.",
      "i" = "Gov repo:     {.url {gov_json$gov_repo_url}}",
      "i" = "Gov storage:  {gov_json$gov_storage$type} / {gov_json$gov_storage$root}"
    ))
  }

  if (!has_gov_json && has_gov_store) {
    cli::cli_warn(c(
      "Project {.val {project_name}} has no governance attached.",
      "i" = "The governance store credentials supplied will be ignored.",
      "i" = "Use {.fn gov_attach} (from the datomanager package) if you intend to attach governance."
    ))
  }

  # Effective governance store: NULL when no gov.json (includes warn case above)
  effective_gov_store <- if (has_gov_json) store$governance else NULL

  if (has_gov_json && has_gov_store) {
    # Cross-check gov_repo_url from governance.json against store, when supplied
    expected_url <- store$gov_repo_url
    recorded_url <- gov_json$gov_repo_url
    if (!is.null(expected_url) && nzchar(expected_url) &&
        !identical(expected_url, recorded_url)) {
      cli::cli_abort(c(
        "Governance URL mismatch for project {.val {project_name}}.",
        "x" = "governance.json: {.url {recorded_url}}",
        "x" = "store gov_repo_url: {.url {expected_url}}",
        "i" = "Run {.fn datom_pull} to sync your local clone, or check your store."
      ))
    }
  }

  # gov_local_path: derive only when gov is actually attached; otherwise NULL.
  gov_local_path <- if (!is.null(effective_gov_store)) {
    .datom_resolve_or_default_gov_path(store, as.character(path))
  } else {
    NULL
  }

  # Resolve data location via ref.json (if governance store present)
  ref_location <- .datom_resolve_data_location(
    store, role,
    project_name = project_name,
    path = as.character(path),
    gov_local_path = gov_local_path,
    endpoint = endpoint
  )

  # Synthesise effective_data_store, handling credentials-only case.
  # For datom_store_s3_creds, ref_location supplies the location fields;
  # the client is built from the synthesised full store so the correct
  # region is used from the start.
  effective_data_store <- store$data
  migrated <- FALSE

  if (is_datom_store_s3_creds(store$data)) {
    # ref_location is guaranteed non-NULL: .datom_resolve_data_location() aborts otherwise.
    effective_data_store <- datom_store_s3(
      bucket        = ref_location$root,
      prefix        = ref_location$prefix,
      region        = ref_location$region %||% "us-east-1",
      access_key    = store$data$access_key,
      secret_key    = store$data$secret_key,
      session_token = store$data$session_token,
      validate      = FALSE
    )
  } else if (!is.null(ref_location)) {
    ref_root   <- ref_location$root
    ref_prefix <- ref_location$prefix
    store_root   <- .datom_store_root(store$data)
    store_prefix <- store$data$prefix
    migrated <- !identical(ref_root, store_root) ||
      !identical(ref_prefix %||% NULL, store_prefix %||% NULL)
  }

  conn <- .datom_build_init_conn(
    project_name, effective_data_store,
    if (role == "developer") as.character(path) else NULL,
    role, endpoint,
    gov_store = effective_gov_store,
    gov_local_path = gov_local_path
  )

  # Populate identity fields from store and git remote
  conn$github_pat <- store$github_pat
  conn$github_api_url <- store$github_api_url
  conn$data_repo_url <- tryCatch({
    repo <- git2r::repository(as.character(path))
    remotes <- git2r::remotes(repo)
    if (length(remotes) > 0L) git2r::remote_url(repo, remotes[[1L]]) else NULL
  }, error = function(e) NULL)

  # Override conn root/prefix/region with ref-resolved values if migrated
  if (!is.null(ref_location) && migrated) {
    conn$root <- ref_location$root
    conn$prefix <- ref_location$prefix
    conn$region <- ref_location$region
  }

  # Validate data store reachability
  .datom_check_data_reachable(conn, migrated = migrated)

  # Validate git remote reachability
  .datom_check_git_reachable(conn)

  conn
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

  # Resolve data location via ref.json (if governance store present).
  # Readers do not have a gov clone -- always read via gov storage client.
  ref_location <- .datom_resolve_data_location(
    store, store$role,
    project_name = project_name,
    path = NULL,
    gov_local_path = NULL,
    endpoint = endpoint
  )

  # Synthesise effective_data_store, handling credentials-only case.
  effective_data_store <- store$data
  migrated <- FALSE

  if (is_datom_store_s3_creds(store$data)) {
    # ref_location is guaranteed non-NULL: .datom_resolve_data_location() aborts otherwise.
    effective_data_store <- datom_store_s3(
      bucket        = ref_location$root,
      prefix        = ref_location$prefix,
      region        = ref_location$region %||% "us-east-1",
      access_key    = store$data$access_key,
      secret_key    = store$data$secret_key,
      session_token = store$data$session_token,
      validate      = FALSE
    )
  } else if (!is.null(ref_location)) {
    ref_root   <- ref_location$root
    ref_prefix <- ref_location$prefix
    store_root   <- .datom_store_root(store$data)
    store_prefix <- store$data$prefix
    migrated <- !identical(ref_root, store_root) ||
      !identical(ref_prefix %||% NULL, store_prefix %||% NULL)
  }

  conn <- .datom_build_init_conn(
    project_name, effective_data_store, NULL, store$role, endpoint,
    gov_store = store$governance,
    gov_local_path = NULL
  )

  conn$github_api_url <- store$github_api_url

  # Override conn root/prefix/region with ref-resolved values if migrated
  if (!is.null(ref_location) && migrated) {
    conn$root <- ref_location$root
    conn$prefix <- ref_location$prefix
    conn$region <- ref_location$region
  }

  # --- Data-first gov-discovery probe (Style B) ------------------------------
  # When the reader supplied no governance store, probe the data storage for
  # governance.json. If present, the project is gov-attached but the reader
  # bypassed it -- warn (do not abort): the conn is usable but the data
  # coordinates may go stale after a migration.
  if (is.null(store$governance)) {
    gov_json <- tryCatch(
      .datom_storage_read_governance_json(conn),
      error = function(e) NULL
    )
    if (!is.null(gov_json)) {
      cli::cli_warn(c(
        "Project {.val {project_name}} has governance attached, but you connected with data-store credentials only.",
        "i" = "Connection resolved using supplied coordinates; these may go stale after a data migration.",
        "i" = "To stay current, rebuild your store with {.code governance = datom_store_*(...)} and pass credentials only.",
        "i" = "Gov repo:    {.url {gov_json$gov_repo_url}}",
        "i" = "Gov storage: {gov_json$gov_storage$type} / {gov_json$gov_storage$root}"
      ))
    }
  }

  # Validate data store reachability
  .datom_check_data_reachable(conn, migrated = migrated)

  conn
}
