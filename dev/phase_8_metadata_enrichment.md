# Phase 8: Metadata Enrichment & Table Types

## Overview

This phase addresses metadata schema gaps identified during the spec review.
The current `.tbit_build_metadata()` writes a minimal set of fields. This phase
brings the code in line with the updated specification: adding `table_type`,
`original_file_sha`, `size_bytes` to metadata.json.

Additionally, this phase includes a design exploration section for a planned
access management sister package that will influence routing, redirect integration,
and the `"imported"` vs `"derived"` lineage concept.

Git commit SHA enrichment in version_history.json was designed but deferred —
tbit doesn't pair code with data, so `metadata_sha` is the meaningful version
identifier. The enrichment approaches are preserved in the spec for future reference.

**Status**: Planning

**Depends on**: All prior phases (1–6 complete), Phase 7 (in parallel — no blocking dependencies)

---

## Problem Space

### P1: Incomplete Metadata

`.tbit_build_metadata()` currently writes: `data_sha`, `nrow`, `ncol`, `colnames`,
`created_at`, `tbit_version`, `custom`.

Missing per updated spec:
- `table_type`: `"imported"` (from source file via `tbit_sync`) or `"derived"` (from data frame via `tbit_write`)
- `original_file_sha`: SHA of the source file. Only meaningful for imported tables; `null` for derived.
- `size_bytes`: Size of the parquet file in bytes. Available at write time.

### P2: Git Commit SHA Not in version_history.json

Readers without GitHub access cannot pair a tbit version with its git commit.
The `commit` field is in the spec but was never populated due to a chicken-and-egg
problem: version_history.json is inside the commit, so the SHA isn't known when
the file is written.

### P3: Access Management Sister Package (Design Exploration)

A planned sister package will handle access management, potentially owning routing
and influencing redirect integration. The `"imported"` vs `"derived"` distinction
has implications for lineage-aware access patterns.

---

## Design Decisions

### D1: `table_type` Determination

- `tbit_sync()` path (source file → import → `tbit_write`): `table_type = "imported"`
- Direct `tbit_write(conn, data = df, ...)`: `table_type = "derived"`

Implementation: Add a `table_type` parameter to `.tbit_build_metadata()` with
default `"derived"`. `tbit_sync()` passes `"imported"` explicitly.

### D2: `original_file_sha` Flow

- `tbit_sync()` has the file SHA from `.tbit_compute_file_sha()` — pass it through to `.tbit_build_metadata()`
- Direct `tbit_write()` passes `NULL` — stored as JSON `null`

Implementation: Add `original_file_sha = NULL` parameter to `.tbit_build_metadata()`.

### D3: `size_bytes` Computation

- In `tbit_write()`, the parquet is written to a temp file before upload. Use `fs::file_size(tmp)`.
- For metadata-only changes (`change_type == "metadata_only"`), read size from existing S3 metadata.

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

- [ ] `.tbit_build_metadata()` accepts `table_type`, `original_file_sha`, `size_bytes`
- [ ] `table_type` defaults to `"derived"`, set to `"imported"` in `tbit_sync()` path
- [ ] `original_file_sha` stored as `null` when not provided
- [ ] `size_bytes` computed from parquet temp file
- [ ] Existing tests updated — metadata comparisons reflect new fields
- [ ] New tests: verify schema for imported vs derived tables

### Chunk 2: Access Management Design Exploration (No Code)

- [ ] Document the access management sister package concept
- [ ] Define relationship to routing (who owns routing.json dispatch?)
- [ ] Define relationship to redirect resolution (who calls `.tbit_s3_resolve_redirect()`?)
- [ ] Document lineage model: `"imported"` → `"derived"` (parental lineage, not children)
- [ ] Identify integration points in tbit that the sister package would hook into
- [ ] Output: design notes in this phase doc, with decisions migrated to spec when stable

---

## Current State

**Planning** — no implementation started.

---

## Deferred (Out of Scope for Phase 8)

| Item | Reason |
|------|--------|
| Git commit SHA in version_history.json | tbit doesn't pair code with data — `metadata_sha` is the version. Two enrichment approaches preserved in spec for future reference. |
| Routing dispatch implementation | Waiting on access management package design (Chunk 2) |
| Redirect integration in `tbit_get_conn()` | Same — integration point may be owned by sister package |
| `max_file_size_gb` enforcement | Separate concern, low risk — can be a quick follow-up |
| `parallel_uploads` implementation | Optimization, not correctness — defer to when repos are large enough to need it |

---

## Notes / Learnings

- The "imported" vs "derived" distinction emerged from reviewing `original_file_sha` —
  it's only meaningful when a source file exists. This naturally maps to two table types
  with different lineage characteristics.
- Git commit SHA enrichment was designed (two approaches) but deferred: tbit uses git
  as a mechanism, not a code repo. `metadata_sha` is the version. The enrichment patterns
  are preserved in the spec under "Deferred to v2" for future reference.
- The access management sister package is still early-stage. Chunk 2 is explicitly
  a design exploration with no code deliverable — output is documentation and decisions.
