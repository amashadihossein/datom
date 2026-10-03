# Expand a Member List to One Row Per Member Per Tag Value

The shared expansion both shaping verbs are built on – see point 1 of
this file's header for why there is exactly one of these.

## Usage

``` r
.datom_expand_member_tags(members)
```

## Arguments

- members:

  A non-empty member list.

## Value

A data frame of `.member`, `name`, `project`, `version`, `kind`, `key`,
`value`.

## Details

Carries a `.member` column holding the member's position, which is what
lets
[`datom_structure_members()`](https://amashadihossein.github.io/datom/reference/datom_structure_members.md)
get back from a row to the record it came from.
[`datom_list_members()`](https://amashadihossein.github.io/datom/reference/datom_list_members.md)
drops it, because a position is not a fact about a member.
