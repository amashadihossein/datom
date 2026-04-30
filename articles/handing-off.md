# Handing Off to a Statistician

> **Where we left off:** STUDY-001 is on S3. Four tables, version 1
> each.

A statistician on your team has been asked to run an interim analysis.
She needs the latest dm/ex/lb/ae snapshots, today, and she needs to be
able to re-create the same snapshot three months from now when the
safety review asks where the numbers came from.

This article is a **role-switch article**. You stop being the engineer
for a moment; you become the statistician on a different laptop, in a
different R session, with read-only credentials. The capabilities
introduced are not new functions — they’re a new way of using
[`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
and
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md).

## What the engineer sends

You (the engineer) message the statistician three pieces of information:

1.  **Governance repo URL** —
    `https://github.com/your-org/datom-governance.git`.
2.  **Data bucket / prefix / region** — `your-org-datom-data`,
    `study-001/`, `us-east-1`.
3.  **Project name** — `STUDY_001`.

Plus the credentials she’ll need to set up herself:

- A GitHub PAT with **read** access to `datom-governance` and the data
  repo. (Personal account, organization member; no special scope beyond
  `repo` read.)
- An AWS profile with **read** access to the data bucket.

You do **not** send her any data files. The point of datom is that
there’s nothing to send — she pulls bytes herself.

## What the statistician does

The remainder of this article is from the statistician’s side. **Open a
different R session** (or a fresh
[`tempdir()`](https://rdrr.io/r/base/tempfile.html)) to follow along.

### Set up credentials

``` r
# One-time per machine
keyring::key_set("GITHUB_PAT")
keyring::key_set("AWS_ACCESS_KEY_ID")
keyring::key_set("AWS_SECRET_ACCESS_KEY")
```

### Resume the prior state

The resume script for article 5 does the work of building a **reader
conn** against the S3 store. Unlike resume scripts 2–4, this one needs
network access (S3 + GitHub).

``` r
state <- source(
  system.file("vignette-setup", "resume_article_5.R", package = "datom")
)$value

reader_conn <- state$conn
print(reader_conn)
#> -- datom connection
#> * Project: "STUDY_001"
#> * Role: "reader"
#> * Backend: "s3"
#> * Root: "your-org-datom-data"
#> * Prefix: "study-001/"
```

The conn’s `role` is `"reader"`. Reader connections do not have a local
data clone. The statistician never ran
[`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
and never wrote anything; she just constructed a store and asked datom
for a connection.

### Read the latest of each table

``` r
library(datom)

dm <- datom_read(reader_conn, "dm")
ex <- datom_read(reader_conn, "ex")
lb <- datom_read(reader_conn, "lb")
ae <- datom_read(reader_conn, "ae")

nrow(dm)
#> [1] 14
```

Same data the engineer wrote. Same parquet bytes. No CSV transfer, no
“version 3 with the patches we applied.” One source of truth.

### Pin the analysis to a version

The interim analysis report needs a paragraph that says “data was
extracted from STUDY_001 at version X.” That version is the metadata SHA
from
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md):

``` r
hist_dm <- datom_history(reader_conn, "dm")
hist_dm$version[1L]
#> [1] "8a3b21cc9f..."
```

The statistician records `8a3b21cc9f...` (and the equivalent for
ex/lb/ae) in her analysis script. Three months from now, when the
auditor asks “where did this number come from,” she runs:

``` r
dm_at_analysis <- datom_read(reader_conn, "dm", version = "8a3b21cc9f...")
```

…and gets back the exact bytes the analysis used, even if STUDY_001 has
moved on through versions 4, 5, 6.

## Why this matters

Three things just happened that don’t happen with shared CSVs:

1.  **No copy was made.** The statistician’s analysis pulls directly
    from the canonical store. No “is your CSV the same as my CSV?”
    conversation ever happens.
2.  **The version is identifiable.** The same SHA references the same
    bytes on every machine, forever. This is the audit story regulators
    want.
3.  **The handoff is one-way.** The reader role has no write capability
    — the statistician *cannot* accidentally create a fork by saving a
    new version. The engineer remains the data steward.

## Where you are

You’re back to being the engineer. The statistician has what she needs.
Nothing in your workflow changed.

In the next article, **a second engineer joins** the project. Unlike the
statistician, she needs to write — and that means handling
pull-before-push discipline.

\`\`\`\`
