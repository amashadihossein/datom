# Refuse a Set That Belongs to Another Project

A `datom_set` records the project it belongs to: the one it was read
from, or the connection it was assembled on. The write stamps
`conn$project_name` into the stored document, so a set from another
project written here would be silently re-homed. The name gate does not
catch that on its own, because two product repos may declare the same
set name (two studies, each with a set called `adam`).

## Usage

``` r
.datom_check_set_project(conn, name, set_project)
```

## Arguments

- conn:

  The product repo's developer connection.

- name:

  The resolved set name, for the message.

- set_project:

  The project the set carries, or `NULL` when it carries none (a plain
  member list, or a set whose project was never recorded).

## Value

Invisibly `NULL`; aborts with class `datom_set_project_mismatch`.
