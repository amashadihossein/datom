# Get a Pointer to a datom Project

Returns a pointer to the project, called a
[connection](https://amashadihossein.github.io/datom/reference/datom-package.md)
(`conn`): a record of which project you are working on, where its data
is kept, and whether you can write. Almost every other datom function
takes it as its first argument. Nothing stays open; it only checks once
that the storage (and, for a developer, the GitHub repository) can be
reached. Developers pass `path` (their local copy) and `store`; readers,
who have no local copy, pass `store` and `project_name`.

## Usage

``` r
datom_get_conn(path = NULL, store = NULL, project_name = NULL, endpoint = NULL)
```

## Arguments

- path:

  Path to datom repository. If provided, reads config from
  `.datom/project.yaml`.

- store:

  A `datom_store` object. Required for all connections. The data
  component provides bucket, prefix, region, and credentials.

- project_name:

  Project name. Required for readers (no local repo). Ignored when
  `path` is provided (read from yaml).

- endpoint:

  Optional S3 endpoint URL (e.g., for S3 access points). NULL for
  default.

## Value

A `datom_conn` object.

## Details

**Developer** (local repo + store): provide `path` and `store`. Reads
project identity from `.datom/project.yaml`; uses store for credentials
and S3 config. Cross-checks bucket/prefix between yaml and store.

**Reader** (no local repo): provide `store` and `project_name`. Store
provides everything.

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

  # Developer: local repo plus store.
  conn <- datom_get_conn(path = file.path(tmp, "repo"), store = store)
  print(conn)

  # Reader: store plus project name, no local repo.
  reader_store <- datom_store(data = datom_store_local(file.path(tmp, "storage")))
  print(datom_get_conn(store = reader_store, project_name = "example_project"))

  unlink(tmp, recursive = TRUE)
}
#> ℹ Created store directory /tmp/RtmphTeynu/datom-example-1afd2242a129/storage.
#> ✔ Initialized datom repository "example_project" at /tmp/RtmphTeynu/datom-example-1afd2242a129/repo
#> 
#> ── datom connection 
#> • Project: "example_project"
#> • Backend: "local"
#> • Role: "developer"
#> • Data root: "/tmp/RtmphTeynu/datom-example-1afd2242a129/storage"
#> • Governance: not attached
#> • Path: /tmp/RtmphTeynu/datom-example-1afd2242a129/repo
#> • Data repo: </tmp/RtmphTeynu/datom-example-1afd2242a129/remote.git>
#> 
#> ── datom connection 
#> • Project: "example_project"
#> • Backend: "local"
#> • Role: "reader"
#> • Data root: "/tmp/RtmphTeynu/datom-example-1afd2242a129/storage"
#> • Governance: not attached
```
