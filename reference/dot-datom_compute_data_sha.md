# Compute SHA-256 of Data

Computes a deterministic SHA-256 hash of a data frame by writing to
parquet format. By default, preserves column and row order — reordering
either will produce a different hash.

## Usage

``` r
.datom_compute_data_sha(data, sort_columns = FALSE, sort_rows = FALSE)
```

## Arguments

- data:

  Data frame to hash.

- sort_columns:

  If TRUE, sorts columns alphabetically before hashing. Useful when
  column order shouldn't affect identity.

- sort_rows:

  If TRUE, sorts rows by all columns before hashing. Useful when row
  order shouldn't affect identity.

## Value

Character SHA-256 hash.
