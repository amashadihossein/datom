# datom Package Specification

## Overview

Picture an analytical workflow built to derive specific insights from evolving data served as snapshots. Your dataset might consist of 50 or 100 different tables from which you create additional derived tables as your analysis requires. As these tables evolve and your transformation logic changes, ensuring that outputs remain trackable and reproducible for all collaborators becomes increasingly difficult. This scenario is familiar in clinical data science, where agility is key and reproducibility is paramount.

datom serves as a foundational building block for addressing this use case, leveraging only tools readily available to data scientists: git, GitHub, and cloud object storage. While initially supporting AWS S3, datom is designed to be cloud storage agnostic. Similarly, though we begin with an R implementation, the architecture supports future Python and other language implementations.

The package enables version-controlled data management by abstracting tables as code in git while storing actual data in cloud storage. For collections of tabular datasets that evolve over time, datom enables:

- Setting up cloud-based repositories
- Frequently syncing data with automatic versioning
- Tracking complete data lineage
- Accessing any historical version for reproducibility

The primary utility motivating datom is building version-tracked data products. Companion packages (dpbuild, dpdeploy, and dpi) build upon datom to collectively enable creating, managing, and accessing reproducible data products in clinical and scientific workflows.

---

## Design Principles

1. **Git as source of truth**: All metadata originates in git for version control
2. **S3 metadata caching**: Metadata synced to S3 enables data reader access without GitHub
3. **Separated workflows**: Data developers need git + S3 access for writes; data readers need only S3 access for reads
4. **Content addressing**: SHA-based storage for efficient deduplication
5. **Implicit location**: Data location derived from connection + redirect chain, not stored in metadata
6. **Language agnostic**: Designed for R and Python implementations
7. **Storage agnostic**: Initial S3 support with extensibility to other cloud providers
8. **One repo per project**: Each git repository manages a single project/prefix

---

## Versioning Model

### What Gets Versioned

datom distinguishes between **versioned content** and **tracked configuration**:

| Category | Files | Versioned? | Creates version_history entry? |
|----------|-------|------------|-------------------------------|
| **Data** | `{data_sha}.parquet` | Yes | Yes |
| **Metadata** | `metadata.json`, `{metadata_sha}.json` | Yes | Yes |
| **Configuration** | `routing.json`, `project.yaml`, `manifest.json` | No | No |

### datom Version = metadata_sha

The datom version is the **metadata_sha**, computed from alphabetically sorted metadata fields (which include `data_sha`). This uniquely identifies a (data, metadata) pair.

```
metadata fields (sorted, semantic only) → JSON canonical form → SHA-256 → metadata_sha
       ↑                                         ↑
   includes data_sha               jsonlite::toJSON(auto_unbox=TRUE)
```

**Volatile fields excluded**: `created_at` and `datom_version` are stripped before hashing. These change on every call (timestamp) or with package upgrades but don't represent semantic changes to the data or metadata.

**JSON canonical form**: The SHA is computed over `jsonlite::toJSON()` output (with `serialize = FALSE`), not over the R object directly. This ensures that metadata built in-memory and metadata read back from JSON (e.g., from S3) always produce the same SHA, despite R type differences introduced by JSON round-tripping (integer vs double, character vector vs list).

**Routing is explicitly excluded** from version computation. Changing routing does not change any datom version.

### Git's Role

Git serves two distinct purposes:

| Purpose | Applies to | Git commits? | Affects datom version? |
|---------|------------|--------------|----------------------|
| **Version control** | Data + metadata | Yes | Yes |
| **Conflict resolution** | Routing + config | Yes | No |

All files live in one repo for simplicity, but:
- Data/metadata commits → create version_history.json entries
- Routing/config commits → tracked in git only (audit trail, multi-dev coordination)

### Example: Routing Change

```
Day 1:  datom_write() → version "xyz789" created
        git commit includes: metadata.json, version_history.json
        
Day 2:  Edit routing.json (add "cached" context)
        git commit includes: routing.json only
        
Result: datom version unchanged ("xyz789")
        git log shows both commits
        version_history.json unchanged
```

### Why This Separation?

- **Routing is operational**: "how to access" — applies to all versions
- **Data + metadata is content**: "what exists" — each version is immutable
- **Single repo simplicity**: git handles conflict resolution for everything
- **Clean versioning**: version identity not polluted by config changes

---

## User Types

| User Type | Description | Credentials Required |
|-----------|-------------|---------------------|
| **Data developers** | Create and update datasets, manage evolving clinical/scientific data | AWS credentials + GITHUB_PAT |
| **Data readers** | Consume versioned data for analysis, need reproducible access | AWS credentials only |
| **Data products** | Analytical applications built on versioned datoms (via dpbuild, dpdeploy, dpi) | AWS credentials only |

User type is auto-detected based on the presence of `GITHUB_PAT`.

---

## Architecture

### Storage Structure

**Git Repository (Authoritative Source)**:
```
repo/
├── {table_name}/
│   ├── metadata.json             # Current metadata only
│   └── version_history.json      # Index: version → SHA mappings
├── input_files/                   # Flat directory for source files (gitignored)
│   ├── customers.csv
│   └── orders.tsv
├── .datom/
│   ├── project.yaml              # Project configuration
│   ├── routing.json              # Methods configuration (repo-wide)
│   ├── manifest.json             # Repository catalog
│   ├── migration_history.json    # Audit trail of location changes
│   └── state/                    # Operation integrity tracking
│       └── {operation_id}.json
└── .gitignore                     # Ignores input_files/* and data formats
```

