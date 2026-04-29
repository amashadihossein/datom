# dev/dev-sandbox.R
# ──────────────────────────────────────────────────────────────────────────────
# Developer sandbox: stand up and tear down a complete datom data product
# infrastructure (GitHub repo + S3 namespace + local repo) in one call.
#
# Usage:
#   source("dev/dev-sandbox.R")
#   store <- sandbox_store()   # builds store from keyring/env vars
#   env <- sandbox_up(store)   # creates everything, returns connection info
#   # ... work / test ...
#   sandbox_down(env)          # tears down everything
#   sandbox_reset(env, store)  # down + up (same config)
#
# Prerequisites:
#   - AWS credentials accessible (keyring, env vars, etc.)
#   - GITHUB_PAT accessible
#   - `gh` CLI for teardown (repo deletion only)
#   - datom loaded (devtools::load_all())
#
# All defaults are overridable. Adjust .sandbox_defaults() for your setup.
# ──────────────────────────────────────────────────────────────────────────────

# --- Configuration -----------------------------------------------------------

#' Default sandbox configuration
#'
#' Edit these values once to match your dev environment. Every sandbox_*
#' function pulls from here unless overridden.
#'
#' Credentials: set the environment variables below, or pass explicit values
#' to sandbox_store(). Env vars are never hard-coded here.
#'
#'   AWS_ACCESS_KEY   - AWS access key ID
#'   AWS_SECRET_KEY   - AWS secret access key
#'   GITHUB_PAT       - GitHub personal access token
.sandbox_defaults <- function() {
  list(
    project_name = "SANDBOX_TEST",
    github_org    = NULL,            # NULL = personal repo; set to "my-org" for org repos
    repo_name     = "datom-sandbox", # GitHub repo name (data repo)
    gov_repo_name = "datom-sandbox-gov", # GitHub repo name (governance repo)
    bucket        = "datom-test",    # REQUIRED -- your dev S3 bucket
    gov_bucket    = "datom-gov-test", # REQUIRED -- your dev governance S3 bucket
    prefix        = "sandbox/",      # S3 prefix (keeps sandbox isolated)
    region        = "us-east-1",
    base_dir      = fs::path_abs("../datom-test"),  # sibling of datom project
    populate      = TRUE,            # seed with example data?
    n_months      = 2L               # how many monthly snapshots to sync
  )
}

# --- Store construction ------------------------------------------------------

#' Build a datom_store for sandbox use
#'
#' Constructs a `datom_store` with S3 components from credentials. Defaults
#' to keyring; override with explicit values or env vars.
#'
#' @param bucket S3 bucket name.
#' @param prefix S3 prefix.
#' @param region AWS region.
#' @param access_key AWS access key ID.
#' @param secret_key AWS secret access key.
#' @param github_pat GitHub PAT.
#' @param github_org GitHub org for repo creation (NULL = personal).
#' @param data_repo_url Pre-existing data repo URL (NULL = create_repo in sandbox_up).
#'
#' @return A `datom_store` object (developer role).
sandbox_store <- function(bucket = .sandbox_defaults()$bucket,
                          gov_bucket = .sandbox_defaults()$gov_bucket,
                          prefix = .sandbox_defaults()$prefix,
                          region = .sandbox_defaults()$region,
                          access_key = Sys.getenv("AWS_ACCESS_KEY"),
                          secret_key = Sys.getenv("AWS_SECRET_KEY"),
                          github_pat = Sys.getenv("GITHUB_PAT"),
                          github_org = .sandbox_defaults()$github_org,
                          data_repo_url = NULL) {
  data_comp <- datom::datom_store_s3(
    bucket     = bucket,
    prefix     = prefix,
    region     = region,
    access_key = access_key,
    secret_key = secret_key,
    validate   = FALSE
  )

  gov_comp <- datom::datom_store_s3(
    bucket     = gov_bucket,
    prefix     = prefix,
    region     = region,
    access_key = access_key,
    secret_key = secret_key,
    validate   = FALSE
  )

  datom::datom_store(
    governance = gov_comp,
    data       = data_comp,
    github_pat = github_pat,
    github_org = github_org,
    data_repo_url = data_repo_url,
    validate   = FALSE
  )
}


