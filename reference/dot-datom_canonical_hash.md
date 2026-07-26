# Compute the datom-cv1 Canonical Content Hash

The I/O-free identity engine for `datom-cv1`. Computes `data_sha` from
the in-memory logical values only – no parquet write, no CSV, no temp
files, no [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
or coercion, and never invokes arrow. Columns are read via `data[[i]]` /
`names(data)` and dimensions via
[`nrow()`](https://rdrr.io/r/base/nrow.html) /
[`ncol()`](https://rdrr.io/r/base/nrow.html), so two frames with equal
values hash identically regardless of container class (tibble vs
data.frame vs grouped_df), row names, or arrow version.

## Usage

``` r
.datom_canonical_hash(data)
```

## Arguments

- data:

  A data frame with at least one row and one column.

## Value

A list with `data_sha` (character) and `column_hashes` (an ordered list
of `list(name, sha)` in column order, computed once and reused for both
`data_sha` and the persisted column index).

## Details

Before encoding, every column is scanned through
[`.datom_hash_recourse()`](https://amashadihossein.github.io/datom/reference/dot-datom_hash_recourse.md);
if any are unsupported the function aborts **once**, listing every
offender with its class and canonical recourse. This fires during
`data_sha` computation (step 1 of
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)),
before any git or storage mutation, so a refusal leaves no partial
state.

The final hash is
`sha256( "datom-cv1" || f64le(nrow) || f64le(ncol) || concat(col_digest_hex...) )`.
