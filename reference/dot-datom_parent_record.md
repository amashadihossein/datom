# Resolve One Parent Record From Its Versioned Snapshot

The body of
[`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md)
for one table at one named version, shared by both of its routes so a
parent declared by version and one declared from a set are read, checked
and shaped by the same code.

## Usage

``` r
.datom_parent_record(conn, table, version)
```

## Arguments

- conn:

  A `datom_conn` scoped to the parent's project.

- table:

  Parent table name.

- version:

  Parent version.

## Value

One parent record.
