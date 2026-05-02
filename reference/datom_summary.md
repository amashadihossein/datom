# Summarize a datom Project

Returns a compact, role-aware overview of a datom project: its name,
backend, table/version totals, last write time, and (for developers) the
git remote URL. Reads `.metadata/manifest.json` from the data store.

## Usage

``` r
datom_summary(conn)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

## Value

A `datom_summary` S3 object (a list with class `"datom_summary"`)
containing: `project_name`, `role`, `backend`, `root`, `prefix`,
`table_count`, `total_versions`, `last_updated`, `remote_url`.
`remote_url` is `NULL` for readers (no local data clone).
