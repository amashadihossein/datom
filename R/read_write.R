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
#'
#' @examples
#' \dontrun{
#' tmp <- tempfile("datom_read_")
#' store <- datom_store(
#'   data = datom_store_local(path = file.path(tmp, "storage")),
#'   github_pat = "ghp_examplePATforDemoPurposesOnly1234",
#'   data_repo_url = "https://github.com/example/my-project",
#'   validate = FALSE
#' )
#' datom_init_repo(
#'   path = file.path(tmp, "repo"),
#'   project_name = "example_project",
#'   store = store
#' )
#' conn <- datom_get_conn(path = file.path(tmp, "repo"), store = store)
#' datom_write(conn, data = datom_example_data("dm"), name = "dm")
#' dm <- datom_read(conn, "dm")
#' head(dm)
#' unlink(tmp, recursive = TRUE)
#' }
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

  # 2. Resolve version to data_sha (+ the expected parquet_sha for integrity)

  resolved <- .datom_resolve_version(metadata_list, version = version, name = name)

  # 3. Download and read parquet, verifying its integrity against parquet_sha.
  .datom_read_parquet(
    conn, name, resolved$data_sha,
    parquet_sha = resolved$parquet_sha
  )
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


#' Resolve Version to data_sha and parquet_sha
#'
#' Given metadata from [.datom_read_metadata()], resolves a version spec
#' to the corresponding `data_sha` (the storage address) and the recorded
#' `parquet_sha` (the stored-object integrity hash). If `version` is NULL,
#' resolves from the current `metadata.json`; if a metadata_sha string, looks
#' it up in `version_history.json`.
#'
#' The `parquet_sha` may be `NULL`/`""` for pre-cv1 metadata, and for any
#' version-pinned read until `version_history` entries persist `parquet_sha`
#' (task 5.1). A `NULL`/empty `parquet_sha` tells [.datom_read_parquet()] to
#' skip the integrity check (the intended pre-cv1 grace).
#'
#' @param metadata_list Return value of [.datom_read_metadata()].
#' @param version NULL (current) or a metadata_sha string.
#' @param name Table name (for error messages).
#' @return Named list with `data_sha` (character) and `parquet_sha`
#'   (character or NULL) for the resolved version.
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
    return(list(
      data_sha = data_sha,
      parquet_sha = metadata_list$current$parquet_sha
    ))
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

  list(
    data_sha = data_sha,
    parquet_sha = history[[match_idx]]$parquet_sha
  )
}


