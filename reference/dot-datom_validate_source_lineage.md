# Validate source_lineage Field Structure

Checks that `source_lineage` is either NULL or a list of entries each
containing non-empty string fields `project`, `table`, and
`version_sha`. Extra fields are allowed (pass-through). Aborts with a
cli error pointing to the first invalid entry.

## Usage

``` r
.datom_validate_source_lineage(x)
```

## Arguments

- x:

  Value to validate.

## Value

Invisibly TRUE if valid.
