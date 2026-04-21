# Resolve a Storage Key to a Local Path

Builds the full filesystem path from `conn$root`, `conn$prefix`, and the
relative key segments.

## Usage

``` r
.datom_local_path(conn, key)
```

## Arguments

- conn:

  A `datom_conn` object with `backend = "local"`.

- key:

  Relative storage key (after `prefix/datom/`).

## Value

An absolute filesystem path.
