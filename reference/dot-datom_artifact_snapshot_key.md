# Build the Relative Key for a Versioned Metadata Snapshot

Note this is a different directory from the payload key: the snapshot
lives under `.metadata/` and is addressed by `metadata_sha` (the
version), whereas the payload sits beside it addressed by `data_sha`
(the content). Both end in `.json` for a set, which is exactly why they
are easy to confuse.

## Usage

``` r
.datom_artifact_snapshot_key(name, metadata_sha)
```

## Arguments

- name:

  Artifact name (validated).

- metadata_sha:

  The version (validated as 6-64 hex).

## Value

Character relative key, e.g. `"dm/.metadata/c3d4....json"`.
