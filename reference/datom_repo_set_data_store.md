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
if (FALSE) { # \dontrun{
new_store <- datom_store_s3(
  bucket     = "new-bucket",
  prefix     = "study-001",
  region     = "us-east-1",
  access_key = Sys.getenv("AWS_ACCESS_KEY_ID"),
  secret_key = Sys.getenv("AWS_SECRET_ACCESS_KEY"),
  validate   = FALSE
)
datom_repo_set_data_store(conn, new_store)
} # }
```
