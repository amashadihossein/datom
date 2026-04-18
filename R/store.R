# Store abstraction for datom storage backends
#
# Type-specific constructors: datom_store_s3() (now), datom_store_local() (Phase 12)
# Composite constructor: datom_store() bundles governance + data + git config


# --- datom_store: composite constructor ---------------------------------------

#' Create a datom Store
#'
#' Bundles a governance store component, a data store component, and git config
#' into a single store object. Role (developer vs reader) is derived from
#' `github_pat` presence.
#'
#' @param governance A store component (e.g., `datom_store_s3()`) for governance
#'   files (dispatch, ref, migration history).
#' @param data A store component (e.g., `datom_store_s3()`) for data files
#'   (manifest, tables, metadata).
#' @param github_pat GitHub personal access token. If provided, role is
#'   `"developer"`. If NULL, role is `"reader"`.
#' @param remote_url GitHub remote URL. Required when `github_pat` is provided
#'   and `create_repo = FALSE` will be used in `datom_init_repo()`.
#' @param github_org GitHub organization for repo creation. NULL for personal repos.
#' @param validate If `TRUE` (default), validate GitHub PAT via API.
#'   Set to `FALSE` for tests or offline use.
#'
#' @return A `datom_store` object.
#' @export
datom_store <- function(governance,
                        data,
                        github_pat = NULL,
                        remote_url = NULL,
                        github_org = NULL,
                        validate = TRUE) {

  # --- Validate components are store objects ----------------------------------
  if (!.is_datom_store_component(governance)) {
    cli::cli_abort(
      "{.arg governance} must be a datom store component (e.g., {.fn datom_store_s3})."
    )
  }

  if (!.is_datom_store_component(data)) {
    cli::cli_abort(
      "{.arg data} must be a datom store component (e.g., {.fn datom_store_s3})."
    )
  }

  # --- Validate github_pat ---------------------------------------------------
  if (!is.null(github_pat)) {
    if (!is.character(github_pat) || length(github_pat) != 1L ||
        is.na(github_pat) || !nzchar(github_pat)) {
      cli::cli_abort("{.arg github_pat} must be a single non-empty string or NULL.")
    }
  }

  # --- Validate remote_url ---------------------------------------------------
  if (!is.null(remote_url)) {
    if (!is.character(remote_url) || length(remote_url) != 1L ||
        is.na(remote_url) || !nzchar(remote_url)) {
      cli::cli_abort("{.arg remote_url} must be a single non-empty string or NULL.")
    }
  }

  # --- Validate github_org ---------------------------------------------------
  if (!is.null(github_org)) {
    if (!is.character(github_org) || length(github_org) != 1L ||
        is.na(github_org) || !nzchar(github_org)) {
      cli::cli_abort("{.arg github_org} must be a single non-empty string or NULL.")
    }
  }

  # --- Role derivation --------------------------------------------------------
  role <- if (!is.null(github_pat)) "developer" else "reader"

  # --- GitHub PAT validation --------------------------------------------------
  github_identity <- NULL

  if (!is.null(github_pat) && isTRUE(validate)) {
    github_identity <- .datom_validate_github_pat(github_pat)
  }

  structure(
    list(
      governance = governance,
      data = data,
      role = role,
      github_pat = github_pat,
      remote_url = remote_url,
      github_org = github_org,
      validated = isTRUE(validate),
      identity = list(
        github = github_identity,
        governance = governance$identity,
        data = data$identity
      )
    ),
    class = "datom_store"
  )
}


#' Check if Object is a datom Store
#'
#' @param x Object to test.
#' @return TRUE or FALSE.
#' @keywords internal
is_datom_store <- function(x) {
  inherits(x, "datom_store")
}


#' Print a datom Store
#'
#' Displays store configuration with masked secrets.
#'
#' @param x A `datom_store` object.
#' @param ... Ignored.
#' @return Invisible `x`.
#' @export
print.datom_store <- function(x, ...) {
  cli::cli_h3("datom store")
  cli::cli_ul()
  cli::cli_li("Role: {.val {x$role}}")

  if (!is.null(x$remote_url)) {
    cli::cli_li("Remote: {.url {x$remote_url}}")
  }

  if (!is.null(x$github_org)) {
    cli::cli_li("GitHub org: {.val {x$github_org}}")
  }

  if (!is.null(x$github_pat)) {
    cli::cli_li("GitHub PAT: {.val {(.datom_mask_secret(x$github_pat))}}")
  }

  if (!is.null(x$identity$github)) {
    cli::cli_li("GitHub user: {.val {x$identity$github$login}}")
  }

  cli::cli_end()

  cli::cli_text("")
  cli::cli_text("{.strong Governance:}")
  print(x$governance)

  cli::cli_text("")
  cli::cli_text("{.strong Data:}")
  print(x$data)

  invisible(x)
}


