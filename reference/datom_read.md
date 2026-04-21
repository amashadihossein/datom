# Read a datom Table

Unified read function with dispatch via `dispatch.json`. Reads from S3
metadata cache for data readers.

## Usage

``` r
datom_read(conn, name, version = NULL, context = NULL, ...)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- version:

  Optional metadata_sha (datom version). If NULL, uses current.

- context:

  Optional context for dispatch (e.g., "default", "cached").

- ...:

  Additional parameters forwarded to routed function.

## Value

Data frame or routed function result.
