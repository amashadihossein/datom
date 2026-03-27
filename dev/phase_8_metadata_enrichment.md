# Phase 8: Metadata Enrichment & Table Types

## Overview

This phase brings tbit's metadata schema in line with the updated specification
and ensures tbit is compatible with the planned tbitaccess sister package
(see `dev/tbitaccess_overview.md`).

Key additions:
- Metadata schema: `table_type`, `size_bytes`, `parents`
- version_history.json: add `original_file_sha` field (source file provenance + skip optimization)
- New exported function: `tbit_get_parents()`
- Connection: `endpoint` parameter in `tbit_conn` / `tbit_get_conn()`
- S3 convention: `.access/` reserved namespace documented

Git commit SHA enrichment in version_history.json was designed but deferred —
tbit doesn't pair code with data, so `metadata_sha` is the version identifier.
The enrichment approaches are preserved in the spec for future reference.

**Status**: Planning

**Depends on**: All prior phases (1–6 complete), Phase 7 (in parallel — no blocking dependencies)

---

## Problem Space

### P1: Incomplete Metadata Schema

`.tbit_build_metadata()` currently writes: `data_sha`, `nrow`, `ncol`, `colnames`,
`created_at`, `tbit_version`, `custom`.

Missing per updated spec:
- `table_type`: `"imported"` or `"derived"`
- `size_bytes`: Parquet file size in bytes
- `original_file_sha`: Moved to version_history.json (not metadata.json). Tracked per-version for source file provenance and future skip optimization across version rollbacks.
- `parents`: Lineage field required by tbitaccess for access gate computation and
  by dp_dev for dependency tracking. List of `{source, table, version}` entries
  or `null`. Always `null` for imported tables.

### P2: `parents` Parameter Missing from `tbit_write()`

`tbit_write()` has no way for callers (dp_dev, users) to record lineage at write time.
In practice, dp_dev manages dependency versions via targets or similar, and provides
exact `metadata_sha` values for each parent. tbit just stores what it's given.

### P3: No `tbit_get_parents()` Function

tbitaccess needs to read lineage from metadata to walk the ancestry tree for access
resolution. No exported function exists yet.

### P4: No `endpoint` in `tbit_conn`

tbitaccess routes reads through S3 access points for IAM enforcement. It needs
to pass an endpoint URL when constructing a connection. Currently `tbit_conn` and
`tbit_get_conn()` have no endpoint parameter.

---

## Design Decisions

### D1: `table_type` Determination

- `tbit_sync()` path (source file → import → `tbit_write`): `table_type = "imported"`
- Direct `tbit_write(conn, data = df, ...)`: `table_type = "derived"`

Implementation: Add a `table_type` parameter to `.tbit_build_metadata()` with
default `"derived"`. `tbit_sync()` passes `"imported"` explicitly.

### D2: `original_file_sha` Flow

`original_file_sha` lives in version_history.json, not metadata.json. This means it
does NOT participate in `metadata_sha` computation — re-importing identical data from
a corrected source file doesn't create a new tbit version.

- `tbit_sync()` computes file SHA via `.tbit_compute_file_sha()` → passes to `tbit_write()` via `.original_file_sha`
- Direct `tbit_write()` has `.original_file_sha = NULL` → stored as JSON `null` in version_history entry
- `.tbit_write_metadata_local()` includes `original_file_sha` in the new version_history entry

Future skip optimization (deferred): scan version_history for matching `original_file_sha`
to avoid re-importing unchanged source files, even when manifest only tracks current SHA.

### D3: `size_bytes` Computation

- In `tbit_write()`, the parquet is written to a temp file before upload. Use `fs::file_size(tmp)`.
- For metadata-only changes (`change_type == "metadata_only"`), read size from existing S3 metadata.

### D5: `parents` Field

- `tbit_write()` gains a `parents = NULL` parameter
- Passed through to `.tbit_build_metadata()` and stored as-is in metadata.json
- `parents` participates in `metadata_sha` computation (alphabetically sorted with other fields) — changing parents creates a new version
- `tbit_sync()` never passes `parents`; imported tables always store `parents: null`
- No auto-resolution of version: callers (dp_dev) supply exact `metadata_sha` values. If version is unknown, caller passes `null` for that entry (lineage recorded as unknown, not omitted)
- Schema per entry: `list(source = "project_name", table = "table_name", version = "metadata_sha")`

### D6: `endpoint` in `tbit_conn`

- `new_tbit_conn()` gains `endpoint = NULL` parameter, stored in the conn object
- `tbit_get_conn()` and `.tbit_get_conn_reader()` accept and forward `endpoint`
- `.tbit_s3_client()` passes endpoint to paws when non-NULL
- Default `NULL` changes no existing behavior

