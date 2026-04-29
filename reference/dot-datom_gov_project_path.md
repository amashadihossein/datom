# Build Project-Scoped Path Within Gov Clone

Returns `{gov_local_path}/projects/{project_name}/`. This is where
`dispatch.json`, `ref.json`, and `migration_history.json` live for a
given project in the shared governance repo.

## Usage

``` r
.datom_gov_project_path(gov_local_path, project_name)
```

## Arguments

- gov_local_path:

  Absolute path to the governance clone directory.

- project_name:

  Project name string.

## Value

An `fs_path` character scalar.
