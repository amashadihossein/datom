# Rewrite the Data Store Pointer in project.yaml

Updates `storage.data` in `.datom/project.yaml` to point at `new_store`,
then commits and pushes the data repo. This is the data-side bookkeeping
step of a store relocation.

## Usage

``` r
datom_repo_set_data_store(conn, new_store, message = NULL)
```

## Arguments

- conn:

  A `datom_conn` object with `role = "developer"` and a local repo path
  (`conn$path`).

- new_store:

  A `datom_store_s3` or `datom_store_local` component (i.e. the
  data-side component of a
  [`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md)
  object, not the full composite).

- message:

  Optional commit message. Defaults to
  `"Update data store: {project_name}"`.

## Value

Invisibly, the SHA of the resulting commit.

## Details

**Read-modify-write contract**: the function reads the full existing
`project.yaml`, modifies **only** `storage.data`, and writes back. It
never reconstructs the file from conn fields. This preserves
`storage.governance` on governed projects (it is permanent once written)
and any other fields not owned by this function.

For governed projects the authoritative address is `ref.json` in the gov
repo – this function updates only the local data clone so that
[`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
stays consistent after migration. It is called by
`datomanager::gov_migrate_data()` after the ref switch, never before.

## See also

[`datom_storage_copy()`](https://amashadihossein.github.io/datom/reference/datom_storage_copy.md),
[`datom_storage_verify()`](https://amashadihossein.github.io/datom/reference/datom_storage_verify.md),
[`datom_repo_delete()`](https://amashadihossein.github.io/datom/reference/datom_repo_delete.md)

## Examples

``` r
# Offline, self-contained: a bare git repo stands in for GitHub and a
# local directory for object storage.
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

  # Repoint project.yaml at a relocated data store.
  new_store <- datom_store_local(file.path(tmp, "storage-relocated"))
  datom_repo_set_data_store(conn, new_store)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a313094d17d/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmp0YCcPh/datom-example-1a313094d17d/repo
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a313094d17d/storage-relocated.
#> ✔ Updated .datom/project.yaml data store pointer for "example_project".
```
