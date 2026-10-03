# Resolve the document_sha to Record and Whether to Upload

The set analogue of
[`.datom_resolve_parquet_sha()`](https://amashadihossein.github.io/datom/reference/dot-datom_resolve_parquet_sha.md),
kept beside it so the two cannot drift: the decision is the same
decision, and both are the one place where "these are new bytes, so hash
them" is the wrong answer.

## Usage

``` r
.datom_resolve_document_sha(
  conn,
  name,
  data_sha,
  new_document_sha,
  change_type,
  current
)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Set name.

- data_sha:

  Canonical content hash (the storage address).

- new_document_sha:

  SHA-256 of the payload bytes just written to the clone.

- change_type:

  `"metadata_only"` or `"full"` (never `"none"`).

- current:

  The current metadata (from
  [`.datom_has_changes()`](https://amashadihossein.github.io/datom/reference/dot-datom_has_changes.md)),
  or NULL.

## Value

List with `document_sha` (character or NULL) and `upload` (logical).

## Details

**Recomputing the hash from freshly emitted bytes while reusing the
stored object records a hash of bytes nobody stored.** Nothing fails at
write time – it surfaces much later as a *refused read of a valid
version*, when the integrity gate compares the stored payload against a
hash taken from a different serialization of the same content. Sets
reach that state far more easily than tables do: for a table it takes an
`arrow` upgrade, while for a set an ordinary tag-value reorder is
enough, because several payload spellings share one `data_sha`.

Cases, mirroring the parquet ones:

- `metadata_only` – the `data_sha` is unchanged, so the payload object
  already exists; carry the current metadata's `document_sha` forward
  and do not upload. Structurally unreachable for a set today (a set's
  hashed fields are `data_sha`, `hash_algo` and `kind`, so unchanged
  content means an unchanged version), and handled anyway rather than
  assumed away.

- `full` where a prior version already recorded a `document_sha` for
  this exact `data_sha` – reuse it and do **not** re-upload.

- `full` otherwise – upload these bytes and record their hash.
