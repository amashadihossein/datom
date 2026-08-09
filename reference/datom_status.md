# Show Repository Status

Displays connection info, table count, and (for developers) uncommitted
git changes and input file sync state.

## Usage

``` r
datom_status(conn)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

## Value

Invisibly, a list with `connection`, `tables`, and optionally `git` and
`input_files` status details.

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
  conn <- datom_get_conn(file.path(tmp, "repo"), store)

  datom_status(conn)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b33314f6fb1/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b33314f6fb1/repo
#> 
#> ── datom status ──
#> 
#> ℹ Project: "example_project"
#> ℹ Root: "/tmp/RtmprkodKH/datom-example-1b33314f6fb1/storage"
#> ℹ Role: "developer"
#> ℹ Tables on local: 0
#> ✔ Git: clean (no uncommitted changes)
#> ℹ Branch: "master"
#> ℹ Input files: directory empty
```
