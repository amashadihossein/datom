# Repoint One Member at One Version

Points 1, 2 and 3 of this file's header all live here: the labels are
attached verbatim rather than passed through the constructor, the link
is rebuilt through the shared factory, and the rebuilt record's recorded
project is compared against the one it replaces.

## Usage

``` r
.datom_repoint_member(record, conn, version)
```

## Arguments

- record:

  The member record being replaced.

- conn:

  The connection for that member's project.

- version:

  The version to pin.

## Value

The new member record, carrying the old labels and, when the old record
had one, a link to the new version.
