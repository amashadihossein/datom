#' Pull Latest Changes from Remote
#'
#' Fetches and merges the latest git changes from the remote repository.
#' This is the recommended entry point at the start of each work session
#' to ensure the local state is current before syncing or writing tables.
#'
#' Git is the source of truth for all metadata (manifest, dispatch, table
#' metadata). The manifest and other metadata files live in git and are
#' pulled along with any other committed changes.
#'
#' Requires developer role (readers have no git access).
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#'
#' @return Invisibly, a list with:
#'   \describe{
#'     \item{`commits_pulled`}{Integer count of new commits merged.}
#'     \item{`branch`}{Current branch name.}
#'   }
#'
#' @examples
#' \dontrun{
#' conn <- datom_get_conn("path/to/repo")
#' datom_pull(conn)
#' #> ✔ Pulled 2 commits on main.
#' }
#' @export
datom_pull <- function(conn) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Pull requires {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Pull requires a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  repo_path <- conn$path

  # Record HEAD SHA before pulling
  repo <- git2r::repository(repo_path)
  head_before <- as.character(git2r::revparse_single(repo, "HEAD")$sha)
  branch_name <- .datom_git_branch(repo_path)

  # Git pull (fetch + merge)
  .datom_git_pull(repo_path)

  # Count commits pulled by comparing HEAD before/after
  head_after <- as.character(git2r::revparse_single(repo, "HEAD")$sha)
  commits_pulled <- 0L
  if (!identical(head_before, head_after)) {
    commits_pulled <- tryCatch({
      ab <- git2r::ahead_behind(
        git2r::revparse_single(repo, head_before),
        git2r::revparse_single(repo, "HEAD")
      )
      as.integer(ab[[2]])  # how far old HEAD is behind new HEAD
    }, error = function(e) NA_integer_)
  }

  if (is.na(commits_pulled) || commits_pulled > 0L) {
    n_msg <- if (is.na(commits_pulled)) "new" else commits_pulled
    cli::cli_alert_success("Pulled {n_msg} commit{?s} on {.val {branch_name}} (data repo).")
  } else {
    cli::cli_alert_info("Already up to date on {.val {branch_name}} (data repo).")
  }

  # --- Pull gov repo when gov_local_path is set ------------------------------
  gov_result <- NULL
  if (!is.null(conn$gov_local_path) && nzchar(conn$gov_local_path)) {
    gov_result <- tryCatch({
      .datom_gov_pull(conn)
      cli::cli_alert_success("Gov repo up to date.")
      list(pulled = TRUE)
    }, error = function(e) {
      cli::cli_alert_warning("Gov pull failed: {conditionMessage(e)}")
      list(pulled = FALSE, error = conditionMessage(e))
    })
  }

  invisible(list(
    commits_pulled = commits_pulled,
    branch = branch_name,
    gov = gov_result
  ))
}


#' Pull Latest Changes from the Governance Repo
#'
#' Fetches and merges upstream changes into the local governance clone.
#' Useful when you need to refresh governance metadata (dispatch, ref,
#' migration history) without touching the data repo.
#'
#' In normal workflows `datom_pull()` handles both repos. Use this only when
#' you need the gov clone to be current independently.
#'
#' Requires a developer connection with `gov_local_path` set.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#'
#' @return Invisibly, the result of the pull.
#' @export
datom_pull_gov <- function(conn) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Gov pull requires {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$gov_local_path) || !nzchar(conn$gov_local_path)) {
    cli::cli_abort(c(
      "Gov pull requires a local gov clone path.",
      "i" = "Set {.arg gov_local_path} in {.fn datom_store} to use this function."
    ))
  }

  result <- .datom_gov_pull(conn)
  cli::cli_alert_success("Gov repo up to date.")
  invisible(result)
}


