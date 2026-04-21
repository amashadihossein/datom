# Clinical Data Versioning with datom

## The Problem

Clinical trials generate evolving data. As subjects enroll and visits
accumulate, EDC (Electronic Data Capture) systems produce periodic data
extracts—snapshots that grow over time. A typical Phase II study might
have 50–100 tables updated monthly, and your analysis code must work
reproducibly against any of those snapshots.

datom solves this by version-controlling your raw data alongside code.
Metadata lives in git; actual data lives in S3 as content-addressed
parquet files. Every extract gets a SHA-based version, so you (or a
colleague, or a regulator) can reproduce any historical result.

This vignette walks through a realistic workflow: receiving monthly EDC
extracts for a Phase II study, syncing them to datom, listing tables and
versions, and retrieving historical snapshots by version.

> **Note**: datom manages *raw* versioned data. Derived datasets (like
> ADSL) are built downstream by the daapr ecosystem, which reads
> versioned inputs from datom.

## Example Study: STUDY-001

datom ships with simulated data for a small Phase II study:

- **48 subjects** enrolled over 6 months (Jan–Jun 2026)
- **DM domain**: demographics (age, sex, race, country, enrollment date)
- **EX domain**: exposure (treatment arm, dose, first dose date)
- **Monthly snapshots**: filtering by enrollment date simulates
  receiving updated EDC extracts

``` r
library(datom)

# View the monthly cutoff dates
datom_example_cutoffs()
#> month_1    month_2    month_3    month_4    month_5    month_6
#> "2026-01-28" "2026-02-28" "2026-03-28" "2026-04-28" "2026-05-28" "2026-06-28"

# Month-1 extract: only early enrollees
dm_m1 <- datom_example_data("dm", cutoff_date = "2026-01-28")
nrow(dm_m1)
#> [1] 6

# Month-3 extract: enrollment ramps up
dm_m3 <- datom_example_data("dm", cutoff_date = "2026-03-28")
nrow(dm_m3)
#> [1] 19

# Full study data
dm_all <- datom_example_data("dm")
nrow(dm_all)
#> [1] 48
```

## Setup

### Build a Store

A store bundles your S3 credentials and GitHub PAT into a single object.
Credentials are validated at construction time — bad credentials fail
immediately, not mid-workflow.

``` r
# Build S3 component (same bucket for governance and data in this example)
s3 <- datom_store_s3(
  bucket     = "clinical-data-bucket",
  prefix     = "study-001/",
  region     = "us-east-1",
  access_key = keyring::key_get("AWS_ACCESS_KEY"),
  secret_key = keyring::key_get("AWS_SECRET_KEY")
)

# Combine into a store with GitHub PAT for developer role
store <- datom_store(
  governance = s3,
  data       = s3,
  github_pat = keyring::key_get("GITHUB_PAT")
)
```

### One-Time Repository Initialization

A data developer sets up the datom repository once. This creates the
folder structure, initializes git with a remote, and generates
configuration files.

``` r
datom_init_repo(
  path         = "study_001_data",
  project_name = "STUDY_001",
  store        = store,
  create_repo  = TRUE,           # creates a GitHub repo via API
  repo_name    = "study-001-data" # GitHub repo name (defaults to project_name)
)
```

This creates:

    study_001_data/
    ├── .datom/
    │   ├── project.yaml       # Storage config (bucket, prefix, region)
    │   ├── dispatch.json        # Read method dispatch
    │   └── manifest.json       # Table catalog (initially empty)
    ├── input_files/            # Drop EDC extracts here (gitignored)
    └── .gitignore              # Keeps data files out of git

### Connect

``` r
conn <- datom_get_conn(path = "study_001_data")
print(conn)
#> ── datom connection
#> • Project: "STUDY_001"
#> • Role: "developer"
#> • Bucket: "clinical-data-bucket"
#> • Prefix: "study-001/"
#> • Region: "us-east-1"
#> • Path: /path/to/study_001_data
```

## Monthly Workflow: Receiving and Syncing EDC Extracts

### Month 1: First Data Transfer

Your data management team delivers the first EDC extract. You place the
files in `input_files/`:

``` r
# Simulate receiving the month-1 extract
cutoffs <- datom_example_cutoffs()

dm_m1 <- datom_example_data("dm", cutoff_date = cutoffs["month_1"])
ex_m1 <- datom_example_data("ex", cutoff_date = cutoffs["month_1"])

write.csv(dm_m1, "study_001_data/input_files/dm.csv", row.names = FALSE)
write.csv(ex_m1, "study_001_data/input_files/ex.csv", row.names = FALSE)
```

Scan and sync:

``` r
# Scan input_files/ — computes SHA of each file, compares against manifest
manifest <- datom_sync_manifest(conn)
#> ℹ Scanned 2 files: 2 new, 0 changed, 0 unchanged.
manifest
#>   name          file format  file_sha                           status
#> 1   dm .../dm.csv    csv    a1b2c3...                          new
#> 2   ex .../ex.csv    csv    d4e5f6...                          new

# Sync: imports each file, converts to parquet, uploads to S3, commits to git
results <- datom_sync(conn, manifest)
#> ℹ Syncing 2 tables...
#> ✔ dm synced (new).
#> ✔ ex synced (new).
#> ℹ Sync complete: 2 succeeded, 0 failed, 0 skipped.
```

What just happened:

1.  Each CSV was imported via
    [`rio::import()`](http://gesistsa.github.io/rio/reference/import.md)
    and written as parquet to S3
2.  A SHA-256 was computed for both the source file and the parquet data
3.  `metadata.json` and `version_history.json` were created in git and
    synced to S3
4.  A git commit was made and pushed for each table
5.  The local `manifest.json` was updated with current version info

## Exploring the Repository After Syncing

Before moving on, it’s worth pausing to verify the state of the
repository and get familiar with the data you’ve just versioned.

### List All Tables

[`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
gives you a quick inventory of what is registered and when each table
was last updated. Version hashes are shown as 8-character prefixes by
default — pass `short_hash = FALSE` for the full 64-character SHA:

``` r
datom_list(conn)
#>   name current_version last_updated          
#> 1 dm   a8ee7a31        2026-01-28T10:25:00Z
#> 2 ex   1f476930        2026-01-28T10:25:00Z
```

Pass `include_versions = TRUE` to see the current data SHA alongside the
version identifier:

``` r
datom_list(conn, include_versions = TRUE)
#>   name current_version current_data_sha last_updated          version_count
#> 1 dm   a8ee7a31        a1b2c3d4         2026-01-28T10:25:00Z  1
#> 2 ex   1f476930        d4e5f6a7         2026-01-28T10:25:00Z  1
```

### Inspect Version History

[`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
shows the full audit trail for a single table — who synced it, when, and
which version hash corresponds to each snapshot:

``` r
datom_history(conn, "dm")
#>   version   data_sha  timestamp             author       commit_message
#> 1 a8ee7a31  a1b2c3d4  2026-01-28T10:25:00Z  jane@co.com  Sync dm
```

Each version hash uniquely identifies the (data, metadata) pair at that
point in time. Right now there is one entry — the month-1 snapshot.

### Pull Down a Version to Evaluate

Before trusting that the sync worked correctly, read the data back and
spot-check it:

``` r
# Read the current (month-1) snapshot
dm_m1 <- datom_read(conn, "dm")
nrow(dm_m1)
#> [1] 6

# Spot-check: confirm only early enrollees are present
range(as.Date(dm_m1$RFSTDTC))
#> [1] "2026-01-03" "2026-01-28"
```

Rows, columns, and date ranges all look right. You can also read by the
version hash directly — short prefix matching works just like
`git log --abbrev-commit`:

> **Note**: The version hashes in this vignette (e.g., `"a8ee7a31"`) are
> illustrative. Your actual hashes will differ because they are derived
> from the data content. Always get your version hashes from
> [`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md)
> or
> [`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md)
> — never copy them from documentation.

``` r
# Equivalent: read by version hash 8 character prefix
# Replace "a8ee7a31" with the hash from your datom_history(conn, "dm")
dm_m1 <- datom_read(conn, "dm", version = "a8ee7a31")
nrow(dm_m1)
#> [1] 6
```

## Month 3: Updated Extract

Two months later, enrollment has progressed. The data management team
sends updated extracts:

``` r
# Simulate month-3 extract
dm_m3 <- datom_example_data("dm", cutoff_date = cutoffs["month_3"])
ex_m3 <- datom_example_data("ex", cutoff_date = cutoffs["month_3"])

write.csv(dm_m3, "study_001_data/input_files/dm.csv", row.names = FALSE)
write.csv(ex_m3, "study_001_data/input_files/ex.csv", row.names = FALSE)

# Scan — datom detects both files have changed (different SHA)
manifest <- datom_sync_manifest(conn)
#> ℹ Scanned 2 files: 0 new, 2 changed, 0 unchanged.

# Sync the updates
results <- datom_sync(conn, manifest)
#> ℹ Syncing 2 tables...
#> ✔ dm synced (changed).
#> ✔ ex synced (changed).
#> ℹ Sync complete: 2 succeeded, 0 failed, 0 skipped.
```

Because the parquet content changed (new subjects), datom uploaded new
parquet files to S3 with fresh SHAs. The old parquet files remain — they
are never overwritten or deleted.

## Change Detection

datom uses SHA-based content addressing for efficient change detection.
If the data hasn’t changed, no upload occurs:

``` r
# Re-sync with the same files — nothing happens
manifest <- datom_sync_manifest(conn)
#> ℹ Scanned 2 files: 0 new, 0 changed, 2 unchanged.

results <- datom_sync(conn, manifest)
#> ℹ All files unchanged. Nothing to sync.
```

## Data Reader Workflow

Downstream analysts don’t need git access. They connect directly to S3
using a reader store (no `github_pat`):

> **Important**: The `bucket` and `prefix` must exactly match the values
> used in
> [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md).
> Ask your data developer if you’re unsure. A mismatched prefix is a
> common source of `AccessDenied (HTTP 403)` errors.

``` r
# Reader store — no github_pat
reader_s3 <- datom_store_s3(
  bucket     = "clinical-data-bucket",
  prefix     = "study-001/",
  access_key = keyring::key_get("AWS_ACCESS_KEY_READER"),
  secret_key = keyring::key_get("AWS_SECRET_KEY_READER")
)

reader_store <- datom_store(governance = reader_s3, data = reader_s3)

reader_conn <- datom_get_conn(store = reader_store, project_name = "STUDY_001")
print(reader_conn)
#> ── datom connection
#> • Project: "STUDY_001"
#> • Role: "reader"
#> • Bucket: "clinical-data-bucket"
#> • Prefix: "study-001/"
#> • Region: "us-east-1"

# List available tables — same as developer
tables <- datom_list(reader_conn)
#>   name current_version last_updated          
#> 1 dm   a8ee7a31        2026-03-28T10:25:00Z
#> 2 ex   1f476930        2026-03-28T10:25:00Z

# Read the latest version
dm_latest <- datom_read(reader_conn, "dm")
nrow(dm_latest)
#> [1] 19

# Inspect the full history to find an earlier version
datom_history(reader_conn, "dm")
#>   version   data_sha  timestamp             author       commit_message
#> 1 a8ee7a31  e5f6a7b8  2026-03-28T10:25:00Z  jane@co.com  Sync dm
#> 2 f7a8b9c2  a1b2c3d4  2026-01-28T10:25:00Z  jane@co.com  Sync dm

# Read a specific earlier version by hash prefix
dm_v1 <- datom_read(reader_conn, "dm", version = "f7a8b9c2")
nrow(dm_v1)
#> [1] 6
```

## Repository Validation

After syncing, verify git and S3 are consistent:

``` r
datom_validate(conn)
#> ✔ All checks passed. Git and S3 are consistent.

# Check repository status
datom_status(conn)
#> ── datom status ──
#> ℹ Project: "STUDY_001"
#> ℹ Bucket: "clinical-data-bucket"
#> ℹ Role: "developer"
#> ✔ Git: clean (no uncommitted changes)
#> ℹ Branch: "main"
#> ℹ Tables on S3: 2
#> ✔ Input files: all 2 unchanged
```

## Key Concepts

### Content Addressing

Every data file is stored as `{sha256}.parquet`. Two identical datasets
always produce the same SHA, so there’s built-in deduplication.
Different data produces a different SHA, so versions never collide.

### Metadata vs Data

- **Metadata** (in git): `metadata.json` tracks dimensions, column
  names, data SHA, and timestamps. `version_history.json` maps each
  datom version to its data SHA.
- **Data** (in S3): Immutable parquet files, keyed by SHA. Never
  overwritten or deleted.

### datom Version = metadata SHA

The datom version identifier is the SHA of the metadata fields (sorted
alphabetically). Since metadata includes the data SHA, the version
uniquely identifies a (data, metadata) pair. You can use a short prefix
of the version hash (like `"f7a8b9"`) — datom resolves it as long as
it’s unambiguous, just like git short SHAs.

### Two User Roles

| Role          | Credentials                 | Capabilities                |
|---------------|-----------------------------|-----------------------------|
| **Developer** | AWS + `github_pat` in store | Read, write, sync, validate |
| **Reader**    | AWS only (no `github_pat`)  | Read any version            |

Role is derived from the store: if `github_pat` is provided, you’re a
developer.

## Summary

This workflow demonstrates the core datom loop for clinical data:

1.  **Build a store** with
    [`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md)
    → bundle credentials once
2.  **Initialize** with `datom_init_repo(store = ...)` → one-time setup
3.  **Receive** EDC extracts → place in `input_files/`
4.  **Scan** with
    [`datom_sync_manifest()`](https://amashadihossein.github.io/datom/reference/datom_sync_manifest.md)
    → detect new and changed files
5.  **Sync** with
    [`datom_sync()`](https://amashadihossein.github.io/datom/reference/datom_sync.md)
    → import, convert to parquet, version, upload
6.  **Explore** with
    [`datom_list()`](https://amashadihossein.github.io/datom/reference/datom_list.md),
    [`datom_history()`](https://amashadihossein.github.io/datom/reference/datom_history.md),
    and
    [`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
    → verify what was synced before moving on
7.  **Update** by dropping new extracts and repeating the sync cycle
8.  **Retrieve** any historical snapshot with
    `datom_read(conn, name, version = "...")`

Every step is tracked in git with full audit trail. Data readers access
any version via S3 without needing git credentials.

Derived datasets (like ADSL) belong in the downstream daapr ecosystem,
which reads versioned raw inputs managed by datom.
