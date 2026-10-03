# Normalize a Parsed JSON String Array to a Character Vector

`jsonlite::fromJSON(simplifyVector = FALSE)` returns a JSON array of
strings as a list of length-1 characters, and `auto_unbox = TRUE` on the
write means a single label was written as a bare string. So one tag key
comes back in three shapes – `character(1)`, a list of 1, or a list of n
– for what is one value in the document.

## Usage

``` r
.datom_read_string_array(v)
```

## Arguments

- v:

  A parsed JSON value.

## Value

A character vector when `v` was an all-text array, otherwise `v`.

## Details

Same strings, same order, same count: this is a representation change,
not a content change, which is why order is preserved and duplicates are
kept. Sorting or deduplicating here would be the write's
canonicalization performed by a reader.

Anything that is not an all-text array is returned untouched. A reader
has no caller intent to tidy toward and nothing downstream requires tag
values to be text, so an odd value is reported by whoever tries to use
it rather than refused here.
