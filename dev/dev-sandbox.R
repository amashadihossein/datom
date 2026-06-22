# dev/dev-sandbox.R
# ──────────────────────────────────────────────────────────────────────────────
# Developer sandbox: stand up and tear down a complete datom data product
# (GitHub repo + storage namespace + local repo) in one call.
#
# SOLO-ONLY. After the gov-seam lift-out (spec gov-seam-liftout, 2026-06-20) datom
# no longer owns the governance write surface -- gov init/attach/decommission live
# in the companion package `datomanager`. This sandbox therefore stands up only
# Solo_Projects (no governance attached). The gov-attached sandbox flow will be
# reintroduced in datomanager's own dev tooling. The previous gov-capable version
# is preserved in git history.
#
# Usage:
#   source("~/projects/dev/datom/dev/dev-sandbox.R")
#   store <- sandbox_store()          # S3 store from keyring/env vars
#   # or: store <- sandbox_store_local(path = "~/projects/dev/datom-test/foo")
#   env <- sandbox_up(store)          # creates everything, returns connection info
#   # ... work / test ...
#   sandbox_down(env)                 # tears down everything
#   sandbox_reset(env, store)         # down + up (same config)
#
# Prerequisites:
#   - GITHUB_PAT accessible (every datom data repo is git+GitHub-backed)
#   - AWS credentials accessible for S3 stores (keyring, env vars, etc.)
#   - `gh` CLI only for the teardown fallback when no conn is available
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
#'   AWS_ACCESS_KEY_ID      - AWS access key ID
#'   AWS_SECRET_ACCESS_KEY  - AWS secret access key
#'   GITHUB_PAT             - GitHub personal access token
.sandbox_defaults <- function() {
  list(
    project_name = "SANDBOX_TEST",
    github_org   = NULL,             # NULL = personal repo; set to "my-org" for org repos
    repo_name    = "datom-sandbox",  # GitHub repo name (data repo)
    bucket       = "datom-test",     # REQUIRED for S3 stores -- your dev S3 bucket
    prefix       = "sandbox/",       # storage prefix (keeps sandbox isolated)
    region       = "us-east-1",
    base_dir     = fs::path_abs("../datom-test"),  # sibling of datom project
    populate     = TRUE,             # seed with example data?
    n_months     = 2L                # how many monthly snapshots to sync
  )
}

# --- Store construction ------------------------------------------------------

#' Build a solo datom_store (S3 data backend) for sandbox use
#'
#' Constructs a `datom_store` with an S3 data component only (no governance).
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
#' @return A solo `datom_store` object (developer role).
sandbox_store <- function(bucket = .sandbox_defaults()$bucket,
                          prefix = .sandbox_defaults()$prefix,
                          region = .sandbox_defaults()$region,
                          access_key = Sys.getenv("AWS_ACCESS_KEY_ID"),
                          secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY"),
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

  datom::datom_store(
    governance    = NULL,
    data          = data_comp,
    github_pat    = github_pat,
    github_org    = github_org,
    data_repo_url = data_repo_url,
    validate      = FALSE
  )
}


#' Build a solo local-backend datom_store for sandbox use
#'
#' Constructs a `datom_store` with a local filesystem data component only (no
#' governance). No AWS credentials needed -- data lives on disk.
#'
#' @param path Root directory for local storage. Created if it doesn't exist.
#' @param prefix Storage prefix (default NULL).
#' @param github_pat GitHub PAT (still required: the data repo is git-backed).
#' @param github_org GitHub org for repo creation (NULL = personal).
#' @param data_repo_url Pre-existing data repo URL (NULL = create_repo in sandbox_up).
#'
#' @return A solo `datom_store` object (developer role, local backend).
sandbox_store_local <- function(path,
                                prefix = NULL,
                                github_pat = Sys.getenv("GITHUB_PAT"),
                                github_org = NULL,
                                data_repo_url = NULL) {
  fs::dir_create(path)

  data_comp <- datom::datom_store_local(
    path     = path,
    prefix   = prefix,
    validate = FALSE
  )

  datom::datom_store(
    governance    = NULL,
    data          = data_comp,
    github_pat    = github_pat,
    github_org    = github_org,
    data_repo_url = data_repo_url,
    validate      = FALSE
  )
}


# --- Helpers (gh CLI -- teardown fallback only) -------------------------------

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

