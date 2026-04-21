# Write an R List to Storage as JSON

Write an R List to Storage as JSON

## Usage

``` r
.datom_storage_write_json(conn, key, data)
```

## Arguments

- conn:

  A `datom_conn` object.

- key:

  Relative storage key (after `prefix/datom/`).

- data:

  An R list to serialize to JSON.

## Value

Invisible `TRUE` on success.
