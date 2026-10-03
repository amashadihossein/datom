# One Line Describing a Member, for a Message That Has to Name Several

Name, kind, the first 8 characters of its version, and its tags. The
version costs nothing – a read member's `id$version` is the full
recorded string – and it is what the reader needs to narrow an ambiguous
name.

## Usage

``` r
.datom_member_lines(members)
```

## Arguments

- members:

  A member list.

## Value

A character vector, one entry per member.
