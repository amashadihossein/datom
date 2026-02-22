# dev/dev-sandbox.R
# ──────────────────────────────────────────────────────────────────────────────
# Developer sandbox: stand up and tear down a complete tbit data product
# infrastructure (GitHub repo + S3 namespace + local repo) in one call.
#
# Usage:
#   source("dev/dev-sandbox.R")
#   env <- sandbox_up()      # creates everything, returns connection info
#   # ... work / test ...
#   sandbox_down(env)         # tears down everything
#   sandbox_reset(env)        # down + up (same config)
#
# Prerequisites:
#   - `gh` CLI installed and authenticated (https://cli.github.com)
#   - AWS credentials set: TBIT_{PROJECT}_ACCESS_KEY_ID / SECRET_ACCESS_KEY
#   - GITHUB_PAT set
#   - tbit loaded (devtools::load_all())
#
# All defaults are overridable. Adjust .sandbox_defaults() for your setup.
# ──────────────────────────────────────────────────────────────────────────────

# --- Configuration -----------------------------------------------------------

#' Default sandbox configuration
#'
#' Edit these values once to match your dev environment. Every sandbox_*
#' function pulls from here unless overridden.
.sandbox_defaults <- function() {
  list(
    project_name = "SANDBOX_TEST",
    github_org    = NULL,            # NULL = personal repo; set to "my-org" for org repos
    repo_name     = "tbit-sandbox",  # GitHub repo name
    bucket        = "tbit-test",           # REQUIRED — your dev S3 bucket
    prefix        = "sandbox/",      # S3 prefix (keeps sandbox isolated)
    region        = "us-east-1",
    base_dir      = fs::path_abs("../tbit-test"),  # sibling of tbit project
    populate      = TRUE,            # seed with example data?
    n_months      = 2L               # how many monthly snapshots to sync
  )
}

# --- Helpers -----------------------------------------------------------------

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
  #browser()
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

.sandbox_repo_full_name <- function(cfg) {
  if (!is.null(cfg$github_org) && nzchar(cfg$github_org)) {
    paste0(cfg$github_org, "/", cfg$repo_name)
  } else {
    # Personal repo — gh uses the authenticated user
    cfg$repo_name
  }
}

.sandbox_remote_url <- function(cfg) {
  # Determine the owner (org or authenticated user)
  if (!is.null(cfg$github_org) && nzchar(cfg$github_org)) {
    owner <- cfg$github_org
  } else {
    # Query gh for authenticated user
    res <- .sandbox_gh("api", "user", "--jq", ".login")
    owner <- trimws(res$output[[1]])
  }
  paste0("https://github.com/", owner, "/", cfg$repo_name, ".git")
}

# --- S3 cleanup --------------------------------------------------------------

#' Delete all objects under the sandbox S3 prefix
#'
#' Uses paws.storage directly (no aws CLI dependency). Lists all objects
#' under prefix/tbit/ and deletes them in batches of 1000.
.sandbox_wipe_s3 <- function(cfg) {
  cred_names <- tbit:::.tbit_derive_cred_names(cfg$project_name)
  s3 <- tbit:::.tbit_s3_client(cred_names, region = cfg$region)

  full_prefix <- paste0(
    if (!is.null(cfg$prefix)) paste0(gsub("/+$", "", cfg$prefix), "/") else "",
    "tbit/"
  )

  cli::cli_alert_info("Listing S3 objects under {.val {cfg$bucket}/{full_prefix}}...")

  all_keys <- character()
  continuation <- NULL
  repeat {
    args <- list(Bucket = cfg$bucket, Prefix = full_prefix, MaxKeys = 1000L)
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
    cli::cli_alert_info("No S3 objects found. Nothing to delete.")
    return(invisible(0L))
  }

  cli::cli_alert_warning("Deleting {length(all_keys)} S3 object{?s}...")

  # Delete in batches of 1000 (S3 limit)
  batches <- split(all_keys, ceiling(seq_along(all_keys) / 1000))
  for (batch in batches) {
    objects <- purrr::map(batch, ~ list(Key = .x))
    s3$delete_objects(
      Bucket = cfg$bucket,
      Delete = list(Objects = objects, Quiet = TRUE)
    )
  }

  cli::cli_alert_success("Deleted {length(all_keys)} S3 object{?s}.")
  invisible(length(all_keys))
}