#' Build a local-backend datom_store for sandbox use
#'
#' Constructs a `datom_store` with local filesystem components. No AWS
#' credentials needed — data lives on disk.
#'
#' @param path Root directory for local storage. Created if it doesn't exist.
#' @param prefix Storage prefix (default NULL).
#' @param github_pat GitHub PAT (still required for governance/git).
#' @param github_org GitHub org for repo creation (NULL = personal).
#' @param data_repo_url Pre-existing data repo URL (NULL = create_repo in sandbox_up).
#'
#' @return A `datom_store` object (developer role, local backend).
sandbox_store_local <- function(path,
                                gov_path = paste0(path, "-gov"),
                                prefix = NULL,
                                github_pat = Sys.getenv("GITHUB_PAT"),
                                github_org = NULL,
                                data_repo_url = NULL) {
  fs::dir_create(path)
  fs::dir_create(gov_path)

  data_comp <- datom::datom_store_local(
    path     = path,
    prefix   = prefix,
    validate = FALSE
  )

  gov_comp <- datom::datom_store_local(
    path     = gov_path,
    prefix   = prefix,
    validate = FALSE
  )

  datom::datom_store(
    governance = gov_comp,
    data       = data_comp,
    github_pat = github_pat,
    github_org = github_org,
    data_repo_url = data_repo_url,
    validate   = FALSE
  )
}


# --- Helpers (gh CLI — used only for teardown) --------------------------------

.sandbox_check_gh <- function() {
  rc <- system2("gh", "--version", stdout = FALSE, stderr = FALSE)
  if (rc != 0L) {
    cli::cli_abort(c(
      "{.strong gh} CLI is not installed or not on PATH.",
      "i" = "Install from {.url https://cli.github.com}"
    ))
  }
  invisible(TRUE)
}

.sandbox_gh <- function(..., error_on_fail = TRUE) {
  args <- c(...)
  result <- suppressWarnings(system2("gh", args, stdout = TRUE, stderr = TRUE))
  status <- attr(result, "status") %||% 0L
  if (error_on_fail && status != 0L) {
    cli::cli_abort(c(
      "gh command failed: {.code gh {paste(args, collapse = ' ')}}",
      "x" = paste(result, collapse = "\n")
    ))
  }
  list(output = result, status = status)
}

.sandbox_repo_full_name <- function(cfg, repo_name = NULL, repo_url = NULL) {
  repo_name <- repo_name %||% cfg$repo_name

  # Prefer parsing a known github URL when available -- handles edge cases
  # where the user's PAT auth login differs from the org that owns the repo.
  if (!is.null(repo_url) && nzchar(repo_url) &&
      grepl("github\\.com", repo_url, ignore.case = TRUE)) {
    return(sub(".*github\\.com[:/]([^/]+/[^/]+?)(\\.git)?$", "\\1",
               repo_url, perl = TRUE))
  }

  if (!is.null(cfg$github_org) && nzchar(cfg$github_org)) {
    paste0(cfg$github_org, "/", repo_name)
  } else {
    # Personal repo -- resolve the authenticated user's login.
    owner <- trimws(.sandbox_gh("api", "user", "-q", ".login")$output)
    paste0(owner, "/", repo_name)
  }
}

.sandbox_storage_label <- function(store_component) {
  if (inherits(store_component, "datom_store_s3")) {
    paste0("s3://", store_component$bucket, "/",
           store_component$prefix %||% "", "datom/")
  } else {
    as.character(datom:::.datom_store_root(store_component))
  }
}


# --- S3 cleanup --------------------------------------------------------------

