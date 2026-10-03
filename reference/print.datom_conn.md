# Print a datom Connection

Displays a clean summary without exposing credentials or the S3 client.

## Usage

``` r
# S3 method for class 'datom_conn'
print(x, ...)
```

## Arguments

- x:

  A `datom_conn` object.

- ...:

  Ignored.

## Value

Invisible `x`.

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

  print(conn)

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmphTeynu/datom-example-1afd519e858c/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmphTeynu/datom-example-1afd519e858c/repo
#> 
#> ── datom connection 
#> • Project: "example_project"
#> • Backend: "local"
#> • Role: "developer"
#> • Data root: "/tmp/RtmphTeynu/datom-example-1afd519e858c/storage"
#> • Governance: not attached
#> • Path: /tmp/RtmphTeynu/datom-example-1afd519e858c/repo
#> • Data repo: </tmp/RtmphTeynu/datom-example-1afd519e858c/remote.git>
```
