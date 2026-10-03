# Paths git Is Ignoring in a Clone

`git2r::status(ignored = TRUE)` is the only route – git2r exposes no
check-ignore verb – and it reports an ignored **directory** with a
trailing slash and does not recurse into it, so a caller's path has to
be matched against these as prefixes rather than compared for equality.
The trailing slash is stripped here so one comparison covers a file
entry and a directory entry.

## Usage

``` r
.datom_git_ignored(path)
```

## Arguments

- path:

  Repository path.

## Value

Character vector of ignored paths, possibly empty, without trailing
slashes.

## Details

Only ever called from
[`.datom_check_include_paths()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_include_paths.md),
and only when the caller supplied paths, so no existing write gains a
git read.