**Note:** Contents of `input_files/` are gitignored. Only metadata tracked in git; actual data files stay local and sync to S3 as parquet.

**Cloud Storage (S3)**:
```
bucket/
└── {optional_prefix}/
    └── datom/
        ├── .access/                   # Reserved for datomaccess package (do not read/write)
        ├── .metadata/
        │   ├── routing.json           # Methods (synced from git)
        │   ├── manifest.json          # Repository catalog
        │   └── migration_history.json # Audit trail
        ├── .redirect.json             # Only present post-migration in OLD bucket
        └── {table_name}/
            ├── {data_sha}.parquet     # Data files (content-addressed)
            └── .metadata/
                ├── metadata.json      # Current metadata
                ├── {metadata_sha}.json # Versioned metadata snapshots
                └── version_history.json
```

### Location Resolution

Data location is implicit, not stored in metadata. Resolution follows redirect chain:

```
datom_read(conn, "customers", ...)
        │
        ▼
1. Check conn.bucket/prefix/datom/.redirect.json
2. If found → follow to new location, repeat step 1
3. If not found → this is current location
4. Read from resolved location
```

**Post-migration credential requirement**: If old code points to bucket-A but data migrated to bucket-B, user needs credentials for both buckets (bucket-A for redirect, bucket-B for data). Updating code to point directly to bucket-B avoids dual-credential need.

---

## Metadata Schema

### metadata.json

Current state only — no history stored here:

```json
{
  "data_sha": "abc123...",
  "table_type": "derived",
  "parents": [
    {"source": "med-mm-001", "table": "os_data", "version": "a3f8c1..."},
    {"source": "med-mm-002", "table": "os_data", "version": "b9e2d4..."}
  ],
  "size_bytes": 1048576,
  "nrow": 10000,
  "ncol": 15,
  "colnames": ["id", "name", "value"],
  "created_at": "2024-01-15T10:30:00Z",
  "datom_version": "0.1.0",
  "custom": {
    "description": "Response table",
    "tags": ["Efficacy", "SDTM"]
  }
}
```

| Field | Description |
|-------|-------------|
| `data_sha` | SHA of the parquet file stored in S3 |
| `table_type` | `"imported"` (from source file via `datom_sync`) or `"derived"` (from data frame via `datom_write`) |
| `parents` | Lineage. For `"imported"` tables: always `null`. For `"derived"` tables: list of `{source, table, version}` entries, or `null` if lineage not recorded. Each entry: `source` = project_name of the parent data space, `table` = table name, `version` = metadata_sha at derivation time. Required by datomaccess for access gate computation; also used by dp_dev for dependency tracking. |
| `size_bytes` | Size of the parquet file in bytes |
| `nrow`, `ncol` | Table dimensions |
| `colnames` | Column names array |
| `created_at` | ISO timestamp of creation |
| `datom_version` | Version of datom that created this |
| `custom` | User-defined metadata (description, tags, etc.) |

### version_history.json

Index mapping versions to data with full audit info. **metadata_sha serves as the datom version** — it uniquely identifies the (data, metadata) pair:

```json
[
  {
    "version": "xyz789...",
    "data_sha": "abc123...",
    "original_file_sha": "def456...",
    "timestamp": "2024-01-15T10:30:00Z",
    "author": "jane.doe@company.com",
    "commit_message": "Updated Q4 data"
  }
]
```

| Field | Description |
|-------|-------------|
| `version` | metadata_sha — the datom version identifier |
| `data_sha` | SHA of the parquet file |
| `original_file_sha` | SHA of the source file (CSV, TSV, etc.). **Nullable** — present for imported tables (`datom_sync`); `null` for derived tables (`datom_write`). Enables skip optimization: scan history for matching file SHA to avoid re-importing unchanged source files, even across version rollbacks. |
| `timestamp` | ISO timestamp of creation |
| `author` | Git author (name or email) |
| `commit_message` | Descriptive message for this version |

**Note:** A single data_sha may appear with multiple versions if metadata was updated without data changes.

**Why no git commit SHA?** datom uses git as a versioning and conflict-management mechanism, not as a code repository. The meaningful version identifier is `metadata_sha` (content-addressed, deterministic). Since datom doesn't pair code with data, the git commit SHA adds no reproducibility value — data is either imported from a file or written from an R session, neither of which is captured by the commit. When git context is needed, `timestamp` + `author` or `git log --all -S "<metadata_sha>"` locates the commit directly. Git commit SHA enrichment was considered and designed but deferred — see "Deferred to v2" for the approach if a compelling use case emerges.

### .redirect.json

Left in OLD bucket post-migration:

```json
{
  "redirect_to": "s3://bucket-B/proj/datom/",
  "migrated_at": "2024-06-01T00:00:00Z",
  "credentials": {
    "access_key_env": "DATOM_CLINICAL_DATA_ACCESS_KEY_ID_2",
    "secret_key_env": "DATOM_CLINICAL_DATA_SECRET_ACCESS_KEY_2"
  }
}
```

Enables old code to find data at new location. Credential env var names follow convention with `_2`, `_3`, etc. suffix for redirects.

---

## Store Objects

Store objects bundle storage configuration + credentials, replacing scattered `bucket`/`prefix`/`region` params and env-var conventions.

