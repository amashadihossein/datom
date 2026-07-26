# Check if Object is a Local Store Component

Check if Object is a Local Store Component

## Usage

``` r
is_datom_store_local(x)
```

## Arguments

- x:

  Object to test.

## Value

TRUE or FALSE.

## Examples

``` r
tmp <- tempfile("datom_store_")
store <- datom_store_local(path = tmp, validate = TRUE)
#> ℹ Created store directory /tmp/RtmpecJCk2/datom_store_191a77fd4a55.
is_datom_store_local(store)
#> [1] TRUE
is_datom_store_local("not a store")
#> [1] FALSE
unlink(tmp, recursive = TRUE)
```
