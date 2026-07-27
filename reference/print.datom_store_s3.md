# Print an S3 Store Component

Displays store configuration with masked secrets.

## Usage

``` r
# S3 method for class 'datom_store_s3'
print(x, ...)
```

## Arguments

- x:

  A `datom_store_s3` object.

- ...:

  Ignored.

## Value

Invisible `x`.

## Examples

``` r
s3 <- datom_store_s3(
  bucket = "my-datom-bucket",
  access_key = "AKIAIOSFODNN7EXAMPLE",
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  validate = FALSE
)
print(s3)
#> 
#> ── datom S3 store component 
#> • Bucket: "my-datom-bucket"
#> • Region: "us-east-1"
#> • Access key: "AKIA****"
#> • Secret key: "****"
#> • Validated: FALSE
```
