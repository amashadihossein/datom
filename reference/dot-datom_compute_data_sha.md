# Compute the datom-cv1 Content Hash of a Data Frame

Thin wrapper over
[`.datom_canonical_hash()`](https://amashadihossein.github.io/datom/reference/dot-datom_canonical_hash.md)
returning only the scalar `data_sha`. Preserves the scalar-string
contract for callers that need just the content hash (for example the
[`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)
self-lineage entry). Row and column order are significant; there is no
sort option.

## Usage

``` r
.datom_compute_data_sha(data)
```

## Arguments

- data:

  Data frame to hash.

## Value

Character SHA-256 `data_sha`.
