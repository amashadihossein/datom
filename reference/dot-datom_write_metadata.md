# Write Metadata Files to Git and S3 (Legacy Wrapper)

Calls
[`.datom_write_metadata_local()`](https://amashadihossein.github.io/datom/reference/dot-datom_write_metadata_local.md)
then
[`.datom_push_metadata_s3()`](https://amashadihossein.github.io/datom/reference/dot-datom_push_metadata_s3.md).
Kept for backward compatibility. Does NOT commit or push.

## Usage

``` r
.datom_write_metadata(conn, name, metadata, metadata_sha, message = NULL)
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

## Value

Invisible list with metadata_sha, git_paths, and s3_keys.
