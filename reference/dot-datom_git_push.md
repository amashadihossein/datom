# Push to Remote

Pulls (fetch + merge) first to detect conflicts, then pushes. Aborts on
merge conflicts – user must resolve manually per spec.

## Usage

``` r
.datom_git_push(path, pat = NULL)
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
