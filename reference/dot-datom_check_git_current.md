# Check Local Branch is Current with Remote

Fetches from the remote and compares local HEAD SHA against the upstream
HEAD SHA. If the local branch is behind, aborts with a clear message
telling the developer to pull first.

## Usage

``` r
.datom_check_git_current(path)
```

## Arguments

- path:

  Repository path.

## Value

Invisible `TRUE` if the local branch is up to date.

## Details

Does NOT auto-pull — lets the developer decide how to resolve.
