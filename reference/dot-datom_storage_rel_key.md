# Strip datom Namespace Prefix from a Full Storage Key

Converts a full storage key (as returned by
[`.datom_storage_list_objects()`](https://amashadihossein.github.io/datom/reference/dot-datom_storage_list_objects.md))
to a relative key suitable for upload/download helpers (after
`{prefix}/datom/`).

## Usage

``` r
.datom_storage_rel_key(full_key, conn)
```

## Arguments

- full_key:

  Full storage key string.

- conn:

  The source `datom_conn` (provides prefix for stripping).

## Value

Relative key string.
