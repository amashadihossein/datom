# The Member List of a Set, or an Abort Naming What Was Passed

A `datom_set` however it was made – read back, or assembled with
[`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md)
– which is exactly what
[`datom_write_set()`](https://amashadihossein.github.io/datom/reference/datom_write_set.md)
takes, so the edit verbs and the write accept the same objects.

## Usage

``` r
.datom_edit_members(x, arg = "x")
```

## Arguments

- x:

  The value the caller passed.

- arg:

  Argument name for the message.

## Value

The member list, possibly empty.
