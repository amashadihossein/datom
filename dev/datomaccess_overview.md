# datomaccess Integration — Context for datom Development

> **Purpose**: This file provides context for development tools (Copilot, Claude, etc.)
> about a planned sister package, **datomaccess**, so that datom development decisions
> remain compatible with future access management integration.
>
> **datomaccess does not exist yet.** Nothing here needs to be built now unless
> marked as a datom requirement. This is forward-looking context only.

---

## What is datomaccess?

A future R package (with Python counterpart) that layers access management on top of datom. It will:

- Let domain owners define **roles** (named sets of table-level read permissions)
- Map **users** (enterprise identities) to roles via **grants**
- Store roles and grants in a **registry** (itself a datom in a governance bucket)
- **Auto-inherit** access requirements for derived tables by walking lineage
- **Enforce** access at the cloud storage API level (S3 access points, IAM)

datomaccess depends on datom. datom does **not** depend on datomaccess. datom must work fully without datomaccess installed.

---

## What datom Needs to Accommodate datomaccess

### 1. Lineage (parents) in Metadata — REQUIRED

Every table written via `datom_write()` should include a `parents` field in `metadata.json`.

**Schema:**

```json
{
  "data_sha": "abc123...",
  "table_type": "derived",
  "parents": [
    {
      "source": "med-mm-001",
      "table": "os_data",
      "version": "a3f8c1..."
    }
  ],
  "...other fields..."
}
```

**Rules:**

- `parents` is a **first-class metadata field** (not inside `custom`)
- It participates in `metadata_sha` computation (changing parents = new version)
- For `table_type: "imported"` (via `datom_sync`): `parents` is always `null`
- For `table_type: "derived"` (via `datom_write`): `parents` is a list or `null`
- `parents: null` on a derived table means "lineage not recorded" — valid, not an error
- Each parent entry has: `source` (project_name of source data space), `table` (table name), `version` (metadata_sha at derivation time)
- For tables derived within the same project, `source` equals `conn$project_name`

**Why:** datomaccess walks lineage upward to compute access gates. dpbuild also uses lineage for data product construction. Even without datomaccess, lineage serves datom's own reproducibility story.

**Files to modify:**

- `R/read_write.R`: `.datom_build_metadata()` — add `parents` field
- `R/read_write.R`: `datom_write()` — add `parents` parameter, pass to `.datom_build_metadata()`
- When `parents` is provided, `table_type` should be `"derived"`

### 2. parents Parameter in datom_write — REQUIRED

```r
# Current signature:
datom_write(conn, data = NULL, name = NULL, metadata = NULL, message = NULL)

# Proposed signature:
datom_write(conn, data = NULL, name = NULL, metadata = NULL,
           message = NULL, parents = NULL)
```

`parents` is a list of named lists: `list(list(source = "...", table = "...", version = "..."), ...)`.

When `datom_write` is called from `datom_sync` (imported tables), `parents` is never passed — those tables always have `parents: null`.

### 3. datom_get_parents() — REQUIRED

New exported function:

```r
#' Get Parent Tables from Lineage
#'
#' Reads the `parents` field from a table's metadata. Returns NULL for
#' imported tables or derived tables with no recorded lineage.
#'
#' @param conn A `datom_conn` object.
#' @param name Table name.
#' @param version Optional metadata_sha. If NULL, uses current version.
#' @return List of parent entries (each with source, table, version), or NULL.
#' @export
datom_get_parents <- function(conn, name, version = NULL) {
  .datom_validate_name(name)
  meta <- .datom_read_metadata(conn, name)

  if (!is.null(version)) {
    # Read versioned snapshot
    versioned_key <- .datom_build_s3_key(
      conn$prefix, name, ".metadata", paste0(version, ".json")
    )
    versioned_meta <- .datom_s3_read_json(conn, versioned_key)
    return(versioned_meta$parents)
  }

  meta$current$parents
}
```

**File:** Create in `R/query.R` or `R/read_write.R` (wherever lineage-related reads best fit).

### 4. Endpoint Override in Connection — REQUIRED

datomaccess will route reads through S3 access points. datom_conn needs to accept an optional endpoint.

**Files to modify:**

