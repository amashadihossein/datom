# ref.json — Data Location Reference
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
      root = data_store$bucket,
      prefix = data_store$prefix,
      region = data_store$region
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
