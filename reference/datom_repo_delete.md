# Delete the Data GitHub Repository and Local Clone

Deletes the data-side GitHub repository via the GitHub REST API and
removes the local clone directory. This is the data-side teardown step
for a datom project.

## Usage

``` r
datom_repo_delete(conn, confirm, force_gov_attached = FALSE)
```

## Arguments

- conn:

  A `datom_conn` object (developer role required).

- confirm:

  Character string. Must equal `conn$project_name` exactly. No
  interactive prompts – this must be supplied explicitly.

- force_gov_attached:

  Logical. `FALSE` (default) refuses to run when governance is attached
  (`!is.null(conn$gov_root)`). Pass `TRUE` only when called
  programmatically from `datomanager::gov_decommission()`.

## Value

Invisible `TRUE` on success.

## Details

**Solo projects** (no governance attached): call this together with
[`datom_storage_delete_prefix()`](https://amashadihossein.github.io/datom/reference/datom_storage_delete_prefix.md)
for a complete teardown.

**Governed projects**: use `datomanager::gov_decommission()` instead.
That function calls `datom_repo_delete()` internally (with
`force_gov_attached = TRUE`). Calling `datom_repo_delete()` directly on
a governed project without that flag is refused to prevent accidentally
orphaning the governance registration.

Steps:

1.  Delete the data GitHub repo via the GitHub REST API (requires
    `conn$github_pat` with `delete_repo` scope; skipped with a warning
    when `conn$github_pat` is NULL or when the remote is not GitHub).
    Aborts if `conn$data_repo_url` is not set.

2.  Remove the local clone directory (`conn$path`).

Each step is warn-and-continue on failure so the other still runs.

## See also

[`datom_storage_delete_prefix()`](https://amashadihossein.github.io/datom/reference/datom_storage_delete_prefix.md),
[`datom_repo_set_data_store()`](https://amashadihossein.github.io/datom/reference/datom_repo_set_data_store.md)

## Examples

``` r
# Offline, self-contained: a bare git repo stands in for GitHub and a
# local directory for object storage. Because the remote is not GitHub,
# the API deletion step is skipped and only the local clone is removed.
if (requireNamespace("git2r", quietly = TRUE)) {
  tmp <- tempfile("datom-example-")
  remote <- file.path(tmp, "remote.git")
  dir.create(remote, recursive = TRUE)
  git2r::init(remote, bare = TRUE)

  store <- datom_store(
    data = datom_store_local(file.path(tmp, "storage")),
    github_pat = "example-token", # role selector; a local remote needs none
    data_repo_url = remote,
    validate = FALSE
  )
  datom_init_repo(file.path(tmp, "repo"), "example_project", store)
  conn <- datom_get_conn(file.path(tmp, "repo"), store)

  # Solo project teardown (no governance): storage, then repo.
  datom_storage_delete_prefix(conn)
  datom_repo_delete(conn, confirm = conn$project_name)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b3370de950d/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b3370de950d/repo
#> ℹ Deleting data repo for "example_project"...
#> ℹ No GitHub remote found -- skipping repo deletion.
#> ℹ Removing local clone /tmp/RtmprkodKH/datom-example-1b3370de950d/repo...
#> ✔ Removed local clone.
```
