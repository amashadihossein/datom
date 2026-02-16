#' Read a tbit Table
#'
#' Unified read function with routing via `routing.json`. Reads from S3
#' metadata cache for data readers.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param name Table name.
#' @param version Optional metadata_sha (tbit version). If NULL, uses current.
#' @param context Optional context for routing (e.g., "default", "cached").
#' @param ... Additional parameters forwarded to routed function.
#'
#' @return Data frame or routed function result.
#' @export
tbit_read <- function(conn,
                      name,
                      version = NULL,
                      context = NULL,
                      ...) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls tbit_conn} object from {.fn tbit_get_conn}.")
  }

  .tbit_validate_name(name)

  # 1. Read metadata + version history from S3
  metadata_list <- .tbit_read_metadata(conn, name)

  # 2. Resolve version to data_sha

  data_sha <- .tbit_resolve_version(metadata_list, version = version, name = name)

  # 3. Download and read parquet
  # TODO: Phase 6 will add routing via context + routing.json
  .tbit_read_parquet(conn, name, data_sha)
}


# --- Read infrastructure ------------------------------------------------------

#' Read Table Metadata from S3
#'
#' Fetches both `metadata.json` (current state) and `version_history.json`
#' (version index) for a given table from S3.
#'
#' @param conn A `tbit_conn` object.
#' @param name Table name (validated).
#' @return Named list with `current` (metadata.json contents) and
#'   `history` (version_history.json contents as a list of entries).
#' @keywords internal
.tbit_read_metadata <- function(conn, name) {
  .tbit_validate_name(name)

  metadata_key <- paste0(name, "/.metadata/metadata.json")
  history_key <- paste0(name, "/.metadata/version_history.json")

  current <- .tbit_s3_read_json(conn, metadata_key)
  history <- .tbit_s3_read_json(conn, history_key)

  list(current = current, history = history)
}


#' Resolve Version to data_sha
#'
#' Given metadata from [.tbit_read_metadata()], resolves a version spec
#' to the corresponding `data_sha`. If `version` is NULL, returns the
#' current `data_sha` from `metadata.json`. If a metadata_sha string,
#' looks it up in `version_history.json`.
#'
#' @param metadata_list Return value of [.tbit_read_metadata()].
#' @param version NULL (current) or a metadata_sha string.
#' @param name Table name (for error messages).
#' @return Character string `data_sha`.
#' @keywords internal
.tbit_resolve_version <- function(metadata_list, version = NULL, name = "table") {
  if (is.null(version)) {
    data_sha <- metadata_list$current$data_sha
    if (is.null(data_sha) || !nzchar(data_sha)) {
      cli::cli_abort(
        c(
          "metadata.json for {.val {name}} has no {.field data_sha}.",
          "i" = "The metadata may be corrupt or the table has no data."
        )
      )
    }
    return(data_sha)
  }

  if (!is.character(version) || length(version) != 1L || !nzchar(version)) {
    cli::cli_abort("{.arg version} must be a single non-empty string or NULL.")
  }

  # Look up version (metadata_sha) in history
  history <- metadata_list$history
  if (!is.list(history) || length(history) == 0L) {
    cli::cli_abort(
      c(
        "No version history found for {.val {name}}.",
        "i" = "version_history.json is empty or missing."
      )
    )
  }

  # history is a list of entries; each has $version and $data_sha
  match_idx <- purrr::detect_index(history, ~ identical(.x$version, version))

  if (match_idx == 0L) {
    cli::cli_abort(
      c(
        "Version {.val {version}} not found in history for {.val {name}}.",
        "i" = "Use {.fn tbit_history} to see available versions."
      )
    )
  }

  data_sha <- history[[match_idx]]$data_sha
  if (is.null(data_sha) || !nzchar(data_sha)) {
    cli::cli_abort(
      c(
        "Version {.val {version}} has no {.field data_sha} in history.",
        "i" = "The version_history.json entry may be corrupt."
      )
    )
  }

  data_sha
}


#' Download and Read Parquet from S3
#'
#' Downloads `{table}/{data_sha}.parquet` from S3 to a temporary file
#' and reads it via `arrow::read_parquet()`.
#'
#' @param conn A `tbit_conn` object.
#' @param name Table name.
#' @param data_sha SHA identifying the parquet file.
#' @return Data frame.
#' @keywords internal
.tbit_read_parquet <- function(conn, name, data_sha) {
  .tbit_validate_name(name)

  if (!is.character(data_sha) || length(data_sha) != 1L || !nzchar(data_sha)) {
    cli::cli_abort("{.arg data_sha} must be a single non-empty string.")
  }

  s3_key <- paste0(name, "/", data_sha, ".parquet")
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  .tbit_s3_download(conn, s3_key, tmp)

  arrow::read_parquet(tmp)
}


# --- Write infrastructure -----------------------------------------------------

