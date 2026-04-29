# Delete a GitHub Repository

Deletes a GitHub repository via the REST API. Requires a PAT with the
`delete_repo` scope.

## Usage

``` r
.datom_delete_github_repo(repo_full, pat)
```

## Arguments

- repo_full:

  Repository in `"owner/repo"` form.

- pat:

  GitHub personal access token (must have `delete_repo` scope).

## Value

Invisible `TRUE` on success; aborts on failure.
