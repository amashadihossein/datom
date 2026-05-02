# Promoting to S3

> **Where we left off:** STUDY-001 has four tables (`dm`, `ex`, `lb`,
> `ae`), all on your laptop. Both git repos are on GitHub.

A colleague on a different laptop now needs to read the data. Local
filesystem storage was fine when you were the only one writing; it stops
working the moment a second person needs the same bytes.

This article promotes STUDY-001 from local-filesystem data storage to
**S3**. After this article, your gov repo and data repo are unchanged on
the GitHub side, but the parquet bytes live in an S3 bucket — and any
teammate with read access to that bucket can pull a versioned snapshot.

## A note on local -\> S3 migration

datom’s `ref.json` has slots for `previous` data locations and a
`migration_history.json` is initialized for every project. The intent is
a future `datom_migrate_data()` that copies bytes from one store to
another without resetting history. **That capability isn’t shipped yet**
(planned for a future release). Until it is, the practical path is to
retire the local project and re-establish it on S3.

We choose this honest, slightly-lossy path here because:

- The history of a *brand-new* study with three months of extracts is
  recoverable: re-write the four current tables and you’re done.
- Studies that have run for a year on local storage shouldn’t have run
  on local storage — they are the audience for `datom_migrate_data()`
  later.

If preserving history across a backend change matters to your project
**right now**, start on S3 from article 1 and skip this article.

## Set up AWS credentials

datom uses the [keyring](https://r-lib.github.io/keyring/) package for
credentials, the same way it stored your GitHub PAT in article 1. Set
your AWS access keys once:

``` r

keyring::key_set("AWS_ACCESS_KEY_ID")
keyring::key_set("AWS_SECRET_ACCESS_KEY")
```

If your organization issues short-lived session tokens (STS), set the
session token too:

``` r

keyring::key_set("AWS_SESSION_TOKEN")
```

You will also need:

- A **bucket** you can read and write. datom does not create buckets for
  you — bucket lifecycle (encryption, versioning, retention) is your
  organization’s policy domain, not datom’s.
- A **prefix** within the bucket if you share the bucket with other
  projects. Below we use `study-001/`.

The full credential reference, including how to scope a reader-only PAT
and how to handle SSO + assume-role flows, is in [Credentials in
Practice](https://amashadihossein.github.io/datom/articles/credentials-in-practice.md).

## Resume the prior state

``` r

state <- source(
  system.file("vignette-setup", "resume_article_4.R", package = "datom")
)$value

old_conn  <- state$conn
study_dir <- state$study_dir
```

`old_conn` is the local-backend conn from article 3. We’ll use it to
read the four current tables, then decommission it.

## Snapshot the current data

Before tearing anything down, capture the latest state of each table in
memory:

``` r

library(datom)

cutoff   <- "2026-03-28"
snapshot <- list(
  dm = datom_read(old_conn, "dm"),
  ex = datom_read(old_conn, "ex"),
  lb = datom_read(old_conn, "lb"),
  ae = datom_read(old_conn, "ae")
)
```

Each element is the current version’s data frame.

## Decommission the local project

[`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md)
removes the project from governance, deletes the GitHub repos, and
clears the local clones and parquet store. It is **destructive** and
requires you to type the project name as `confirm` to proceed.

``` r

datom_decommission(old_conn, confirm = "STUDY_001")
#> i Removing data store contents under datom/STUDY_001/
#> v Deleted GitHub repo `study-001-data`
#> v Removed local data clone /tmp/.../study_001_data
#> v Unregistered STUDY_001 from governance
#> v Removed gov storage entry projects/STUDY_001/
```

The governance repo (`datom-governance`) is **not** decommissioned —
it’s a shared registry across all your projects. Only `STUDY_001` is
removed from it.

## Build the S3 store

``` r

library(fs)

study_dir <- path(tempdir(), "study_001_data")  # fresh clone target

aws_data <- datom_store_s3(
  bucket     = "your-org-datom-data",   # <-- replace with a bucket you own
  prefix     = "study-001/",
  region     = "us-east-1",
  access_key = keyring::key_get("AWS_ACCESS_KEY_ID"),
  secret_key = keyring::key_get("AWS_SECRET_ACCESS_KEY")
)

# Reuse the existing local gov store - the gov repo carries on.
gov_local <- datom_store_local(
  path = path(tempdir(), "study_001_gov_root")
)

store <- datom_store(
  governance     = gov_local,
  data           = aws_data,
  github_pat     = keyring::key_get("GITHUB_PAT"),
  gov_repo_url   = state$gov_repo_url,
  gov_local_path = state$gov_clone_path
)
```

## Re-initialize STUDY_001 on S3

``` r

datom_init_repo(
  path         = study_dir,
  project_name = "STUDY_001",
  store        = store,
  create_repo  = TRUE,
  repo_name    = "study-001-data"
)

conn <- datom_get_conn(path = study_dir, store = store)
print(conn)
#> -- datom connection
#> * Project: "STUDY_001"
#> * Role: "developer"
#> * Backend: "s3"
#> * Root: "your-org-datom-data"
#> * Prefix: "study-001/"
```

The data backend is now `"s3"`. From here on, every
[`datom_write()`](https://amashadihossein.github.io/datom/reference/datom_write.md)
uploads parquet to S3 and every
[`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
streams it back from S3.

## Replay the four tables

``` r

datom_write(conn, snapshot$dm, "dm",
            message = "Re-establish dm on S3 (was local through 2026-03-28)")
datom_write(conn, snapshot$ex, "ex",
            message = "Re-establish ex on S3 (was local through 2026-03-28)")
datom_write(conn, snapshot$lb, "lb",
            message = "Re-establish lb on S3 (was local through 2026-03-28)")
datom_write(conn, snapshot$ae, "ae",
            message = "Re-establish ae on S3 (was local through 2026-03-28)")
```

Each table now has version 1 in the S3-backed project. The history of
versions 1–3 from the local project is gone; the **commit messages**
above are your audit trail for that.

## Confirm

``` r

datom_list(conn)
#>   name current_version current_data_sha last_updated
#> 1   ae    19f44e3a       e91d04ff         2026-04-29T...
#> 2   dm    8a3b21cc       c2e80a14         2026-04-29T...
#> 3   ex    5d72e0f1       88a73e02         2026-04-29T...
#> 4   lb    c1ffea90       4c3812dd         2026-04-29T...

# Note: data_sha values match the local project (parquet bytes are identical).
# Version SHAs are new because metadata (commit times, messages) differs.
```

The `data_sha` column matches the local project’s last `data_sha` for
each table — the **bytes** are identical, datom is just storing them in
a different place. Version SHAs are different because they include
metadata that changed (timestamps, commit messages).

## Where you are

- STUDY_001 lives on S3. Your local clone is just a working copy of the
  git metadata.
- The four tables are at version 1 again, with honest commit messages
  recording the local-era history.
- `ref.json` in the gov repo points at the S3 bucket; any teammate who
  clones the data repo and has S3 read access can read the data.

In the next article, you **hand the project off to a statistician** who
needs to read the data without write access — the canonical reader role.

\`\`\`\`
