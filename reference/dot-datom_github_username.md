# Get GitHub Username from PAT

Calls `GET /user` to get the authenticated user's login.

## Usage

``` r
.datom_github_username(pat, api_url = "https://api.github.com")
```

## Arguments

- pat:

  GitHub personal access token.

- api_url:

  GitHub API base URL (default `"https://api.github.com"`).

## Value

Username string.
