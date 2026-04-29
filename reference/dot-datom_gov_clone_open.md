# Open an Existing Gov Clone

Returns a `git2r` repository handle for the gov clone at
`gov_local_path`. Aborts if the path is not a valid git repository.

## Usage

``` r
.datom_gov_clone_open(gov_local_path)
```

## Arguments

- gov_local_path:

  Absolute path to the governance clone directory.

## Value

A
[`git2r::repository`](https://docs.ropensci.org/git2r/reference/repository.html)
object.
