# Each Artifact's Current Version in One Project, in One Read

The manifest carries `current_version` per artifact, so learning what
moved costs **one read per project** rather than one per member. Only
the members that actually move then pay a snapshot read, through
[`datom_member()`](https://amashadihossein.github.io/datom/reference/datom_member.md),
which is what keeps the new pointer trustworthy.

## Usage

``` r
.datom_current_artifact_versions(conn)
```

## Arguments

- conn:

  A connection to the project.

## Value

A named character vector of artifact name to current version, with `NA`
for an entry that records none. Empty when the project has no artifacts.

## Details

The manifest is read directly rather than through
[`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
for two reasons:
[`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
abbreviates that column to 8 characters by default, which is not a
version a member can record, and its abort would name S3 on a local
backend.

An unreadable manifest **refuses**. It is the one answer that cannot be
reported: a member whose project could not be read is a member whose
state is unknown, which is the same situation as a missing connection.
