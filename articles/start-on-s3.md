# Starting on S3

**Goal:** Stand up a versioned datom project whose data lives directly
in **Amazon S3** and onboard data using
[`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md).
The same progressive workflow from [Getting
Started](https://amashadihossein.github.io/datom/articles/getting-started.md)
applies here – one file, update, no-op, batch – with the only difference
being which store you build. This is the “start me in object storage”
path.

> **Want to dabble locally first?** Start with [Getting
> Started](https://amashadihossein.github.io/datom/articles/getting-started.md)
> instead – it uses a local filesystem store and needs no AWS account.
> The two paths use the **same functions**; the only difference is which
> store you build. You can read either one first.

You are the data engineer for **STUDY-001**, a Phase II clinical trial,
and your team already works in S3. There is no reason to stage data on a
laptop: you want the very first extract to land in the shared object
store, versioned from commit one. datom supports that directly. Metadata
still lives in a git repository (so version history is diff-able and
reproducible across machines); only the choice of data store changes.

**Two locations, two roles:**

- **Input folder** (mutable, disposable) – a landing zone for data not
  yet onboarded. Files here can be overwritten or deleted freely.
  Re-syncing already-onboarded content is a no-op. Nothing here is the
  source of truth.
- **Storage** (immutable, permanent) – once
  [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)
  onboards a file, storage holds the versioned, content-addressed copy
  in S3. The original input file is no longer needed; the onboarded data
  stands on its own.

## Requirements

datom keeps **metadata in git** and **data wherever you tell it to
live**. For this article that is an S3 bucket. You need three things:

- **A GitHub account** with a personal access token (PAT) scoped to
  `repo`. Store it in your OS keychain once with
  `keyring::key_set("GITHUB_PAT")`. The `gh` CLI is **not** required –
  datom creates the metadata repo through the GitHub REST API directly
  using your PAT.
- **An S3 bucket** you can read and write. datom does **not** create
  buckets: bucket lifecycle (encryption, versioning, retention) is your
  organization’s policy domain. A common convention is one bucket per
  study, with raw data at the bucket root (an empty prefix) and derived
  products under named prefixes (`adam/`, `tlf/`).
- **AWS credentials** (an access key and secret key) authorized for that
  bucket.

**Verify your keyring setup** before continuing:

``` r

nzchar(keyring::key_get("GITHUB_PAT"))   # should return TRUE
```

## Configure your environment

Everything machine-specific lives here. Credentials have several valid
sources, so they get their own section (and their own chunks) below; set
the rest once:

``` r

library(datom)
library(fs)

# --- Settings you control --------------------------------------------------
project_name <- "STUDY_001"        # logical project name (recorded in metadata)
repo_name    <- "study-001-data"   # GitHub repo name for the metadata repo

bucket <- "study-001-data"         # an S3 bucket you can read/write
                                   #   (datom does NOT create buckets)
prefix <- NULL                     # raw data at the bucket root; use e.g.
                                   #   "adam/" for a derived-products prefix
region <- "us-east-1"              # the bucket's AWS region

# Local working directory for the metadata git clone. The data itself never
# lands here -- it goes straight to S3. A temp dir is fine for this walkthrough.
dev_dir <- path(tempdir(), "study_001_dev")

# GitHub PAT (scoped to `repo`), read from your OS keychain by name.
github_pat <- keyring::key_get("GITHUB_PAT")
# ---------------------------------------------------------------------------
```

## Set your AWS credentials

[`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md)
takes `access_key` and `secret_key` as plain strings. datom never reads
them from the environment on your behalf – you pass the values in
explicitly. **Run exactly one** of the chunks below, whichever fits your
environment, then continue.

``` r

# Option A -- keyring (recommended for an interactive developer machine)
access_key <- keyring::key_get("AWS_ACCESS_KEY_ID")
secret_key <- keyring::key_get("AWS_SECRET_ACCESS_KEY")
```

``` r

# Option B -- environment variables (CI/CD, Docker)
access_key <- Sys.getenv("AWS_ACCESS_KEY_ID")
secret_key <- Sys.getenv("AWS_SECRET_ACCESS_KEY")
```

``` r

# Option C -- inline (fine for a quick session; never commit these values)
access_key <- "AKIAIOSFODNN7EXAMPLE"
secret_key <- "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

## Build the S3 store

A **store** bundles the addresses datom needs: where parquet bytes go
and the GitHub PAT that lets datom push metadata. The data component is
now an S3 component instead of a local one.

Governance is **not attached** (`governance = NULL`). A solo project’s
location authority is its own `project.yaml`; you do not need a
portfolio register to get started. Governance is opt-in and added later
(see [Governance and migration come
later](#governance-and-migration-come-later)).

``` r

