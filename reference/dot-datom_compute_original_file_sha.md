# Compute SHA-256 of an Input File's Raw Bytes

Answers "have this input artifact's bytes changed?". This is the
`original_file_sha` of the three-SHA identity model – distinct from
`data_sha` (canonical logical content) and `parquet_sha` (stored bytes).

## Usage

``` r
.datom_compute_original_file_sha(path)
```

## Arguments

- path:

  Path to file.

## Value

Character SHA-256 hash.
