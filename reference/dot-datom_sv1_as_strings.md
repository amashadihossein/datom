# Coerce a Parsed-JSON String Set to a Character Vector

A tag value arrives in one of three spellings, all meaning the same
thing: a length-1 character vector (`"output"`), a longer character
vector (`c("safety", "efficacy")`), or – after a JSON round trip with
`simplifyVector = FALSE` – a list of length-1 strings. All three
normalise to a character vector here, which is what makes a single
string and a one-element array hash identically.

## Usage

``` r
.datom_sv1_as_strings(v, what)
```

## Arguments

- v:

  The value to normalise.

- what:

  Key path used in error messages (e.g. `"tags$domain"`).

## Value

A character vector, possibly of length zero.

## Details

`character(0)` and [`list()`](https://rdrr.io/r/base/list.html) (the
parsed form of `[]`) both normalise to the empty set. Upstream,
canonicalization drops a key whose value is empty – "no labels" is
spelled by omitting the key – so the encoder should never meet one. It
must not depend on that: an encoder whose correctness rests on an
upstream rule breaks silently the day that rule moves.
