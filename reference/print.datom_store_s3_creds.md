# Print a Credentials-Only S3 Store Component

Displays masked credentials and a note that location is resolved from
ref.json at connection time.

## Usage

``` r
# S3 method for class 'datom_store_s3_creds'
print(x, ...)
```

## Arguments

- x:

  A `datom_store_s3_creds` object.

- ...:

  Ignored.

## Value

Invisible `x`.

## Examples

``` r
creds <- datom_store_s3_creds(
  access_key = "AKIAIOSFODNN7EXAMPLE",
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
)
print(creds)
#> 
#> ── datom S3 credentials-only store component 
#> • Bucket / prefix / region: <resolved from ref.json>
#> • Access key: "AKIA****"
#> • Secret key: "****"
```
