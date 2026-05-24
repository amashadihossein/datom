# Build Git Credentials for HTTPS Remotes

Returns a
[`git2r::cred_user_pass`](https://docs.ropensci.org/git2r/reference/cred_user_pass.html)
object when the remote URL is HTTPS and a PAT has been supplied. Returns
NULL for SSH remotes or when `pat` is absent.

## Usage

``` r
.datom_git_credentials(remote_url, pat = NULL)
```

## Arguments

- remote_url:

  Character remote URL.

- pat:

  GitHub personal access token. NULL (default) means no authentication;
  git2r will attempt unauthenticated or SSH access.

## Value

A
[`git2r::cred_user_pass`](https://docs.ropensci.org/git2r/reference/cred_user_pass.html)
object or NULL.

## Details

The PAT must be supplied explicitly – datom does not read environment
variables internally. Callers obtain the PAT from `conn$github_pat`,
which is populated at conn-construction time from `store$github_pat`.
