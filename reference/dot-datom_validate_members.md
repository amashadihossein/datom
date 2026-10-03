# Validate a Member List

Checks that `members` is a list of member records, each an `id` of
exactly `project`, `name`, `kind`, `version` – all single non-empty
strings, with `kind` one of `"table"` or `"set"` – plus an optional
`tags` map. Aborts naming the first offending member, with a remedy
pointing at
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md).

## Usage

``` r
.datom_validate_members(x)
```

## Arguments

- x:

  Value to validate: a list of member records, or `NULL`.

## Value

Invisibly `TRUE`.

## Details

**This validator sees one member at a time**, so two payload-level cases
are deliberately not here and belong to the set write, which is the only
place that sees a whole payload:

- **zero members** – an empty member list passes here;

- **the same `id` listed twice with different `tags`** – invisible from
  a per-member view, and not caught by deduplication either, since a
  member's digest covers its tags, so both entries survive.

Set-level tags never pass through here at all; the write validates those
with
[`.datom_validate_tag_map()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_tag_map.md)
directly.
