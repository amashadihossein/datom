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
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   # Repoint project.yaml at a relocated data store.
#'   new_store <- datom_store_local(file.path(tmp, "storage-relocated"))
#'   datom_repo_set_data_store(conn, new_store)
#'
#'   unlink(tmp, recursive = TRUE)
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
  # Checked before the merge below, and NOT covered by the connection-time gate:
  # this verb edits, commits and pushes the file, so a shape this build cannot
  # read would get a `storage$data` block merged into it on this build's
  # assumptions -- a format that reparented those keys ends up with a stale block
  # beside the real one -- and then distributed to every collaborator. The gate at
  # connection time ran on the file as it was when the connection opened; a hand
  # edit or a pull since then replaces it, and this is the storage-migration verb,
  # so it is called exactly when somebody is reorganising storage by hand. Same
  # reasoning as `.datom_check_set_write_gates()`, and it applies harder here,
  # because that one only refuses a write while this one publishes one.
  #
  # The read-modify-write is separately what carries an unrecognised
  # `schema_version` forward untouched rather than dropping it -- nothing but
  # `datom_init_repo()` stamps that field, so this verb never raises the declared
  # number.
  cfg <- yaml::read_yaml(yaml_path)
  .datom_check_project_schema(cfg, source = yaml_path, operation = "write")

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


#' Delete the Data GitHub Repository and Local Clone
#'
#' Deletes the data-side GitHub repository via the GitHub REST API and removes
#' the local clone directory. This is the data-side teardown step for a datom
#' project.
#'
#' **Solo projects** (no governance attached): call this together with
#' [datom_storage_delete_prefix()] for a complete teardown.
#'
#' **Governed projects**: use `datomanager::gov_decommission()` instead.
#' That function calls `datom_repo_delete()` internally (with
#' `force_gov_attached = TRUE`). Calling `datom_repo_delete()` directly on
#' a governed project without that flag is refused to prevent accidentally
#' orphaning the governance registration.
#'
#' Steps:
#' 1. Delete the data GitHub repo via the GitHub REST API (requires
#'    `conn$github_pat` with `delete_repo` scope; skipped with a warning
#'    when `conn$github_pat` is NULL or when the remote is not GitHub).
#'    Aborts if `conn$data_repo_url` is not set.
#' 2. Remove the local clone directory (`conn$path`).
#'
#' Each step is warn-and-continue on failure so the other still runs.
#'
#' @param conn A `datom_conn` object (developer role required).
#' @param confirm Character string. Must equal `conn$project_name` exactly.
#'   No interactive prompts -- this must be supplied explicitly.
#' @param force_gov_attached Logical. `FALSE` (default) refuses to run when
#'   governance is attached (`!is.null(conn$gov_root)`). Pass `TRUE` only
#'   when called programmatically from `datomanager::gov_decommission()`.
#' @return Invisible `TRUE` on success.
#' @export
#' @seealso [datom_storage_delete_prefix()], [datom_repo_set_data_store()]
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage. Because the remote is not GitHub,
#' # the API deletion step is skipped and only the local clone is removed.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   # Solo project teardown (no governance): storage, then repo.
#'   datom_storage_delete_prefix(conn)
#'   datom_repo_delete(conn, confirm = conn$project_name)
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_repo_delete <- function(conn, confirm, force_gov_attached = FALSE) {
  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object.")
  }
  if (conn$role != "developer") {
    cli::cli_abort(c(
      "{.fn datom_repo_delete} requires a developer connection.",
      "i" = "Current role: {.val {conn$role}}"
    ))
  }

  project_name <- conn$project_name

  if (!identical(confirm, project_name)) {
    cli::cli_abort(c(
      "Confirmation does not match the project name.",
      "i" = "Pass {.code conn$project_name} ({.val {project_name}}) as {.arg confirm}."
    ))
  }

  # Gov-attached guard: refuse unless caller explicitly opts through
  if (!is.null(conn$gov_root) && !isTRUE(force_gov_attached)) {
    cli::cli_abort(c(
      "{.fn datom_repo_delete} refuses to delete a governed project's data repo.",
      "i" = "Use {.fn gov_decommission} from datomanager to tear down a governed project.",
      "i" = "Or pass {.code force_gov_attached = TRUE} if you are calling this from a governed teardown."
    ))
  }

  cli::cli_alert_info("Deleting data repo for {.val {project_name}}...")

  # ---- Step 1. Delete GitHub repo -------------------------------------------
  tryCatch(
    {
      repo_url <- conn$data_repo_url
      if (is.null(repo_url)) {
        cli::cli_abort(c(
          "Cannot delete GitHub repository: {.field data_repo_url} is not set on this conn.",
          "i" = "Rebuild the conn with {.fn datom_get_conn} and retry."
        ))
      }

      if (!grepl("github\\.com", repo_url, ignore.case = TRUE)) {
        cli::cli_alert_info("No GitHub remote found -- skipping repo deletion.")
      } else {
        repo_full <- sub(
          ".*github\\.com[:/]([^/]+/[^/]+?)(\\.git)?$",
          "\\1",
          repo_url,
          perl = TRUE
        )
        pat <- conn$github_pat
        if (is.null(pat) || !nzchar(pat)) {
          cli::cli_alert_warning(
            "No GitHub PAT on conn. Delete {.val {repo_full}} manually."
          )
        } else {
          cli::cli_alert_info("Deleting GitHub repo {.val {repo_full}}...")
          tryCatch(
            {
              .datom_delete_github_repo(
                repo_full, pat,
                api_url = conn$github_api_url %||% "https://api.github.com"
              )
              cli::cli_alert_success("Deleted GitHub repo {.val {repo_full}}.")
            },
            error = function(e) {
              cli::cli_alert_danger("GitHub repo deletion failed: {conditionMessage(e)}")
              cli::cli_alert_info("Delete {.val {repo_full}} manually.")
            }
          )
        }
      }
    },
    error = function(e) {
      cli::cli_alert_danger("GitHub repo deletion step failed: {conditionMessage(e)}")
      cli::cli_alert_info("Continuing with remaining teardown steps...")
    }
  )

  # ---- Step 2. Remove local clone -------------------------------------------
  if (!is.null(conn$path) && fs::dir_exists(conn$path)) {
    cli::cli_alert_info("Removing local clone {.path {conn$path}}...")
    tryCatch(
      {
        fs::dir_delete(conn$path)
        cli::cli_alert_success("Removed local clone.")
      },
      error = function(e) {
        cli::cli_alert_danger("Failed to remove local clone: {conditionMessage(e)}")
      }
    )
  }

  invisible(TRUE)
}


