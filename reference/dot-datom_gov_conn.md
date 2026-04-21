# Create a Governance-Scoped Connection

Returns a lightweight connection that routes S3 operations to the
governance store. The storage dispatch layer
(`.datom_storage_write_json`, etc.) read `conn$root`, `conn$prefix`, and
`conn$client` — this swaps in the governance equivalents so the helpers
work transparently.

## Usage

``` r
.datom_gov_conn(conn)
```

## Arguments

- conn:

  A `datom_conn` object with governance fields populated.

## Value

A list with `root`, `prefix`, `client` pointing to the governance store.
