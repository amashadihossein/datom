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
#' @param gov_local_path Absolute path to the local gov clone (NULL for readers).
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
                          gov_client = NULL,
                          gov_local_path = NULL,
                          backend = "s3") {
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
      project_name = project_name,
      backend = backend,
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
      gov_client = gov_client,
      gov_local_path = gov_local_path
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
  cli::cli_li("Backend: {.val {x$backend}}")
  cli::cli_li("Role: {.val {x$role}}")
  cli::cli_li("Data root: {.val {x$root}}")

  if (!is.null(x$prefix)) {
    cli::cli_li("Data prefix: {.val {x$prefix}}")
  }

  if (!is.null(x$region)) {
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
      org = store$github_org
    )
  }

  if (is.null(remote_url)) {
    cli::cli_abort(c(
      "No remote URL available.",
      "i" = "Either provide {.arg data_repo_url} on the store or set {.code create_repo = TRUE}."
    ))
  }

  # --- Resolve gov_local_path ------------------------------------------------
  gov_local_path <- if (!is.null(store$gov_local_path)) {
    fs::path_abs(store$gov_local_path)
  } else if (!is.null(store$gov_repo_url)) {
    .datom_resolve_gov_local_path(
      data_local_path = fs::path_abs(path),
      gov_repo_url    = store$gov_repo_url
    )
  } else {
    NULL
  }

  # --- Step 0: ensure gov clone is available ---------------------------------
  # Capture pre-existence so on.exit cleanup can roll back the clone iff we
  # created it (and only if a later step fails before git push).
  .gov_clone_created_here <- FALSE
  if (!is.null(store$gov_repo_url) && !is.null(gov_local_path)) {
    gov_clone_existed_before <- .datom_gov_clone_exists(as.character(gov_local_path))
    .datom_gov_clone_init(store$gov_repo_url, as.character(gov_local_path))
    .gov_clone_created_here <- !gov_clone_existed_before
  }

  # Register gov-clone rollback immediately so failures in the namespace
  # checks below (which run before the data-side on.exit is set) still
  # trigger cleanup. Cleared by setting .git_pushed = TRUE after push.
  .git_pushed <- FALSE
  .init_success <- FALSE
  .safe_delete <- function(p, is_dir = TRUE) {
    tryCatch(
      if (is_dir) fs::dir_delete(p) else fs::file_delete(p),
      error = function(e) NULL
    )
  }
  on.exit({
    if (.gov_clone_created_here && !.init_success && !.git_pushed &&
        !is.null(gov_local_path) && fs::dir_exists(gov_local_path)) {
      .safe_delete(as.character(gov_local_path))
    }
  }, add = TRUE)

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
        project_name, data_root, data_prefix, data_region,
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

  # --- Gov project namespace check -------------------------------------------
  # Abort if this project name is already registered in the gov clone. This
  # prevents a data-first init from completing only to have the gov registration
  # step fail, which would require manual cleanup.
  if (!is.null(gov_local_path) && .datom_gov_clone_exists(as.character(gov_local_path))) {
    gov_project_dir <- .datom_gov_project_path(as.character(gov_local_path), project_name)
    if (fs::dir_exists(gov_project_dir)) {
      cli::cli_abort(c(
        "Project {.val {project_name}} is already registered in the governance repo.",
        "i" = "Found at: {.path {gov_project_dir}}",
        "i" = "Use a different project name or decommission the existing project first."
      ))
    }
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
  gov_backend <- .datom_store_backend(store$governance)
  gov_root <- .datom_store_root(store$governance)
  gov_region <- .datom_store_region(store$governance)

  gov_yaml <- list(
    type = gov_backend,
    root = gov_root,
    prefix = store$governance$prefix
  )
  if (gov_backend == "s3") gov_yaml$region <- gov_region

  data_yaml <- list(
    type = data_backend,
    root = data_root,
    prefix = data_prefix
  )
  if (data_backend == "s3") data_yaml$region <- data_region

  project_config <- list(
    project_name = project_name,
    project_description = "",
    created_at = format(Sys.Date(), "%Y-%m-%d"),
    datom_version = as.character(utils::packageVersion("datom")),
    storage = list(
      governance = gov_yaml,
      data = data_yaml,
      max_file_size_gb = max_file_size_gb
    ),
    repos = list(
      data = list(remote_url = remote_url),
      governance = list(
        remote_url = store$gov_repo_url,
        local_path = store$gov_local_path
      )
    ),
    sync = list(
      continue_on_error = TRUE,
      parallel_uploads = 4L
    ),
    renv = FALSE
  )

  yaml::write_yaml(project_config, fs::path(path, ".datom", "project.yaml"))

  # --- Build dispatch and ref payloads (written to gov, not data clone) ------
  dispatch <- list(
    methods = list(
      r = list(default = "datom::datom_read"),
      python = list(default = "datom.read")
    )
  )

  ref <- .datom_create_ref(store$data)

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

  # Stage data-repo files only (dispatch.json and ref.json live in gov repo)
  git2r::add(repo, c(
    ".datom/project.yaml",
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
  .git_pushed <- TRUE

  # From this point on, the data git remote has been advertised. Failures
  # below are reported but do NOT roll back local files (user has work to
  # recover) -- they abort with a clear recovery hint.

  data_conn <- .datom_build_init_conn(
    project_name, store$data, path, "developer", NULL,
    gov_store = store$governance,
    gov_local_path = if (!is.null(gov_local_path)) as.character(gov_local_path) else NULL
  )

  # --- Register project in gov repo + mirror to gov storage ------------------
  # dispatch.json and ref.json live in the gov repo (projects/{name}/),
  # never in the data clone. .datom_gov_register_project() commits + pushes
  # both files and mirrors them to gov storage. A failure here is a hard
  # abort: the data repo is pushed but no project entry exists in gov, so
  # readers cannot discover this project. Recovery is manual via
  # datom_sync_dispatch().
  if (!is.null(gov_local_path)) {
    tryCatch(
      .datom_gov_register_project(data_conn, project_name, dispatch, ref),
      error = function(e) {
        cli::cli_abort(c(
          "Data repo pushed but gov registration failed.",
          "x" = conditionMessage(e),
          "i" = "Local data clone is intact at {.path {path}}.",
          "i" = "After fixing the cause (e.g. credentials, connectivity), run {.fn datom_sync_dispatch} to register the project."
        ), call = NULL)
      }
    )
  }

  # --- Mirror manifest to data storage ----------------------------------------
  # Manifest is part of the data-side contract -- readers need it to clone.
  # Failure aborts; user runs datom_sync_manifest after fixing cause.
  tryCatch({
    .datom_storage_write_json(data_conn, ".metadata/manifest.json", manifest)
  }, error = function(e) {
    cli::cli_abort(c(
      "Data repo pushed and gov registered but manifest upload failed.",
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


# --- datom_init_gov -----------------------------------------------------------

#' Initialize a Governance Repository
#'
#' One-time setup to create a shared governance repository that serves many
#' data projects in an organisation. Creates the GitHub repo (optionally),
#' seeds the skeleton (`README.md` + `projects/.gitkeep`), commits, and
#' pushes.
#'
#' Idempotent: if `gov_local_path` already contains an initialised governance
#' clone (i.e. `projects/.gitkeep` exists), the function returns silently
#' without making any changes.
#'
#' @param gov_store A governance store component (`datom_store_s3` or
#'   `datom_store_local`).  This is the storage backend that individual data
#'   projects will use to register their dispatch and ref files.
#' @param gov_repo_url GitHub URL of the governance repo.  Mutually exclusive
#'   with `create_repo = TRUE`.
#' @param gov_local_path Local path for the governance clone.  When `NULL`,
#'   derived from the basename of `gov_repo_url` (`.git` suffix stripped) in
#'   the current directory.  When `create_repo = TRUE` and no URL is known
#'   yet, set this explicitly or let it default to `repo_name`.
#' @param create_repo If `TRUE`, create a GitHub repo via the API and use the
#'   returned URL.  Mutually exclusive with providing `gov_repo_url`.
#' @param repo_name GitHub repo name when `create_repo = TRUE`.  Required
#'   when `create_repo = TRUE`.
#' @param github_pat GitHub personal access token.  Required when
#'   `create_repo = TRUE`.
#' @param github_org GitHub organisation slug.  `NULL` creates the repo under
#'   the authenticated user account.
#' @param private Whether the created repo should be private.  Default `TRUE`.
#'   Ignored when `create_repo = FALSE`.
#'
#' @return Invisible `gov_repo_url` on success.
#' @export
datom_init_gov <- function(gov_store,
                            gov_repo_url = NULL,
                            gov_local_path = NULL,
                            create_repo = FALSE,
                            repo_name = NULL,
                            github_pat = NULL,
                            github_org = NULL,
                            private = TRUE) {
  .datom_check_git2r()

  # --- Input validation -------------------------------------------------------
  if (!.is_datom_store_component(gov_store)) {
    cli::cli_abort(
      "{.arg gov_store} must be a {.cls datom_store_s3} or {.cls datom_store_local} object."
    )
  }

  if (isTRUE(create_repo) && !is.null(gov_repo_url)) {
    cli::cli_abort(c(
      "{.arg create_repo} and {.arg gov_repo_url} are mutually exclusive.",
      "i" = "Either set {.code create_repo = TRUE} or provide {.arg gov_repo_url}, not both."
    ))
  }

  if (isTRUE(create_repo) && is.null(repo_name)) {
    cli::cli_abort(
      "{.arg repo_name} is required when {.code create_repo = TRUE}."
    )
  }

  if (isTRUE(create_repo) && is.null(github_pat)) {
    cli::cli_abort(
      "{.arg github_pat} is required when {.code create_repo = TRUE}."
    )
  }

  if (!isTRUE(create_repo) && is.null(gov_repo_url)) {
    cli::cli_abort(c(
      "No governance repo URL available.",
      "i" = "Either provide {.arg gov_repo_url} or set {.code create_repo = TRUE}."
    ))
  }

  # --- Create GitHub repo if requested ----------------------------------------
  if (isTRUE(create_repo)) {
    gov_repo_url <- .datom_create_github_repo(
      repo_name = repo_name,
      pat = github_pat,
      org = github_org,
      private = private
    )
  }

  # --- Resolve gov_local_path -------------------------------------------------
  if (is.null(gov_local_path)) {
    base_name <- sub("\\.git$", "", basename(gov_repo_url))
    gov_local_path <- fs::path_abs(base_name)
  } else {
    gov_local_path <- fs::path_abs(gov_local_path)
  }

  # --- Idempotence check ------------------------------------------------------
  # If the skeleton already exists (projects/.gitkeep), treat as already done.
  if (fs::file_exists(fs::path(gov_local_path, "projects", ".gitkeep"))) {
    if (.datom_gov_clone_exists(gov_local_path)) {
      .datom_gov_validate_remote(gov_local_path, gov_repo_url)
    }
    cli::cli_alert_info("Governance repository already initialised at {.path {gov_local_path}}.")
    return(invisible(gov_repo_url))
  }

  # --- Set up local clone -----------------------------------------------------
  # For create_repo: init locally and set remote (remote is brand-new/empty).
  # For existing URL: clone the remote.
  if (isTRUE(create_repo)) {
    fs::dir_create(gov_local_path)
    repo <- git2r::init(gov_local_path)
    git_cfg <- git2r::config()$global
    author_name  <- git_cfg$user.name  %||% "datom"
    author_email <- git_cfg$user.email %||% "datom@noreply"
    git2r::config(repo, user.name = author_name, user.email = author_email)
    git2r::remote_add(repo, name = "origin", url = gov_repo_url)
  } else {
    .datom_gov_clone_init(gov_repo_url, gov_local_path)
  }

  # --- Seed gov repo skeleton -------------------------------------------------
  projects_dir <- fs::path(gov_local_path, "projects")
  gitkeep_path <- fs::path(projects_dir, ".gitkeep")
  readme_path  <- fs::path(gov_local_path, "README.md")

  fs::dir_create(projects_dir)
  if (!fs::file_exists(gitkeep_path)) writeLines("", gitkeep_path)
  if (!fs::file_exists(readme_path)) {
    writeLines(c("# Governance Repository",
                 "",
                 "This repository stores governance metadata for datom data projects.",
                 "Each registered project has a subdirectory under `projects/`."),
               readme_path)
  }

  # --- Commit and push --------------------------------------------------------
  repo <- git2r::repository(gov_local_path)
  git_cfg <- git2r::config()$global
  author_name  <- git_cfg$user.name  %||% "datom"
  author_email <- git_cfg$user.email %||% "datom@noreply"
  git2r::config(repo, user.name = author_name, user.email = author_email)

  git2r::add(repo, c("README.md", fs::path("projects", ".gitkeep")))
  git2r::commit(
    repo,
    message = "Initialize governance repository",
    author  = git2r::default_signature(repo)
  )

  .datom_git_push(gov_local_path)

  cli::cli_alert_success("Governance repository initialised at {.path {gov_local_path}}.")

  invisible(gov_repo_url)
}


#' Clone a datom Repository
#'
#' Clones a remote datom repository and returns a connection. This is the
#' recommended way for teammates to join an existing datom project — it wraps
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

  # --- Clone or verify gov repo when gov_repo_url is set ---------------------
  if (!is.null(store$gov_repo_url) && nzchar(store$gov_repo_url)) {
    gov_local_path <- if (!is.null(store$gov_local_path) && nzchar(store$gov_local_path)) {
      fs::path_abs(store$gov_local_path)
    } else {
      .datom_resolve_gov_local_path(
        data_local_path = path,
        gov_repo_url    = store$gov_repo_url
      )
    }

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
                                   gov_local_path = NULL) {
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
    project_name = project_name,
    root = data_root,
    prefix = data_prefix,
    region = data_region,
    client = client,
    path = path,
    role = role,
    endpoint = endpoint,
    gov_root = gov_root,
    gov_prefix = gov_prefix,
    gov_region = gov_region,
    gov_client = gov_client,
    gov_local_path = gov_local_path,
    backend = backend
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
    if (!is.null(yaml_root) && !identical(yaml_root, data_root)) {
      cli::cli_abort(c(
        "Store/config mismatch: store data root is {.val {data_root}} but {.file project.yaml} says {.val {yaml_root}}.",
        "i" = "Ensure the store matches the project configuration."
      ))
    }
  }

  role <- store$role

  # gov_local_path: use explicit override from store if set, otherwise derive
  # sibling default from the gov_repo_url (if available). Computed before ref
  # resolution so the developer fast path can read from the local gov clone.
  gov_local_path <- if (!is.null(store$gov_local_path)) {
    store$gov_local_path
  } else if (!is.null(store$gov_repo_url)) {
    as.character(.datom_resolve_gov_local_path(
      data_local_path = as.character(path),
      gov_repo_url = store$gov_repo_url
    ))
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

  # If ref resolved a different location, build a modified data store
  effective_data_store <- store$data
  migrated <- FALSE
  if (!is.null(ref_location)) {
    ref_root <- ref_location$root
    ref_prefix <- ref_location$prefix
    store_root <- .datom_store_root(store$data)
    store_prefix <- store$data$prefix
    migrated <- !identical(ref_root, store_root) ||
      !identical(ref_prefix %||% NULL, store_prefix %||% NULL)
  }

  conn <- .datom_build_init_conn(
    project_name, effective_data_store,
    if (role == "developer") as.character(path) else NULL,
    role, endpoint,
    gov_store = store$governance,
    gov_local_path = gov_local_path
  )

  # Override conn root/prefix/region with ref-resolved values if migrated
  if (!is.null(ref_location) && migrated) {
    conn$root <- ref_location$root
    conn$prefix <- ref_location$prefix
    conn$region <- ref_location$region
  }

  # Validate data store reachability
  .datom_check_data_reachable(conn, migrated = migrated)

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

  migrated <- FALSE
  if (!is.null(ref_location)) {
    ref_root <- ref_location$root
    ref_prefix <- ref_location$prefix
    store_root <- .datom_store_root(store$data)
    store_prefix <- store$data$prefix
    migrated <- !identical(ref_root, store_root) ||
      !identical(ref_prefix %||% NULL, store_prefix %||% NULL)
  }

  conn <- .datom_build_init_conn(
    project_name, store$data, NULL, store$role, endpoint,
    gov_store = store$governance,
    gov_local_path = NULL
  )

  # Override conn root/prefix/region with ref-resolved values if migrated
  if (!is.null(ref_location) && migrated) {
    conn$root <- ref_location$root
    conn$prefix <- ref_location$prefix
    conn$region <- ref_location$region
  }

  # Validate data store reachability
  .datom_check_data_reachable(conn, migrated = migrated)

  conn
}
