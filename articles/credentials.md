# Credential Management

## Overview

datom uses a **store object** to manage credentials and storage
configuration. Credentials are passed directly when constructing the
store — no magic environment variable naming conventions to remember.
This vignette explains how stores work, how to manage credentials, and
how to set up access for developers and readers.

## The Store Object

A `datom_store` bundles everything datom needs to connect to storage:

``` r
library(datom)

store <- datom_store(
  governance = datom_store_s3(
    bucket     = "clinical-data-bucket",
    prefix     = "study-001/",
    region     = "us-east-1",
    access_key = "your_aws_access_key",
    secret_key = "your_aws_secret_key"
  ),
  data = datom_store_s3(
    bucket     = "clinical-data-bucket",
    prefix     = "study-001/",
    region     = "us-east-1",
    access_key = "your_aws_access_key",
    secret_key = "your_aws_secret_key"
  ),
  github_pat = "ghp_your_github_pat"
)
```

The store has two S3 components (**governance** and **data**) that can
point to different buckets — or the same one. When both use the same
credentials and bucket, you can simplify:

``` r
s3 <- datom_store_s3(
  bucket     = "clinical-data-bucket",
  prefix     = "study-001/",
  access_key = "your_aws_access_key",
  secret_key = "your_aws_secret_key"
)

store <- datom_store(governance = s3, data = s3, github_pat = "ghp_...")
```

## Developer vs Reader

|                        | Developer                              | Reader                      |
|------------------------|----------------------------------------|-----------------------------|
| **S3 access**          | Read + write                           | Read only                   |
| **Git access**         | Yes (`github_pat`)                     | No                          |
| **Store construction** | `datom_store(..., github_pat = "...")` | `datom_store(...)` (no pat) |

datom derives your role from the store:

- **`github_pat` provided** → developer (role = `"developer"`)
- **`github_pat` omitted** → reader (role = `"reader"`)

``` r
# Developer store
dev_store <- datom_store(governance = s3, data = s3, github_pat = "ghp_...")
dev_store$role
#> [1] "developer"

# Reader store
reader_store <- datom_store(governance = s3, data = s3)
reader_store$role
#> [1] "reader"
```

## Where to Keep Credentials

### keyring (Recommended)

