# Normalize a prefix value to NULL or a non-empty string

A NULL prefix serializes to JSON as an empty object () and reads back as
an empty list, not NULL. Empty strings can also creep in. This collapses
all empty-ish forms (NULL, [`list()`](https://rdrr.io/r/base/list.html),
`""`, `NA`) to NULL so that location equality checks survive a JSON
round-trip.

## Usage

``` r
.datom_normalize_prefix(prefix)
```

## Arguments

- prefix:

  A raw prefix value from a parsed ref.json.

## Value

NULL or a single non-empty character string.
