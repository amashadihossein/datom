# Build Connection from Local Repo + Store (Developer Path)

Reads `.datom/project.yaml` for project identity and cross-checks
against the store config. Uses the store for credentials.

## Usage

``` r
.datom_get_conn_developer(path, store, endpoint = NULL)
```

## Arguments

- path:

  Path to datom repository.

- store:

  A `datom_store` object.

- endpoint:

  Optional S3 endpoint URL.

## Value

A `datom_conn` object.
