# Sync Data-Side Metadata to Storage

Mirrors the data repo's metadata to the data store so readers see
current state: the manifest (`.metadata/manifest.json`) and each
artifact's metadata (`{name}/.metadata/metadata.json`,
`version_history.json`). **Every artifact of either kind**, not tables
only – discovery is
[`.datom_clone_artifact_names()`](https://amashadihossein.github.io/datom/reference/dot-datom_clone_artifact_names.md)
and has been kind-agnostic since sets existed.

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

**It is not metadata-only, and the name understates it.** For a **set**,
a payload missing from storage is restored from the clone – see
`.datom_restore_set_payload()` in this file for the three conditions on
that. So this function can put content into storage, not just documents
about content.

Data-only: governance files (dispatch.json, ref.json,
migration_history.json) are not touched here. Governance sync is owned
by the governance layer (`gov_sync_dispatch()`).

**Two public routes reach this**, and both get the restore:
`datom_write(conn)` with no `data` and no `name` (the mirror-everything
route), and `datom_validate(fix = TRUE)`. Describing the restore as
repair-only would leave a reader surprised to see it fire under a write
verb.

Used after a failed upload, or by `datom_validate(fix = TRUE)`, to bring
storage back in line with the local data clone. Requires a developer
connection with a local repo path.
