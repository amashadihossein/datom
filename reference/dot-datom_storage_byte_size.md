# Get Byte Size of a Single Storage Object

Returns the byte size of the object at `rel_key` without reading its
content. For S3 uses `HEAD`; for local uses
[`fs::file_size()`](https://fs.r-lib.org/reference/file_info.html).
Errors if the object is not found.

## Usage

``` r
.datom_storage_byte_size(conn, rel_key)
```

## Arguments

- conn:

  A `datom_conn` object.

- rel_key:

  Relative storage key (after `{prefix}/datom/`).

## Value

Numeric byte count.
