# A Set With No Version Yet

What a set is before its first write: a name (or `NULL`, left for the
write to resolve), the project it belongs to, and no members. Spelled
`list(version = NULL, ...)` so the empty fields keep their names, which
is the shape
[`datom_get_set()`](https://amashadihossein.github.io/datom/reference/datom_get_set.md)
returns for a read set.
[`datom_assemble_set()`](https://amashadihossein.github.io/datom/reference/datom_assemble_set.md)
returns one, and the sync preview starts from one when the repo's set
has never been written.

## Usage

``` r
.datom_empty_set(name, project)
```

## Arguments

- name:

  The set's name, or `NULL`.

- project:

  The repo's project name.

## Value

A `datom_set`.
