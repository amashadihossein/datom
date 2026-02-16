# Internal validation helpers

# Reserved names that cannot be used as table names
.tbit_reserved_names <- c(
  ".metadata", ".tbit", "input_files", "tbit", ".redirect.json",
  ".git", ".gitignore", "renv"
)


#' Validate a tbit Table Name
#'
#' Checks that a table name is filesystem-safe and S3-safe. Returns the
#' name invisibly on success, errors with a clear message on failure.
#'
#' @param name Character string to validate as a table name.
#' @return Invisible `name` on success.
#' @keywords internal
.tbit_validate_name <- function(name) {
  if (!is.character(name) || length(name) != 1L || is.na(name)) {
    cli::cli_abort("{.arg name} must be a single non-NA character string.")
  }

  if (!nzchar(name)) {
    cli::cli_abort("{.arg name} must not be empty.")
  }

  if (nchar(name) > 128L) {
    cli::cli_abort(
      "{.arg name} must be 128 characters or fewer (got {nchar(name)})."
    )
  }

  if (!grepl("^[a-zA-Z]", name)) {
    cli::cli_abort(
      "{.arg name} must start with a letter. Got: {.val {name}}"
    )
  }

  if (!grepl("^[a-zA-Z][a-zA-Z0-9_ ()-]*$", name)) {
    cli::cli_abort(
      "{.arg name} may only contain letters, numbers, underscores, hyphens, spaces, and parentheses. Got: {.val {name}}"
    )
  }

  name_lower <- tolower(name)
  if (name_lower %in% .tbit_reserved_names) {
    cli::cli_abort(
      "{.val {name}} is a reserved name and cannot be used as a table name."
    )
  }

  invisible(name)
}


# --- Credential utilities (Phase 4) ------------------------------------------

#' Derive Credential Environment Variable Names
#'
#' Converts a project name into the standard tbit credential env var names.
#' Convention: `TBIT_{PROJECT_NAME}_ACCESS_KEY_ID` /
#' `TBIT_{PROJECT_NAME}_SECRET_ACCESS_KEY`
#'
#' Normalisation: uppercase, spaces/hyphens → underscores.
#'
#' @param project_name Project name string.
#' @return Named list with `access_key_env` and `secret_key_env`.
#' @keywords internal
.tbit_derive_cred_names <- function(project_name) {
  if (!is.character(project_name) || length(project_name) != 1L ||
      is.na(project_name) || !nzchar(project_name)) {
    cli::cli_abort("{.arg project_name} must be a single non-empty string.")
  }

  normalized <- toupper(project_name)
  normalized <- gsub("[- ]+", "_", normalized)

  list(
    access_key_env = paste0("TBIT_", normalized, "_ACCESS_KEY_ID"),
    secret_key_env = paste0("TBIT_", normalized, "_SECRET_ACCESS_KEY")
  )
}


#' Check Required Credentials
#'
#' Validates that the required environment variables are set for the given
#' project and role. Readers need S3 credentials; developers also need
#' GITHUB_PAT.
#'
#' @param project_name Project name string.
#' @param role One of `"reader"` or `"developer"`.
#' @return Invisible named list with `access_key_env` and `secret_key_env`
#'   (the derived names, for downstream use).
#' @keywords internal
.tbit_check_credentials <- function(project_name,
                                    role = c("reader", "developer")) {
  role <- match.arg(role)

  cred_names <- .tbit_derive_cred_names(project_name)

  missing <- character(0)

  if (!nzchar(Sys.getenv(cred_names$access_key_env, unset = ""))) {
    missing <- c(missing, cred_names$access_key_env)
  }
  if (!nzchar(Sys.getenv(cred_names$secret_key_env, unset = ""))) {
    missing <- c(missing, cred_names$secret_key_env)
  }
  if (role == "developer" && !nzchar(Sys.getenv("GITHUB_PAT", unset = ""))) {
    missing <- c(missing, "GITHUB_PAT")
  }

  if (length(missing) > 0L) {
    cli::cli_abort(c(
      "Missing {length(missing)} required environment variable{?s}:",
      purrr::set_names(
        paste0("{.envvar ", missing, "}"),
        rep("x", length(missing))
      ),
      "i" = "Set with {.code Sys.setenv({missing[[1]]} = \"...\")}"
    ))
  }

  invisible(cred_names)
}
