# Delete governance.json Mirror from Data Storage

Called by
[`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md).
No-ops silently when key is absent. Deletion is implemented via
prefix-delete on the exact key path; the single-key delete dispatch
helper is wired in Chunk 7.

## Usage

``` r
.datom_storage_delete_governance_json(conn)
```

## Arguments

- conn:

  A `datom_conn` for the data store.

## Value

Invisible NULL.
