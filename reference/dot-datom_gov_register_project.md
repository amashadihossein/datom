# Register a Project in the Gov Repo

Creates `projects/{project_name}/` in the gov clone with initial
`dispatch.json`, `ref.json`, and `migration_history.json`. Commits all
three in a single commit, pushes, then mirrors each file to gov storage.

## Usage

``` r
.datom_gov_register_project(conn, project_name, dispatch, ref)
```

## Arguments

- conn:

  A `datom_conn` with `gov_local_path` and gov storage fields.

- project_name:

  Project name string.

- dispatch:

  Initial dispatch list.

- ref:

  Initial ref list (from
  [`.datom_create_ref()`](https://amashadihossein.github.io/datom/reference/dot-datom_create_ref.md)).

## Value

Invisible TRUE.

## Details

Aborts if the project folder already exists (namespace collision).
