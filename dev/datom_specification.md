# datom Package Specification

## Overview

Picture an analytical workflow built to derive specific insights from evolving data served as snapshots. Your dataset might consist of 50 or 100 different tables from which you create additional derived tables as your analysis requires. As these tables evolve and your transformation logic changes, ensuring that outputs remain trackable and reproducible for all collaborators becomes increasingly difficult. This scenario is familiar in clinical data science, where agility is key and reproducibility is paramount.

datom serves as a foundational building block for addressing this use case, leveraging only tools readily available to data scientists: git, GitHub, and cloud object storage. While initially supporting AWS S3 and local filesystem, datom is designed to be storage agnostic. Similarly, though we begin with an R implementation, the architecture supports future Python and other language implementations.

The package enables version-controlled data management by abstracting tables as code in git while storing actual data in cloud storage. For collections of tabular datasets that evolve over time, datom enables:

- Setting up cloud-based repositories
- Frequently syncing data with automatic versioning
- Tracking complete data lineage
- Accessing any historical version for reproducibility

The primary utility motivating datom is building version-tracked data products. Companion packages (dpbuild, dpdeploy, and dpi) build upon datom to collectively enable creating, managing, and accessing reproducible data products in clinical and scientific workflows.

---

## Design Principles

1. **Git as source of truth**: All metadata originates in git for version control
2. **Git + GitHub for the data repo are mandatory; governance is optional and on-demand**: Every datom project requires a data git repo with a remote (today: GitHub) and a storage backend for parquet bytes. The governance layer (portfolio register, dispatch routing, managed migration) is adopted on-demand via `datom_attach_gov()` -- typically when graduating to object storage or migrating data. The storage backend (`datom_store_s3`, `datom_store_local`, future GCS, etc.) controls only where parquet bytes live; it does **not** make git optional. Once gov is attached, it cannot be detached. There is still no "local-only / no-remote" mode for the data repo. Amended Phase 18, 2026-05-02 (supersedes the Phase-16 lock that required gov from day one).
3. **S3 metadata caching**: Metadata synced to S3 enables data reader access without GitHub
4. **Separated workflows**: Data developers need git + S3 access for writes; data readers need only S3 access for reads
5. **Content addressing**: SHA-based storage for efficient deduplication
6. **Explicit data reference**: Data location stored in `ref.json` at the governance store, resolved via `.datom_resolve_ref()` — single read, no recursion
7. **Two-store architecture**: Governance store (dispatch, ref, migration history) and data store (manifest, table data/metadata) can target different buckets
8. **Storage abstraction**: Business logic calls `.datom_storage_*()` dispatch functions; backend-specific code (`.datom_s3_*()`) is isolated behind a dispatch layer keyed on `conn$backend`
9. **Language agnostic**: Designed for R and Python implementations
10. **Storage agnostic**: S3 and local filesystem supported; extensible to other cloud providers
11. **One repo per project**: Each git repository manages a single project/prefix

---

## Versioning Model

### What Gets Versioned

datom distinguishes between **versioned content** and **tracked configuration**:

| Category | Files | Versioned? | Creates version_history entry? |
|----------|-------|------------|-------------------------------|
| **Data** | `{data_sha}.parquet` | Yes | Yes |
| **Metadata** | `metadata.json`, `{metadata_sha}.json` | Yes | Yes |
| **Configuration** | `dispatch.json`, `project.yaml`, `manifest.json` | No | No |

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
        
Day 2:  Edit dispatch.json (add "cached" context)
        git commit includes: dispatch.json only
        
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
| **Data developers** | Create and update datasets, manage evolving clinical/scientific data | Storage credentials (AWS for S3, none for local) + GITHUB_PAT |
| **Data readers** | Consume versioned data for analysis, need reproducible access | Storage credentials (AWS for S3, none for local) |
| **Data products** | Analytical applications built on versioned datoms (via dpbuild, dpdeploy, dpi) | AWS credentials only |

User type is auto-detected based on the presence of `GITHUB_PAT`.

---

## Architecture

### Two Repositories: Governance + Data

datom uses **two separate git repositories**:

- **Governance repository** (one per organization/governance bucket): a thin git repo that tracks routing/governance metadata for *every* data project sharing the governance store. Per-project metadata lives at `projects/{project_name}/`. The governance repo is created once via `datom_init_gov()` and shared across all projects.
- **Data repository** (one per project): the per-project git repo containing table metadata, version history, and the project manifest. Created by `datom_init_repo()`.

Both repos are git-tracked and pushed to GitHub. They are cloned to **separate** local working directories (siblings by default, e.g. `study-001-data/` next to `acme-gov/`).

