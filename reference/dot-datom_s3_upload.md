# Upload File to S3

Reads a local file as raw bytes and uploads via `put_object()`.

## Usage

``` r
.datom_s3_upload(conn, local_path, s3_key)
```

## Arguments

- conn:

  A `datom_conn` object.

- local_path:

  Local file path to upload.

- s3_key:

  Relative S3 key (after `prefix/datom/`).

## Value

Invisible `TRUE` on success.
