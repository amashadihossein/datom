# Show Repository Status

Displays connection info, table count, and (for developers) uncommitted
git changes and input file sync state.

## Usage

``` r
datom_status(conn)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

## Value

Invisibly, a list with `connection`, `tables`, and optionally `git` and
`input_files` status details.
