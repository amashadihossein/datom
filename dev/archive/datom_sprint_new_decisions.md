# datom Architecture Sprint — New Decisions

> **Context**: Lineage (parents in metadata, datom_get_parents, endpoint override)
> has already been communicated and factored into the current codebase.
> This document covers only the NEW architectural decisions from the latest review.

---

## Decision 1: Rename routing.json → dispatch.json

### The Gist

`routing.json` is a misleading name. It controls **method dispatch** (which function handles reads), not address routing. Rename it to `dispatch.json` to free "routing" for its natural meaning — address resolution.

### Why Now

With the tbit → datom rename already in progress, this is a clean moment to fix the name. Additionally, the new routing/data separation (Decision 2) introduces actual address routing via `ref.json`. Having both "routing.json" and "ref.json" would be confusing.

### What the File Does (Unchanged)

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

It answers: "When someone reads a datom, which function handles it?"

### What to Change

**File renames:**
- `.datom/routing.json` → `.datom/dispatch.json` (local repo)
- `{prefix}/datom/.metadata/routing.json` → `{prefix}/datom/.metadata/dispatch.json` (S3)

**Code references to update:**
- `datom_init_repo()` — create `dispatch.json` instead of `routing.json`
- `datom_sync_routing()` — rename to `datom_sync_dispatch()` (or generalize — see Decision 2 note below)
- `is_valid_datom_repo()` / `datom_repository_check()` — check for `dispatch.json`
- Any internal functions that read/write routing.json
- Spec: all references to routing.json → dispatch.json
- Tests: all references

**Note on `datom_sync_routing()`:** This function currently syncs routing.json + manifest + migration_history to S3. With the routing/data separation (Decision 2), its scope changes — see Decision 2 for how this function evolves.

---

## Decision 2: Separate Routing Address from Data Address

### The Gist

Give routing metadata (dispatch, data location, migration history) its own **stable address** that is independent from where data physically lives. Data can move without routing needing to move. The current co-located layout becomes the default simple case, not the only option.

### The Core Idea

Routing has its own address. Data has its own address. They **may** be the same (simple case) or **may** differ (enterprise case). The current design is a special case where they happen to be equal.

```
Simple case (default — nothing changes for current users):

  Routing address = s3://bucket-A/proj/datom/.metadata/
  Data address    = s3://bucket-A/proj/datom/
  Same bucket. Same as today.


Enterprise case (opt-in):

  Routing address = s3://org-governance/med-mm-001/
  Data address    = s3://bucket-B/trial/datom/
  Different buckets. Routing stays put. Data can move freely.
```

### Why This Is Better Than .redirect.json Chains

The current spec has `.redirect.json` — a chain of hops where each old location points to the next. Problems with chains:

- Reader needs credentials for every hop in the chain
- Chains can get stale or break
- Migration means planting breadcrumbs across multiple buckets
- More hops = more latency

The new design: **one file (`ref.json`) at a stable location tells you where data is right now.** No chains. No hops. One read.

### New File: ref.json

Lives at the **routing address**. Replaces `.redirect.json`.

```json
{
  "current": {
    "bucket": "bucket-B",
    "prefix": "trial/",
    "region": "us-east-1",
    "credentials": {
      "access_key_env": "DATOM_MED_MM_001_ACCESS_KEY_ID",
      "secret_key_env": "DATOM_MED_MM_001_SECRET_ACCESS_KEY"
    }
  },
  "previous": [
    {
      "bucket": "bucket-A",
      "prefix": "trial/",
      "deprecated_at": "2026-01-15",
      "sunset_at": "2026-07-15",
      "message": "Data migrated to bucket-B. Update your connection."
    }
  ]
}
```

**When routing and data are co-located:** `ref.json` is either absent (implying "data is right here") or self-referencing. No overhead.

**When data moves:** Update `ref.json` at the routing address. One file change, done.

### Dual-Routing During Transitions

During migration, maintain routing at **both** old and new locations for backward compatibility:

