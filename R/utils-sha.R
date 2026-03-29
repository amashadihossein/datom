# Internal helpers for SHA computation and metadata operations

#' Compute SHA-256 of Data
#'
#' Computes a deterministic SHA-256 hash of a data frame by writing to
#' parquet format. By default, preserves column and row order — reordering
#' either will produce a different hash.
#'
#' @param data Data frame to hash.
#' @param sort_columns If TRUE, sorts columns alphabetically before hashing.
#'   Useful when column order shouldn't affect identity.
#' @param sort_rows If TRUE, sorts rows by all columns before hashing.
#'   Useful when row order shouldn't affect identity.
#' @return Character SHA-256 hash.
#' @keywords internal
.tbit_compute_data_sha <- function(data, sort_columns = FALSE, sort_rows = FALSE) {
  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame.")
  }

  if (ncol(data) == 0L || nrow(data) == 0L) {
    cli::cli_abort("{.arg data} must have at least one row and one column.")
  }

  prepared <- data

  if (sort_columns) {
    col_order <- sort(names(prepared))
    prepared <- prepared[, col_order, drop = FALSE]
  }

  if (sort_rows) {
    row_order <- do.call(order, prepared)
    prepared <- prepared[row_order, , drop = FALSE]
    rownames(prepared) <- NULL
  }

  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  arrow::write_parquet(prepared, tmp)
  digest::digest(file = tmp, algo = "sha256")
}


#' Compute SHA-256 of Metadata
#'
#' Sorts fields alphabetically before hashing for deterministic results,
#' regardless of field insertion order. Volatile fields (`created_at`,
#' `tbit_version`) are excluded so that identical semantic content always
#' produces the same SHA, regardless of when it was written.
#'
#' Hashes a JSON canonical form rather than the R object directly. This
#' ensures that metadata read back from JSON (e.g., from S3) produces the
#' same SHA as metadata built in-memory, despite R type differences
#' (integer vs double, character vector vs list) introduced by JSON
#' round-tripping.
#'
#' @param metadata Named list of metadata fields.
#' @return Character SHA-256 hash.
#' @keywords internal
.tbit_compute_metadata_sha <- function(metadata) {
  if (!is.list(metadata) || is.null(names(metadata))) {
    cli::cli_abort("{.arg metadata} must be a named list.")
  }

  # Exclude volatile fields that don't define content identity
  volatile <- c("created_at", "tbit_version")
  semantic <- metadata[setdiff(names(metadata), volatile)]

  sorted_names <- sort(names(semantic))
  sorted_metadata <- semantic[sorted_names]

  # JSON canonical form: type-agnostic (integer/double, vector/list all
  # serialise identically), so in-memory and S3-round-tripped metadata
  # always produce the same hash.
  canonical <- jsonlite::toJSON(sorted_metadata, auto_unbox = TRUE)
  digest::digest(canonical, algo = "sha256", serialize = FALSE)
}


#' Compute SHA-256 of File
#'
#' @param path Path to file.
#' @return Character SHA-256 hash.
#' @keywords internal
.tbit_compute_file_sha <- function(path) {
  path <- fs::path_abs(path)

  if (!fs::file_exists(path)) {
    cli::cli_abort("File not found: {.path {path}}")
  }

  digest::digest(file = path, algo = "sha256")
}


#' Sync Single Table Metadata to S3
#'
#' @param conn Connection object.
#' @param name Table name.
#' @return Summary of sync operation.
#' @keywords internal
.tbit_sync_metadata <- function(conn, name) {
  .tbit_validate_name(name)

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Metadata sync requires {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Metadata sync requires a local git repo path.",
      "i" = "Use {.fn tbit_get_conn} with a tbit-initialized repo."
    ))
  }

  repo_path <- conn$path
  table_dir <- fs::path(repo_path, name)

  # Pull before write to ensure fresh state (Phase 7)
  .tbit_git_pull(repo_path)

  metadata_path <- fs::path(table_dir, "metadata.json")
  if (!fs::file_exists(metadata_path)) {
    cli::cli_abort(c(
      "No metadata found for table {.val {name}}.",
      "i" = "Expected {.path {metadata_path}} to exist."
    ))
  }

  # Read metadata from git repo

  metadata <- jsonlite::read_json(metadata_path, simplifyVector = TRUE)
  metadata_sha <- .tbit_compute_metadata_sha(metadata)

  # Check for changes against S3
  change_type <- .tbit_has_changes(conn, name, metadata$data_sha, metadata_sha)

  if (change_type == "none") {
    cli::cli_alert_info("No metadata changes for {.val {name}}. Skipping sync.")
    return(invisible(list(
      name = name,
      metadata_sha = metadata_sha,
      action = "none"
    )))
  }

  # Git commit + push first (local → git → S3 ordering)
  history_path <- fs::path(table_dir, "version_history.json")

  git_files <- character()
  if (fs::file_exists(metadata_path)) {
    git_files <- c(git_files, fs::path_rel(metadata_path, repo_path))
  }
  if (fs::file_exists(history_path)) {
    git_files <- c(git_files, fs::path_rel(history_path, repo_path))
  }

  commit_sha <- tryCatch(
    {
      sha <- .tbit_git_commit(repo_path, git_files, paste0("Sync metadata for ", name))
      .tbit_git_push(repo_path)
      sha
    },
    error = function(e) {
      cli::cli_abort(c(
        "Git commit/push failed for {.val {name}}. S3 sync aborted.",
        "x" = conditionMessage(e),
        "i" = "Resolve the git issue and re-run. S3 was not modified."
      ))
    }
  )

  # Sync metadata files to S3 (only after git succeeds)
  s3_metadata_key <- paste0(name, "/.metadata/metadata.json")
  .tbit_s3_write_json(conn, s3_metadata_key, metadata)

  s3_keys <- s3_metadata_key

  # Sync version_history.json if it exists locally
  if (fs::file_exists(history_path)) {
    history <- jsonlite::read_json(history_path)
    s3_history_key <- paste0(name, "/.metadata/version_history.json")
    .tbit_s3_write_json(conn, s3_history_key, history)
    s3_keys <- c(s3_keys, s3_history_key)
  }

  cli::cli_alert_success("Synced metadata for {.val {name}} to S3.")

  invisible(list(
    name = name,
    metadata_sha = metadata_sha,
    action = change_type,
    s3_keys = s3_keys,
    commit_sha = commit_sha
  ))
}


#' Abbreviate SHA Hash
#'
#' Truncates a SHA-256 hash to a short prefix for display. Accepts
#' character vectors; `NA` values pass through unchanged.
#'
#' @param sha Character vector of SHA hashes.
#' @param n Number of characters to keep. Default 8.
#' @return Character vector of abbreviated hashes.
#' @keywords internal
.tbit_abbreviate_sha <- function(sha, n = 8L) {
  if (!is.character(sha)) return(sha)
  ifelse(is.na(sha), NA_character_, substr(sha, 1L, n))
}