- `R/conn.R`: `new_datom_conn()` — add `endpoint = NULL` parameter, store in conn object
- `R/conn.R`: `datom_get_conn()` — add `endpoint = NULL` parameter, pass through
- `R/conn.R`: `.datom_get_conn_reader()` — accept and forward `endpoint`
- `R/utils-s3.R`: `.datom_s3_client()` — when `endpoint` is provided, pass as `endpoint` config to `paws.storage::s3()`

When `endpoint` is NULL (default), everything works exactly as today. datomaccess sets this when loaded.

### 5. Reserved Namespace — CONVENTION ONLY

The S3 key prefix `{prefix}/datom/.access/` is reserved for datomaccess. datom should not read, write, or delete keys under this prefix.

`datom_list()` already reads from `manifest.json` only, so this is safe by construction. Just document the convention in the spec's storage structure section.

**Verified (Phase 8, Chunk 4)**: Full audit confirms datom is safe:
- No R/ source file references `.access` in any S3 key construction
- All S3 operations are point-access (`put_object`, `get_object`, `head_object`) on explicit keys
- No `list_objects` or `delete_object` calls exist in package code
- `.datom_build_s3_key()` always inserts a `datom/` segment, structurally separating datom keys from `.access/`

Add to the S3 storage structure diagram:

```
bucket/
└── {optional_prefix}/
    └── datom/
        ├── .access/                    # Reserved for datomaccess package
        │   └── (managed by datomaccess)
        ├── .metadata/
        │   ├── routing.json
        │   ├── manifest.json
        │   └── migration_history.json
        ├── .redirect.json
        └── {table_name}/
            └── ...
```

### 6. Storage Utility Sharing — RECOMMENDED, NOT BLOCKING

datomaccess will need S3 read/write capabilities. datom already has:

```
.datom_s3_exists()
.datom_s3_read_json()
.datom_s3_write_json()
.datom_s3_upload()
.datom_s3_download()
```

No action needed now. When datomaccess is built, these can be accessed via `datom:::` or re-exported. Just keep these functions with clean interfaces (conn + key based) so they remain reusable.

---

## Table Type Convention

The `table_type` field maps directly to the entry path:

```
datom_sync()   → "imported"   (file on disk → parquet)
                 original_file_sha: populated (in version_history.json)
                 parents: null (always)

datom_write()  → "derived"    (data frame in memory → parquet)
                 original_file_sha: null (in version_history.json)
                 parents: list or null
```

"Derived" aligns with clinical data science convention (CDISC/ADaM) — anything that isn't a raw source extract. This includes joins, transformations, synthetic data, API pulls, and manually constructed tables.

`datom_write` should NOT accept `table_type = "imported"`. If data came from a file, it goes through `datom_sync`.

---

## Design Invariants (Do Not Break)

These properties are critical for datomaccess integration:

1. **Three independent layers**: DATA (parquet + SHA) and METADATA (git-tracked JSON) are versioned and immutable once written. Access/routing is a separate mutable layer that does not affect versions.

2. **routing.json is method routing, not access routing**: datom's `routing.json` controls which R/Python function handles reads (e.g., "default" → `datom::datom_read`). Access routing (who can read what) is a completely separate concern owned by datomaccess, stored in `.access/`.

3. **datom_conn exposes key fields**: `conn$project_name`, `conn$bucket`, `conn$prefix`, `conn$region`, `conn$role` must remain accessible as simple list fields. datomaccess reads these to resolve access points and registry lookups.

4. **S3 utilities use conn-based interface**: All `.datom_s3_*` functions take `conn` as first argument and derive bucket/client from it. This means swapping the endpoint (via access points) works transparently.

5. **datom works fully without datomaccess**: No conditional logic checking for datomaccess. No optional imports. datom is complete on its own. datomaccess wraps/intercepts from outside.

---

## Retroactive Access Management Adoption

Users can start with datom alone and add datomaccess later. This works because:

- The registry maps roles to current tables — no historical context needed
- `datom_list()` shows all tables; domain owners group them into roles after the fact
- Tables with `parents: null` require manual role assignment (no auto-inheritance)
- Tables with `parents: [...]` get auto-inheritance via `access_compute_gates()`
- No metadata migration, no data movement, no version changes needed

The only cost of late adoption: older derived tables written without `parents` won't benefit from automatic gate inheritance. They still work — they just need manual role assignment.

---

## datomaccess High-Level Architecture (For Context Only)

