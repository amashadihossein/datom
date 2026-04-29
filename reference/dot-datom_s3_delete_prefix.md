# Delete All S3 Objects Under a Prefix

Lists every key under `{prefix}/datom/{prefix_key}` and deletes in
batches of up to 1000. A missing prefix is a no-op.

## Usage

``` r
.datom_s3_delete_prefix(conn, prefix_key = NULL)
```

## Arguments

- conn:

  A `datom_conn` object.

- prefix_key:

  Relative prefix (after `prefix/datom/`).

## Value

Invisibly, the count of deleted objects.
