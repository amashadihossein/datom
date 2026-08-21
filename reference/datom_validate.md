# Validate Git-Storage Consistency

Checks that git metadata matches S3 storage for all tables and
repo-level files. Reports mismatches as a structured result.

## Usage

``` r
datom_validate(conn, fix = FALSE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- fix:

  If `TRUE`, attempts to fix inconsistencies by syncing data-side
  metadata (manifest + per-table metadata) to storage.

## Value

A list with:

- valid:

  Logical — `TRUE` if everything is consistent.

- repo_files:

  Data frame of repo-level file checks.

- tables:

  Data frame of per-table checks.

- fixed:

  Logical — `TRUE` if `fix = TRUE` was applied.

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
  datom_validate(conn)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a313e30e565/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmp0YCcPh/datom-example-1a313e30e565/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> ℹ No governance attached -- skipping dispatch/ref/migration_history checks.
#> ✔ All checks passed. Git and S3 are consistent.
```
