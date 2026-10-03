# Every Metadata Field Name This Build Knows

The two halves of the classification joined: the fields that make up a
version's identity, and the fields datom deliberately keeps out of it. A
name in neither half is a name this build cannot place.

## Usage

``` r
.datom_metadata_known_fields()
```

## Value

Character vector of field names, unsorted.

## Details

A function rather than a stored vector, for two reasons that both bite.
`R/` is sourced alphabetically (DESCRIPTION declares no `Collate`), and
this file sorts before `R/utils-sha.R` where both halves are defined –
so a constant built from them here would be built from values that do
not exist yet and the package would fail to install. Deriving it at call
time also means it cannot fall out of step with either half.

**Append-only.** A name that has ever been written must keep classifying
forever, including names datom no longer writes: a build that forgets
one meets an older document, fails to place a field it should know, and
starts preserving as unfamiliar something it could have handled – or,
once the write-side refusal lands, refuses the document outright and
blocks the upgrade direction, which must always work.