#' Write the Data-Side Governance Attachment Record
#'
#' Writes `governance.json` -- the data-side pointer recording which governance
#' repository a project is attached to. This is the data-repo / data-storage
#' half of attaching governance; the gov-repo registration (writing `ref.json`
#' and `dispatch.json`, committing to the gov repo) is performed separately by
#' the governance layer (`datomanager::gov_attach()`).
#'
#' `governance.json` is the canonical data->gov pointer in the bidirectional
#' governance link: the gov repo's `ref.json` points gov->data, and this file
#' points data->gov, so either repo can find the other. It is written to two
#' locations, mirroring the manifest pattern (git canonical, storage derived):
#' * `.datom/governance.json` in the local data clone (git canonical), committed
#'   and pushed to the data repo.
#' * `{prefix}/datom/.metadata/governance.json` in data storage (derived mirror;
#'   a failed mirror write warns but does not abort -- the git copy is canonical
#'   and readers with gov access resolve location from the gov repo).
#'
#' Routing this write through datom upholds the two-repos invariant: the
#' governance layer never mutates the data repo directly.
#'
#' @param conn A `datom_conn` object with `role = "developer"` and a local
#'   data clone (`conn$path`).
#' @param gov_repo_url HTTPS clone URL of the governance git repository to
#'   record.
#' @param gov_store A `datom_store_s3` or `datom_store_local` component for the
#'   governance storage. Only its location fields are persisted; credentials
#'   are discarded.
#' @param message Optional commit message. Defaults to
#'   `"Attach governance: {project_name}"`.
#' @return Invisibly, the SHA of the resulting data-repo commit.
#' @export
#' @seealso [datom_repo_delete()], [datom_repo_set_data_store()]
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   # Data-side half of governance attachment. The gov-repo registration
#'   # is performed separately by the companion datomanager package.
#'   datom_repo_attach_governance(
#'     conn,
#'     gov_repo_url = "https://github.com/example/acme-gov",
#'     gov_store    = datom_store_local(file.path(tmp, "gov-storage"))
#'   )
#'   gov_json <- jsonlite::read_json(
#'     file.path(tmp, "repo", ".datom", "governance.json")
#'   )
#'   print(gov_json$gov_repo_url)
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_repo_attach_governance <- function(conn, gov_repo_url, gov_store,
                                         message = NULL) {
  .datom_check_git2r()

  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object.")
  }
  if (conn$role != "developer") {
    cli::cli_abort(c(
      "{.fn datom_repo_attach_governance} requires a developer connection.",
      "i" = "Current role: {.val {conn$role}}"
    ))
  }
  if (is.null(conn$path)) {
    cli::cli_abort(
      "{.arg conn} has no local repo {.field path}; cannot write governance.json."
    )
  }
  if (!is.character(gov_repo_url) || length(gov_repo_url) != 1L ||
      !nzchar(gov_repo_url)) {
    cli::cli_abort("{.arg gov_repo_url} must be a non-empty character string.")
  }
  if (!.is_datom_store_component(gov_store)) {
    cli::cli_abort(
      "{.arg gov_store} must be a {.cls datom_store_s3} or {.cls datom_store_local} object."
    )
  }

  yaml_path <- fs::path(conn$path, ".datom", "project.yaml")
  if (!fs::file_exists(yaml_path)) {
    cli::cli_abort("No {.file .datom/project.yaml} found at {.path {conn$path}}.")
  }

  project_name <- conn$project_name

  # --- Build + write governance.json (git canonical) -------------------------
  gov_json <- .datom_create_governance_json(
    gov_repo_url = gov_repo_url,
    gov_store    = gov_store
  )
  .datom_write_governance_json_local(conn$path, gov_json)

  # --- Commit + push the data repo -------------------------------------------
  commit_msg <- message %||% glue::glue("Attach governance: {project_name}")
  sha <- .datom_git_commit(
    conn$path,
    files   = ".datom/governance.json",
    message = commit_msg
  )
  .datom_git_push(conn$path, pat = conn$github_pat)

  # --- Mirror to data storage (warn-and-continue on failure) -----------------
  tryCatch(
    .datom_storage_write_governance_json(conn, gov_json),
    error = function(e) {
      cli::cli_warn(c(
        "governance.json storage upload failed.",
        "x" = conditionMessage(e),
        "i" = "Local copy is intact. Readers with gov access resolve location from gov."
      ))
    }
  )

  cli::cli_alert_success(
    "Wrote data-side governance record for {.val {project_name}}."
  )
  invisible(sha)
}


