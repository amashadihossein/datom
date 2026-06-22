# Sync Data-Side Metadata to Storage

Mirrors the data repo's metadata to the data store so readers see
current state: the manifest (`.metadata/manifest.json`) and each table's
metadata (`{name}/.metadata/metadata.json`, `version_history.json`).

## Usage

``` r
.datom_sync_data_metadata(conn, .confirm = TRUE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- .confirm:

  If `TRUE` (default), requires interactive confirmation before
  proceeding. Set to `FALSE` for non-interactive use.

## Value

Invisibly, a list with `repo_files` (character vector of synced keys)
and `tables` (list of per-table sync results).

## Details

Data-only: governance files (dispatch.json, ref.json,
migration_history.json) are not touched here. Governance sync is owned
by the governance layer (`gov_sync_dispatch()`).

Used after a failed upload, or by `datom_validate(fix = TRUE)`, to bring
storage metadata back in line with the local data clone. Requires a
developer connection with a local repo path.
