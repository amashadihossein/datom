# Phase 11: Routing Separation

## Goal

Replace redirect-chain resolution with single-indirection routing via `ref.json`. Rename `routing.json` → `dispatch.json`. Remove the env var credential bridge introduced in Phase 10. Establish an always-two-stores architecture: every datom project has a governance store and a data store.

## Motivation

datom is a serverless data ecosystem — there's no server to precompute or update paths when data moves. Runtime resolution is necessary, but the current approach (`.redirect.json` chains where each hop points to the next, potentially across buckets with different credentials) is the wrong pattern:

- Each hop requires credentials for that location
- Chains can break or go stale
- Migration means planting breadcrumbs across multiple buckets
- More hops = more latency and failure points

The fix is architecturally obvious: **separate where data lives from where the pointers are.** A governance store holds a `ref.json` that says where data is right now. One read, no chains, no multi-credential complexity.

This also enables:
- **Data mobility**: Data moves between buckets by updating one file at the governance address. No reader changes.
- **Organizational discovery**: The governance bucket is the well-known entry point for finding any study's data.
- **datom_ops compatibility**: Governance has routing (datom owns) + registry (datom_ops owns) in separate namespaces.

## Core Architectural Decision: Always Two Stores

Every datom project has exactly two stores: **governance** and **data**. No co-location in cloud mode.

### Why Two Stores Always

Governance and data have fundamentally different access patterns and sensitivity:

```
GOVERNANCE STORE:
  Contains: dispatch.json, ref.json, migration_history.json
  Sensitivity: NONE — pointers, config, audit trails only
  Access: Broad organizational read access
  Stability: Rarely moves, well-known address

DATA STORE:
  Contains: manifest.json, table metadata, parquet files
  Sensitivity: HIGH — actual study data
  Access: Restricted per project/role
  Stability: May move (reorg, cost, compliance)
```

Co-locating these creates a contradiction: either governance is locked down (breaking discoverability) or data is broadly accessible (breaking security). Keeping them separate eliminates this tension.

### Onboarding: Local Mode Is the Onramp

The cost of two stores depends on the backend:

```
Local mode:   two folders → trivial (mkdir, no provisioning)
Cloud mode:   two buckets → one extra step at a point where the
              user is already committed to cloud infrastructure
```

Users try datom locally first with two folders. If they like it, they set up cloud with two buckets. The concept is consistent at every level — two stores, always.

### The Onboarding Staircase

```
Level 0:  Two local folders + local git      → "I get versioning"
Level 1:  Two local folders + GitHub          → "My team can use this"
Level 2:  Two shared folders + GitHub         → "Team workflow on network drives"
Level 3:  Two S3 buckets + GitHub             → "Cloud production"
```

Every level has two stores. The only thing that changes is the backend type.

## Design Decisions

### Convention: One Project, One Backend, One Dispatch

A project is an organizational boundary. Routing and dispatch are **project-level**, not table-level. A project lives on one storage backend with one dispatch configuration. There is no use case for splitting a project across S3 and GCS, or having different dispatch methods for different tables within the same project.

This convention keeps the system simple and is enforced by file placement: `dispatch.json` and `ref.json` exist once per project at the governance address.

### Rename `routing.json` → `dispatch.json`

The file controls **method dispatch** (which function handles reads), not address routing. With actual routing (`ref.json`) being introduced, keeping both names would be confusing.

**Changes:**
- `.datom/routing.json` → `.datom/dispatch.json` (local repo)
- S3 key: `{prefix}/datom/.metadata/routing.json` → `{prefix}/datom/.metadata/dispatch.json`
- `datom_sync_routing()` → `datom_sync_dispatch()`
- All internal references, validation checks, tests, spec

### `ref.json` — Single-Indirection Data Location

Lives at the **governance store**. Replaces `.redirect.json`. Always present.

```json
{
  "current": {
    "bucket": "bucket-A",
    "prefix": "trial/",
    "region": "us-east-1"
  }
}
```

After a data migration:

```json
{
  "current": {
    "bucket": "bucket-B",
    "prefix": "trial/",
    "region": "us-east-1"
  },
  "previous": [
    {
      "bucket": "bucket-A",
      "prefix": "trial/",
      "deprecated_at": "2026-01-15",
      "sunset_at": "2026-07-15",
      "message": "Data migrated to bucket-B. Old routing will be removed after sunset date."
    }
  ]
}
```

