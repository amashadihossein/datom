# List Available Tables

Lists tables from S3 manifest. Reads `.metadata/manifest.json` from S3
and returns a data frame with one row per table.

## Usage

``` r
datom_list(conn, pattern = NULL, include_versions = FALSE, short_hash = TRUE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- pattern:

  Optional glob pattern for filtering table names.

- include_versions:

  If TRUE, includes version count info.

- short_hash:

  If TRUE (default), truncates version and data SHA columns to 8
  characters for readability. Set to FALSE for full hashes.

## Value

Data frame with table info (name, current_version, last_updated, etc.).
