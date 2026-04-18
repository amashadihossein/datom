# Phase 11: Routing Separation

## Goal

Replace redirect-chain resolution with single-indirection routing via `ref.json` at a stable address. Rename `routing.json` → `dispatch.json`. Remove the env var credential bridge introduced in Phase 10 by wiring store credentials directly through the S3 client. Establish project-level conventions for routing and dispatch.

## Motivation

datom is a serverless data ecosystem — there's no server to precompute or update paths when data moves. Runtime resolution is necessary, but the current approach (`.redirect.json` chains where each hop points to the next, potentially across buckets with different credentials) is the wrong pattern:

- Each hop requires credentials for that location
- Chains can break or go stale
- Migration means planting breadcrumbs across multiple buckets
- More hops = more latency and failure points

The fix is architecturally obvious: **separate where data lives from where the pointers are.** A single stable routing address holds a `ref.json` that says where data is right now. One read, no chains, no multi-credential complexity.

This also enables:
- **Data mobility**: Data moves between buckets (reorg, cost, compliance) by updating one file at the routing address. No reader changes.
- **Organizational discovery**: A governance bucket becomes the well-known entry point for finding any study's data.
- **datom_ops compatibility**: Governance bucket has routing (datom owns) + registry (datom_ops owns) in separate namespaces, designed so datom_ops won't require changes to datom.

## Design Decisions

### Convention: One Project, One Backend, One Dispatch

A project is an organizational boundary. Routing and dispatch are **project-level**, not table-level. A project lives on one storage backend with one dispatch configuration. There is no use case for splitting a project across S3 and GCS, or having different dispatch methods for different tables within the same project.

This convention keeps the system simple and is enforced by file placement: `dispatch.json` and `ref.json` exist once per project at the routing address.

### Rename `routing.json` → `dispatch.json`

The file controls **method dispatch** (which function handles reads), not address routing. With actual routing (`ref.json`) being introduced, keeping both names would be confusing.

**Changes:**
- `.datom/routing.json` → `.datom/dispatch.json` (local repo)
- `{prefix}/datom/.metadata/routing.json` → `{prefix}/datom/.metadata/dispatch.json` (S3)
- `datom_sync_routing()` → `datom_sync_dispatch()`
- All internal references, validation checks, tests, spec

### `ref.json` — Single-Indirection Data Location

Lives at the **routing address**. Replaces `.redirect.json`.

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

**When routing and data are co-located (default):** `ref.json` is absent — implies "data is right here." No overhead for the simple case.

**When data moves:** Create/update `ref.json` at the routing address. One file change.

**Resolution logic** (`.datom_resolve_ref()`):
1. Check routing address for `ref.json`
2. If absent → data is at the routing address (co-located)
3. If present → `current` block gives the data location
4. Single read, no recursion, no chain-walking

### Routing/Data Separation in `project.yaml`

```yaml
# Simple case (co-located — current behavior, nothing extra needed)
storage:
  type: s3
  bucket: med-mm-001
  prefix: trial/
  region: us-east-1

# Separated routing (opt-in)
storage:
  type: s3
  bucket: med-mm-001
  prefix: trial/
  region: us-east-1
  routing:
    bucket: org-governance
    prefix: med-mm-001/
    region: us-east-1
```

When `storage.routing` is absent → routing files live with the data (co-located).
When `storage.routing` is present → `dispatch.json`, `ref.json`, `migration_history.json` are read/written from the routing address.

### Direct Credential Wiring (Remove Env Var Bridge)

Phase 10 introduced `.datom_install_store()` as a temporary bridge — injecting store credentials into `DATOM_{PROJECT}_*` env vars so existing S3 code worked unchanged. Phase 11 removes this indirection:

- `.datom_s3_client()` accepts credentials directly from the store/conn object
- Remove `.datom_install_store()`
- Remove `.datom_derive_cred_names()`
- Remove `.datom_check_credentials()`
- `project.yaml` no longer stores `credentials.access_key_env` / `secret_key_env`

### What Lives Where

```
ROUTING ADDRESS (stable, lightweight, project-level):
  dispatch.json             ← method dispatch
  ref.json                  ← where data lives now (absent if co-located)
  migration_history.json    ← audit trail of moves

DATA ADDRESS (movable, content-heavy):
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
{routing_address}/                  ← datom owns (dispatch, ref, migration_history)
{data_address}/datom/.metadata/     ← datom owns (manifest)
{data_address}/datom/{table_name}/  ← datom owns
{data_address}/datom/.access/       ← datom_ops owns (reserved, datom never touches)
{governance}/registry/              ← datom_ops owns (future)
```

### Governance Bucket Principles

When routing is separated into an organizational governance bucket:
- Contains only pointers, config, and audit trails — **no sensitive data**
- Designed for broad organizational read access
- Write access restricted to domain owners / governance admins
- Readers need governance read + their authorized data bucket credentials

### Dual-Routing During Transitions

