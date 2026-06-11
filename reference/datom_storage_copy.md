# Copy All Objects Between Two datom Storage Namespaces

Enumerates all objects under `from_conn`'s datom namespace and streams
each one to `to_conn`'s datom namespace. All four backend combinations
are supported:

## Usage

``` r
datom_storage_copy(from_conn, to_conn)
```

## Arguments

- from_conn:

  A `datom_conn` object (source).

- to_conn:

  A `datom_conn` object (destination).

## Value

A data frame with columns `key` (character, relative key after
`{prefix}/datom/`) and `bytes` (numeric, byte count per object). Returns
a zero-row data frame if the source namespace is empty.

## Details

- **local -\> local**: direct file copy via
  [`fs::file_copy()`](https://fs.r-lib.org/reference/copy.html).

- **local -\> S3**: reads raw bytes and uploads via `put_object`.

- **S3 -\> local**: downloads via `get_object` and writes to disk.

- **S3 -\> S3**: streams bytes through memory (get then put).
  Server-side `copy_object` (same-region optimisation) is reserved for a
  future release.

This is a policy-free primitive. It does not modify the source
namespace, update `project.yaml`, or switch `ref.json`. For a complete
managed migration (governed projects) use
`datomanager::gov_migrate_data()`. For solo-project relocation combine
this function with
[`datom_repo_set_data_store()`](https://amashadihossein.github.io/datom/reference/datom_repo_set_data_store.md).

## See also

[`datom_storage_verify()`](https://amashadihossein.github.io/datom/reference/datom_storage_verify.md),
[`datom_storage_list()`](https://amashadihossein.github.io/datom/reference/datom_storage_list.md),
[`datom_storage_delete_prefix()`](https://amashadihossein.github.io/datom/reference/datom_storage_delete_prefix.md),
[`datom_repo_set_data_store()`](https://amashadihossein.github.io/datom/reference/datom_repo_set_data_store.md)

## Examples

``` r
if (FALSE) { # \dontrun{
from_conn <- datom_get_conn(path = ".", store = old_store)
to_conn   <- datom_get_conn(path = ".", store = new_store)
copied    <- datom_storage_copy(from_conn, to_conn)
nrow(copied)  # number of objects copied
sum(copied$bytes)  # total bytes
} # }
```
