# Stage Files and Commit on the Gov Clone

Pulls first (fetch + merge) to avoid diverged histories, then stages
`paths` relative to the gov clone root and creates a commit.

## Usage

``` r
.datom_gov_commit(conn, paths, msg, staged_deletions = FALSE)
```

## Arguments

- conn:

  A `datom_conn` with `gov_local_path` set.

- paths:

  Character vector of file paths **relative** to the gov clone root
  (e.g., `"projects/my-study/dispatch.json"`).

- msg:

  Commit message string.

- staged_deletions:

  If `TRUE`, paths represent deleted files; skip the existence check and
  stage with `force = TRUE`. Default `FALSE`.

## Value

Commit SHA as a string.
