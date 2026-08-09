# Scan and Prepare Manifest for Sync

Scans a flat `input_files/` directory and computes file SHAs. Compares
against the current `.datom/manifest.json` to detect new or changed
files. Returns a manifest data frame for review before calling
[`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md).

## Usage

``` r
datom_sync_manifest(conn, path = NULL, pattern = "*")
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- path:

  Optional path to input files directory. Defaults to `input_files/`
  inside the repo.

- pattern:

  Glob pattern for file matching. Default `"*"`.

  Files whose format is outside datom's ingestion allowlist (flat
  tabular formats only) are flagged `"unsupported_format"` up front,
  without blocking their allowlisted siblings.

## Value

Data frame with columns: name, file, format, original_file_sha, status
(one of `"new"`, `"changed"`, `"unchanged"`, `"unsupported_format"`).

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

  # Drop a source file into the repo's input_files/ directory.
  file.copy(
    system.file("extdata", "dm.csv", package = "datom"),
    file.path(tmp, "repo", "input_files", "dm.csv")
  )

  manifest <- datom_sync_manifest(conn)
  print(manifest[, c("name", "format", "status")])

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b33479b0e4c/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b33479b0e4c/repo
#> ℹ Scanned 1 file: 1 new, 0 changed, 0 unchanged.
#>   name format status
#> 1   dm    csv    new
```
