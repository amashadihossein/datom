# List S3 Objects Under a Prefix

Lists every key under `{prefix}/datom/{prefix_key}` and returns relative
keys (relative to the datom namespace, i.e. with the `prefix/datom/`
part stripped). Paginates via `ContinuationToken`.

## Usage

``` r
.datom_s3_list_objects(conn, prefix)
```

## Arguments

- conn:

  A `datom_conn` object.

- prefix:

  Relative prefix (after `prefix/datom/`).

## Value

Character vector of relative keys (may be empty).
