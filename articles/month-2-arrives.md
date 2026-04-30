# Month 2 Arrives

> **Where we left off:** STUDY-001 is initialized. One table (`dm`)
> holds the first 6 subjects. Both git repos are live on GitHub.

A month has passed. Eight more subjects have enrolled. The data
management team sends you the month-2 extract, and you need to register
the new state without losing the old one.

This article introduces three capabilities: writing a second version of
an existing table, asking datom for a table’s full history, and reading
any historical version by its SHA.

## Resume the prior state

If you closed your R session after article 1 (or you’re picking the
journey up here), source the resume script. It rebuilds the end-state of
article 1 from scratch:

``` r
state <- source(
  system.file("vignette-setup", "resume_article_2.R", package = "datom")
)$value

conn       <- state$conn
study_dir  <- state$study_dir
```

The resume script is idempotent — running it twice in the same session
is safe. It uses [`tempdir()`](https://rdrr.io/r/base/tempfile.html)
paths by default; set `DATOM_VIGNETTE_DIR` and related env vars to
override.

If you’re continuing in the same R session as article 1, skip the source
call and reuse your existing `conn`.

## The month-2 extract

``` r
library(datom)

dm_m2 <- datom_example_data("dm", cutoff_date = "2026-02-28")
nrow(dm_m2)
#> [1] 14
```

Eight new subjects have been added. The month-1 rows are still there,
unchanged.

## Write the new version

``` r
datom_write(
  conn,
  data    = dm_m2,
  name    = "dm",
  message = "DM extract through 2026-02-28"
)
#> v Wrote "dm" (full): "5c1a3f7b"
```

`(full)` means both the data and the metadata changed — datom uploaded a
new parquet file and recorded a new entry in the version history. The
previous version is **still on disk and still in git**; nothing was
overwritten.

## Re-running is a no-op

datom is content-addressed: if you call
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
again with the same data, it detects that nothing has changed and
returns without producing a new version.

``` r
datom_write(conn, data = dm_m2, name = "dm")
#> i No changes detected for "dm". Skipping write.
```

This is what makes pipelines safe to re-run — accidental duplicate
writes cost nothing and pollute no history.

## Look at the history

``` r
datom_history(conn, "dm")
#>   version  data_sha  table_type  size_bytes  created_at           message
#> 1 5c1a3f7b 9e8f1c2d  raw         3812        2026-02-28T10:14:02Z DM extract through 2026-02-28
#> 2 a8ee7a31 4b6d0a7e  raw         1734        2026-01-28T09:02:11Z Initial DM extract through 2026-01-28
```

Two rows, newest first. The `version` column is the **metadata SHA** —
the identifier you use to pin a read.

## Pin a read to a specific version

The default
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
returns the current version:

``` r
dm_now <- datom_read(conn, "dm")
nrow(dm_now)
#> [1] 14
```

Pass a `version` to retrieve any historical snapshot:

``` r
hist    <- datom_history(conn, "dm")
m1_ver  <- hist$version[hist$message == "Initial DM extract through 2026-01-28"]

dm_m1_again <- datom_read(conn, "dm", version = m1_ver)
nrow(dm_m1_again)
#> [1] 6
```

The data you get back is bit-for-bit identical to what you wrote in
article 1, even though the current version of `dm` has 14 rows. This is
the property your future statisticians, regulators, and auditors rely
on.

## Where you are

- `dm` has two versions; you can read either at any time.
- Re-writing the same data is a free no-op.
- Version SHAs are stable across machines — share one and a colleague
  reads the same bytes you did.

In the next article, **a folder of extracts arrives** instead of a
single table, and we use
[`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)
to import them all at once.
