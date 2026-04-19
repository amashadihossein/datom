# {{{project_name}}}

> This repository is managed by [datom](https://github.com/amashadihossein/datom) — a version-controlled data management system for tabular data.

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

### 2. Create a store and connect

**Developer** (has git clone + S3 + GitHub access):

```r
library(datom)

store <- datom_store(
  governance = datom_store_s3("{{{bucket}}}", {{{prefix_code}}}, "{{{region}}}", access_key = "...", secret_key = "..."),
  data       = datom_store_s3("{{{bucket}}}", {{{prefix_code}}}, "{{{region}}}", access_key = "...", secret_key = "..."),
  github_pat = Sys.getenv("GITHUB_PAT"),
  remote_url = "{{{remote_url}}}"
)

conn <- datom_get_conn(path = ".", store = store)
```

**Reader** (S3 only, no git clone needed):

```r
library(datom)

store <- datom_store(
  governance = datom_store_s3("{{{bucket}}}", {{{prefix_code}}}, "{{{region}}}", access_key = "...", secret_key = "..."),
  data       = datom_store_s3("{{{bucket}}}", {{{prefix_code}}}, "{{{region}}}", access_key = "...", secret_key = "...")
)

conn <- datom_get_conn(store = store, project_name = "{{{project_name}}}")
```

### 3. Explore

```r
# List all tables
datom_list(conn)

# View version history of a specific table
datom_history(conn, "table_name")

# Read the latest version
datom_read(conn, "table_name")

# Read a specific version (use hash from datom_list or datom_history)
datom_read(conn, "table_name", version = "a8ee7a31")
```

## Notes

- **Do not commit data files** to this repository. The `.gitignore` is configured
  to exclude common data formats. Actual data lives in S3 as parquet files;
  git tracks only metadata.
- See the datom documentation for details on store configuration.

---

*Initialized on {{{created_at}}} with datom v{{{datom_version}}}.*
