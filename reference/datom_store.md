# Create a datom Store

Bundles a governance store component, a data store component, and git
config into a single store object. Role (developer vs reader) is derived
from `github_pat` presence.

## Usage

``` r
datom_store(
  governance = NULL,
  data,
  github_pat = NULL,
  data_repo_url = NULL,
  gov_repo_url = NULL,
  gov_local_path = NULL,
  github_org = NULL,
  github_api_url = NULL,
  validate = TRUE
)
```

## Arguments

- governance:

  A store component (e.g.,
  [`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md))
  for governance files (dispatch, ref, migration history), or `NULL` for
  a no-governance store. A no-governance store represents a project that
  has not yet been promoted to governance (via the datomanager package);
  `gov_repo_url` and `gov_local_path` must also be `NULL` in that case.

- data:

  A store component (e.g.,
  [`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md))
  for data files (manifest, tables, metadata).

- github_pat:

  GitHub personal access token. If provided, role is `"developer"`. If
  NULL, role is `"reader"`.

- data_repo_url:

  GitHub remote URL for the data repository. Required when `github_pat`
  is provided and `create_repo = FALSE` in
  [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md).

- gov_repo_url:

  GitHub remote URL for the shared governance repository. The governance
  repo is created once per org (via the datomanager package) and
  referenced here by every project that uses it.

- gov_local_path:

  Local directory path for the governance clone. If NULL (default), the
  clone is placed as a sibling of the data repo, named after the
  basename of `gov_repo_url` (e.g., `"acme-gov"`).

- github_org:

  GitHub organization for repo creation. NULL for personal repos.

- github_api_url:

  GitHub API base URL. `NULL` (default) uses `"https://api.github.com"`,
  which is correct for github.com and GitHub Enterprise Cloud (GHEC).
  For GitHub Enterprise Server (GHES) pass the server's API root, e.g.
  `"https://github.mycompany.com/api/v3"`. A trailing `/` is stripped
  for consistency.

- validate:

  If `TRUE` (default), validate GitHub PAT via API. Set to `FALSE` for
  tests or offline use.

## Value

A `datom_store` object.

## Examples

``` r
tmp <- tempfile("datom_store_")
store <- datom_store(
  data = datom_store_local(path = tmp),
  data_repo_url = "https://github.com/example/my-project",
  validate = FALSE
)
#> ℹ Created store directory /tmp/Rtmp2dhiUC/datom_store_19aa40cf960c.
store
#> 
#> ── datom store 
#> • Role: "reader"
#> • Data repo: <https://github.com/example/my-project>
#> 
#> Governance:
#> not attached
#> 
#> Data:
#> 
#> ── datom local store component 
#>   • Path: /tmp/Rtmp2dhiUC/datom_store_19aa40cf960c
#>   • Validated: TRUE
is_datom_store(store)
#> [1] TRUE
unlink(tmp, recursive = TRUE)
```
