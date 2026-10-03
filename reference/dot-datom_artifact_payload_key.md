# Build the Relative Key for an Artifact's Payload

The stored data object for an artifact: parquet for a table, JSON for a
set. This is the single place that decision is made.

## Usage

``` r
.datom_artifact_payload_key(name, sha, kind = c("table", "set"))
```

## Arguments

- name:

  Artifact name (validated).

- sha:

  Content hash addressing the payload – `data_sha` (validated as 6-64
  hex, since it is spliced into a storage key).

- kind:

  `"table"` (parquet payload) or `"set"` (JSON payload).

## Value

Character relative key, e.g. `"dm/9f2a....parquet"`.
