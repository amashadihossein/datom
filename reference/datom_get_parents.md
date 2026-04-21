# Get Parent Lineage for a Table

Reads the `parents` field from a table's metadata. Returns the lineage
entries recorded at write time by dp_dev or other callers. For imported
tables or derived tables with no recorded lineage, returns `NULL`.

## Usage

``` r
datom_get_parents(conn, name, version = NULL)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- version:

  Optional metadata_sha (datom version). If NULL, reads current
  metadata. If provided, fetches the versioned metadata snapshot from
  S3.

## Value

List of parent entries (each with `source`, `table`, `version`), or
`NULL` if no lineage is recorded.
