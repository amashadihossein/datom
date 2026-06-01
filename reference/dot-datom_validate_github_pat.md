# Validate GitHub PAT

Calls GitHub `GET /user` to verify the PAT is valid.

## Usage

``` r
.datom_validate_github_pat(pat, api_url = "https://api.github.com")
```

## Arguments

- pat:

  GitHub personal access token.

- api_url:

  GitHub API base URL (default `"https://api.github.com"`).

## Value

A list with `login` and `id`.
