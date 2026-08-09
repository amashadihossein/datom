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
#> ℹ Created store directory /tmp/RtmprkodKH/datom_store_1b33f2f9026.
print(store)
#> 
#> ── datom local store component 
#> • Path: /tmp/RtmprkodKH/datom_store_1b33f2f9026
#> • Validated: TRUE
unlink(tmp, recursive = TRUE)
```
