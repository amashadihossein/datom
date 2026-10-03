# Tidy One Tag Value

Sorts and dedupes a tag value, and normalises the three spellings of a
string set into one character vector so that `auto_unbox = TRUE` writes
a single label as a bare string and only a genuine multi-label value as
an array.

## Usage

``` r
.datom_tidy_tag_value(v)
```

## Arguments

- v:

  A tag value.

## Value

A sorted, deduplicated character vector, or `v` unchanged.

## Details

**Anything this build does not recognise as text is returned
untouched.** That is what keeps tidying from aborting:
[`sort()`](https://rdrr.io/r/base/sort.html) on a list or a function
fails with a base-R message that names nothing, whereas leaving the
value alone hands it to the validator, whose message names the key and
the allowed types. Tidy what you can, refuse the rest – in that order,
and never the reverse.

A missing value is left alone for the same reason: `NA` has no text
meaning, so it is a refusal rather than a tidy case.
