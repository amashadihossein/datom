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
  parents = NULL
)
```

## Arguments

- data:

  Data frame being written.

- data_sha:

  SHA-256 of the parquet-formatted data.

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

## Value

Named list suitable for writing as metadata.json.
