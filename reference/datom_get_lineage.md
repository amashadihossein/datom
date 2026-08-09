# Get Lineage for a Table

Reads lineage metadata for a table. Depending on `depth`, returns either
the pre-computed transitive source list (`source_lineage`) or the
immediate parent list (`parents`). Both fields are stored flat in the
table's metadata – no walking or cross-project resolution is performed.

## Usage

``` r
datom_get_lineage(conn, name, version = NULL, depth = c("source", "parents"))
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- version:

  Optional metadata_sha (datom version). If NULL, reads current
  metadata. If provided, fetches the versioned metadata snapshot.

- depth:

  One of `"source"` (default) or `"parents"`.

## Value

For `depth = "source"`: the table's recorded `source_lineage` – a list
of source-table descriptors (each with `project`, `table`,
`version_sha`), or `NULL` if the field is absent. For
`depth = "parents"`: list of parent entries (each with `source`,
`table`, `version`, `data_sha`), or `NULL` if no lineage is recorded.

## Details

The two fields answer different questions:

- `"source"`: "what raw datasets does this table ultimately depend on?"
  (audit, regulatory disclosure, reproducibility scope). Derived at
  write time as the deduplicated union of the parents' `source_lineage`
  fields.

- `"parents"`: "what did this table come from one step back?"
  (debugging, diff, replay). Equivalent to
  [`datom_get_parents()`](https://amashadihossein.github.io/datom/reference/datom_get_parents.md).

## See also

[`datom_get_parents()`](https://amashadihossein.github.io/datom/reference/datom_get_parents.md)
for a direct shorthand for the `"parents"` depth.

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

  datom_write(conn, data = datom_example_data("dm"), name = "dm")
  print(datom_get_lineage(conn, "dm", depth = "parents"))
  print(datom_get_lineage(conn, "dm", depth = "source"))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b332b1a7c6d/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b332b1a7c6d/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> NULL
#> NULL
```