#' Download and Read Parquet from S3
#'
#' Downloads `{table}/{data_sha}.parquet` from S3 to a temporary file and reads
#' it via `arrow::read_parquet()`. When an expected `parquet_sha` is supplied
#' (non-empty), the downloaded object's SHA-256 is verified against it BEFORE
#' parsing, so corruption or tampering aborts rather than being silently read.
#'
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param data_sha SHA identifying the parquet file.
#' @param parquet_sha Expected SHA-256 of the stored parquet object bytes, from
#'   the resolved metadata (see [.datom_resolve_version()]). When non-empty, the
#'   downloaded file is verified against it and a mismatch aborts. When `NULL`
#'   or empty (pre-cv1 metadata, or a version-pinned read before task 5.1
#'   persists it), the integrity check is skipped and the read succeeds.
#' @return Data frame.
#' @keywords internal
.datom_read_parquet <- function(conn, name, data_sha, parquet_sha = NULL) {
  .datom_validate_name(name)

  if (!is.character(data_sha) || length(data_sha) != 1L || !nzchar(data_sha)) {
    cli::cli_abort("{.arg data_sha} must be a single non-empty string.")
  }
  # data_sha is spliced into a storage key; reject path-traversal / non-hex.
  .datom_validate_sha(data_sha, arg = "data_sha")

  s3_key <- paste0(name, "/", data_sha, ".parquet")
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)

  .datom_storage_download(conn, s3_key, tmp)

  # Read-time integrity: verify the stored object bytes against the recorded
  # parquet_sha before parsing. Skipped when parquet_sha is absent/empty
  # (pre-cv1 metadata) -- a read-time grace, not a data migration.
  if (!is.null(parquet_sha) && nzchar(parquet_sha)) {
    actual <- digest::digest(file = tmp, algo = "sha256")
    if (!identical(actual, parquet_sha)) {
      cli::cli_abort(
        c(
          "Stored parquet for {.val {name}} failed its integrity check.",
          "x" = "Key: {.val {s3_key}}",
          "x" = "Expected {.field parquet_sha}: {.val {parquet_sha}}",
          "x" = "Actual SHA-256: {.val {actual}}",
          "i" = "The stored object may be corrupted or tampered with. Do not trust this data."
        )
      )
    }
  }

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
#' @param data_sha datom-cv1 canonical content hash of the data.
#' @param custom Optional named list of user-supplied custom metadata.
#' @param table_type `"derived"` (default, from `datom_write`) or `"imported"` (from `datom_sync`).
#' @param size_bytes Size of the parquet file in bytes. NULL if not yet computed.
#' @param parents Lineage list of parent entries (each with source, table, version),
#'   or NULL if no lineage recorded.
#' @param source_lineage Pre-computed transitive source list (each entry with
#'   project, table, version_sha), or NULL.
#' @param original_file_sha SHA-256 of the source file, for imported tables.
#'   Included in the metadata **only when non-NULL**; the derived path omits it
#'   from the object entirely (not present-with-NULL).
#' @param column_hashes Ordered list of per-column `list(name, sha)` digests
#'   from [.datom_canonical_hash()], or NULL. Excluded from `metadata_sha`
#'   (see [.datom_compute_metadata_sha()]).
#' @return Named list suitable for writing as metadata.json. Always carries
#'   `hash_algo = "datom-cv1"` and declares `parquet_sha` (left NULL here and
#'   populated by [datom_write()] after change detection, since the stored-
#'   object hash is not knowable until then; it is excluded from `metadata_sha`
#'   so this deferred assignment is safe).
#' @keywords internal
.datom_build_metadata <- function(data, data_sha, custom = NULL,
                                 table_type = "derived", size_bytes = NULL,
                                 parents = NULL, source_lineage = NULL,
                                 original_file_sha = NULL, column_hashes = NULL) {
  if (!table_type %in% c("imported", "derived")) {
    cli::cli_abort("{.arg table_type} must be {.val imported} or {.val derived}.")
  }

  meta <- list(
    data_sha = data_sha,
    hash_algo = "datom-cv1",
    parquet_sha = NULL,
    table_type = table_type,
    nrow = nrow(data),
    ncol = ncol(data),
    colnames = names(data),
    column_hashes = column_hashes,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    datom_version = as.character(utils::packageVersion("datom"))
  )

  if (!is.null(original_file_sha)) meta$original_file_sha <- original_file_sha
  if (!is.null(parents)) meta$parents <- parents
  if (!is.null(source_lineage)) meta$source_lineage <- source_lineage
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
#' @return Named list with two elements: `change_type` -- `"none"` (no change),
#'   `"metadata_only"` (data same, metadata changed), or `"full"` (data
#'   changed) -- and `current`, the already-read current metadata (or `NULL`
#'   for a brand-new table). Returning `current` lets [datom_write()] reuse it
#'   (the `metadata_only` `parquet_sha` carry-forward and the revert-to-older
#'   history scan) without a second storage read.
#' @keywords internal
.datom_has_changes <- function(conn, name, new_data_sha, new_metadata_sha) {
  metadata_key <- paste0(name, "/.metadata/metadata.json")

  # If metadata doesn't exist yet, it's a new table -> full write, no current.
  if (!.datom_storage_exists(conn, metadata_key)) {
    return(list(change_type = "full", current = NULL))
  }

  current <- .datom_storage_read_json(conn, metadata_key)
  current_metadata_sha <- .datom_compute_metadata_sha(current)

  change_type <- if (identical(current_metadata_sha, new_metadata_sha)) {
    "none"
  } else if (identical(current$data_sha, new_data_sha)) {
    "metadata_only"
  } else {
    "full"
  }

  list(change_type = change_type, current = current)
}


#' Resolve the parquet_sha to Record and Whether to Upload
#'
#' For a write that is not a no-op, decides which `parquet_sha` the new metadata
#' should carry and whether the freshly-serialized parquet bytes need uploading.
#' The caller performs the actual upload AFTER the git push (git push is the
#' serialization point); this function only decides.
#'
#' Cases:
#' * `metadata_only` -- the `data_sha` is unchanged, so the parquet object
#'   already exists; carry forward the current metadata's `parquet_sha` (which
#'   may be NULL for a pre-cv1 table, leaving the integrity check skipped) and
#'   do not upload.
#' * `full` where a prior version already recorded a `parquet_sha` for this
#'   exact `data_sha` -- the stored object exists and is pinned by that version;
#'   reuse its `parquet_sha` and do NOT re-upload (a fresh serialization can
#'   differ byte-for-byte and would break that version's integrity pin).
#' * `full` otherwise (brand-new content, or a legacy object with no recorded
#'   `parquet_sha`) -- upload these bytes and record their hash.
#'
#' This refines the design's literal step 7 (which gated on
#' `.datom_storage_exists()`): a recorded `parquet_sha` is the precise thing we
#' must not clobber, and its presence implies the object exists, so the history
#' lookup subsumes the existence check with identical behavior and one fewer
#' storage round-trip.
#'
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param data_sha Canonical content hash (the storage address).
#' @param new_parquet_sha SHA-256 of the freshly-serialized parquet bytes.
#' @param change_type `"metadata_only"` or `"full"` (never `"none"`).
#' @param current The current metadata (from [.datom_has_changes()]), or NULL.
#' @return List with `parquet_sha` (character or NULL) and `upload` (logical).
#' @keywords internal
.datom_resolve_parquet_sha <- function(conn, name, data_sha, new_parquet_sha,
                                       change_type, current) {
  # metadata_only: data_sha unchanged -> the parquet object already exists;
  # carry the current object's parquet_sha forward, no upload.
  if (identical(change_type, "metadata_only")) {
    return(list(parquet_sha = current$parquet_sha, upload = FALSE))
  }

  # change_type == "full".
  # TODO(task 5.1): version_history entries do not persist parquet_sha until
  # task 5.1, so this lookup returns NULL until then and every "full" write
  # uploads (unchanged from prior behavior). When 5.1 lands, confirm the reuse
  # branch activates and enable the end-to-end revert-reuse test (task 12.5).
  reused <- .datom_lookup_history_parquet_sha(conn, name, data_sha)
  if (!is.null(reused)) {
    return(list(parquet_sha = reused, upload = FALSE))
  }

  list(parquet_sha = new_parquet_sha, upload = TRUE)
}


#' Most-recent version_history parquet_sha for a data_sha
#'
#' Scans the developer's local `version_history.json` (newest-first) for the
#' most recent entry whose `data_sha` matches and that carries a non-empty
#' `parquet_sha`. Returns NULL when none is found -- including the transitional
#' period before task 5.1 persists `parquet_sha` into history entries, and for
#' pre-cv1 histories. Reads the local git clone (offline-friendly); a stale
#' clone is tolerated because the subsequent git push serializes concurrent
#' writers (a behind clone fails to push before it can upload).
#'
#' @param conn A `datom_conn` object (developer, with local path).
#' @param name Table name.
#' @param data_sha Canonical content hash to match.
#' @return Character `parquet_sha`, or NULL.
#' @keywords internal
.datom_lookup_history_parquet_sha <- function(conn, name, data_sha) {
  history_path <- fs::path(conn$path, name, "version_history.json")
  if (!fs::file_exists(history_path)) {
    return(NULL)
  }

  history <- jsonlite::read_json(history_path)
  for (entry in history) {
    if (identical(entry$data_sha %||% "", data_sha)) {
      parquet_sha <- entry$parquet_sha %||% ""
      if (nzchar(parquet_sha)) {
        return(parquet_sha)
      }
    }
  }

  NULL
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
#' @param name Table name. If NULL with NULL data, does a data-only metadata
#'   sync to storage (manifest + per-table metadata).
#' @param metadata Optional list of custom metadata.
#' @param message Optional commit message.
#' @param parents Optional list of parent records produced by
#'   [datom_parent()], each carrying `source`, `table`, `version`,
#'   `data_sha`, and `source_lineage`. When supplied, the table's
#'   `source_lineage` is derived as the deduplicated union of the parents'
#'   `source_lineage` and each parent is recorded lean (`source`, `table`,
#'   `version`, `data_sha`). NULL if no lineage is recorded. There is no
#'   public `source_lineage` parameter; it is always derived from `parents`.
#' @param .source_lineage Internal. Flat list of transitive non-derived
#'   source descriptors (each with `project`, `table`, `version_sha`) for the
#'   imported self-entry path, set by [datom_sync()]. Unused on the derived
#'   (parents) path.
#' @param .table_type Internal. `"derived"` (default) or `"imported"`
#'   (set by `datom_sync()`).
#' @param .original_file_sha Internal. SHA of source file
#'   (set by `datom_sync()`); NULL for derived.
#' @param .original_format Internal. Original file format
#'   (set by `datom_sync()`); NULL for derived.
#'
#' @return List with deployment details.
#' @export
#'
#' @examples
#' \dontrun{
#' tmp <- tempfile("datom_write_")
#' store <- datom_store(
#'   data = datom_store_local(path = file.path(tmp, "storage")),
#'   github_pat = "ghp_examplePATforDemoPurposesOnly1234",
#'   data_repo_url = "https://github.com/example/my-project",
#'   validate = FALSE
#' )
#' datom_init_repo(
#'   path = file.path(tmp, "repo"),
#'   project_name = "example_project",
#'   store = store
#' )
#' conn <- datom_get_conn(path = file.path(tmp, "repo"), store = store)
#' dm <- datom_example_data("dm")
#' datom_write(conn, data = dm, name = "dm")
#' unlink(tmp, recursive = TRUE)
#' }
datom_write <- function(conn,
                       data = NULL,
                       name = NULL,
                       metadata = NULL,
                       message = NULL,
                       parents = NULL,
                       .source_lineage = NULL,
                       .table_type = "derived",
                       .original_file_sha = NULL,
                       .original_format = NULL) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("conn must be a datom_conn object from datom_get_conn()")
  }

  # Route based on arguments

  if (is.null(data) && is.null(name)) {
    return(.datom_sync_data_metadata(conn))
  }

  if (is.null(data) && !is.null(name)) {
    return(.datom_sync_metadata(conn, name))
  }

  if (!is.data.frame(data)) {
    cli::cli_abort("{.arg data} must be a data frame.")
  }

  .datom_validate_name(name)

  # Parents must be resolved datom_parent() records. Derive the table's
  # source_lineage from their union and record lean parent edges. When no
  # parents are given, use the internal .source_lineage (imported path).
  if (!is.null(parents)) {
    .datom_validate_parents(parents)
    parent_lineages <- lapply(parents, function(p) p$source_lineage)
    source_lineage <- datom_lineage_union(parent_lineages)
    parents <- lapply(parents, function(p) list(
      source   = p$source,
      table    = p$table,
      version  = p$version,
      data_sha = p$data_sha
    ))
  } else {
    source_lineage <- .source_lineage
    .datom_validate_source_lineage(source_lineage)
  }

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

  # 0. Write-time ref guard: ensure data location hasn't changed
  .datom_check_ref_current(conn)

  # 1. Canonical content hash: data_sha (the storage address) + the per-column
  #    index, in one pass. The all-offenders abort fires here -- before any
  #    git/storage/manifest mutation -- so a refusal leaves no partial state.
  hashed <- .datom_canonical_hash(data)
  data_sha <- hashed$data_sha

  # 2. Serialize parquet to a temp file; capture its size and the stored-object
  #    integrity hash (parquet_sha) of these exact bytes.
  tmp <- tempfile(fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)
  arrow::write_parquet(data, tmp)
  size_bytes <- as.numeric(fs::file_size(tmp))
  new_parquet_sha <- digest::digest(file = tmp, algo = "sha256")

  # 3. Build metadata. parquet_sha is set in step 5 (after change detection);
  #    it is excluded from metadata_sha, so this deferral does not affect the
  #    version identity.
  meta <- .datom_build_metadata(
    data, data_sha,
    custom = metadata,
    table_type = .table_type,
    parents = parents,
    source_lineage = source_lineage,
    size_bytes = size_bytes,
    original_file_sha = .original_file_sha,
    column_hashes = hashed$column_hashes
  )
  metadata_sha <- .datom_compute_metadata_sha(meta)

  # 4. Change detection (reuses the already-read current metadata).
  chg <- .datom_has_changes(conn, name, data_sha, metadata_sha)
  change_type <- chg$change_type

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

  # 5. Decide the parquet_sha to record and whether these bytes need uploading.
  #    The upload itself stays AFTER the git push (step 8); this only decides.
  parquet_decision <- .datom_resolve_parquet_sha(
    conn, name, data_sha, new_parquet_sha, change_type, chg$current
  )
  meta$parquet_sha <- parquet_decision$parquet_sha

  # 6. Write metadata + manifest locally
  write_result <- .datom_write_metadata_local(
    conn, name, meta, metadata_sha,
    message = message,
    original_file_sha = .original_file_sha
  )
  .datom_update_manifest_entry(
    conn, name,
    metadata_sha = metadata_sha,
    data_sha = data_sha,
    file_sha = .original_file_sha,
    format = .original_format
  )

  # 7. Git commit + push (must succeed before touching storage). Git push is the
  #    serialization point that makes the reuse decision in step 5 safe against
  #    concurrent writers.
  git_files <- c(
    fs::path_rel(write_result$git_paths, conn$path),
    ".datom/manifest.json"
  )
  commit_msg <- message %||% paste0("Update ", name)
  commit_sha <- .datom_git_commit(conn$path, git_files, commit_msg)
  .datom_git_push(conn$path, pat = conn$github_pat)

  # 8. Upload parquet (only when step 5 decided it is needed -- after git).
  if (isTRUE(parquet_decision$upload)) {
    parquet_key <- paste0(name, "/", data_sha, ".parquet")
    .datom_storage_upload(conn, tmp, parquet_key)
  }

  # 9. Push metadata to S3
  .datom_push_metadata_s3(conn, name, meta, metadata_sha)

  # 10. Push manifest to S3 (completes the round-trip)
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
