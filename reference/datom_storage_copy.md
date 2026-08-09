# Copy All Objects Between Two datom Storage Namespaces

Enumerates all objects under `from_conn`'s datom namespace and streams
each one to `to_conn`'s datom namespace. All four backend combinations
are supported:

## Usage

``` r
datom_storage_copy(from_conn, to_conn)
```

## Arguments

- from_conn:

  A `datom_conn` object (source).

- to_conn:

  A `datom_conn` object (destination).

## Value

A data frame with columns `key` (character, relative key after
`{prefix}/datom/`) and `bytes` (numeric, byte count per object). Returns
a zero-row data frame if the source namespace is empty.

## Details

- **local -\> local**: direct file copy via
  [`fs::file_copy()`](https://fs.r-lib.org/reference/copy.html).

- **local -\> S3**: reads raw bytes and uploads via `put_object`.

- **S3 -\> local**: downloads via `get_object` and writes to disk.

- **S3 -\> S3**: streams bytes through memory (get then put).
  Server-side `copy_object` (same-region optimisation) is reserved for a
  future release.

This is a policy-free primitive. It does not modify the source
namespace, update `project.yaml`, or switch `ref.json`. For a complete
managed migration (governed projects) use
`datomanager::gov_migrate_data()`. For solo-project relocation combine
this function with
[`datom_repo_set_data_store()`](https://amashadihossein.github.io/datom/reference/datom_repo_set_data_store.md).

## See also

[`datom_storage_verify()`](https://amashadihossein.github.io/datom/reference/datom_storage_verify.md),
[`datom_storage_list()`](https://amashadihossein.github.io/datom/reference/datom_storage_list.md),
[`datom_storage_delete_prefix()`](https://amashadihossein.github.io/datom/reference/datom_storage_delete_prefix.md),
[`datom_repo_set_data_store()`](https://amashadihossein.github.io/datom/reference/datom_repo_set_data_store.md)

## Examples

``` r
# Offline, self-contained: a bare git repo stands in for GitHub and two
# local directories for the source and destination object stores.
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
  from_conn <- datom_get_conn(file.path(tmp, "repo"), store)
  datom_write(from_conn, data = datom_example_data("dm"), name = "dm")

  # The destination is addressed with a reader connection: no local repo,
  # just a store plus the project name.
  to_store <- datom_store(data = datom_store_local(file.path(tmp, "storage2")))
  to_conn <- datom_get_conn(store = to_store, project_name = "example_project")

  copied <- datom_storage_copy(from_conn, to_conn)
  print(nrow(copied))      # number of objects copied
  print(sum(copied$bytes)) # total bytes

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b3321b24a2a/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b3321b24a2a/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b3321b24a2a/storage2.
#> ℹ Copying 5 objects ("local" -> "local")...
#> ✔ Copied 5 objects (10,493 bytes total).
#> [1] 5
#> [1] 10493
```
