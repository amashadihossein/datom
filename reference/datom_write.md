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
# Offline, self-contained: a bare git repo stands in for GitHub and a
# local directory for object storage.
if (requireNamespace("git2r", quietly = TRUE)) {
  tmp <- tempfile("datom-example-")
  remote <- file.path(tmp, "remote.git")
  dir.create(remote, recursive = TRUE)
  git2r::init(remote, bare = TRUE)

  store <- datom_store(
    data = datom_store_local(file.path(tmp, "storage")),
    github_pat = "example-token", # role selector; a local remote needs none
    data_repo_url = remote,
    validate = FALSE
  )
  datom_init_repo(file.path(tmp, "repo"), "example_project", store)
  conn <- datom_get_conn(file.path(tmp, "repo"), store)

  # --- Basic write (no lineage) ---
  dm <- datom_example_data("dm")
  datom_write(conn, data = dm, name = "dm")

  # --- Write with a single parent ---
  # Each parent's data_sha and lineage are resolved by datom_parent.
  lb <- datom_example_data("lb")
  datom_write(conn, data = lb, name = "lb")
  lb_summary <- aggregate(
    list(n = lb$LBTESTCD), by = list(LBTESTCD = lb$LBTESTCD), FUN = length
  )
  datom_write(
    conn,
    data    = lb_summary,
    name    = "lb_summary",
    message = "Lab test counts",
    parents = list(
      datom_parent(conn, "lb", datom_history(conn, "lb")$version[1])
    )
  )

  # --- Write with multiple parents ---
  # The source lineage is derived as the union of the parents' lineages.
  dm_lb_merged <- merge(dm, lb, by = "USUBJID")
  datom_write(
    conn,
    data    = dm_lb_merged,
    name    = "dm_lb_merged",
    message = "Demographics joined with lab results",
    parents = list(
      datom_parent(conn, "dm", datom_history(conn, "dm")$version[1]),
      datom_parent(conn, "lb", datom_history(conn, "lb")$version[1])
    )
  )

  print(datom_list(conn))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a31383ce9d5/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmp0YCcPh/datom-example-1a31383ce9d5/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> ✔ Wrote "lb" (full): "6c9b32e4"
#> ✔ Wrote "lb_summary" (full): "8b43b1b7"
#> ✔ Wrote "dm_lb_merged" (full): "052274e4"
#>           name current_version current_data_sha         last_updated
#> 1           dm        039f0c3f         71a93ffa 2026-08-21T01:18:38Z
#> 2           lb        6c9b32e4         87f206ab 2026-08-21T01:18:38Z
#> 3   lb_summary        8b43b1b7         b081ff1a 2026-08-21T01:18:38Z
#> 4 dm_lb_merged        052274e4         03b9889f 2026-08-21T01:18:38Z
```
