# tbit Package Specification

## Overview

Picture an analytical workflow built to derive specific insights from evolving data served as snapshots. Your dataset might consist of 50 or 100 different tables from which you create additional derived tables as your analysis requires. As these tables evolve and your transformation logic changes, ensuring that outputs remain trackable and reproducible for all collaborators becomes increasingly difficult. This scenario is familiar in clinical data science, where agility is key and reproducibility is paramount.

tbit serves as a foundational building block for addressing this use case, leveraging only tools readily available to data scientists: git, GitHub, and cloud object storage. While initially supporting AWS S3, tbit is designed to be cloud storage agnostic. Similarly, though we begin with an R implementation, the architecture supports future Python and other language implementations.

The package enables version-controlled data management by abstracting tables as code in git while storing actual data in cloud storage. For collections of tabular datasets that evolve over time, tbit enables:

- Setting up cloud-based repositories
- Frequently syncing data with automatic versioning
- Tracking complete data lineage
- Accessing any historical version for reproducibility

The primary utility motivating tbit is building version-tracked data products. Companion packages (dpbuild, dpdeploy, and dpi) build upon tbit to collectively enable creating, managing, and accessing reproducible data products in clinical and scientific workflows.

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

tbit distinguishes between **versioned content** and **tracked configuration**:

| Category | Files | Versioned? | Creates version_history entry? |
|----------|-------|------------|-------------------------------|
| **Data** | `{data_sha}.parquet` | Yes | Yes |
| **Metadata** | `metadata.json`, `{metadata_sha}.json` | Yes | Yes |
| **Configuration** | `routing.json`, `project.yaml`, `manifest.json` | No | No |

### tbit Version = metadata_sha

The tbit version is the **metadata_sha**, computed from alphabetically sorted metadata fields (which include `data_sha`). This uniquely identifies a (data, metadata) pair.

```
metadata fields (sorted) → SHA-256 → metadata_sha = tbit version
       ↑
   includes data_sha
```

**Routing is explicitly excluded** from version computation. Changing routing does not change any tbit version.

### Git's Role

Git serves two distinct purposes:

| Purpose | Applies to | Git commits? | Affects tbit version? |
|---------|------------|--------------|----------------------|
| **Version control** | Data + metadata | Yes | Yes |
| **Conflict resolution** | Routing + config | Yes | No |

All files live in one repo for simplicity, but:
- Data/metadata commits → create version_history.json entries
- Routing/config commits → tracked in git only (audit trail, multi-dev coordination)

### Example: Routing Change

```
Day 1:  tbit_write() → version "xyz789" created
        git commit includes: metadata.json, version_history.json
        
Day 2:  Edit routing.json (add "cached" context)
        git commit includes: routing.json only
        
Result: tbit version unchanged ("xyz789")
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
| **Data products** | Analytical applications built on versioned tbits (via dpbuild, dpdeploy, dpi) | AWS credentials only |

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
├── .tbit/
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
    └── tbit/
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
tbit_read(conn, "customers", ...)
        │
        ▼
1. Check conn.bucket/prefix/tbit/.redirect.json
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
  "original_file_sha": "def456...",
  "size_bytes": 1048576,
  "nrow": 10000,
  "ncol": 15,
  "colnames": ["id", "name", "value"],
  "created_at": "2024-01-15T10:30:00Z",
  "tbit_version": "0.1.0",
  "custom": {
    "description": "Response table",
    "tags": ["Efficacy", "SDTM"]
  }
}
```

| Field | Description |
|-------|-------------|
| `data_sha` | SHA of the parquet file stored in S3 |
| `original_file_sha` | SHA of the source file (CSV, TSV, etc.) for deduplication |
| `size_bytes` | Size of the parquet file |
| `nrow`, `ncol` | Table dimensions |
| `colnames` | Column names array |
| `created_at` | ISO timestamp of creation |
| `tbit_version` | Version of tbit that created this |
| `custom` | User-defined metadata (description, tags, etc.) |

### version_history.json

Index mapping versions to data with full audit info. **metadata_sha serves as the tbit version** — it uniquely identifies the (data, metadata) pair:

