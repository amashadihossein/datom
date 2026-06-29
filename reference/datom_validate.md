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
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_validate_")
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
datom_validate(conn)
unlink(tmp, recursive = TRUE)
} # }
```
