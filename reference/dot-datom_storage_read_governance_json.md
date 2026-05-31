# Read governance.json Mirror from Data Storage

Returns the parsed list, or NULL when the key is absent. Aborts on any
non-not-found storage error or on failed schema validation.

## Usage

``` r
.datom_storage_read_governance_json(conn)
```

## Arguments

- conn:

  A `datom_conn` for the data store.

## Value

Parsed list or NULL.
