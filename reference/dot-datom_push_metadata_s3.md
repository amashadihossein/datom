# Push Metadata Files to S3

Uploads `metadata.json`, `version_history.json`, and a versioned
snapshot to S3. Called AFTER git commit+push succeeds to maintain local
→ git → S3 ordering.

## Usage

``` r
.datom_push_metadata_s3(conn, name, metadata, metadata_sha, commit_sha = NULL)
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

- commit_sha:

  The commit that produced `metadata_sha`, or `NULL` from a caller that
  made no commit.

## Value

Invisible character vector of S3 keys written.

## Details

**The stored history carries one field the clone's copy cannot**, and
this is the reason `commit_sha` exists as an argument here: the clone's
`version_history.json` is inside the commit that would name it, so only
a storage-bound copy can say which commit produced a version. The upload
sends the clone's file wholesale, so without the merge below the field
would survive on the newest version only – the second write of an
artifact would erase the first version's commit id.

`commit_sha` is **derived, never authored**. It reaches this function as
an argument only because the caller one layer up already holds the
commit it just made; no exported verb accepts it, and every other
entry's value is worked out from git. See `R/version-commit.R`.
