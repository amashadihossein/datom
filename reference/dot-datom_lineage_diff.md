# Compute diff between declared and computed source_lineage

Compute diff between declared and computed source_lineage

## Usage

``` r
.datom_lineage_diff(declared, computed)
```

## Arguments

- declared:

  List of declared source_lineage entries.

- computed:

  List of computed (union) source_lineage entries.

## Value

List with `missing`, `extra`, `wrong_version` elements.
