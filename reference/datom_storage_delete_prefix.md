# Delete All Objects Under a datom Storage Prefix

Removes every file under `{prefix}/datom/{prefix_key}` from storage.
Pass `prefix_key = NULL` (the default) to delete the entire datom
namespace for this connection. A missing or empty prefix is a no-op.

## Usage

``` r
datom_storage_delete_prefix(conn, prefix_key = NULL)
```

## Arguments

- conn:

  A `datom_conn` object.

- prefix_key:

  Relative prefix to delete under (after `{prefix}/datom/`). `NULL`
  (default) deletes the entire datom namespace root for this connection.

## Value

Invisibly, a backend-specific value. For S3: the count of deleted
objects (0L if nothing found). For the local backend: `1L` if the prefix
directory existed and was removed, `0L` otherwise.

## Details

**Irreversible.** Intended for package developers building tools on top
of datom (e.g. datomanager for rollback or source deletion after
migration). End users performing a full project teardown should use
[`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md)
instead.

## Examples

``` r
if (FALSE) { # \dontrun{
# Delete a single table's objects
datom_storage_delete_prefix(conn, prefix_key = "demographics")

# Delete the entire datom namespace (use with care)
datom_storage_delete_prefix(conn)
} # }
```
