# Pull Latest Changes from Remote

Fetches and merges the latest git changes from the remote repository.
This is the recommended entry point at the start of each work session to
ensure the local state is current before syncing or writing tables.

## Usage

``` r
datom_pull(conn)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

## Value

Invisibly, a list with:

- `commits_pulled`:

  Integer count of new commits merged.

- `branch`:

  Current branch name.

## Details

Git is the source of truth for all metadata (manifest, dispatch, table
metadata). The manifest and other metadata files live in git and are
pulled along with any other committed changes.

Requires developer role (readers have no git access).

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

  # Nothing new on the remote yet, so this is a no-op.
  datom_pull(conn)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b3324375762/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b3324375762/repo
#> ℹ Already up to date on "master" (data repo).
```
