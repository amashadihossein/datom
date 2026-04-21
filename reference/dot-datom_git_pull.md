# Pull from Remote (Fetch + Merge)

Fetches from the remote and merges upstream changes into the current
branch. Aborts on merge conflicts — user must resolve manually. This is
the primary defense against diverged histories.

## Usage

``` r
.datom_git_pull(path)
```

## Arguments

- path:

  Repository path.

## Value

Invisible TRUE on success.