**ref.json is always present** at the governance address. No "absent means co-located" special case. It always tells you where data is.

**Resolution logic** (`.datom_resolve_ref()`):
1. Read `ref.json` from governance store
2. `current` block gives the data location
3. Single read, no recursion, no chain-walking

**No credentials in ref.json.** The reader's data store provides credentials. ref.json resolves the address; the store provides the access. This keeps credential management separate from address resolution.

### Two-Store `project.yaml`

```yaml
# Cloud
storage:
  governance:
    type: s3
    bucket: org-governance
    prefix: med-mm-001/
    region: us-east-1
  data:
    type: s3
    bucket: bucket-A
    prefix: trial/
    region: us-east-1

# Local
storage:
  governance:
    type: local
    path: ~/datom-gov/med-mm-001
  data:
    type: local
    path: ~/datom-data/med-mm-001
```

No single-store fallback. No optional routing section. Two stores, always, at every level.

### Direct Credential Wiring (Remove Env Var Bridge)

Phase 10 introduced `.datom_install_store()` as a temporary bridge — injecting store credentials into `DATOM_{PROJECT}_*` env vars so existing S3 code worked unchanged. Phase 11 removes this indirection.

The env var naming convention (`DATOM_{PROJECT}_ACCESS_KEY_ID`, `_2`, `_3` suffixes) existed because redirect chains could land in different buckets needing different credentials. With two explicit stores replacing chains, that entire rationale disappears.

- `.datom_s3_client()` accepts credentials directly from the store object
- Remove `.datom_install_store()`
- Remove `.datom_derive_cred_names()`
- Remove `.datom_check_credentials()`
- `project.yaml` no longer stores `credentials.access_key_env` / `secret_key_env`

### What Lives Where

```
GOVERNANCE STORE (stable, lightweight, project-level):
  dispatch.json             ← method dispatch
  ref.json                  ← where data lives now (always present)
  migration_history.json    ← audit trail of moves

DATA STORE (movable, content-heavy):
  .metadata/
    manifest.json           ← catalog of tables
  .access/                  ← reserved for datom_ops (datom never writes here)
  {table_name}/
    {data_sha}.parquet
    .metadata/
      metadata.json
      {metadata_sha}.json
      version_history.json
```

### Namespace Ownership

```
{governance_store}/                      ← datom owns (dispatch, ref, migration_history)
{data_store}/datom/.metadata/            ← datom owns (manifest)
{data_store}/datom/{table_name}/         ← datom owns
{data_store}/datom/.access/              ← datom_ops owns (reserved, datom never touches)
{governance_store}/../registry/          ← datom_ops owns (future)
```

### Governance Store Principles

The governance store:
- Contains only pointers, config, and audit trails — **no sensitive data**
- Designed for broad organizational read access
- Write access restricted to domain owners / governance admins
- In cloud mode, typically one governance bucket shared across all studies
- In local mode, can be a single folder with per-project subfolders

### Dual-Routing During Data Migration

When data migrates from one location to another, maintain governance routing at **both** old and new governance addresses during a transition window.

**Important:** This is for the rare case where the governance address itself changes (e.g., migrating from local to cloud). Normal data migration (bucket-A → bucket-B) only requires updating `ref.json` at the existing governance address — no dual-routing needed.

```
BEFORE:
  Governance: bucket-gov-A
  Data:       bucket-A
  ref.json at bucket-gov-A says: data at bucket-A

DATA MIGRATION (common — just update ref.json):
  Governance: bucket-gov-A (unchanged)
  Data:       bucket-B (moved)
  ref.json at bucket-gov-A updated to: data at bucket-B
  → All readers resolve immediately. No dual routing needed.

GOVERNANCE MIGRATION (rare — full transition):
  Governance at bucket-gov-A:  ref.json → points to bucket-B + deprecation warning
  Governance at bucket-gov-B:  ref.json → points to bucket-B (canonical)
  Data:                        bucket-B only

  Old code → bucket-gov-A → ref.json → bucket-B → works (with deprecation warning)
  New code → bucket-gov-B → ref.json → bucket-B → works

AFTER SUNSET:
  Remove governance files from bucket-gov-A
  Everything at bucket-gov-B + bucket-B
```

