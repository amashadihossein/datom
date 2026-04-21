# Build a datom_conn from Store Components

Backend-aware helper that creates the appropriate client (S3 client or
NULL) and assembles a `datom_conn`. Used by
[`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md),
[`.datom_get_conn_developer()`](https://amashadihossein.github.io/datom/reference/dot-datom_get_conn_developer.md),
and
[`.datom_get_conn_reader()`](https://amashadihossein.github.io/datom/reference/dot-datom_get_conn_reader.md).

## Usage

``` r
.datom_build_init_conn(
  project_name,
  data_store,
  path,
  role,
  endpoint = NULL,
  gov_store = NULL
)
```

## Arguments

- project_name:

  Project name string.

- data_store:

  A store component (datom_store_s3 or datom_store_local).

- path:

  Local repo path (NULL for readers).

- role:

  One of "developer" or "reader".

- endpoint:

  Optional S3 endpoint URL.

- gov_store:

  A store component for governance (can be NULL).

## Value

A `datom_conn` object.
