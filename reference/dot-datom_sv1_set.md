# Encode a Set Payload for datom-sv1

`set(p) = h(0x05 || map(p.tags) || concat(sort(unique(member(m)), radix)))`.

## Usage

``` r
.datom_sv1_set(payload, what = "payload")
```

## Arguments

- payload:

  A list with `members` and optional set-level `tags`.

- what:

  Position label used in error messages.

## Value

A raw vector of 32 bytes.

## Details

Member digests are deduped and sorted, exactly like tag values:
arrangement is presentation, not content. The producer of a member list
is normally a script, so an insertion-order refactor must not mint a new
version of a citable artifact.

A zero-member payload aborts, mirroring
[`.datom_canonical_hash()`](https://amashadihossein.github.io/datom/reference/dot-datom_canonical_hash.md)'s
refusal of a zero-row or zero-column table.
