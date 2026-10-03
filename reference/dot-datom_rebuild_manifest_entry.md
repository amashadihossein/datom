# Rebuild One Artifact's Manifest Row from Its Own Documents

Every field on the row is copied from `metadata.json`, counted from
`version_history.json`, or – for a set's member count – read from the
payload. The row's shape has to match what
`.datom_update_manifest_entry()` writes, field for field, or a rebuilt
repo answers differently from a healthy one – so the two are pinned
against each other by a test rather than by matching comments.

## Usage

``` r
.datom_rebuild_manifest_entry(conn, name)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Artifact name.

## Value

A named list: one manifest artifact row.

## Details

`last_updated` is the one field with no recorded source: the writer
stamps the wall clock at the moment it rewrites the row, and that moment
is not in any document. The version's own `created_at` is used instead,
which is the closest true statement available – when this artifact's
current state was written.

**A set's row is built from different fields, and costs a third read.**
A set carries `member_count` where a table carries `size_bytes`, and
that count lives in the payload rather than in either document read here
– hence
[`.datom_rebuild_member_count()`](https://amashadihossein.github.io/datom/reference/dot-datom_rebuild_member_count.md).
Putting a `size_bytes` on a set row instead would be worse than leaving
the count out: the default is `0`, which has length 1 and therefore
survives
[`purrr::compact()`](https://purrr.tidyverse.org/reference/keep.html),
so the row would state that the artifact is zero bytes.
