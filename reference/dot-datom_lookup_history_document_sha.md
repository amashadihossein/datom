# Most-recent version_history document_sha for a data_sha

The set half of
[`.datom_lookup_history_object_sha()`](https://amashadihossein.github.io/datom/reference/dot-datom_lookup_history_object_sha.md).
Unlike its parquet sibling there is no legacy population to return NULL
for: sets record `document_sha` from their first write, which is what
lets a set read treat a missing one as an error rather than a skip.

## Usage

``` r
.datom_lookup_history_document_sha(conn, name, data_sha)
```

## Arguments

- conn:

  A `datom_conn` object (developer, with local path).

- name:

  Artifact name.

- data_sha:

  Canonical content hash to match.

## Value

Character `document_sha`, or NULL.
