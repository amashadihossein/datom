# Print a Member Link

Print a Member Link

## Usage

``` r
# S3 method for class 'datom_link'
print(x, ...)
```

## Arguments

- x:

  A `datom_link` from a member of a set read with
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md).

- ...:

  Ignored.

## Value

Invisible `x`.

## Examples

``` r
# See datom_get_set() for a runnable set example; a link is one of its
# members' `$fetch` elements.
print(names(formals(datom_get_set)))
#> [1] "conn"    "name"    "version"
```
