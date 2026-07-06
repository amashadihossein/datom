# Check if Object is a datom Store

Check if Object is a datom Store

## Usage

``` r
is_datom_store(x)
```

## Arguments

- x:

  Object to test.

## Value

TRUE or FALSE.

## Examples

``` r
tmp <- tempfile("datom_store_")
store <- datom_store(
  data = datom_store_local(path = tmp),
  data_repo_url = "https://github.com/example/my-project",
  validate = FALSE
)
#> ℹ Created store directory /tmp/Rtmp589ZMh/datom_store_1a685bc1ab92.
is_datom_store(store)
#> [1] TRUE
is_datom_store("not a store")
#> [1] FALSE
unlink(tmp, recursive = TRUE)
```
