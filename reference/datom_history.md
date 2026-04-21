# Show Version History

Shows version history for a table by reading `version_history.json` from
S3. Returns the most recent `n` versions.

## Usage

``` r
datom_history(conn, name, n = 10, short_hash = TRUE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- n:

  Maximum number of versions to return. Default 10.

- short_hash:

  If TRUE (default), truncates version and data SHA columns to 8
  characters for readability. Set to FALSE for full hashes.

## Value

Data frame with columns: version, data_sha, timestamp, author,
commit_message.