# --- Core functions ----------------------------------------------------------

#' Stand up a sandbox tbit data product
#'
#' Creates a GitHub repo, runs tbit_init_repo(), and optionally populates
#' with example study data.
#'
#' @param ... Override any defaults from .sandbox_defaults().
#' @return A sandbox environment list (pass to sandbox_down/sandbox_reset).
sandbox_up <- function(...) {
  cfg <- utils::modifyList(.sandbox_defaults(), list(...))

  if (is.null(cfg$bucket) || !nzchar(cfg$bucket)) {
    cli::cli_abort(c(
      "{.arg bucket} is required.",
      "i" = "Set it in {.fn .sandbox_defaults} or pass {.code bucket = \"my-bucket\"} to {.fn sandbox_up}."
    ))
  }

  .sandbox_check_gh()

  local_path <- fs::path(cfg$base_dir, cfg$repo_name)

  cli::cli_h2("Sandbox Up: {.val {cfg$project_name}}")

  # 1. Create GitHub repo
  cli::cli_alert_info("Creating GitHub repo {.val {cfg$repo_name}}...")

  create_args <- c("repo", "create", .sandbox_repo_full_name(cfg), "--private")
  # Check if repo already exists
  view_result <- .sandbox_gh("repo", "view", .sandbox_repo_full_name(cfg),
                              "--json", "name", error_on_fail = FALSE)
  if (view_result$status == 0L) {
    cli::cli_alert_warning("GitHub repo {.val {cfg$repo_name}} already exists. Reusing.")
  } else {
    .sandbox_gh(create_args)
    cli::cli_alert_success("Created GitHub repo {.val {cfg$repo_name}}.")
  }

  remote_url <- .sandbox_remote_url(cfg)

  # 2. Clean up local path if it exists

  if (fs::dir_exists(local_path)) {
    cli::cli_alert_warning("Local path {.path {local_path}} exists. Removing.")
    fs::dir_delete(local_path)
  }

  # 3. Initialize tbit repo
  cli::cli_alert_info("Initializing tbit repo at {.path {local_path}}...")

  tbit::tbit_init_repo(
    path         = local_path,
    project_name = cfg$project_name,
    remote_url   = remote_url,
    bucket       = cfg$bucket,
    prefix       = cfg$prefix,
    region       = cfg$region
  )

  cli::cli_alert_success("tbit repo initialized and pushed.")

  # 4. Optionally populate with example data
  conn <- NULL
  if (isTRUE(cfg$populate)) {
    cli::cli_alert_info("Populating with example data ({cfg$n_months} month{?s})...")

    conn <- tbit::tbit_get_conn(path = local_path)
    cutoffs <- tbit::tbit_example_cutoffs()
    n <- min(cfg$n_months, length(cutoffs))

    for (i in seq_len(n)) {
      cutoff <- cutoffs[i]
      month_label <- names(cutoffs)[i]

      cli::cli_alert_info("Syncing {.val {month_label}} (cutoff: {cutoff})...")

      dm <- tbit::tbit_example_data("dm", cutoff_date = cutoff)
      ex <- tbit::tbit_example_data("ex", cutoff_date = cutoff)

      input_dir <- fs::path(local_path, "input_files")
      write.csv(dm, fs::path(input_dir, "dm.csv"), row.names = FALSE)
      write.csv(ex, fs::path(input_dir, "ex.csv"), row.names = FALSE)

      manifest <- tbit::tbit_sync_manifest(conn)
      if (any(manifest$status %in% c("new", "changed"))) {
        tbit::tbit_sync(conn, manifest, continue_on_error = FALSE)
      } else {
        cli::cli_alert_info("No changes for {.val {month_label}}. Skipping.")
      }
    }

    cli::cli_alert_success("Populated {n} month{?s} of example data.")
  }

  # 5. Build the environment object
  env <- list(
    config     = cfg,
    local_path = as.character(local_path),
    remote_url = remote_url,
    conn       = conn,
    created_at = Sys.time()
  )

  class(env) <- "tbit_sandbox"

  cli::cli_h3("Sandbox ready")
  cli::cli_ul()
  cli::cli_li("Local: {.path {local_path}}")
  cli::cli_li("Remote: {.url {remote_url}}")
  cli::cli_li("S3: s3://{cfg$bucket}/{cfg$prefix}tbit/")
  cli::cli_end()

  invisible(env)
}