### `datom_store_s3()` — Component Constructor

```r
datom_store_s3(
  bucket,
  prefix = NULL,
  region = "us-east-1",
  access_key,
  secret_key,
  session_token = NULL,
  validate = TRUE
)
```

Creates a single S3 storage component (used for governance or data). When `validate = TRUE`, runs `HeadBucket` to verify credentials and bucket access. Returns `datom_store_s3` S3 class.

Future backends (`datom_store_local()`, `datom_store_gcs()`) will have their own constructors.

### `datom_store()` — Composite Constructor

```r
datom_store(
  governance,
  data,
  github_pat = NULL,
  remote_url = NULL,
  github_org = NULL,
  validate = TRUE
)
```

Bundles governance + data store components with git config:
- `github_pat` present → `role = "developer"`; absent → `role = "reader"`
- `remote_url`: existing GitHub repo URL (mutually exclusive with `create_repo` in `datom_init_repo()`)
- `github_org`: for org repo creation; NULL → personal repo
- When `validate = TRUE` and `github_pat` provided, validates PAT via `GET /user`

### `.datom_install_store()` — Env Var Bridge (Temporary)

`.datom_install_store(store, project_name)` injects store credentials into env vars (`DATOM_{PROJECT}_ACCESS_KEY_ID`, etc.) so existing S3 code works unchanged. Called inside `datom_init_repo()` / `datom_get_conn()`. **Phase 11 removes this** by wiring `.datom_s3_client()` directly to store credentials.

### `.datom_create_github_repo()` — GitHub Repo Creation

Creates GitHub repos via REST API (`httr2`). Safety: existing+empty → reuse, existing+content → abort before local side effects.

---

## API Reference

### Repository Management (Data Developers)

#### datom_init_repo()

```r
datom_init_repo(
  path = ".",
  project_name,
  store,
  create_repo = FALSE,
  repo_name = project_name,
  max_file_size_gb = 1000,
  git_ignore = c(...),
  .force = FALSE
)
```

One-time setup for data developers:
- `store`: composite `datom_store()` object (replaces `bucket`/`prefix`/`region`/`remote_url`)
- `create_repo = TRUE`: auto-creates GitHub repo via API from `repo_name` (normalized: lowercase, underscores → hyphens). Requires developer store.
- `repo_name`: defaults to `project_name`; allows custom GitHub repo name
- **Validation-first**: all store/repo validation happens before any filesystem or git side effects
- **S3 namespace safety check**: checks `{prefix}/datom/.metadata/manifest.json` on S3 before writing. Pass `.force = TRUE` to override.
- Creates folder structure, initializes git with remote
- Creates `.datom/project.yaml` with two-component storage config (`storage.governance` + `storage.data`)
- Creates `.datom/routing.json` with default methods
- Creates `.datom/manifest.json` with `project_name` at the top level
- Pushes initial commit to git, then uploads routing + manifest to S3

Returns: Invisible TRUE on success. Cleans up on failure.

#### datom_get_conn()

```r
datom_get_conn(
  path = NULL,
  store = NULL,
  project_name = NULL,
  endpoint = NULL
)
```

Flexible connection for both developers and readers:

| Use case | Parameters |
|----------|------------|
| Developer (has repo) | `path = "my_project"` — reads from .datom/project.yaml; optional `store` for credentials |
| Reader (S3 only) | `store` + `project_name` — store provides everything |
| dpbuild / dp_dev | `store` + `project_name` — programmatic setup |
| datomaccess (access points) | `endpoint` — S3 access point URL overriding default endpoint |

`endpoint`: Optional S3 endpoint URL. When `NULL` (default), standard S3 is used. datomaccess sets this to route reads through S3 access points for IAM enforcement. Stored in the returned `datom_conn` object and forwarded to all S3 operations.

- Validates credentials based on `project_name` → `DATOM_{PROJECT_NAME}_*`
- Follows redirect chain to resolve current data location (**Planned — not yet integrated.** The `.datom_s3_resolve_redirect()` function exists but is not wired into connection builders. Integration point may be influenced by datomaccess.)
- Auto-detects developer vs reader based on GITHUB_PAT presence

Returns: Connection object (`datom_conn` S3 class)

#### datom_clone()

```r
datom_clone(path, store)
```

Clones an existing datom repository and returns a ready-to-use connection:
- `store`: composite `datom_store()` with `remote_url` and `github_pat`
- Wraps `git2r::clone()` + `datom_get_conn(path)`
- Validates the clone contains `.datom/project.yaml` (is a datom repo)
- Rejects non-empty target directories

Returns: `datom_conn` object (developer role)

#### datom_pull()

```r
datom_pull(conn)
```

Pulls latest git changes from remote. Recommended at the start of each work session:
- Fetches and merges upstream commits (metadata, manifest, routing — all tracked in git)
- Git is the source of truth — no S3 refresh needed
- Developer role only (readers have no git access)
- Reports commits pulled and current branch

Returns: Invisible list with `commits_pulled` (integer) and `branch` (string)

### Core Operations

#### datom_read() — All Users

```r
datom_read(
  conn,
  name,
  version = NULL,
  context = NULL,
  ...
)
```

Unified read function with routing via routing.json:
- `version`: metadata_sha (datom version) — if NULL, uses current
- `context`: runtime behavior selection (default: "default") (**Planned — not yet implemented.** Currently reads parquet directly; routing dispatch via `context` and `routing.json` will be added when downstream consumers exist.)
- Metadata always from S3 for readers
- Additional parameters in `...` forwarded to routed function

