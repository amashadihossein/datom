# Print a datom Set

One line per member – name, kind, and its tags as compact `key=value`
pairs, or `-` when it has none – plus the route to a member's content.
Long member lists are truncated. A set not yet written shows version
`NA`.

## Usage

``` r
# S3 method for class 'datom_set'
print(x, ..., n = 20L)
```

## Arguments

- x:

  A `datom_set`, from
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
  or
  [`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md).

- ...:

  Ignored.

- n:

  Maximum number of members to list.

## Value

Invisible `x`.

## Details

Tags are open-keyed by design, so there is no fixed column layout to
print them in.

## Examples

``` r
# See datom_get_set() for a runnable example that prints a set.
print(names(formals(datom_get_set)))
#> [1] "conn"    "name"    "version"
```
