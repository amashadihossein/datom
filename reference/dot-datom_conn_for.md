# Scope-Selecting Connection Accessor

Returns the connection shaped for either the data or governance store.
The storage dispatch layer (`.datom_storage_*`) reads `conn$root`,
`conn$prefix`, and `conn$client`; this accessor swaps those fields when
callers need to operate on the governance store.

## Usage

``` r
.datom_conn_for(conn, scope = c("data", "gov"))
```

## Arguments

- conn:

  A `datom_conn` object.

- scope:

  Either `"data"` (default; returns `conn` unchanged) or `"gov"`
  (returns a sub-conn with governance fields swapped in).

## Value

A `datom_conn` object scoped to the requested store.

## Details

Single source of truth for "which store am I talking to right now?" –
replaces ad-hoc `conn$gov_client` peeking and the prior
`.datom_gov_conn()` helper.
