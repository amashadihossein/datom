# Validate Git-Storage Consistency

Checks that git metadata matches S3 storage for all tables and
repo-level files. Reports mismatches as a structured result.

## Usage

``` r
datom_validate(conn, fix = FALSE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- fix:

  If `TRUE`, attempts to fix inconsistencies by syncing metadata to S3
  via
  [`datom_sync_dispatch()`](https://amashadihossein.github.io/datom/reference/datom_sync_dispatch.md).

## Value

A list with:

- valid:

  Logical — `TRUE` if everything is consistent.

- repo_files:

  Data frame of repo-level file checks.

- tables:

  Data frame of per-table checks.

- fixed:

  Logical — `TRUE` if `fix = TRUE` was applied.
