# Tidy a Set Payload

The silent half of canonicalization: every spelling that states the same
fact is reduced to one, and nothing here is an error. Covers the
set-level tag map, each member's `id` key order, and each member's tag
map.

## Usage

``` r
.datom_tidy_set_payload(payload)
```

## Arguments

- payload:

  A list with `members` and optional set-level `tags`.

## Value

The tidied payload.

## Details

Member order and member deduplication are **not** here, because they
need the identity encoder and so can only run once validation has
established that every value is encodable – see
[`.datom_order_set_members()`](https://amashadihossein.github.io/datom/reference/dot-datom_order_set_members.md).

Key order is canonicalized at **three** levels, not two: the set's own
tag map, each member's `id`, and each member record's own `id` / `tags`
pair. Stopping at the second leaves one spelling uncanonical for no
reason – the encoder reaches both member slots by name, so the two
orders hash identically and serialise differently.

An empty tag map has its key **removed** rather than set to `NULL`, at
both levels. `jsonlite` writes a NULL element as
[`{}`](https://rdrr.io/r/base/Paren.html), and `"tags": {}` is the one
spelling a writer must never emit: the hash cannot tell it from an
absent map, so nothing would fail, and the stored file would carry an
empty object in every untagged member forever.
