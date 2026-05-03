# Require Governance Attached on a Connection

Guard helper used by gov-only commands (`datom_projects`,
`datom_pull_gov`, `datom_sync_dispatch`) to fail with a single uniform
message when called on a no-governance connection. Not used by
`datom_decommission` – that command's gov-half is conditional, not
required.

## Usage

``` r
.datom_require_gov(conn, what)
```

## Arguments

- conn:

  A `datom_conn` object.

- what:

  Character. The user-facing name of the calling function (e.g.
  `"datom_pull_gov()"`), used in the error message.

## Value

Invisible `TRUE` when gov is attached. Aborts otherwise.
