# Phase 11: Routing Separation

## Goal

Replace redirect-chain resolution with single-indirection routing via `ref.json` at the governance store. Rename `routing.json` → `dispatch.json`. Remove the env var credential bridge by wiring store credentials directly through the S3 client. Wire the two-component store (governance + data) introduced in Phase 10 to their respective file responsibilities.

## Motivation

datom is a serverless data ecosystem — there's no server to precompute or update paths when data moves. Runtime resolution is necessary, but the current approach (`.redirect.json` chains where each hop points to the next, potentially across buckets with different credentials) is the wrong pattern:

- Each hop requires credentials for that location
- Chains can break or go stale
- Migration means planting breadcrumbs across multiple buckets
- More hops = more latency and failure points

The fix: **separate where data lives from where the pointers are.** The governance component of the store holds a `ref.json` that says where data is right now. One read, no chains, no multi-credential complexity.

This also enables:
- **Data mobility**: Data moves between buckets by updating one file at the governance address. No reader changes.
- **Organizational discovery**: The governance bucket is the well-known entry point for finding any study's data.
- **datom_ops compatibility**: Governance has routing (datom owns) + registry (datom_ops owns) in separate namespaces, designed so datom_ops won't require changes to datom.

## Prerequisites from Phase 10

Phase 10 delivers:
- `datom_store_s3()` — type-specific component constructor (validates credentials, bucket access)
- `datom_store(governance, data)` — composite store with two components
- Two-component store wired through `datom_init_repo()`, `datom_get_conn()`, `datom_clone()`
- `project.yaml` with `storage.governance` + `storage.data` structure
- `.datom_install_store()` — temporary env var bridge (to be removed here)
- GitHub repo auto-creation

Phase 11 builds on this foundation — the store shape is stable, we're wiring it to routing responsibilities and removing internal plumbing.

## Design Decisions

### Convention: One Project, One Backend, One Dispatch

A project is an organizational boundary. Routing and dispatch are **project-level**, not table-level. A project lives on one storage backend with one dispatch configuration.

Enforced by file placement: `dispatch.json` and `ref.json` exist once per project at the governance address.

### Rename `routing.json` → `dispatch.json`

The file controls **method dispatch** (which function handles reads), not address routing. With actual routing (`ref.json`) being introduced, keeping both names would be confusing.

**Changes:**
- `.datom/routing.json` → `.datom/dispatch.json` (local repo)
- S3 key: `{prefix}/datom/.metadata/routing.json` → governance store key for `dispatch.json`
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

**ref.json is always present** at the governance address — no "absent means co-located" special case. It always tells you where data is.

**Resolution logic** (`.datom_resolve_ref()`):
1. Read `ref.json` from governance store
2. `current` block gives the data location
3. Single read, no recursion, no chain-walking

**No credentials in ref.json.** The data store component provides credentials. ref.json resolves the address; the store provides the access.

### Direct Credential Wiring (Remove Env Var Bridge)

The env var naming convention (`DATOM_{PROJECT}_ACCESS_KEY_ID` with `_2`, `_3` suffixes) existed because redirect chains could land in different buckets needing different credentials — env var names had to be derivable per-hop. With two explicit store components replacing chains, that entire rationale disappears.

- `.datom_s3_client()` accepts credentials directly from the store component
- Remove `.datom_install_store()`
- Remove `.datom_derive_cred_names()`
- Remove `.datom_check_credentials()`

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

### Dual-Routing During Governance Migration

**Normal data migration** (common): Data moves from bucket-A to bucket-B. Update `ref.json` at the existing governance address. All readers resolve immediately. No dual-routing needed.

**Governance migration** (rare): The governance address itself changes. Maintain routing at **both** old and new governance addresses during a transition window:

```
DURING TRANSITION:
  Governance at old-gov:  ref.json → points to bucket-B + deprecation warning
  Governance at new-gov:  ref.json → points to bucket-B (canonical)
  Data:                   bucket-B only

  Old code → old-gov → ref.json → bucket-B → works (with cli::cli_warn())
  New code → new-gov → ref.json → bucket-B → works

AFTER SUNSET:
  Remove governance files from old-gov
```

The `previous` array and `sunset_at` field give users a concrete deadline.

### Stale Data Credentials After Migration

