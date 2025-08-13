# tbit Package Requirements Specification

## Overview

Picture an analytical workflow built to derive specific insights from evolving data served as snapshots. Your dataset might consist of 50 or 100 different tables from which you create additional derived tables as your analysis requires. As these tables evolve and your transformation logic changes, ensuring that outputs remain trackable and reproducible for all collaborators becomes increasingly difficult. This scenario is familiar in clinical data science, where agility is key and reproducibility is paramount.

tbit aims to serve as a foundational building block for addressing this use case, leveraging only the tools readily available to data scientists: git, GitHub, and cloud object storage. While initially supporting AWS S3, tbit is designed to be cloud storage agnostic. Similarly, though we begin with an R implementation, the architecture supports future Python and other language implementations.

The package enables version-controlled data management by abstracting tables as code in git while storing actual data in cloud storage. For collections of tabular datasets that evolve over time, tbit enables:
- Setting up cloud-based repositories
- Frequently syncing data with automatic versioning
- Tracking complete data lineage
- Accessing any historical version for reproducibility

The primary utility motivating tbit is building version-tracked data products. Companion packages (dpbuild, dpdeploy, and dpi) build upon tbit to collectively enable creating, managing, and accessing reproducible data products in clinical and scientific workflows.

### Key Design Principles

1. **Git as source of truth**: All metadata originates in git for version control
2. **S3 metadata caching**: Metadata synced to S3 enables data reader access without GitHub  
3. **Separated workflows**: Data developers need git + S3 access for writes; data readers need only S3 access for reads
4. **Content addressing**: SHA-based storage for efficient deduplication
5. **Routing layer**: access.json provides flexible dispatch without tight coupling
6. **Language agnostic**: Designed for R and Python implementations
7. **Storage agnostic**: Initial S3 support with extensibility to other cloud providers
8. **One repo per project**: Each git repository manages a single project/prefix

### User Types

- **Data developers**: Create and update datasets, manage evolving clinical/scientific data (identified by presence of GITHUB_PAT)
- **Data readers**: Consume versioned data for analysis, need reproducible access (S3 credentials only)
- **Data products**: Analytical applications built on versioned tbits (via dpbuild, dpdeploy, dpi)

## Architecture

### Storage Structure

**Git Repository (Authoritative Source)**:
```
repo/
├── {table_name}/
│   ├── metadata.json             # Current metadata only
│   ├── version_history.json      # Index: commit → SHA mappings including original_file_sha
│   └── access.json               # Routing configuration
├── input_files/                   # Flat directory for source files (no subdirectories)
│   ├── customers.csv
│   └── orders.tsv
├── .tbit/
│   ├── project.yaml              # Project configuration for dev environment
│   └── state/                    # Operation integrity tracking
│       └── {operation_id}.json   # Tracks in-progress operations
└── manifest.json                 # Repository catalog
```

**Cloud Storage (S3)**:
```
bucket/
├── {optional_prefix}/             # Optional project prefix
│   ├── tbit/                     # Shared input tables
│   │   ├── {table_name}/
│   │   │   ├── {sha}.parquet     # Data files
│   │   │   └── .metadata/        # Synced from git (for user access)
│   │   │       ├── metadata.json      
│   │   │       ├── version_history.json 
│   │   │       └── access.json        
│   │   └── .manifest/
│   │       └── manifest.json     # Repository catalog (identical to git version)
│   └── data_products/
│       └── {dp_name}/
│           └── tbit/             # Derived tables
```

### Metadata Schema

**metadata.json** - Current state only:
```json
{
  "data_sha": "abc123...",          # SHA of parquet file
  "original_file_sha": "def456...", # SHA of original CSV/TSV/etc
  "size_bytes": 1048576,
  "nrow": 10000,
  "ncol": 15,
  "colnames": ["id", "name", "value", ...],
  "created_at": "2024-01-15T10:30:00Z",
  "tbit_version": "0.1.0",
  "custom": {
    "description": "Response table",
    "tags": ["Efficacy", "SDTM"]
  }
}
```

**version_history.json** - Index with original file tracking:
```json
[
  {
    "commit": "def456...",
    "data_sha": "abc123...",           # SHA of parquet
    "metadata_sha": "xyz789...",       # SHA of all metadata fields (alphabetically sorted)
    "original_file_sha": "qrs456...",  # SHA of CSV/TSV/etc
    "timestamp": "2024-01-15T10:30:00Z"
  }
]
```
Note: Author information retrieved from git at runtime, not stored

