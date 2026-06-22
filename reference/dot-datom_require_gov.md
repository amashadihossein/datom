# Require Governance Attached on a Connection

Guard helper used by gov-only commands (e.g. `datom_projects`) to fail
with a single uniform message when called on a no-governance connection.

## Usage

``` r
.datom_require_gov(conn, what)
```

## Arguments

- conn:

  A `datom_conn` object.

- what:

  Character. The user-facing name of the calling function (e.g.
  `"datom_projects()"`), used in the error message.

## Value

Invisible `TRUE` when gov is attached. Aborts otherwise.
