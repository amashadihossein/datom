# Check Whether a Gov Clone Exists

Returns `TRUE` if `gov_local_path` is a directory that looks like a git
repository (contains a `.git` folder). Does **not** validate the remote
URL.

## Usage

``` r
.datom_gov_clone_exists(gov_local_path)
```

## Arguments

- gov_local_path:

  Absolute path to the governance clone directory.

## Value

Logical scalar.
