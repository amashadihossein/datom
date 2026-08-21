# List Available Tables

Lists tables from S3 manifest. Reads `.metadata/manifest.json` from S3
and returns a data frame with one row per table.

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

Data frame with table info (name, current_version, last_updated, etc.).

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
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a3165e5d5b9/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmp0YCcPh/datom-example-1a3165e5d5b9/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#>   name current_version current_data_sha         last_updated
#> 1   dm        039f0c3f         71a93ffa 2026-08-21T01:18:32Z
```
