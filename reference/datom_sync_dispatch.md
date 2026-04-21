# Sync Dispatch Metadata to S3

Updates all metadata in S3 to match the local git repository. This
includes repo-level files (dispatch.json, manifest.json,
migration_history.json) and per-table metadata (metadata.json,
version_history.json). Requires interactive confirmation unless
`.confirm = FALSE`.

## Usage

``` r
datom_sync_dispatch(conn, .confirm = TRUE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- .confirm:

  If `TRUE` (default), requires interactive confirmation before
  proceeding. Set to `FALSE` for non-interactive use.

## Value

Invisibly, a list with `repo_files` (character vector of uploaded
repo-level keys) and `tables` (list of per-table sync results).

## Details

Used after migration, dispatch changes, or any situation where S3
metadata may be out of sync with git.