When data migrates from one location to another, maintain routing at **both** old and new locations during a transition window:

```
BEFORE:
  Routing + Data: bucket-A

DURING TRANSITION:
  Routing at bucket-A:  ref.json → points to bucket-B + deprecation warning
  Routing at bucket-B:  ref.json → points to bucket-B (canonical, or absent if co-located)
  Data:                 bucket-B only

  Old code → bucket-A routing → ref.json → bucket-B → works (with deprecation warning)
  New code → bucket-B routing → bucket-B data → works

AFTER SUNSET:
  Remove routing from bucket-A
  Everything at bucket-B
```

The `previous` array in `ref.json` and the `sunset_at` field give users a concrete deadline. Code that resolves via the old routing address emits a `cli::cli_warn()` with the deprecation message and sunset date.

This is how old code keeps working during migration without redirect chains — the old location's routing files are a **copy**, not a hop.

### Convention: Project-Level vs Table-Level Files

These files exist **once per project** at the routing or data address — never inside a table folder:

| File | Level | Location |
|------|-------|----------|
| `dispatch.json` | Project | Routing address |
| `ref.json` | Project | Routing address |
| `migration_history.json` | Project | Routing address |
| `manifest.json` | Project | Data address (`.metadata/`) |

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

This means the layout diagrams in this doc and in `datom_specification.md` are normative — they define behavior, not just document it.

### Credentials in `ref.json` — Design Note

`ref.json` intentionally carries **no credentials**. The reader's store object already holds credentials for the data bucket they're authorized to access. `ref.json` resolves the *address*; the store provides the *access*. Putting credential metadata in `ref.json` would leak information into the governance bucket and couple address resolution to credential management.

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

**Why this belongs here**: The env var naming convention (`DATOM_{PROJECT}_*`) exists because redirect chains could land in different buckets needing different credentials — env var names had to be derivable per-hop. With `ref.json` replacing chains, that entire rationale disappears. This chunk is a direct consequence of the routing redesign. It is self-contained and can be done independently of chunks 3–4, but it is squarely Phase 11 work.

### Chunk 3: `ref.json` + `.datom_resolve_ref()`

**Files**: `R/s3.R` (or new `R/routing.R`), `R/conn.R`, tests

- `.datom_resolve_ref(routing_address)` — reads `ref.json`, returns data location (or routing address if absent)
- Remove `.datom_s3_resolve_redirect()` and `.redirect.json` support
- Update `datom_get_conn()` to resolve data location via ref before building conn
- Create `ref.json` in `datom_init_repo()` only when routing is separated
- Tests for co-located (no ref.json) and separated (ref.json present) cases

### Chunk 4: `storage.routing` in `project.yaml`

**Files**: `R/init.R`, `R/conn.R`, `R/sync.R`, tests

- Parse optional `storage.routing` section in `project.yaml`
- When present: dispatch.json, ref.json, migration_history.json read/written from routing address
- When absent: routing files live with data (current behavior)
- `datom_init_repo()` accepts routing config on the store (or as param) and writes it to project.yaml
- `datom_sync_dispatch()` targets routing address; manifest sync targets data address
- Tests for both co-located and separated paths

### Chunk 5: Convention Codification + Spec Update

**Files**: `dev/datom_specification.md`, `.github/copilot-instructions.md`

- Document project-level vs table-level file rules in spec
- Document folder structure as cross-language contract
- Document namespace ownership (datom vs datom_ops)
- Document governance bucket accessibility principle
- Document one-project-one-backend convention
- Update S3 storage structure diagrams

### Chunk 6: Sandbox, E2E, Documentation

**Files**: `dev/dev-sandbox.R`, `dev/e2e-test.R`, vignettes, roxygen

- Update sandbox tooling for new file names and routing
- E2E test: co-located path (primary — this is what real users do today)
- E2E test: separated routing path (scaffolded, validates the plumbing)
- Update vignettes (credentials, getting-started)
- `devtools::document()`, `devtools::check()`

## Acceptance Criteria

- [ ] `routing.json` renamed to `dispatch.json` everywhere (local, S3, code, tests)
- [ ] `datom_sync_routing()` renamed to `datom_sync_dispatch()`
- [ ] `.datom_s3_client()` accepts direct credentials, no env var indirection
- [ ] `.datom_install_store()`, `.datom_derive_cred_names()`, `.datom_check_credentials()` removed
- [ ] `.datom_s3_resolve_redirect()` and `.redirect.json` removed
- [ ] `.datom_resolve_ref()` reads `ref.json` from routing address (single read, no recursion)
- [ ] `project.yaml` supports optional `storage.routing` section
- [ ] Co-located case works (ref.json absent → data at routing address)
- [ ] Separated routing case works (ref.json present → data at different address)
- [ ] Deprecation warning emitted when data resolved via old routing copy (dual-routing transition path)
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

- Phase 10 complete (store object on conn, `.datom_install_store()` bridge in place)
- No new package dependencies expected
