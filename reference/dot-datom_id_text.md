# One `id` Field as Text, or `NA`

A member read by
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
always has four single-string `id` fields – the read refuses a payload
where one is not. This exists for the other input: a `datom_set`
assembled by hand, which is supported and untrusted. `NA` rather than an
abort so a listing still shows the member; the abort belongs to whoever
tries to *resolve* it.

## Usage

``` r
.datom_id_text(id, field)
```

## Arguments

- id:

  A member's `id` map.

- field:

  One of `project`, `name`, `kind`, `version`.

## Value

A single string, or `NA_character_`.
