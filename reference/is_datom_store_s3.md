# Check if Object is an S3 Store Component

Check if Object is an S3 Store Component

## Usage

``` r
is_datom_store_s3(x)
```

## Arguments

- x:

  Object to test.

## Value

TRUE or FALSE.

## Examples

``` r
s3 <- datom_store_s3(
  bucket = "my-datom-bucket",
  access_key = "AKIAIOSFODNN7EXAMPLE",
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  validate = FALSE
)
is_datom_store_s3(s3)
#> [1] TRUE
is_datom_store_s3("not a store")
#> [1] FALSE
```
