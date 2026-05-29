# governance.json primitives
#
# Helpers to build, write, and read the governance.json pointer file.
# This file records the governance attachment for a data project.
# It lives at two locations:
#   - Git copy (canonical):    {data_clone}/.datom/governance.json
#   - Storage mirror (derived): {prefix}/datom/.metadata/governance.json
#
# The pattern is identical to manifest.json: git is canonical; the storage
# mirror is written in the same step and is always derived from git.
#
# Never write credentials, gov_local_path, or any per-machine state into
# governance.json (see Invariant 1 and 5 in the phase doc).


# --- Builder ------------------------------------------------------------------

#' Build governance.json Content
#'
#' Constructs the governance pointer list that is written to both the local
#' git copy and the data-store mirror.
#'
#' @param gov_repo_url HTTPS clone URL of the governance git repository.
#' @param gov_store A `datom_store_s3` or `datom_store_local` component
#'   representing the governance storage (location + credentials). Only the
#'   location fields are persisted; credentials are discarded.
#' @param attached_at Optional ISO 8601 UTC timestamp string. Defaults to the
#'   current system time.
#' @return Named list suitable for serialisation to JSON.
#' @keywords internal
.datom_create_governance_json <- function(gov_repo_url, gov_store,
                                          attached_at = NULL) {
  if (!is.character(gov_repo_url) || !nzchar(gov_repo_url)) {
    cli::cli_abort("{.arg gov_repo_url} must be a non-empty character string.")
  }

  backend <- .datom_store_backend(gov_store)
  root    <- as.character(fs::path_norm(.datom_store_root(gov_store)))
  prefix  <- gov_store$prefix %||% NULL
  region  <- if (identical(backend, "s3")) gov_store$region else NULL

  if (!backend %in% c("s3", "local")) {
    cli::cli_abort("Unsupported governance store backend: {.val {backend}}")
  }
  if (!is.character(root) || !nzchar(root)) {
    cli::cli_abort("Governance store must have a non-empty root (bucket or path).")
  }

  if (is.null(attached_at)) {
    attached_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }

  gov_storage <- list(
    type   = backend,
    root   = root,
    prefix = prefix,
    region = region
  )
  # Drop NULL fields for cleaner JSON
  gov_storage <- gov_storage[!vapply(gov_storage, is.null, logical(1L))]

  list(
    gov_repo_url = gov_repo_url,
    gov_storage  = gov_storage,
    attached_at  = attached_at
  )
}


# --- Local (git-copy) I/O -----------------------------------------------------

#' Write governance.json to Local Git Clone
#'
#' Writes `content` to `{path}/.datom/governance.json`. The directory must
#' already exist (created during `datom_init_repo()` or `datom_attach_gov()`).
#'
#' @param path Absolute path to the root of the local data git clone.
#' @param content Named list from `.datom_create_governance_json()`.
#' @return Invisible NULL.
#' @keywords internal
.datom_write_governance_json_local <- function(path, content) {
  dest_dir <- fs::path(path, ".datom")
  fs::dir_create(dest_dir)
  dest <- fs::path(dest_dir, "governance.json")
  jsonlite::write_json(content, dest, auto_unbox = TRUE, pretty = TRUE)
  invisible(NULL)
}

#' Read governance.json from Local Git Clone
#'
#' Reads and validates `{path}/.datom/governance.json`. Returns NULL when the
#' file is absent (project is not gov-attached). Aborts on malformed JSON or
#' failed schema validation.
#'
#' @param path Absolute path to the root of the local data git clone.
#' @return Parsed list or NULL.
#' @keywords internal
.datom_read_governance_json_local <- function(path) {
  src <- fs::path(path, ".datom", "governance.json")
  if (!fs::file_exists(src)) return(NULL)

  content <- tryCatch(
    jsonlite::read_json(src, simplifyVector = FALSE),
    error = function(e) {
      cli::cli_abort(
        c(
          "Failed to parse {.path {src}}.",
          "i" = "Parse error: {conditionMessage(e)}"
        ),
        parent = e
      )
    }
  )
  .datom_validate_governance_json(content, source_label = as.character(src))
  content
}


