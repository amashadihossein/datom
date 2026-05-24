# Pull from Remote (Fetch + Merge)

Fetches from the remote and merges upstream changes into the current
branch. Aborts on merge conflicts - user must resolve manually. This is
the primary defense against diverged histories.

## Usage

``` r
.datom_git_pull(path, pat = NULL)
```

## Arguments

- path:

  Repository path.

- pat:

  GitHub personal access token. Passed directly to
  [`.datom_git_credentials()`](https://amashadihossein.github.io/datom/reference/dot-datom_git_credentials.md).
  NULL means unauthenticated.

## Value

Invisible TRUE on success.