**Resolution:** version → lookup in version_history.json → get data_sha → fetch `{data_sha}.parquet` + `{version}.json`

Returns: Data frame or routed function result

#### datom_write() — Data Developers

```r
datom_write(
  conn,
  data = NULL,
  name = NULL,
  metadata = NULL,
  message = NULL,
  parents = NULL
)
```

Flexible write operations:

| data | name | Behavior |
|------|------|----------|
| provided | provided | Normal write: commit → push → S3 sync |
| NULL | provided | Metadata-only sync for single table (e.g., after editing routing.json) |
| NULL | NULL | Aliases to `datom_sync_routing()` |

For normal writes:
- Change detection via metadata_sha comparison (alphabetically sorted fields)
- Handles: no-op, metadata-only update, or full update with S3 upload
- `parents`: list of `list(source, table, version)` entries recording lineage. `NULL` if lineage not recorded. In practice, supplied by dp_dev which tracks dependency versions automatically (e.g., via targets). `datom_sync()` never passes `parents` — imported tables always have `parents: null`.

Returns: List with deployment details

#### datom_get_parents() — All Users

```r
datom_get_parents(conn, name, version = NULL)
```

Reads the `parents` field from a table's metadata:
- `version`: metadata_sha of a specific version. If `NULL`, reads current metadata.
- Returns `NULL` for imported tables or derived tables with no recorded lineage.
- For versioned reads, fetches the `{version}.json` snapshot from S3.

Required by datomaccess to walk lineage for access gate computation.

Returns: List of parent entries (each with `source`, `table`, `version`), or `NULL`.

#### datom_sync_routing() — Data Developers

```r
datom_sync_routing(conn, .confirm = TRUE)
```

Updates all metadata in S3 to match git after migration or routing changes:
- Interactive confirmation required (set `.confirm = FALSE` for programmatic use)
- Updates routing.json, migration_history.json for all tables
- Used after external migration (aws cli, etc.) and project.yaml update

```
# Warning: This will update routing metadata for all 147 tables.
# Current location: s3://bucket-B/proj/datom/
# Proceed? [y/N]
```

Returns: Summary of updated files

### Batch Operations (Data Developers)

#### datom_sync_manifest()

```r
datom_sync_manifest(conn, path = NULL, pattern = "*")
```

Scans flat `input_files/` directory:
- No subdirectories allowed
- Computes SHA of files in original format
- Checks against manifest (current SHAs) for fast no-op detection
- Only fetches version_history.json on mismatch

Returns: Manifest for review

#### datom_sync()

```r
datom_sync(conn, manifest, continue_on_error = TRUE)
```

Processes new/changed files:
- One commit per table
- Manual conflict resolution on concurrent writes

Returns: Updated manifest with results

### Query Operations (Data Readers)

#### datom_list()

```r
datom_list(conn, pattern = NULL, include_versions = FALSE, short_hash = TRUE)
```

Lists available tables from S3 manifest.
- `short_hash`: If TRUE (default), truncates SHA columns to 8 characters for readability.

Returns: Data frame with table info

#### datom_history()

```r
datom_history(conn, name, n = 10, short_hash = TRUE)
```

Shows version history for a table including author and commit message.
- `short_hash`: If TRUE (default), truncates SHA columns to 8 characters for readability.

Returns: Data frame with version details

### Status & Validation

#### datom_status() — All Users

```r
datom_status(conn)
```

Displays connection info, table count from S3 manifest, and (for developers) uncommitted git changes and input file sync state.

- **Connection summary**: project name, bucket, prefix, region, role
- **Table count**: read from S3 manifest
- **Git status** (developer only): uncommitted changes, current branch
- **Input files** (developer only): new, changed, and unchanged file counts vs manifest

Returns: Invisibly, a list with `connection`, `tables`, and optionally `git` and `input_files` status details.

#### datom_validate() — Data Developers

```r
datom_validate(conn, fix = FALSE)
```

Checks that git metadata matches S3 storage for all tables and repo-level files. Reports mismatches as a structured result.

- **Repo-level checks**: routing.json, manifest.json, migration_history.json exist on S3
- **Per-table checks**: metadata.json, version_history.json, and `{data_sha}.parquet` exist on S3 for each table tracked in git
- `fix = TRUE`: attempts to repair inconsistencies by calling `datom_sync_routing(conn, .confirm = FALSE)`

Returns: List with `valid` (logical), `repo_files` (data frame), `tables` (data frame), `fixed` (logical).

#### datom_migrate() — Data Developers (Future)

```r
datom_migrate(conn_from, conn_to, tables, update_redirects)
```

**Not yet implemented.** Managed migration — see "Deferred to v2."

### Example Data

#### datom_example_data()

```r
datom_example_data(domain = c("dm", "ex"), cutoff_date = NULL)
```

Loads bundled clinical trial example data (DM and EX domains) for use in examples and vignettes. The data simulates a Phase II study (STUDY-001) with 48 subjects.

- `domain`: `"dm"` (demographics) or `"ex"` (exposure)
- `cutoff_date`: Optional `"YYYY-MM-DD"` to filter subjects enrolled on or before this date, simulating a point-in-time EDC extract

Returns: Data frame.

#### datom_example_cutoffs()

