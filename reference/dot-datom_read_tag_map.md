# Normalize a Parsed Tag Map's Values

Applies
[`.datom_read_string_array()`](https://amashadihossein.github.io/datom/reference/dot-datom_read_string_array.md)
to every value and does nothing else: no key sorting, no value sorting,
no deduplication, no dropping of an empty-valued key. A map with no
names is returned untouched rather than refused, for the same reason a
single odd value is.

## Usage

``` r
.datom_read_tag_map(tags)
```

## Arguments

- tags:

  A parsed tag map, or `NULL`.

## Value

The map with each value normalized, or `NULL`.
