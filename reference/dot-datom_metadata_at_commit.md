# Read a Metadata Document as One Commit Left It

`revparse_single(repo, "<sha>:<path>")` is the whole mechanism: it
resolves git's own `commit:path` syntax straight to the blob and raises
when the path is absent at that commit. Indexing the tree object instead
returns an empty list for a path that is not there, which reads as a
successful lookup.

## Usage

``` r
.datom_metadata_at_commit(repo, sha, rel)
```

## Arguments

- repo:

  A `git2r` repository handle.

- sha:

  Commit sha.

- rel:

  Repo-relative path of the document.

## Value

The parsed document, or `NULL` when it cannot be read.
