# Resolve Data Location from Local Gov Clone

Reads `projects/{project_name}/ref.json` directly from a local gov clone
on disk. Faster than storage reads, works offline, and reflects the last
[`datom_pull_gov()`](https://amashadihossein.github.io/datom/reference/datom_pull_gov.md).
Used for developer connections.

## Usage

``` r
.datom_resolve_ref_from_clone(gov_local_path, project_name)
```

## Arguments

- gov_local_path:

  Absolute path to the local gov clone.

- project_name:

  Project name string.

## Value

A named list with `root`, `prefix`, `region` for the current data
location.
