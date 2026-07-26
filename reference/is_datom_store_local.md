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
#> ℹ Created store directory /tmp/RtmpVrYwqy/datom_store_1a9a1a32f7f3.
is_datom_store_local(store)
#> [1] TRUE
is_datom_store_local("not a store")
#> [1] FALSE
unlink(tmp, recursive = TRUE)
```
