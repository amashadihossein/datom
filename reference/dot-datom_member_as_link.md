# Build the Resolvable Link for One Member Record

The single route from a record to a callable link, used by
[`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md)
and by every leaf
[`datom_structure_members()`](https://amashadihossein.github.io/datom/reference/datom_structure_members.md)
produces – and it is the same factory
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
uses for `$fetch`. So kind dispatch, and the project hint that lives
beside it, have one implementation reached by every route.

## Usage

``` r
.datom_member_as_link(record, what = "member")
```

## Arguments

- record:

  A member record, with or without a `fetch` element.

- what:

  Noun for messages about an unusable record.

## Value

A `datom_link`.

## Details

Any `fetch` already on the record is dropped first, so a record that
came from a read produces a link over pure data rather than a link
carrying a link.
