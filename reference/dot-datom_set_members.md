# The Member List of a Set, or an Abort Naming What Was Passed

Every verb in this file starts here, so "this is not a set" is reported
once and identically rather than surfacing as a `$` on a data frame
returning NULL.

## Usage

``` r
.datom_set_members(x, arg = "x")
```

## Arguments

- x:

  The value the caller passed.

- arg:

  Argument name for the message.

## Value

The member list, possibly empty.

## Details

A set with no members is **not** an error. The writer refuses an empty
member list, but the reader does not – a hand-built payload, or one from
a newer datom, reads back with none – so every verb below has to have an
answer for zero members.
