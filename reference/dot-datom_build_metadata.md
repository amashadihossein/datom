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
  original_format = NULL,
  project = NULL
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

- original_format:

  Extension of the source file (`"csv"`, `"parquet"`, ...), for imported
  tables. Recorded on the same only-when-non-NULL terms as
  `original_file_sha`, and for one reason: it was previously written
  onto the manifest row and nowhere else, which made it the single field
  a reconstructed index had to drop. It is **not** part of the version
  identity – see `.datom_metadata_excluded_fields`.

- project:

  The name of the project whose namespace this artifact is being written
  into, from the writing repo's own `.datom/project.yaml`. Recorded on
  the only-when-non-NULL terms `original_file_sha` uses, and last in the
  signature to match the order the other optional fields were added in.
  Note what that does **not** buy: every existing caller passes `data`
  and `data_sha` positionally and everything else by name, so an
  argument inserted higher up would shift nothing today – it is a
  convention here, not a guard.

  Why the writer records it at all: a **reader** connection's
  `project_name` is a string the caller passed to
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
  and nothing compares it against the repo, so anything derived from
  that label is unverified. A write always has a clone, so the name
  written here is the repo's own declaration – which is what later lets
  [`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md)
  and
  [`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md)
  cite a project without trusting a label.

## Value

Named list suitable for writing as metadata.json. Always carries
`kind = "table"` (which artifact kind the document describes),
`schema_version` (the format the document is written in) and
`hash_algo = "datom-cv1"`, and declares `parquet_sha` (left NULL here
and populated by
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
after change detection, since the stored- object hash is not knowable
until then; it is excluded from `metadata_sha` so this deferred
assignment is safe).
