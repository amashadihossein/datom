# Auditing & Reproducibility

> **Where we left off:** STUDY-001 and STUDY-002 are both registered in
> the shared governance repo. STUDY-001 has six months of monthly
> extracts on S3; STUDY-002 is freshly initialized.

It’s month seven. A regulator emails: *“Please confirm what data backed
the safety review you ran on 2026-01-15, and demonstrate that the same
table can be regenerated today, byte-for-byte.”*

This article walks through the answer. The capabilities are ones you’ve
already met –
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md),
`datom_read(version = ...)`,
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
– and two new ones from the Phase-17 release:
[`datom_summary()`](https://amashadihossein.github.io/datom/reference/datom_summary.md)
and
[`datom_projects()`](https://amashadihossein.github.io/datom/reference/datom_projects.md).
The new lens is the **audit question**: not “what is the latest data?”
but “what was the data, on that date, for that report?”

``` r

state <- source(
  system.file("vignette-setup", "resume_article_8.R", package = "datom")
)$value

conn <- state$conn
```

## A quick portfolio snapshot

Before diving in, take a one-screen look at the portfolio. From any
developer’s clone of any project, with the gov clone refreshed:

``` r

datom_pull_gov(conn)
datom_projects(conn)
#>        name data_backend          data_root data_prefix        registered_at
#> 1 STUDY_001           s3 your-org-datom-data   study-001/ 2026-04-12T14:08:11Z
#> 2 STUDY_002           s3 your-org-datom-data   study-002/ 2026-04-30T09:22:03Z
```

[`datom_projects()`](https://amashadihossein.github.io/datom/reference/datom_projects.md)
reads `ref.json` for every project registered in the gov repo – one row
per project, telling you backend, root, and prefix without having to
clone any data repo. It’s the manager-friendly version of
`fs::dir_ls(gov_clone/projects)` you saw in the previous article.

For a single project,
[`datom_summary()`](https://amashadihossein.github.io/datom/reference/datom_summary.md)
gives the per-project view:

``` r

datom_summary(conn)
#>
#> -- datom project summary --
#> * Project:    "STUDY_001"
#> * Role:       "developer"
#> * Backend:    S3 -- "your-org-datom-data/study-001/"
#> * Tables:     4 (24 versions total)
#> * Last write: "2026-03-30T17:42:08Z"
#> * Remote:     "https://github.com/your-org/study-001-data.git"
```

Six months, four tables, twenty-four versions. That total is the audit
trail’s table of contents.

## The regulator’s question, decomposed

“What data backed the safety review on 2026-01-15?” decomposes into:

1.  **Which versions were current on 2026-01-15?** (find them in
    history)
2.  **What were the exact bytes?** (read by version, not by latest)
3.  **Can we prove the bytes haven’t drifted?** (validate)

### 1. Version history is the timeline

``` r

datom_history(conn, "lb", n = 20, short_hash = FALSE)
#>                    version                 data_sha            timestamp
#> 1  9f3a1b2c4d5e6f7a8b9c... f1e2d3c4b5a69788...  2026-03-30T17:42:08Z
#> 2  7c8d9e0f1a2b3c4d5e6f... a9b8c7d6e5f43322...  2026-02-28T16:15:55Z
#> 3  5e6f7a8b9c0d1e2f3a4b... 887766554433221... 2026-01-31T09:08:22Z
#> 4  3a4b5c6d7e8f9a0b1c2d... 776655443322110... 2026-01-12T11:30:14Z
#> 5  1c2d3e4f5a6b7c8d9e0f... 665544332211009... 2025-12-30T14:02:47Z
#>                              author                       commit_message
#> 1  Eng One <eng1@your-org.example>  sync month 6: lb +18 rows, ae +3 rows
#> 2  Eng One <eng1@your-org.example>  sync month 5: lb +21 rows, ae +1 row
#> 3  Eng One <eng1@your-org.example>  sync month 4 -- year-end cutoff
#> 4  Eng One <eng1@your-org.example>  hotfix: re-extract month 3 with corrected LBORRES
#> 5  Eng One <eng1@your-org.example>  sync month 3: lb +19 rows, ae +2 rows
```

For an audit trail, pass `short_hash = FALSE`. The full 40-character
`version` is the metadata SHA – the same string a reproducible script
will pin to. The `data_sha` is the content hash of the parquet bytes; it
changes only when the data changes.

The version current on 2026-01-15 is row 4: written on 2026-01-12,
superseded on 2026-01-31. Note the `commit_message` – “hotfix:
re-extract month 3 with corrected LBORRES” is the kind of breadcrumb
that an audit trail lives or dies by. It came from the `git commit`
message at sync time. (See [Version
SHAs](https://amashadihossein.github.io/datom/articles/design-version-shas.md)
for why these two SHAs differ and what each one guarantees.)

### 2. Pinned reads are byte-exact reproductions

The full SHA from row 4 goes straight into
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md):

``` r

lb_2026_01_15 <- datom_read(
  conn,
  name    = "lb",
  version = "3a4b5c6d7e8f9a0b1c2d..."  # full 40-char SHA from datom_history()
)

nrow(lb_2026_01_15)
#> [1] 587
```

That data frame is bit-for-bit what the safety review saw. datom
resolves `version` to a `data_sha`, downloads exactly that parquet
object, and reads it. There is no “approximate” read – the SHA either
resolves or it errors.

This is the answer to the regulator. A short script that pins every
table to a SHA from the audit window will regenerate the analysis input
identically, on any machine, today or in three years.

``` r

# A reproducible reader script -- the kind a statistician archives next
# to the safety review code.
lb <- datom_read(conn, "lb", version = "3a4b5c6d7e8f9a0b1c2d...")
ae <- datom_read(conn, "ae", version = "8b7a6c5d4e3f2a1b0c9d...")
dm <- datom_read(conn, "dm", version = "6d5e4f3a2b1c0d9e8f7a...")
ex <- datom_read(conn, "ex", version = "4f3e2d1c0b9a8f7e6d5c...")
```

Pinning by version SHA is the contract. Pinning by date (“the data as of
2026-01-15”) is a derived convenience – you compute it by walking
[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
once, recording the SHAs, and then never trusting the date again.

### 3. `datom_validate()` proves no drift

A pinned read trusts that the parquet bytes at the storage location for
`data_sha = f1e2d3c4...` still hash to that SHA.
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
verifies that for every table in the project:

``` r

result <- datom_validate(conn)
#> v All checks passed. Git and S3 are consistent.

result$valid
#> [1] TRUE
```

The check compares git-tracked metadata (`manifest.json`,
`.metadata/version_history.json` per table) against what’s actually
stored. A `FALSE` result means an object was deleted, replaced, or
corrupted in storage without a corresponding git commit – a discrepancy
the auditor needs to know about. With `fix = TRUE`, datom re-pushes
metadata to storage where it’s only a sync-state issue.

[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
is per-project and developer-only – it needs a local git clone to
compare. To validate the whole portfolio in CI, walk
[`datom_projects()`](https://amashadihossein.github.io/datom/reference/datom_projects.md):

``` r

projects <- datom_projects(conn)

results <- purrr::map(projects$name, function(nm) {
  proj_conn <- datom_get_conn(
    path  = fs::path("~/data-repos", nm),  # one clone per project
    store = state$conn$store              # same store; conn re-resolves
  )
  list(name = nm, valid = datom_validate(proj_conn)$valid)
})
```

In practice you’ll set this up once – a nightly job clones what’s
missing, pulls what’s stale, and validates each project. A single
`FALSE` is an alert.

## The audit envelope

Three things together constitute the auditable record for an analysis:

1.  **The pinned reader script** (the version SHAs).
2.  **The analysis code** (statistician’s R session, ideally in its own
    git repo with `renv::snapshot()`).
3.  **[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
    output at the time of report sign-off** (proof that storage matched
    git on that date).

Archive those three artefacts together with the report. Three years
later, anyone can run the reader script, get byte-identical input,
re-run the analysis, and compare outputs. The version history confirms
nothing was rewritten in between.

This is what immutability buys. The data SHA is the contract; git is the
time machine;
[`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
is the periodic confirmation that the contract still holds. None of
those three things are bespoke to a sponsor or an SOP – they’re
properties of how datom stores tables.

## Where you are

- [`datom_projects()`](https://amashadihossein.github.io/datom/reference/datom_projects.md)
  enumerates the portfolio in one call; one row per registered study, no
  per-project clone required.
- [`datom_summary()`](https://amashadihossein.github.io/datom/reference/datom_summary.md)
  is the at-a-glance per-project view.
- [`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
  with `short_hash = FALSE` produces the full audit trail; the `version`
  and `data_sha` columns are the pin points.
- `datom_read(version = ...)` is byte-exact. Pinning by SHA, not by
  date, is the contract.
- [`datom_validate()`](https://amashadihossein.github.io/datom/reference/datom_validate.md)
  is the periodic consistency check; walk
  [`datom_projects()`](https://amashadihossein.github.io/datom/reference/datom_projects.md)
  to extend it across a portfolio.

The user-journey track has one stop left – **Looking Ahead: datom in the
daapr Stack** – which steps back from STUDY-001 to frame what datom is
and isn’t, and where the higher-level packages take over.
