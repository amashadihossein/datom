# Show Version History

Shows version history for a table by reading `version_history.json` from
S3. Returns the most recent `n` versions.

## Usage

``` r
datom_history(conn, name, n = 10, short_hash = FALSE)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

- name:

  Table name.

- n:

  Maximum number of versions to return. Default 10.

- short_hash:

  If TRUE (default), truncates version and data SHA columns to 8
  characters for readability. Set to FALSE for full hashes.

## Value

Data frame with columns: version, data_sha, timestamp, author,
commit_message.

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
  print(datom_history(conn, "dm"))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmprkodKH/datom-example-1b3337c35c81/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmprkodKH/datom-example-1b3337c35c81/repo
#> ✔ Wrote "dm" (full): "039f0c3f"
#>                                                            version
#> 1 039f0c3fc4d639b4977f44e83df863da9535e70df737cc758747bda8bd2d89d8
#>                                                           data_sha
#> 1 71a93ffaa4cdc59750a5d5fbf49bb4ffcd656f00038cae2849958acae622b538
#>              timestamp                author commit_message
#> 1 2026-08-09T02:20:36Z datom <datom@noreply>      Update dm
```
