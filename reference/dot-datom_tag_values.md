# A Tag Value as a Plain Character Vector

**This is only possible because the tag grammar is text-only.**
[`.datom_validate_tag_map()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_tag_map.md)
refuses numbers, booleans, `null` and nesting, so a tag value is a
character vector and the `value` column of a member listing is a plain
character column with no list-column anywhere. If the grammar ever
widened, this function and the long format above it are what would have
to change.

## Usage

``` r
.datom_tag_values(v)
```

## Arguments

- v:

  A tag value.

## Value

A character vector, possibly empty.

## Details

The two shapes handled are the two a value legitimately arrives in: a
character vector, and the list-of-length-1-characters a JSON array
parses as. A missing value is dropped rather than carried, because it
states no label and no datom write can produce one – carried through, it
would become a branch named `NA`.
