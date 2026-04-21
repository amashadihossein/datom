# Abbreviate SHA Hash

Truncates a SHA-256 hash to a short prefix for display. Accepts
character vectors; `NA` values pass through unchanged.

## Usage

``` r
.datom_abbreviate_sha(sha, n = 8L)
```

## Arguments

- sha:

  Character vector of SHA hashes.

- n:

  Number of characters to keep. Default 8.

## Value

Character vector of abbreviated hashes.
