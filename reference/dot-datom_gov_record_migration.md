# Record a Migration Event in Gov Repo

Appends `event` to `projects/{project_name}/migration_history.json` in
the gov clone, commits, pushes, and mirrors to gov storage. Creates the
file with an empty array if it does not exist.

## Usage

``` r
.datom_gov_record_migration(conn, project_name, event)
```

## Arguments

- conn:

  A `datom_conn` with `gov_local_path` and gov storage fields.

- project_name:

  Project name string.

- event:

  A named list describing the migration event. Typically includes
  `event_type`, `occurred_at`, and `details`.

## Value

Invisible TRUE.
