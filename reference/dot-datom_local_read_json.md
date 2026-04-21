# Read and Parse JSON from Local Storage

Reads a JSON file from the store and parses it. Uses
`simplifyVector = FALSE` to match S3 behavior.

## Usage

``` r
.datom_local_read_json(conn, key)
```

## Arguments

- conn:

  A `datom_conn` object with `backend = "local"`.

- key:

  Relative storage key (after `prefix/datom/`).

## Value

Parsed R list.
