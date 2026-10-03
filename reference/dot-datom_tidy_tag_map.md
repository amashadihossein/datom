# Tidy a Tag Map

Radix-sorts the keys, drops a key whose value is empty, and tidies each
value. Never aborts: a malformed map is passed through for the validator
to report.

## Usage

``` r
.datom_tidy_tag_map(tags)
```

## Arguments

- tags:

  A named list, or `NULL`.

## Value

The tidied map, or `NULL` when nothing is left.

## Details

Radix sort throughout, i.e. C-locale byte order, so the canonical form
does not depend on the machine's collation – the same reason the
identity hash sorts that way.
