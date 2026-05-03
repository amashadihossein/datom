#' Check if Path is a Valid datom Repository
#'
#' Validates datom repository structure. Used internally and by dpbuild.
#'
#' @param path Path to evaluate.
#' @param checks Which checks to perform. Any combination of "all", "git",
#'   "datom", "renv".
#' @param verbose If TRUE, prints which tests passed/failed.
#'
#' @return TRUE or FALSE.
#' @export
is_valid_datom_repo <- function(path,
                               checks = c("all", "git", "datom", "renv"),
                               verbose = FALSE) {
  checks <- match.arg(
    arg = checks,
    choices = c("all", "git", "datom", "renv"),
    several.ok = TRUE
  )

  dx <- datom_repository_check(path = path)

  if (!"all" %in% checks) {
    if (!"git" %in% checks) {
      dx <- dx[setdiff(names(dx), "git_initialized")]
    }
    if (!"datom" %in% checks) {
      dx <- dx[setdiff(names(dx), c("datom_initialized", "datom_manifest"))]
    }
    if (!"renv" %in% checks) {
      dx <- dx[setdiff(names(dx), "renv_initialized")]
    }
  }

  if (verbose) {
    purrr::iwalk(dx, function(val, name) {
      if (isTRUE(val)) {
        cli::cli_alert_success("{name}")
      } else {
        cli::cli_alert_danger("{name}")
      }
    })
  }

  all(vapply(dx, isTRUE, logical(1)))
}


#' Check datom Repository Structure
#'
#' Returns detailed check results for each component.
#'
#' @param path Path to evaluate.
#'
#' @return List of TRUE/FALSE per check.
#' @keywords internal
datom_repository_check <- function(path) {
  path <- fs::path_abs(path)

  list(
    git_initialized = fs::dir_exists(fs::path(path, ".git")),
    datom_initialized = fs::file_exists(fs::path(path, ".datom", "project.yaml")),
    datom_manifest = fs::file_exists(fs::path(path, ".datom", "manifest.json")),
    renv_initialized = fs::dir_exists(fs::path(path, "renv"))
  )
}


#' Validate Git-Storage Consistency
#'
#' Checks that git metadata matches S3 storage for all tables and repo-level
#' files. Reports mismatches as a structured result.
#'
#' @param conn A `datom_conn` object from [datom_get_conn()].
#' @param fix If `TRUE`, attempts to fix inconsistencies by syncing metadata
#'   to S3 via [datom_sync_dispatch()].
#'
#' @return A list with:
#'   \describe{
#'     \item{valid}{Logical — `TRUE` if everything is consistent.}
#'     \item{repo_files}{Data frame of repo-level file checks.}
#'     \item{tables}{Data frame of per-table checks.}
#'     \item{fixed}{Logical — `TRUE` if `fix = TRUE` was applied.}
#'   }
#' @export
datom_validate <- function(conn, fix = FALSE) {

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object from {.fn datom_get_conn}.")
  }

  if (conn$role != "developer") {
    cli::cli_abort(c(
      "Validation requires {.val developer} role.",
      "i" = "Current role: {.val {conn$role}}."
    ))
  }

  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "Validation requires a local git repo path.",
      "i" = "Use {.fn datom_get_conn} with a datom-initialized repo."
    ))
  }

  # --- Repo-level file checks ---
  repo_file_checks <- .datom_validate_repo_files(conn)

  # --- Project identity check ---
  project_name_ok <- .datom_validate_project_name(conn)

  # --- Per-table checks ---
  table_checks <- .datom_validate_tables(conn)

  if (is.null(conn$gov_root)) {
    cli::cli_alert_info(
      "No governance attached -- skipping dispatch/ref/migration_history checks."
    )
  }

  all_repo_ok <- nrow(repo_file_checks) == 0L ||
    all(repo_file_checks$status == "ok")
  all_tables_ok <- nrow(table_checks) == 0L ||
    all(table_checks$status == "ok")
  is_valid <- all_repo_ok && all_tables_ok && project_name_ok

  if (is_valid) {
    cli::cli_alert_success("All checks passed. Git and S3 are consistent.")
  } else {
    n_repo_issues <- sum(repo_file_checks$status != "ok")
    n_table_issues <- sum(table_checks$status != "ok")
    cli::cli_alert_warning(
      "Found {n_repo_issues + n_table_issues} issue{?s}: {n_repo_issues} repo-level, {n_table_issues} table-level."
    )
  }

  fixed <- FALSE

  if (!is_valid && isTRUE(fix)) {
    cli::cli_alert_info("Attempting to fix by syncing metadata to S3...")
    tryCatch({
      datom_sync_dispatch(conn, .confirm = FALSE)
      fixed <- TRUE
      cli::cli_alert_success("Fix applied. Re-run {.fn datom_validate} to verify.")
    }, error = function(e) {
      cli::cli_alert_danger("Fix failed: {conditionMessage(e)}")
    })
  }

  invisible(list(
    valid = is_valid,
    repo_files = repo_file_checks,
    tables = table_checks,
    fixed = fixed
  ))
}


