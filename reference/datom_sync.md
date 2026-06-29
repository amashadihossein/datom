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
  with columns `name`, `file`, `format`, `file_sha`, `status`.

- continue_on_error:

  If `TRUE` (default), continues processing remaining tables when one
  fails. If `FALSE`, stops on first error.

## Value

The manifest data frame augmented with `result` and `error` columns.
`result` is `"success"`, `"skipped"`, or `"error"`.

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_sync_")
store <- datom_store(
  data = datom_store_local(path = file.path(tmp, "storage")),
  github_pat = "ghp_examplePATforDemoPurposesOnly1234",
  data_repo_url = "https://github.com/example/my-project",
  validate = FALSE
)
datom_init_repo(
  path = file.path(tmp, "repo"),
  project_name = "example_project",
  store = store
)
conn <- datom_get_conn(path = file.path(tmp, "repo"), store = store)
input_dir <- file.path(tmp, "repo", "input_files")
dir.create(input_dir)
file.copy(
  system.file("extdata/dm.csv", package = "datom"),
  file.path(input_dir, "dm.csv")
)
manifest <- datom_sync_manifest(conn)
result <- datom_sync(conn, manifest)
result[, c("name", "status", "result")]
unlink(tmp, recursive = TRUE)
} # }
```