#' Sync Dispatch Metadata to S3
#'
#' Updates all metadata in S3 to match the local git repository. This includes
#' repo-level files (dispatch.json, manifest.json, migration_history.json) and
#' per-table metadata (metadata.json, version_history.json). Requires
#' interactive confirmation unless `.confirm = FALSE`.
#'
#' Used after migration, dispatch changes, or any situation where S3 metadata
#' may be out of sync with git.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param .confirm If `TRUE` (default), requires interactive confirmation
#'   before proceeding. Set to `FALSE` for non-interactive use.
#'
#' @return Invisibly, a list with `repo_files` (character vector of uploaded
#'   repo-level keys) and `tables` (list of per-table sync results).
#' @export
datom_sync_dispatch <- function(conn, .confirm = TRUE) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Sync dispatch requires {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Sync dispatch requires a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # Discover tables from git repo (directories with metadata.json)
  repo_path <- conn$path
  table_dirs <- fs::dir_ls(repo_path, type = "directory")
  table_dirs <- table_dirs[!grepl("^\\.", fs::path_file(table_dirs))]
  table_dirs <- table_dirs[!fs::path_file(table_dirs) %in%
    c("input_files", "renv", "man", "R", "tests", "vignettes", "src")]

  table_names <- fs::path_file(table_dirs)
  table_names <- table_names[purrr::map_lgl(table_dirs, function(d) {
    fs::file_exists(fs::path(d, "metadata.json"))
  })]

  s3_location <- paste0("s3://", conn$root, "/", conn$prefix %||% "", "datom/")

  # Interactive confirmation

  if (isTRUE(.confirm)) {
    if (!interactive()) {
      cli::cli_abort(c(
        "Interactive confirmation required.",
        "i" = "Use {.code .confirm = FALSE} for non-interactive use."
      ))
    }

    cli::cli_alert_warning(
      "This will update dispatch metadata for {length(table_names)} table{?s}."
    )
    cli::cli_alert_info("Current location: {.url {s3_location}}")

    answer <- readline("Proceed? [y/N] ")
    if (!tolower(answer) %in% c("y", "yes")) {
      cli::cli_alert_info("Sync cancelled.")
      return(invisible(list(repo_files = character(), tables = list())))
    }
  }

  # --- Sync repo-level files ---
  # dispatch.json + migration_history.json → governance store

  # manifest.json → data store
  repo_files_synced <- character()
  gov_conn <- .datom_gov_conn(conn)

  governance_files <- list(
    dispatch.json = fs::path(repo_path, ".datom", "dispatch.json"),
    ref.json = fs::path(repo_path, ".datom", "ref.json"),
    migration_history.json = fs::path(repo_path, ".datom", "migration_history.json")
  )

  data_files <- list(
    manifest.json = fs::path(repo_path, ".datom", "manifest.json")
  )

  for (fname in names(governance_files)) {
    local_path <- governance_files[[fname]]
    if (fs::file_exists(local_path)) {
      data <- jsonlite::read_json(local_path)
      s3_key <- paste0(".metadata/", fname)
      .datom_storage_write_json(gov_conn, s3_key, data)
      repo_files_synced <- c(repo_files_synced, s3_key)
    }
  }

  for (fname in names(data_files)) {
    local_path <- data_files[[fname]]
    if (fs::file_exists(local_path)) {
      data <- jsonlite::read_json(local_path)
      s3_key <- paste0(".metadata/", fname)
      .datom_storage_write_json(conn, s3_key, data)
      repo_files_synced <- c(repo_files_synced, s3_key)
    }
  }

  cli::cli_alert_success(
    "Synced {length(repo_files_synced)} repo-level file{?s} to S3."
  )

  # --- Sync per-table metadata ---
  table_results <- purrr::map(table_names, function(tbl) {
    tryCatch({
      .datom_sync_table_metadata(conn, tbl)
    }, error = function(e) {
      cli::cli_alert_danger("Failed to sync {.val {tbl}}: {conditionMessage(e)}")
      list(name = tbl, action = "error", error = conditionMessage(e))
    })
  })
  names(table_results) <- table_names

  n_ok <- sum(purrr::map_chr(table_results, ~ .x$action %||% "error") != "error")
  n_err <- length(table_results) - n_ok

  cli::cli_alert_info(
    "Sync dispatch complete: {n_ok} table{?s} synced, {n_err} error{?s}."
  )

  invisible(list(
    repo_files = repo_files_synced,
    tables = table_results
  ))
}


