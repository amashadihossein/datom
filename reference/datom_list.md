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
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_list_")
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
datom_write(conn, data = datom_example_data("dm"), name = "dm")
datom_list(conn)
unlink(tmp, recursive = TRUE)
} # }
```
