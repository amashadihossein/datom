# Create a datom Store

Bundles a governance store component, a data store component, and git
config into a single store object. Role (developer vs reader) is derived
from `github_pat` presence.

## Usage

``` r
datom_store(
  governance,
  data,
  github_pat = NULL,
  data_repo_url = NULL,
  gov_repo_url = NULL,
  gov_local_path = NULL,
  github_org = NULL,
  validate = TRUE
)
```

## Arguments

- governance:

  A store component (e.g.,
  [`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md))
  for governance files (dispatch, ref, migration history).

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
  repo is created once per org via
  [`datom_init_gov()`](https://amashadihossein.github.io/datom/reference/datom_init_gov.md)
  and referenced here by every project that uses it.

- gov_local_path:

  Local directory path for the governance clone. If NULL (default), the
  clone is placed as a sibling of the data repo, named after the
  basename of `gov_repo_url` (e.g., `"acme-gov"`).

- github_org:

  GitHub organization for repo creation. NULL for personal repos.

- validate:

  If `TRUE` (default), validate GitHub PAT via API. Set to `FALSE` for
  tests or offline use.

## Value

A `datom_store` object.