**manifest.json** - Repository catalog:
```json
{
  "updated_at": "2024-01-15T10:30:00Z",
  "tables": {
    "customers": {
      "current_data_sha": "abc123...",
      "current_metadata_sha": "xyz789...",
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

### Routing Configuration (access.json)

```json
{
  "current": {
    "location": "s3://bucket/tbit/table_name/",
    "methods": {
      "r": {
        "default": "tbit::tbit_read",
        "secured": "tbit_auth::read_with_access_control",
        "cached": "tbit_cache::read_cached"
      },
      "python": {
        "default": "tbit.read",
        "secured": "tbit_auth.read_with_access_control",
        "cached": "tbit_cache.read_cached"
      }
    }
  },
  "history": [
    {
      "location": "s3://old-bucket/table_name/",
      "valid_until": "2024-01-01T00:00:00Z",
      "migration_reason": "Bucket consolidation"
    }
  ]
}
```

**Design Principles**: 
- Methods organized by language, then context
- Each language has its own implementation following its conventions
- R functions expect (conn, name, table_version, git_version, ...)
- Python functions follow Python tbit package conventions
- Enables language-specific optimizations while maintaining consistent contexts
- Extra parameters passed via `...` are forwarded directly to routed functions

## API Reference

### Repository Management (Data Developers)

**tbit_init_repo(path = ".", remote_url, bucket, prefix = NULL, region = NULL, max_file_size_gb = 1000)**
- One-time setup for data developers
- Validates environment variables (AWS credentials, GITHUB_PAT)
- Creates folder structure, initializes git with remote, sets up renv
- Creates `.tbit/project.yaml` for environment restoration
- Optional prefix for bucket organization (one project per repo)
- Configurable max file size limit (default 1TB)
- Returns: Success status

**tbit_get_conn(path = ".")**
- Loads project configuration and validates required environment variables
- For data developers: Checks git + S3 access (presence of GITHUB_PAT)
- For data readers: Checks S3 access only
- Returns: Connection object

### Core Operations

**tbit_read(conn, name, table_version = NULL, git_version = NULL, context = NULL, ...)** (All Users)
- Unified read function with routing via access.json
- Context parameter for runtime behavior selection
- Metadata always from S3 for readers
- git_version takes precedence over table_version when both provided
- Additional parameters in `...` forwarded to routed function
- Returns: Data frame or routed function result

**tbit_write(conn, data, name, metadata = NULL, message = NULL)** (Data Developers)
- Complete workflow: git commit → git push → S3 sync in sequence
- Change detection via metadata_sha comparison (alphabetically sorted fields)
- Handles: no-op, metadata-only update, or full update with S3 upload
- Returns: List with deployment details

### Batch Operations (Data Developers)

**tbit_sync_manifest(conn, path = NULL, pattern = "\*")**
- Scans flat `input_files/` directory (no subdirectories allowed)
- Computes SHA of files in original format
- Checks against manifest and version history for deduplication
- Returns: Manifest for review

**tbit_sync(conn, manifest, continue_on_error = TRUE)**
- Processes new/changed files only
- One commit per table
- Manual conflict resolution on concurrent writes
- Returns: Updated manifest with results

### Query Operations (Data Readers)

**tbit_list(conn, pattern = NULL, include_versions = FALSE)**
- Lists available tables from S3 manifest
- Returns: Data frame with table info

**tbit_history(conn, name, n = 10)**
- Shows version history
- Returns: Data frame with version details

### Utility Functions

**tbit_status()** (Both) - Shows uncommitted changes and sync state

**tbit_validate(conn, fix = FALSE)** (Data Developers) - Checks git-storage consistency

**tbit_migrate(conn_from, conn_to, tables = NULL, update_redirects = TRUE)** (Data Developers) - Migrates tables between storage locations

## User Workflows

### Data Developer Workflow
```r
# Set environment variables
Sys.setenv(
  AWS_ACCESS_KEY_ID = "your_key",
  AWS_SECRET_ACCESS_KEY = "your_secret",
  GITHUB_PAT = "your_pat"
)