```
┌─────────────────────────────────────────────────────┐
│                   REGISTRY (a datom)                  │
│                                                      │
│   roles:   role → [source, table] mappings           │
│   grants:  user_identity → [role] mappings           │
│                                                      │
│   Lives in a dedicated governance bucket              │
└──────────────────────┬──────────────────────────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
   ┌────────────┐ ┌────────────┐ ┌────────────┐
   │ med-mm-001 │ │ med-mm-002 │ │ med-mm-xxx │
   │  (study)   │ │  (study)   │ │  (meta)    │
   │            │ │            │ │            │
   │ datom data  │ │ datom data  │ │ derived    │
   │ + .access/ │ │ + .access/ │ │ + .access/ │
   └────────────┘ └────────────┘ └────────────┘
```

**Enforcement model:**

- **Layer 1 (R-level, advisory):** datomaccess checks registry before `datom_read()`. Bypassable if user calls S3 directly. Useful for development/exploration.
- **Layer 2 (Cloud IAM, enforced):** datomaccess materializes registry into S3 access points and IAM policies. Unbypassable. Required for compliance/production.

Layer 1 ships first as datomaccess MVP. Layer 2 adds cloud enforcement later.

---

## Access Resolution — Full Specification

This section describes how datomaccess determines whether a user can read a given table. This is the core algorithm that makes access management work. It relies on three things that datom provides: **lineage** (parents in metadata), **connection context** (project_name, bucket), and **the registry** (roles and grants stored as datom tables in a governance bucket).

### Core Concepts

**Registry** — A governance data space (its own datom bucket) containing three tables:

```
ROLES TABLE: Maps roles to the specific tables they grant access to.
┌──────────────────────┬────────────┬──────────────────┐
│ role                 │ source     │ table            │
├──────────────────────┼────────────┼──────────────────┤
│ studyx_safety        │ study-x    │ ae_data          │
│ studyx_safety        │ study-x    │ dm_data          │
│ studyx_pk            │ study-x    │ pc_data          │
│ mm001_efficacy       │ med-mm-001 │ os_data          │
│ mm001_efficacy       │ med-mm-001 │ tumor_response   │
│ mm002_efficacy       │ med-mm-002 │ os_data          │
└──────────────────────┴────────────┴──────────────────┘

GRANTS TABLE: Maps users to the roles they hold.
┌──────────────────┬──────────────────────┐
│ user             │ role                 │
├──────────────────┼──────────────────────┤
│ sara@company.com │ studyx_safety        │
│ sara@company.com │ studyx_pk            │
│ sara@company.com │ mm001_efficacy       │
│ sara@company.com │ mm002_efficacy       │
│ john@company.com │ mm001_efficacy       │
└──────────────────┴──────────────────────┘

SOURCES TABLE: Maps project names to their bucket/prefix locations.
┌────────────┬──────────────┬─────────┐
│ source     │ bucket       │ prefix  │
├────────────┼──────────────┼─────────┤
│ study-x    │ bucket-x     │ trial/  │
│ med-mm-001 │ bucket-001   │ trial/  │
│ med-mm-002 │ bucket-002   │ trial/  │
│ med-mm-xxx │ bucket-xxx   │ meta/   │
└────────────┴──────────────┴─────────┘
```

A domain owner manages the roles for their own study. A governance admin manages cross-study grants. The sources table is populated when studies are registered in the governance system.

**Lineage** — Each derived table's metadata records its immediate parents. Only immediate parents — not grandparents or deeper ancestors. The access algorithm walks upward through the lineage to discover the full ancestor tree.

**Leaf tables** — Imported tables (from `datom_sync`) or derived tables with `parents: null`. These are the endpoints of the lineage walk — the original data sources whose access restrictions gate everything derived from them.

### The Naive Walk Algorithm

This is the baseline approach. It is correct, simple, and sufficient for most workloads. Optimizations (described later) can be layered on top without changing the interface.

**When a user calls `datom_read(conn, "some_table")`**, datomaccess runs `access_check()`:

```
access_check(acc, user, conn, table_name):

  STEP 1 — WALK LINEAGE UPWARD TO FIND ALL LEAF ANCESTORS

    Start at the requested table. Read its metadata to get parents.
    For each parent, read that parent's metadata to get its parents.
    Repeat until reaching tables with no parents (leaves).

    The walk is a depth-first traversal of the lineage DAG.
    It terminates at:
      - Imported tables (table_type: "imported")
      - Derived tables with parents: null (lineage not recorded)

    Collect all unique leaves into a set.

  STEP 2 — CHECK FOR EXPLICIT OVERRIDE

    Check if the requested table itself has an explicit entry in the
    roles table. If so, those roles are added to the required set.
    This allows domain owners to add restrictions beyond what lineage
    would imply (e.g., restricting a summary table even if the user
    can access the underlying data).

  STEP 3 — LOOK UP REQUIRED ROLES FOR EACH LEAF

    For every leaf in the set, query the roles table:
      "Which roles grant access to (leaf.source, leaf.table)?"
    
    Union all required roles into a single set: required_roles.

  STEP 4 — LOOK UP USER'S GRANTED ROLES

    Query the grants table:
      "Which roles does this user hold?"
    
    This gives: user_roles.

  STEP 5 — COMPARE

    missing = required_roles − user_roles

    If missing is empty → ALLOW the read.
    If missing is not empty → DENY with an informative error
      listing exactly which roles are missing.
```

### Worked Example: Within-Study Derivation

**Setup:** A single study with a two-layer derivation chain.

```
study-x (one bucket):

  ae_data   (imported, LEAF)        ← requires studyx_safety
  dm_data   (imported, LEAF)        ← requires studyx_safety
  pc_data   (imported, LEAF)        ← requires studyx_pk

  x         (derived from ae + dm)
  Y         (derived from x + pc)
```

The metadata looks like:

```json
// x metadata.json
{
  "table_type": "derived",
  "parents": [
    {"source": "study-x", "table": "ae_data", "version": "aaa111"},
    {"source": "study-x", "table": "dm_data", "version": "bbb222"}
  ]
}

// Y metadata.json
{
  "table_type": "derived",
  "parents": [
    {"source": "study-x", "table": "x", "version": "ccc333"},
    {"source": "study-x", "table": "pc_data", "version": "ddd444"}
  ]
}
```

**Sara reads Y. The walk proceeds:**

```
Y (derived)
├─ study-x:x (derived → keep walking)
│   ├─ study-x:ae_data (imported → LEAF ✓)
│   └─ study-x:dm_data (imported → LEAF ✓)
│
└─ study-x:pc_data (imported → LEAF ✓)

Leaves found: {ae_data, dm_data, pc_data}

Role lookup:
  ae_data  → studyx_safety
  dm_data  → studyx_safety  (deduplicates)
  pc_data  → studyx_pk

Required roles: {studyx_safety, studyx_pk}

Sara has: {studyx_safety, studyx_pk} → ALL PRESENT → ALLOW
```

**John reads Y:**

```
Same walk, same required roles: {studyx_safety, studyx_pk}

John has: {mm001_efficacy} → MISSING both → DENY

Error: "Access denied for Y. Missing roles: studyx_safety, studyx_pk"
```

**John reads x (not Y):**

```
x (derived)
├─ study-x:ae_data (LEAF)
└─ study-x:dm_data (LEAF)

Leaves: {ae_data, dm_data}
Required: {studyx_safety}
John has: {mm001_efficacy} → MISSING studyx_safety → DENY
```

### Worked Example: Cross-Study Derivation

**Setup:** A meta-analysis product draws from two studies, each with their own roles.

```
med-mm-001:  os_data (imported)     ← requires mm001_efficacy
med-mm-002:  os_data (imported)     ← requires mm002_efficacy
med-mm-xxx:  pooled_os (derived from both)
```

```json
// med-mm-xxx: pooled_os metadata.json
{
  "table_type": "derived",
  "parents": [
    {"source": "med-mm-001", "table": "os_data", "version": "abc123"},
    {"source": "med-mm-002", "table": "os_data", "version": "def456"}
  ]
}
```

**Sara reads pooled_os from med-mm-xxx:**

```
pooled_os (med-mm-xxx, derived)
├─ med-mm-001:os_data (imported → LEAF ✓)  [different bucket!]
└─ med-mm-002:os_data (imported → LEAF ✓)  [different bucket!]

Leaves: {med-mm-001:os_data, med-mm-002:os_data}

Required: {mm001_efficacy, mm002_efficacy}
Sara has both → ALLOW
```

**Cross-bucket metadata reads:** The lineage walk needs to read metadata from med-mm-001 and med-mm-002, which are in different buckets than med-mm-xxx. The `source` field in each parent entry is a `project_name`. datomaccess uses the registry's SOURCES table to look up the bucket/prefix for each source, then constructs a temporary reader connection to fetch metadata:

```r
# Inside the lineage walker (pseudocode)
parent_conn <- datom_get_conn(
  bucket = sources_table[parent$source, "bucket"],
  prefix = sources_table[parent$source, "prefix"],
  project_name = parent$source
)
parent_parents <- datom_get_parents(parent_conn, parent$table, parent$version)
```

### Worked Example: Deep Mixed Derivation

**Setup:** Three layers deep, mixing within-study and cross-study lineage.

```
study-x:     ae + dm → x;  x + pc → Y
study-z:     ae → Z
med-mm-xxx:  Y + Z → final_table
```

**Sara reads final_table:**

```
final_table (med-mm-xxx, derived)
│
├─ study-x:Y (derived → keep walking)
│   ├─ study-x:x (derived → keep walking)
│   │   ├─ study-x:ae_data (LEAF ✓)
│   │   └─ study-x:dm_data (LEAF ✓)
│   └─ study-x:pc_data (LEAF ✓)
│
└─ study-z:Z (derived → keep walking)
    └─ study-z:ae_data (LEAF ✓)

Leaves: {study-x:ae_data, study-x:dm_data,
         study-x:pc_data, study-z:ae_data}

Required roles:
  study-x:ae_data  → studyx_safety
  study-x:dm_data  → studyx_safety  (dedup)
  study-x:pc_data  → studyx_pk
  study-z:ae_data  → studyz_safety

Required: {studyx_safety, studyx_pk, studyz_safety}
```

Three roles, across two studies, resolved from a three-layer lineage. The algorithm is the same at every depth.

### Why Walk to Leaves (Not Every Level)?

Access restrictions originate from the **source data** — patient records from specific trials. If you can access the raw ingredients, you can access anything derived from them. This matches clinical data intuition: the sensitivity lives in the original data, not in a summary statistic derived from it.

Checking every intermediate level would create confusing scenarios where a user has access to all inputs but not the output. The leaf-only approach avoids this.

**Exception: explicit overrides.** If a domain owner wants to restrict a specific derived table independently of its lineage (e.g., a table containing results under embargo), they add that table directly to the roles table. Step 2 of the algorithm catches this. The final required set becomes:

```
required_roles = (roles for leaf ancestors) ∪ (roles for this specific table if any)
```

### Performance: Naive Walk Cost

For the typical case (≤3 layers deep, ≤3 cross-study hops):

```
Metadata reads per hop:  1 (read parents from metadata.json)
Typical hops:            3-6 (for a 3-layer tree with branching)
Cost per read:           ~50ms per S3 GET
Total overhead:          ~150-300ms

For comparison:
  Reading the actual parquet:  200-2000ms (depending on size)
```

The naive walk adds ~150-300ms to a read that already takes 200-2000ms. Noticeable but not blocking. For the MVP, this is fine.

### Optimized Resolution: Session Cache

The naive walk is correct but redundant — the same user reading multiple tables from the same study will re-walk overlapping lineage paths and re-query the same registry data. Since roles and grants change infrequently, we can cache the resolved permission set and invalidate only when something changes.

**The key insight:** The registry is a datom, so it has a `metadata_sha` (version). If the registry version hasn't changed since the last resolution, the cached result is still valid. Checking the registry version is a single S3 HEAD request (~20ms).

**Cache structure:**

```
Session cache (in-memory R environment):

  Key:   {user, source (study), registry_version}
  Value: {allowed_tables, full_access_flag, resolved_roles}

  Example entry:
    user: "sara@company.com"
    source: "study-x"
    registry_version: "v47abc..."
    allowed_tables: ["ae_data", "dm_data", "pc_data", "x", "Y"]
    full_access: TRUE
    resolved_roles: ["studyx_safety", "studyx_pk"]
```

**Cached read flow:**

```
datom_read(conn, "Y")
  │
  ├─ Cache lookup: key = {sara, study-x, *}
  │   │
  │   ├─ CACHE MISS (first read of session):
  │   │   1. Fetch registry metadata_sha (1 HEAD request, ~20ms)
  │   │   2. Walk lineage for Y → find leaves → resolve roles
  │   │   3. Store result in cache keyed on registry version
  │   │   4. ALLOW or DENY based on resolution
  │   │
  │   ├─ CACHE HIT + VERSION MATCH:
  │   │   1. Fetch registry metadata_sha (1 HEAD request, ~20ms)
  │   │   2. Compare to cached version → MATCH
  │   │   3. Look up "Y" in cached allowed_tables → FOUND
  │   │   4. ALLOW (no tree walk, no registry query)
  │   │
  │   └─ CACHE HIT + VERSION STALE:
  │       1. Fetch registry metadata_sha → MISMATCH
  │       2. Invalidate cache for this source
  │       3. Re-resolve (full walk)
  │       4. Update cache
  │
  └─ datom_read proceeds with the data fetch
```

