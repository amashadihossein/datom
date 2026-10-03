# Find the One Member a Name Refers To

**An ambiguous name aborts and teaches.** Two members can legitimately
share a name – the same artifact at two versions, for instance a current
table beside a locked baseline – so a name is not a key, and answering
with the first match would be plausible and wrong. The abort lists the
candidates with their versions and tags and names the two ways to
narrow: `tags`, which is the navigation axis people reach for, and
`version`, for exact pinning.

## Usage

``` r
.datom_find_member(members, name, tags = NULL, version = NULL)
```

## Arguments

- members:

  The set's member list.

- name:

  The name to look up.

- tags:

  Optional label filter.

- version:

  Optional version, or a prefix of one.

## Value

One member record.