```
                ┌──────────────────────────────────────────┐
                │ Governance GitHub repo (acme-gov)         │
                │ Mirrors gov clone:                        │
                │   projects/STUDY_001/dispatch.json        │
                │   projects/STUDY_001/ref.json             │
                │   projects/STUDY_001/migration_history... │
                │   projects/STUDY_002/...                  │
                └──────────────────────────────────────────┘
                              ▲
                              │ git push/pull
                              │
   ┌─────────────────┐        │        ┌─────────────────┐
   │ Data GitHub repo │       │        │ Data GitHub repo │
   │  (study-001)     │       │        │  (study-002)     │
   │ Per-project      │       │        │ Per-project      │
   │ tables, manifest │       │        │ tables, manifest │
   └─────────────────┘        │        └─────────────────┘
```

### Storage Structure

**Governance Repository (git, on disk)**:
```
acme-gov/
├── README.md
├── projects/
│   ├── .gitkeep
│   ├── STUDY_001/
│   │   ├── dispatch.json             # Methods configuration (project-scoped)
│   │   ├── ref.json                  # Data location reference (project-scoped)
│   │   └── migration_history.json    # Audit trail of location changes
│   └── STUDY_002/
│       └── ...
└── .git/
```

**Data Repository (git, on disk — one per project)**:
```
study-001-data/
├── {table_name}/
│   ├── metadata.json             # Current metadata only
│   └── version_history.json      # Index: version -> SHA mappings
├── input_files/                   # Flat directory for source files (gitignored)
│   ├── customers.csv
│   └── orders.tsv
├── .datom/
│   ├── project.yaml              # Project configuration
│   └── manifest.json             # Repository catalog (project-scoped)
└── .gitignore
```

**Note:** Contents of `input_files/` are gitignored. Only metadata tracked in git; actual data files stay local and sync to the data store as parquet. **`dispatch.json`, `ref.json`, and `migration_history.json` no longer live in the data repo** — they are owned by the governance repo at `projects/{project_name}/`.

**Cloud Storage — Governance Store**:
```
governance-bucket/
└── {optional_prefix}/
    └── datom/
        ├── .access/                          # Reserved for datomaccess (do not touch)
        └── projects/
            ├── STUDY_001/
            │   ├── dispatch.json             # Mirrors gov repo
            │   ├── ref.json
            │   └── migration_history.json
            └── STUDY_002/
                └── ...
```

**Cloud Storage — Data Store** (per project):
```
data-bucket/
└── {optional_prefix}/
    └── datom/
        ├── .metadata/
        │   └── manifest.json          # Project manifest (mirrors data repo)
        └── {table_name}/
            ├── {data_sha}.parquet     # Data files (content-addressed)
            └── .metadata/
                ├── metadata.json      # Current metadata
                ├── {metadata_sha}.json
                └── version_history.json
```

**Local Filesystem Store** mirrors the cloud layout (same paths, on disk).

**Note:** Governance and data stores may be the same bucket+prefix or different ones. The two-store + two-repo split lets organizations keep routing/governance metadata centralized while per-project data and tables live in isolated buckets.

### Location Resolution

Data location is stored in `ref.json` in the governance repo at `projects/{project_name}/ref.json`. Resolution is **role-aware**:

```
datom_read(conn, "customers", ...)
        |
        v
1. Resolve ref.json (role-aware):
   - Developer with gov_local_path: read from local gov clone (fast/offline)
   - Reader: read via gov storage client (no clone)
2. Extract current.root, current.prefix, current.region
3. Read data from resolved location in data store
```

**Post-migration**: `ref.json` may contain `previous` entries with sunset dates. The parser emits a deprecation warning when previous entries exist, alerting operators that old location cleanup is pending. No redirect chain — migration is a ref.json update + data copy + commit on the gov repo.

### Ref Resolution Lifecycle

Ref resolution runs at two points in the conn lifecycle:

**Conn time** (`datom_get_conn()` — both reader and developer roles, both backends):
1. Resolve `projects/{project_name}/ref.json` (role-aware: clone for developer, storage for reader).
2. Detect migration: `store$data` location vs ref location.
   - **Developer + mismatch** → auto-pull git (data repo), re-read `project.yaml`. If still mismatched, abort with "ref.json and project.yaml disagree after pull". Otherwise proceed (pull fixed it, info message).
   - **Reader + mismatch** → warn "data migrated, update your store config", proceed using the ref-resolved location with the reader's existing data credentials.
3. Reachability check (`HeadBucket` for S3, `fs::dir_exists()` for local):
   - Reachable → proceed.
   - Unreachable + migrated → actionable error mentioning credentials/path after migration.
   - Unreachable + no migration → generic unreachable error.
4. **Ref failure at conn time is warn-only**: governance informs, it does not gate reads. If `ref.json` is unreadable, warn with details and proceed using `store$data` location. Data reachability is what gates access — not governance reachability.
5. **No governance component** → skip ref resolution entirely (backward compatible with pre-Phase 10 stores).