The `previous` array in `ref.json` and the `sunset_at` field give users a concrete deadline. Code that resolves via the old governance address emits a `cli::cli_warn()` with the deprecation message and sunset date.

### What Happens When Data Credentials Are Stale After Migration

Reader has governance credentials (works) but old data credentials (stale after data moved to new bucket):

```r
# Resolution:
# 1. Read ref.json from governance store         ✅ works
# 2. ref.json says data is at bucket-B
# 3. Try to read from bucket-B with old creds    ❌ fails
# 4. Error:

cli::cli_abort(c(
  "Data for {.val {project_name}} has migrated to {.val {new_bucket}}.",
  "i" = "Migration recorded on {.val {deprecated_at}}.",
  "i" = "Your data store credentials don't have access to the new location.",
  "i" = "Update your data store for {.val {new_bucket}}."
))
```

The governance credential always works — the reader can always discover where data is. Only the data credential may be stale. The error is specific and actionable.

### Convention: Project-Level vs Table-Level Files

These files exist **once per project** — never inside a table folder:

| File | Level | Location |
|------|-------|----------|
| `dispatch.json` | Project | Governance store |
| `ref.json` | Project | Governance store |
| `migration_history.json` | Project | Governance store |
| `manifest.json` | Project | Data store (`.metadata/`) |

These files exist **per table** — never at the project level:

| File | Level | Location |
|------|-------|----------|
| `metadata.json` | Table | `{table_name}/.metadata/` |
| `{metadata_sha}.json` | Table | `{table_name}/.metadata/` |
| `version_history.json` | Table | `{table_name}/.metadata/` |
| `{data_sha}.parquet` | Table | `{table_name}/` |

**Rule**: Never create dispatch.json, ref.json, or migration_history.json inside a table folder. Never create metadata.json or version_history.json at the project level.

### Convention: Folder Structure as Cross-Language Contract

The directory layout is a **spec-level contract**, not an R implementation detail. R-datom and Python-datom must produce and consume the same layout. Any change to the layout is a breaking change that requires a spec version bump.

The layout diagrams in this doc and in `datom_specification.md` are normative — they define behavior, not just document it.

### Constructor Signatures

```r
# Cloud — two S3 stores
conn <- datom_get_conn(
  governance = datom_store(type = "s3", bucket = "org-gov", prefix = "med-mm-001/", ...),
  data = datom_store(type = "s3", bucket = "bucket-A", prefix = "trial/", ...),
  project_name = "med_mm_001"
)

# Local — two folder stores
conn <- datom_get_conn(
  governance = datom_store(type = "local", path = "~/datom-gov/med-mm-001"),
  data = datom_store(type = "local", path = "~/datom-data/med-mm-001"),
  project_name = "med_mm_001"
)

# Developer — reads two-store config from project.yaml
conn <- datom_get_conn(path = "my_project")
```

Two stores, always. The store type (local vs s3) can differ between governance and data in principle, but the convention is to use the same backend type for both.

## Chunks

### Chunk 1: Rename `routing.json` → `dispatch.json`

**Files**: `R/init.R`, `R/sync.R`, `R/validate.R`, `inst/templates/`, tests

- Rename local file: `.datom/routing.json` → `.datom/dispatch.json`
- Rename S3 key references
- Rename `datom_sync_routing()` → `datom_sync_dispatch()` (export + all callers)
- Update `datom_repository_check()` / validation to look for `dispatch.json`
- Update template
- Update all tests
- Pure rename — no behavior change

### Chunk 2: Direct Credential Wiring

**Files**: `R/s3.R`, `R/credentials.R`, `R/conn.R`, `R/init.R`, tests

- Refactor `.datom_s3_client()` to accept `access_key` and `secret_key` directly (from store on conn)
- Update `.datom_get_conn_developer()` and `.datom_get_conn_reader()` to pass credentials from store
- Remove `.datom_install_store()` bridge
- Remove `.datom_derive_cred_names()`
- Remove `.datom_check_credentials()`
- Remove `storage.credentials.*_env` from `project.yaml` template
- Update all tests

