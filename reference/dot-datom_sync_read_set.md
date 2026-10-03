# The Repo's Set As Stored, or an Empty One When It Has Never Been Written

See point 1 of this file's header. The probe is on the set's
current-state document, which is what
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
reads first. `FALSE` means the set has never been written; `TRUE` means
read it, and any error from that read is the caller's to see. An error
from the probe itself is never absence: an unreachable store cannot
report that a file is missing.

## Usage

``` r
.datom_sync_read_set(conn, name)
```

## Arguments

- conn:

  The product repo's developer connection.

- name:

  The set's name.

## Value

A `datom_set`.
