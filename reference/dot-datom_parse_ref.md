# Parse a ref.json structure into a location list

Common parsing logic shared by storage-backed and clone-backed ref
readers.

## Usage

``` r
.datom_parse_ref(ref, source)
```

## Arguments

- ref:

  Parsed ref.json content (R list).

- source:

  Identifier for error messages (root, key, or path).

## Value

A named list with `root`, `prefix`, `region`.
