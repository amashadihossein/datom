# Write dispatch.json to Gov Clone and Storage

Writes `projects/{project_name}/dispatch.json` to the local gov clone,
commits (with a pull-first), pushes, then mirrors to gov storage.

## Usage

``` r
.datom_gov_write_dispatch(conn, project_name, dispatch)
```

## Arguments

- conn:

  A `datom_conn` with `gov_local_path` and gov storage fields.

- project_name:

  Project name string.

- dispatch:

  An R list representing the dispatch configuration.

## Value

Invisible TRUE.
