# Build Metadata Object

Constructs the metadata list for a table write, including auto-computed
fields (data_sha, dimensions, colnames, timestamp, datom_version) and
any user-supplied custom metadata.

## Usage

``` r
.datom_build_metadata(
  data,
  data_sha,
  custom = NULL,
  table_type = "derived",
  size_bytes = NULL,
  parents = NULL,
  source_lineage = NULL,
  original_file_sha = NULL,
  column_hashes = NULL
)
```

## Arguments

- data:

  Data frame being written.

- data_sha:

  datom-cv1 canonical content hash of the data.

- custom:

  Optional named list of user-supplied custom metadata.

- table_type:

  `"derived"` (default, from `datom_write`) or `"imported"` (from
  `datom_sync`).

- size_bytes:

  Size of the parquet file in bytes. NULL if not yet computed.

- parents:

  Lineage list of parent entries (each with source, table, version), or
  NULL if no lineage recorded.

- source_lineage:

  Pre-computed transitive source list (each entry with project, table,
  version_sha), or NULL.

- original_file_sha:

  SHA-256 of the source file, for imported tables. Included in the
  metadata **only when non-NULL**; the derived path omits it from the
  object entirely (not present-with-NULL).

- column_hashes:

  Ordered list of per-column `list(name, sha)` digests from
  [`.datom_canonical_hash()`](https://amashadihossein.github.io/datom/reference/dot-datom_canonical_hash.md),
  or NULL. Excluded from `metadata_sha` (see
  [`.datom_compute_metadata_sha()`](https://amashadihossein.github.io/datom/reference/dot-datom_compute_metadata_sha.md)).

## Value

Named list suitable for writing as metadata.json. Always carries
`hash_algo = "datom-cv1"` and declares `parquet_sha` (left NULL here and
populated by
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
after change detection, since the stored- object hash is not knowable
until then; it is excluded from `metadata_sha` so this deferred
assignment is safe).
