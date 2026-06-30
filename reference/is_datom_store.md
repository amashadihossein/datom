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
#> ℹ Created store directory /tmp/RtmpGjIVo1/datom_store_19aa2ccea05d.
is_datom_store(store)
#> [1] TRUE
is_datom_store("not a store")
#> [1] FALSE
unlink(tmp, recursive = TRUE)
```
