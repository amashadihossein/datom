# Mask a Secret for Display

By default shows the first 4 characters followed by `****`. That prefix
is fine for GitHub PATs (the `ghp_`/`github_pat_` prefix is a public
type tag), but for AWS secret access keys and session tokens the first
characters are real entropy – pass `reveal_prefix = FALSE` to mask them
fully.

## Usage

``` r
.datom_mask_secret(secret, reveal_prefix = TRUE)
```

## Arguments

- secret:

  A string.

- reveal_prefix:

  If `TRUE` (default), reveal the first 4 characters. If `FALSE`, mask
  the whole secret (no characters revealed).

## Value

Masked string.
