# Print a datom_summary

Print a datom_summary

## Usage

``` r
# S3 method for class 'datom_summary'
print(x, ...)
```

## Arguments

- x:

  A `datom_summary` object.

- ...:

  Ignored.

## Value

Invisible `x`.

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
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a3179b389ee/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmp0YCcPh/datom-example-1a3179b389ee/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> 
#> ── datom project summary 
#> • Project: "example_project"
#> • Role: "developer"
#> • Backend: local -- "/tmp/Rtmp0YCcPh/datom-example-1a3179b389ee/storage"
#> • Tables: 1 (1 version total)
#> • Last write: "2026-08-21T01:18:58Z"
#> • Remote: "/tmp/Rtmp0YCcPh/datom-example-1a3179b389ee/remote.git"
```
