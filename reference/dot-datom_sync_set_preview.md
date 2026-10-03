# Map a Product Repo's Set Against Its Sources

The product-repo route of
[`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md).
Three kinds of read: the stored set (or none), one manifest per source,
nothing per artifact.

## Usage

``` r
.datom_sync_set_preview(conn, set_name, sources, pattern)
```

## Arguments

- conn:

  The product repo's developer connection.

- set_name:

  The set name `.datom/project.yaml` declares.

- sources:

  One `datom_conn` or a list of them.

- pattern:

  Glob filtering source artifact names.

## Value

The preview data frame; see
[`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md).
