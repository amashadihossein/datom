# Read the Parents One Table Member Records

The snapshot read behind
[`.datom_check_set_parents()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_set_parents.md).
The format check sits **outside** the read's handler, so a snapshot from
a newer datom keeps its own refusal instead of being reworded as a read
failure – the same pairing as
[`.datom_parent_record()`](https://amashadihossein.github.io/datom/reference/dot-datom_parent_record.md).

## Usage

``` r
.datom_member_parents(conn, id)
```

## Arguments

- conn:

  The set's own developer connection.

- id:

  The member's `id` map.

## Value

The snapshot's `parents` list, or `NULL` when it records none.
