# Delete a GitHub Repository

Deletes a GitHub repository via the REST API. Requires a PAT with the
`delete_repo` scope.

## Usage

``` r
.datom_delete_github_repo(repo_full, pat, api_url = "https://api.github.com")
```

## Arguments

- repo_full:

  Repository in `"owner/repo"` form.

- pat:

  GitHub personal access token (must have `delete_repo` scope).

- api_url:

  GitHub API base URL (default `"https://api.github.com"`).

## Value

Invisible `TRUE` on success; aborts on failure.