# --- The sanctioned git-mutation surface --------------------------------------
#
# datom_repo_commit() and datom_repo_push() exist so a downstream package
# (dpbuild, dpdeploy) can commit its own content -- code, environment, framework
# state -- into the data repo without importing git2r. Every git mutation of the
# data repo goes through datom; these two are the human-moment half of that, and
# `.datom_git_commit()` / `.datom_git_push()` remain the machine-moment half.
#
# The distinction between the two halves is the whole point and is not cosmetic.
# A machine moment (inside datom_write() / datom_write_set()) stages an explicit
# file list and never add-all, because it fires at a time datom chose and the
# tree may hold a human's work in progress. A human moment is the opposite: the
# caller asked for it, so `paths = NULL` means what `git add .` means.


#' Connection Requirements Shared by the Two Git-Mutation Verbs
#'
#' Both verbs need the same three things and nothing else: a real connection, a
#' developer role, and a local clone to operate on.
#'
#' @param conn A `datom_conn` object.
#' @param verb Name of the calling verb, for the message.
#' @return Invisible `TRUE`.
#' @keywords internal
.datom_check_git_verb_conn <- function(conn, verb) {
  if (!inherits(conn, "datom_conn")) {
    cli::cli_abort("{.arg conn} must be a {.cls datom_conn} object.")
  }
  if (conn$role != "developer") {
    cli::cli_abort(c(
      "{.fn {verb}} requires a developer connection.",
      "i" = "Current role: {.val {conn$role}}"
    ))
  }
  if (is.null(conn$path)) {
    cli::cli_abort(c(
      "{.arg conn} has no local repo {.field path}.",
      "i" = "{.fn {verb}} operates on a clone; use {.fn datom_get_conn} with one."
    ))
  }

  invisible(TRUE)
}


