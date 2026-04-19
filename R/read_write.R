#' Read a datom Table
#'
#' Unified read function with dispatch via `dispatch.json`. Reads from S3
#' metadata cache for data readers.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param name Table name.
#' @param version Optional metadata_sha (datom version). If NULL, uses current.
#' @param context Optional context for dispatch (e.g., "default", "cached").
#' @param ... Additional parameters forwarded to routed function.
#'
#' @return Data frame or routed function result.
#' @export
datom_read <- function(conn,
                      name,
                      version = NULL,
                      context = NULL,
                      ...) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  .datom_validate_name(name)

  # 1. Read metadata + version history from S3
  metadata_list <- .datom_read_metadata(conn, name)

  # 2. Resolve version to data_sha

  data_sha <- .datom_resolve_version(metadata_list, version = version, name = name)

  # 3. Download and read parquet
  # TODO: Phase 6 will add dispatch via context + dispatch.json
  .datom_read_parquet(conn, name, data_sha)
}


# --- Read infrastructure ------------------------------------------------------

#' Read Table Metadata from S3
#'
#' Fetches both `metadata.json` (current state) and `version_history.json`
#' (version index) for a given table from S3.
#'
#' @param conn A `datom_conn` object.
#' @param name Table name (validated).
#' @return Named list with `current` (metadata.json contents) and
#'   `history` (version_history.json contents as a list of entries).
#' @keywords internal
.datom_read_metadata <- function(conn, name) {
  .datom_validate_name(name)

  metadata_key <- paste0(name, "/.metadata/metadata.json")
  history_key <- paste0(name, "/.metadata/version_history.json")

  current <- .datom_storage_read_json(conn, metadata_key)
  history <- .datom_storage_read_json(conn, history_key)

  list(current = current, history = history)
}


