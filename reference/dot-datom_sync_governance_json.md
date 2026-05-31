# Sync governance.json Storage Mirror from Git Copy

Reads the git-canonical copy and overwrites the storage mirror. Call
after a partial failure to repair a missing or stale storage mirror.

## Usage

``` r
.datom_sync_governance_json(conn)
```

## Arguments

- conn:

  A `datom_conn` with `path` set to the local data git clone.

## Value

Invisible NULL.
