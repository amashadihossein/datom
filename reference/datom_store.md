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
  remote_url = NULL,
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

- remote_url:

  GitHub remote URL. Required when `github_pat` is provided and
  `create_repo = FALSE` will be used in
  [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md).

- github_org:

  GitHub organization for repo creation. NULL for personal repos.

- validate:

  If `TRUE` (default), validate GitHub PAT via API. Set to `FALSE` for
  tests or offline use.

## Value

A `datom_store` object.
