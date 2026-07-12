# Validate parents Field Structure

Checks that `parents` is either NULL or a list of entries each
containing non-empty string fields `source`, `table`, `version`, and
`data_sha`. WHERE an entry carries a non-NULL, non-empty
`source_lineage` field, it is validated via
[`.datom_validate_source_lineage()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_source_lineage.md).
Aborts with a cli error pointing to the first invalid entry.

## Usage

``` r
.datom_validate_parents(x)
```

## Arguments

- x:

  Value to validate.

## Value

Invisibly TRUE if valid.
