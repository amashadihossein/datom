# Refuse Applied Rows Whose Project Has No Connection

Only `new` and `changed` rows: they are the only ones apply acts on, and
a full preview's `not_checked` rows belong by definition to projects not
in `sources`, so checking every row would make an unedited preview
impossible to apply.

## Usage

``` r
.datom_sync_refuse_missing_source(todo, labels)
```

## Arguments

- todo:

  The `new` and `changed` rows.

- labels:

  The project names of the source connections.

## Value

Invisibly `NULL`; aborts with class `datom_sync_source_missing`.
