# Read and Parse JSON from S3

Downloads an S3 object, reads it as text, and parses as JSON. Uses
`simplifyVector = FALSE` to keep lists as lists (matching how
[`.datom_s3_write_json()`](https://amashadihossein.github.io/datom/reference/dot-datom_s3_write_json.md)
writes them).

## Usage

``` r
.datom_s3_read_json(conn, s3_key)
```

## Arguments

- conn:

  A `datom_conn` object.

- s3_key:

  Relative S3 key (after `prefix/datom/`).

## Value

Parsed R list.
