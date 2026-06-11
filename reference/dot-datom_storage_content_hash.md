# Compute SHA-256 Hash of a Storage Object's Content

For S3, downloads the raw bytes and hashes in memory. For local, hashes
the file directly. Used by
[`datom_storage_verify()`](https://amashadihossein.github.io/datom/reference/datom_storage_verify.md)
in `content` mode.

## Usage

``` r
.datom_storage_content_hash(conn, rel_key)
```

## Arguments

- conn:

  A `datom_conn` object.

- rel_key:

  Relative storage key (after `{prefix}/datom/`).

## Value

Character SHA-256 hex string.