# Idempotent gh repo deletion. Returns invisible(TRUE) if deleted or already
# gone. Used only as a teardown fallback when no conn is available (otherwise
# datom_repo_delete() handles repo deletion via httr2).
.sandbox_gh_repo_delete <- function(full_name, kind = "GitHub repo") {
  view <- .sandbox_gh("repo", "view", full_name, "--json", "name",
                      error_on_fail = FALSE)
  if (view$status != 0L) {
    cli::cli_alert_info("{kind} {.val {full_name}} not found -- already deleted.")
    return(invisible(FALSE))
  }
  cli::cli_alert_info("Deleting {kind} {.val {full_name}}...")
  .sandbox_gh("repo", "delete", full_name, "--yes")
  cli::cli_alert_success("Deleted {kind} {.val {full_name}}.")
  invisible(TRUE)
}


# --- Storage cleanup ---------------------------------------------------------

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

#' Wipe the data store namespace (S3 or local), backend-agnostic
#'
#' datom_repo_delete() removes the GitHub repo + local clone but NOT the data
#' store namespace (the store root is caller-owned). The sandbox owns its
#' namespace, so it wipes it here on teardown.
.sandbox_wipe_storage <- function(store, label = "data") {
  tryCatch(.sandbox_wipe_s3_component(store$data, label),
           error = function(e) cli::cli_alert_danger("{label} S3 cleanup failed: {conditionMessage(e)}"))
  tryCatch(.sandbox_wipe_local_component(store$data, label),
           error = function(e) cli::cli_alert_danger("{label} local cleanup failed: {conditionMessage(e)}"))
  invisible(TRUE)
}


# --- Core functions ----------------------------------------------------------

#' Stand up a solo sandbox datom data product
#'
#' Creates a GitHub data repo (via datom_init_repo with create_repo = TRUE),
#' and optionally populates with example study data. No governance is attached.
#'
#' @param store A solo `datom_store` object (from `sandbox_store()` /
#'   `sandbox_store_local()`).
#' @param ... Override any defaults from .sandbox_defaults().
#' @return A sandbox environment list (pass to sandbox_down/sandbox_reset).
sandbox_up <- function(store, ...) {
  cfg <- utils::modifyList(.sandbox_defaults(), list(...))

  if (missing(store) || !datom::is_datom_store(store)) {
    cli::cli_abort(c(
      "{.arg store} is required and must be a {.cls datom_store}.",
      "i" = "Build one with {.fn sandbox_store} or {.fn sandbox_store_local}."
    ))
  }
  if (!is.null(store$governance)) {
    cli::cli_abort(c(
      "This sandbox is solo-only -- {.arg store} must have no governance component.",
      "i" = "Governance lives in datomanager after the gov-seam lift-out."
    ))
  }

  local_path <- fs::path(cfg$base_dir, cfg$repo_name)

  cli::cli_h2("Sandbox Up (solo): {.val {cfg$project_name}}")

  # Determine whether to create repo or use existing data_repo_url
  create_repo <- is.null(store$data_repo_url)

  if (!create_repo) {
    cli::cli_alert_info("Using existing remote: {.url {store$data_repo_url}}")
  } else {
    cli::cli_alert_info("Will create GitHub repo {.val {cfg$repo_name}} via API...")
  }

  # Clean up local path if it exists
  if (fs::dir_exists(local_path)) {
    cli::cli_alert_warning("Local path {.path {local_path}} exists. Removing.")
    fs::dir_delete(local_path)
  }

  # ---- Initialize data repo (creates GitHub data repo if needed) -----------
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

  env <- list(
    config     = cfg,
    store      = store,
    local_path = as.character(local_path),
    conn       = conn,
    created_at = Sys.time()
  )

  class(env) <- "datom_sandbox"

  cli::cli_h3("Sandbox ready (solo)")
  cli::cli_ul()
  cli::cli_li("Git repo: {.path {local_path}}")
  cli::cli_li("Data: {.path {(.sandbox_storage_label(store$data))}}")
  cli::cli_li("Governance: not attached (datom is solo-only; gov lives in datomanager)")
  cli::cli_end()

  invisible(env)
}


