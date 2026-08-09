# Delete All Objects Under a datom Storage Prefix

Removes every file under `{prefix}/datom/{prefix_key}` from storage.
Pass `prefix_key = NULL` (the default) to delete the entire datom
namespace for this connection. A missing or empty prefix is a no-op.

## Usage

``` r
datom_storage_delete_prefix(conn, prefix_key = NULL)
```

## Arguments

- conn:

  A `datom_conn` object.

- prefix_key:

  Relative prefix to delete under (after `{prefix}/datom/`). `NULL`
  (default) deletes the entire datom namespace root for this connection.

## Value

Invisibly, a backend-specific value. For S3: the count of deleted
objects (0L if nothing found). For the local backend: `1L` if the prefix
directory existed and was removed, `0L` otherwise.

## Details

**Irreversible.** Intended for package developers building tools on top
of datom (e.g. datomanager for rollback or source deletion after
migration). End users performing a full project teardown should use
[`datom_repo_delete()`](https://amashadihossein.github.io/datom/reference/datom_repo_delete.md)
instead.

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

  # Delete a single table's objects
  datom_storage_delete_prefix(conn, prefix_key = "dm")

  # Delete the entire datom namespace (use with care)
  datom_storage_delete_prefix(conn)
  print(datom_storage_list(conn))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b335dd94f68/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b335dd94f68/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> character(0)
```
