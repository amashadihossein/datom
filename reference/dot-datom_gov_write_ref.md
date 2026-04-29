# Write ref.json to Gov Clone and Storage

Writes `projects/{project_name}/ref.json` to the local gov clone,
commits, pushes, then mirrors to gov storage.

## Usage

``` r
.datom_gov_write_ref(conn, project_name, ref)
```

## Arguments

- conn:

  A `datom_conn` with `gov_local_path` and gov storage fields.

- project_name:

  Project name string.

- ref:

  An R list representing the ref content (from
  [`.datom_create_ref()`](https://amashadihossein.github.io/datom/reference/dot-datom_create_ref.md)).

## Value

Invisible TRUE.
