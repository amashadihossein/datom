# Declare a parent for lineage

Resolves a parent table against a single project connection and returns
a pure-data lineage record. The parent's authoritative `data_sha` and
its `source_lineage` are read from the parent's own versioned metadata
snapshot at `{table}/.metadata/{version}.json`; a caller cannot supply
or override `data_sha` (there is no `data_sha` parameter). The returned
record retains no live connection and is serializable as plain data.

## Usage

``` r
datom_parent(conn, table, version)
```

## Arguments

- conn:

  A `datom_conn` scoped to the parent's project store, from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- table:

  Parent table name (single non-empty validated string).

- version:

  Parent version (metadata_sha; single non-empty string).

## Value

A list with exactly `source`, `table`, `version`, `data_sha`, and
`source_lineage`. `source` is the parent connection's `project_name`;
`source_lineage` is `NULL` when the snapshot carries none.

## Details

Same-project and cross-project parents are declared identically – the
only difference is which connection is passed. `source` is always
derived from the connection's `project_name`.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- datom_get_conn(path = "path/to/repo", store = store)
p <- datom_parent(conn, "dm", "v_dm_9f3")
} # }
```
