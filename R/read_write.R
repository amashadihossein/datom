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
  # Support prefix matching (like git short SHAs)
  match_indices <- which(purrr::map_lgl(
    history, ~ startsWith(.x$version %||% "", version)
  ))

  if (length(match_indices) == 0L) {
    cli::cli_abort(
      c(
        "Version {.val {version}} not found in history for {.val {name}}.",
        "i" = "Use {.fn tbit_history} to see available versions."
      )
    )
  }

  if (length(match_indices) > 1L) {
    cli::cli_abort(
      c(
        "Version prefix {.val {version}} is ambiguous for {.val {name}}.",
        "i" = "It matches {length(match_indices)} versions. Use a longer prefix.",
        "i" = "Use {.fn tbit_history} to see available versions."
      )
    )
  }

  match_idx <- match_indices[[1L]]

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


#' Write Metadata Files Locally
#'
#' Writes `metadata.json` and appends to `version_history.json` in the local
#' git repo. Does NOT commit, push, or touch S3 — the caller handles those.
#'
#' @param conn A `tbit_conn` object (must be developer with path).
#' @param name Table name.
#' @param metadata Named list for metadata.json.
#' @param metadata_sha SHA of the metadata (the tbit "version").
#' @param message Commit message (stored in version_history entry).
#' @return Invisible list with metadata_sha and local paths written.
#' @keywords internal
.tbit_write_metadata_local <- function(conn, name, metadata, metadata_sha, message = NULL) {
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

  invisible(list(
    metadata_sha = metadata_sha,
    git_paths = c(metadata_path, history_path)
  ))
}


#' Push Metadata Files to S3
#'
#' Uploads `metadata.json`, `version_history.json`, and a versioned snapshot
#' to S3. Called AFTER git commit+push succeeds to maintain local → git → S3
#' ordering.
#'
#' @param conn A `tbit_conn` object.
#' @param name Table name.
#' @param metadata Named list for metadata.json.
#' @param metadata_sha SHA of the metadata (the tbit "version").
#' @return Invisible character vector of S3 keys written.
#' @keywords internal
.tbit_push_metadata_s3 <- function(conn, name, metadata, metadata_sha) {
  # Read local version_history.json (written by .tbit_write_metadata_local)
  history_path <- fs::path(conn$path, name, "version_history.json")
  history <- if (fs::file_exists(history_path)) {
    jsonlite::read_json(history_path)
  } else {
    list()
  }

  s3_metadata_key <- paste0(name, "/.metadata/metadata.json")
  s3_history_key <- paste0(name, "/.metadata/version_history.json")
  s3_versioned_key <- paste0(name, "/.metadata/", metadata_sha, ".json")

  .tbit_s3_write_json(conn, s3_metadata_key, metadata)
  .tbit_s3_write_json(conn, s3_history_key, history)
  .tbit_s3_write_json(conn, s3_versioned_key, metadata)

  invisible(c(s3_metadata_key, s3_history_key, s3_versioned_key))
}


#' Write Metadata Files to Git and S3 (Legacy Wrapper)
#'
#' Calls [.tbit_write_metadata_local()] then [.tbit_push_metadata_s3()].
#' Kept for backward compatibility. Does NOT commit or push.
#'
#' @inheritParams .tbit_write_metadata_local
#' @return Invisible list with metadata_sha, git_paths, and s3_keys.
#' @keywords internal
.tbit_write_metadata <- function(conn, name, metadata, metadata_sha, message = NULL) {
  local_result <- .tbit_write_metadata_local(
    conn, name, metadata, metadata_sha, message = message
  )
  s3_keys <- .tbit_push_metadata_s3(conn, name, metadata, metadata_sha)

  invisible(list(
    metadata_sha = metadata_sha,
    git_paths = local_result$git_paths,
    s3_keys = s3_keys
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
    cli::cli_abort("{.arg data} must be a data frame.")
  }

  .tbit_validate_name(name)

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Write operations require {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Write operations require a local git repo path.",
      "i" = "Use {.fn tbit_get_conn} with a tbit-initialized repo."
    ))
  }

  # 1. Compute SHAs
  data_sha <- .tbit_compute_data_sha(data)
  meta <- .tbit_build_metadata(data, data_sha, custom = metadata)
  metadata_sha <- .tbit_compute_metadata_sha(meta)

  # 2. Change detection
  change_type <- .tbit_has_changes(conn, name, data_sha, metadata_sha)

  if (change_type == "none") {
    cli::cli_alert_info("No changes detected for {.val {name}}. Skipping write.")
    return(invisible(list(
      name = name,
      data_sha = data_sha,
      metadata_sha = metadata_sha,
      action = "none"
    )))
  }

  # 3. Write parquet to temp file (staged locally, not yet uploaded)
  tmp <- NULL
  if (change_type == "full") {
    tmp <- tempfile(fileext = ".parquet")
    on.exit(unlink(tmp), add = TRUE)
    arrow::write_parquet(data, tmp)
  }

  # 4. Write metadata locally
  write_result <- .tbit_write_metadata_local(
    conn, name, meta, metadata_sha,
    message = message
  )

  # 5. Git commit + push (must succeed before touching S3)
  git_files <- fs::path_rel(write_result$git_paths, conn$path)
  commit_msg <- message %||% paste0("Update ", name)
  commit_sha <- .tbit_git_commit(conn$path, git_files, commit_msg)
  .tbit_git_push(conn$path)

  # 6. Upload parquet to S3 (only after git succeeds)
  if (change_type == "full" && !is.null(tmp)) {
    parquet_key <- paste0(name, "/", data_sha, ".parquet")
    .tbit_s3_upload(conn, tmp, parquet_key)
  }

  # 7. Push metadata to S3 (final step — completes the round-trip)
  .tbit_push_metadata_s3(conn, name, meta, metadata_sha)

  cli::cli_alert_success(
    "Wrote {.val {name}} ({change_type}): {.val {substr(metadata_sha, 1, 8)}}"
  )

  invisible(list(
    name = name,
    data_sha = data_sha,
    metadata_sha = metadata_sha,
    action = change_type,
    commit_sha = commit_sha
  ))
}
