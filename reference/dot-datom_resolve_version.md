# Resolve Version to data_sha and parquet_sha

Given metadata from
[`.datom_read_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_metadata.md),
resolves a version spec to the corresponding `data_sha` (the storage
address) and the recorded `parquet_sha` (the stored-object integrity
hash). If `version` is NULL, resolves from the current `metadata.json`;
if a metadata_sha string, looks it up in `version_history.json`.

## Usage

``` r
.datom_resolve_version(metadata_list, version = NULL, name = "table")
```

## Arguments

- metadata_list:

  Return value of
  [`.datom_read_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_metadata.md).

- version:

  NULL (current) or a metadata_sha string.

- name:

  Table name (for error messages).

## Value

Named list with `data_sha` (character) and `parquet_sha` (character or
NULL) for the resolved version.

## Details

The `parquet_sha` may be `NULL`/`""` for pre-cv1 metadata, and for any
version-pinned read until `version_history` entries persist
`parquet_sha` (task 5.1). A `NULL`/empty `parquet_sha` tells
[`.datom_read_parquet()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_parquet.md)
to skip the integrity check (the intended pre-cv1 grace).
