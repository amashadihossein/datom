# Delete All Objects Under a Storage Prefix

Removes every file under `prefix/datom/{prefix_key}` from storage. For
S3 this lists then batch-deletes. For local it removes the directory. A
missing prefix is a no-op (returns 0L). Pass `prefix_key = NULL` to
delete the entire datom namespace for this connection.

## Usage

``` r
.datom_storage_delete_prefix(conn, prefix_key = NULL)
```

## Arguments

- conn:

  A `datom_conn` object.

- prefix_key:

  Relative prefix to delete under (after `prefix/datom/`). `NULL`
  deletes the entire datom namespace root.

## Value

Invisibly, the count of deleted objects.