#' Check if Object is a Store Component
#'
#' Returns TRUE for any datom store component type (datom_store_s3, future
#' datom_store_local, etc.).
#'
#' @param x Object to test.
#' @return TRUE or FALSE.
#' @keywords internal
.is_datom_store_component <- function(x) {
  inherits(x, "datom_store_s3") # extend with || for future backends
}


#' Validate GitHub PAT
#'
#' Calls GitHub `GET /user` to verify the PAT is valid.
#'
#' @param pat GitHub personal access token.
#' @return A list with `login` and `id`.
#' @keywords internal
.datom_validate_github_pat <- function(pat) {
  tryCatch({
    resp <- httr2::request("https://api.github.com/user") |>
      httr2::req_headers(
        Authorization = paste("Bearer", pat),
        Accept = "application/vnd.github+json"
      ) |>
      httr2::req_perform()

    body <- httr2::resp_body_json(resp)
    list(login = body$login, id = body$id)
  }, error = function(e) {
    cli::cli_abort(c(
      "GitHub PAT validation failed.",
      "x" = "GET /user returned an error.",
      "i" = "Check that {.arg github_pat} is a valid token.",
      "i" = "Underlying error: {conditionMessage(e)}"
    ), parent = e)
  })
}


# --- datom_store_s3: S3 component constructor ---------------------------------

#' Create an S3 Store Component
#'
#' Constructs a validated S3 storage component for use as either the governance
#' or data component of a `datom_store`. Validates credentials and bucket access
#' at construction time (unless `validate = FALSE`).
#'
#' @param bucket S3 bucket name.
#' @param prefix S3 key prefix (e.g., `"project/"`). NULL for no prefix.
#' @param region AWS region (default `"us-east-1"`).
#' @param access_key AWS access key ID.
#' @param secret_key AWS secret access key.
#' @param session_token Optional AWS session token (for temporary credentials).
#' @param validate If `TRUE` (default), validate credentials and bucket access
#'   at construction time. Set to `FALSE` for tests or offline use.
#'
#' @return A `datom_store_s3` object.
#' @export
datom_store_s3 <- function(bucket,
                           prefix = NULL,
                           region = "us-east-1",
                           access_key,
                           secret_key,
                           session_token = NULL,
                           validate = TRUE) {


  # --- Structural validation --------------------------------------------------
  if (!is.character(bucket) || length(bucket) != 1L ||
      is.na(bucket) || !nzchar(bucket)) {
    cli::cli_abort("{.arg bucket} must be a single non-empty string.")
  }

  if (!is.null(prefix)) {
    if (!is.character(prefix) || length(prefix) != 1L || is.na(prefix)) {
      cli::cli_abort("{.arg prefix} must be a single string or NULL.")
    }
  }

  if (!is.character(region) || length(region) != 1L ||
      is.na(region) || !nzchar(region)) {
    cli::cli_abort("{.arg region} must be a single non-empty string.")
  }

  if (!is.character(access_key) || length(access_key) != 1L ||
      is.na(access_key) || !nzchar(access_key)) {
    cli::cli_abort("{.arg access_key} must be a single non-empty string.")
  }

  if (!is.character(secret_key) || length(secret_key) != 1L ||
      is.na(secret_key) || !nzchar(secret_key)) {
    cli::cli_abort("{.arg secret_key} must be a single non-empty string.")
  }

  if (!is.null(session_token)) {
    if (!is.character(session_token) || length(session_token) != 1L ||
        is.na(session_token) || !nzchar(session_token)) {
      cli::cli_abort("{.arg session_token} must be a single non-empty string or NULL.")
    }
  }

  # --- Connectivity validation ------------------------------------------------
  identity <- NULL

  if (isTRUE(validate)) {
    identity <- .datom_validate_s3_store(
      access_key = access_key,
      secret_key = secret_key,
      session_token = session_token,
      region = region,
      bucket = bucket
    )
  }

  structure(
    list(
      bucket = bucket,
      prefix = prefix,
      region = region,
      access_key = access_key,
      secret_key = secret_key,
      session_token = session_token,
      validated = isTRUE(validate),
      identity = identity
    ),
    class = "datom_store_s3"
  )
}


