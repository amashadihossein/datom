# First Extract

**Goal:** Stand up a versioned datom project using a local filesystem
store – write your first table, read it back, and confirm git is
tracking the history. No AWS account needed. The same workflow extends
to a shared team space (S3 or a shared filesystem) without changing a
single function call.

> **Already done the two-minute tour in the README?** The tour and this
> article cover the same ground. If your project initialized cleanly and
> [`datom_read()`](https://amashadihossein.github.io/datom/reference/datom_read.md)
> returned `TRUE`, you can jump straight to [Month 2
> Arrives](https://amashadihossein.github.io/datom/articles/month-2-arrives.md).

You are the data engineer for **STUDY-001**, a Phase II clinical trial.
The first EDC extract has just landed. datom lets you and your
collaborators build a **shared, versioned data space** – multiple
engineers writing new extracts, multiple analysts reading any version,
all coordinated through a single git history. Every write is a git
commit; every read resolves to an exact version SHA. No one can silently
overwrite history, and anyone with access to the repo can reproduce any
past analysis by pinning to a SHA.

This first article walks the local-only path. The same workflow – same
functions, same commands – works for a shared S3 space once you swap the
local store for an S3 store in [Promoting to
S3](https://amashadihossein.github.io/datom/articles/promoting-to-s3.md).

## Requirements

datom keeps **metadata in git** (diff-able, auditable) and **data
wherever you tell it to live** (S3 or a local directory). Even when data
lives on a local filesystem, metadata still goes to a git remote – that
is how version history stays reproducible across machines.

You need two things, both one-time:

- **A GitHub account** with a personal access token (PAT) scoped to
  `repo`. Store it in your OS keychain once with
  `keyring::key_set("GITHUB_PAT")`; every article after this picks it up
  automatically. See [Credentials in
  Practice](https://amashadihossein.github.io/datom/articles/credentials-in-practice.md)
  for a step-by-step walkthrough of PAT creation and keyring setup.
- **The `gh` CLI is not required** – datom creates GitHub repos through
  the GitHub REST API directly using your PAT.

No AWS, no cloud account, no governance repo for this article.

**Verify your keyring setup** before continuing:

``` r

nzchar(keyring::key_get("GITHUB_PAT"))   # should return TRUE
```

If it errors, follow the [Credentials in
Practice](https://amashadihossein.github.io/datom/articles/credentials-in-practice.md)
setup steps first.

## Set up your working paths

Two paths are needed, and they serve different roles:

- **`dev_dir`** – your local clone of the data git repository. This is
  where metadata (`project.yaml`, `metadata.json`, version history)
  lives. In a team setting this would be cloned on every developer’s
  machine.
- **`data_dir`** – the directory where parquet bytes are written. In a
  team setting this would be an S3 bucket (or a shared network mount),
  so every team member reads from the same physical store.

Here both point to temporary directories for demonstration. Replace them
with real paths – or an S3 store – when you are ready for a persistent
shared space.

``` r

library(datom)
library(fs)

# Two paths, two roles:
#   dev_dir  -- your local workspace for this project (stays on your machine)
#   data_dir -- where the actual data lives; replace with a real path or S3
#               store when you are ready for a persistent shared space
dev_dir  <- path(tempdir(), "study_001_dev")   # data git clone
data_dir <- path(tempdir(), "study_001_data")  # parquet bytes live here

dir_create(data_dir)
```

## Build a store

A **store** bundles the addresses datom needs: where parquet bytes go
and the GitHub PAT that lets datom push metadata. Governance is not
attached yet (`governance = NULL`); you’ll add it in [Promoting to
S3](https://amashadihossein.github.io/datom/articles/promoting-to-s3.md).

``` r

data_component <- datom_store_local(path = data_dir)

store <- datom_store(
  governance = NULL,
  data       = data_component,
  github_pat = keyring::key_get("GITHUB_PAT")
)
```

## Initialize the data repository

``` r

datom_init_repo(
  path         = dev_dir,
  project_name = "STUDY_001",
  store        = store,
  create_repo  = TRUE,
  repo_name    = "study-001-data"
)
```

This creates a GitHub repo, clones it into `dev_dir`, and commits a
`project.yaml` that records the project’s data store address. The git
repo is now live on GitHub. No parquet data is pushed to GitHub – only
the metadata commits travel over the wire; the parquet bytes stay in
`data_dir`.

Take a moment to inspect the repo structure before moving on:

``` r

# Metadata layout in the git clone
fs::dir_tree(dev_dir)

# Storage layout (empty until first write)
fs::dir_tree(data_dir)
```

## Connect

``` r

conn <- datom_get_conn(path = dev_dir, store = store)
print(conn)
#> -- datom connection
#> * Project: "STUDY_001"
#> * Role: "developer"
#> * Backend: "local"
#> * Root: "/tmp/.../study_001_data"
#> * Path: "/tmp/.../study_001_dev"
#> * Governance: not attached
```

## Write your first extract

The month-1 extract has just landed. Load the demographics snapshot for
subjects enrolled by 2026-01-28:

``` r

dm_m1 <- datom_example_data("dm", cutoff_date = "2026-01-28")
nrow(dm_m1)
#> [1] 4
```

Write it as a versioned datom table:

``` r

datom_write(
  conn,
  data    = dm_m1,
  name    = "dm",
  message = "Initial DM extract through 2026-01-28"
)
#> v Wrote "dm" (full): "a8ee7a31"
```

Three things just happened, in this order:

1.  The data frame was serialized to parquet and written to `data_dir`.
    **No data was pushed to the GitHub repo** – parquet bytes never
    leave your local store.
2.  `metadata.json` and `version_history.json` were updated in the git
    clone and committed.
3.  The metadata commit was pushed to GitHub. The version is now
    auditable from any machine with repo access, but the raw data stays
    where you put it.

After the write, explore what changed:

``` r

fs::dir_tree(data_dir)    # parquet file now present
datom_status(conn)        # table list with SHAs
datom_history(conn, "dm") # version history
```

## Read it back

``` r

dm_back <- datom_read(conn, "dm")
```

datom stores data in [Apache Parquet](https://parquet.apache.org/)
format and reads it back as a `tibble`. If your original object was not
already a tibble, the classes will differ even though the data is
identical:

``` r

identical(datom_read(conn, "dm"), dm_m1)
#> [1] FALSE  # dm_m1 may carry extra classes (e.g. data.frame)

identical(datom_read(conn, "dm"), tibble::as_tibble(dm_m1))
#> [1] TRUE   # compare as tibble for a clean round-trip check
```

The read does **not** go through GitHub. It uses the manifest cached in
`data_dir` to locate the parquet file and stream it back. This is the
same path a data reader on a different machine takes – they need access
to the data store, not to the git repo.

## Where you are

You have a fully versioned datom project up and running:

- One table (`dm`) with one version, one parquet file in `data_dir`
- Metadata committed and pushed to GitHub – version history is auditable
- Parquet data stays local – **nothing sensitive went to GitHub**
- No governance attached yet; you’ll add it in [Promoting to
  S3](https://amashadihossein.github.io/datom/articles/promoting-to-s3.md)
  when sharing matters

In the next article, the **month-2 extract arrives** with new subjects,
and you write a second version without overwriting the first.

## Teardown

**Planning to continue to [Month 2
Arrives](https://amashadihossein.github.io/datom/articles/month-2-arrives.md)?**
Leave everything as-is and reuse your `conn` in the next article. The
resume script in article 2 is there for users who closed their session;
you don’t need it.

If you are done exploring, pick one:

``` r

# Option A -- full scripted teardown (deletes local files AND the GitHub repo).
# Do this BEFORE unlink().
datom_decommission(conn, confirm = "STUDY_001")

# Option B -- local only (GitHub repo stays; delete it manually from the UI).
unlink(c(dev_dir, data_dir), recursive = TRUE)
```

Do not call [`unlink()`](https://rdrr.io/r/base/unlink.html) before
[`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md)
– removing the local clone first strips the GitHub remote reference and
the remote repo will not be deleted.
