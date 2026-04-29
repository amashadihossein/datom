# Sync Dispatch Metadata to Storage

Updates metadata in storage to match the current state in git/local
files. This includes repo-level governance files (dispatch.json,
ref.json, migration_history.json) and per-table metadata (metadata.json,
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

Invisibly, a list with `repo_files` (character vector of synced
keys/paths) and `tables` (list of per-table sync results).

## Details

Governance files (dispatch.json, ref.json, migration_history.json) are
re-written to the governance repo via git commit + push and then
mirrored to gov storage. Per-table metadata is written from the data
clone to the data store. Requires a developer connection with a gov
clone.

Used after migration, dispatch changes, or any situation where storage
metadata may be out of sync with git.
