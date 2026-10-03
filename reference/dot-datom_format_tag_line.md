# Format a Tag Map for One Line of Output

`key=value` pairs, several labels joined by `|`, `-` when there are no
tags. Tags are open-keyed, so a fixed column layout is impossible – do
not try.

## Usage

``` r
.datom_format_tag_line(tags)
```

## Arguments

- tags:

  A tag map, or `NULL`.

## Value

A single string.
