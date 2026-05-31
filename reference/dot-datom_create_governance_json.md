# Build governance.json Content

Constructs the governance pointer list that is written to both the local
git copy and the data-store mirror.

## Usage

``` r
.datom_create_governance_json(gov_repo_url, gov_store, attached_at = NULL)
```

## Arguments

- gov_repo_url:

  HTTPS clone URL of the governance git repository.

- gov_store:

  A `datom_store_s3` or `datom_store_local` component representing the
  governance storage (location + credentials). Only the location fields
  are persisted; credentials are discarded.

- attached_at:

  Optional ISO 8601 UTC timestamp string. Defaults to the current system
  time.

## Value

Named list suitable for serialisation to JSON.
