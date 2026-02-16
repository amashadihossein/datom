#' List Available Tables
#'
#' Lists tables from S3 manifest. Reads `.tbit/manifest.json` from S3
#' and returns a data frame with one row per table.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param pattern Optional glob pattern for filtering table names.
#' @param include_versions If TRUE, includes version count info.
#'
#' @return Data frame with table info (name, current_version, last_updated, etc.).
#' @export
tbit_list <- function(conn,
                      pattern = NULL,
                      include_versions = FALSE) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls tbit_conn} object from {.fn tbit_get_conn}.")
  }

  manifest <- tryCatch(
    .tbit_s3_read_json(conn, ".tbit/manifest.json"),
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

  do.call(rbind, rows)
}


#' Show Version History
#'
#' Shows version history for a table by reading `version_history.json`
#' from S3. Returns the most recent `n` versions.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#' @param name Table name.
#' @param n Maximum number of versions to return. Default 10.
#'
#' @return Data frame with columns: version, data_sha, timestamp, author,
#'   commit_message.
#' @export
tbit_history <- function(conn,
                         name,
                         n = 10) {

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

  do.call(rbind, rows)
}


#' Show Repository Status
#'
#' Shows uncommitted changes and sync state.
#'
#' @param conn A `tbit_conn` object from [tbit_get_conn()].
#'
#' @return Status summary (printed, returns invisibly).
#' @export
tbit_status <- function(conn) {

  if (!inherits(conn, "tbit_conn")) {
    cli::cli_abort("conn must be a tbit_conn object from tbit_get_conn()")
  }

  # TODO: Implement in Phase 6
  stop("Not yet implemented")
}
