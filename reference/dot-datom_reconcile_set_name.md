# The Set Name a Write Uses, From the Call and From the Set Itself

A `datom_set` carries its name, and the caller may pass `name =` too.
When both are given they must agree: preferring either would write a set
under a name one of them did not say. When only one is given it is the
one used, and
[`.datom_check_set_write_gates()`](https://amashadihossein.github.io/datom/reference/dot-datom_check_set_write_gates.md)
then checks it against the repo's declared set – so a set named for
another repo stops there, with the gate's message. A set with no name
(an assembled one, usually) takes the declared one.

## Usage

``` r
.datom_reconcile_set_name(name, set_name)
```

## Arguments

- name:

  The `name` argument, or `NULL`.

- set_name:

  The name the set carries, or `NULL` (also when `members` was a plain
  list of records).

## Value

The name to hand to the gate, or `NULL`.
