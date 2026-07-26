# Most-recent version_history parquet_sha for a data_sha

Scans the developer's local `version_history.json` (newest-first) for
the most recent entry whose `data_sha` matches and that carries a
non-empty `parquet_sha`. Returns NULL when none is found – including the
transitional period before task 5.1 persists `parquet_sha` into history
entries, and for pre-cv1 histories. Reads the local git clone
(offline-friendly); a stale clone is tolerated because the subsequent
git push serializes concurrent writers (a behind clone fails to push
before it can upload).

## Usage

``` r
.datom_lookup_history_parquet_sha(conn, name, data_sha)
```

## Arguments

- conn:

  A `datom_conn` object (developer, with local path).

- name:

  Table name.

- data_sha:

  Canonical content hash to match.

## Value

Character `parquet_sha`, or NULL.
