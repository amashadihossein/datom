# Print a datom Store

Displays store configuration with masked secrets.

## Usage

``` r
# S3 method for class 'datom_store'
print(x, ...)
```

## Arguments

- x:

  A `datom_store` object.

- ...:

  Ignored.

## Value

Invisible `x`.

## Examples

``` r
tmp <- tempfile("datom_store_")
store <- datom_store(
  data = datom_store_local(path = tmp),
  data_repo_url = "https://github.com/example/my-project",
  validate = FALSE
)
#> ℹ Created store directory /tmp/RtmpWbqD0Z/datom_store_198f388fa94a.
print(store)
#> 
#> ── datom store 
#> • Role: "reader"
#> • Data repo: <https://github.com/example/my-project>
#> 
#> Governance:
#> not attached
#> 
#> Data:
#> 
#> ── datom local store component 
#>   • Path: /tmp/RtmpWbqD0Z/datom_store_198f388fa94a
#>   • Validated: TRUE
unlink(tmp, recursive = TRUE)
```
