# Write an R List to Local Storage as JSON

Serializes `data` to JSON and writes to the store directory. Creates
parent directories if needed.

## Usage

``` r
.datom_local_write_json(conn, key, data)
```

## Arguments

- conn:

  A `datom_conn` object with `backend = "local"`.

- key:

  Relative storage key (after `prefix/datom/`).

- data:

  An R list to serialize to JSON.

## Value

Invisible `TRUE` on success.
