# Reconstruct the Whole Artifact Index from Storage

One storage listing plus two reads per artifact. The result is a
complete manifest in this build's shape: the artifact rows, the summary
counters recomputed from them, and the current format declared.

## Usage

``` r
.datom_rebuild_manifest(conn, prior = NULL)
```

## Arguments

- conn:

  A `datom_conn` object.

- prior:

  The document being replaced, or `NULL`.

## Value

A manifest in current shape.

## Details

`project_name` and `updated_at` are carried from the document being
replaced when it has them. Both are recorded facts about the repo rather
than about the artifacts, so neither is recoverable from a listing – and
inventing a fresh `updated_at` would state that the index was rewritten
now, when nothing was written at all.

Aborts rather than returning a partial index. Half an artifact list is
indistinguishable from a repo that only has half those artifacts, and
the caller's job is to decide what an unreachable store means – see
[`.datom_read_manifest()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_manifest.md),
which keeps a schema refusal separate from an IO failure on the way back
out.
