# List Registered Project Names

Returns the set of project names registered in the governance repo. When
a local gov clone is available, lists directories under
`{gov_local_path}/projects/` (offline-friendly, reflects last
[`datom_pull_gov()`](https://amashadihossein.github.io/datom/reference/datom_pull_gov.md)).
Otherwise lists keys under `projects/` via the gov storage client and
extracts unique top-level segments.

## Usage

``` r
.datom_gov_list_projects(gov_conn, gov_local_path = NULL)
```

## Arguments

- gov_conn:

  A gov-scoped `datom_conn` (from
  [`.datom_gov_conn()`](https://amashadihossein.github.io/datom/reference/dot-datom_gov_conn.md)
  or `.datom_build_gov_resolve_conn()`).

- gov_local_path:

  Optional absolute path to a local gov clone. When provided and the
  clone exists, the filesystem path is preferred.

## Value

Character vector of project names (sorted, may be empty).

## Details

Skips entries that don't contain a `ref.json` (corrupt registry rows).
