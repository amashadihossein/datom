# Check if Path is a Valid datom Repository

Validates datom repository structure. Used internally and by dpbuild.

## Usage

``` r
is_valid_datom_repo(
  path,
  checks = c("all", "git", "datom", "renv"),
  verbose = FALSE
)
```

## Arguments

- path:

  Path to evaluate.

- checks:

  Which checks to perform. Any combination of "all", "git", "datom",
  "renv".

- verbose:

  If TRUE, prints which tests passed/failed.

## Value

TRUE or FALSE.
