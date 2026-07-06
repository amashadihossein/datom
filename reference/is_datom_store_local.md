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
#> ℹ Created store directory /tmp/RtmpHbIpp1/datom_store_19657d03dc6a.
is_datom_store_local(store)
#> [1] TRUE
is_datom_store_local("not a store")
#> [1] FALSE
unlink(tmp, recursive = TRUE)
```
