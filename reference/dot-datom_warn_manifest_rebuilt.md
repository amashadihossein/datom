# Say That the Artifact Index Was Reconstructed

One warning per rebuild, carrying a condition class so a caller – or a
test – can count them rather than match on wording.

## Usage

``` r
.datom_warn_manifest_rebuilt(source, reason, declared, n)
```

## Arguments

- source:

  Which copy of the manifest was rebuilt.

- reason:

  `"schema"` (the document declares a format above this build) or
  `"shape"` (no artifact list this build can reach).

- declared:

  The version the document declared, for the schema reason.

- n:

  How many artifacts the rebuild found.

## Value

Invisibly `NULL`.

## Details

It names what happened, why, and what to do, in that order. The "why" is
the part a user cannot work out for themselves: a manifest whose
artifact list has moved somewhere this build cannot see looks exactly
like an empty repo, and the whole point of warning is that this
session's answers came from a reconstruction rather than from the
recorded index.
