# Check if S3 Object Exists

Uses a HEAD request for efficiency. Returns `TRUE` if the object exists,
`FALSE` on 404/NoSuchKey. Any other error (403, network) is re-thrown.

## Usage

``` r
.datom_s3_exists(conn, s3_key)
```

## Arguments

- conn:

  A `datom_conn` object.

- s3_key:

  Relative S3 key (after `prefix/datom/`).

## Value

`TRUE` or `FALSE`.
