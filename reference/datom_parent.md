# Declare a parent for lineage

Resolves a parent table against a single project connection and returns
a pure-data lineage record. The parent's authoritative `data_sha` and
its `source_lineage` are read from the parent's own versioned metadata
snapshot at `{table}/.metadata/{version}.json`; a caller cannot supply
or override `data_sha` (there is no `data_sha` parameter). The returned
record retains no live connection and is serializable as plain data.

## Usage

``` r
datom_parent(conn, table, version)
```

## Arguments

- conn:

  A `datom_conn` scoped to the parent's project store, from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- table:

  Parent table name (single non-empty validated string).

- version:

  Parent version (metadata_sha; single non-empty string).

## Value

A list with exactly `source`, `table`, `version`, `data_sha`, and
`source_lineage`. `source` is the parent connection's `project_name`;
`source_lineage` is `NULL` when the snapshot carries none.

## Details

Same-project and cross-project parents are declared identically – the
only difference is which connection is passed. `source` is always
derived from the connection's `project_name`.

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

  # Resolve a parent declaration to pass to the parents argument of
  # datom_write.
  print(datom_parent(conn, "dm", datom_history(conn, "dm")$version[1]))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b338c7c40f/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b338c7c40f/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> $source
#> [1] "example_project"
#> 
#> $table
#> [1] "dm"
#> 
#> $version
#> [1] "039f0c3fc4d639b4977f44e83df863da9535e70df737cc758747bda8bd2d89d8"
#> 
#> $data_sha
#> [1] "71a93ffaa4cdc59750a5d5fbf49bb4ffcd656f00038cae2849958acae622b538"
#> 
#> $source_lineage
#> NULL
#> 
```