When a reader's governance credentials work but data credentials are stale (data moved to a new bucket they don't have access to):

1. Read `ref.json` from governance store — ✅ works
2. `ref.json` says data is at bucket-B
3. Try to read from bucket-B with old creds — ❌ 403
4. Actionable error: tells user the data migrated, when, and to update their data store credentials

Governance always resolves. Only data credentials can go stale. The error is specific.

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

- Refactor `.datom_s3_client()` to accept `access_key` and `secret_key` directly (from store component on conn)
- Update `.datom_get_conn_developer()` and `.datom_get_conn_reader()` to pass credentials from store
- Remove `.datom_install_store()` bridge
- Remove `.datom_derive_cred_names()`
- Remove `.datom_check_credentials()`
- Update all tests

**Why this belongs here**: The env var naming convention existed because redirect chains could land in different buckets needing different credentials per-hop. With two explicit store components replacing chains, that entire rationale disappears. Direct consequence of the routing redesign.

### Chunk 3: Wire Governance Store to Routing Files (dispatch + migration_history)

**Files**: `R/init.R`, `R/sync.R`, `R/conn.R`, tests

- `datom_init_repo()` writes dispatch.json and migration_history.json to governance store (not data store)
- `datom_init_repo()` writes manifest.json to data store
- `datom_sync_dispatch()` targets governance store; manifest sync targets data store
- `datom_get_conn()` reads dispatch.json from governance store
- Tests verifying files land in the correct store component
- **Note**: ref.json is NOT created in this chunk — that's Chunk 4

### Chunk 4: `ref.json` + `.datom_resolve_ref()`

**Files**: `R/routing.R` (new), `R/conn.R`, `R/init.R`, tests

- `ref.json` always present at governance store — created by `datom_init_repo()`
- Initial content mirrors the data store component from the composite store:
  ```json
  {
    "current": {
      "bucket": "study-bucket",
      "prefix": "trial/",
      "region": "us-east-1"
    }
  }
  ```
- `.datom_resolve_ref(governance_store)` — reads `ref.json`, returns data location
- Remove `.datom_s3_resolve_redirect()` and `.redirect.json` support
- Deprecation warning when `ref.json` has `previous` entries with message
- Stale credential error handling (governance resolves but data 403s → actionable error)
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

### Chunk 6: Sandbox, E2E, Documentation

**Files**: `dev/dev-sandbox.R`, `dev/e2e-test.R`, vignettes, roxygen

- Update sandbox tooling for dispatch.json naming and governance/data split
- E2E test: two-bucket S3 path (governance + data)
- E2E test: data migration (manually write updated ref.json to simulate migration, verify resolution + deprecation warning)
- Update vignettes (credentials, getting-started)
- `devtools::document()`, `devtools::check()`

## Acceptance Criteria

- [ ] `routing.json` renamed to `dispatch.json` everywhere (local, S3, code, tests)
- [ ] `datom_sync_routing()` renamed to `datom_sync_dispatch()`
- [ ] `.datom_s3_client()` accepts direct credentials, no env var indirection
- [ ] `.datom_install_store()`, `.datom_derive_cred_names()`, `.datom_check_credentials()` removed
- [ ] `.datom_s3_resolve_redirect()` and `.redirect.json` removed
- [ ] Governance store receives dispatch.json, ref.json, migration_history.json
- [ ] Data store receives manifest.json, table data and metadata
- [ ] `ref.json` always present at governance store, created by `datom_init_repo()`
- [ ] `.datom_resolve_ref()` reads `ref.json` (single read, no recursion)
- [ ] Deprecation warning emitted when ref.json has previous entries
- [ ] Stale data credentials produce clear, actionable error message
- [ ] Namespace conventions documented in spec
- [ ] Full test suite passes, count ≥ Phase 10 final count
- [ ] E2E workflow succeeds

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

- Phase 10 complete (`datom_store_s3()`, `datom_store(governance, data)`, two-component project.yaml, `.datom_install_store()` bridge in place)
- No new package dependencies expected

## Out of Scope

- **Local store backend** (`datom_store_local()`) — deferred to Phase 12. Enables the onboarding staircase (local folders → cloud buckets) and is prioritized over other future backends (GCS, Azure).
- **datom_ops implementation** — namespace ownership is documented but datom_ops code is a separate package.
