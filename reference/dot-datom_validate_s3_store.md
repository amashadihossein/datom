# Validate S3 Store Connectivity

Checks bucket access via HeadBucket. This validates both credentials and
bucket existence/permissions in a single call.

## Usage

``` r
.datom_validate_s3_store(access_key, secret_key, session_token, region, bucket)
```

## Arguments

- access_key:

  AWS access key ID.

- secret_key:

  AWS secret access key.

- session_token:

  Optional session token.

- region:

  AWS region.

- bucket:

  Bucket name.

## Value

Invisible TRUE on success.
