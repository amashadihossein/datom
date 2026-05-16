# Get Lineage for a Table

Reads lineage metadata for a table. Depending on `depth`, returns either
the pre-computed transitive source list (`source_lineage`) or the
immediate parent list (`parents`). Both fields are stored flat in the
table's metadata – no walking or cross-project resolution is performed.

## Usage

``` r
datom_get_lineage(conn, name, version = NULL, depth = c("source", "parents"))
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- version:

  Optional metadata_sha (datom version). If NULL, reads current
  metadata. If provided, fetches the versioned metadata snapshot.

- depth:

  One of `"source"` (default) or `"parents"`.

## Value

For `depth = "source"`: list of source-table descriptors (each with
`project`, `table`, `version_sha`), or `NULL` if the field is absent.
For `depth = "parents"`: list of parent entries (each with `source`,
`table`, `version`), or `NULL` if no lineage is recorded.

## Details

The two fields answer different questions:

- `"source"`: "what raw datasets does this table ultimately depend on?"
  (audit, regulatory disclosure, reproducibility scope). Pre-computed by
  dpbuild from the union of parents' `source_lineage` fields.

- `"parents"`: "what did this table come from one step back?"
  (debugging, diff, replay). Equivalent to
  [`datom_get_parents()`](https://amashadihossein.github.io/datom/reference/datom_get_parents.md).

## See also

[`datom_get_parents()`](https://amashadihossein.github.io/datom/reference/datom_get_parents.md)
for a direct shorthand for the `"parents"` depth.
