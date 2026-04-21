# Validate GitHub PAT

Calls GitHub `GET /user` to verify the PAT is valid.

## Usage

``` r
.datom_validate_github_pat(pat)
```

## Arguments

- pat:

  GitHub personal access token.

## Value

A list with `login` and `id`.
