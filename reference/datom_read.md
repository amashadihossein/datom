# Read a datom Table

Unified read function with dispatch via `dispatch.json`. Reads from S3
metadata cache for data readers.

## Usage

``` r
datom_read(conn, name, version = NULL, context = NULL, ...)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- version:

  Optional metadata_sha (datom version). If NULL, uses current.

- context:

  Optional context for dispatch (e.g., "default", "cached").

- ...:

  Additional parameters forwarded to routed function.

## Value

Data frame or routed function result.

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_read_")
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
dm <- datom_read(conn, "dm")
head(dm)
unlink(tmp, recursive = TRUE)
} # }
```
