# List All Objects in a datom Storage Namespace

Returns the full storage keys of every object under the datom namespace
for this connection (`{prefix}/datom/...`). Intended for package
developers building tools on top of datom (e.g. datomanager); end users
typically do not need to inspect raw storage keys directly.

## Usage

``` r
datom_storage_list(conn)
```

## Arguments

- conn:

  A `datom_conn` object.

## Value

A character vector of full storage keys. May be empty if the namespace
contains no objects.

## Details

Keys are returned in their full storage-key form – for S3 that is
`"{prefix}/datom/..."` relative to the bucket root; for local backends
it is a path relative to `conn$root`. This mirrors the contract of the
internal
[`.datom_storage_list_objects()`](https://amashadihossein.github.io/datom/reference/dot-datom_storage_list_objects.md)
dispatch layer.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- datom_get_conn(path = ".", store = store)
keys <- datom_storage_list(conn)
length(keys)
} # }
```
