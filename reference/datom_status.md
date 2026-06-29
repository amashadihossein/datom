# Show Repository Status

Displays connection info, table count, and (for developers) uncommitted
git changes and input file sync state.

## Usage

``` r
datom_status(conn)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

## Value

Invisibly, a list with `connection`, `tables`, and optionally `git` and
`input_files` status details.

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_status_")
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
datom_status(conn)
unlink(tmp, recursive = TRUE)
} # }
```
