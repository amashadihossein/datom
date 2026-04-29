# Pull Latest Changes from the Governance Repo

Fetches and merges upstream changes into the local governance clone.
Useful when you need to refresh governance metadata (dispatch, ref,
migration history) without touching the data repo.

## Usage

``` r
datom_pull_gov(conn)
```

## Arguments

- conn:

  A `datom_conn` object from
  [`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md).

## Value

Invisibly, the result of the pull.

## Details

In normal workflows
[`datom_pull()`](https://amashadihossein.github.io/datom/reference/datom_pull.md)
handles both repos. Use this only when you need the gov clone to be
current independently.

Requires a developer connection with `gov_local_path` set.