#' Delete all objects under the sandbox S3 prefix
#'
#' Uses paws.storage directly (no aws CLI dependency). Lists all objects
#' under prefix/datom/ and deletes them in batches of 1000.
.sandbox_wipe_s3_component <- function(store_component, label = "data") {
  if (!inherits(store_component, "datom_store_s3")) {
    cli::cli_alert_info("Skipping {label} S3 wipe (not an S3 store).")
    return(invisible(0L))
  }

  s3 <- datom:::.datom_s3_client(
    access_key = store_component$access_key,
    secret_key = store_component$secret_key,
    region     = store_component$region
  )

  full_prefix <- paste0(
    if (!is.null(store_component$prefix)) paste0(gsub("/+$", "", store_component$prefix), "/") else "",
    "datom/"
  )

  cli::cli_alert_info("Listing {label} S3 objects under {.val {store_component$bucket}/{full_prefix}}...")

  all_keys <- character()
  continuation <- NULL
  repeat {
    args <- list(Bucket = store_component$bucket, Prefix = full_prefix, MaxKeys = 1000L)
    if (!is.null(continuation)) args$ContinuationToken <- continuation

    resp <- do.call(s3$list_objects_v2, args)
    keys <- purrr::map_chr(resp$Contents, "Key")
    all_keys <- c(all_keys, keys)

    if (isTRUE(resp$IsTruncated)) {
      continuation <- resp$NextContinuationToken
    } else {
      break
    }
  }

  if (length(all_keys) == 0L) {
    cli::cli_alert_info("No {label} S3 objects found. Nothing to delete.")
    return(invisible(0L))
  }

  cli::cli_alert_warning("Deleting {length(all_keys)} {label} S3 object{?s}...")

  batches <- split(all_keys, ceiling(seq_along(all_keys) / 1000))
  for (batch in batches) {
    objects <- purrr::map(batch, ~ list(Key = .x))
    s3$delete_objects(
      Bucket = store_component$bucket,
      Delete = list(Objects = objects, Quiet = TRUE)
    )
  }

  cli::cli_alert_success("Deleted {length(all_keys)} {label} S3 object{?s}.")
  invisible(length(all_keys))
}

# --- Local cleanup -----------------------------------------------------------

#' Delete the sandbox local store directory
.sandbox_wipe_local_component <- function(store_component, label = "data") {
  if (!inherits(store_component, "datom_store_local")) {
    cli::cli_alert_info("Skipping {label} local wipe (not a local store).")
    return(invisible(0L))
  }

  path <- as.character(datom:::.datom_store_root(store_component))

  if (!fs::dir_exists(path)) {
    cli::cli_alert_info("No {label} local directory found at {.path {path}}.")
    return(invisible(0L))
  }

  cli::cli_alert_warning("Removing {label} local directory {.path {path}}...")
  fs::dir_delete(path)
  cli::cli_alert_success("Removed {label} local directory.")
  invisible(TRUE)
}

# --- Core functions ----------------------------------------------------------

