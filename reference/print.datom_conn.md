# Print a datom Connection

Displays a clean summary without exposing credentials or the S3 client.

## Usage

``` r
# S3 method for class 'datom_conn'
print(x, ...)
```

## Arguments

- x:

  A `datom_conn` object.

- ...:

  Ignored.

## Value

Invisible `x`.

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_conn_")
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
print(conn)
unlink(tmp, recursive = TRUE)
} # }
```