**Write time** (`datom_write()` — before any data SHA computation):
1. Re-resolve ref via `.datom_check_ref_current(conn)`. **Storage-only** (no clone fallback) — the write-time guard intentionally hits gov storage to catch stale clones.
2. Compare ref root/prefix against `conn$root`/`conn$prefix`.
3. **Any failure is a hard abort** — network error, missing file, malformed JSON, location mismatch. Writing without a verified location risks orphaning data; there is no safe fallback. Error mentions "orphaning data" and instructs the user to rebuild the conn.
4. No `conn$gov_root` (legacy conn) → skip check.

**Read time**: no ref re-check. Stale reads fail cleanly (404/403/missing file) → user rebuilds conn → self-healing. No silent corruption risk.

**Credentials vs location**: `ref.json` tells you *where* the data is, not *how to authenticate*. The user's `store$data` credentials are used against the ref-resolved location. For local backend, no credentials — just the path.

### Write Targeting: Data vs Governance

Every datom write is targeted at exactly one of the two repos:

| Operation                    | Data clone   | Gov clone    | Notes                                      |
|------------------------------|--------------|--------------|--------------------------------------------|
| `datom_write()`              | git + storage| —            | Tables, manifest, metadata.                |
| `datom_sync()` / batch       | git + storage| —            | Same as `datom_write()`, multi-table.      |
| `datom_sync_dispatch()`      | —            | git + storage| Commits/pushes `projects/{name}/dispatch.json`. |
| `datom_init_gov()`           | —            | git + storage| Creates the gov repo + skeleton.           |
| `datom_init_repo()`          | git + storage| git + storage| Registers project (writes `projects/{name}/{ref,dispatch,migration_history}.json` + commits gov), then sets up data repo. |
| `datom_decommission()`       | git + storage| git + storage| Wipes data project + removes `projects/{name}/` from gov + commits gov. |
| `datom_pull()`               | git only     | git only     | Pulls both clones (no storage refresh — git is source of truth). |

**Invariant**: data-side functions never touch the gov clone after init/decommission, and gov-side functions never touch the data clone. Tested via the data-side write purity audit.

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

### ref.json

Always present at the governance store, created by `datom_init_repo()`. Stores the authoritative data location:

S3 backend:
```json
{
  "current": {
    "type": "s3",
    "root": "study-bucket",
    "prefix": "trial/",
    "region": "us-east-1"
  }
}
```

Local backend:
```json
{
  "current": {
    "type": "local",
    "root": "/data/storage",
    "prefix": null
  }
}
```

Post-migration, may contain `previous` entries:

```json
{
  "current": {
    "type": "s3",
    "root": "bucket-B",
    "prefix": "proj/",
    "region": "us-east-1"
  },
  "previous": [
    {
      "type": "s3",
      "root": "bucket-A",
      "prefix": "proj/",
      "region": "us-east-1",
      "sunset_date": "2025-01-01"
    }
  ]
}
```

`.datom_resolve_ref()` reads `ref.json` from the governance store and returns the `current` data location. When `previous` entries exist, it emits a deprecation warning.

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

Creates a single S3 storage component (used for governance or data). When `validate = TRUE`, runs `HeadBucket` to verify credentials and bucket access. Returns `datom_store_s3` S3 class with `type = "s3"`.

### `datom_store_local()` — Local Filesystem Component Constructor

```r
datom_store_local(
  path,
  prefix = NULL,
  validate = TRUE
)
```

Creates a local filesystem storage component. `path` is the root directory (analogous to S3 bucket). When `validate = TRUE`, checks that the directory exists and is writable. Returns `datom_store_local` S3 class with fields `$path` (normalized absolute path), `$prefix`, `$validated`.

No credentials needed — filesystem permissions are implicit.

Future backends (`datom_store_gcs()`, `datom_store_azure()`) will have their own constructors.

### `datom_store()` — Composite Constructor

```r
datom_store(
  governance,
  data,
  github_pat = NULL,
  data_repo_url = NULL,
  gov_repo_url = NULL,
  gov_local_path = NULL,
  github_org = NULL,
  validate = TRUE
)
```

Bundles governance + data store components with git config:
- `github_pat` present → `role = "developer"`; absent → `role = "reader"`
- `data_repo_url`: existing GitHub data repo URL (mutually exclusive with `create_repo` in `datom_init_repo()`)
- `gov_repo_url`: existing GitHub governance repo URL
- `gov_local_path`: override for local governance clone directory (default: `basename(gov_repo_url)` sibling of data repo)
- `github_org`: for org repo creation; NULL → personal repo
- When `validate = TRUE` and `github_pat` provided, validates PAT via `GET /user`

### `.datom_create_github_repo()` — GitHub Repo Creation

Creates GitHub repos via REST API (`httr2`). Safety: existing+empty → reuse, existing+content → abort before local side effects.

