# Canonical Recourse String for an Unhashable Column

The single source of truth for the remediation advice attached to an
unsupported column. Returns `NULL` when `.datom_column_kind(x)`
classifies the column as hashable, otherwise the canonical recourse
string for the first matching offender category. Both
[`datom_check_hashable()`](https://amashadihossein.github.io/datom/reference/datom_check_hashable.md)
and the
[`.datom_canonical_hash()`](https://amashadihossein.github.io/datom/reference/dot-datom_canonical_hash.md)
all-offenders abort call this one function, so the checker's advice and
the abort's advice can never diverge.

## Usage

``` r
.datom_hash_recourse(x)
```

## Arguments

- x:

  A single column (vector) from a data frame.

## Value

`NULL` when `x` is hashable, otherwise a canonical recourse string.

## Details

The column name and class are added by the caller (a checker row or an
abort bullet); the strings here are type-scoped only. Detection order
matters: `POSIXlt` (a list under the hood) is matched before the generic
list rows; the nested-data-frame list row before the generic list row;
and the class-specific rows (`units`, `sfc`,
`yearmon`/`yearqtr`/`chron`) before the "other classed" fallback.
