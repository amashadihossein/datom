#' List Available Tables
#'
#' Lists tables from S3 manifest. Reads `.metadata/manifest.json` from S3
#' and returns a data frame with one row per table.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param pattern Optional glob pattern for filtering table names.
#' @param include_versions If TRUE, includes version count info.
#' @param short_hash If TRUE (default), truncates version and data SHA
#'   columns to 8 characters for readability. Set to FALSE for full hashes.
#'
#' @return Data frame with table info (name, current_version, last_updated, etc.).
#' @export
tbit_list <- function(conn,
                      pattern = NULL,
                      include_versions = FALSE,
                      short_hash = TRUE) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls tbit_conn} object from {.fn tbit_get_conn}.")
  }

  manifest <- tryCatch(
    .tbit_s3_read_json(conn, ".metadata/manifest.json"),
    error = function(e) {
      cli::cli_abort(c(
        "Could not read manifest from S3.",
        "i" = "The repository may not be initialized or manifest is missing.",
        "i" = "Underlying error: {conditionMessage(e)}"
      ))
    }
  )

  tables <- manifest$tables
  if (is.null(tables) || length(tables) == 0L) {
    return(data.frame(
      name = character(),
      current_version = character(),
      last_updated = character(),
      stringsAsFactors = FALSE
    ))
  }

  table_names <- names(tables)

  # Apply glob pattern filter
  if (!is.null(pattern)) {
    table_names <- table_names[grepl(utils::glob2rx(pattern), table_names)]
    if (length(table_names) == 0L) {
      return(data.frame(
        name = character(),
        current_version = character(),
        last_updated = character(),
        stringsAsFactors = FALSE
      ))
    }
  }

  # Build data frame
  rows <- purrr::map(table_names, function(tbl_name) {
    entry <- tables[[tbl_name]]
    row <- data.frame(
      name = tbl_name,
      current_version = entry$current_version %||% NA_character_,
      current_data_sha = entry$current_data_sha %||% NA_character_,
      last_updated = entry$last_updated %||% NA_character_,
      stringsAsFactors = FALSE
    )
    if (include_versions) {
      row$version_count <- entry$version_count %||% NA_integer_
    }
    row
  })

  result <- do.call(rbind, rows)

  if (isTRUE(short_hash)) {
    result$current_version <- .tbit_abbreviate_sha(result$current_version)
    result$current_data_sha <- .tbit_abbreviate_sha(result$current_data_sha)
  }

  result
}


