# Most-recent version_history parquet_sha for a data_sha

The table half of
[`.datom_lookup_history_object_sha()`](https://amashadihossein.github.io/datom/reference/dot-datom_lookup_history_object_sha.md).
Returns NULL for a pre-cv1 history, whose entries predate `parquet_sha`
being recorded.

## Usage

``` r
.datom_lookup_history_parquet_sha(conn, name, data_sha)
```

## Arguments

- conn:

  A `datom_conn` object (developer, with local path).

- name:

  Artifact name.

- data_sha:

  Canonical content hash to match.

## Value

Character `parquet_sha`, or NULL.
