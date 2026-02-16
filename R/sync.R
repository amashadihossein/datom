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
#' Processes new/changed files from manifest. One commit per table.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param manifest Manifest from [tbit_sync_manifest()].
#' @param continue_on_error If TRUE, continues on individual file errors.
#'
#' @return Updated manifest with results.
#' @export
tbit_sync <- function(conn,
                      manifest,
                      continue_on_error = TRUE) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement
  stop("Not yet implemented")
}
