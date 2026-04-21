# Read Table Metadata from S3

Fetches both `metadata.json` (current state) and `version_history.json`
(version index) for a given table from S3.

## Usage

``` r
.datom_read_metadata(conn, name)
```

## Arguments

- conn:

  A `datom_conn` object.

- name:

  Table name (validated).

## Value

Named list with `current` (metadata.json contents) and `history`
(version_history.json contents as a list of entries).
