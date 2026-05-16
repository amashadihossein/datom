# Union and deduplicate source_lineage lists

Takes a list of source_lineage lists and returns a single deduplicated
list. Dedup key is (project, table, version_sha). In case of
project+table collision with differing version_sha, all variants are
kept (the caller's diff logic will flag them).

## Usage

``` r
.datom_lineage_union(lineage_lists)
```

## Arguments

- lineage_lists:

  List of source_lineage lists (each itself a list of entries).

## Value

Deduplicated list of source_lineage entries.