```json
[
  {
    "version": "xyz789...",
    "data_sha": "abc123...",
    "original_file_sha": "qrs456...",
    "timestamp": "2024-01-15T10:30:00Z",
    "author": "jane.doe@company.com",
    "commit_message": "Updated Q4 data",
    "commit": "def456..."
  }
]
```

| Field | Description |
|-------|-------------|
| `version` | metadata_sha — the tbit version identifier |
| `data_sha` | SHA of the parquet file |
| `original_file_sha` | SHA of the source file |
| `commit` | Git commit SHA (for audit purposes) |

**Note:** A single data_sha may appear with multiple versions if metadata was updated without data changes.

### .redirect.json

Left in OLD bucket post-migration:

```json
{
  "redirect_to": "s3://bucket-B/proj/tbit/",
  "migrated_at": "2024-06-01T00:00:00Z",
  "credentials": {
    "access_key_env": "TBIT_CLINICAL_DATA_ACCESS_KEY_ID_2",
    "secret_key_env": "TBIT_CLINICAL_DATA_SECRET_ACCESS_KEY_2"
  }
}
```

Enables old code to find data at new location. Credential env var names follow convention with `_2`, `_3`, etc. suffix for redirects.

---

## API Reference

### Repository Management (Data Developers)

#### tbit_init_repo()

```r
tbit_init_repo(
  path = ".",
  project_name,
  remote_url,
  bucket,
  prefix = NULL,
  region = NULL,
  max_file_size_gb = 1000,
  git_ignore = c(
    ".Rprofile", ".Renviron", ".Rhistory",
    ".Rapp.history", ".Rproj.user/",
    ".DS_Store", "*.csv", "*.tsv",
    "*.rds", "*.txt", "*.parquet",
    "*.sas7bdat", ".RData", ".RDataTmp",
    "*.html", "*.png", "*.pdf",
    ".vscode/", "rsconnect/"
  )
)
```

One-time setup for data developers:
- `project_name`: used to auto-generate credential env var names (`TBIT_{PROJECT_NAME}_*`)
- Validates environment variables (auto-generated credential names, GITHUB_PAT)
- Creates folder structure, initializes git with remote, sets up renv
- Creates `.tbit/project.yaml` with auto-generated credential config
- Creates `.tbit/routing.json` with default methods
- Creates `.gitignore` with specified patterns (covers `input_files/` contents)
- Optional prefix for bucket organization
- Configurable max file size limit (default 1TB)

Returns: Success status

#### tbit_get_conn()

```r
tbit_get_conn(
  path = NULL,
  bucket = NULL,
  prefix = NULL,
  project_name = NULL
)
```

Flexible connection for both developers and readers:

| Use case | Parameters |
|----------|------------|
| Developer (has repo) | `path = "my_project"` — reads from .tbit/project.yaml |
| Reader (S3 only) | `bucket`, `prefix`, `project_name` — direct connection |
| dpbuild (derived tbits) | `bucket`, `prefix`, `project_name` — programmatic setup |

- Validates credentials based on `project_name` → `TBIT_{PROJECT_NAME}_*`
- Follows redirect chain to resolve current data location
- Auto-detects developer vs reader based on GITHUB_PAT presence

Returns: Connection object (`tbit_conn` S3 class)

**Implementation note**: Internal S3 utility functions (Phase 2) initially accept a
lightweight list (`list(bucket, s3_client)`). Phase 4 introduces the full `tbit_conn`
S3 class and refactors these functions to accept it. This avoids a circular dependency
between S3 ops and connection management during development.

### Core Operations

#### tbit_read() — All Users

```r
tbit_read(
  conn,
  name,
  version = NULL,
  context = NULL,
  ...
)
```

Unified read function with routing via routing.json:
- `version`: metadata_sha (tbit version) — if NULL, uses current
- `context`: runtime behavior selection (default: "default")
- Metadata always from S3 for readers
- Additional parameters in `...` forwarded to routed function

**Resolution:** version → lookup in version_history.json → get data_sha → fetch `{data_sha}.parquet` + `{version}.json`

Returns: Data frame or routed function result

#### tbit_write() — Data Developers

```r
tbit_write(
  conn,
  data = NULL,
  name = NULL,
  metadata = NULL,
  message = NULL
)
```

