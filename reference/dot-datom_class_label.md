# Human-Readable Class Label for a Column

Renders the label shown for a column in the all-offenders abort bullets
and in the
[`datom_check_hashable()`](https://amashadihossein.github.io/datom/reference/datom_check_hashable.md)
report: the collapsed `class(x)` string for an explicitly-classed
column, or `typeof(x)` for an unclassed one (so a list column reads
`list`, a complex column `complex`, and a `units` column `units`).

## Usage

``` r
.datom_class_label(x)
```

## Arguments

- x:

  A single column (vector) from a data frame.

## Value

A single character string.