#' Refuse a Repo With No Remote, Before git2r Does It Unhelpfully
#'
#' `.datom_git_push()` reads `git2r::remotes(repo)[[1L]]`, which subscripts an
#' empty list on a repo with no remote and fails with R's own out-of-bounds
#' error -- a message naming nothing the caller can act on. A data repo is
#' required to have a remote, so this is an edge rather than a scenario, but
#' `datom_repo_push()` is the first thing somebody points at a half-configured
#' repo.
#'
#' Deliberately **not** inside `.datom_git_push()`: putting it there would change
#' what four existing callers do on a repo they have never met in that state.
#' Both new verbs call it, so there is no second copy.
#'
#' @param path Repository path.
#' @param verb Name of the calling verb, for the message.
#' @return The remote name.
#' @keywords internal
.datom_check_git_remote <- function(path, verb) {
  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  remotes <- git2r::remotes(repo)
  if (length(remotes) == 0L) {
    cli::cli_abort(
      c(
        "{.fn {verb}} needs a git remote, and {.path {path}} has none.",
        "i" = "Add one with {.code git remote add origin <url>} and push once by hand.",
        "i" = "A datom data repo is expected to have a remote -- see {.fn datom_init_repo}."
      ),
      class = "datom_no_git_remote"
    )
  }

  remotes[[1L]]
}


#' Commits on This Branch the Remote Does Not Have
#'
#' The ahead half of the count `.datom_check_git_current()` already computes for
#' its behind half: `git2r::ahead_behind()` element `[[1]]` is ahead, `[[2]]` is
#' behind. No new git machinery.
#'
#' **Does not fetch.** The comparison is against the cached remote-tracking ref,
#' so a stale ref can only cause an unnecessary push -- and a push pulls first
#' and is idempotent, so the cost of being wrong in that direction is a round
#' trip. Fetching here would instead make a clean-tree call fail when offline.
#'
#' @param path Repository path.
#' @return Integer count of unpushed commits, or `NA_integer_` when it cannot be
#'   determined -- no upstream tracking ref yet, or the comparison failed.
#'   `NA` means *cannot prove there is nothing to publish*, so callers push: that
#'   is exactly the state of a branch that has never been pushed.
#' @keywords internal
.datom_git_ahead <- function(path) {
  repo <- tryCatch(
    git2r::repository(path),
    error = function(e) {
      cli::cli_abort("Not a git repository: {.path {path}}")
    }
  )

  upstream <- tryCatch(
    git2r::branch_get_upstream(git2r::repository_head(repo)),
    error = function(e) NULL
  )
  if (is.null(upstream)) return(NA_integer_)

  tryCatch(
    {
      ab <- git2r::ahead_behind(
        git2r::revparse_single(repo, "HEAD"),
        git2r::revparse_single(repo, upstream$name)
      )
      as.integer(ab[[1]])
    },
    error = function(e) NA_integer_
  )
}


