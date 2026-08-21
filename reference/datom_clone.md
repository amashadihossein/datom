# Clone a datom Repository

Clones a remote datom repository and returns a connection. This is the
recommended way for teammates to join an existing datom project – it
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
  Must have `data_repo_url` set and role `"developer"` (i.e.,
  `github_pat` provided).

- ...:

  Additional arguments passed to
  [`git2r::clone()`](https://docs.ropensci.org/git2r/reference/clone.html).

## Value

A `datom_conn` object (developer role).

## Details

When `store$gov_repo_url` is set the governance repo is also cloned (or
verified if it already exists locally). An existing clone with
uncommitted changes causes an error to avoid surprising state.

## Examples

``` r
# Offline, self-contained: a bare git repo stands in for GitHub and a
# local directory for object storage.
if (requireNamespace("git2r", quietly = TRUE)) {
  tmp <- tempfile("datom-example-")
  remote <- file.path(tmp, "remote.git")
  dir.create(remote, recursive = TRUE)
  git2r::init(remote, bare = TRUE)

  store <- datom_store(
    data = datom_store_local(file.path(tmp, "storage")),
    github_pat = "example-token", # role selector; a local remote needs none
    data_repo_url = remote,
    validate = FALSE
  )
  datom_init_repo(file.path(tmp, "repo"), "example_project", store)

  # A teammate joins the project from the remote alone.
  conn <- datom_clone(path = file.path(tmp, "teammate"), store = store)
  print(datom_list(conn))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a314e6c8b2b/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmp0YCcPh/datom-example-1a314e6c8b2b/repo
#> cloning into '/tmp/Rtmp0YCcPh/datom-example-1a314e6c8b2b/teammate'...
#> ✔ Cloned "example_project" to /tmp/Rtmp0YCcPh/datom-example-1a314e6c8b2b/teammate
#> [1] name            current_version last_updated   
#> <0 rows> (or 0-length row.names)
```
