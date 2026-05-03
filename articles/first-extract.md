# First Extract

You are the data engineer for **STUDY-001**, a Phase II clinical trial.
The first EDC extract has just landed in your inbox. By the end of this
article you will have a versioned datom repository, your first table
written, and the same data read back out — all on your laptop, with no
AWS account.

## What you’ll need

datom keeps **metadata in git** (so changes are diff-able and auditable)
and **data wherever you tell it to live** (S3, GCS, a local directory).
Even when the data lives on your laptop, the metadata still goes to a
git remote.

datom also has a **governance layer** for portfolios that share data
across teams (registry of projects, dispatch routing, managed
migration). You don’t need it for your first project, and this article
doesn’t set it up. We’ll attach governance later, in [Promoting to
S3](https://amashadihossein.github.io/datom/articles/promoting-to-s3.md),
at the natural moment when sharing matters.

Two prerequisites, one-time setup:

- A **GitHub account** and a personal access token (PAT) with `repo`
  scope. Save it once with `keyring::key_set("GITHUB_PAT")` so
  subsequent articles pick it up automatically.
- The **`gh` CLI is not required** — datom creates GitHub repos through
  the GitHub REST API directly using your PAT.

That’s it. No AWS, no cloud account, no governance repo.

## Set up your working paths

Articles 1–3 use temporary directories so you can throw everything away
with a single [`unlink()`](https://rdrr.io/r/base/unlink.html) at the
end. If you’d rather keep the data around, replace the two
[`tempdir()`](https://rdrr.io/r/base/tempfile.html) lines with
`~/study_001_data` and `~/study_001_local_root`.

``` r

library(datom)
library(fs)

study_dir <- path(tempdir(), "study_001_data")        # data git clone
data_root <- path(tempdir(), "study_001_data_root")   # parquet bytes live here

dir_create(data_root)
```

## Build a store

A **store** bundles all the addresses datom needs: where parquet bytes
go and the GitHub PAT that lets datom push metadata. We’re not attaching
governance yet, so `governance = NULL`.

``` r

data_component <- datom_store_local(path = data_root)

store <- datom_store(
  governance = NULL,
  data       = data_component,
  github_pat = keyring::key_get("GITHUB_PAT")
)
```

## Initialize the data repository

``` r

datom_init_repo(
  path         = study_dir,
  project_name = "STUDY_001",
  store        = store,
  create_repo  = TRUE,
  repo_name    = "study-001-data"
)
```

This creates a GitHub repo, clones it into `study_dir`, and writes a
`project.yaml` that points the repo at your local data store. The git
repo is now live on GitHub with an empty parquet area waiting for your
first table. No governance repo is created — `STUDY_001` is a private,
laptop-only project at this stage.

## Connect

``` r

conn <- datom_get_conn(path = study_dir, store = store)
print(conn)
#> -- datom connection
#> * Project: "STUDY_001"
#> * Role: "developer"
#> * Backend: "local"
#> * Root: "/tmp/.../study_001_data_root"
#> * Path: "/tmp/.../study_001_data"
#> * Governance: not attached
```

## Write your first extract

The month-1 extract has just landed. Load the demographics snapshot for
subjects enrolled by 2026-01-28:

``` r

dm_m1 <- datom_example_data("dm", cutoff_date = "2026-01-28")
nrow(dm_m1)
#> [1] 6
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

1.  The data frame was hashed and written as parquet to your local data
    root.
2.  `metadata.json` and `version_history.json` were written to the data
    git clone and committed.
3.  The commit was pushed to GitHub. Your data is now versioned and the
    version is auditable from anywhere with access to the repo.

## Read it back

``` r

dm_back <- datom_read(conn, "dm")
identical(dm_back, dm_m1)
#> [1] TRUE
```

The read does **not** go through GitHub. It uses the manifest cached in
your data root to find the parquet file and stream it back. This is the
same path a data reader on a different machine takes — they just need
access to the data root, not git.

## Where you are

You have a fully versioned datom project on your laptop:

- One table (`dm`) with one version, one parquet file
- Data git repo pushed to GitHub
- Round-trip read/write working
- No governance attached yet — you’ll add that in [Promoting to
  S3](https://amashadihossein.github.io/datom/articles/promoting-to-s3.md),
  the natural moment when sharing matters.

In the next article, the **month 2 extract arrives** with new subjects,
and we write it without overwriting history.

## Cleanup (optional)

If you’re not continuing to article 2 right now:

``` r

unlink(c(study_dir, data_root), recursive = TRUE)
```

Note: this removes only your local files. The GitHub repo
`study-001-data` remains — delete it from the GitHub UI if you don’t
want to keep it. Article 7 introduces
[`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md)
for the scripted teardown.