#' Commit Content in the Data Repo
#'
#' Commits changes in the data repo clone and, by default, pushes them. This is
#' datom's **sanctioned git-mutation surface** for downstream packages: a build
#' or deployment package commits its own content -- code, `renv.lock`, framework
#' state -- through this verb rather than importing `git2r` and writing to the
#' data repo behind datom's back.
#'
#' **`paths = NULL` means what `git add .` means.** It stages tracked
#' modifications, deletions and untracked files, minus anything `.gitignore`
#' excludes. That is the correct semantic for a human-invoked moment, and it is
#' deliberately the opposite of what datom's own writes do: a commit created
#' inside [datom_write()] stages an explicit file list, because it fires at a
#' moment datom chose and must never sweep up work in progress.
#'
#' One consequence of add-all worth knowing rather than discovering: if an
#' earlier datom write failed after writing local metadata but before committing,
#' those datom files are dirty and this verb will stage them. That is left
#' intentional -- silently excluding datom's own paths would make the argument
#' lie about its contract, and the state is exactly what [datom_validate()]
#' reports and `datom_validate(fix = TRUE)` repairs. It also moves git *ahead* of
#' storage, which is the safe direction.
#'
#' **Commit is idempotent, push is convergent, and neither implies the other.**
#' A clean tree produces no commit and is not an error, so "commit everything"
#' can be called twice. With `push = TRUE` the push still runs when the branch is
#' ahead of the remote, even though no commit was created -- otherwise one failed
#' push would leave the remote behind forever, since every later call finds a
#' clean tree and returns early.
#'
#' @param conn A `datom_conn` object with `role = "developer"` and a local repo
#'   path (`conn$path`).
#' @param message Commit message. Required, and used only when a commit is
#'   actually created.
#' @param paths `NULL` (default) to stage everything `git add .` would stage, or
#'   a character vector of repo-relative paths to stage exactly those. Explicit
#'   paths must exist: to record a deletion, use `paths = NULL`.
#' @param push Push after committing (default `TRUE`), through the same path
#'   datom's own writes use -- so it inherits pull-before-push and upstream
#'   tracking. `push = FALSE` commits only; [datom_repo_push()] is the other half
#'   of that split.
#' @return Invisibly, the commit SHA; `invisible(NULL)` when no commit was
#'   created (whether or not a push happened).
#' @export
#' @seealso [datom_repo_push()], [datom_validate()]
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   # Content datom does not own, committed through datom.
#'   dir.create(file.path(tmp, "repo", "R"))
#'   writeLines("build <- function() NULL", file.path(tmp, "repo", "R", "build.R"))
#'   datom_repo_commit(conn, "Add build script")
#'
#'   # Idempotent: a clean tree is a no-op, not an error.
#'   datom_repo_commit(conn, "Nothing to do")
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_repo_commit <- function(conn, message, paths = NULL, push = TRUE) {
  .datom_check_git2r()
  .datom_check_git_verb_conn(conn, "datom_repo_commit")

  if (!is.character(message) || length(message) != 1L || !nzchar(message)) {
    cli::cli_abort("{.arg message} must be a non-empty character string.")
  }
  if (!is.null(paths) &&
      (!is.character(paths) || length(paths) == 0L || any(!nzchar(paths)))) {
    cli::cli_abort(c(
      "{.arg paths} must be a non-empty character vector of repo-relative paths, or NULL.",
      "i" = "{.code paths = NULL} stages everything {.code git add .} would stage."
    ))
  }
  if (!is.logical(push) || length(push) != 1L || is.na(push)) {
    cli::cli_abort("{.arg push} must be {.code TRUE} or {.code FALSE}.")
  }

  # Only when a push is actually going to be attempted: a repo with no remote
  # can still legitimately be committed to locally.
  if (isTRUE(push)) .datom_check_git_remote(conn$path, "datom_repo_commit")

  # The on-a-branch guard, asserted rather than inherited. It lives inside
  # `.datom_git_branch()` and is reached only from `.datom_git_push()`, so with
  # `push = FALSE` nothing would check it.
  #
  # Do NOT delete this as duplication of `.datom_check_git_current()`. That
  # function does reach `.datom_git_branch()`, but only after four early returns
  # -- no remote, the fetch failed, no upstream, and local SHA identical to
  # upstream -- so it guards a detached HEAD only when you are already out of
  # sync with the remote. A detached HEAD while up to date is the ordinary shape
  # of the mistake and passes straight through. This is also why the guard earns
  # a line at a low rate: a commit onto a detached HEAD succeeds, prints a SHA,
  # and becomes unreachable the moment you switch branches -- and with
  # `push = FALSE` there is no later push failure to reveal it.
  branch_name <- .datom_git_branch(conn$path)

  # Nothing-to-do is detected here rather than read off the helper's return
  # value. `.datom_git_commit()` returns HEAD's SHA when nothing ends up staged
  # (tests/testthat/test-utils-git.R "returns HEAD SHA when files are
  # unchanged"), which is a success value, so a wrapper that returned what it was
  # given could never report the no-op.
  repo <- git2r::repository(conn$path)
  head_before <- as.character(git2r::revparse_single(repo, "HEAD")$sha)

  # `files = "."` delegates the add-all to the same helper every other commit
  # site uses: "." passes its file-existence guard, and `git2r::add()` with
  # default flags respects `.gitignore` and stages deletions.
  #
  # `staged_deletions = TRUE` is the wrong spelling and the tempting one. It
  # exists to skip the existence check, and it sets `git2r::add(force = TRUE)`,
  # which stages gitignored files -- so it would quietly break the "minus
  # gitignored files" half of this contract. It is also unnecessary: default
  # flags already stage deletions.
  sha <- .datom_git_commit(
    conn$path,
    files   = paths %||% ".",
    message = message
  )
  created <- !identical(sha, head_before)

  if (created) {
    cli::cli_alert_success(
      "Committed {.val {substr(sha, 1L, 7L)}} on {.val {branch_name}}: {message}"
    )
  } else {
    cli::cli_alert_info("Nothing to commit -- no staged changes.")
  }

  if (isTRUE(push)) {
    # A commit just created is by definition one the remote lacks, so the ahead
    # count is only consulted on the no-op path -- which is the path that would
    # otherwise leave a previously failed push unrepaired forever.
    ahead <- if (created) NA_integer_ else .datom_git_ahead(conn$path)

    if (created || is.na(ahead) || ahead > 0L) {
      .datom_git_push(conn$path, pat = conn$github_pat)
    } else {
      cli::cli_alert_info(
        "Remote already has every commit on {.val {branch_name}}."
      )
    }
  }

  if (created) invisible(sha) else invisible(NULL)
}