data_component <- datom_store_s3(
  bucket     = bucket,
  prefix     = prefix,
  region     = region,
  access_key = access_key,
  secret_key = secret_key
)

store <- datom_store(
  governance = NULL,
  data       = data_component,
  github_pat = github_pat
)
```

By default
[`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md)
validates connectivity to the bucket as the store is built, so a
credential or permission problem surfaces immediately rather than at
first sync.

## Initialize the data repository

The local working directory (`dev_dir`) holds only the **git clone** –
the metadata repository. The data itself never lands there; it goes
straight to S3.

``` r

datom_init_repo(
  path         = dev_dir,
  project_name = project_name,
  store        = store,
  create_repo  = TRUE,
  repo_name    = repo_name
)
```

This creates a GitHub repo, clones it into `dev_dir`, and commits a
`project.yaml` that records the project’s S3 data store address. No
parquet data is pushed to GitHub – only metadata commits travel over the
wire.

[`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
also creates an `input_files/` directory inside the clone. It is
gitignored – files placed there are never committed. It is the inbox for
[`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md).

## Connect

``` r

conn <- datom_get_conn(path = dev_dir, store = store)
print(conn)
#> -- datom connection
#> * Project: "STUDY_001"
#> * Backend: "s3"
#> * Role: "developer"
#> * Data root: "study-001-data"
#> * Data region: "us-east-1"
#> * Governance: not attached
#> * Path: "/tmp/.../study_001_dev"
#> * Data repo: <https://github.com/.../study-001-data>
```

## Step 1: Sync one file

The month-1 extract has just landed. Drop it in the input folder:

``` r

# The input folder lives inside the git clone but is gitignored.
# Files placed here are the raw material for datom_sync().
input_dir <- path(dev_dir, "input_files")

write.csv(
  datom_example_data("dm", cutoff_date = "2026-01-28"),
  path(input_dir, "dm.csv"),
  row.names = FALSE
)
```

Scan and sync:

``` r

manifest <- datom_sync_manifest(conn)
#> i Scanned 1 file: 1 new, 0 changed, 0 unchanged.

datom_sync(conn, manifest)
#> i Syncing 1 table...
#> v dm synced (new).
#> i Sync complete: 1 succeeded, 0 failed, 0 skipped.
```

Three things just happened, in order:

1.  The CSV was read and serialized to parquet, then uploaded **to S3**
    – not to GitHub, and not to the local filesystem.
2.  `metadata.json` and `version_history.json` were updated in the git
    clone and committed.
3.  The metadata commit was pushed to GitHub. The version is auditable
    from any machine with repo access, while the raw data stays in your
    bucket.

Confirm:

``` r

datom_list(conn)
#>   name current_version current_data_sha last_updated
#> 1   dm        a8ee7a31         4b6d0a7e 2026-01-28T...

datom_history(conn, "dm")
#>    version  data_sha timestamp            message
#> 1 a8ee7a31 4b6d0a7e 2026-01-28T09:02:11Z dm synced from dm.csv
```

The input file is now disposable – storage (S3) is the source of truth:

``` r

file_delete(path(input_dir, "dm.csv"))
datom_read(conn, "dm")   # still works -- reads from S3
```

## Step 2: Update one file

The month-2 extract arrives with new subjects:

``` r

write.csv(
  datom_example_data("dm", cutoff_date = "2026-02-28"),
  path(input_dir, "dm.csv"),
  row.names = FALSE
)

manifest <- datom_sync_manifest(conn)
#> i Scanned 1 file: 0 new, 1 changed, 0 unchanged.

datom_sync(conn, manifest)
#> i Syncing 1 table...
#> v dm synced (changed).
#> i Sync complete: 1 succeeded, 0 failed, 0 skipped.
```

Two versions now coexist in S3. Read either one:

``` r

datom_history(conn, "dm")
#>    version  data_sha timestamp            message
#> 1 5c1a3f7b 9e8f1c2d 2026-02-28T10:14:02Z dm synced from dm.csv
#> 2 a8ee7a31 4b6d0a7e 2026-01-28T09:02:11Z dm synced from dm.csv

# Current version (month 2)
nrow(datom_read(conn, "dm"))
#> [1] 16

# Prior version (month 1) by SHA
hist   <- datom_history(conn, "dm")
m1_ver <- hist$version[nrow(hist)]   # oldest row is the month-1 version
nrow(datom_read(conn, "dm", version = m1_ver))
#> [1] 4
```

