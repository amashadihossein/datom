# {{{project_name}}}

> This repository is managed by [tbit](https://github.com/amashadihossein/tbit) — a version-controlled data management system for tabular data.

## Storage

| Setting | Value |
|---------|-------|
| Bucket  | `{{{bucket}}}` |
| Prefix  | {{{prefix_display}}} |
| Region  | `{{{region}}}` |

## Getting Started

### 1. Clone this repository

```bash
git clone {{{remote_url}}}
```

### 2. Set environment variables

**All users** (developers and readers) need S3 credentials:

```r
Sys.setenv(
  {{{access_key_env}}} = "<your-access-key>",
  {{{secret_key_env}}} = "<your-secret-key>"
)
```

**Developers** also need a GitHub PAT for git operations:

```r
Sys.setenv(GITHUB_PAT = "<your-github-pat>")
```

### 3. Connect

**Developer** (has git clone):

```r
library(tbit)
conn <- tbit_get_conn(path = ".")
```

**Reader** (S3 only, no git clone needed):

```r
library(tbit)
conn <- tbit_get_conn(
  bucket       = "{{{bucket}}}",
  prefix       = {{{prefix_code}}},
  project_name = "{{{project_name}}}"
)
```

### 4. Explore

```r
# List all tables
tbit_list(conn)

# View version history of a specific table
tbit_history(conn, "table_name")

# Read the latest version
tbit_read(conn, "table_name")

# Read a specific version (use hash from tbit_list or tbit_history)
tbit_read(conn, "table_name", version = "a8ee7a31")
```

## Notes

- **Do not commit data files** to this repository. The `.gitignore` is configured
  to exclude common data formats. Actual data lives in S3 as parquet files;
  git tracks only metadata.
- Credential environment variable names are derived from the project name.
  See the tbit documentation for details.

---

*Initialized on {{{created_at}}} with tbit v{{{tbit_version}}}.*