#' Push the Data Repo to Its Remote
#'
#' Pushes the current branch of the data repo clone, through the same path
#' datom's own writes use -- so it inherits pull-before-push, upstream tracking,
#' and the on-a-branch guard.
#'
#' **Convergent, not imperative.** Nothing to push is an informational no-op
#' rather than an error, so calling it twice is safe and "make sure the remote
#' has everything" is a legal standalone operation.
#'
#' This is the other half of [datom_repo_commit()]`(push = FALSE)`. Without it,
#' "push what I already committed" would only be expressible as *another commit
#' attempt* -- and since `paths = NULL` is add-all, a caller who merely wanted to
#' push would risk committing whatever work in progress the tree happened to
#' hold.
#'
#' @param conn A `datom_conn` object with `role = "developer"` and a local repo
#'   path (`conn$path`).
#' @return Invisibly `TRUE`.
#' @export
#' @seealso [datom_repo_commit()], [datom_pull()]
#' @examples
#' # Offline, self-contained: a bare git repo stands in for GitHub and a
#' # local directory for object storage.
#' if (requireNamespace("git2r", quietly = TRUE)) {
#'   tmp <- tempfile("datom-example-")
#'   remote <- file.path(tmp, "remote.git")
#'   dir.create(remote, recursive = TRUE)
#'   git2r::init(remote, bare = TRUE)
#'
#'   store <- datom_store(
#'     data = datom_store_local(file.path(tmp, "storage")),
#'     github_pat = "example-token", # role selector; a local remote needs none
#'     data_repo_url = remote,
#'     validate = FALSE
#'   )
#'   datom_init_repo(file.path(tmp, "repo"), "example_project", store)
#'   conn <- datom_get_conn(file.path(tmp, "repo"), store)
#'
#'   # Commit now, push later.
#'   writeLines("notes", file.path(tmp, "repo", "NOTES.md"))
#'   datom_repo_commit(conn, "Add notes", push = FALSE)
#'   datom_repo_push(conn)
#'
#'   # Convergent: a second call has nothing to do and says so.
#'   datom_repo_push(conn)
#'
#'   unlink(tmp, recursive = TRUE)
#' }
datom_repo_push <- function(conn) {
  .datom_check_git2r()
  .datom_check_git_verb_conn(conn, "datom_repo_push")
  .datom_check_git_remote(conn$path, "datom_repo_push")

  ahead <- .datom_git_ahead(conn$path)

  # The on-a-branch guard is INHERITED here, unlike in `datom_repo_commit()`
  # where it is asserted up front. The asymmetry is deliberate and was checked by
  # breaking it rather than reasoned about: an explicit assert here reddened
  # nothing, because the early return below cannot be reached on a detached HEAD.
  # `.datom_git_ahead()` needs an upstream tracking ref, a detached HEAD has none,
  # so the count is NA, so this verb always goes on to `.datom_git_push()` --
  # which carries the guard. The commit verb has no such backstop when
  # `push = FALSE`, which is why the assert lives there and not here.
  if (!is.na(ahead) && ahead == 0L) {
    # Safe by the same property: an upstream ref exists, so HEAD is a branch.
    branch_name <- .datom_git_branch(conn$path)
    cli::cli_alert_info(
      "Nothing to push -- {.val {branch_name}} matches the remote."
    )
    return(invisible(TRUE))
  }

  .datom_git_push(conn$path, pat = conn$github_pat)

  # Deliberately no commit count in the message: the push pulls first, so a merge
  # can add a commit between the count above and what actually went out, and a
  # number that is wrong once in a while is worse than no number.
  # Read after the push rather than before: cli refuses a `{}` expression that
  # starts with a dot, and a local binding is clearer than working around that.
  branch_name <- .datom_git_branch(conn$path)
  cli::cli_alert_success("Pushed {.val {branch_name}} to the data remote.")

  invisible(TRUE)
}
