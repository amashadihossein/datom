# Print a Local Store Component

Displays store configuration.

## Usage

``` r
# S3 method for class 'datom_store_local'
print(x, ...)
```

## Arguments

- x:

  A `datom_store_local` object.

- ...:

  Ignored.

## Value

Invisible `x`.

## Examples

``` r
tmp <- tempfile("datom_store_")
store <- datom_store_local(path = tmp, validate = TRUE)
#> ℹ Created store directory /tmp/Rtmpeon3tF/datom_store_1957290f3135.
print(store)
#> 
#> ── datom local store component 
#> • Path: /tmp/Rtmpeon3tF/datom_store_1957290f3135
#> • Validated: TRUE
unlink(tmp, recursive = TRUE)
```
