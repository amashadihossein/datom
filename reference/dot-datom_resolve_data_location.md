# Resolve Data Location via Ref (Conn-Time Helper)

Called during
[`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
for both readers and developers when a governance store is present.
Reads `ref.json` from governance, detects migration (store\$data
location != ref location), and returns the ref-resolved location.

## Usage

``` r
.datom_resolve_data_location(
  store,
  role,
  project_name = NULL,
  path = NULL,
  gov_local_path = NULL,
  endpoint = NULL
)
```

## Arguments

- store:

  A `datom_store` object with governance component.

- role:

  `"developer"` or `"reader"`.

- project_name:

  Project name (required when governance is present).

- path:

  Local repo path (developers only; NULL for readers).

- gov_local_path:

  Absolute path to the local gov clone (developers only; NULL for
  readers or when the clone does not yet exist).

- endpoint:

  Optional S3 endpoint URL.

## Value

A named list with `root`, `prefix`, `region` from the ref, or NULL if no
governance store is present (skip ref resolution).

## Details

Read path is **role-aware**:

- Developer with `gov_local_path` set: read `projects/{name}/ref.json`
  from the local gov clone (faster, works offline, reflects last
  [`datom_pull_gov()`](https://amashadihossein.github.io/datom/reference/datom_pull_gov.md)).

- Otherwise (reader, or developer without a clone yet): read via the gov
  storage client.
