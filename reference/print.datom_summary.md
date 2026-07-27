# Print a datom_summary

Print a datom_summary

## Usage

``` r
# S3 method for class 'datom_summary'
print(x, ...)
```

## Arguments

- x:

  A `datom_summary` object.

- ...:

  Ignored.

## Value

Invisible `x`.

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_summary_")
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
print(datom_summary(conn))
unlink(tmp, recursive = TRUE)
} # }
```