```
BEFORE:
  Routing + Data: bucket-A

DURING TRANSITION:
  Routing at bucket-A:  ref.json → points to bucket-B + deprecation warning
  Routing at bucket-B:  ref.json → points to bucket-B (canonical)
  Data:                 bucket-B only

  Old code → bucket-A routing → directed to bucket-B → works (with warning)
  New code → bucket-B routing → bucket-B data → works

AFTER SUNSET:
  Remove routing from bucket-A
  Everything at bucket-B
```

No broken reads during transition. Deprecation warnings guide users to update.

### What Lives Where

```
ROUTING ADDRESS (stable, lightweight):
  dispatch.json             ← method dispatch
  ref.json                  ← where data lives now
  migration_history.json    ← audit trail of moves

DATA ADDRESS (movable, content-heavy):
  .metadata/
    manifest.json           ← catalog of what tables exist
  .access/                  ← reserved for datom_ops
  {table_name}/
    {data_sha}.parquet
    .metadata/
      metadata.json
      {metadata_sha}.json
      version_history.json
```

**Why manifest stays with data:** Manifest changes on every write. If it lived at the routing address (potentially a different bucket), every `datom_write()` would need a cross-bucket write. Manifest describes what's physically in the data store — it belongs with the data.

### What to Change in project.yaml

Add optional `routing` section under `storage`:

```yaml
# Simple case (routing co-located — current behavior, no change needed)
storage:
  type: s3
  bucket: med-mm-001
  prefix: trial/
  region: us-east-1
  credentials:
    access_key_env: "DATOM_MED_MM_001_ACCESS_KEY_ID"
    secret_key_env: "DATOM_MED_MM_001_SECRET_ACCESS_KEY"

# Separated routing (opt-in for enterprise)
storage:
  type: s3
  bucket: med-mm-001
  prefix: trial/
  region: us-east-1
  routing:
    bucket: org-governance
    prefix: med-mm-001/
  credentials:
    access_key_env: "DATOM_MED_MM_001_ACCESS_KEY_ID"
    secret_key_env: "DATOM_MED_MM_001_SECRET_ACCESS_KEY"
```

When `storage.routing` is absent → routing is at the data address (current behavior).
When `storage.routing` is present → routing is fetched from there instead.

### Code Changes

**Replace redirect chain with ref resolution:**
- Remove `.datom_s3_resolve_redirect()` (chain walker)
- Remove `.redirect.json` from spec and code
- Add `.datom_resolve_ref()` — reads `ref.json` from routing address, returns current data location. Single read, no recursion.

**Update connection builders:**
- `datom_get_conn()` — when `storage.routing` exists in project.yaml, fetch dispatch.json and ref.json from routing location, then resolve data location from ref.json
- `.datom_get_conn_reader()` — same: check routing location first for ref.json

**Update datom_init_repo():**
- Create `ref.json` alongside `dispatch.json` at the routing location
- For simple case, both go in the data bucket under `.metadata/`

**Evolve datom_sync_routing() → datom_sync_meta()** (or similar):
- Currently syncs routing.json + manifest + migration_history to S3
- New scope: syncs dispatch.json + ref.json + migration_history to routing address, AND manifest to data address
- Or split into two functions: `datom_sync_dispatch()` (routing address) and existing manifest sync (data address)

### S3 Storage Structure (Complete, Updated)

**Co-located (simple case, default):**

```
{bucket}/{prefix}/datom/
├── .access/                        # Reserved for datom_ops
├── .metadata/
│   ├── dispatch.json               # Was: routing.json
│   ├── ref.json                    # NEW (absent or self-ref when co-located)
│   ├── manifest.json
│   └── migration_history.json
└── {table_name}/
    ├── {data_sha}.parquet
    └── .metadata/
        ├── metadata.json
        ├── {metadata_sha}.json
        └── version_history.json
```

**Separated (enterprise case):**

