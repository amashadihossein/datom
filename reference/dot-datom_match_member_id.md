# The Position of a Member Named by a Record or a Link

Matched on the whole `id`, which is a member's only unique key: the same
name can appear twice, and two projects may both hold a `dm`.

## Usage

``` r
.datom_match_member_id(members, record)
```

## Arguments

- members:

  The set's member list.

- record:

  The record the caller passed, or the one a link carries.

## Value

An integer vector of positions, normally of length one.
