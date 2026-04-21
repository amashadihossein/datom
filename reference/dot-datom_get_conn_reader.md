# Build Connection from Store (Reader Path)

Constructs a connection from a store object and project_name. Uses the
data component of the store for S3 configuration.

## Usage

``` r
.datom_get_conn_reader(store, project_name, endpoint = NULL)
```

## Arguments

- store:

  A `datom_store` object.

- project_name:

  Project name string.

- endpoint:

  Optional S3 endpoint URL.

## Value

A `datom_conn` object.