```
ROUTING: {routing_bucket}/{routing_prefix}/
├── dispatch.json
├── ref.json                        # Points to data location
└── migration_history.json

DATA: {data_bucket}/{data_prefix}/datom/
├── .access/                        # Reserved for datom_ops
├── .metadata/
│   └── manifest.json
└── {table_name}/
    ├── {data_sha}.parquet
    └── .metadata/
        ├── metadata.json
        ├── {metadata_sha}.json
        └── version_history.json
```

### Connection to datom_ops (Future)

The access management registry also needs a stable location. When routing is separated, the registry and routing can share a home:

```
s3://org-governance/
├── registry/                       # datom_ops: roles, grants, sources
└── routing/
    ├── med-mm-001/                 # routing for study 001
    │   ├── dispatch.json
    │   ├── ref.json
    │   └── migration_history.json
    └── med-mm-002/                 # routing for study 002
        └── ...
```

The registry's `sources` table and `ref.json` express overlapping information (where is each study's data?). They may converge when datom_ops is built. For now, just designing for compatibility.

---

## Decision 3: Explicit Storage Conventions

### The Gist

Several structural conventions are currently implicit. They need to be made explicit in the spec so that both R and Python implementations conform, and so Copilot/AI tools don't accidentally violate them.

### Convention 3a: Project-Level vs Table-Level Files

These files exist **once per project**, not per table:

```
PROJECT-LEVEL (one per datom project):
  dispatch.json             ← method dispatch for all tables
  ref.json                  ← one data location for the whole project
  migration_history.json    ← project-level migration audit trail
  manifest.json             ← catalog of all tables

TABLE-LEVEL (one set per table):
  metadata.json             ← current state of this table
  {metadata_sha}.json       ← versioned snapshots
  version_history.json      ← version index for this table
  {data_sha}.parquet        ← content-addressed data files
```

**Rule:** Never create dispatch.json, ref.json, or migration_history.json inside a table folder. Never create metadata.json or version_history.json at the project level.

### Convention 3b: Folder Structure Is a Cross-Language Contract

The directory layout is not an implementation detail — it is a **spec-level contract**. R-datom and Python-datom must produce and consume the same layout. Any change to the layout is a breaking change that requires a spec version bump.

**Canonical layout at the routing address:**

```
{routing_root}/
├── dispatch.json
├── ref.json
└── migration_history.json
```

**Canonical layout at the data address:**

```
{data_root}/datom/
├── .access/                      # Reserved for datom_ops, never touched by datom
├── .metadata/
│   └── manifest.json
└── {table_name}/
    ├── {data_sha}.parquet
    └── .metadata/
        ├── metadata.json
        ├── {metadata_sha}.json
        └── version_history.json
```

**Invariants:**
- The `datom/` segment is always present in the data path
- Table names are flat — no nesting of tables within tables
- `.metadata/` at project level holds only `manifest.json`
- `.metadata/` at table level holds metadata and version history
- `.access/` is reserved and never written to by datom core

### Convention 3c: Namespace Ownership

When datom and datom_ops share a governance bucket, each package owns its own subtree. Neither reads nor writes the other's namespace.

```
{governance}/routing/{project_name}/    ← datom owns
{governance}/registry/                  ← datom_ops owns
{data}/datom/.access/                   ← datom_ops owns
{data}/datom/.metadata/                 ← datom owns
{data}/datom/{table_name}/              ← datom owns
```

**Rule:** datom never writes to `.access/` or `registry/`. datom_ops never writes to `.metadata/` or `{table_name}/`.

### Convention 3d: Governance Bucket Is Non-Sensitive

When routing is separated into a shared governance bucket, that bucket contains:
- Method dispatch config (which functions handle reads)
- Data location pointers (bucket names, prefixes)
- Migration audit trails
- Role definitions and grants (who can access what — not the data itself)

**None of this is sensitive data.** The governance bucket should have **broad organizational read access**. Any user who might need to connect to any study should be able to read the governance bucket. **Write access** is restricted to domain owners and governance admins.

This is a design principle, not just a default — the governance bucket's accessibility is what makes the separated routing model work. Readers don't need credentials for each study's data bucket to discover where data lives; they only need governance read access plus credentials for their authorized data buckets.