```r
datom_example_cutoffs()
```

Returns a named character vector of monthly cutoff dates for STUDY-001, useful for simulating data evolution in examples.

Returns: Named character vector (`month_1` through `month_6`).

### Repository Validation

#### is_valid_datom_repo()

```r
is_valid_datom_repo(
  path,
  checks = c("all", "git", "datom", "renv"),
  verbose = FALSE
)
```

Validates datom repository structure. Used internally by datom functions and externally by dpbuild.

| Check | Validates |
|-------|-----------|
| `git` | Git repository initialized |
| `datom` | `.datom/project.yaml`, `.datom/routing.json`, `.datom/manifest.json` exist |
| `renv` | `renv/` directory exists |

Returns: TRUE or FALSE

#### datom_repository_check()

```r
datom_repository_check(path)
```

Internal function returning detailed check results:

```r
list(
  git_initialized = TRUE/FALSE,
  datom_initialized = TRUE/FALSE,
  datom_routing = TRUE/FALSE,
  datom_manifest = TRUE/FALSE,
  renv_initialized = TRUE/FALSE
)
```

**dpbuild integration:** `dp_repository_check()` calls `datom_repository_check()` internally — a valid dp repository is a superset of a valid datom repository.

---

## User Workflows

### Data Developer Workflow

```r
# Create store with credentials (e.g., from keyring or .Renviron)
store <- datom_store(
  governance = datom_store_s3(
    bucket = "org-governance",
    prefix = "project-alpha/",
    access_key = keyring::key_get("datom_gov_access_key"),
    secret_key = keyring::key_get("datom_gov_secret_key")
  ),
  data = datom_store_s3(
    bucket = "shared-bucket",
    prefix = "project-alpha/",
    access_key = keyring::key_get("datom_data_access_key"),
    secret_key = keyring::key_get("datom_data_secret_key")
  ),
  github_pat = keyring::key_get("github_pat")
)

# --- Lead developer: one-time project setup ---
datom_init_repo(
  path = "my_project",
  project_name = "CLINICAL_DATA",
  store = store,
  create_repo = TRUE  # auto-creates GitHub repo
)

# --- All other developers: clone existing repo ---
conn <- datom_clone("my_project", store)

# --- Daily workflow ---
conn <- datom_get_conn("my_project")
datom_pull(conn)  # Always pull at session start

# Place source files in input_files/ (must be flat, no subdirectories)
manifest <- datom_sync_manifest(conn)
results <- datom_sync(conn, manifest)
```

### Data Reader Workflow

```r
# Reader store — no github_pat
store <- datom_store(
  governance = datom_store_s3(
    bucket = "org-governance",
    prefix = "project-alpha/",
    access_key = Sys.getenv("GOV_ACCESS_KEY"),
    secret_key = Sys.getenv("GOV_SECRET_KEY")
  ),
  data = datom_store_s3(
    bucket = "shared-bucket",
    prefix = "project-alpha/",
    access_key = Sys.getenv("DATA_ACCESS_KEY"),
    secret_key = Sys.getenv("DATA_SECRET_KEY")
  )
)

# Connect (reader role — no git)
conn <- datom_get_conn(
  store = store,
  project_name = "CLINICAL_DATA"
)

# List available tables
tables <- datom_list(conn)

# Read data (version = metadata_sha)
data <- datom_read(conn, "customers", version = "xyz789")
```

### Migration Workflow

```r
# 1. Copy data externally (aws cli, console, etc.)
#    aws s3 sync s3://bucket-A/proj/ s3://bucket-B/proj/

# 2. Place .redirect.json in old bucket with credentials for new bucket
#    {
#      "redirect_to": "s3://bucket-B/proj/datom/",
#      "migrated_at": "...",
#      "credentials": {
#        "access_key_env": "DATOM_CLINICAL_DATA_ACCESS_KEY_ID_2",
#        "secret_key_env": "DATOM_CLINICAL_DATA_SECRET_ACCESS_KEY_2"
#      }
#    }

# 3. Update project.yaml with new bucket
conn <- datom_get_conn("my_project")

# 4. Sync routing to new location (interactive confirmation)
datom_sync_routing(conn)
```

### Data Product Integration

```r
# R data product closure
dp$input$customers <- function(context = NULL, ...) {
  datom_read(
    "customers",
    version = "xyz789",
    context = context,
    ...
  )
}
```

```python
# Python equivalent
class DataProduct:
    def customers(self, context=None, **kwargs):
        return datom_read(
            "customers",
            version="xyz789",
            context=context,
            **kwargs
        )
```

---

## Data Flow

### Write Operation (Data Developers)

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Compute data_sha (parquet) and original_file_sha (source)   │
│ 2. Sort metadata fields alphabetically, compute metadata_sha   │
│ 3. Check if matches HEAD → no-op if yes                        │
│ 4. Check version_history for existing SHAs (deduplication)     │
│ 5. Determine update type and execute                           │
│ 6. Commit and push to git (author from git config)             │
│ 7. Upload to S3 (if new data)                                  │
│ 8. Sync metadata to S3 for data reader access                  │
│ 9. Update state tracking for operation integrity               │
└─────────────────────────────────────────────────────────────────┘
```

### Read Operation (All Users)

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Follow redirect chain to resolve current location           │
│ 2. Read version_history.json from S3                           │
│ 3. Lookup version (metadata_sha) → get data_sha                │
│ 4. Get routing method from routing.json                        │
│ 5. Download {data_sha}.parquet and {version}.json from S3      │
│ 6. Apply context-specific processing via routing               │
└─────────────────────────────────────────────────────────────────┘
```