#' Stand up a sandbox datom data product
#'
#' Creates a GitHub repo (via datom_init_repo with create_repo = TRUE),
#' and optionally populates with example study data.
#'
#' @param store A `datom_store` object (from `sandbox_store()`).
#' @param ... Override any defaults from .sandbox_defaults().
#' @return A sandbox environment list (pass to sandbox_down/sandbox_reset).
sandbox_up <- function(store, ...) {
  cfg <- utils::modifyList(.sandbox_defaults(), list(...))

  if (missing(store) || !datom::is_datom_store(store)) {
    cli::cli_abort(c(
      "{.arg store} is required and must be a {.cls datom_store}.",
      "i" = "Build one with {.fn sandbox_store}."
    ))
  }

  local_path <- fs::path(cfg$base_dir, cfg$repo_name)
  gov_local_path <- fs::path(cfg$base_dir, cfg$gov_repo_name)

  cli::cli_h2("Sandbox Up: {.val {cfg$project_name}}")

  # Determine whether to create repo or use existing data_repo_url
  create_repo <- is.null(store$data_repo_url)

  if (!create_repo) {
    cli::cli_alert_info("Using existing remote: {.url {store$data_repo_url}}")
  } else {
    cli::cli_alert_info("Will create GitHub repo {.val {cfg$repo_name}} via API...")
  }

  # Clean up local paths if they exist
  if (fs::dir_exists(local_path)) {
    cli::cli_alert_warning("Local path {.path {local_path}} exists. Removing.")
    fs::dir_delete(local_path)
  }
  if (fs::dir_exists(gov_local_path)) {
    cli::cli_alert_warning("Gov local path {.path {gov_local_path}} exists. Removing.")
    fs::dir_delete(gov_local_path)
  }

  # ---- Step 1: bootstrap governance repo (gov-first per Phase 15) ----------
  if (is.null(store$gov_repo_url)) {
    cli::cli_alert_info("Initializing governance repo {.val {cfg$gov_repo_name}}...")
    gov_repo_url <- datom::datom_init_gov(
      gov_store      = store$governance,
      gov_local_path = as.character(gov_local_path),
      create_repo    = TRUE,
      repo_name      = cfg$gov_repo_name,
      github_pat     = store$github_pat,
      github_org     = store$github_org,
      private        = TRUE
    )

    # Rebuild store with gov_repo_url + gov_local_path so datom_init_repo can
    # locate the gov clone we just created.
    store <- datom::datom_store(
      governance     = store$governance,
      data           = store$data,
      github_pat     = store$github_pat,
      data_repo_url  = store$data_repo_url,
      gov_repo_url   = gov_repo_url,
      gov_local_path = as.character(gov_local_path),
      github_org     = store$github_org,
      validate       = FALSE
    )
  } else {
    cli::cli_alert_info("Using existing gov remote: {.url {store$gov_repo_url}}")
  }

  # ---- Step 2: initialize data repo (creates GitHub data repo if needed) ---
  cli::cli_alert_info("Initializing datom repo at {.path {local_path}}...")

  datom::datom_init_repo(
    path         = local_path,
    project_name = cfg$project_name,
    store        = store,
    create_repo  = create_repo,
    repo_name    = cfg$repo_name
  )

  cli::cli_alert_success("datom repo initialized and pushed.")

  # Optionally populate with example data
  conn <- NULL
  if (isTRUE(cfg$populate)) {
    cli::cli_alert_info("Populating with example data ({cfg$n_months} month{?s})...")

    conn <- datom::datom_get_conn(path = local_path, store = store)
    cutoffs <- datom::datom_example_cutoffs()
    n <- min(cfg$n_months, length(cutoffs))

    for (i in seq_len(n)) {
      cutoff <- cutoffs[i]
      month_label <- names(cutoffs)[i]

      cli::cli_alert_info("Syncing {.val {month_label}} (cutoff: {cutoff})...")

      dm <- datom::datom_example_data("dm", cutoff_date = cutoff)
      ex <- datom::datom_example_data("ex", cutoff_date = cutoff)

      input_dir <- fs::path(local_path, "input_files")
      write.csv(dm, fs::path(input_dir, "dm.csv"), row.names = FALSE)
      write.csv(ex, fs::path(input_dir, "ex.csv"), row.names = FALSE)

      manifest <- datom::datom_sync_manifest(conn)
      if (any(manifest$status %in% c("new", "changed"))) {
        datom::datom_sync(conn, manifest, continue_on_error = FALSE)
      } else {
        cli::cli_alert_info("No changes for {.val {month_label}}. Skipping.")
      }
    }

    cli::cli_alert_success("Populated {n} month{?s} of example data.")
  }

  # Build the environment object
  env <- list(
    config         = cfg,
    store          = store,
    local_path     = as.character(local_path),
    gov_local_path = as.character(gov_local_path),
    conn           = conn,
    created_at     = Sys.time()
  )

  class(env) <- "datom_sandbox"

  cli::cli_h3("Sandbox ready")
  cli::cli_ul()
  cli::cli_li("Git repo: {.path {local_path}}")
  cli::cli_li("Gov clone: {.path {gov_local_path}}")
  cli::cli_li("Data: {.path {(.sandbox_storage_label(store$data))}}")
  cli::cli_li("Governance: {.path {(.sandbox_storage_label(store$governance))}}")
  cli::cli_end()

  invisible(env)
}


