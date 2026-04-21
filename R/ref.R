# ref.json -- Data Location Reference
#
# `ref.json` lives at the **governance store** and tells readers where data
# currently lives. Always present; never absent. Single read, no recursion.
#
# Structure:
#   {
#     "current": { "root": "...", "prefix": "...", "region": "..." },
#     "previous": [
#       {
#         "root": "...", "prefix": "...", "region": "...",
#         "migrated_at": "2026-01-15T00:00:00Z",
#         "sunset_at": "2026-04-15T00:00:00Z"
#       }
#     ]
#   }


#' Create Initial ref.json Content
#'
#' Builds the initial `ref.json` structure from the data store component.
#' No `previous` entries on first creation.
#'
#' @param data_store A `datom_store_s3` component (the data portion of the store).
#' @return A list suitable for JSON serialization.
#' @keywords internal
.datom_create_ref <- function(data_store) {
  list(
    current = list(
      root = .datom_store_root(data_store),
      prefix = data_store$prefix,
      region = .datom_store_region(data_store)
    ),
    previous = list()
  )
}


#' Resolve Data Location from Governance Store
#'
#' Reads `ref.json` from the governance store and returns the current data
#' location as a named list. Single read, no recursion, no chain-walking.
#'
#' If the ref has `previous` entries, a deprecation-style warning is emitted
#' to alert users that a migration occurred and old locations may sunset.
#'
#' @param gov_conn A `datom_conn`-like object scoped to the governance store
#'   (i.e., `root`, `prefix`, `client` point to the governance store).
#'   Typically produced by `.datom_gov_conn(conn)`.
#' @return A named list with `root`, `prefix`, `region` for the current
#'   data location.
#' @keywords internal
.datom_resolve_ref <- function(gov_conn) {
  ref <- tryCatch(
    .datom_storage_read_json(gov_conn, ".metadata/ref.json"),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to read {.file ref.json} from governance store.",
          "x" = "Root: {.val {gov_conn$root}}",
          "x" = "Prefix: {.val {gov_conn$prefix}}",
          "i" = "Underlying error: {conditionMessage(e)}",
          "i" = "The governance store may be unreachable or {.file ref.json} may not exist."
        ),
        parent = e
      )
    }
  )

  current <- ref$current
  if (is.null(current) || is.null(current$root)) {
    cli::cli_abort(c(
      "Invalid {.file ref.json}: missing {.field current.root}.",
      "x" = "Governance root: {.val {gov_conn$root}}"
    ))
  }

  # Emit warning if there are previous migration entries
  previous <- ref$previous
  if (length(previous) > 0L) {
    last_migration <- previous[[1L]]
    sunset <- last_migration$sunset_at %||% "unknown"
    old_bucket <- last_migration$root %||% "unknown"
    cli::cli_warn(c(
      "Data was migrated from {.val {old_bucket}}.",
      "i" = "Previous location sunsets at: {.val {sunset}}.",
      "i" = "Update your store credentials if needed."
    ))
  }

  list(
    root = current$root,
    prefix = current$prefix %||% NULL,
    region = current$region %||% "us-east-1"
  )
}


#' Resolve Data Location via Ref (Conn-Time Helper)
#'
#' Called during `datom_get_conn()` for both readers and developers when a
#' governance store is present. Reads `ref.json` from governance, detects
#' migration (store$data location != ref location), and returns the
#' ref-resolved location.
#'
#' **Developer migration**: auto-pulls git, re-reads project.yaml. Errors if
#' project.yaml still disagrees after pull.
#'
#' **Reader migration**: warns that the store config is stale, proceeds with
#' ref-resolved location.
#'
#' @param store A `datom_store` object with governance component.
#' @param role `"developer"` or `"reader"`.
#' @param path Local repo path (developers only; NULL for readers).
#' @param endpoint Optional S3 endpoint URL.
#' @return A named list with `root`, `prefix`, `region` from the ref, or
#'   NULL if no governance store is present (skip ref resolution).
#' @keywords internal
.datom_resolve_data_location <- function(store, role, path = NULL,
                                          endpoint = NULL) {
  # No governance component -> skip ref resolution (backward compatible)
  if (is.null(store$governance)) return(NULL)

  # Build a temporary gov conn to read ref.json
  gov_backend <- .datom_store_backend(store$governance)
  gov_root <- .datom_store_root(store$governance)
  gov_prefix <- store$governance$prefix
  gov_region <- .datom_store_region(store$governance)

  if (gov_backend == "s3") {
    gov_client <- .datom_s3_client(
      store$governance$access_key, store$governance$secret_key,
      region = gov_region %||% "us-east-1", endpoint = endpoint,
      session_token = store$governance$session_token
    )
  } else {
    gov_client <- NULL
  }

  gov_conn <- new_datom_conn(
    project_name = "ref-resolve",
    root = gov_root,
    prefix = gov_prefix,
    region = gov_region %||% "us-east-1",
    client = gov_client,
    path = NULL,
    role = "reader",
    endpoint = endpoint,
    backend = gov_backend
  )

  # Resolve ref -- fail gracefully if governance store unreachable
  ref_location <- tryCatch(
    .datom_resolve_ref(gov_conn),
    error = function(e) {
      cli::cli_warn(c(
        "Could not resolve ref.json from governance store.",
        "i" = "Underlying error: {conditionMessage(e)}",
        "i" = "Proceeding with store-configured data location."
      ))
      return(NULL)
    }
  )

  if (is.null(ref_location)) return(NULL)

  # Compare ref location against store$data
  store_root <- .datom_store_root(store$data)
  store_prefix <- store$data$prefix

  migrated <- !identical(ref_location$root, store_root) ||
    !identical(ref_location$prefix %||% NULL, store_prefix %||% NULL)

  if (migrated) {
    if (role == "developer" && !is.null(path)) {
      # Auto-pull git to sync local project.yaml
      cli::cli_alert_info("Ref location differs from store -- pulling git to sync.")
      tryCatch(
        .datom_git_pull(path),
        error = function(e) {
          cli::cli_abort(c(
            "Failed to auto-pull git after detecting migration.",
            "i" = "ref.json points to {.val {ref_location$root}} but store has {.val {store_root}}.",
            "i" = "Git pull error: {conditionMessage(e)}"
          ), parent = e)
        }
      )

      # Re-read project.yaml and check if it now agrees with ref
      yaml_path <- fs::path(path, ".datom", "project.yaml")
      if (fs::file_exists(yaml_path)) {
        cfg <- yaml::read_yaml(yaml_path)
        yaml_root <- cfg$storage$data$root
        if (!is.null(yaml_root) && !identical(yaml_root, ref_location$root)) {
          cli::cli_abort(c(
            "ref.json and project.yaml disagree after git pull.",
            "x" = "ref.json: {.val {ref_location$root}}",
            "x" = "project.yaml: {.val {yaml_root}}",
            "i" = "This may indicate a conflict. Resolve manually."
          ))
        }
      }
    } else {
      # Reader: warn, proceed with ref address
      cli::cli_warn(c(
        "Data has been migrated to a new location.",
        "i" = "ref.json points to {.val {ref_location$root}} but your store has {.val {store_root}}.",
        "i" = "Update your store config to stop this warning."
      ))
    }
  }

  ref_location
}