Flexible write operations:

| data | name | Behavior |
|------|------|----------|
| provided | provided | Normal write: commit → push → S3 sync |
| NULL | provided | Metadata-only sync for single table (e.g., after editing routing.json) |
| NULL | NULL | Aliases to `tbit_sync_routing()` |

For normal writes:
- Change detection via metadata_sha comparison (alphabetically sorted fields)
- Handles: no-op, metadata-only update, or full update with S3 upload

Returns: List with deployment details

#### tbit_sync_routing() — Data Developers

```r
tbit_sync_routing(conn)
```

Updates all metadata in S3 to match git after migration or routing changes:
- Interactive confirmation required
- Updates routing.json, migration_history.json for all tables
- Used after external migration (aws cli, etc.) and project.yaml update

```
# Warning: This will update routing metadata for all 147 tables.
# Current location: s3://bucket-B/proj/tbit/
# Proceed? [y/N]
```

Returns: Summary of updated files

### Batch Operations (Data Developers)

#### tbit_sync_manifest()

```r
tbit_sync_manifest(conn, path = NULL, pattern = "*")
```

Scans flat `input_files/` directory:
- No subdirectories allowed
- Computes SHA of files in original format
- Checks against manifest (current SHAs) for fast no-op detection
- Only fetches version_history.json on mismatch

Returns: Manifest for review

#### tbit_sync()

```r
tbit_sync(conn, manifest, continue_on_error = TRUE)
```

Processes new/changed files:
- One commit per table
- Manual conflict resolution on concurrent writes

Returns: Updated manifest with results

### Query Operations (Data Readers)

#### tbit_list()

```r
tbit_list(conn, pattern = NULL, include_versions = FALSE)
```

Lists available tables from S3 manifest.

Returns: Data frame with table info

#### tbit_history()

```r
tbit_history(conn, name, n = 10)
```

Shows version history for a table including author and commit message.

Returns: Data frame with version details

### Utility Functions

| Function | Users | Description |
|----------|-------|-------------|
| `tbit_status()` | Both | Shows uncommitted changes and sync state |
| `tbit_validate(conn, fix = FALSE)` | Developers | Checks git-storage consistency |
| `tbit_migrate(conn_from, conn_to, tables, update_redirects)` | Developers | Future: managed migration |

### Repository Validation

#### is_valid_tbit_repo()

```r
is_valid_tbit_repo(
  path,
  checks = c("all", "git", "tbit", "renv"),
  verbose = FALSE
)
```

Validates tbit repository structure. Used internally by tbit functions and externally by dpbuild.

| Check | Validates |
|-------|-----------|
| `git` | Git repository initialized |
| `tbit` | `.tbit/project.yaml`, `.tbit/routing.json`, `.tbit/manifest.json` exist |
| `renv` | `renv/` directory exists |

Returns: TRUE or FALSE

#### tbit_repository_check()

```r
tbit_repository_check(path)
```

Internal function returning detailed check results:

```r
list(
  git_initialized = TRUE/FALSE,
  tbit_initialized = TRUE/FALSE,
  tbit_routing = TRUE/FALSE,
  tbit_manifest = TRUE/FALSE,
  renv_initialized = TRUE/FALSE
)
```

**dpbuild integration:** `dp_repository_check()` calls `tbit_repository_check()` internally — a valid dp repository is a superset of a valid tbit repository.

---

## User Workflows

### Data Developer Workflow

```r
# Set environment variables (names auto-generated from project_name)
Sys.setenv(
  TBIT_CLINICAL_DATA_ACCESS_KEY_ID = "your_key",
  TBIT_CLINICAL_DATA_SECRET_ACCESS_KEY = "your_secret",
  GITHUB_PAT = "your_pat"
)

# One-time project setup
tbit_init_repo(
  path = "my_project",
  project_name = "clinical_data",
  remote_url = "https://github.com/org/data-repo.git",
  bucket = "shared-bucket",
  prefix = "project-alpha/",
  region = "us-east-1",
  max_file_size_gb = 500
)

# Connect and sync files
conn <- tbit_get_conn("my_project")

# Place source files in input_files/ (must be flat, no subdirectories)
# input_files/customers.csv
# input_files/orders.tsv

manifest <- tbit_sync_manifest(conn)
results <- tbit_sync(conn, manifest)
```

