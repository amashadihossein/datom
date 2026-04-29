# Resolve Gov Clone Path with Store Defaults

Convenience wrapper that derives a gov clone path from a `datom_store`:
returns the store's explicit `gov_local_path` if set; otherwise derives
a sibling-of-data default from `gov_repo_url`; otherwise returns `NULL`.

## Usage

``` r
.datom_resolve_or_default_gov_path(store, data_local_path)
```

## Arguments

- store:

  A `datom_store` object.

- data_local_path:

  Absolute path to the local data repo (used to compute the sibling
  default when no override is set).

## Value

Character path string or `NULL`.

## Details

Centralises the three-arm pattern previously duplicated in
[`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md),
[`datom_clone()`](https://amashadihossein.github.io/datom/reference/datom_clone.md),
and
[`.datom_get_conn_developer()`](https://amashadihossein.github.io/datom/reference/dot-datom_get_conn_developer.md).
