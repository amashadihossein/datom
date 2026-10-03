# List a Set's Members and Their Labels

A data frame with one row per member **per label value** – long format,
not wide. Tags are open-keyed and multi-valued, so a wide frame would
need a list-column and a column set that changes from one set to the
next; long is a plain frame with fixed columns whatever the set holds.

## Usage

``` r
datom_list_members(x)
```

## Arguments

- x:

  A `datom_set` from
  [`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md).

## Value

A data frame of `name`, `project`, `version`, `kind`, `key`, `value`.
Zero rows, with those columns, for a set with no members.

## Details

Filtering is therefore ordinary R –
[`subset()`](https://rdrr.io/r/base/subset.html), `dplyr::filter()` –
and datom grows no query vocabulary of its own.

## The columns

`name`, `project`, `version` and `kind` identify the member; `key` and
`value` are one label. **An untagged member still gets a row**, with
`NA` for both, so `unique(m$name)` is the complete member list rather
than the tagged part of it.

`value` is a plain character column, never a list-column, because the
tag grammar is text only.

## See also

[`datom_structure_members()`](https://amashadihossein.github.io/datom/reference/datom_structure_members.md)
for a navigable view of the same labels,
[`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md)
to resolve one member.

## Examples

``` r
# These two facts about a set -- its members and their labels -- are all this
# verb reads, so a set built by hand shows the shape. In practice `x` comes
# from datom_get_set().
x <- structure(
  list(
    name = "study001-adam", project = "study001", version = NULL,
    data_sha = NULL, tags = list(description = "ADaM datasets"),
    members = list(
      list(
        id = list(project = "study001", name = "adsl", kind = "table",
                  version = strrep("a", 64)),
        tags = list(type = "output", domain = c("safety", "efficacy"))
      ),
      list(
        id = list(project = "study001", name = "dm", kind = "table",
                  version = strrep("b", 64))
      )
    )
  ),
  class = "datom_set"
)

# adsl appears three times, once per label; the untagged dm appears once.
datom_list_members(x)
#>   name  project
#> 1 adsl study001
#> 2 adsl study001
#> 3 adsl study001
#> 4   dm study001
#>                                                            version  kind    key
#> 1 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa table   type
#> 2 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa table domain
#> 3 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa table domain
#> 4 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb table   <NA>
#>      value
#> 1   output
#> 2   safety
#> 3 efficacy
#> 4     <NA>

# Filtering is plain R.
subset(datom_list_members(x), key == "domain" & value == "safety")
#>   name  project
#> 2 adsl study001
#>                                                            version  kind    key
#> 2 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa table domain
#>    value
#> 2 safety
```
