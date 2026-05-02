# List Objects Under a Storage Prefix

Returns the keys of every object under `{prefix}/datom/{prefix_arg}`.
Keys are returned in their full storage-key form (i.e. including the
`{prefix}/datom/` portion), matching what
[`.datom_local_list_objects()`](https://amashadihossein.github.io/datom/reference/dot-datom_local_list_objects.md)
and
[`.datom_s3_list_objects()`](https://amashadihossein.github.io/datom/reference/dot-datom_s3_list_objects.md)
return.

## Usage

``` r
.datom_storage_list_objects(conn, prefix)
```

## Arguments

- conn:

  A `datom_conn` object.

- prefix:

  Relative prefix to list under (after `prefix/datom/`).

## Value

Character vector of full storage keys (may be empty).
