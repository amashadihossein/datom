# Clone a datom Repository

Clones a remote datom repository and returns a connection. This is the
recommended way for teammates to join an existing datom project — it
wraps
[`git2r::clone()`](https://docs.ropensci.org/git2r/reference/clone.html)
and immediately returns a ready-to-use `datom_conn`.

## Usage

``` r
datom_clone(path, store, ...)
```

## Arguments

- path:

  Local path to clone into.

- store:

  A `datom_store` object (from
  [`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md)).
  Must have `remote_url` set and role `"developer"` (i.e., `github_pat`
  provided).

- ...:

  Additional arguments passed to
  [`git2r::clone()`](https://docs.ropensci.org/git2r/reference/clone.html).

## Value

A `datom_conn` object (developer role).

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- datom_clone(
  path = "study_001_data",
  store = my_store
)
datom_pull(conn)
} # }
```
