# Most-recent version_history Stored-Object Hash for a data_sha

Scans the developer's local `version_history.json` (newest-first) for
the most recent entry whose `data_sha` matches and that carries a
non-empty hash in `field`. Returns NULL when none is found. Reads the
local git clone (offline-friendly); a stale clone is tolerated because
the subsequent git push serializes concurrent writers (a behind clone
fails to push before it can upload).

## Usage

``` r
.datom_lookup_history_object_sha(conn, name, data_sha, field)
```

## Arguments

- conn:

  A `datom_conn` object (developer, with local path).

- name:

  Artifact name.

- data_sha:

  Canonical content hash to match.

- field:

  `"parquet_sha"` (a table's stored parquet) or `"document_sha"` (a
  set's stored JSON payload).

## Value

The recorded hash, or NULL.

## Details

One scan serves both kinds, because the question is identical in each
case – *has this exact content already been stored, and under which byte
hash?* – and only the field name differs. Two copies would eventually
disagree about what counts as a usable recorded value, and the reuse
decision they feed is the one place where getting that wrong records a
hash of bytes nobody stored.