#' Tear down a sandbox datom data product
#'
#' Deletes storage objects (S3 or local filesystem), GitHub repos, and local
#' clone directories.  Supports scoped teardown so you can tear down just the
#' project data, just the governance infrastructure, or everything at once.
#'
#' @param env Sandbox environment from sandbox_up().
#' @param scope One of `"all"` (default), `"project"`, or `"gov"`:
#'   * `"project"` -- decommission the data project only (leaves gov intact).
#'   * `"gov"` -- destroy the governance repo only (refuses if projects are
#'     still registered; call `scope = "project"` first, or use
#'     `force = TRUE`).
#'   * `"all"` -- project decommission, then gov destroy.
#' @param confirm If TRUE (default in interactive), asks before destroying.
#' @param force If TRUE, allow gov destroy even when projects are still
#'   registered (passed to `.datom_gov_destroy()`).  Ignored for
#'   `scope = "project"`.
sandbox_down <- function(env,
                         scope   = c("all", "project", "gov"),
                         confirm = interactive(),
                         force   = FALSE) {
  if (!inherits(env, "datom_sandbox")) {
    cli::cli_abort("{.arg env} must be a {.cls datom_sandbox} from {.fn sandbox_up}.")
  }

  scope <- match.arg(scope)
  cfg   <- env$config
  store <- env$store

  cli::cli_h2("Sandbox Down: {.val {cfg$project_name}}")

  if (isTRUE(confirm)) {
    cli::cli_alert_danger("This will permanently delete:")
    cli::cli_ul()
    if (scope %in% c("all", "project")) {
      cli::cli_li("Data storage: {.path {(.sandbox_storage_label(store$data))}}")
      cli::cli_li("Data GitHub repo: {.val {cfg$repo_name}}")
      cli::cli_li("Data clone: {.path {env$local_path}}")
    }
    if (scope %in% c("all", "gov")) {
      cli::cli_li("Governance storage: {.path {(.sandbox_storage_label(store$governance))}}")
      cli::cli_li("Gov GitHub repo: {.val {cfg$gov_repo_name %||% '(unknown)'}}")
      cli::cli_li("Gov clone: {.path {env$gov_local_path %||% env$conn$gov_local_path %||% '(unknown)'}}")
    }
    cli::cli_end()

    answer <- readline("Type 'yes' to confirm: ")
    if (!identical(tolower(trimws(answer)), "yes")) {
      cli::cli_alert_info("Teardown cancelled.")
      return(invisible(FALSE))
    }
  }

  # ---- Project decommission --------------------------------------------------
  if (scope %in% c("all", "project")) {
    if (!is.null(env$conn)) {
      datom::datom_decommission(env$conn, confirm = cfg$project_name)
    } else {
      # Fallback: manual teardown if conn is not available
      tryCatch({
        .sandbox_wipe_s3_component(store$data, "data")
      }, error = function(e) {
        cli::cli_alert_danger("Data storage cleanup failed: {conditionMessage(e)}")
      })
      tryCatch({
        .sandbox_check_gh()
        .sandbox_gh("repo", "delete", .sandbox_repo_full_name(cfg), "--yes")
        cli::cli_alert_success("Deleted data GitHub repo.")
      }, error = function(e) {
        cli::cli_alert_danger("Data GitHub repo deletion failed: {conditionMessage(e)}")
      })
      if (fs::dir_exists(env$local_path)) {
        fs::dir_delete(env$local_path)
        cli::cli_alert_success("Removed local data clone.")
      }
    }

    # Mop up the data store root for local backends. datom_decommission()
    # deletes the datom/ namespace inside the root but leaves the root itself
    # (it doesn't own the parent directory). The sandbox does own it.
    # No-op for S3 (root=bucket; we never delete buckets).
    tryCatch({
      .sandbox_wipe_local_component(store$data, "data")
    }, error = function(e) {
      cli::cli_alert_danger("Data local directory cleanup failed: {conditionMessage(e)}")
    })
  }

  # ---- Gov destroy -----------------------------------------------------------
  if (scope %in% c("all", "gov")) {
    # Wipe gov storage
    tryCatch({
      .sandbox_wipe_s3_component(store$governance, "governance")
      .sandbox_wipe_local_component(store$governance, "governance")
    }, error = function(e) {
      cli::cli_alert_danger("Governance storage cleanup failed: {conditionMessage(e)}")
      cli::cli_alert_info("Continuing with remaining teardown...")
    })

    # Delete gov GitHub repo
    gov_repo_name <- cfg$gov_repo_name %||% NULL
    gov_repo_url  <- store$gov_repo_url %||% env$conn$gov_repo_url %||% NULL
    if (!is.null(gov_repo_name)) {
      tryCatch({
        .sandbox_check_gh()
        gov_full_name <- .sandbox_repo_full_name(
          cfg, repo_name = gov_repo_name, repo_url = gov_repo_url
        )
        cli::cli_alert_info("Deleting gov GitHub repo {.val {gov_full_name}}...")
        .sandbox_gh("repo", "delete", gov_full_name, "--yes")
        cli::cli_alert_success("Deleted gov GitHub repo.")
      }, error = function(e) {
        cli::cli_alert_danger("Gov GitHub repo deletion failed: {conditionMessage(e)}")
        cli::cli_alert_info("You may need to delete it manually.")
      })
    }

    # Destroy local gov clone
    gov_local_path <- env$gov_local_path %||% env$conn$gov_local_path %||% NULL
    if (!is.null(gov_local_path)) {
      tryCatch(
        datom:::.datom_gov_destroy(gov_local_path, force = force),
        error = function(e) {
          cli::cli_alert_danger("Gov clone destroy failed: {conditionMessage(e)}")
        }
      )
    }
  }

  cli::cli_alert_success("Sandbox {.val {cfg$project_name}} torn down ({scope}).")
  invisible(TRUE)
}