#' Sync a single table's metadata files to S3
#' @noRd
.datom_sync_table_metadata <- function(conn, name) {
  repo_path <- conn$path
  table_dir <- fs::path(repo_path, name)

  s3_keys <- character()

  # metadata.json
  metadata_path <- fs::path(table_dir, "metadata.json")
  if (fs::file_exists(metadata_path)) {
    data <- jsonlite::read_json(metadata_path)
    s3_key <- paste0(name, "/.metadata/metadata.json")
    .datom_storage_write_json(conn, s3_key, data)
    s3_keys <- c(s3_keys, s3_key)
  }

  # version_history.json
  history_path <- fs::path(table_dir, "version_history.json")
  if (fs::file_exists(history_path)) {
    data <- jsonlite::read_json(history_path)
    s3_key <- paste0(name, "/.metadata/version_history.json")
    .datom_storage_write_json(conn, s3_key, data)
    s3_keys <- c(s3_keys, s3_key)
  }

  # Versioned metadata snapshots ({metadata_sha}.json)
  meta_dir <- fs::path(table_dir, ".metadata")
  if (fs::dir_exists(meta_dir)) {
    snapshot_files <- fs::dir_ls(meta_dir, glob = "*.json")
    for (snap in snapshot_files) {
      snap_name <- fs::path_file(snap)
      data <- jsonlite::read_json(snap)
      s3_key <- paste0(name, "/.metadata/", snap_name)
      .datom_storage_write_json(conn, s3_key, data)
      s3_keys <- c(s3_keys, s3_key)
    }
  }

  list(name = name, action = "synced", s3_keys = s3_keys)
}


