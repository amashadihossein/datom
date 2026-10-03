# Commits on This Branch the Remote Does Not Have

The ahead half of the count
[`.datom_check_git_current()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_git_current.md)
already computes for its behind half:
[`git2r::ahead_behind()`](https://docs.ropensci.org/git2r/reference/ahead_behind.html)
element `[[1]]` is ahead, `[[2]]` is behind. No new git machinery.

## Usage

``` r
.datom_git_ahead(path)
```

## Arguments

- path:

  Repository path.

## Value

Integer count of unpushed commits, or `NA_integer_` when it cannot be
determined – no upstream tracking ref yet, or the comparison failed.
`NA` means *cannot prove there is nothing to publish*, so callers push:
that is exactly the state of a branch that has never been pushed.

## Details

**Does not fetch.** The comparison is against the cached remote-tracking
ref, so a stale ref can only cause an unnecessary push – and a push
pulls first and is idempotent, so the cost of being wrong in that
direction is a round trip. Fetching here would instead make a clean-tree
call fail when offline.
