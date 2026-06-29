# Show Version History

Shows version history for a table by reading `version_history.json` from
S3. Returns the most recent `n` versions.

## Usage

``` r
datom_history(conn, name, n = 10, short_hash = FALSE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- n:

  Maximum number of versions to return. Default 10.

- short_hash:

  If TRUE (default), truncates version and data SHA columns to 8
  characters for readability. Set to FALSE for full hashes.

## Value

Data frame with columns: version, data_sha, timestamp, author,
commit_message.

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_hist_")
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
datom_history(conn, "dm")
unlink(tmp, recursive = TRUE)
} # }
```
