# Is a Value a Single Non-Empty, Non-Missing String?

The field test used by the member validator. Deliberately **stricter
than
[`.datom_validate_parents()`](https://amashadihossein.github.io/datom/reference/dot-datom_validate_parents.md)'s
equivalent**, which accepts `NA_character_`: that value is character,
has length 1, and `nzchar(NA_character_)` is `TRUE`, so the obvious
three-part test lets it through. A missing value in a member's `id`
would be spliced into a storage key or written into a citable payload,
so it is refused here.

## Usage

``` r
.datom_is_text_scalar(x)
```

## Arguments

- x:

  Value to test.

## Value

`TRUE` or `FALSE`.
