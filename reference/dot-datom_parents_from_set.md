# Declare Parents at the Versions a Set Pins

The `x =` route of
[`datom_parent()`](https://amashadihossein.github.io/datom/reference/datom_parent.md).
Each name is resolved by
[`.datom_find_member()`](https://amashadihossein.github.io/datom/reference/dot-datom_find_member.md),
the resolver
[`datom_fetch_member()`](https://amashadihossein.github.io/datom/reference/datom_fetch_member.md)
uses for a name, so the two verbs cannot pick different members for the
same name and labels. Tag validation is the same call with the same
remedy, for the same reason.

## Usage

``` r
.datom_parents_from_set(conn, table, x, tags)
```

## Arguments

- conn:

  A `datom_conn` scoped to the parents' project.

- table:

  Character vector of member names.

- x:

  A `datom_set`.

- tags:

  Optional label filter.

## Value

An unnamed list of parent records, one per `table`.
