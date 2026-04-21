# Validate Data Store Reachability

Checks that the data store at the ref-resolved location is reachable.
For S3: HeadBucket. For local: dir_exists. Provides actionable error
messages when data is unreachable after migration.

## Usage

``` r
.datom_check_data_reachable(conn, migrated = FALSE)
```

## Arguments

- conn:

  A `datom_conn` object (already ref-resolved).

- migrated:

  Logical, whether a migration was detected.

## Value

Invisible TRUE on success. Warns on network error (offline use ok).
