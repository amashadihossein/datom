# Commit Changes

Stages the specified files and creates a commit.

## Usage

``` r
.datom_git_commit(path, files, message, staged_deletions = FALSE)
```

## Arguments

- path:

  Repository path.

- files:

  Character vector of files to add (relative to repo root).

- message:

  Commit message.

- staged_deletions:

  If `TRUE`, skip the file-existence check and use
  `git2r::add(force = TRUE)` so deletions can be staged. Default
  `FALSE`.

## Value

Commit SHA as a string.
