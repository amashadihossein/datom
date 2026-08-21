# Verify a Copy Between Two datom Storage Namespaces

Checks that objects in `to_conn`'s datom namespace match their
counterparts in `from_conn`. Two verification modes are available:

## Usage

``` r
datom_storage_verify(
  from_conn,
  to_conn,
  keys = NULL,
  mode = c("structural", "content")
)
```

## Arguments

- from_conn:

  A `datom_conn` object (source / reference).

- to_conn:

  A `datom_conn` object (destination to verify).

- keys:

  Character vector of relative keys (after `{prefix}/datom/`) to verify.
  `NULL` (default) verifies every key returned by
  `datom_storage_list(from_conn)`. Pass a subset to verify a sample.

- mode:

  `"structural"` (default) or `"content"`. See above.

## Value

A data frame with columns:

- `key` (character): relative storage key.

- `ok` (logical): `TRUE` if the object passed verification.

- `issue` (character): description of the mismatch, or `NA` if `ok`.
  Returns a zero-row data frame if `keys` is empty.

## Details

- **`"structural"` (default)**: Confirms each destination object exists
  and its byte size matches the source. Fast – one `HEAD`/stat per
  object, no byte transfer. Catches truncated or missing objects, which
  is the dominant copy failure mode.

- **`"content"`**: Re-reads destination bytes, recomputes the SHA-256
  hash, and compares against the source hash. Expensive (full
  re-download for remote backends) but gives true bit-level integrity.
  Use for regulated or paranoid runs.

## See also

[`datom_storage_copy()`](https://amashadihossein.github.io/datom/reference/datom_storage_copy.md),
[`datom_storage_list()`](https://amashadihossein.github.io/datom/reference/datom_storage_list.md)

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

  to_store <- datom_store(data = datom_store_local(file.path(tmp, "storage2")))
  to_conn <- datom_get_conn(store = to_store, project_name = "example_project")
  copied <- datom_storage_copy(from_conn, to_conn)

  # Verify all copied objects structurally (default, fast)
  results <- datom_storage_verify(from_conn, to_conn)
  print(all(results$ok))

  # Verify a subset with full content hash
  print(datom_storage_verify(from_conn, to_conn,
                             keys = copied$key[1],
                             mode = "content"))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a314ae39778/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/Rtmp0YCcPh/datom-example-1a314ae39778/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#> ℹ Created store directory /tmp/Rtmp0YCcPh/datom-example-1a314ae39778/storage2.
#> ℹ Copying 5 objects ("local" -> "local")...
#> ✔ Copied 5 objects (10,493 bytes total).
#> ℹ Verifying 5 objects -- "structural (size)" mode...
#> ✔ All 5 objects verified successfully.
#> [1] TRUE
#> ℹ Verifying 1 object -- "content (hash)" mode...
#> ✔ All 1 object verified successfully.
#>                       key   ok issue
#> 1 .metadata/manifest.json TRUE  <NA>
```