### Data Reader Workflow

```r
# Only need S3 credentials (names match project_name from project.yaml)
Sys.setenv(
  TBIT_CLINICAL_DATA_ACCESS_KEY_ID = "your_key",
  TBIT_CLINICAL_DATA_SECRET_ACCESS_KEY = "your_secret"
)

# Connect to bucket (follows redirects automatically)
conn <- tbit_get_conn()

# List available tables
tables <- tbit_list(conn)

# Read data (version = metadata_sha)
data <- tbit_read(conn, "customers", version = "xyz789")
```

### Migration Workflow

```r
# 1. Copy data externally (aws cli, console, etc.)
#    aws s3 sync s3://bucket-A/proj/ s3://bucket-B/proj/

# 2. Place .redirect.json in old bucket with credentials for new bucket
#    {
#      "redirect_to": "s3://bucket-B/proj/tbit/",
#      "migrated_at": "...",
#      "credentials": {
#        "access_key_env": "TBIT_CLINICAL_DATA_ACCESS_KEY_ID_2",
#        "secret_key_env": "TBIT_CLINICAL_DATA_SECRET_ACCESS_KEY_2"
#      }
#    }

# 3. Update project.yaml with new bucket
conn <- tbit_get_conn("my_project")

# 4. Sync routing to new location (interactive confirmation)
tbit_sync_routing(conn)
```

### Data Product Integration

```r
# R data product closure
dp$input$customers <- function(context = NULL, ...) {
  tbit_read(
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
        return tbit_read(
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

### Change Detection

- `metadata_sha` computed from alphabetically sorted fields
- Includes both `data_sha` and `original_file_sha`
- Single comparison detects any change
- Enables efficient updates and deduplication

### Conflict Resolution

- Pull before push to detect conflicts
- On non-fast-forward error: Manual resolution required
- User must pull latest and re-run sync
- No automatic merge of concurrent updates

---

## Project Configuration

### Credential Naming Convention

Credentials are programmatically managed based on `project_name`:

**Convention:** `TBIT_{PROJECT_NAME}_ACCESS_KEY_ID` / `TBIT_{PROJECT_NAME}_SECRET_ACCESS_KEY`

- `tbit_init_repo(project_name = "clinical_data", ...)` auto-generates env var names
- User only provides `project_name`; tbit derives credential names (uppercased, spaces → underscores)
- Ensures unique credentials when dpbuild combines multiple tbit repos
- Redirects append `_2`, `_3`, etc. for chained migrations

### .tbit/project.yaml

```yaml
project_name: clinical_data
project_description: Shared data repository for analytics
created_at: 2024-01-15
tbit_version: 0.1.0

# Storage configuration
storage:
  type: s3
  bucket: shared-bucket
  prefix: project-alpha/
  region: us-east-1
  max_file_size_gb: 1000
  credentials:
    access_key_env: "TBIT_CLINICAL_DATA_ACCESS_KEY_ID"      # auto-generated
    secret_key_env: "TBIT_CLINICAL_DATA_SECRET_ACCESS_KEY"  # auto-generated

# Sync configuration
sync:
  continue_on_error: true
  parallel_uploads: 4