### Write Ordering & Resilience

**Strict ordering: local → git → S3.** Every write path follows this sequence:

1. Write metadata files to local disk
2. Git commit + push (must succeed before proceeding)
3. Upload data and metadata to S3

**Git gates S3.** If git commit or push fails, S3 writes are aborted entirely. This ensures S3 never contains data that git doesn't know about. The user is instructed to fix the git issue and re-run.

**Idempotent re-runs.** If a write fails partway through:
- `.datom_has_changes()` checks S3 (the final destination). If S3 is stale, changes are re-detected.
- `.datom_git_commit()` returns HEAD SHA when files are already committed (no-op on re-run).
- S3 uploads are content-addressed (parquet) or unconditional overwrites (metadata JSON), so re-uploading is safe.
- `datom_sync_routing()` is the escape hatch: a full local → S3 push that's always safe to run.

**Key functions and their ordering:**

| Function | Order | Git failure behavior |
|----------|-------|---------------------|
| `datom_write()` | local → git → S3 | Hard error, S3 untouched |
| `.datom_sync_metadata()` | local → git → S3 | Hard error, S3 untouched |
| `datom_sync()` (per-table) | via `datom_write()` | Per above |
| `datom_sync()` (manifest) | local → git → S3 | Warning, S3 skipped |
| `datom_sync_routing()` | local → S3 only | N/A (recovery tool) |
| `datom_init_repo()` | local → git only | Cleanup on failure |

### Change Detection

- `metadata_sha` computed from alphabetically sorted fields
- Single comparison detects any change
- Enables efficient updates and deduplication
- `original_file_sha` tracked in version_history.json (not metadata.json) — does not inflate version count when identical data is re-imported from a different source file path
- Change detection reads from **S3** (the final destination), so incomplete round-trips are re-detected on re-run

### Conflict Resolution

**Pull-before-push discipline**: Every write path pulls from remote before pushing. `.datom_git_push()` calls `.datom_git_pull()` as its first step (fetch + merge). This is the primary defense against diverged histories in multi-developer scenarios.

**Stale state detection**: `datom_sync()` calls `.datom_check_git_current()` at entry, which compares local HEAD vs remote HEAD via `git2r::ahead_behind()`. If behind, sync aborts with an actionable error directing the user to run `datom_pull()`. This catches stale state before any local writes occur.

**Conflict handling**:
- Auto-pull before push resolves most non-fast-forward situations silently
- Merge conflicts (rare — requires two developers syncing the same table simultaneously) require manual resolution: `git status` → edit → `git add` → `git commit` → re-run sync
- No automatic merge of concurrent updates

---

## Project Configuration

### Credential Naming Convention (Internal)

Credentials are now provided via `datom_store_s3()` objects. Internally, `.datom_install_store()` maps them to env vars for backward compatibility:

**Convention:** `DATOM_{PROJECT_NAME}_ACCESS_KEY_ID` / `DATOM_{PROJECT_NAME}_SECRET_ACCESS_KEY`

This bridge is temporary — Phase 11 removes it by wiring `.datom_s3_client()` directly to store credentials.

- Redirects append `_2`, `_3`, etc. for chained migrations

### .datom/project.yaml

```yaml
project_name: clinical_data
project_description: Shared data repository for analytics
created_at: 2024-01-15
datom_version: 0.1.0

# Two-component storage configuration
storage:
  governance:
    type: s3
    bucket: org-governance
    prefix: clinical-data/
    region: us-east-1
  data:
    type: s3
    bucket: study-bucket
    prefix: project-alpha/
    region: us-east-1

# Git remote
git:
  remote_url: https://github.com/org/clinical-data.git

# Sync configuration
sync:
  continue_on_error: true
  parallel_uploads: 4

# Computational environment
renv: false  # renv integration deferred — see Deferred to v2
```

**Secrets are never persisted.** The `type` field enables future backend dispatch. The two-component structure (governance + data) allows routing files and data files to target different buckets/prefixes.

### .datom/routing.json

```json
{
  "methods": {
    "r": {
      "default": "datom::datom_read"
    },
    "python": {
      "default": "datom.read"
    }
  }
}
```

### .datom/manifest.json

```json
{
  "project_name": "STUDY_001",
  "updated_at": "2024-01-15T10:30:00Z",
  "tables": {
    "customers": {
      "current_version": "xyz789...",
      "current_data_sha": "abc123...",
      "original_file_sha": "def456...",
      "original_format": "csv",
      "last_updated": "2024-01-15T10:30:00Z",
      "size_bytes": 1048576,
      "version_count": 15
    }
  },
  "summary": {
    "total_tables": 2,
    "total_size_bytes": 3145728,
    "total_versions": 23
  }
}
```

**Design rationale**: The "current" fields per table enable sync optimization. When `datom_sync_manifest()` runs, it compares local file SHAs against manifest. Only on mismatch does it fetch the full `version_history.json`. For repos with 100-300 tables, this avoids hundreds of S3 GETs on unchanged re-runs.

### .datom/migration_history.json

