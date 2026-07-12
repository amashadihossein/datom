# Union and deduplicate source_lineage lists (internal wrapper)

Thin wrapper retained for existing internal callers. Delegates to the
exported
[`datom_lineage_union()`](https://amashadihossein.github.io/datom/reference/datom_lineage_union.md).

## Usage

``` r
.datom_lineage_union(lineage_lists)
```

## Arguments

- lineage_lists:

  List of source_lineage lists (each a list of entries).

## Value

Deduplicated list of source_lineage entries.