#' Build Metadata Object
#'
#' Constructs the metadata list for a table write, including auto-computed
#' fields (data_sha, dimensions, colnames, timestamp, tbit_version) and
#' any user-supplied custom metadata.
#'
#' @param data Data frame being written.
#' @param data_sha SHA-256 of the parquet-formatted data.
#' @param custom Optional named list of user-supplied custom metadata.
#' @return Named list suitable for writing as metadata.json.
#' @keywords internal
.tbit_build_metadata <- function(data, data_sha, custom = NULL) {
  meta <- list(
    data_sha = data_sha,
    nrow = nrow(data),
    ncol = ncol(data),
    colnames = names(data),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    tbit_version = as.character(utils::packageVersion("tbit"))
  )

  if (!is.null(custom)) {
    if (!is.list(custom) || is.null(names(custom))) {
      cli::cli_abort("{.arg metadata} must be a named list.")
    }
    meta$custom <- custom
  }

  meta
}


#' Detect Changes Against Current Metadata
#'
#' Compares the proposed metadata_sha against the current version in S3.
#' Returns the type of change detected.
#'
#' @param conn A `tbit_conn` object.
#' @param name Table name.
#' @param new_data_sha SHA of the new data.
#' @param new_metadata_sha SHA of the new metadata (from `.tbit_compute_metadata_sha()`).
#' @return Character string: `"none"` (no change), `"metadata_only"` (data same,
#'   metadata changed), or `"full"` (data changed).
#' @keywords internal
.tbit_has_changes <- function(conn, name, new_data_sha, new_metadata_sha) {
  metadata_key <- paste0(name, "/.metadata/metadata.json")

  # If metadata doesn't exist yet, it's a new table → full write

  if (!.tbit_s3_exists(conn, metadata_key)) {
    return("full")
  }

  current <- .tbit_s3_read_json(conn, metadata_key)
  current_metadata_sha <- .tbit_compute_metadata_sha(current)

  if (identical(current_metadata_sha, new_metadata_sha)) {
    return("none")
  }

  if (identical(current$data_sha, new_data_sha)) {
    return("metadata_only")
  }

  "full"
}


#' Write Metadata Files to Git and S3
#'
#' Writes `metadata.json` and appends to `version_history.json` in both
#' the local git repo and S3. Does NOT commit or push — the caller handles that.
#'
#' @param conn A `tbit_conn` object (must be developer with path).
#' @param name Table name.
#' @param metadata Named list for metadata.json.
#' @param metadata_sha SHA of the metadata (the tbit "version").
#' @param message Commit message (stored in version_history entry).
#' @return Invisible list with metadata_sha and paths written.
#' @keywords internal
.tbit_write_metadata <- function(conn, name, metadata, metadata_sha, message = NULL) {
  # --- Write to git repo (local) ---
  repo_path <- conn$path
  table_dir <- fs::path(repo_path, name)
  fs::dir_create(table_dir)

  # metadata.json — current state
  metadata_path <- fs::path(table_dir, "metadata.json")
  jsonlite::write_json(metadata, metadata_path, auto_unbox = TRUE, pretty = TRUE)

  # version_history.json — append new entry
  history_path <- fs::path(table_dir, "version_history.json")

  history <- if (fs::file_exists(history_path)) {
    jsonlite::read_json(history_path)
  } else {
    list()
  }

  author <- tryCatch(
    .tbit_git_author(repo_path),
    error = function(e) "unknown"
  )

  new_entry <- list(
    version = metadata_sha,
    data_sha = metadata$data_sha,
    timestamp = metadata$created_at,
    author = author,
    commit_message = message %||% paste0("Update ", name)
  )

  history <- c(list(new_entry), history)
  jsonlite::write_json(history, history_path, auto_unbox = TRUE, pretty = TRUE)

  # --- Write to S3 ---
  s3_metadata_key <- paste0(name, "/.metadata/metadata.json")
  s3_history_key <- paste0(name, "/.metadata/version_history.json")
  s3_versioned_key <- paste0(name, "/.metadata/", metadata_sha, ".json")

  .tbit_s3_write_json(conn, s3_metadata_key, metadata)
  .tbit_s3_write_json(conn, s3_history_key, history)
  .tbit_s3_write_json(conn, s3_versioned_key, metadata)

  invisible(list(
    metadata_sha = metadata_sha,
    git_paths = c(metadata_path, history_path),
    s3_keys = c(s3_metadata_key, s3_history_key, s3_versioned_key)
  ))
}


#' Write a tbit Table
#'
#' Writes data to a tbit repository. Commits to git, pushes, and syncs to S3.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param data Data frame to write. If NULL with name, does metadata-only sync.
#' @param name Table name. If NULL with NULL data, aliases to
#'   [tbit_sync_routing()].
#' @param metadata Optional list of custom metadata.
#' @param message Optional commit message.
#'
#' @return List with deployment details.
#' @export
tbit_write <- function(conn,
                       data = NULL,
                       name = NULL,
                       metadata = NULL,
                       message = NULL) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # Route based on arguments

  if (is.null(data) && is.null(name)) {
    return(tbit_sync_routing(conn))
  }

  if (is.null(data) && !is.null(name)) {
    return(.tbit_sync_metadata(conn, name))
  }

  if (!is.data.frame(data)) {
    cli::cli_abort("data must be a data frame")
  }

  # TODO: Implement normal write
  stop("Not yet implemented")
}
