# Write governance.json Mirror to Data Storage

Writes `content` to `.metadata/governance.json` in the data store. Uses
[`.datom_storage_write_json()`](https://amashadihossein.github.io/datom/reference/dot-datom_storage_write_json.md)
dispatch (backend-neutral).

## Usage

``` r
.datom_storage_write_governance_json(conn, content)
```

## Arguments

- conn:

  A `datom_conn` for the data store.

- content:

  Named list from
  [`.datom_create_governance_json()`](https://amashadihossein.github.io/datom/reference/dot-datom_create_governance_json.md).

## Value

Invisible NULL.
