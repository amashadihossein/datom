# Download and Read Parquet from S3

Downloads `{table}/{data_sha}.parquet` from S3 to a temporary file and
reads it via
[`arrow::read_parquet()`](https://arrow.apache.org/docs/r/reference/read_parquet.html).

## Usage

``` r
.datom_read_parquet(conn, name, data_sha)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Table name.

- data_sha:

  SHA identifying the parquet file.

## Value

Data frame.