---

## API Reference

### Repository Management (Data Developers)

#### datom_init_gov()

```r
datom_init_gov(
  gov_store,
  gov_repo_url = NULL,
  gov_local_path = NULL,
  create_repo = FALSE,
  repo_name = NULL,
  github_pat = NULL,
  github_org = NULL,
  private = TRUE
)
```

One-time bootstrap of the **governance repository** for an organization (or any group sharing a governance store). Run once per governance bucket; all subsequent `datom_init_repo()` calls reuse the resulting gov repo.

- `gov_store`: a single `datom_store_s3()` or `datom_store_local()` component (the governance side of `datom_store()`).
- `create_repo = TRUE`: provisions a new GitHub repo via REST API. Mutually exclusive with `gov_repo_url`.
- `gov_repo_url`: URL of an existing (empty) governance GitHub repo to adopt.
- `gov_local_path`: working directory for the gov clone. Defaults to `basename(repo_url)` next to the user's current directory.
- `private = TRUE`: governance repos default to private — they enumerate every project in the org.

Side effects:
1. Validates credentials and reachability of `gov_store`.
2. Creates GitHub repo (if `create_repo = TRUE`) or validates the existing one is empty.
3. `git2r::clone()` to `gov_local_path`, scaffolds `README.md` + `projects/.gitkeep`, commits, pushes.
4. Uploads the empty `projects/` skeleton to gov storage.

Returns: the gov repo URL (string), suitable to feed into `datom_store(gov_repo_url = ...)`.

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

One-time setup for data developers. Requires that `datom_init_gov()` has already been run for the target governance store; the gov repo URL must be present on the store via `datom_store(gov_repo_url = ...)`.

- `store`: composite `datom_store()` with both governance and data components, plus `gov_repo_url` (and optionally `gov_local_path`).
- `create_repo = TRUE`: auto-creates the **data** GitHub repo via API from `repo_name` (normalized: lowercase, underscores -> hyphens).
- `repo_name`: defaults to `project_name`; allows custom GitHub repo name.
- **Validation-first**: all store/repo validation happens before any filesystem or git side effects.
- **Gov clone bootstrap**: pulls or shallow-clones the gov repo to `gov_local_path` if not already present.
- **Namespace safety check**: aborts if `projects/{project_name}/ref.json` already exists in the gov repo (another project is using this name). Pass `.force = TRUE` to override.
- Creates data folder structure, initializes git with remote.
- Creates `.datom/project.yaml` with two-component storage config + `repos.governance` block.
- Creates `.datom/manifest.json` with `project_name` at the top level.
- Writes `projects/{project_name}/{ref,dispatch,migration_history}.json` to the gov clone, commits + pushes the gov repo, then uploads the same files to gov storage.
- Pushes initial commit to the data git remote, then uploads manifest to data storage.

Returns: Invisible TRUE on success. Cleans up gov clone + data clone on failure (best-effort).

#### datom_decommission()

```r
datom_decommission(
  conn,
  force = FALSE,
  delete_gov_clone = FALSE
)
```

Tears down a project. Removes the project's data (storage + GitHub data repo) and its governance footprint (`projects/{project_name}/` from gov clone + gov storage), then commits + pushes the gov repo. Idempotent on partial failure.

- `force = FALSE`: requires interactive confirmation.
- `delete_gov_clone = FALSE`: gov clone is shared across projects; defaults to leaving it in place. Set `TRUE` only when decommissioning the last project on the governance bucket.

Returns: Invisible list with `data_deleted`, `gov_pruned`, `data_repo_deleted` flags.

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
- Resolves data location from ref.json at governance store
- Auto-detects developer vs reader based on GITHUB_PAT presence

Returns: Connection object (`datom_conn` S3 class)

#### datom_clone()

```r
datom_clone(path, store)
```

Clones an existing datom repository and returns a ready-to-use connection:
- `store`: composite `datom_store()` with `data_repo_url` and `github_pat`
- Wraps `git2r::clone()` + `datom_get_conn(path)`
- Validates the clone contains `.datom/project.yaml` (is a datom repo)
- Rejects non-empty target directories

Returns: `datom_conn` object (developer role)

#### datom_pull()

```r
datom_pull(conn)
```

Pulls latest git changes from remotes. Recommended at the start of each work session:
- Pulls **both** the data repo and the governance repo (`projects/{project_name}/` is what changes).
- Git is the source of truth — no storage refresh needed.
- Developer role only (readers have no git access).
- Reports commits pulled per repo and current branches.

Returns: Invisible list with `data` and `governance` sub-lists, each with `commits_pulled` (integer) and `branch` (string).

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