#' Scan and Prepare Manifest for Sync
#'
#' Scans a flat `input_files/` directory and computes file SHAs. Compares
#' against the current `.datom/manifest.json` to detect new or changed files.
#' Returns a manifest data frame for review before calling [datom_sync()].
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param path Optional path to input files directory. Defaults to
#'   `input_files/` inside the repo.
#' @param pattern Glob pattern for file matching. Default `"*"`.
#'
#' @return Data frame with columns: name, file, format, file_sha, status
#'   (one of `"new"`, `"changed"`, `"unchanged"`).
#' @export
datom_sync_manifest <- function(conn,
                               path = NULL,
                               pattern = "*") {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Sync operations require {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Sync operations require a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # Resolve input directory
  input_dir <- if (is.null(path)) {
    fs::path(conn$path, "input_files")
  } else {
    fs::path_abs(path)
  }

  if (!fs::dir_exists(input_dir)) {
    cli::cli_abort(c(
      "Input directory not found: {.path {input_dir}}",
      "i" = "Create it and place source files inside."
    ))
  }

  # Validate flat directory (no subdirectories)
  subdirs <- fs::dir_ls(input_dir, type = "directory")
  if (length(subdirs) > 0L) {
    cli::cli_abort(c(
      "Input directory must be flat (no subdirectories).",
      "x" = "Found {length(subdirs)} subdirector{?y/ies}: {.path {fs::path_file(subdirs)}}"
    ))
  }

  # List files matching pattern
  all_files <- fs::dir_ls(input_dir, type = "file")
  if (pattern != "*") {
    rx <- utils::glob2rx(pattern)
    all_files <- all_files[grepl(rx, fs::path_file(all_files))]
  }

  if (length(all_files) == 0L) {
    cli::cli_alert_info("No files found in {.path {input_dir}} matching {.val {pattern}}.")
    return(data.frame(
      name = character(),
      file = character(),
      format = character(),
      file_sha = character(),
      status = character(),
      stringsAsFactors = FALSE
    ))
  }

  # Read current manifest (local git copy)
  manifest_path <- fs::path(conn$path, ".datom", "manifest.json")
  current_manifest <- if (fs::file_exists(manifest_path)) {
    jsonlite::read_json(manifest_path)
  } else {
    list(tables = list())
  }

  # Build manifest rows
  rows <- purrr::map(all_files, function(fp) {
    file_name <- fs::path_file(fp)
    table_name <- fs::path_ext_remove(file_name)
    file_format <- fs::path_ext(fp)
    file_sha <- .datom_compute_file_sha(fp)

    # Compare against current manifest
    existing <- current_manifest$tables[[table_name]]
    status <- if (is.null(existing)) {
      "new"
    } else if (!identical(existing$original_file_sha, file_sha)) {
      "changed"
    } else {
      "unchanged"
    }

    data.frame(
      name = table_name,
      file = as.character(fp),
      format = file_format,
      file_sha = file_sha,
      status = status,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, rows)
  rownames(result) <- NULL

  n_new <- sum(result$status == "new")
  n_changed <- sum(result$status == "changed")
  n_unchanged <- sum(result$status == "unchanged")

  cli::cli_alert_info(
    "Scanned {nrow(result)} file{?s}: {n_new} new, {n_changed} changed, {n_unchanged} unchanged."
  )

  result
}


#' Sync Files to datom Repository
#'
#' Processes new/changed files from a manifest produced by
#' [datom_sync_manifest()]. Imports each file via `rio::import()`, converts to
#' a data frame, and calls [datom_write()] to store as parquet in S3 with git
#' metadata. Updates the local `.datom/manifest.json` after each successful
#' write.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param manifest Data frame from [datom_sync_manifest()], with columns
#'   `name`, `file`, `format`, `file_sha`, `status`.
#' @param continue_on_error If `TRUE` (default), continues processing
#'   remaining tables when one fails. If `FALSE`, stops on first error.
#'
#' @return The manifest data frame augmented with `result` and `error` columns.
#'   `result` is `"success"`, `"skipped"`, or `"error"`.
#' @export
datom_sync <- function(conn,
                      manifest,
                      continue_on_error = TRUE) {

  # --- validation ---
  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Sync operations require {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Sync operations require a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  if (!is.data.frame(manifest)) {
    cli::cli_abort("{.arg manifest} must be a data frame from {.fn datom_sync_manifest}.")
  }

  required_cols <- c("name", "file", "format", "file_sha", "status")
  missing_cols <- setdiff(required_cols, names(manifest))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "Manifest missing required columns: {.val {missing_cols}}.",
      "i" = "Use {.fn datom_sync_manifest} to generate a valid manifest."
    ))
  }

  .datom_check_rio()

  # --- stale-state check ---
  .datom_check_git_current(conn$path)

  # --- filter to actionable rows ---
  actionable <- manifest$status %in% c("new", "changed")
  manifest$result <- ifelse(actionable, NA_character_, "skipped")
  manifest$error <- NA_character_

  n_todo <- sum(actionable)
  if (n_todo == 0L) {
    cli::cli_alert_info("All files unchanged. Nothing to sync.")
    return(manifest)
  }

  cli::cli_alert_info("Syncing {n_todo} table{?s}...")

  # --- process each actionable table ---
  todo_idx <- which(actionable)

  for (i in todo_idx) {
    tbl_name <- manifest$name[i]
    tbl_file <- manifest$file[i]
    tbl_format <- manifest$format[i]
    tbl_file_sha <- manifest$file_sha[i]

    tryCatch({
      # Import file → data frame
      data <- .datom_import_file(tbl_file, tbl_format)

      # Write via datom_write (handles manifest update internally)
      write_result <- datom_write(
        conn,
        data = data,
        name = tbl_name,
        message = paste0("Sync ", tbl_name, " (", manifest$status[i], ")"),
        .table_type = "imported",
        .original_file_sha = tbl_file_sha,
        .original_format = tbl_format
      )

      manifest$result[i] <- "success"

      cli::cli_alert_success("{.val {tbl_name}} synced ({manifest$status[i]}).")

    }, error = function(e) {
      manifest$result[i] <<- "error"
      manifest$error[i] <<- conditionMessage(e)

      if (continue_on_error) {
        cli::cli_alert_danger("Failed to sync {.val {tbl_name}}: {conditionMessage(e)}")
      } else {
        cli::cli_abort(c(
          "Failed to sync {.val {tbl_name}}.",
          "x" = conditionMessage(e),
          "i" = "Set {.code continue_on_error = TRUE} to skip failures."
        ))
      }
    })
  }

  # --- summary ---
  n_ok <- sum(manifest$result == "success", na.rm = TRUE)
  n_err <- sum(manifest$result == "error", na.rm = TRUE)
  n_skip <- sum(manifest$result == "skipped", na.rm = TRUE)

  cli::cli_alert_info(
    "Sync complete: {n_ok} succeeded, {n_err} failed, {n_skip} skipped."
  )

  manifest
}


# --- Internal helpers for datom_sync -------------------------------------------

#' Check rio availability
#' @noRd
.datom_check_rio <- function() {
  if (!requireNamespace("rio", quietly = TRUE)) {
    cli::cli_abort(c(
      "Package {.pkg rio} is required for file import during sync.",
      "i" = "Install with {.code install.packages(\"rio\")}"
    ))
  }
  invisible(TRUE)
}


#' Import a file to data frame via rio
#' @noRd
.datom_import_file <- function(file, format) {
  # Parquet goes through arrow directly (more reliable than rio for parquet)
  if (tolower(format) == "parquet") {
    return(arrow::read_parquet(file))
  }

  data <- rio::import(file)

  if (!is.data.frame(data)) {
    cli::cli_abort("Imported file {.path {file}} did not produce a data frame.")
  }

  data
}


#' Update a single table entry in local .datom/manifest.json
#' @noRd
.datom_update_manifest_entry <- function(conn, name, metadata_sha, data_sha,
                                        file_sha = NULL, format = NULL) {
  manifest_path <- fs::path(conn$path, ".datom", "manifest.json")
  fs::dir_create(fs::path_dir(manifest_path))

  manifest <- if (fs::file_exists(manifest_path)) {
    jsonlite::read_json(manifest_path)
  } else {
    list(project_name = conn$project_name, tables = list(), summary = list())
  }

  # Read size_bytes from local metadata.json (already written at this point)
  meta_path <- fs::path(conn$path, name, "metadata.json")
  size_bytes <- if (fs::file_exists(meta_path)) {
    m <- jsonlite::read_json(meta_path)
    as.integer(m$size_bytes %||% 0L)
  } else {
    0L
  }

  # Count versions from version_history.json
  vh_path <- fs::path(conn$path, name, "version_history.json")
  version_count <- if (fs::file_exists(vh_path)) {
    vh <- jsonlite::read_json(vh_path)
    length(vh)
  } else {
    1L
  }

  entry <- list(
    current_version = metadata_sha,
    current_data_sha = data_sha,
    last_updated = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    size_bytes = size_bytes,
    version_count = as.integer(version_count)
  )

  if (!is.null(file_sha)) entry$original_file_sha <- file_sha
  if (!is.null(format)) entry$original_format <- format

  manifest$tables[[name]] <- entry

  # Update summary
  manifest$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  manifest$summary <- list(
    total_tables = length(manifest$tables),
    total_size_bytes = sum(purrr::map_dbl(
      manifest$tables, ~ as.numeric(.x$size_bytes %||% 0L)
    )),
    total_versions = sum(purrr::map_int(
      manifest$tables, ~ as.integer(.x$version_count %||% 0L)
    ))
  )

  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)

  invisible(manifest)
}