# --- Storage (mirror) I/O -----------------------------------------------------

#' Write governance.json Mirror to Data Storage
#'
#' Writes `content` to `.metadata/governance.json` in the data store.
#' Uses `.datom_storage_write_json()` dispatch (backend-neutral).
#'
#' @param conn A `datom_conn` for the data store.
#' @param content Named list from `.datom_create_governance_json()`.
#' @return Invisible NULL.
#' @keywords internal
.datom_storage_write_governance_json <- function(conn, content) {
  .datom_storage_write_json(conn, ".metadata/governance.json", content)
  invisible(NULL)
}

#' Read governance.json Mirror from Data Storage
#'
#' Returns the parsed list, or NULL when the key is absent. Aborts on any
#' non-not-found storage error or on failed schema validation.
#'
#' @param conn A `datom_conn` for the data store.
#' @return Parsed list or NULL.
#' @keywords internal
.datom_storage_read_governance_json <- function(conn) {
  key <- ".metadata/governance.json"
  if (!.datom_storage_exists(conn, key)) return(NULL)

  content <- .datom_storage_read_json(conn, key)
  full_key <- .datom_build_storage_key(conn$prefix, key)
  .datom_validate_governance_json(content,
    source_label = paste0(c(conn$backend, conn$root, full_key), collapse = "/"))
  content
}

#' Delete governance.json Mirror from Data Storage
#'
#' Called by `datom_decommission()`. No-ops silently when key is absent.
#' Deletion is implemented via prefix-delete on the exact key path; the
#' single-key delete dispatch helper is wired in Chunk 7.
#'
#' @param conn A `datom_conn` for the data store.
#' @return Invisible NULL.
#' @keywords internal
.datom_storage_delete_governance_json <- function(conn) {
  # Chunk 7 wires .datom_storage_delete_key(); use prefix-delete for now
  # to handle both backends without introducing a new dispatch function yet.
  .datom_storage_delete_prefix(conn, ".metadata/governance.json")
  invisible(NULL)
}


# --- Sync (repair) helper -----------------------------------------------------

#' Sync governance.json Storage Mirror from Git Copy
#'
#' Reads the git-canonical copy and overwrites the storage mirror. Call after
#' a partial failure to repair a missing or stale storage mirror.
#'
#' @param conn A `datom_conn` with `path` set to the local data git clone.
#' @return Invisible NULL.
#' @keywords internal
.datom_sync_governance_json <- function(conn) {
  content <- .datom_read_governance_json_local(conn$path)
  if (is.null(content)) {
    cli::cli_abort(
      c(
        "No governance.json found in local git clone.",
        "i" = "Only call {.fn .datom_sync_governance_json} for gov-attached projects."
      )
    )
  }
  .datom_storage_write_governance_json(conn, content)
  invisible(NULL)
}


# --- Validation ---------------------------------------------------------------

# Internal: validate a parsed governance.json list. Aborts on any issue.
.datom_validate_governance_json <- function(content, source_label = "governance.json") {
  is_nonempty_string <- function(x) is.character(x) && length(x) == 1L && nzchar(x)

  if (!is_nonempty_string(content$gov_repo_url)) {
    cli::cli_abort(
      "{.val gov_repo_url} must be a non-empty string in {.path {source_label}}."
    )
  }

  gs <- content$gov_storage
  if (is.null(gs)) {
    cli::cli_abort(
      "{.val gov_storage} is missing in {.path {source_label}}."
    )
  }

  if (!gs$type %in% c("s3", "local")) {
    cli::cli_abort(
      "{.val gov_storage$type} must be {.val s3} or {.val local} in {.path {source_label}}."
    )
  }

  if (!is_nonempty_string(gs$root)) {
    cli::cli_abort(
      "{.val gov_storage$root} must be a non-empty string in {.path {source_label}}."
    )
  }

  invisible(content)
}
