# Connection Requirements Shared by the Two Git-Mutation Verbs

Both verbs need the same three things and nothing else: a real
connection, a developer role, and a local clone to operate on.

## Usage

``` r
.datom_check_git_verb_conn(conn, verb)
```

## Arguments

- conn:

  A `datom_conn` object.

- verb:

  Name of the calling verb, for the message.

## Value

Invisible `TRUE`.
