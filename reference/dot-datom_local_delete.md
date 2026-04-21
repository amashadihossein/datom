# Delete a File from Local Storage

Delete a File from Local Storage

## Usage

``` r
.datom_local_delete(conn, key)
```

## Arguments

- conn:

  A `datom_conn` object with `backend = "local"`.

- key:

  Relative storage key (after `prefix/datom/`).

## Value

Invisible `TRUE` on success.