#' Validate project_name consistency between local manifest and connection
#'
#' Reads the local `.datom/manifest.json` and checks that its `project_name`
#' field matches `conn$project_name`. A mismatch indicates a namespace collision
#' (two projects sharing the same S3 bucket + prefix).
#'
#' @param conn A `datom_conn` object.
#' @return `TRUE` if consistent or no project_name in manifest (legacy
#'   repos without project tracking). `FALSE` on mismatch (with a warning).
#' @noRd
.datom_validate_project_name <- function(conn) {
  manifest_path <- fs::path(conn$path, ".datom", "manifest.json")

  if (!fs::file_exists(manifest_path)) return(TRUE)

  manifest <- tryCatch(
    jsonlite::read_json(manifest_path),
    error = function(e) return(TRUE)
  )

  manifest_project <- manifest$project_name
  if (is.null(manifest_project)) return(TRUE)  # legacy manifest without project_name

  if (!identical(manifest_project, conn$project_name)) {
    cli::cli_alert_danger(
      "Project name mismatch: manifest says {.val {manifest_project}} but connection says {.val {conn$project_name}}."
    )
    cli::cli_alert_info(
      "This may indicate a namespace collision. Check bucket/prefix configuration."
    )
    return(FALSE)
  }

  TRUE
}


#' Validate repo-level files exist on S3
#' @noRd
.datom_validate_repo_files <- function(conn) {
  repo_path <- conn$path
  project_name <- conn$project_name
  has_gov <- !is.null(conn$gov_root)

  # Manifest (data side) is always checked.
  files_to_check <- list(
    list(
      local = as.character(fs::path(repo_path, ".datom", "manifest.json")),
      s3_key = ".metadata/manifest.json",
      name = "manifest.json",
      target_conn = conn
    )
  )

  # Governance files (dispatch / ref / migration_history) only exist when
  # the project has been gov-attached. For no-gov projects they are
  # genuinely absent; skipping keeps the validator from reporting false
  # negatives.
  if (has_gov) {
    gov_conn <- .datom_gov_conn(conn)
    gov_local_path <- conn$gov_local_path

    proj_key <- function(name) {
      fs::path("projects", project_name, name)
    }

    gov_local <- function(name) {
      if (is.null(gov_local_path) || !nzchar(gov_local_path)) {
        return(NA_character_)
      }
      as.character(fs::path(gov_local_path, "projects", project_name, name))
    }

    files_to_check <- c(
      list(
        list(
          local = gov_local("dispatch.json"),
          s3_key = as.character(proj_key("dispatch.json")),
          name = "dispatch.json",
          target_conn = gov_conn
        ),
        list(
          local = gov_local("ref.json"),
          s3_key = as.character(proj_key("ref.json")),
          name = "ref.json",
          target_conn = gov_conn
        ),
        list(
          local = gov_local("migration_history.json"),
          s3_key = as.character(proj_key("migration_history.json")),
          name = "migration_history.json",
          target_conn = gov_conn
        )
      ),
      files_to_check
    )
  }

  rows <- purrr::map(files_to_check, function(fc) {
    if (is.na(fc$local)) {
      # No local clone available (e.g. reader): skip local check
      return(NULL)
    }
    local_exists <- fs::file_exists(fc$local)

    if (!local_exists) {
      # File not in clone -- skip
      return(NULL)
    }

    s3_exists <- .datom_storage_exists(fc$target_conn, fc$s3_key)

    status <- if (s3_exists) "ok" else "missing_s3"

    data.frame(
      file = fc$name,
      local = TRUE,
      s3 = s3_exists,
      status = status,
      stringsAsFactors = FALSE
    )
  })

  rows <- purrr::compact(rows)

  if (length(rows) == 0L) {
    return(data.frame(
      file = character(), local = logical(),
      s3 = logical(), status = character(),
      stringsAsFactors = FALSE
    ))
  }

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}


