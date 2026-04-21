# Resolve Version to data_sha

Given metadata from
[`.datom_read_metadata()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_metadata.md),
resolves a version spec to the corresponding `data_sha`. If `version` is
NULL, returns the current `data_sha` from `metadata.json`. If a
metadata_sha string, looks it up in `version_history.json`.

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

Character string `data_sha`.
