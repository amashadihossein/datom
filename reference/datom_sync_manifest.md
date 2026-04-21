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

## Value

Data frame with columns: name, file, format, file_sha, status (one of
`"new"`, `"changed"`, `"unchanged"`).
