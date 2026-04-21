# Download File from S3

Downloads an S3 object and writes it to a local path. Creates parent
directories if needed.

## Usage

``` r
.datom_s3_download(conn, s3_key, local_path)
```

## Arguments

- conn:

  A `datom_conn` object.

- s3_key:

  Relative S3 key (after `prefix/datom/`).

- local_path:

  Local file path (destination).

## Value

Invisible `TRUE` on success.
