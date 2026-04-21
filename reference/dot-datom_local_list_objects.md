# List Objects in Local Storage

Lists files under a given prefix in the store.

## Usage

``` r
.datom_local_list_objects(conn, prefix)
```

## Arguments

- conn:

  A `datom_conn` object with `backend = "local"`.

- prefix:

  Relative prefix to list under.

## Value

Character vector of relative keys (relative to `conn$root`).
