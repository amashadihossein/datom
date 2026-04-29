# Unregister a Project from the Gov Repo

Deletes `projects/{project_name}/` from the gov clone, commits the
deletions, and pushes. Does not delete gov storage files (caller is
responsible for cleaning up storage, typically via
[`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md)).

## Usage

``` r
.datom_gov_unregister_project(conn, project_name)
```

## Arguments

- conn:

  A `datom_conn` with `gov_local_path` set.

- project_name:

  Project name string.

## Value

Invisible TRUE.