```json
[
  {
    "from": "s3://bucket-A/proj/datom/",
    "to": "s3://bucket-B/proj/datom/",
    "migrated_at": "2024-06-01T00:00:00Z",
    "reason": "Bucket consolidation"
  }
]
```

Documentary only — does not drive runtime behavior.

---

## Implementation Details

### Environment Validation

- Check required environment variables on connection
- GITHUB_PAT presence determines developer vs reader role
- Use standard AWS and GitHub variable names
- No custom configuration functions

### Project Structure Validation

- Verify `.datom/`, `.git/`, and `manifest.json` exist
- Validate `input_files/` is flat (no subdirectories)
- Called internally by all operations

### Routing Implementation

```r
datom_read <- function(name, version = NULL, context = NULL, conn = NULL, ...) {

  if (is.null(context)) context <- "default"

  # Location already resolved via redirect chain in conn
  
  # Read routing.json from S3 metadata
  routing_info <- .get_routing_from_s3(conn)

  # Get R method for the specified context
  r_methods <- routing_info$methods$r
  if (!context %in% names(r_methods)) {
    stop("Context '", context, "' not found for R")
  }

  func_name <- r_methods[[context]]
  func <- eval(parse(text = func_name))

  # Call with R conventions, forwarding extra parameters
  func(conn, name, version, ...)
}
```

---

## Performance & Security

### Performance Optimizations

**Implemented:**
- Use HEAD requests for existence checks
- Hash original files to avoid re-reading
- Skip unchanged files via `original_file_sha` comparison
- Manifest current SHAs avoid version_history.json fetches for unchanged tables

**Planned — not yet implemented:**
- Enforce `max_file_size_gb` from project.yaml (config exists, enforcement not wired)
- Parallelize multi-file operations (`parallel_uploads` in project.yaml, not yet used)

### Security Considerations

- Never store credentials in files
- Use standard environment variables exclusively
- S3 metadata is read-only for data readers
- Validate all paths for traversal attacks
- Respect configured file size limits (**Planned** — `max_file_size_gb` stored in project.yaml but not enforced at runtime)

### Connection Architecture

- `datom_conn` S3 class wraps project_name, bucket, prefix, region, s3_client, path, role, endpoint
- Two modes: **developer** (has local repo path + git) and **reader** (S3 only, no local repo)
- Role derived from composite store: `github_pat` present → developer; absent → reader
- `datom_get_conn(path = ...)` reads two-component `.datom/project.yaml` (developer path)
- `datom_get_conn(store = ..., project_name = ...)` builds connection from store (reader path)
- Credential env var names derived from `project_name` via `.datom_install_store()` bridge (temporary — Phase 11 removes)
- `endpoint`: optional S3 endpoint override stored in conn; when set, all `.datom_s3_*` calls route through it. Used by datomaccess to enforce S3 access point routing.
- `datom_init_repo()` sets local git config (`user.name`, `user.email`) from global config or fallback — `git2r::default_signature()` requires local config on freshly init'd repos

### Dependency Strategy

