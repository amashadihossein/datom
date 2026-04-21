# Build Full S3 URI

Convenience function that combines bucket and key into an S3 URI.

## Usage

``` r
.datom_build_s3_uri(bucket, key)
```

## Arguments

- bucket:

  S3 bucket name.

- key:

  S3 object key (from
  [`.datom_build_storage_key()`](https://amashadihossein.github.io/datom/reference/dot-datom_build_storage_key.md)).

## Value

Character string S3 URI.
