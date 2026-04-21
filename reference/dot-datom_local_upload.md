# Upload File to Local Storage

Copies a local file to the store directory. Creates parent directories
if needed.

## Usage

``` r
.datom_local_upload(conn, local_path, key)
```

## Arguments

- conn:

  A `datom_conn` object with `backend = "local"`.

- local_path:

  Local file path to upload.

- key:

  Relative storage key (after `prefix/datom/`).

## Value

Invisible `TRUE` on success.
