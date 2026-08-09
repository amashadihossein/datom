# Get Parent Lineage for a Table

Reads the `parents` field from a table's metadata. Returns the lineage
entries recorded at write time by
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md).
For imported tables or derived tables with no recorded lineage, returns
`NULL`.

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

List of parent entries (each with `source`, `table`, `version`,
`data_sha`), or `NULL` if no lineage is recorded. The `data_sha` field
is the parent's authoritative data SHA recorded via
[`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md),
and together with `source` and `version` is sufficient to select the
parent's project connection and its pinned version.

## See also

[`datom_get_lineage()`](https://amashadihossein.github.io/datom/reference/datom_get_lineage.md)
for a unified interface that also exposes the transitive
`source_lineage` field via `depth = "source"`.

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

  dm <- datom_example_data("dm")
  datom_write(conn, data = dm, name = "dm")
  datom_write(
    conn,
    data    = dm[dm$SEX == "F", ],
    name    = "dm_female",
    parents = list(datom_parent(conn, "dm", datom_history(conn, "dm")$version[1]))
  )
  print(datom_get_parents(conn, "dm_female"))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b3312ab97fb/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b3312ab97fb/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> ✔ Wrote "dm_female" (full): "3bd94a7a"
#> [[1]]
#> [[1]]$source
#> [1] "example_project"
#> 
#> [[1]]$table
#> [1] "dm"
#> 
#> [[1]]$version
#> [1] "039f0c3fc4d639b4977f44e83df863da9535e70df737cc758747bda8bd2d89d8"
#> 
#> [[1]]$data_sha
#> [1] "71a93ffaa4cdc59750a5d5fbf49bb4ffcd656f00038cae2849958acae622b538"
#> 
#> 
```
