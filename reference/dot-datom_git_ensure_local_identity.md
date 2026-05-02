# Ensure a Repo Has a Local Git Identity

Sets `user.name` and `user.email` on the **local** config of `repo` so
that `git2r::default_signature(repo)` succeeds even when the host has no
global git identity (e.g. CI runners). Values are taken from global
config when present; otherwise fallback constants are used.

## Usage

``` r
.datom_git_ensure_local_identity(
  repo,
  fallback_name = "datom",
  fallback_email = "datom@noreply"
)
```

## Arguments

- repo:

  A
  [`git2r::repository`](https://docs.ropensci.org/git2r/reference/repository.html)
  handle.

- fallback_name:

  Identity used when no global `user.name` is set.

- fallback_email:

  Identity used when no global `user.email` is set.

## Value

Invisible `repo`.

## Details

Idempotent: re-setting the same values is a no-op from git's
perspective.
