# Check ref.json Matches Connection (Write-Time Guard)

Re-resolves `ref.json` from the governance store and compares against
the current connection's data location. Errors if they disagree,
preventing writes to the wrong location after a migration.

## Usage

``` r
.datom_check_ref_current(conn)
```

## Arguments

- conn:

  A `datom_conn` object.

## Value

Invisible TRUE if current, or skips silently if no governance fields.
