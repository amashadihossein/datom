# List All Objects in a datom Storage Namespace

Returns the full storage keys of every object under the datom namespace
for this connection (`{prefix}/datom/...`). Intended for package
developers building tools on top of datom (e.g. datomanager); end users
typically do not need to inspect raw storage keys directly.

## Usage

``` r
datom_storage_list(conn)
```

## Arguments

- conn:

  A `datom_conn` object.

## Value

A character vector of full storage keys. May be empty if the namespace
contains no objects.

## Details

Keys are returned in their full storage-key form – for S3 that is
`"{prefix}/datom/..."` relative to the bucket root; for local backends
it is a path relative to `conn$root`. This mirrors the contract of the
internal
[`.datom_storage_list_objects()`](https://amashadihossein.github.io/datom/reference/dot-datom_storage_list_objects.md)
dispatch layer.

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

  print(datom_storage_list(conn))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b335468adf9/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b335468adf9/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> [1] "datom/.metadata/manifest.json"                                                           
#> [2] "datom/dm/.metadata/039f0c3fc4d639b4977f44e83df863da9535e70df737cc758747bda8bd2d89d8.json"
#> [3] "datom/dm/.metadata/metadata.json"                                                        
#> [4] "datom/dm/.metadata/version_history.json"                                                 
#> [5] "datom/dm/71a93ffaa4cdc59750a5d5fbf49bb4ffcd656f00038cae2849958acae622b538.parquet"       
```
