# Create a GitHub Repository

Creates a new GitHub repository via the REST API. Handles both org and
personal repos.

## Usage

``` r
.datom_create_github_repo(repo_name, pat, org = NULL, private = TRUE)
```

## Arguments

- repo_name:

  Repository name.

- pat:

  GitHub personal access token.

- org:

  GitHub organization. NULL for personal repos.

- private:

  Whether the repo should be private (default TRUE).

## Value

The clone URL of the created/reused repository.

## Details

Safety guard:

- Repo doesn't exist → create, return URL

- Repo exists + empty → reuse, return URL

- Repo exists + has content → abort
