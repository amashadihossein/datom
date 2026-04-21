# Build Git Credentials for HTTPS Remotes

Returns a
[`git2r::cred_user_pass`](https://docs.ropensci.org/git2r/reference/cred_user_pass.html)
object using `GITHUB_PAT` if the remote URL is HTTPS. Returns NULL for
SSH remotes or when no PAT is available.

## Usage

``` r
.datom_git_credentials(remote_url)
```

## Arguments

- remote_url:

  Character remote URL.

## Value

A
[`git2r::cred_user_pass`](https://docs.ropensci.org/git2r/reference/cred_user_pass.html)
object or NULL.
