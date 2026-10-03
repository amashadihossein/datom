# Refuse a Repo With No Remote, Before git2r Does It Unhelpfully

[`.datom_git_push()`](https://amashadihossein.github.io/datom/reference/dot-datom_git_push.md)
reads `git2r::remotes(repo)[[1L]]`, which subscripts an empty list on a
repo with no remote and fails with R's own out-of-bounds error – a
message naming nothing the caller can act on. A data repo is required to
have a remote, so this is an edge rather than a scenario, but
[`datom_repo_push()`](https://amashadihossein.github.io/datom/reference/datom_repo_push.md)
is the first thing somebody points at a half-configured repo.

## Usage

``` r
.datom_check_git_remote(path, verb)
```

## Arguments

- path:

  Repository path.

- verb:

  Name of the calling verb, for the message.

## Value

The remote name.

## Details

Deliberately **not** inside
[`.datom_git_push()`](https://amashadihossein.github.io/datom/reference/dot-datom_git_push.md):
putting it there would change what four existing callers do on a repo
they have never met in that state. Both new verbs call it, so there is
no second copy.
