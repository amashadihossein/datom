# Refuse the Set's Own Project as a Source

The set's own project holds its outputs, which are derived from the
inputs and move only once they are re-derived. Checked on the labels,
before any read.

## Usage

``` r
.datom_refuse_own_project_source(own, labels)
```

## Arguments

- own:

  The set's own project name.

- labels:

  The project names of the source connections.

## Value

Invisibly `NULL`; aborts with class `datom_sync_own_project_source`.
