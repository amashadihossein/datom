# Delete governance.json Mirror from Data Storage

Removes the governance.json mirror during project teardown. No-ops
silently when the key is absent. Deletion is implemented via
prefix-delete on the exact key path.

## Usage

``` r
.datom_storage_delete_governance_json(conn)
```

## Arguments

- conn:

  A `datom_conn` for the data store.

## Value

Invisible NULL.
