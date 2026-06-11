# Copy a Single Storage Object Between Two Connections

Dispatches on the (from_backend, to_backend) pair. For local-\>local
uses [`fs::file_copy`](https://fs.r-lib.org/reference/copy.html); all
other combos transfer raw bytes.

## Usage

``` r
.datom_copy_one(from_conn, to_conn, rel_key)
```

## Arguments

- from_conn:

  Source `datom_conn`.

- to_conn:

  Destination `datom_conn`.

- rel_key:

  Relative storage key (after `{prefix}/datom/`).

## Value

Named list with `key` (character) and `bytes` (numeric).
