# Push Metadata Files to S3

Uploads `metadata.json`, `version_history.json`, and a versioned
snapshot to S3. Called AFTER git commit+push succeeds to maintain local
→ git → S3 ordering.

## Usage

``` r
.datom_push_metadata_s3(conn, name, metadata, metadata_sha)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Table name.

- metadata:

  Named list for metadata.json.

- metadata_sha:

  SHA of the metadata (the datom "version").

## Value

Invisible character vector of S3 keys written.