**Cost after cache warmup:** One HEAD request (~20ms) to verify registry version. No lineage walk. No registry query. This is negligible.

### Optimized Resolution: Full-Access Fast Path

In practice, each study has 3-5 roles and 100-300 tables. Many users (especially data developers) will hold ALL roles for their study. Once detected, the cache stores a blanket pass.

**How it works:**

```
During resolution, after collecting the user's roles for a study:

  all_study_roles = (all unique roles in registry where source = this study)
  user_study_roles = (user's roles that apply to this study)

  if user_study_roles ⊇ all_study_roles:
    Cache: full_access = TRUE for this study
    → All future reads from this study skip both lineage walk AND table lookup
```

**When does this trigger?** After Sara reads a handful of tables from study-x and the resolver discovers she has `studyx_safety` + `studyx_pk` (which are the only roles for study-x), it flips to full-access mode. Every subsequent read from study-x is instant.

**Invalidation:** Same as before — if registry version changes, the cache is invalidated and re-resolved. A new role added to the study would change the registry version, and Sara's next read would re-resolve (discovering whether she has the new role or not).

### Optimized Resolution: Precomputed Leaf Map

This optimization moves the lineage walk from read time to role-definition time. When a domain owner creates or updates a role via `access_create_role()` or `access_update_role()`, datomaccess precomputes the leaf ancestors for every table in the role and stores the result:

```
ROLE_LEAVES TABLE (precomputed, stored in registry):
┌──────────────────┬─────────┬─────────────┬────────────┐
│ role             │ table   │ leaf_source │ leaf_table  │
├──────────────────┼─────────┼─────────────┼────────────┤
│ studyx_safety    │ x       │ study-x     │ ae_data    │
│ studyx_safety    │ x       │ study-x     │ dm_data    │
│ studyx_safety    │ Y       │ study-x     │ ae_data    │
│ studyx_safety    │ Y       │ study-x     │ dm_data    │
│ studyx_pk        │ Y       │ study-x     │ pc_data    │
└──────────────────┴─────────┴─────────────┴────────────┘
```

With this table, `access_check()` skips the lineage walk entirely — it looks up the precomputed leaves directly. The tradeoff: this table must be recomputed when lineage changes (new derived tables, updated parents). Since role definitions and table lineage change infrequently, this is a good tradeoff at scale.

**Recommendation:** Don't build this for Phase B (MVP). The session cache + full-access fast path covers 95%+ of reads. Add the precomputed leaf map in Phase C only if profiling shows the walk is a bottleneck.

### Optimization Summary

```
                         │ Network calls │ Lineage walk │ When to use
─────────────────────────┼───────────────┼──────────────┼──────────────
Naive walk               │ N per hop     │ Yes          │ Phase B (MVP)
Session cache            │ 1 HEAD        │ No           │ Phase B+
Full-access fast path    │ 1 HEAD        │ No           │ Phase B+
Precomputed leaf map     │ 0-1           │ No           │ Phase C (if needed)
```

The Phase B MVP ships with naive walk + session cache. This is correct, simple, and fast enough for ≤3-layer lineage with 100-300 tables per study.

---

**Read-time flow with datomaccess (complete):**

```
datom_read(conn, "some_table")
  │
  ├─ datomaccess intercepts (if loaded)
  │   │
  │   ├─ Check session cache
  │   │   ├─ Cache hit + version valid → ALLOW (no walk)
  │   │   ├─ Full-access flag set → ALLOW (no walk, no lookup)
  │   │   └─ Cache miss or stale → continue to resolution
  │   │
  │   ├─ Resolve: walk lineage → collect leaves → look up roles
  │   ├─ Compare user grants against required roles
  │   ├─ Update session cache with result
  │   ├─ If Layer 2 active: route to access-point endpoint
  │   │
  │   └─ ALLOW → datom_read proceeds
  │      DENY  → error with missing roles listed
  │
  └─ datom_read fetches data normally
```