# One-time project setup with optional prefix
tbit_init_repo(path = "my_project", 
               remote_url = "https://github.com/org/data-repo.git",
               bucket = "shared-bucket",
               prefix = "project-alpha/",  # Optional
               region = "us-east-1",
               max_file_size_gb = 500)     # Optional, default 1000

# Connect and sync files
conn <- tbit_get_conn("my_project")

# Place source files in input_files/ (must be flat, no subdirectories)
# input_files/customers.csv
# input_files/orders.tsv

manifest <- tbit_sync_manifest(conn)
results <- tbit_sync(conn, manifest)

# Handle conflicts if concurrent write occurred
# Error: "Another update occurred, please run tbit_sync again"
```

### Data Reader Workflow
```r
# Only need S3 credentials and bucket name
Sys.setenv(
  AWS_ACCESS_KEY_ID = "your_key",
  AWS_SECRET_ACCESS_KEY = "your_secret"
)

# Connect to bucket (with optional prefix if configured)
conn <- tbit_get_conn()

# List available tables
tables <- tbit_list(conn)

# Read data
data <- tbit_read(conn, "customers", table_version = "abc123")
```

### Data Product Integration
```r
# R data product closure
dp$input$customers <- function(context = NULL, ...) {
  tbit_read("customers", 
            table_version = "abc123",
            context = context,
            ...)  # Extra parameters forwarded
}

# Python data product equivalent
class DataProduct:
    def customers(self, context=None, **kwargs):
        return tbit_read("customers",
                        table_version="abc123",
                        context=context,
                        **kwargs)
```

## Data Flow

### Write Operation (Data Developers)
1. Compute data_sha (parquet) and original_file_sha (CSV/TSV/etc)
2. Sort metadata fields alphabetically, compute metadata_sha
3. Check if matches HEAD (no-op if yes)
4. Check version_history for existing SHAs (including original_file_sha)
5. Determine update type and execute
6. Commit and push to git (author from git config)
7. Upload to S3 (if new data)
8. Sync metadata to S3 for data reader access
9. Update state tracking for operation integrity

### Read Operation (All Users)
1. Read metadata from S3 (cached from git)
2. Resolve version and routing from access.json
3. If git_version provided, use it (more specific than table_version)
4. Download parquet from S3
5. Apply context-specific processing via routing

### Change Detection
- metadata_sha computed from alphabetically sorted fields
- Includes both data_sha and original_file_sha
- Single comparison detects any change
- Enables efficient updates and deduplication

### Conflict Resolution
- Pull before push to detect conflicts
- On non-fast-forward error: Manual resolution required
- User must pull latest and re-run sync
- No automatic merge of concurrent updates

## Implementation Details

### Project Configuration (.tbit/project.yaml)
```yaml
project_name: my_tbits
project_description: Shared data repository for analytics
created_at: 2024-01-15
tbit_version: 0.1.0

# Required environment variables (standard names)
required_env:
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY
  - GITHUB_PAT  # Only for data developers

# Storage configuration  
storage:
  type: s3
  bucket: shared-bucket
  prefix: project-alpha/    # Optional
  region: us-east-1
  max_file_size_gb: 1000   # Configurable limit
  
# Sync configuration
sync:
  continue_on_error: true   # Default behavior
  parallel_uploads: 4       # Optional optimization
  