#' Validate per-table metadata consistency
#' @noRd
.datom_validate_tables <- function(conn) {
  repo_path <- conn$path

  # Discover tables (directories with metadata.json)
  all_dirs <- fs::dir_ls(repo_path, type = "directory")
  all_dirs <- all_dirs[!grepl("^\\.", fs::path_file(all_dirs))]
  all_dirs <- all_dirs[!fs::path_file(all_dirs) %in%
    c("input_files", "renv", "man", "R", "tests", "vignettes", "src")]

  table_dirs <- all_dirs[purrr::map_lgl(all_dirs, function(d) {
    fs::file_exists(fs::path(d, "metadata.json"))
  })]

  table_names <- fs::path_file(table_dirs)

  if (length(table_names) == 0L) {
    return(data.frame(
      table = character(),
      metadata_local = logical(),
      metadata_s3 = logical(),
      history_local = logical(),
      history_s3 = logical(),
      data_s3 = logical(),
      status = character(),
      stringsAsFactors = FALSE
    ))
  }

  rows <- purrr::map(table_names, function(tbl) {
    .datom_validate_one_table(conn, tbl)
  })

  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}


#' Validate a single table's git-S3 consistency
#' @noRd
.datom_validate_one_table <- function(conn, name) {
  repo_path <- conn$path

  # Local checks
  metadata_local <- fs::file_exists(fs::path(repo_path, name, "metadata.json"))
  history_local <- fs::file_exists(fs::path(repo_path, name, "version_history.json"))

  # S3 checks
  metadata_s3 <- .datom_storage_exists(conn, paste0(name, "/.metadata/metadata.json"))
  history_s3 <- .datom_storage_exists(conn, paste0(name, "/.metadata/version_history.json"))

  # Check that data parquet exists (read data_sha from local metadata)
  data_s3 <- FALSE
  if (metadata_local) {
    tryCatch({
      meta <- jsonlite::read_json(
        fs::path(repo_path, name, "metadata.json"),
        simplifyVector = TRUE
      )
      if (!is.null(meta$data_sha) && nzchar(meta$data_sha)) {
        data_key <- paste0(name, "/", meta$data_sha, ".parquet")
        data_s3 <- .datom_storage_exists(conn, data_key)
      }
    }, error = function(e) {
      # Leave data_s3 as FALSE
    })
  }

  # Determine status
  issues <- character()
  if (metadata_local && !metadata_s3) issues <- c(issues, "metadata_missing_s3")
  if (history_local && !history_s3) issues <- c(issues, "history_missing_s3")
  if (!data_s3) issues <- c(issues, "data_missing_s3")

  status <- if (length(issues) == 0L) "ok" else paste(issues, collapse = ",")

  data.frame(
    table = name,
    metadata_local = metadata_local,
    metadata_s3 = metadata_s3,
    history_local = history_local,
    history_s3 = history_s3,
    data_s3 = data_s3,
    status = status,
    stringsAsFactors = FALSE
  )
}
