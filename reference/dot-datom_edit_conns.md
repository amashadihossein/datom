# The Supplied Connections, Keyed by the Project Each One Claims

One connection or a list of them, because a set legitimately spans
projects and access in datom is per project. The key is
`conn$project_name`, which nothing verifies – see this file's header for
what confirms the choice afterwards.

## Usage

``` r
.datom_edit_conns(conn, arg = "conn")
```

## Arguments

- conn:

  A `datom_conn`, or a list of them.

- arg:

  Argument name for the message.

## Value

A named list of connections.

## Details

**Two connections claiming one project are refused rather than
ordered**, since choosing between them would be a guess and the wrong
one reads another project's namespace.