Unified read function with routing via dispatch.json:
- `version`: metadata_sha (datom version) — if NULL, uses current
- `context`: runtime behavior selection (default: "default") (**Planned — not yet implemented.** Currently reads parquet directly; routing dispatch via `context` and `dispatch.json` will be added when downstream consumers exist.)
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
| NULL | provided | Metadata-only sync for single table (e.g., after editing dispatch.json) |
| NULL | NULL | Aliases to `datom_sync_dispatch()` |

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

#### datom_sync_dispatch() — Data Developers

```r
datom_sync_dispatch(conn, .confirm = TRUE)
```

Updates routing/governance metadata in storage to match the gov clone:
- Interactive confirmation required (set `.confirm = FALSE` for programmatic use).
- **Targets the governance repo + governance store only.** Pushes `projects/{project_name}/{dispatch,ref,migration_history}.json` from the gov clone to gov storage. Also commits + pushes the gov repo if there are uncommitted gov-side changes.
- Does **not** touch the data clone or data store. Use `datom_validate(fix = TRUE)` for data-side reconciliation.
- Used after external migration (aws cli, etc.) and `project.yaml` update.

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

#### datom_summary()

```r
datom_summary(conn)
```

Compact, role-aware overview of a single project: name, role, backend/root/prefix, table count, total versions, last write time, and (developers only) the data git remote URL. Reads `.metadata/manifest.json` from the data store. Returns an S3 `datom_summary` object with a `print` method.

#### datom_projects()

```r
datom_projects(x)
```

Lists every project registered in the shared governance repo. Accepts a `datom_conn` (uses the local gov clone when present -- offline, fast) or a `datom_store` (lets a caller enumerate the portfolio before connecting to any one project). Reads `projects/*/ref.json`. Corrupt entries warn and skip. Returns a sorted data frame with `name`, `data_backend`, `data_root`, `data_prefix`, `registered_at`.

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

- **Repo-level checks**: `projects/{project_name}/{ref,dispatch,migration_history}.json` exist in gov clone + gov storage; `.datom/manifest.json` exists in data repo + data storage.
- **Per-table checks**: metadata.json, version_history.json, and `{data_sha}.parquet` exist on data storage for each table tracked in git
- `fix = TRUE`: attempts to repair inconsistencies by calling `datom_sync_dispatch(conn, .confirm = FALSE)` (gov-side) and re-uploading data-side metadata.

Returns: List with `valid` (logical), `repo_files` (data frame), `tables` (data frame), `fixed` (logical).

#### datom_migrate() — Data Developers (Future)

```r
datom_migrate(conn_from, conn_to, tables, update_ref = TRUE)
```

**Not yet implemented.** Managed migration — see "Deferred to v2."

### Example Data

#### datom_example_data()

```r
datom_example_data(domain = c("dm", "ex", "lb", "ae"), cutoff_date = NULL)
```

Loads bundled clinical trial example data for use in examples and vignettes. The data simulates a Phase II study (STUDY-001) with 48 subjects across four SDTM-style domains.

- `domain`: `"dm"` (demographics), `"ex"` (exposure), `"lb"` (laboratory), or `"ae"` (adverse events)
- `cutoff_date`: Optional `"YYYY-MM-DD"` to filter rows on or before this date, simulating a point-in-time EDC extract

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
| `datom` | `.datom/project.yaml`, `.datom/manifest.json` exist (gov files live in the governance repo, not here) |
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

# --- Bootstrap governance repo (one-time per organization / gov bucket) ---
gov_repo_url <- datom_init_gov(
  gov_store = store$governance,
  create_repo = TRUE,
  repo_name  = "acme-gov",
  github_pat = keyring::key_get("github_pat"),
  github_org = "acme"
)

# Re-build the store with gov_repo_url so subsequent calls find the gov repo
store <- datom_store(
  governance = store$governance,
  data = store$data,
  github_pat = keyring::key_get("github_pat"),
  gov_repo_url = gov_repo_url
)

