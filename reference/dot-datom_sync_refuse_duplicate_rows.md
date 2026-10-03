# Refuse Two Applied Rows for One Artifact

A preview never produces them. Without this the second row would stop as
stale, which names the wrong problem.

## Usage

``` r
.datom_sync_refuse_duplicate_rows(todo)
```

## Arguments

- todo:

  The `new` and `changed` rows.

## Value

Invisibly `NULL`; aborts with class `datom_sync_manifest_duplicate_row`.