#' Show Version History
#'
#' Shows version history for a table by reading `version_history.json`
#' from S3. Returns the most recent `n` versions.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param name Table name.
#' @param n Maximum number of versions to return. Default 10.
#' @param short_hash If TRUE (default), truncates version and data SHA
#'   columns to 8 characters for readability. Set to FALSE for full hashes.
#'
#' @return Data frame with columns: version, data_sha, timestamp, author,
#'   commit_message.
#' @export
tbit_history <- function(conn,
                         name,
                         n = 10,
                         short_hash = TRUE) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls tbit_conn} object from {.fn tbit_get_conn}.")
  }

  .tbit_validate_name(name)

  if (!is.numeric(n) || length(n) != 1L || n < 1L) {
    cli::cli_abort("{.arg n} must be a positive integer.")
  }

  n <- as.integer(n)

  history_key <- paste0(name, "/.metadata/version_history.json")

  history <- tryCatch(
    .tbit_s3_read_json(conn, history_key),
    error = function(e) {
      cli::cli_abort(c(
        "No version history found for table {.val {name}}.",
        "i" = "The table may not exist or has no history.",
        "i" = "Underlying error: {conditionMessage(e)}"
      ))
    }
  )

  if (!is.list(history) || length(history) == 0L) {
    return(data.frame(
      version = character(),
      data_sha = character(),
      timestamp = character(),
      author = character(),
      commit_message = character(),
      stringsAsFactors = FALSE
    ))
  }

  # Take first n entries (history is most-recent-first)
  history <- utils::head(history, n)

  rows <- purrr::map(history, function(entry) {
    # Author may be a list (name + email) or a string
    author_val <- if (is.list(entry$author)) {
      paste0(entry$author$name, " <", entry$author$email, ">")
    } else {
      entry$author %||% NA_character_
    }

    data.frame(
      version = entry$version %||% NA_character_,
      data_sha = entry$data_sha %||% NA_character_,
      timestamp = entry$timestamp %||% NA_character_,
      author = author_val,
      commit_message = entry$commit_message %||% NA_character_,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, rows)

  if (isTRUE(short_hash)) {
    result$version <- .tbit_abbreviate_sha(result$version)
    result$data_sha <- .tbit_abbreviate_sha(result$data_sha)
  }

  result
}


#' Get Parent Lineage for a Table
#'
#' Reads the `parents` field from a table's metadata. Returns the lineage
#' entries recorded at write time by dp_dev or other callers. For imported
#' tables or derived tables with no recorded lineage, returns `NULL`.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param name Table name.
#' @param version Optional metadata_sha (tbit version). If NULL, reads
#'   current metadata. If provided, fetches the versioned metadata snapshot
#'   from S3.
#'
#' @return List of parent entries (each with `source`, `table`, `version`),
#'   or `NULL` if no lineage is recorded.
#' @export
tbit_get_parents <- function(conn, name, version = NULL) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls tbit_conn} object from {.fn tbit_get_conn}.")
  }

  .tbit_validate_name(name)

  if (is.null(version)) {
    # Read current metadata.json
    metadata_key <- paste0(name, "/.metadata/metadata.json")
  } else {
    if (!is.character(version) || length(version) != 1L || !nzchar(version)) {
      cli::cli_abort("{.arg version} must be a single non-empty string or NULL.")
    }
    # Read versioned snapshot
    metadata_key <- paste0(name, "/.metadata/", version, ".json")
  }

  metadata <- tryCatch(
    .tbit_s3_read_json(conn, metadata_key),
    error = function(e) {
      if (is.null(version)) {
        cli::cli_abort(c(
          "No metadata found for table {.val {name}}.",
          "i" = "The table may not exist.",
          "i" = "Underlying error: {conditionMessage(e)}"
        ))
      } else {
        cli::cli_abort(c(
          "Version {.val {version}} not found for table {.val {name}}.",
          "i" = "Use {.fn tbit_history} to see available versions.",
          "i" = "Underlying error: {conditionMessage(e)}"
        ))
      }
    }
  )

  # parents is NULL for imported tables or when not recorded

  metadata$parents
}


