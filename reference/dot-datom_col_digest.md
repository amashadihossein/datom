# Compute a Single Column's datom-cv1 Digest

Encodes one column to its per-column SHA-256 hex digest for `datom-cv1`,
as `sha256( utf8(tag) || utf8(colname) || 0x00 || payload )`. The tag is
the kind returned by
[`.datom_column_kind()`](https://amashadihossein.github.io/datom/reference/dot-datom_column_kind.md)
and the payload is produced by the shared encoders. Labelled columns
strip their class and attributes and re-dispatch on the bare underlying
vector, so value labels never enter identity.

## Usage

``` r
.datom_col_digest(name, x)
```

## Arguments

- name:

  Column name (used verbatim, UTF-8, in the digest input).

- x:

  The column vector.

## Value

A 64-character SHA-256 hex string.