The [keyring](https://r-lib.github.io/keyring/) package stores
credentials in your OS keychain (macOS Keychain, Windows Credential
Manager, Linux Secret Service):

``` r
# One-time setup: store credentials
keyring::key_set_with_value("AWS_ACCESS_KEY", password = "AKIA...")
keyring::key_set_with_value("AWS_SECRET_KEY", password = "wJal...")
keyring::key_set_with_value("GITHUB_PAT", password = "ghp_...")

# Build store from keyring (every session)
store <- datom_store(
  governance = datom_store_s3(
    bucket     = "clinical-data-bucket",
    prefix     = "study-001/",
    access_key = keyring::key_get("AWS_ACCESS_KEY"),
    secret_key = keyring::key_get("AWS_SECRET_KEY")
  ),
  data = datom_store_s3(
    bucket     = "clinical-data-bucket",
    prefix     = "study-001/",
    access_key = keyring::key_get("AWS_ACCESS_KEY"),
    secret_key = keyring::key_get("AWS_SECRET_KEY")
  ),
  github_pat = keyring::key_get("GITHUB_PAT")
)
```

This keeps credentials encrypted at rest and out of plain-text files.

### `.Renviron` (Simple Alternative)

Add credentials to your user-level `~/.Renviron` file (restart R after
editing):

``` bash
# ~/.Renviron
MY_AWS_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE
MY_AWS_SECRET_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
GITHUB_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Then reference them when building the store:

``` r
store <- datom_store(
  governance = datom_store_s3(
    bucket     = "clinical-data-bucket",
    prefix     = "study-001/",
    access_key = Sys.getenv("MY_AWS_ACCESS_KEY"),
    secret_key = Sys.getenv("MY_AWS_SECRET_KEY")
  ),
  data = datom_store_s3(
    bucket     = "clinical-data-bucket",
    prefix     = "study-001/",
    access_key = Sys.getenv("MY_AWS_ACCESS_KEY"),
    secret_key = Sys.getenv("MY_AWS_SECRET_KEY")
  ),
  github_pat = Sys.getenv("GITHUB_PAT")
)
```

> **Security**: `~/.Renviron` is per-user and lives outside any git
> repository. Never commit credentials to version control.

### CI/CD Environments

In CI/CD (GitHub Actions, GitLab CI, etc.), use encrypted secrets:

``` yaml
# Example: GitHub Actions
env:
  AWS_ACCESS_KEY: ${{ secrets.AWS_ACCESS_KEY }}
  AWS_SECRET_KEY: ${{ secrets.AWS_SECRET_KEY }}
  GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
```

Then build the store from
[`Sys.getenv()`](https://rdrr.io/r/base/Sys.getenv.html) as above.

## Credential Validation

By default,
[`datom_store_s3()`](https://amashadihossein.github.io/datom/reference/datom_store_s3.md)
validates credentials at construction time by calling AWS STS
`GetCallerIdentity` and checking bucket access. If credentials are
wrong, you get an immediate error — not a cryptic failure mid-workflow.

``` r
# This will fail immediately if credentials are invalid
datom_store_s3(
  bucket     = "my-bucket",
  access_key = "bad-key",
  secret_key = "bad-secret"
)
#> ✖ AWS credential validation failed.
#> ℹ Check your access_key and secret_key.
```

Pass `validate = FALSE` to skip validation (useful for tests or offline
work):

``` r
datom_store_s3(
  bucket     = "my-bucket",
  access_key = "...",
  secret_key = "...",
  validate   = FALSE
)
```

## Multiple Projects

Each project gets its own store. There’s no global state or naming
convention to manage:

``` r
# Project 1
store_study_001 <- datom_store(
  governance = datom_store_s3(bucket = "bucket-a", prefix = "study-001/", ...),
  data       = datom_store_s3(bucket = "bucket-a", prefix = "study-001/", ...),
  github_pat = keyring::key_get("GITHUB_PAT")
)

# Project 2 — different bucket, different credentials
store_registry <- datom_store(
  governance = datom_store_s3(bucket = "bucket-b", prefix = "registry/", ...),
  data       = datom_store_s3(bucket = "bucket-b", prefix = "registry/", ...),
  github_pat = keyring::key_get("GITHUB_PAT")
)
```

## What Happens Under the Hood

When you pass a store to
[`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
or
[`datom_clone()`](https://amashadihossein.github.io/datom/reference/datom_clone.md),
datom internally bridges the store credentials into temporary
environment variables for the duration of the session. This means:

- You never need to set `DATOM_*` environment variables manually
- Credentials are scoped to the project name and cleaned up
  automatically
- The store is persisted (minus secrets) in `.datom/project.yaml` so
  that `datom_get_conn(path = "...")` can reconnect without re-providing
  the store

## What to Share with Teammates

### For Developers

Share the project setup instructions (typically in the repository
README):

| Item           | Value                                                                                        |
|----------------|----------------------------------------------------------------------------------------------|
| Git remote URL | `https://github.com/org/study-001-data.git`                                                  |
| S3 bucket      | `"clinical-data-bucket"`                                                                     |
| S3 prefix      | `"study-001/"`                                                                               |
| AWS access key | Distribute via your team’s secrets manager                                                   |
| AWS secret key | Distribute via your team’s secrets manager                                                   |
| `GITHUB_PAT`   | Each developer generates their own via [GitHub Settings](https://github.com/settings/tokens) |

Developers clone with:

``` r
store <- datom_store(
  governance = datom_store_s3(bucket = "clinical-data-bucket", prefix = "study-001/", ...),
  data       = datom_store_s3(bucket = "clinical-data-bucket", prefix = "study-001/", ...),
  github_pat = "ghp_...",
  remote_url = "https://github.com/org/study-001-data.git"
)

conn <- datom_clone(path = "study_001_data", store = store)
```

### For Readers

Readers don’t need git access. Share:

| Item            | Value                                        |
|-----------------|----------------------------------------------|
| `project_name`  | `"STUDY_001"`                                |
| S3 bucket       | `"clinical-data-bucket"`                     |
| S3 prefix       | `"study-001/"`                               |
| AWS credentials | Reader-scoped IAM keys (read-only S3 access) |

Readers connect with:

``` r
store <- datom_store(
  governance = datom_store_s3(bucket = "clinical-data-bucket", prefix = "study-001/", ...),
  data       = datom_store_s3(bucket = "clinical-data-bucket", prefix = "study-001/", ...)
)

reader_conn <- datom_get_conn(store = store, project_name = "STUDY_001")
```

## Troubleshooting

### Credential validation fails at store construction

    ✖ AWS credential validation failed.

Check that your `access_key` and `secret_key` are correct and that the
IAM user/role has `s3:ListBucket` and `sts:GetCallerIdentity`
permissions.

### GitHub PAT validation fails

    ✖ GitHub PAT validation failed.

Ensure your PAT has the `repo` scope. Generate a new one at [GitHub
Settings → Tokens](https://github.com/settings/tokens).

### Developer detected as reader

If
[`datom_get_conn()`](https://amashadihossein.github.io/datom/reference/datom_get_conn.md)
returns `role = "reader"` when you expect developer, the store was
constructed without `github_pat`. Rebuild the store with a PAT.

### Reader gets AccessDenied

The `bucket` and `prefix` must exactly match what was used during
[`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md).
A mismatched prefix is a common source of 403 errors. Ask your data
developer for the correct values.