#' Resolve Version to data_sha
#'
#' Given metadata from [.datom_read_metadata()], resolves a version spec
#' to the corresponding `data_sha`. If `version` is NULL, returns the
#' current `data_sha` from `metadata.json`. If a metadata_sha string,
#' looks it up in `version_history.json`.
#'
#' @param metadata_list Return value of [.datom_read_metadata()].
#' @param version NULL (current) or a metadata_sha string.
#' @param name Table name (for error messages).
#' @return Character string `data_sha`.
#' @keywords internal
.datom_resolve_version <- function(metadata_list, version = NULL, name = "table") {
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
        "i" = "Use {.fn datom_history} to see available versions."
      )
    )
  }

  if (length(match_indices) > 1L) {
    cli::cli_abort(
      c(
        "Version prefix {.val {version}} is ambiguous for {.val {name}}.",
        "i" = "It matches {length(match_indices)} versions. Use a longer prefix.",
        "i" = "Use {.fn datom_history} to see available versions."
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
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param data_sha SHA identifying the parquet file.
#' @return Data frame.
#' @keywords internal
.datom_read_parquet <- function(conn, name, data_sha) {
  .datom_validate_name(name)

  if (!is.character(data_sha) || length(data_sha) != 1L || !nzchar(data_sha)) {
    cli::cli_abort("{.arg data_sha} must be a single non-empty string.")
  }

  s3_key <- paste0(name, "/", data_sha, ".parquet")
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  .datom_storage_download(conn, s3_key, tmp)

  arrow::read_parquet(tmp)
}


# --- Write infrastructure -----------------------------------------------------

#' Build Metadata Object
#'
#' Constructs the metadata list for a table write, including auto-computed
#' fields (data_sha, dimensions, colnames, timestamp, datom_version) and
#' any user-supplied custom metadata.
#'
#' @param data Data frame being written.
#' @param data_sha SHA-256 of the parquet-formatted data.
#' @param custom Optional named list of user-supplied custom metadata.
#' @param table_type `"derived"` (default, from `datom_write`) or `"imported"` (from `datom_sync`).
#' @param size_bytes Size of the parquet file in bytes. NULL if not yet computed.
#' @param parents Lineage list of parent entries (each with source, table, version),
#'   or NULL if no lineage recorded.
#' @return Named list suitable for writing as metadata.json.
#' @keywords internal
.datom_build_metadata <- function(data, data_sha, custom = NULL,
                                 table_type = "derived", size_bytes = NULL,
                                 parents = NULL) {
  if (!table_type %in% c("imported", "derived")) {
    cli::cli_abort("{.arg table_type} must be {.val imported} or {.val derived}.")
  }

  meta <- list(
    data_sha = data_sha,
    table_type = table_type,
    nrow = nrow(data),
    ncol = ncol(data),
    colnames = names(data),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    datom_version = as.character(utils::packageVersion("datom"))
  )

  if (!is.null(parents)) meta$parents <- parents
  if (!is.null(size_bytes)) meta$size_bytes <- size_bytes

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
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param new_data_sha SHA of the new data.
#' @param new_metadata_sha SHA of the new metadata (from `.datom_compute_metadata_sha()`).
#' @return Character string: `"none"` (no change), `"metadata_only"` (data same,
#'   metadata changed), or `"full"` (data changed).
#' @keywords internal
.datom_has_changes <- function(conn, name, new_data_sha, new_metadata_sha) {
  metadata_key <- paste0(name, "/.metadata/metadata.json")

  # If metadata doesn't exist yet, it's a new table → full write

  if (!.datom_storage_exists(conn, metadata_key)) {
    return("full")
  }

  current <- .datom_storage_read_json(conn, metadata_key)
  current_metadata_sha <- .datom_compute_metadata_sha(current)

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
#' @param conn A `datom_conn` object (must be developer with path).
#' @param name Table name.
#' @param metadata Named list for metadata.json.
#' @param metadata_sha SHA of the metadata (the datom "version").
#' @param message Commit message (stored in version_history entry).
#' @param original_file_sha SHA of the source file for imported tables; NULL for derived.
#' @return Invisible list with metadata_sha and local paths written.
#' @keywords internal
.datom_write_metadata_local <- function(conn, name, metadata, metadata_sha,
                                       message = NULL,
                                       original_file_sha = NULL) {
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
    .datom_git_author(repo_path),
    error = function(e) "unknown"
  )

  new_entry <- list(
    version = metadata_sha,
    data_sha = metadata$data_sha,
    timestamp = metadata$created_at,
    author = author,
    commit_message = message %||% paste0("Update ", name)
  )

  if (!is.null(original_file_sha)) {
    new_entry$original_file_sha <- original_file_sha
  }

  # Guard: skip append if latest entry already has the same version SHA
  latest_version <- if (length(history) > 0) history[[1]]$version else NULL
  if (!identical(latest_version, metadata_sha)) {
    history <- c(list(new_entry), history)
  }
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
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param metadata Named list for metadata.json.
#' @param metadata_sha SHA of the metadata (the datom "version").
#' @return Invisible character vector of S3 keys written.
#' @keywords internal
.datom_push_metadata_s3 <- function(conn, name, metadata, metadata_sha) {
  # Read local version_history.json (written by .datom_write_metadata_local)
  history_path <- fs::path(conn$path, name, "version_history.json")
  history <- if (fs::file_exists(history_path)) {
    jsonlite::read_json(history_path)
  } else {
    list()
  }

  s3_metadata_key <- paste0(name, "/.metadata/metadata.json")
  s3_history_key <- paste0(name, "/.metadata/version_history.json")
  s3_versioned_key <- paste0(name, "/.metadata/", metadata_sha, ".json")

  .datom_storage_write_json(conn, s3_metadata_key, metadata)
  .datom_storage_write_json(conn, s3_history_key, history)
  .datom_storage_write_json(conn, s3_versioned_key, metadata)

  invisible(c(s3_metadata_key, s3_history_key, s3_versioned_key))
}


#' Write Metadata Files to Git and S3 (Legacy Wrapper)
#'
#' Calls [.datom_write_metadata_local()] then [.datom_push_metadata_s3()].
#' Kept for backward compatibility. Does NOT commit or push.
#'
#' @inheritParams .datom_write_metadata_local
#' @return Invisible list with metadata_sha, git_paths, and s3_keys.
#' @keywords internal
.datom_write_metadata <- function(conn, name, metadata, metadata_sha, message = NULL) {
  local_result <- .datom_write_metadata_local(
    conn, name, metadata, metadata_sha, message = message
  )
  s3_keys <- .datom_push_metadata_s3(conn, name, metadata, metadata_sha)

  invisible(list(
    metadata_sha = metadata_sha,
    git_paths = local_result$git_paths,
    s3_keys = s3_keys
  ))
}


#' Write a datom Table
#'
#' Writes data to a datom repository. Commits to git, pushes, and syncs to S3.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param data Data frame to write. If NULL with name, does metadata-only sync.
#' @param name Table name. If NULL with NULL data, aliases to
#'   [datom_sync_dispatch()].
#' @param metadata Optional list of custom metadata.
#' @param message Optional commit message.
#' @param parents Optional lineage: list of `list(source, table, version)` entries.
#'   Used by dp_dev to track dependency versions. NULL if lineage not recorded.
#' @param .table_type Internal. `"derived"` (default) or `"imported"` (set by `datom_sync()`).
#' @param .original_file_sha Internal. SHA of source file (set by `datom_sync()`); NULL for derived.
#' @param .original_format Internal. Original file format (set by `datom_sync()`); NULL for derived.
#'
#' @return List with deployment details.
#' @export
datom_write <- function(conn,
                       data = NULL,
                       name = NULL,
                       metadata = NULL,
                       message = NULL,
                       parents = NULL,
                       .table_type = "derived",
                       .original_file_sha = NULL,
                       .original_format = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("conn must be a datom_conn object from datom_get_conn()")
  }

  # Route based on arguments

  if (is.null(data) && is.null(name)) {
    return(datom_sync_dispatch(conn))
  }

  if (is.null(data) && !is.null(name)) {
    return(.datom_sync_metadata(conn, name))
  }

  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame.")
  }

  .datom_validate_name(name)

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Write operations require {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Write operations require a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # 1. Compute data SHA
  data_sha <- .datom_compute_data_sha(data)

  # 2. Write parquet to temp (need size_bytes for complete metadata)
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)
  arrow::write_parquet(data, tmp)
  size_bytes <- as.numeric(fs::file_size(tmp))

  # 3. Build metadata (complete — includes size_bytes)
  meta <- .datom_build_metadata(
    data, data_sha,
    custom = metadata,
    table_type = .table_type,
    parents = parents,
    size_bytes = size_bytes
  )
  metadata_sha <- .datom_compute_metadata_sha(meta)

  # 4. Change detection
  change_type <- .datom_has_changes(conn, name, data_sha, metadata_sha)

  if (change_type == "none") {
    cli::cli_alert_info(
      "No changes detected for {.val {name}}. Skipping write."
    )
    return(invisible(list(
      name = name,
      data_sha = data_sha,
      metadata_sha = metadata_sha,
      action = "none"
    )))
  }

  # 5. Write metadata locally
  write_result <- .datom_write_metadata_local(
    conn, name, meta, metadata_sha,
    message = message,
    original_file_sha = .original_file_sha
  )

  # 5b. Update manifest.json locally
  .datom_update_manifest_entry(
    conn, name,
    metadata_sha = metadata_sha,
    data_sha = data_sha,
    file_sha = .original_file_sha,
    format = .original_format
  )

  # 6. Git commit + push (must succeed before touching S3)
  git_files <- c(
    fs::path_rel(write_result$git_paths, conn$path),
    ".datom/manifest.json"
  )
  commit_msg <- message %||% paste0("Update ", name)
  commit_sha <- .datom_git_commit(conn$path, git_files, commit_msg)
  .datom_git_push(conn$path)

  # 7. Upload parquet to S3 (only if data changed — after git succeeds)
  if (change_type == "full") {
    parquet_key <- paste0(name, "/", data_sha, ".parquet")
    .datom_storage_upload(conn, tmp, parquet_key)
  }

  # 8. Push metadata to S3
  .datom_push_metadata_s3(conn, name, meta, metadata_sha)

  # 9. Push manifest to S3 (completes the round-trip)
  manifest_path <- fs::path(conn$path, ".datom", "manifest.json")
  if (fs::file_exists(manifest_path)) {
    manifest_data <- jsonlite::read_json(manifest_path)
    .datom_storage_write_json(conn, ".metadata/manifest.json", manifest_data)
  }

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
