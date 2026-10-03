#' @section Key terms:
#' - **Project**: one body of data you manage together, such as one clinical
#'   study. It has a name, a GitHub repository that records every change, and a
#'   storage location that holds the data itself; the data never goes into git.
#'   Created once with [datom_init_repo()].
#' - **Store**: tells datom where a project's data lives (a local folder or an
#'   S3 bucket) and, if you will write, your GitHub token. Built with
#'   [datom_store()].
#' - **Developer and reader**: the two roles. A developer has a GitHub token and
#'   a local copy of the project, and can write. A reader needs only access to
#'   the storage -- no token, no git -- and can only read. datom picks the role
#'   from whether the store carries a token.
#' - **Connection (`conn`)**: a pointer to one project, returned by
#'   [datom_get_conn()]. It records which project, where its data is kept, and
#'   your role, and it is the first argument to almost every other function.
#' - **Table**: a data frame saved in datom under a name, such as `dm`. Saved
#'   with [datom_write()] or [datom_sync()], read with [datom_read()].
#' - **Version**: a long identifier for one exact saved state of a table or a
#'   set. Old versions are never overwritten, and a save that changes nothing
#'   makes no new version. [datom_history()] lists them; pass one as
#'   `version =` to read it back.
#' - **Sync manifest**: the preview [datom_sync_manifest()] returns -- one row
#'   per file in `input_files/`, each marked new, changed, unchanged, or in a
#'   format datom cannot read -- which you then pass to [datom_sync()].
#' - **Set**: a named, versioned list of exact versions of tables (or other
#'   sets), so a whole collection can be cited with one version string. It holds
#'   no data.
#' - **Member**: one entry in a set -- one table or set, pinned at one version,
#'   with optional labels such as `type = "input"`.
#' - **Parent, source and lineage**: a parent is a table another table was made
#'   from, named with [datom_parent()] before writing. A source is an original
#'   imported table at the start of the chain. Lineage is the record of both,
#'   read with [datom_get_lineage()].
"_PACKAGE"

# Allow use of dot when piping
utils::globalVariables(".")

## usethis namespace: start
#' @importFrom rlang .data
#' @importFrom rlang %||%
## usethis namespace: end
NULL
