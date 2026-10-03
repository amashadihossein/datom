# Refuse a Preview the Set Has Moved Away From

A `changed` row must find exactly one member for its artifact, at
`version_from`; a `new` row must find none. Anything else means the set
was edited after the preview was built, and acting anyway would leave a
removed member removed, move a member the preview never showed, or add a
second member for one artifact.

## Usage

``` r
.datom_sync_refuse_stale(todo, hits, members, x_given)
```

## Arguments

- todo:

  The `new` and `changed` rows.

- hits:

  For each row of `todo`, the positions of the set's members with that
  project and name.

- members:

  The set's member list.

- x_given:

  Whether the caller passed the set, which changes the remedy: the
  preview always compares against the stored set.

## Value

Invisibly `NULL`; aborts with class `datom_sync_manifest_stale`.