#' Validate Data Store Reachability
#'
#' Checks that the data store at the ref-resolved location is reachable.
#' For S3: HeadBucket. For local: dir_exists. Provides actionable error
#' messages when data is unreachable after migration.
#'
#' @param conn A `datom_conn` object (already ref-resolved).
#' @param migrated Logical, whether a migration was detected.
#' @return Invisible TRUE on success. Warns on network error (offline use ok).
#' @keywords internal
.datom_check_data_reachable <- function(conn, migrated = FALSE) {
  backend <- conn$backend %||% "s3"

  if (backend == "s3") {
    # Skip if client is NULL or not a real paws client
    if (is.null(conn$client) || !is.function(conn$client$head_bucket)) {
      return(invisible(TRUE))
    }
    tryCatch({
      conn$client$head_bucket(Bucket = conn$root)
    }, error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("403|Forbidden|AccessDenied", msg)) {
        if (migrated) {
          cli::cli_abort(c(
            "Data was migrated to {.val {conn$root}} but your credentials can't access it.",
            "x" = "HeadBucket returned 403 / Access Denied.",
            "i" = "Update your store credentials for the new data location."
          ), parent = e)
        } else {
          cli::cli_abort(c(
            "Data store {.val {conn$root}} is unreachable.",
            "x" = "HeadBucket returned 403 / Access Denied.",
            "i" = "Check your AWS credentials and IAM permissions."
          ), parent = e)
        }
      } else if (grepl("404|NoSuchBucket|NotFound", msg)) {
        cli::cli_abort(c(
          "Data store bucket {.val {conn$root}} does not exist.",
          "x" = "HeadBucket returned 404 / Not Found."
        ), parent = e)
      } else {
        # Network error -- warn, don't fail (offline use)
        cli::cli_warn(c(
          "Could not verify data store reachability.",
          "i" = "Underlying error: {conditionMessage(e)}",
          "i" = "Proceeding anyway -- operations may fail later."
        ))
      }
    })
  } else if (backend == "local") {
    if (!fs::dir_exists(conn$root)) {
      if (migrated) {
        cli::cli_abort(c(
          "Data was migrated to {.val {conn$root}} but the directory does not exist.",
          "i" = "Update your store config or create the directory."
        ))
      } else {
        cli::cli_abort(c(
          "Data store directory {.val {conn$root}} does not exist.",
          "i" = "Check the path in your store configuration."
        ))
      }
    }
  }

  invisible(TRUE)
}


#' Check ref.json Matches Connection (Write-Time Guard)
#'
#' Re-resolves `ref.json` from the governance store and compares against the
#' current connection's data location. Errors if they disagree, preventing
#' writes to the wrong location after a migration.
#'
#' @param conn A `datom_conn` object.
#' @return Invisible TRUE if current, or skips silently if no governance fields.
#' @keywords internal
.datom_check_ref_current <- function(conn) {
  # No governance fields -> legacy conn, skip
  if (is.null(conn$gov_root)) return(invisible(TRUE))

  gov_conn <- .datom_gov_conn(conn)

  ref_location <- tryCatch(
    .datom_resolve_ref(gov_conn),
    error = function(e) {
      cli::cli_abort(
        c(
          "Cannot write: ref.json could not be read from governance store.",
          "i" = "Underlying error: {conditionMessage(e)}",
          "i" = "Writing without a verified data location risks orphaning data.",
          "i" = "Check governance store connectivity and retry."
        ),
        parent = e
      )
    }
  )

  if (!identical(ref_location$root, conn$root) ||
      !identical(ref_location$prefix %||% NULL, conn$prefix %||% NULL)) {
    cli::cli_abort(c(
      "Data location changed since connection was created.",
      "x" = "ref.json: root={.val {ref_location$root}}, prefix={.val {ref_location$prefix}}",
      "x" = "conn: root={.val {conn$root}}, prefix={.val {conn$prefix}}",
      "i" = "Rebuild your connection with {.fn datom_get_conn}."
    ))
  }

  invisible(TRUE)
}
