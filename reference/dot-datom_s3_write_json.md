# Write an R List to S3 as JSON

Serializes `data` to JSON via
[`jsonlite::toJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html)
and uploads to S3.

## Usage

``` r
.datom_s3_write_json(conn, s3_key, data)
```

## Arguments

- conn:

  A `datom_conn` object.

- s3_key:

  Relative S3 key (after `prefix/datom/`).

- data:

  An R list to serialize to JSON.

## Value

Invisible `TRUE` on success.
