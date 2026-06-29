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

## Examples

``` r
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_sync_")
store <- datom_store(
  data = datom_store_local(path = file.path(tmp, "storage")),
  github_pat = "ghp_examplePATforDemoPurposesOnly1234",
  data_repo_url = "https://github.com/example/my-project",
  validate = FALSE
)
datom_init_repo(
  path = file.path(tmp, "repo"),
  project_name = "example_project",
  store = store
)
conn <- datom_get_conn(path = file.path(tmp, "repo"), store = store)
# Copy example CSVs into the input_files directory
input_dir <- file.path(tmp, "repo", "input_files")
dir.create(input_dir)
file.copy(
  system.file("extdata/dm.csv", package = "datom"),
  file.path(input_dir, "dm.csv")
)
manifest <- datom_sync_manifest(conn)
manifest
unlink(tmp, recursive = TRUE)
} # }
```
