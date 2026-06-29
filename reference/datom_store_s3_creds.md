# Create a Credentials-Only S3 Store Component

Constructs an S3 store component that carries only AWS credentials – no
bucket, prefix, or region. The data location is resolved at connection
time from `ref.json` stored in the governance repo. This is the
recommended construction style for readers when a governance store is in
place.

## Usage

``` r
datom_store_s3_creds(access_key, secret_key, session_token = NULL)
```

## Arguments

- access_key:

  AWS access key ID.

- secret_key:

  AWS secret access key.

- session_token:

  Optional AWS session token (for temporary credentials).

## Value

A `datom_store_s3_creds` object.

## Details

A `datom_store_s3_creds` component **must** be paired with a governance
component inside
[`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md).
Attempting to create a composite store without governance will abort
with a clear message.

## Examples

``` r
creds <- datom_store_s3_creds(
  access_key = "AKIAIOSFODNN7EXAMPLE",
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
)
creds
#> 
#> ── datom S3 credentials-only store component 
#> • Bucket / prefix / region: <resolved from ref.json>
#> • Access key: "AKIA****"
#> • Secret key: "wJal****"
is_datom_store_s3_creds(creds)
#> [1] TRUE
```
