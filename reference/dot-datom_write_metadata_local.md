# Write Metadata Files Locally

Writes `metadata.json` and appends to `version_history.json` in the
local git repo. Does NOT commit, push, or touch S3 — the caller handles
those.

## Usage

``` r
.datom_write_metadata_local(
  conn,
  name,
  metadata,
  metadata_sha,
  message = NULL,
  original_file_sha = NULL
)
```

## Arguments

- conn:

  A `datom_conn` object (must be developer with path).

- name:

  Table name.

- metadata:

  Named list for metadata.json.

- metadata_sha:

  SHA of the metadata (the datom "version").

- message:

  Commit message (stored in version_history entry).

- original_file_sha:

  SHA of the source file for imported tables; NULL for derived.

## Value

Invisible list with metadata_sha and local paths written.
