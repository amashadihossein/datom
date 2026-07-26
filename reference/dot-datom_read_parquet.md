# Download and Read Parquet from S3

Downloads `{table}/{data_sha}.parquet` from S3 to a temporary file and
reads it via
[`arrow::read_parquet()`](https://arrow.apache.org/docs/r/reference/read_parquet.html).
When an expected `parquet_sha` is supplied (non-empty), the downloaded
object's SHA-256 is verified against it BEFORE parsing, so corruption or
tampering aborts rather than being silently read.

## Usage

``` r
.datom_read_parquet(conn, name, data_sha, parquet_sha = NULL)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Table name.

- data_sha:

  SHA identifying the parquet file.

- parquet_sha:

  Expected SHA-256 of the stored parquet object bytes, from the resolved
  metadata (see
  [`.datom_resolve_version()`](https://amashadihossein.github.io/datom/reference/dot-datom_resolve_version.md)).
  When non-empty, the downloaded file is verified against it and a
  mismatch aborts. When `NULL` or empty (pre-cv1 metadata, or a
  version-pinned read before task 5.1 persists it), the integrity check
  is skipped and the read succeeds.

## Value

Data frame.