#' Check if Object is an S3 Store Component
#'
#' @param x Object to test.
#' @return TRUE or FALSE.
#' @keywords internal
is_datom_store_s3 <- function(x) {
  inherits(x, "datom_store_s3")
}


#' Print an S3 Store Component
#'
#' Displays store configuration with masked secrets.
#'
#' @param x A `datom_store_s3` object.
#' @param ... Ignored.
#' @return Invisible `x`.
#' @export
print.datom_store_s3 <- function(x, ...) {
  cli::cli_h3("datom S3 store component")
  cli::cli_ul()
  cli::cli_li("Bucket: {.val {x$bucket}}")

  if (!is.null(x$prefix)) {
    cli::cli_li("Prefix: {.val {x$prefix}}")
  }

  cli::cli_li("Region: {.val {x$region}}")
  cli::cli_li("Access key: {.val {(.datom_mask_secret(x$access_key))}}")
  cli::cli_li("Secret key: {.val {(.datom_mask_secret(x$secret_key))}}")

  if (!is.null(x$session_token)) {
    cli::cli_li("Session token: {.val {(.datom_mask_secret(x$session_token))}}")
  }

  cli::cli_li("Validated: {.val {x$validated}}")

  if (!is.null(x$identity)) {
    cli::cli_li("AWS account: {.val {x$identity$aws_account_id}}")
  }

  cli::cli_end()
  invisible(x)
}


# --- Internal helpers ---------------------------------------------------------

#' Mask a Secret for Display
#'
#' Shows first 4 characters followed by `****`.
#'
#' @param secret A string.
#' @return Masked string.
#' @keywords internal
.datom_mask_secret <- function(secret) {
  if (is.null(secret) || !nzchar(secret)) return("(not set)")
  n <- nchar(secret)
  if (n <= 4L) return("****")
  paste0(substr(secret, 1L, 4L), "****")
}


#' Validate S3 Store Connectivity
#'
#' Checks AWS identity (STS GetCallerIdentity) and bucket access (HeadBucket).
#'
#' @param access_key AWS access key ID.
#' @param secret_key AWS secret access key.
#' @param session_token Optional session token.
#' @param region AWS region.
#' @param bucket Bucket name.
#' @return A list with identity information (aws_account_id, aws_arn).
#' @keywords internal
.datom_validate_s3_store <- function(access_key, secret_key, session_token,
                                     region, bucket) {

  creds <- list(
    access_key_id = access_key,
    secret_access_key = secret_key
  )
  if (!is.null(session_token)) {
    creds$session_token <- session_token
  }

  config <- list(
    credentials = list(creds = creds),
    region = region
  )

  # --- STS GetCallerIdentity --------------------------------------------------
  identity <- tryCatch({
    sts <- paws.storage::sts(config = config)
    resp <- sts$get_caller_identity()
    list(
      aws_account_id = resp$Account,
      aws_arn = resp$Arn
    )
  }, error = function(e) {
    cli::cli_abort(c(
      "AWS credential validation failed.",
      "x" = "STS GetCallerIdentity returned an error.",
      "i" = "Check that {.arg access_key} and {.arg secret_key} are valid.",
      "i" = "Underlying error: {conditionMessage(e)}"
    ), parent = e)
  })

  # --- HeadBucket -------------------------------------------------------------
  tryCatch({
    s3 <- paws.storage::s3(config = config)
    s3$head_bucket(Bucket = bucket)
  }, error = function(e) {
    msg <- conditionMessage(e)
    if (grepl("403|Forbidden|AccessDenied", msg)) {
      cli::cli_abort(c(
        "AWS credentials are valid but lack access to bucket {.val {bucket}}.",
        "x" = "HeadBucket returned 403 / Access Denied.",
        "i" = "Check IAM permissions for this bucket."
      ), parent = e)
    } else if (grepl("404|NoSuchBucket|NotFound", msg)) {
      cli::cli_abort(c(
        "Bucket {.val {bucket}} does not exist.",
        "x" = "HeadBucket returned 404 / Not Found.",
        "i" = "Create the bucket first or check the bucket name."
      ), parent = e)
    } else {
      cli::cli_abort(c(
        "Failed to verify access to bucket {.val {bucket}}.",
        "i" = "Underlying error: {conditionMessage(e)}"
      ), parent = e)
    }
  })

  identity
}
