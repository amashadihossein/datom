# Refuse a Row Whose Kind Disagrees With the Artifact

Refuse a Row Whose Kind Disagrees With the Artifact

## Usage

``` r
.datom_sync_check_kind(row, found)
```

## Arguments

- row:

  One preview row.

- found:

  The kind the member or the snapshot records.

## Value

Invisibly `NULL`; aborts with class `datom_sync_kind_mismatch`.
