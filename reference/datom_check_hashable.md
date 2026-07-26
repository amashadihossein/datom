# Check Whether a Table Can Be Hashed by datom

Pre-flight check for the datom table contract. Reports, per column,
whether
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
can hash it and – when it cannot – exactly what to do about it. Run this
before a write to fix a table in one pass instead of discovering
offenders one error at a time.

## Usage

``` r
datom_check_hashable(data)
```

## Arguments

- data:

  A data frame to check.

## Value

Invisibly, a data frame with one row per column of `data` and columns:

- `column`:

  Column name.

- `class`:

  Collapsed class string, or
  [`typeof()`](https://rdrr.io/r/base/typeof.html) when unclassed.

- `status`:

  `"ok"` or `"unsupported"`.

- `recourse`:

  `NA` when ok, otherwise how to make the column hashable.

## Details

datom identifies a table version by a canonical hash of its contents
(`data_sha`), which requires every column to be a supported type:
logical, integer, double, character, factor, `Date`, `POSIXct`,
`difftime`/`hms`,
[`data.table::ITime`](https://rdrr.io/pkg/data.table/man/IDateTime.html)/`IDate`,
[`bit64::integer64`](https://bit64.r-lib.org/reference/bit64-package.html),
or a labelled vector over one of those. List columns (including nested
data frames, blobs, and `POSIXlt`), `complex`, `raw`, `sf` geometry,
`units`, and `zoo`/`chron` columns are refused with specific advice.

The advice printed here is the same single-source recourse text
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
would abort with, so the two can never disagree.

## See also

[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)

## Examples

``` r
# A clean table: every column is a supported type
clean <- data.frame(
  id = 1:3,
  score = c(1.5, 2.5, 3.5),
  label = c("a", "b", "c"),
  grp = factor(c("x", "y", "x")),
  day = as.Date(c("2026-01-01", "2026-01-02", "2026-01-03"))
)
datom_check_hashable(clean)
#> ✔ All 5 columns are hashable. This table is ready for `datom_write()`.

# An offending table: a list column and a complex column
messy <- data.frame(id = 1:2)
messy$notes <- list(c("a", "b"), "c")
messy$z <- c(1 + 2i, 3 + 4i)
report <- datom_check_hashable(messy)
#> ✖ 2 of 3 columns are not hashable.
#> ✖ Column notes (<list>): List and blob columns are not hashable. Flatten to one
#>   value per row with tidyr::unnest(), or serialize each element to character
#>   (for example with jsonlite::toJSON() per element), before writing.
#> ✖ Column z (<complex>): Complex columns are not hashable. Split into separate
#>   real and imaginary numeric columns, or convert to character, before writing.
#> ℹ Fix these before `datom_write()`, which refuses the whole table until they are resolved.
report[report$status == "unsupported", c("column", "recourse")]
#>   column
#> 2  notes
#> 3      z
#>                                                                                                                                                                                               recourse
#> 2 List and blob columns are not hashable. Flatten to one value per row with tidyr::unnest(), or serialize each element to character (for example with jsonlite::toJSON() per element), before writing.
#> 3                                                                   Complex columns are not hashable. Split into separate real and imaginary numeric columns, or convert to character, before writing.
```
