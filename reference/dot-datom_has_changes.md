# Detect Changes Against Current Metadata

Compares the proposed metadata_sha against the current version in S3.
Returns the type of change detected.

## Usage

``` r
.datom_has_changes(conn, name, new_data_sha, new_metadata_sha)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Table name.

- new_data_sha:

  SHA of the new data.

- new_metadata_sha:

  SHA of the new metadata (from
  [`.datom_compute_metadata_sha()`](https://amashadihossein.github.io/datom/reference/dot-datom_compute_metadata_sha.md)).

## Value

Named list with two elements: `change_type` – `"none"` (no change),
`"metadata_only"` (data same, metadata changed), or `"full"` (data
changed) – and `current`, the already-read current metadata (or `NULL`
for a brand-new table). Returning `current` lets
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
reuse it (the `metadata_only` `parquet_sha` carry-forward and the
revert-to-older history scan) without a second storage read.
