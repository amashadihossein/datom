# Resolve Data Location from Governance Store

Reads `projects/{project_name}/ref.json` from the governance store and
returns the current data location as a named list. Single read, no
recursion, no chain-walking.

## Usage

``` r
.datom_resolve_ref(gov_conn, project_name = NULL)
```

## Arguments

- gov_conn:

  A `datom_conn`-like object scoped to the governance store (i.e.,
  `root`, `prefix`, `client` point to the governance store). Typically
  produced by `.datom_gov_conn(conn)`.

- project_name:

  Project name string. Used to build the project-scoped storage key
  `projects/{project_name}/ref.json`.

## Value

A named list with `root`, `prefix`, `region` for the current data
location.

## Details

If the ref has `previous` entries, a deprecation-style warning is
emitted to alert users that a migration occurred and old locations may
sunset.