---

## Decision 4: Governance Bucket Ownership Model

### The Gist

datom and datom_ops each independently manage their own subtrees in the governance bucket. They share conventions (the spec), not code. No shared package needed.

### The Model

```
datom:       writes dispatch.json, ref.json, migration_history.json
             to the routing address (which may be the governance bucket)

datom_ops:   writes roles, grants, sources
             to the registry address (in the governance bucket)

Contract:    the spec defines the folder structure
             both packages conform independently
```

### Why Not a Shared Package

A shared `datom_core` package would add a third dependency, complicate installation, and couple the two packages at the code level. The coupling should be at the **spec level** — shared schemas and folder conventions — not shared code.

For S3 utilities, datom_ops can access datom's internal functions via `datom:::` (R convention for using internal functions from a dependency). This is a decision for Phase B (when datom_ops is built), not now.

### What This Means for datom Now

datom only needs to know about one thing: its routing address (from `project.yaml`). It writes routing files there. It doesn't know or care whether datom_ops exists, whether a registry subtree is present, or whether the governance bucket is shared.

If `storage.routing` is absent in project.yaml → routing files go in the data bucket (simple case).
If `storage.routing` is present → routing files go there (enterprise case).

Either way, datom writes the same files to the same relative paths. The governance bucket is just a possible destination for those files.

---

## Updated S3 Structure (Complete Reference)

### Co-located (Simple Case, Default)

```
{bucket}/{prefix}/datom/
├── .access/                        # Reserved for datom_ops
├── .metadata/
│   ├── dispatch.json               # Project-level: method dispatch
│   ├── ref.json                    # Project-level: absent or self-ref
│   ├── manifest.json               # Project-level: table catalog
│   └── migration_history.json      # Project-level: migration audit
└── {table_name}/
    ├── {data_sha}.parquet          # Table-level: content-addressed data
    └── .metadata/
        ├── metadata.json           # Table-level: current state
        ├── {metadata_sha}.json     # Table-level: versioned snapshot
        └── version_history.json    # Table-level: version index
```

### Separated (Enterprise Case)

```
ROUTING: {routing_bucket}/{routing_prefix}/
├── dispatch.json                   # Project-level
├── ref.json                        # Project-level: points to data location
└── migration_history.json          # Project-level

DATA: {data_bucket}/{data_prefix}/datom/
├── .access/                        # Reserved for datom_ops
├── .metadata/
│   └── manifest.json               # Project-level: table catalog
└── {table_name}/
    ├── {data_sha}.parquet          # Table-level
    └── .metadata/
        ├── metadata.json           # Table-level
        ├── {metadata_sha}.json     # Table-level
        └── version_history.json    # Table-level
```

### Shared Governance Bucket (Enterprise, Multiple Studies)

```
s3://org-governance/
├── routing/
│   ├── med-mm-001/                 # datom owns — routing for study 001
│   │   ├── dispatch.json
│   │   ├── ref.json
│   │   └── migration_history.json
│   ├── med-mm-002/                 # datom owns — routing for study 002
│   │   └── ...
│   └── med-mm-xxx/                 # datom owns — routing for meta-study
│       └── ...
└── registry/                       # datom_ops owns — access management
    ├── roles/                      # (future)
    ├── grants/                     # (future)
    └── sources/                    # (future)
```

---

## Sprint Priority

```
1. dispatch.json rename
   (Clean break during tbit → datom rename. Touch every reference.)

2. ref.json + routing/data separation
   (Replace .redirect.json with ref.json. Add optional routing
    location to project.yaml. Update connection resolution.)

3. Codify conventions in spec
   (Project-level vs table-level, folder structure as contract,
    namespace ownership, governance bucket accessibility.)
```

Item 1 is straightforward find-and-replace plus test updates. Item 2 is the architectural change — new file schema, updated connection logic, removing the redirect chain. Item 3 is spec documentation — no code, but important for cross-language parity and datom_ops compatibility.
