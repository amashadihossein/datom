# Apply a Set Sync Preview to a Product Repo's Set

The product-repo route of
[`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md).
See point 5 of this file's header: every check that needs no read comes
first, then the set is read (when not passed), then the stale and kind
checks against it, and only then one snapshot read per applied row.

## Usage

``` r
.datom_sync_set_apply(conn, set_name, manifest, sources, tags, x)
```

## Arguments

- conn:

  The product repo's developer connection.

- set_name:

  The set name `.datom/project.yaml` declares.

- manifest:

  The preview, or any frame with its columns.

- sources:

  One `datom_conn` or a list of them.

- tags:

  Labels for members added by `new` rows.

- x:

  A `datom_set`, or `NULL` to read the stored one.

## Value

The edited `datom_set`.
