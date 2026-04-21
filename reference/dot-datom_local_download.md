# Download File from Local Storage

Copies a file from the store directory to a local path. Creates parent
directories if needed.

## Usage

``` r
.datom_local_download(conn, key, local_path)
```

## Arguments

- conn:

  A `datom_conn` object with `backend = "local"`.

- key:

  Relative storage key (after `prefix/datom/`).

- local_path:

  Local file path (destination).

## Value

Invisible `TRUE` on success.