# Optional renv integration
renv: true
```

Purpose: Enables data developers to restore their working environment after cloning by documenting project settings and required environment variables.

### Internal Implementation

**Environment Validation**
- Check required environment variables on connection
- GITHUB_PAT presence determines developer vs reader role
- Use standard AWS and GitHub variable names
- No custom configuration functions

**Project Structure Validation**
- Verify `.tbit/`, `.git/`, and `manifest.json` exist
- Validate `input_files/` is flat (no subdirectories)
- Called internally by all operations

**Integrity State Tracking** (.tbit/state/)
- Track operations to ensure git-data coupling:
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
- Provides audit log for recovery (manual recovery initially)
- Ensures consistency between git tracking and actual data

**Internal Functions**
- `.tbit_codify()`: Creates metadata files with sorted fields
- `.tbit_commit()`: Git operations (author from git config)
- `.tbit_push()`: Push to remote with pull-first check
- `.tbit_deploy()`: S3 upload and metadata sync

### Performance & Security

**Performance Optimizations**
- Cache metadata per session
- Use HEAD requests for existence checks
- Hash original files to avoid re-reading
- Skip unchanged files via original_file_sha comparison
- Parallelize multi-file operations

**Security Considerations**
- Never store credentials in files
- Use standard environment variables exclusively
- S3 metadata is read-only for data readers
- Validate all paths for traversal attacks
- Respect configured file size limits

## Routing Implementation

```r
tbit_read <- function(name, table_version = NULL, git_version = NULL,
                     context = NULL, conn = NULL, ...) {
  
  # Default context
  if (is.null(context)) context <- "default"
  
  # Read access.json from S3 metadata
  access_info <- .get_access_info_from_s3(conn, name)
  
  # Get R method for the specified context
  r_methods <- access_info$current$methods$r
  if (!context %in% names(r_methods)) {
    stop("Context '", context, "' not found for R")
  }
  
  func_name <- r_methods[[context]]
  func <- eval(parse(text = func_name))
  
  # Call with R conventions, forwarding extra parameters
  func(conn, name, table_version, git_version, ...)
}
```

Python equivalent would follow similar pattern, using language-specific conventions.

## Validation & Testing

### Validation Requirements

**Initialization** (Data Developers):
- Environment variables: AWS credentials and GITHUB_PAT
- GitHub PAT permissions and remote access
- S3 bucket existence and write permissions
- Git user.name and user.email configured
- Validate prefix doesn't conflict with existing data

**Connection**:
- Data developers: Validates git + S3 access (GITHUB_PAT present)
- Data readers: Validates S3 read access only
- Auto-detects user type based on GITHUB_PAT presence

**Operations**:
- Project structure check before all operations
- Input files directory must be flat (no subdirectories)
- File format support via rio::import
- Valid tbit names (filesystem safe)
- File size check against configured limit
- Metadata sync verification after deployment

### Testing Coverage
- Unit: SHA computation (with sorting), routing, metadata operations
- Integration: Full workflow, S3 metadata access, sync verification
- Edge cases: Network failures, corrupt files, missing metadata, concurrent writes

## Supported File Formats
Via `rio::import`: CSV, TSV, Excel, SAS, Parquet, SPSS, Stata, etc.
All stored as parquet regardless of input format.

**Optimized for**: Clinical/scientific datasets that are wide (many columns) but not excessively large (typically MB to low GB range), enabling quick fetching and efficient versioning.

## Extension & Migration

### Future Extensibility
The routing design enables clean integration:
1. **Access Control**: Via tbit_auth package
2. **Performance**: Via tbit_cache package  
3. **Sampling**: Via tbit_utils package
4. **Multi-language**: Python implementation following same architecture
5. **Storage backends**: Designed for cloud storage agnosticism
   - Current: AWS S3
   - Planned: Google Cloud Storage, Azure Blob Storage
   - Architecture supports any object storage with minimal changes

### Key Differences from dpbuild
1. Git-first metadata approach
2. Content-addressable storage
3. S3 metadata caching for data readers
4. Dynamic routing layer with multi-language support
5. Context-based flexibility within each language
6. Simplified configuration (standard environment variables)
7. Unified read interface per language
8. Optional prefix support for shared buckets
9. Alphabetical field sorting for consistent SHA computation

## Summary

tbit provides robust data versioning optimized for clinical data science workflows where reproducibility is paramount. Designed for analytical environments with many evolving tables (50-100+), tbit makes version tracking seamless for datasets that are large in breadth but manageable in size (typically MB to low GB range).

The design separates complexity by user type:
- **Data developers** get full version control with git for creating and updating data
- **Data readers** get simple cloud-storage-only access without needing GitHub credentials
- **Data products** get stable interfaces via the routing layer

Key architectural decisions:
1. **Single read function** (`tbit_read()`) with routing for all access patterns
2. **Environment-based configuration** using standard environment variables
3. **Multi-language support** via routing layer (R implementation first, Python planned)
4. **Cloud storage agnostic** design (S3 first, extensible to GCS, Azure)
5. **Optimized for clinical/scientific workflows** with many tables and frequent updates
6. **One repository per project** with optional bucket prefix support
7. **Deterministic SHA computation** via alphabetical field sorting
8. **Manual conflict resolution** for rare concurrent write scenarios

This architecture keeps tbit focused on core versioning while providing clear extension points for enterprise features. As part of the larger data product ecosystem (with dpbuild, dpdeploy, and dpi), tbit serves as the foundational layer for reproducible analytical workflows in clinical data science.