# --- Lead developer: one-time project setup ---
datom_init_repo(
  path = "my_project",
  project_name = "CLINICAL_DATA",
  store = store,
  create_repo = TRUE  # auto-creates GitHub data repo
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

### Local Backend Developer Workflow

```r
# Create store with local filesystem (no AWS credentials needed)
store <- datom_store(
  governance = datom_store_local(
    path = "/data/storage",
    prefix = "project-alpha/"
  ),
  data = datom_store_local(
    path = "/data/storage",
    prefix = "project-alpha/"
  ),
  github_pat = keyring::key_get("github_pat")
)

# Same workflow as S3 from here on
datom_init_repo(
  path = "my_project",
  project_name = "LOCAL_DATA",
  store = store,
  create_repo = TRUE
)

conn <- datom_get_conn("my_project", store = store)
datom_pull(conn)
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

# 2. Update ref.json to point to new data location
#    (add previous entry for old location with sunset date)

# 3. Update project.yaml with new bucket
conn <- datom_get_conn("my_project")

# 4. Sync dispatch to new location (interactive confirmation)
datom_sync_dispatch(conn)
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
│ 1. Resolve data location from ref.json (governance store)     │
│ 2. Read version_history.json from data store S3               │
│ 3. Lookup version (metadata_sha) → get data_sha                │
│ 4. Get dispatch method from dispatch.json                     │
│ 5. Download {data_sha}.parquet and {version}.json from S3      │
│ 6. Apply context-specific processing via dispatch              │
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
- `datom_sync_dispatch()` is the escape hatch: a full local → S3 push that's always safe to run.

**Key functions and their ordering:**

| Function | Order | Git failure behavior |
|----------|-------|---------------------|
| `datom_write()` | local → git → S3 | Hard error, S3 untouched |
| `.datom_sync_metadata()` | local → git → S3 | Hard error, S3 untouched |
| `datom_sync()` (per-table) | via `datom_write()` | Per above |
| `datom_sync()` (manifest) | local → git → S3 | Warning, S3 skipped |
| `datom_sync_dispatch()` | local → S3 only | N/A (recovery tool) |
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

### Credential Handling

Credentials are provided via `datom_store_s3()` objects and passed directly to `paws.storage::s3()` clients. No env var indirection or naming conventions — each `datom_conn` holds `client` (data store S3 client) and `gov_client` (governance store S3 client) created from the store’s credentials.

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

# Git remotes
repos:
  data:
    remote_url: https://github.com/org/clinical-data.git
  governance:
    remote_url: https://github.com/org/acme-gov.git
    local_path: /path/to/acme-gov

# Sync configuration
sync:
  continue_on_error: true
  parallel_uploads: 4

# Computational environment
renv: false  # renv integration deferred — see Deferred to v2
```

Local backend project.yaml:
```yaml
storage:
  governance:
    type: local
    root: /data/storage
    prefix: project-alpha/
  data:
    type: local
    root: /data/storage
    prefix: project-alpha/
```

**Secrets are never persisted.** The `type` field drives backend dispatch. The two-component structure (governance + data) allows routing files and data files to target different buckets/prefixes.

### projects/{project_name}/dispatch.json (governance repo)

Lives in the **governance repository** at `projects/{project_name}/dispatch.json` and mirrored to gov storage at the same key. Routes `datom_read()` to the appropriate language-specific function per context.

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

### projects/{project_name}/migration_history.json (governance repo)

Lives in the **governance repository** at `projects/{project_name}/migration_history.json` and mirrored to gov storage. Records location changes for the project:

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

- Credentials validated via store objects (`datom_store_s3()` runs `HeadBucket`)
- GITHUB_PAT presence determines developer vs reader role
- No env var naming conventions — credentials passed directly via store objects

### Project Structure Validation

- Verify `.datom/`, `.git/`, and `manifest.json` exist
- Validate `input_files/` is flat (no subdirectories)
- Called internally by all operations

### Dispatch Implementation

```r
datom_read <- function(name, version = NULL, context = NULL, conn = NULL, ...) {

  if (is.null(context)) context <- "default"

  # Read dispatch.json from S3 metadata
  dispatch_info <- .get_dispatch_from_s3(conn)

  # Get R method for the specified context
  r_methods <- dispatch_info$methods$r
  if (!context %in% names(r_methods)) {
    stop("Context '", context, "' not found for R")
  }

  func_name <- r_methods[[context]]
  func <- eval(parse(text = func_name))

  # Call with R conventions, forwarding extra parameters
  func(conn, name, version, ...)
}
```

### Storage Abstraction Layer

Business logic calls generic `.datom_storage_*()` functions that dispatch to backend-specific implementations based on `conn$backend`:

| Generic Function | S3 Implementation | Local Implementation | Purpose |
|---|---|---|---|
| `.datom_storage_upload()` | `.datom_s3_upload()` | `.datom_local_upload()` | Upload file to storage |
| `.datom_storage_download()` | `.datom_s3_download()` | `.datom_local_download()` | Download file from storage |
| `.datom_storage_exists()` | `.datom_s3_exists()` | `.datom_local_exists()` | Check if key exists |
| `.datom_storage_read_json()` | `.datom_s3_read_json()` | `.datom_local_read_json()` | Read JSON from storage |
| `.datom_storage_write_json()` | `.datom_s3_write_json()` | `.datom_local_write_json()` | Write JSON to storage |

The dispatch layer lives in `R/utils-storage.R`. Each function takes a `conn` (or governance sub-connection via `.datom_gov_conn()`) and a storage key. The `backend` field on `conn` determines which implementation is called via `switch(conn$backend, s3 = ..., local = ...)`.

Local backend functions live in `R/utils-local.R` and use `fs::` for all filesystem operations. Storage keys are resolved to full paths via `.datom_local_path(conn, key)` = `fs::path(conn$root, .datom_build_storage_key(conn$prefix, key))`.

Adding a new backend (e.g., GCS, Azure) requires:
1. Creating a new store constructor
2. Implementing the 5 backend functions
3. Adding a `switch()` case in each dispatch function
```

### Governance Repository Contract

The governance repository is a port surface. datom currently owns both gov and data writes; a planned companion package (working name `datomaccess` / `datomanager`) will eventually take over governance write operations. To make that handoff a port replacement rather than a refactor, all gov-write code lives behind a tagged seam.

**Seam location.** All gov-write helpers live in `R/utils-gov.R` and are tagged with `# GOV_SEAM:` comments. Any new gov-write code must go through this file and carry the marker. Gov-**read** helpers (`.datom_resolve_ref()`, `.datom_resolve_ref_from_clone()`, dispatch reads) are not seam-marked — datom always needs to read gov regardless of who writes it.

**Seam helper inventory:**

| Helper | Purpose |
|---|---|
| `.datom_gov_clone_init()` | Clone or open the gov repo at `gov_local_path`; validates remote URL on existing dirs. |
| `.datom_gov_commit()` | Stage + commit on the gov clone. |
| `.datom_gov_push()` | Push gov clone to remote (pull-before-push). |
| `.datom_gov_pull()` | Fetch + fast-forward gov clone. |
| `.datom_gov_write_dispatch()` | Write `projects/{name}/dispatch.json` to gov clone + storage. |
| `.datom_gov_write_ref()` | Write `projects/{name}/ref.json` to gov clone + storage. |
| `.datom_gov_register_project()` | Create `projects/{name}/` folder + initial files; commit + push. |
| `.datom_gov_unregister_project()` | Remove `projects/{name}/`; commit + push. |
| `.datom_gov_record_migration()` | Append to `projects/{name}/migration_history.json`; commit + push. |
| `.datom_gov_destroy()` | Tear down whole gov repo + storage. Refuses if registered projects exist unless `force = TRUE`. Sandbox-only today; companion will own the user-facing equivalent. |

**Commit message conventions (gov repo).** Stable contract — readers/auditors can grep history; the companion package must preserve these strings:

| Operation | Message format |
|---|---|
| `register_project` | `Register project {name}` |
| `unregister_project` | `Unregister project {name}` |
| `write_dispatch` | `Update dispatch for {name}` |
| `write_ref` | `Update ref for {name}` |
| `record_migration` | `Record migration for {name}: {summary}` |

**File initialization.** `.datom_gov_register_project()` creates `projects/{name}/` with three files: `dispatch.json` (default methods), `ref.json` (current data location), and `migration_history.json` (initialized as empty `[]`; appended to by `.datom_gov_record_migration()`).

**Migration ordering.** Migration events are prepended (most-recent-first) so the head of `migration_history.json` is the active record.

**Decommission scope matrix.** Three distinct teardown operations exist; their scopes do not overlap:

| Operation | Scope | Caller | Implementation |
|---|---|---|---|
| **Project decommission** | one project | datom public API | `datom_decommission(conn, confirm = "{name}")` |
| **Gov decommission** | whole gov repo + storage | future companion package | `.datom_gov_destroy()` (today: sandbox-only via `:::`) |
| **Sandbox teardown** | dev playground | `dev/dev-sandbox.R` | `sandbox_down(env, scope = c("all", "project", "gov"))` |

**Concurrency.** Two developers running `datom_sync_dispatch()` on the same project simultaneously could conflict on push. Phase 15 relies on git's standard pull-before-push discipline (built into `.datom_gov_push()`); explicit lock mechanism deferred (see Deferred to v2).

**Future companion package.** The companion package will own:
- The full gov lifecycle (init, register, unregister, destroy) as user-facing functions.
- CODEOWNERS automation on `projects/{name}/` for self-serve project ownership without a platform-team gatekeeper.
- Access-point provisioning (works with `datomaccess` for IAM-enforced reads).
- Concurrency primitives if needed (advisory locks on `projects/{name}/`).

datom will remain a client: reading gov state freely, writing only via the seam helpers — which the companion will replace with thin shims that delegate to its own implementations. **Do not** introduce a plugin/registry mechanism inside datom for this; the seam contract + tagged helpers are sufficient and avoid premature abstraction.

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

- `datom_conn` S3 class wraps project_name, root, prefix, region, client, gov_client, path, role, endpoint, backend
- `root`: storage root — S3 bucket name or local directory path (was `bucket` pre-Phase 12)
- `client`: S3 client for data store (NULL for local backend); `gov_client`: S3 client for governance store (NULL for local)
- `backend`: storage backend type (`"s3"` or `"local"`), used by `.datom_storage_*()` dispatch
- Two modes: **developer** (has local repo path + git) and **reader** (S3 only, no local repo)
- Role derived from composite store: `github_pat` present → developer; absent → reader
- `datom_get_conn(path = ...)` reads two-component `.datom/project.yaml` (developer path)
- `datom_get_conn(store = ..., project_name = ...)` builds connection from store (reader path)
- Credentials passed directly to `paws.storage::s3()` — no env var bridge
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
- Resolves data location from ref.json at governance store

**Operations**:
- Project structure check before all operations
- Input files directory must be flat (no subdirectories)
- File format support via rio::import
- Valid datom names (filesystem safe)
- File size check against configured limit
- Metadata sync verification after deployment

### Testing Coverage

- **Unit**: SHA computation (sorting optional, OFF by default for data; alphabetical for metadata), dispatch, metadata operations, ref.json resolution
- **Integration**: Full workflow, S3 metadata access, sync verification, migration scenarios
- **Edge cases**: Network failures, corrupt files, missing metadata, concurrent writes, ref.json migration warnings

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

- **Implemented**: AWS S3 (via `paws.storage`) and local filesystem (`datom_store_local()` via `fs`)
- **Planned**: Google Cloud Storage, Azure Blob Storage
- Architecture uses `.datom_storage_*()` dispatch layer keyed on `conn$backend`; adding a backend requires implementing 5 functions + a store constructor

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
- **Gov repo concurrency primitives**: Two developers running `datom_sync_dispatch()` simultaneously rely on git pull-before-push to resolve. Advisory locks on `projects/{name}/` (e.g., a short-lived lock file committed and removed) deferred until contention is observed.
- **CODEOWNERS automation on `projects/{name}/`**: Self-serve project ownership without a platform-team gatekeeper. Will live in the future governance companion package, not datom.
- **Companion governance package** (working name `datomaccess` / `datomanager`): Will own the full gov lifecycle (init, register, unregister, destroy) as user-facing functions and replace datom's `# GOV_SEAM:` helpers with thin shims. The seam contract (helper inventory + commit message conventions, see "Governance Repository Contract") is the port surface to preserve. Do not introduce a plugin/registry mechanism inside datom for this — the tagged seam is sufficient.
- **`datom_migrate_data()`**: Managed migration (data copy + ref.json update + `.datom_gov_record_migration()` invocation in one atomic operation). Deferred; today migration is manual (external `aws s3 sync` + `datom_sync_dispatch()`).

### Multi-Developer Collaboration (Implemented)

Team workflows are fully supported:

- **S3 namespace safety check** in `datom_init_repo()`: Verifies target S3 namespace is unoccupied before writing. `.force = TRUE` overrides for intentional takeover.
- **`project_name` in manifest.json**: Enables namespace collision detection. `datom_validate()` cross-checks manifest's `project_name` against `conn$project_name`.
- **`datom_pull()`**: Git pull (fetch + merge). Git is the source of truth for all metadata.
- **`datom_clone()`**: Wraps `git2r::clone()` + `datom_get_conn()` — the recommended way for teammates to join a repo.
- **Pull-before-push discipline**: `.datom_git_push()` auto-pulls before pushing. `.datom_check_git_current()` detects stale state at `datom_sync()` entry.
- **Vignettes**: the *Get Started* / *Scale Up* / *Govern* article track walks the team workflow end-to-end (start at *First Extract*; the *Second Engineer Joins* article covers pull-before-push and conflict recovery). *Credentials in Practice* is the credentials reference.

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
| Location | Stored in metadata | Explicit via ref.json at governance store |
| Migration | Manual | ref.json update + data copy |

---

## Summary

datom provides robust data versioning optimized for clinical data science workflows where reproducibility is paramount. Designed for analytical environments with many evolving tables (50-100+), datom makes version tracking seamless for datasets that are large in breadth but manageable in size.

**Key architectural decisions**:

1. Single read function (`datom_read()`) with routing for all access patterns
2. **datom version = metadata_sha**: uniquely identifies (data, metadata) pair
3. **Direct credential passing**: Store objects provide credentials directly to S3 clients — no env var indirection
4. Multi-language support via routing layer (R first, Python planned)
5. Storage agnostic design (S3 + local filesystem, extensible via `.datom_storage_*()` dispatch)
6. Optimized for clinical/scientific workflows with many tables
7. One repository per project with optional bucket prefix support
8. Deterministic SHA computation via alphabetical field sorting
9. Manual conflict resolution for rare concurrent write scenarios
10. Explicit data location via ref.json at governance store
11. project.yaml authoritative; dispatch.json and S3 metadata derived
12. Two-store architecture: governance (dispatch, ref, migration history) and data (manifest, tables)

This architecture keeps datom focused on core versioning while providing clear extension points for enterprise features. As part of the larger data product ecosystem (with dpbuild, dpdeploy, and dpi), datom serves as the foundational layer for reproducible analytical workflows.
