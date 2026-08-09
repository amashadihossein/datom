# Summarize a datom Project

Returns a compact, role-aware overview of a datom project: its name,
backend, table/version totals, last write time, and (for developers) the
git remote URL. Reads `.metadata/manifest.json` from the data store.

## Usage

``` r
datom_summary(conn)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

## Value

A `datom_summary` S3 object (a list with class `"datom_summary"`)
containing: `project_name`, `role`, `backend`, `root`, `prefix`,
`table_count`, `total_versions`, `last_updated`, `remote_url`.
`remote_url` is `NULL` for readers (no local data clone).

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

  datom_write(conn, data = datom_example_data("dm"), name = "dm")
  print(datom_summary(conn))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b33334d62b4/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b33334d62b4/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> 
#> ── datom project summary 
#> • Project: "example_project"
#> • Role: "developer"
#> • Backend: local -- "/tmp/RtmprkodKH/datom-example-1b33334d62b4/storage"
#> • Tables: 1 (1 version total)
#> • Last write: "2026-08-09T02:20:41Z"
#> • Remote: "/tmp/RtmprkodKH/datom-example-1b33334d62b4/remote.git"
```
