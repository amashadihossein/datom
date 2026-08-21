# Sync Files to datom Repository

Processes new/changed files from a manifest produced by
[`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md).
Imports each file via
[`rio::import()`](http://gesistsa.github.io/rio/reference/import.md),
converts to a data frame, and calls
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
to store as parquet in S3 with git metadata. Updates the local
`.datom/manifest.json` after each successful write.

## Usage

``` r
datom_sync(conn, manifest, continue_on_error = TRUE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- manifest:

  Data frame from
  [`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md),
  with columns `name`, `file`, `format`, `original_file_sha`, `status`.

- continue_on_error:

  If `TRUE` (default), continues processing remaining tables when one
  fails. If `FALSE`, stops on first error.

  Rows flagged `"unsupported_format"` by
  [`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md)
  are reported as `result = "error"` with the recourse in the `error`
  column; the rest of the batch still processes.

## Value

The manifest data frame augmented with `result` and `error` columns.
`result` is `"success"`, `"skipped"`, or `"error"`.

## Examples

``` r
# Offline, self-contained: a bare git repo stands in for GitHub and a
# local directory for object storage. File import needs the optional
# rio package.
if (requireNamespace("git2r", quietly = TRUE) &&
    requireNamespace("rio", quietly = TRUE)) {
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

  file.copy(
    system.file("extdata", "dm.csv", package = "datom"),
    file.path(tmp, "repo", "input_files", "dm.csv")
  )

  manifest <- datom_sync_manifest(conn)
  result <- datom_sync(conn, manifest)
  print(result[, c("name", "status", "result")])

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a316b68fdf0/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmp0YCcPh/datom-example-1a316b68fdf0/repo
#> ℹ Scanned 1 file: 1 new, 0 changed, 0 unchanged.
#> ℹ Syncing 1 table...
#> ✔ Wrote "dm" (full): "3074b39f"
#> ✔ "dm" synced (new).
#> ℹ Sync complete: 1 succeeded, 0 failed, 0 skipped.
#>   name status  result
#> 1   dm    new success
```
