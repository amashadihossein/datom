# Data-repo git operations
#
# Exported helpers that let a downstream package (datomanager) mutate the data
# repo without touching it directly. Every data-repo git write routes through
# these helpers -- this upholds the two-repos invariant: gov code commits only
# to the gov clone; data-repo writes always go through datom.


#' Rewrite the Data Store Pointer in project.yaml
#'
#' Updates `storage.data` in `.datom/project.yaml` to point at `new_store`,
#' then commits and pushes the data repo. This is the data-side bookkeeping
#' step of a store relocation.
#'
#' **Read-modify-write contract**: the function reads the full existing
#' `project.yaml`, modifies **only** `storage.data`, and writes back. It
#' never reconstructs the file from conn fields. This preserves
#' `storage.governance` on governed projects (it is permanent once written)
#' and any other fields not owned by this function.
#'
#' For governed projects the authoritative address is `ref.json` in the gov
#' repo -- this function updates only the local data clone so that
#' `datom_get_conn()` stays consistent after migration. It is called by
#' `datomanager::gov_migrate_data()` after the ref switch, never before.
#'
#' @param conn A `datom_conn` object with `role = "developer"` and a local
#'   repo path (`conn$path`).
#' @param new_store A `datom_store_s3` or `datom_store_local` component
#'   (i.e. the data-side component of a `datom_store()` object, not the
#'   full composite).
#' @param message Optional commit message. Defaults to
#'   `"Update data store: {project_name}"`.
#' @return Invisibly, the SHA of the resulting commit.
#' @export
#' @seealso [datom_storage_copy()], [datom_storage_verify()],
#'   [datom_repo_delete()]
#' @examples
#' \dontrun{
#' new_store <- datom_store_s3(
#'   bucket     = "new-bucket",
#'   prefix     = "study-001",
#'   region     = "us-east-1",
#'   access_key = Sys.getenv("AWS_ACCESS_KEY_ID"),
#'   secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY"),
#'   validate   = FALSE
#' )
#' datom_repo_set_data_store(conn, new_store)
#' }
datom_repo_set_data_store <- function(conn, new_store, message = NULL) {
  .datom_check_git2r()

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object.")
  }
  if (conn$role != "developer") {
    cli::cli_abort(c(
      "{.fn datom_repo_set_data_store} requires a developer connection.",
      "i" = "Current role: {.val {conn$role}}"
    ))
  }
  if (is.null(conn$path)) {
    cli::cli_abort(
      "{.arg conn} has no local repo {.field path}; cannot update {.file project.yaml}."
    )
  }
  if (!.is_datom_store_component(new_store)) {
    cli::cli_abort(
      "{.arg new_store} must be a {.cls datom_store_s3} or {.cls datom_store_local} object."
    )
  }

  yaml_path <- fs::path(conn$path, ".datom", "project.yaml")
  if (!fs::file_exists(yaml_path)) {
    cli::cli_abort("No {.file .datom/project.yaml} found at {.path {conn$path}}.")
  }

  # --- Read full yaml (read-modify-write: never reconstruct from conn) --------
  cfg <- yaml::read_yaml(yaml_path)

  # --- Build new storage.data block from new_store ---------------------------
  backend <- .datom_store_backend(new_store)
  root    <- .datom_store_root(new_store)
  prefix  <- new_store$prefix
  region  <- .datom_store_region(new_store)

  new_data_block <- list(
    type   = backend,
    root   = root,
    prefix = prefix
  )
  if (backend == "s3") new_data_block$region <- region

  # modifyList touches only storage.data; storage.governance (if present) is untouched
  cfg$storage <- utils::modifyList(
    cfg$storage %||% list(),
    list(data = new_data_block)
  )

  # --- Atomic write (tmp + rename) -------------------------------------------
  tmp_path <- fs::path(conn$path, ".datom", "project.yaml.tmp")
  yaml::write_yaml(cfg, tmp_path)
  fs::file_move(tmp_path, yaml_path)

  # --- Commit and push -------------------------------------------------------
  commit_msg <- message %||%
    glue::glue("Update data store: {conn$project_name}")

  sha <- .datom_git_commit(
    conn$path,
    files   = ".datom/project.yaml",
    message = commit_msg
  )

  .datom_git_push(conn$path, pat = conn$github_pat)

  cli::cli_alert_success(
    "Updated {.file .datom/project.yaml} data store pointer for {.val {conn$project_name}}."
  )
  invisible(sha)
}
