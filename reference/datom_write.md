# Write a datom Table

Writes data to a datom repository. Commits to git, pushes, and syncs to
S3.

## Usage

``` r
datom_write(
  conn,
  data = NULL,
  name = NULL,
  metadata = NULL,
  message = NULL,
  parents = NULL,
  source_lineage = NULL,
  .table_type = "derived",
  .original_file_sha = NULL,
  .original_format = NULL
)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- data:

  Data frame to write. If NULL with name, does metadata-only sync.

- name:

  Table name. If NULL with NULL data, does a data-only metadata sync to
  storage (manifest + per-table metadata).

- metadata:

  Optional list of custom metadata.

- message:

  Optional commit message.

- parents:

  Optional lineage: list of `list(source, table, version)` entries. Used
  by dp_dev to track dependency versions. NULL if lineage not recorded.
  At write time, `data_sha` is automatically added to each entry from
  the parent's local metadata snapshot (`NULL` if the snapshot is not in
  the clone).

- source_lineage:

  Required when `parents` is non-NULL. Pre-computed flat list of
  transitive non-derived source descriptors (each with `project`,
  `table`, `version_sha`). Set by dpbuild via the union of parents'
  `source_lineage` fields. NULL for tables without parents.

- .table_type:

  Internal. `"derived"` (default) or `"imported"` (set by
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)).

- .original_file_sha:

  Internal. SHA of source file (set by
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md));
  NULL for derived.

- .original_format:

  Internal. Original file format (set by
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md));
  NULL for derived.

## Value

List with deployment details.
