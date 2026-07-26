# Classify a Column for Canonical Hashing

The single supported-type classifier underneath the `datom-cv1` hash. It
returns the dispatch *kind* for a hashable column or `NULL` for an
unsupported one. Both the all-offenders gate
([`.datom_hash_recourse()`](https://amashadihossein.github.io/datom/reference/dot-datom_hash_recourse.md))
and the per-column encoder in
[`.datom_canonical_hash()`](https://amashadihossein.github.io/datom/reference/dot-datom_canonical_hash.md)
consume this one function, so a column the gate accepts can never be one
the encoder cannot encode.

## Usage

``` r
.datom_column_kind(x)
```

## Arguments

- x:

  A single column (vector) from a data frame.

## Value

One of the kind tags `"i64"`, `"chr"`, `"date"`, `"time"`, `"drtn"`,
`"num"` for a supported column, or `NULL` when unsupported.

## Details

Dispatch is evaluated in a fixed order (reordering can silently change
hashes):
[`bit64::integer64`](https://bit64.r-lib.org/reference/bit64-package.html),
factor, `Date` (incl.
[`data.table::IDate`](https://rdrr.io/pkg/data.table/man/IDateTime.html)),
`POSIXct`, `difftime`/`hms`,
[`data.table::ITime`](https://rdrr.io/pkg/data.table/man/IDateTime.html),
then `haven_labelled`/`labelled`/`labelled_spss` (stripped to their
underlying type and re-classified), then any other explicitly-classed
column is refused, then unclassed atomics (logical/integer/double as
`"num"`, character as `"chr"`), and finally any other type is refused.

Detection uses [`inherits()`](https://rdrr.io/r/base/class.html) /
[`typeof()`](https://rdrr.io/r/base/typeof.html) /
[`is.object()`](https://rdrr.io/r/base/is.object.html) class-string
matching only – it adds no new package dependency (`bit64`,
`data.table`, `haven` are recognised by their class strings, not by
being loaded).