## Step 3: No-op repeat

``` r

manifest <- datom_sync_manifest(conn)
#> i Scanned 1 file: 0 new, 0 changed, 1 unchanged.

datom_sync(conn, manifest)
#> i All files unchanged. Nothing to sync.
```

Identical content is never re-uploaded. Safe to run on a schedule.

## Step 4: A batch of files

Month-3 brings four domains at once:

``` r

cutoff <- "2026-03-28"

write.csv(datom_example_data("dm", cutoff_date = cutoff),
          path(input_dir, "dm.csv"), row.names = FALSE)
write.csv(datom_example_data("ex", cutoff_date = cutoff),
          path(input_dir, "ex.csv"), row.names = FALSE)
write.csv(datom_example_data("lb", cutoff_date = cutoff),
          path(input_dir, "lb.csv"), row.names = FALSE)
write.csv(datom_example_data("ae", cutoff_date = cutoff),
          path(input_dir, "ae.csv"), row.names = FALSE)

manifest <- datom_sync_manifest(conn)
#> i Scanned 4 files: 3 new, 1 changed, 0 unchanged.

datom_sync(conn, manifest)
#> i Syncing 4 tables...
#> v dm synced (changed).
#> v ex synced (new).
#> v lb synced (new).
#> v ae synced (new).
#> i Sync complete: 4 succeeded, 0 failed, 0 skipped.
```

All four tables are now versioned in S3:

``` r

datom_list(conn)
#>   name current_version current_data_sha last_updated
#> 1   ae        3a17b8e2         e91d04ff 2026-03-28T...
#> 2   dm        d0922fc7         c2e80a14 2026-03-28T...
#> 3   ex        f44910b5         88a73e02 2026-03-28T...
#> 4   lb        718e02ca         4c3812dd 2026-03-28T...
```

## Reading as a reader

The reader role connects with bucket credentials alone – no PAT, no git
clone:

``` r

reader_store <- datom_store(
  governance = NULL,
  data       = datom_store_s3(
    bucket     = bucket,
    prefix     = prefix,
    region     = region,
    access_key = access_key,
    secret_key = secret_key
  )
)                                         # no PAT -> reader role

reader_conn <- datom_get_conn(store = reader_store, project_name = project_name)

datom_read(reader_conn, "lb")   # labs, streamed directly from S3
```

The read streams the parquet object from S3 directly; it does **not** go
through GitHub. A teammate on another machine takes the same path – they
need access to the bucket, not to the git repo.

## Where you are

- The same sync workflow (one file, update, no-op, batch) works
  identically on S3 – the backend is transparent.
- Four tables versioned in your bucket; metadata auditable on GitHub.
- Parquet data lives in S3 – **nothing sensitive went to GitHub**.
- No governance attached; the project stands on its own `project.yaml`.

To trace how derived tables descend from their sources, see [Tracing
Data
Lineage](https://amashadihossein.github.io/datom/articles/source-lineage.md).

## Governance and migration come later

Two capabilities are deliberately **not** part of this starting story:

- **Governance** – a shared portfolio register, dispatch-based reader
  access, and managed teardown. It is opt-in and provided by the
  governance companion package (`datomanager`), adopted when a project
  graduates from solo to shared/managed. Starting on S3 does not commit
  you to it.
- **Managed migration** – moving an existing project’s data between
  backends (local to S3, or S3 to S3) while preserving history. That is
  a separate, governed workflow documented with the companion package.
  Because you started on S3, you do not need it now; it remains
  available later without contradicting anything you set up here.

In other words, **start-on-S3** and **migrate-to-S3** are complementary
entry points: this article is the greenfield path, and managed migration
is the move-an-existing-project path.

## Teardown

When you are done exploring, tear the project down.
[`datom_repo_delete()`](https://amashadihossein.github.io/datom/reference/datom_repo_delete.md)
removes the GitHub metadata repo and the local clone. **Do this before**
deleting the local directory by hand – removing the clone first strips
the GitHub remote reference and the remote repo will not be deleted.

``` r

datom_repo_delete(conn, confirm = "STUDY_001")
```

[`datom_repo_delete()`](https://amashadihossein.github.io/datom/reference/datom_repo_delete.md)
does **not** empty your S3 bucket – bucket lifecycle is your
organization’s domain, not datom’s. Remove the project’s objects from S3
with your own tooling (for example, the AWS CLI) if you no longer need
them.
