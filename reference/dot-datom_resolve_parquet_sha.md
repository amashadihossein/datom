# Resolve the parquet_sha to Record and Whether to Upload

For a write that is not a no-op, decides which `parquet_sha` the new
metadata should carry and whether the freshly-serialized parquet bytes
need uploading. The caller performs the actual upload AFTER the git push
(git push is the serialization point); this function only decides.

## Usage

``` r
.datom_resolve_parquet_sha(
  conn,
  name,
  data_sha,
  new_parquet_sha,
  change_type,
  current
)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Table name.

- data_sha:

  Canonical content hash (the storage address).

- new_parquet_sha:

  SHA-256 of the freshly-serialized parquet bytes.

- change_type:

  `"metadata_only"` or `"full"` (never `"none"`).

- current:

  The current metadata (from
  [`.datom_has_changes()`](https://amashadihossein.github.io/datom/reference/dot-datom_has_changes.md)),
  or NULL.

## Value

List with `parquet_sha` (character or NULL) and `upload` (logical).

## Details

Cases:

- `metadata_only` – the `data_sha` is unchanged, so the parquet object
  already exists; carry forward the current metadata's `parquet_sha`
  (which may be NULL for a pre-cv1 table, leaving the integrity check
  skipped) and do not upload.

- `full` where a prior version already recorded a `parquet_sha` for this
  exact `data_sha` – the stored object exists and is pinned by that
  version; reuse its `parquet_sha` and do NOT re-upload (a fresh
  serialization can differ byte-for-byte and would break that version's
  integrity pin).

- `full` otherwise (brand-new content, or a legacy object with no
  recorded `parquet_sha`) – upload these bytes and record their hash.

This refines the design's literal step 7 (which gated on
[`.datom_storage_exists()`](https://amashadihossein.github.io/datom/reference/dot-datom_storage_exists.md)):
a recorded `parquet_sha` is the precise thing we must not clobber, and
its presence implies the object exists, so the history lookup subsumes
the existence check with identical behavior and one fewer storage
round-trip.
