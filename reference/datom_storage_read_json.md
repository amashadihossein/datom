# Read a JSON Document from a datom Storage Namespace

Reads and parses a JSON object from storage, dispatching on the
connection's backend. Intended for package developers building tools on
top of datom (e.g. datomanager) that need to inspect datom's own
documents – manifests, metadata, version history – without reaching into
internals via `:::`.

## Usage

``` r
datom_storage_read_json(conn, key)
```

## Arguments

- conn:

  A `datom_conn` object.

- key:

  Relative storage key (after `{prefix}/datom/`).

## Value

The parsed JSON document as an R list. Nested structures are kept as
lists (`simplifyVector = FALSE`), so JSON arrays of objects do not
collapse into data frames.

## Details

End users should prefer the purpose-built readers:
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
for table data,
[`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
and
[`datom_summary()`](https://amashadihossein.github.io/datom/reference/datom_summary.md)
for the manifest, and
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
for version history. This export is a byte-level primitive and does not
interpret what it reads.

`key` is a **relative** key – the portion after `{prefix}/datom/`, e.g.
`"dm/.metadata/metadata.json"`. The backend prepends the namespace
itself, so passing a full key (one containing a `datom/` segment) is
refused rather than silently resolving under
`{prefix}/datom/{prefix}/datom/` and finding nothing. Keys containing a
`..` segment or a leading `/` are refused too: reads are confined to
this project's namespace.

There is no corresponding write export. Documents are written by
purpose-built verbs
([`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md),
[`datom_repo_attach_governance()`](https://amashadihossein.github.io/datom/reference/datom_repo_attach_governance.md)),
not by a generic byte channel, so that every mutation of a datom
namespace routes through a function that knows what it is writing.

## See also

[`datom_storage_list()`](https://amashadihossein.github.io/datom/reference/datom_storage_list.md)
to discover keys;
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md),
[`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md),
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
for the interpreted equivalents.

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

  # Relative key: the part after `{prefix}/datom/`
  meta <- datom_storage_read_json(conn, "dm/.metadata/metadata.json")
  print(meta$hash_algo)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmpvh48Dj/datom-example-1a7634ea1d17/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmpvh48Dj/datom-example-1a7634ea1d17/repo
#> ✔ Wrote "dm" (full): "b5cbba45"
#> [1] "datom-cv1"
```
