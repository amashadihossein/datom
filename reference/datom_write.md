# Write a datom Table

Writes data to a datom repository. Commits to git, pushes, and syncs to
S3.

## Usage

``` r
datom_write(
  conn,
  data = NULL,
  name = NULL,
  metadata = NULL,
  message = NULL,
  parents = NULL,
  .source_lineage = NULL,
  .table_type = "derived",
  .original_file_sha = NULL,
  .original_format = NULL
)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- data:

  Data frame to write. If NULL with name, does metadata-only sync.

- name:

  Table name. If NULL with NULL data, does a data-only metadata sync to
  storage (manifest + per-table metadata).

- metadata:

  Optional list of custom metadata.

- message:

  Optional commit message.

- parents:

  Optional list of parent records produced by
  [`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md),
  each carrying `source`, `table`, `version`, `data_sha`, and
  `source_lineage`. When supplied, the table's `source_lineage` is
  derived as the deduplicated union of the parents' `source_lineage` and
  each parent is recorded lean (`source`, `table`, `version`,
  `data_sha`). NULL if no lineage is recorded. There is no public
  `source_lineage` parameter; it is always derived from `parents`.

- .source_lineage:

  Internal. Flat list of transitive non-derived source descriptors (each
  with `project`, `table`, `version_sha`) for the imported self-entry
  path, set by
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md).
  Unused on the derived (parents) path.

- .table_type:

  Internal. `"derived"` (default) or `"imported"` (set by
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)).

- .original_file_sha:

  Internal. SHA of source file (set by
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md));
  NULL for derived.

- .original_format:

  Internal. Original file format (set by
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md));
  NULL for derived.

## Value

List with deployment details.

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_write_")
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
dm <- datom_example_data("dm")
datom_write(conn, data = dm, name = "dm")
unlink(tmp, recursive = TRUE)
} # }
```
