# The Zero-Row Shape of a Member Listing

In one place, and carrying every column a populated result carries, so
[`rbind()`](https://rdrr.io/r/base/cbind.html) of an empty listing and a
populated one works.
[`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
had exactly this defect twice: a zero-row frame built from zero rows
loses its columns, and the failure only shows up when somebody binds two
results.

## Usage

``` r
.datom_empty_member_frame()
```

## Value

A zero-row data frame.
