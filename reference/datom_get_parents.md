# Get Parent Lineage for a Table

Reads the `parents` field from a table's metadata. Returns the lineage
entries recorded at write time by dp_dev or other callers. For imported
tables or derived tables with no recorded lineage, returns `NULL`.

## Usage

``` r
datom_get_parents(conn, name, version = NULL)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- version:

  Optional metadata_sha (datom version). If NULL, reads current
  metadata. If provided, fetches the versioned metadata snapshot from
  S3.

## Value

List of parent entries (each with `source`, `table`, `version`), or
`NULL` if no lineage is recorded.

## See also

[`datom_get_lineage()`](https://amashadihossein.github.io/datom/reference/datom_get_lineage.md)
for a unified interface that also exposes the transitive
`source_lineage` field via `depth = "source"`.

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_parents_")
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
datom_get_parents(conn, "dm")
unlink(tmp, recursive = TRUE)
} # }
```