- `paws.storage` (Imports): S3 operations (HeadBucket validation, S3 reads/writes) — lightweight, avoids pulling full `paws`. Note: `sts` is NOT in `paws.storage` (it's in `paws.security.identity`); validation uses HeadBucket only.
- `httr2` (Imports): GitHub REST API (repo creation, PAT validation)
- `git2r` (Suggests): Git operations — only needed by data developers, checked at runtime via `.datom_check_git2r()`
- Data readers never need git2r installed

---

## Supported File Formats

Via `rio::import`: CSV, TSV, Excel, SAS, Parquet, SPSS, Stata, etc.

All stored as parquet regardless of input format.

**Optimized for**: Clinical/scientific datasets that are wide (many columns) but not excessively large (typically MB to low GB range), enabling quick fetching and efficient versioning.

---

## Validation & Testing

### Validation Requirements

**Initialization (Data Developers)**:
- Environment variables: AWS credentials and GITHUB_PAT
- GitHub PAT permissions and remote access
- S3 bucket existence and write permissions
- Git user.name and user.email configured
- Validate prefix doesn't conflict with existing data

**Connection**:
- Data developers: Validates git + S3 access (GITHUB_PAT present)
- Data readers: Validates S3 read access only
- Auto-detects user type based on GITHUB_PAT presence
- Follows redirect chain to resolve current location

**Operations**:
- Project structure check before all operations
- Input files directory must be flat (no subdirectories)
- File format support via rio::import
- Valid datom names (filesystem safe)
- File size check against configured limit
- Metadata sync verification after deployment

### Testing Coverage

- **Unit**: SHA computation (sorting optional, OFF by default for data; alphabetical for metadata), routing, metadata operations, redirect following
- **Integration**: Full workflow, S3 metadata access, sync verification, migration scenarios
- **Edge cases**: Network failures, corrupt files, missing metadata, concurrent writes, chained redirects

---

## Extensibility

### Future Extensions via Routing

| Extension | Package | Description |
|-----------|---------|-------------|
| Access Control | datom_auth | Role-based table access, row/column filtering |
| Performance | datom_cache | Local caching layer |
| Sampling | datom_utils | Read subsets of large tables |
| Multi-language | datom (Python) | Python implementation |

### Storage Backend Extensibility

- **Current**: AWS S3
- **Planned**: Google Cloud Storage, Azure Blob Storage
- Architecture supports any object storage with minimal changes

### Query Interface Extensibility

The routing layer supports future queryable backends (Iceberg, S3 Tables, DuckDB):

```json
{
  "methods": {
    "r": {
      "default": "datom::datom_read",
      "query": "datom_query::read_filtered"
    }
  }
}
```

```r
# Future: query with filters instead of fetching full table
datom_read(conn, "customers", 
          version = "xyz789", 
          context = "query", 
          filter = "age > 30",
          columns = c("id", "name"),
          limit = 100)
```

All `...` params forwarded to routed function — enables API calls, SQL queries, or filtered reads without changing the core interface.

### Deferred to v2

- Table-level routing overrides (repo-level only for v1)
- Managed migration via `datom_migrate()` (manual external copy for v1)
- Queryable backends (Iceberg, S3 Tables)
- **Integrity state tracking** (`.datom/state/` directory with per-operation JSON): The current write-ordering discipline (local → git → S3 with idempotent re-runs) provides structural resilience without explicit state files. State tracking could add value for debugging/audit at scale. Reference schema if revisited:

  ```json
  {
    "operation_id": "op_12345",
    "table": "customers",
    "data_sha_at_commit": "abc123",
    "data_sha_before_s3": "abc123",
    "data_sha_after_s3": "abc123",
    "integrity_hash": "sha256(data + metadata)",
    "stage": "completed",
    "timestamp": "2024-01-15T10:30:00Z"
  }
  ```
- **Git commit SHA in version_history.json**: Denormalizing the git commit SHA into each version_history entry was designed but deferred. datom uses git for versioning mechanics, not code pairing — the `metadata_sha` is the meaningful version identifier and `git log -S` can locate commits when needed. If a use case emerges (e.g., regulatory requirement for explicit commit linkage), two enrichment approaches were evaluated:

  *Approach A — Local + S3 enrichment (preferred if implemented):*
  1. Write version_history entry without `commit` → git commit → get SHA
  2. Enrich local file: inject `commit` SHA into the new entry
  3. Push enriched version to S3
  4. Self-healing: previous entry's commit baked into git on next write
  5. Requires `datom_pull()` to auto-commit dirty enrichment files before pulling (avoids merge conflicts in multi-developer scenarios)

  *Approach B — S3-only enrichment (simpler but fragile):*
  1. Git always has `commit: null`; only S3 gets enriched after push
  2. Simpler (no dirty working tree), but S3 deletion loses all commit SHAs with no git-based recovery

  Approach A is recommended if this feature is revisited — it preserves recoverability from git alone.

- **Session metadata caching**: Could reduce S3 GETs for repeated reads within a session. Requires careful invalidation design — deferred until the trade-offs are well understood.
- **renv integration** in `datom_init_repo()`: Currently deferred; `renv` field in project.yaml defaults to `false`.

### Multi-Developer Collaboration (Implemented)

Team workflows are fully supported:

- **S3 namespace safety check** in `datom_init_repo()`: Verifies target S3 namespace is unoccupied before writing. `.force = TRUE` overrides for intentional takeover.
- **`project_name` in manifest.json**: Enables namespace collision detection. `datom_validate()` cross-checks manifest's `project_name` against `conn$project_name`.
- **`datom_pull()`**: Git pull (fetch + merge). Git is the source of truth for all metadata.
- **`datom_clone()`**: Wraps `git2r::clone()` + `datom_get_conn()` — the recommended way for teammates to join a repo.
- **Pull-before-push discipline**: `.datom_git_push()` auto-pulls before pushing. `.datom_check_git_current()` detects stale state at `datom_sync()` entry.
- **Vignettes**: `vignette("team-collaboration")` for workflows, `vignette("credentials")` for credential setup.

---

## Key Differences from Current dpbuild/pins Approach

| Aspect | Current (pins) | datom |
|--------|---------------|------|
| Metadata source | Storage-native | Git-first |
| Storage format | RDS (R lists) | Parquet (language-agnostic) |
| Versioning | pins versioning | Content-addressable (SHA) |
| Reader access | Needs pins | S3-only access |
| Cross-language | R only | R + Python planned |
| Configuration | Package-specific | Standard env vars |
| Read interface | Package-specific | Unified with routing |
| Location | Stored in metadata | Implicit + redirect chain |
| Migration | Manual | Redirect-based continuity |

---

## Summary

datom provides robust data versioning optimized for clinical data science workflows where reproducibility is paramount. Designed for analytical environments with many evolving tables (50-100+), datom makes version tracking seamless for datasets that are large in breadth but manageable in size.

**Key architectural decisions**:

1. Single read function (`datom_read()`) with routing for all access patterns
2. **datom version = metadata_sha**: uniquely identifies (data, metadata) pair
3. **Credential naming convention**: `DATOM_{PROJECT_NAME}_*` auto-generated, enabling multi-repo composition
4. Multi-language support via routing layer (R first, Python planned)
5. Cloud storage agnostic design (S3 first, extensible)
6. Optimized for clinical/scientific workflows with many tables
7. One repository per project with optional bucket prefix support
8. Deterministic SHA computation via alphabetical field sorting
9. Manual conflict resolution for rare concurrent write scenarios
10. Implicit location with redirect chain for seamless migration
11. project.yaml authoritative; routing.json and S3 metadata derived

This architecture keeps datom focused on core versioning while providing clear extension points for enterprise features. As part of the larger data product ecosystem (with dpbuild, dpdeploy, and dpi), datom serves as the foundational layer for reproducible analytical workflows.