#' Show Repository Status
#'
#' Displays connection info, table count, and (for developers) uncommitted
#' git changes and input file sync state.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#'
#' @return Invisibly, a list with `connection`, `tables`, and optionally
#'   `git` and `input_files` status details.
#' @export
tbit_status <- function(conn) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls tbit_conn} object from {.fn tbit_get_conn}.")
  }

  status <- list(
    connection = list(
      project_name = conn$project_name,
      bucket = conn$bucket,
      prefix = conn$prefix,
      region = conn$region,
      role = conn$role,
      has_path = !is.null(conn$path)
    )
  )

  # --- Connection summary ---
  cli::cli_h2("tbit status")
  cli::cli_alert_info("Project: {.val {conn$project_name}}")
  cli::cli_alert_info("Bucket: {.val {conn$bucket}}")
  if (!is.null(conn$prefix)) {
    cli::cli_alert_info("Prefix: {.val {conn$prefix}}")
  }
  cli::cli_alert_info("Role: {.val {conn$role}}")

  # --- Table count from S3 manifest ---
  table_info <- tryCatch({
    manifest <- .tbit_s3_read_json(conn, ".metadata/manifest.json")
    n <- length(manifest$tables %||% list())
    list(count = n, available = TRUE)
  }, error = function(e) {
    list(count = 0L, available = FALSE, error = conditionMessage(e))
  })

  status$tables <- table_info

  if (table_info$available) {
    cli::cli_alert_info("Tables on S3: {.val {table_info$count}}")
  } else {
    cli::cli_alert_warning("Could not read S3 manifest.")
  }

  # --- Developer-only: git + input_files status ---
  if (!is.null(conn$path)) {
    # Git status
    git_info <- .tbit_status_git(conn$path)
    status$git <- git_info

    if (length(git_info$uncommitted) == 0L) {
      cli::cli_alert_success("Git: clean (no uncommitted changes)")
    } else {
      cli::cli_alert_warning(
        "Git: {length(git_info$uncommitted)} uncommitted change{?s}"
      )
      purrr::walk(git_info$uncommitted, function(f) {
        cli::cli_bullets(c(" " = "{.file {f}}"))
      })
    }

    if (!is.null(git_info$branch)) {
      cli::cli_alert_info("Branch: {.val {git_info$branch}}")
    }

    # Input files scan
    input_dir <- fs::path(conn$path, "input_files")
    if (fs::dir_exists(input_dir)) {
      input_info <- .tbit_status_input_files(conn)
      status$input_files <- input_info

      if (input_info$n_new > 0L || input_info$n_changed > 0L) {
        cli::cli_alert_warning(
          "Input files: {input_info$n_new} new, {input_info$n_changed} changed, {input_info$n_unchanged} unchanged"
        )
      } else if (input_info$n_total > 0L) {
        cli::cli_alert_success(
          "Input files: all {input_info$n_total} unchanged"
        )
      } else {
        cli::cli_alert_info("Input files: directory empty")
      }
    }
  }

  invisible(status)
}


#' Get git status (uncommitted changes + branch)
#' @noRd
.tbit_status_git <- function(path) {
  has_git2r <- requireNamespace("git2r", quietly = TRUE)

  if (!has_git2r || !fs::dir_exists(fs::path(path, ".git"))) {
    return(list(uncommitted = character(), branch = NULL))
  }

  repo <- tryCatch(git2r::repository(path), error = function(e) NULL)
  if (is.null(repo)) {
    return(list(uncommitted = character(), branch = NULL))
  }

  # Get uncommitted files (staged + unstaged + untracked)
  st <- tryCatch(git2r::status(repo), error = function(e) NULL)
  uncommitted <- character()
  if (!is.null(st)) {
    uncommitted <- unique(unlist(st, use.names = FALSE))
  }

  # Get branch
  branch <- tryCatch(.tbit_git_branch(path), error = function(e) NULL)

  list(uncommitted = uncommitted, branch = branch)
}


#' Get input files sync state vs manifest
#' @noRd
.tbit_status_input_files <- function(conn) {
  input_dir <- fs::path(conn$path, "input_files")

  files <- fs::dir_ls(input_dir, type = "file")

  if (length(files) == 0L) {
    return(list(n_total = 0L, n_new = 0L, n_changed = 0L, n_unchanged = 0L))
  }

  # Read local manifest
  manifest_path <- fs::path(conn$path, ".tbit", "manifest.json")
  manifest <- if (fs::file_exists(manifest_path)) {
    jsonlite::read_json(manifest_path)
  } else {
    list(tables = list())
  }

  statuses <- purrr::map_chr(files, function(fp) {
    table_name <- fs::path_ext_remove(fs::path_file(fp))
    file_sha <- .tbit_compute_file_sha(fp)
    existing <- manifest$tables[[table_name]]

    if (is.null(existing)) {
      "new"
    } else if (!identical(existing$original_file_sha, file_sha)) {
      "changed"
    } else {
      "unchanged"
    }
  })

  list(
    n_total = length(files),
    n_new = sum(statuses == "new"),
    n_changed = sum(statuses == "changed"),
    n_unchanged = sum(statuses == "unchanged")
  )
}
