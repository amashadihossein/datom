# Resolve the Local Path for the Governance Clone

Returns the explicit `override` if supplied. Otherwise, places the gov
clone as a sibling of `data_local_path` named after the basename of
`gov_repo_url` (stripping a trailing `.git` suffix). This ensures the
gov clone directory name reflects the gov repo's own identity, not any
specific data project.

## Usage

``` r
.datom_resolve_gov_local_path(data_local_path, gov_repo_url, override = NULL)
```

## Arguments

- data_local_path:

  Absolute path to the local data repo directory.

- gov_repo_url:

  GitHub URL of the governance repo (e.g.,
  `"https://github.com/org/acme-gov.git"`).

- override:

  Optional explicit path. If non-NULL, returned as-is.

## Value

Absolute path string for the gov clone.
