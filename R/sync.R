#' Sync Routing Metadata to S3
#'
#' Updates all metadata in S3 to match git after migration or routing changes.
#' Requires interactive confirmation.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#'
#' @return Summary of updated files.
#' @export
tbit_sync_routing <- function(conn) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}


#' Scan and Prepare Manifest for Sync
#'
#' Scans a flat `input_files/` directory and computes file SHAs. Compares
#' against the current `.tbit/manifest.json` to detect new or changed files.
#' Returns a manifest data frame for review before calling [tbit_sync()].
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param path Optional path to input files directory. Defaults to
#'   `input_files/` inside the repo.
#' @param pattern Glob pattern for file matching. Default `"*"`.
#'
#' @return Data frame with columns: name, file, format, file_sha, status
#'   (one of `"new"`, `"changed"`, `"unchanged"`).
#' @export
tbit_sync_manifest <- function(conn,
                               path = NULL,
                               pattern = "*") {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls tbit_conn} object from {.fn tbit_get_conn}.")
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
      "i" = "Use {.fn tbit_get_conn} with a tbit-initialized repo."
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
  manifest_path <- fs::path(conn$path, ".tbit", "manifest.json")
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
    file_sha <- .tbit_compute_file_sha(fp)

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


#' Sync Files to tbit Repository
#'
#' Processes new/changed files from a manifest produced by
#' [tbit_sync_manifest()]. Imports each file via `rio::import()`, converts to
#' a data frame, and calls [tbit_write()] to store as parquet in S3 with git
#' metadata. Updates the local `.tbit/manifest.json` after each successful
#' write.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param manifest Data frame from [tbit_sync_manifest()], with columns
#'   `name`, `file`, `format`, `file_sha`, `status`.
#' @param continue_on_error If `TRUE` (default), continues processing
#'   remaining tables when one fails. If `FALSE`, stops on first error.
#'
#' @return The manifest data frame augmented with `result` and `error` columns.
#'   `result` is `"success"`, `"skipped"`, or `"error"`.
#' @export
tbit_sync <- function(conn,
                      manifest,
                      continue_on_error = TRUE) {

  # --- validation ---
  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls tbit_conn} object from {.fn tbit_get_conn}.")
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
      "i" = "Use {.fn tbit_get_conn} with a tbit-initialized repo."
    ))
  }

  if (!is.data.frame(manifest)) {
    cli::cli_abort("{.arg manifest} must be a data frame from {.fn tbit_sync_manifest}.")
  }

  required_cols <- c("name", "file", "format", "file_sha", "status")
  missing_cols <- setdiff(required_cols, names(manifest))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "Manifest missing required columns: {.val {missing_cols}}.",
      "i" = "Use {.fn tbit_sync_manifest} to generate a valid manifest."
    ))
  }

  .tbit_check_rio()

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
      data <- .tbit_import_file(tbl_file, tbl_format)

      # Write via tbit_write
      write_result <- tbit_write(
        conn,
        data = data,
        name = tbl_name,
        message = paste0("Sync ", tbl_name, " (", manifest$status[i], ")")
      )

      # Update local manifest.json
      .tbit_update_manifest_entry(
        conn, tbl_name,
        file_sha = tbl_file_sha,
        format = tbl_format,
        write_result = write_result
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


# --- Internal helpers for tbit_sync -------------------------------------------

#' Check rio availability
#' @noRd
.tbit_check_rio <- function() {
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
.tbit_import_file <- function(file, format) {
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


#' Update a single table entry in local .tbit/manifest.json
#' @noRd
.tbit_update_manifest_entry <- function(conn, name, file_sha, format,
                                        write_result) {
  manifest_path <- fs::path(conn$path, ".tbit", "manifest.json")

  manifest <- if (fs::file_exists(manifest_path)) {
    jsonlite::read_json(manifest_path)
  } else {
    list(tables = list(), summary = list())
  }

  manifest$tables[[name]] <- list(
    current_version = write_result$metadata_sha,
    current_data_sha = write_result$data_sha,
    original_file_sha = file_sha,
    original_format = format,
    last_updated = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    size_bytes = file.size(
      fs::path(conn$path, name, ".metadata", "version_history.json")
    ) %||% 0L,
    version_count = 1L
  )

  # Update summary
  manifest$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  manifest$summary <- list(
    total_tables = length(manifest$tables),
    total_size_bytes = sum(purrr::map_dbl(manifest$tables, ~ .x$size_bytes %||% 0)),
    total_versions = sum(purrr::map_int(manifest$tables, ~ .x$version_count %||% 0L))
  )

  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)

  invisible(manifest)
}