# Computational environment
renv: true
```

**project.yaml is authoritative for write location.** Credential env var names are auto-generated from `project_name` — user should not edit these manually.

### .tbit/routing.json

```json
{
  "methods": {
    "r": {
      "default": "tbit::tbit_read"
    },
    "python": {
      "default": "tbit.read"
    }
  }
}
```

### .tbit/manifest.json

```json
{
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

**Design rationale**: The "current" fields per table enable sync optimization. When `tbit_sync_manifest()` runs, it compares local file SHAs against manifest. Only on mismatch does it fetch the full `version_history.json`. For repos with 100-300 tables, this avoids hundreds of S3 GETs on unchanged re-runs.

### .tbit/migration_history.json

```json
[
  {
    "from": "s3://bucket-A/proj/tbit/",
    "to": "s3://bucket-B/proj/tbit/",
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

- Verify `.tbit/`, `.git/`, and `manifest.json` exist
- Validate `input_files/` is flat (no subdirectories)
- Called internally by all operations

### Integrity State Tracking

Location: `.tbit/state/`

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

Provides audit log for recovery (manual recovery initially). Ensures consistency between git tracking and actual data.

### Routing Implementation

```r
tbit_read <- function(name, version = NULL, context = NULL, conn = NULL, ...) {

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

- Cache metadata per session
- Use HEAD requests for existence checks
- Hash original files to avoid re-reading
- Skip unchanged files via `original_file_sha` comparison
- Manifest current SHAs avoid version_history.json fetches for unchanged tables
- Parallelize multi-file operations

### Security Considerations

- Never store credentials in files
- Use standard environment variables exclusively
- S3 metadata is read-only for data readers
- Validate all paths for traversal attacks
- Respect configured file size limits

### Connection Architecture

- `tbit_conn` S3 class wraps project_name, bucket, prefix, region, s3_client, path, role
- Two modes: **developer** (has local repo path + git) and **reader** (S3 only, no local repo)
- Role auto-detected: `GITHUB_PAT` present + `path` provided → developer; otherwise → reader
- `tbit_get_conn(path = ...)` reads `.tbit/project.yaml` (developer path)
- `tbit_get_conn(bucket = ..., project_name = ...)` builds connection directly (reader path)
- Credential env var names derived from `project_name`: `TBIT_{NORMALIZED_NAME}_ACCESS_KEY_ID` / `_SECRET_ACCESS_KEY`
- `tbit_init_repo()` sets local git config (`user.name`, `user.email`) from global config or fallback — `git2r::default_signature()` requires local config on freshly init'd repos

### Dependency Strategy

- `paws.storage` (Imports): S3 operations — lightweight, avoids pulling full `paws`
- `git2r` (Suggests): Git operations — only needed by data developers, checked at runtime via `.tbit_check_git2r()`
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
- Valid tbit names (filesystem safe)
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
| Access Control | tbit_auth | Role-based table access, row/column filtering |
| Performance | tbit_cache | Local caching layer |
| Sampling | tbit_utils | Read subsets of large tables |
| Multi-language | tbit (Python) | Python implementation |

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
      "default": "tbit::tbit_read",
      "query": "tbit_query::read_filtered"
    }
  }
}
```

```r
# Future: query with filters instead of fetching full table
tbit_read(conn, "customers", 
          version = "xyz789", 
          context = "query", 
          filter = "age > 30",
          columns = c("id", "name"),
          limit = 100)
```

All `...` params forwarded to routed function — enables API calls, SQL queries, or filtered reads without changing the core interface.

### Deferred to v2

- Table-level routing overrides (repo-level only for v1)
- Managed migration via `tbit_migrate()` (manual external copy for v1)
- Queryable backends (Iceberg, S3 Tables)

---

## Key Differences from Current dpbuild/pins Approach

| Aspect | Current (pins) | tbit |
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

tbit provides robust data versioning optimized for clinical data science workflows where reproducibility is paramount. Designed for analytical environments with many evolving tables (50-100+), tbit makes version tracking seamless for datasets that are large in breadth but manageable in size.

**Key architectural decisions**:

1. Single read function (`tbit_read()`) with routing for all access patterns
2. **tbit version = metadata_sha**: uniquely identifies (data, metadata) pair
3. **Credential naming convention**: `TBIT_{PROJECT_NAME}_*` auto-generated, enabling multi-repo composition
4. Multi-language support via routing layer (R first, Python planned)
5. Cloud storage agnostic design (S3 first, extensible)
6. Optimized for clinical/scientific workflows with many tables
7. One repository per project with optional bucket prefix support
8. Deterministic SHA computation via alphabetical field sorting
9. Manual conflict resolution for rare concurrent write scenarios
10. Implicit location with redirect chain for seamless migration
11. project.yaml authoritative; routing.json and S3 metadata derived

This architecture keeps tbit focused on core versioning while providing clear extension points for enterprise features. As part of the larger data product ecosystem (with dpbuild, dpdeploy, and dpi), tbit serves as the foundational layer for reproducible analytical workflows.