**Why this belongs here**: The env var naming convention (`DATOM_{PROJECT}_*` with `_2`, `_3` suffixes) existed because redirect chains could land in different buckets needing different credentials. With two explicit stores replacing chains, that entire rationale disappears. This is a direct consequence of the routing redesign.

### Chunk 3: Two-Store Architecture

**Files**: `R/conn.R`, `R/init.R`, `R/store.R` (new), tests

- Implement `datom_store()` constructor — creates a store object (type, bucket/path, prefix, region, credentials)
- Support `type = "s3"` and `type = "local"` backends
- Update `datom_get_conn()` to accept `governance` and `data` store params
- Update `datom_get_conn(path = ...)` to parse two-store config from project.yaml
- Update `project.yaml` schema to `storage.governance` + `storage.data` structure
- Update `datom_init_repo()` to accept and write two-store config
- Governance store gets: dispatch.json, migration_history.json
- Data store gets: manifest.json, table data and metadata
- Remove single-store / co-located code paths
- Tests for local and S3 store types

### Chunk 4: `ref.json` + `.datom_resolve_ref()`

**Files**: `R/s3.R` (or `R/routing.R`), `R/conn.R`, tests

- `ref.json` always present at governance store — created by `datom_init_repo()`
- `.datom_resolve_ref(governance_store)` — reads `ref.json`, returns data location
- Remove `.datom_s3_resolve_redirect()` and `.redirect.json` support
- Update `datom_get_conn()` to resolve data location via ref
- Deprecation warning when `ref.json` has a `previous` entry with message
- Stale credential error handling (governance resolves but data 403s)
- Tests for normal resolution, post-migration resolution, stale credential error

### Chunk 5: Convention Codification + Spec Update

**Files**: `dev/datom_specification.md`, `.github/copilot-instructions.md`

- Document always-two-stores architecture in spec
- Document project-level vs table-level file rules
- Document folder structure as cross-language contract
- Document namespace ownership (datom vs datom_ops)
- Document governance store accessibility principle
- Document one-project-one-backend convention
- Update all S3 storage structure diagrams
- Update onboarding staircase (local → shared → cloud)

### Chunk 6: Sandbox, E2E, Documentation

**Files**: `dev/dev-sandbox.R`, `dev/e2e-test.R`, vignettes, roxygen

- Update sandbox tooling for two-store architecture
- E2E test: local two-folder path (vignette scenario)
- E2E test: S3 two-bucket path (production scenario)
- E2E test: data migration (update ref.json, verify resolution)
- Update vignettes (getting-started with local, upgrading to cloud)
- `devtools::document()`, `devtools::check()`

## Acceptance Criteria

- [ ] `routing.json` renamed to `dispatch.json` everywhere (local, S3, code, tests)
- [ ] `datom_sync_routing()` renamed to `datom_sync_dispatch()`
- [ ] `.datom_s3_client()` accepts direct credentials, no env var indirection
- [ ] `.datom_install_store()`, `.datom_derive_cred_names()`, `.datom_check_credentials()` removed
- [ ] `.datom_s3_resolve_redirect()` and `.redirect.json` removed
- [ ] `datom_store()` constructor works for `type = "s3"` and `type = "local"`
- [ ] `datom_get_conn()` accepts `governance` and `data` store params
- [ ] `project.yaml` uses `storage.governance` + `storage.data` structure
- [ ] `ref.json` always present at governance store, created by `datom_init_repo()`
- [ ] `.datom_resolve_ref()` reads `ref.json` (single read, no recursion)
- [ ] Deprecation warning emitted when data resolved via old governance routing copy
- [ ] Stale data credentials produce clear, actionable error message
- [ ] Namespace conventions documented in spec
- [ ] Full test suite passes, count ≥ Phase 10 final count
- [ ] E2E workflow succeeds for local and S3 paths

## Status

| Chunk | Status | Notes |
|-------|--------|-------|
| 1 | not started | |
| 2 | not started | |
| 3 | not started | |
| 4 | not started | |
| 5 | not started | |
| 6 | not started | |

## Dependencies

- Phase 10 complete (store object on conn, `.datom_install_store()` bridge in place)
- No new package dependencies expected
