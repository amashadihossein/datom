# Check if Object is a Credentials-Only S3 Store Component

Check if Object is a Credentials-Only S3 Store Component

## Usage

``` r
is_datom_store_s3_creds(x)
```

## Arguments

- x:

  Object to test.

## Value

TRUE or FALSE.

## Examples

``` r
creds <- datom_store_s3_creds(
  access_key = "AKIAIOSFODNN7EXAMPLE",
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
)
is_datom_store_s3_creds(creds)
#> [1] TRUE
is_datom_store_s3_creds("not a store")
#> [1] FALSE
```
