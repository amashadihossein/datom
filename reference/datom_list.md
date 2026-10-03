# List the Tables and Sets in a Project

Returns one row per table and set in the project, with its current
version and when it was last updated. Works with both developer and
reader connections.

## Usage

``` r
datom_list(conn, pattern = NULL, include_versions = FALSE, short_hash = TRUE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- pattern:

  Optional glob pattern for filtering table names.

- include_versions:

  If TRUE, includes version count info.

- short_hash:

  If TRUE (default), truncates version and data SHA columns to 8
  characters for readability. Set to FALSE for full hashes.

## Value

Data frame with artifact info (name, kind, current_version,
last_updated, etc.).

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
  print(datom_list(conn))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a7623e28a7/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a7623e28a7/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#>   name  kind current_version current_data_sha         last_updated
#> 1   dm table        b5cbba45         71a93ffa 2026-10-03T21:06:16Z
```
