# Get a datom Connection

Flexible connection for both developers and readers.

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
if (FALSE) { # \dontrun{
tmp <- tempfile("datom_conn_")
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
conn
unlink(tmp, recursive = TRUE)
} # }
```