#' Reset a sandbox (tear down + stand up with same config)
#'
#' @param env Sandbox environment from sandbox_up().
#' @param store A `datom_store` object. If NULL, reuses env$store.
#' @param confirm If TRUE (default in interactive), asks before destroying.
#' @return New sandbox environment.
sandbox_reset <- function(env, store = NULL, confirm = interactive()) {
  if (!inherits(env, "datom_sandbox")) {
    cli::cli_abort("{.arg env} must be a {.cls datom_sandbox} from {.fn sandbox_up}.")
  }

  store <- store %||% env$store

  cli::cli_h2("Sandbox Reset: {.val {env$config$project_name}}")

  sandbox_down(env, confirm = confirm)

  do.call(sandbox_up, c(list(store = store), env$config))
}


#' Recover a sandbox environment for teardown
#'
#' Reconstructs the `env` object needed by `sandbox_down()` without
#' re-creating any infrastructure. Use this when you lost the R session
#' before tearing down.
#'
#' @param store A `datom_store` object.
#' @param ... Override any defaults from .sandbox_defaults() — same args
#'   you originally passed to `sandbox_up()`.
#' @return A `datom_sandbox` object suitable for `sandbox_down()`.
#'
#' @examples
#' \dontrun{
#' source("dev/dev-sandbox.R")
#' store <- sandbox_store()
#' env <- sandbox_recover(
#'   store        = store,
#'   project_name = "STUDY_001",
#'   repo_name    = "study-001-data"
#' )
#' sandbox_down(env)
#' }
sandbox_recover <- function(store, ...) {
  cfg <- utils::modifyList(.sandbox_defaults(), list(...))

  local_path <- fs::path(cfg$base_dir, cfg$repo_name)
  gov_local_path <- fs::path(cfg$base_dir, cfg$gov_repo_name)

  env <- list(
    config         = cfg,
    store          = store,
    local_path     = as.character(local_path),
    gov_local_path = as.character(gov_local_path),
    conn           = NULL,
    created_at     = NA_real_
  )
  class(env) <- "datom_sandbox"

  cli::cli_alert_success("Recovered sandbox env for {.val {cfg$project_name}}.")
  cli::cli_ul()
  cli::cli_li("Git repo: {.path {local_path}}")
  cli::cli_li("Gov clone: {.path {gov_local_path}}")
  cli::cli_li("Data: {.path {(.sandbox_storage_label(store$data))}}")
  cli::cli_li("Governance: {.path {(.sandbox_storage_label(store$governance))}}")
  cli::cli_end()
  cli::cli_alert_info("Pass this to {.fn sandbox_down} to tear down.")

  invisible(env)
}


#' Print method for sandbox environment
print.datom_sandbox <- function(x, ...) {
  cfg <- x$config
  store <- x$store
  age <- if (is.na(x$created_at)) {
    "unknown"
  } else {
    paste0(round(difftime(Sys.time(), x$created_at, units = "mins"), 1), " minutes")
  }

  cli::cli_h3("datom sandbox")
  cli::cli_ul()
  cli::cli_li("Project: {.val {cfg$project_name}}")
  cli::cli_li("Git repo: {.path {x$local_path}}")
  cli::cli_li("Gov clone: {.path {x$gov_local_path %||% '(unknown)'}}")
  cli::cli_li("Data: {.path {(.sandbox_storage_label(store$data))}}")
  cli::cli_li("Governance: {.path {(.sandbox_storage_label(store$governance))}}")
  cli::cli_li("Age: {age}")
  if (!is.null(x$conn)) {
    cli::cli_li("Connection: available (env$conn)")
  }
  cli::cli_end()
  invisible(x)
}