#' Tear down a solo sandbox datom data product
#'
#' Deletes the data GitHub repo + local clone (via `datom_repo_delete()`), then
#' wipes the data store namespace (S3 or local) that the sandbox owns.
#'
#' @param env Sandbox environment from sandbox_up().
#' @param confirm If TRUE (default in interactive), asks before destroying.
sandbox_down <- function(env, confirm = interactive()) {
  if (!inherits(env, "datom_sandbox")) {
    cli::cli_abort("{.arg env} must be a {.cls datom_sandbox} from {.fn sandbox_up}.")
  }

  cfg   <- env$config
  store <- env$store

  cli::cli_h2("Sandbox Down (solo): {.val {cfg$project_name}}")

  if (isTRUE(confirm)) {
    cli::cli_alert_danger("This will permanently delete:")
    cli::cli_ul()
    cli::cli_li("Data storage: {.path {(.sandbox_storage_label(store$data))}}")
    cli::cli_li("Data GitHub repo: {.val {cfg$repo_name}}")
    cli::cli_li("Data clone: {.path {env$local_path}}")
    cli::cli_end()

    answer <- readline("Type 'yes' to confirm: ")
    if (!identical(tolower(trimws(answer)), "yes")) {
      cli::cli_alert_info("Teardown cancelled.")
      return(invisible(FALSE))
    }
  }

  # ---- Delete data repo + clone --------------------------------------------
  if (!is.null(env$conn)) {
    tryCatch(
      datom::datom_repo_delete(env$conn, confirm = cfg$project_name),
      error = function(e) cli::cli_alert_danger("datom_repo_delete failed: {conditionMessage(e)}")
    )
  } else {
    # Fallback (e.g. after sandbox_recover with no conn): use gh + fs directly.
    tryCatch({
      .sandbox_check_gh()
      .sandbox_gh_repo_delete(
        .sandbox_repo_full_name(cfg, repo_url = store$data_repo_url),
        "data GitHub repo"
      )
    }, error = function(e) {
      cli::cli_alert_danger("Data GitHub repo deletion failed: {conditionMessage(e)}")
    })
    if (fs::dir_exists(env$local_path)) {
      fs::dir_delete(env$local_path)
      cli::cli_alert_success("Removed local data clone.")
    }
  }

  # ---- Wipe the data store namespace (caller-owned; not removed above) -----
  .sandbox_wipe_storage(store, "data")

  cli::cli_alert_success("Sandbox {.val {cfg$project_name}} torn down.")
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
#' Reconstructs the `env` object needed by `sandbox_down()` without re-creating
#' any infrastructure. Use this when you lost the R session before tearing down.
#' Rebuilds a conn from the local clone when present (so teardown can route
#' through `datom_repo_delete()`); otherwise teardown falls back to gh + fs.
#'
#' @param store A `datom_store` object.
#' @param ... Override any defaults from .sandbox_defaults() -- same args you
#'   originally passed to `sandbox_up()`.
#' @return A `datom_sandbox` object suitable for `sandbox_down()`.
sandbox_recover <- function(store, ...) {
  cfg <- utils::modifyList(.sandbox_defaults(), list(...))

  local_path <- fs::path(cfg$base_dir, cfg$repo_name)

  conn <- NULL
  if (fs::dir_exists(local_path)) {
    conn <- tryCatch(
      datom::datom_get_conn(path = as.character(local_path), store = store),
      error = function(e) {
        cli::cli_alert_info("Could not rebuild conn from clone: {conditionMessage(e)}")
        NULL
      }
    )
  }

  env <- list(
    config     = cfg,
    store      = store,
    local_path = as.character(local_path),
    conn       = conn,
    created_at = NA_real_
  )
  class(env) <- "datom_sandbox"

  cli::cli_alert_success("Recovered sandbox env for {.val {cfg$project_name}}.")
  cli::cli_ul()
  cli::cli_li("Git repo: {.path {local_path}}")
  cli::cli_li("Data: {.path {(.sandbox_storage_label(store$data))}}")
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

  cli::cli_h3("datom sandbox (solo)")
  cli::cli_ul()
  cli::cli_li("Project: {.val {cfg$project_name}}")
  cli::cli_li("Git repo: {.path {x$local_path}}")
  cli::cli_li("Data: {.path {(.sandbox_storage_label(store$data))}}")
  cli::cli_li("Governance: not attached")
  cli::cli_li("Age: {age}")
  if (!is.null(x$conn)) {
    cli::cli_li("Connection: available (env$conn)")
  }
  cli::cli_end()
  invisible(x)
}