### D4: Git Commit SHA Enrichment — Deferred

After analysis, git commit SHAs in version_history.json were deferred. tbit uses
git as a versioning and conflict-management mechanism, not as a code repository.
The meaningful version identifier is `metadata_sha` (content-addressed, deterministic).
Since tbit doesn't pair code with data, the git SHA adds no reproducibility value.
When git context is needed, `timestamp` + `author` or `git log --all -S "<metadata_sha>"`
locates the commit directly.

Two enrichment approaches were designed and preserved in the spec ("Deferred to v2")
in case a compelling use case emerges later.

---

## Acceptance Criteria

### Chunk 1: Metadata Schema Fields

- [ ] `.tbit_build_metadata()` accepts `table_type`, `size_bytes`, `parents` (NOT `original_file_sha`)
- [ ] `table_type` defaults to `"derived"`, set to `"imported"` in `tbit_sync()` path
- [ ] `original_file_sha` added to version_history.json entries via `.tbit_write_metadata_local()`
- [ ] `tbit_write()` gains `.original_file_sha = NULL` internal param; `tbit_sync()` passes the file SHA
- [ ] `original_file_sha` does NOT participate in `metadata_sha` computation
- [ ] `size_bytes` computed from parquet temp file; read from existing S3 metadata for metadata-only updates
- [ ] `parents` stored as-is; `null` for imported tables (enforced at call site)
- [ ] `parents` participates in `metadata_sha` computation
- [ ] `tbit_write()` gains `parents = NULL` parameter, passed through to `.tbit_build_metadata()`
- [ ] Existing tests updated — metadata comparisons reflect new fields
- [ ] New tests: imported table (parents null, table_type imported), derived with parents, derived without parents

### Chunk 2: `tbit_get_parents()`

- [ ] New exported function in `R/query.R`
- [ ] `tbit_get_parents(conn, name, version = NULL)` — reads `parents` from current or versioned metadata
- [ ] Returns `NULL` for imported tables or derived tables with no recorded lineage
- [ ] Versioned read fetches `{version}.json` snapshot from S3
- [ ] Tests: imported table, derived with parents, derived without parents, versioned read

### Chunk 3: `endpoint` in `tbit_conn`

- [ ] `new_tbit_conn()` gains `endpoint = NULL`, stored in conn object
- [ ] `tbit_get_conn()` and `.tbit_get_conn_reader()` accept and forward `endpoint`
- [ ] `.tbit_s3_client()` passes endpoint to paws when non-NULL
- [ ] All existing tests pass unchanged (NULL default = no behavior change)
- [ ] New test: conn with endpoint set has it accessible as `conn$endpoint`

### Chunk 4: `.access/` Reserved Namespace (Convention Only)

- [ ] S3 storage diagram in spec updated (already done)
- [ ] `tbit_list()` confirmed safe: reads manifest.json only, never touches `.access/`
- [ ] No tbit function reads, writes, or deletes keys under `.access/` prefix
- [ ] Add note to `tbitaccess_overview.md` confirming tbit-side safety

---

## Current State

**Planning** — no implementation started.

---

## Deferred (Out of Scope for Phase 8)

| Item | Reason |
|------|--------|
| Git commit SHA in version_history.json | tbit doesn't pair code with data — `metadata_sha` is the version. Two enrichment approaches preserved in spec for future reference. |
| Routing dispatch implementation | Waiting on tbitaccess design — routing.json method dispatch vs tbitaccess access routing are separate concerns; tbit's routing.json is method routing only |
| Redirect integration in `tbit_get_conn()` | Integration point may be influenced by tbitaccess |
| `max_file_size_gb` enforcement | Separate concern, low risk — can be a quick follow-up |
| `parallel_uploads` implementation | Optimization, not correctness — defer to when repos are large enough to need it |

---

## Notes / Learnings

- `parents` is a first-class field (not in `custom`) because it participates in `metadata_sha`.
- dp_dev (or similar orchestration tool using targets) manages the dependency graph and
  supplies exact parent `metadata_sha` values at write time. tbit stores faithfully, no auto-resolution.
- The `endpoint` parameter is purely additive — `NULL` default means zero behavior change for existing code.
  tbitaccess sets it externally to enforce S3 access point routing without tbit needing to know about it.
- tbitaccess reads tbit metadata; tbit never reads tbitaccess data. The dependency is one-way.
- Git commit SHA enrichment was designed (two approaches) but deferred: tbit uses git
  as a mechanism, not a code repo. The enrichment patterns are preserved in the spec under "Deferred to v2".