#' Tear down a sandbox tbit data product
#'
#' Deletes S3 objects, GitHub repo, and local directory.
#'
#' @param env Sandbox environment from sandbox_up().
#' @param confirm If TRUE (default in interactive), asks before destroying.
sandbox_down <- function(env, confirm = interactive()) {
  if (!inherits(env, "tbit_sandbox")) {
    cli::cli_abort("{.arg env} must be a {.cls tbit_sandbox} from {.fn sandbox_up}.")
  }

  cfg <- env$config

  cli::cli_h2("Sandbox Down: {.val {cfg$project_name}}")

  if (isTRUE(confirm)) {
    cli::cli_alert_danger("This will permanently delete:")
    cli::cli_ul()
    cli::cli_li("S3: s3://{cfg$bucket}/{cfg$prefix}tbit/ (all objects)")
    cli::cli_li("GitHub: {.val {cfg$repo_name}}")
    cli::cli_li("Local: {.path {env$local_path}}")
    cli::cli_end()

    answer <- readline("Type 'yes' to confirm: ")
    if (!identical(tolower(trimws(answer)), "yes")) {
      cli::cli_alert_info("Teardown cancelled.")
      return(invisible(FALSE))
    }
  }

  # 1. Wipe S3
  tryCatch({
    .sandbox_wipe_s3(cfg)
  }, error = function(e) {
    cli::cli_alert_danger("S3 cleanup failed: {conditionMessage(e)}")
    cli::cli_alert_info("Continuing with remaining teardown...")
  })

  # 2. Delete GitHub repo
  tryCatch({
    cli::cli_alert_info("Deleting GitHub repo {.val {cfg$repo_name}}...")
    .sandbox_gh("repo", "delete", .sandbox_repo_full_name(cfg), "--yes")
    cli::cli_alert_success("Deleted GitHub repo.")
  }, error = function(e) {
    cli::cli_alert_danger("GitHub repo deletion failed: {conditionMessage(e)}")
    cli::cli_alert_info("You may need to delete it manually.")
  })

  # 3. Delete local directory
  if (fs::dir_exists(env$local_path)) {
    cli::cli_alert_info("Removing local directory {.path {env$local_path}}...")
    fs::dir_delete(env$local_path)
    cli::cli_alert_success("Removed local directory.")
  }

  cli::cli_alert_success("Sandbox {.val {cfg$project_name}} torn down.")
  invisible(TRUE)
}


#' Reset a sandbox (tear down + stand up with same config)
#'
#' @param env Sandbox environment from sandbox_up().
#' @param confirm If TRUE (default in interactive), asks before destroying.
#' @return New sandbox environment.
sandbox_reset <- function(env, confirm = interactive()) {
  if (!inherits(env, "tbit_sandbox")) {
    cli::cli_abort("{.arg env} must be a {.cls tbit_sandbox} from {.fn sandbox_up}.")
  }

  cli::cli_h2("Sandbox Reset: {.val {env$config$project_name}}")

  sandbox_down(env, confirm = confirm)
  do.call(sandbox_up, env$config)
}


#' Print method for sandbox environment
#' @export
print.tbit_sandbox <- function(x, ...) {
  cfg <- x$config
  age <- round(difftime(Sys.time(), x$created_at, units = "mins"), 1)

  cli::cli_h3("tbit sandbox")
  cli::cli_ul()
  cli::cli_li("Project: {.val {cfg$project_name}}")
  cli::cli_li("Local: {.path {x$local_path}}")
  cli::cli_li("Remote: {.url {x$remote_url}}")
  cli::cli_li("S3: s3://{cfg$bucket}/{cfg$prefix}tbit/")
  cli::cli_li("Age: {age} minutes")
  if (!is.null(x$conn)) {
    cli::cli_li("Connection: available (env$conn)")
  }
  cli::cli_end()
  invisible(x)
}
