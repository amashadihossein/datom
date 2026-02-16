# Phase 6: Sync & Validation

**Status**: 🟢 In Progress  
**Started**: 2026-02-15  
**Target**: Batch sync operations, validation, status  
**Estimated Effort**: 1 week

---

## Objective

Implement batch sync operations (`tbit_sync_manifest`, `tbit_sync`, `tbit_sync_routing`), validation (`tbit_validate`), and status (`tbit_status`). These build on the Phase 5 read/write primitives.

---

## Chunk Queue

| # | Chunk | Functions | Status |
|---|-------|-----------|--------|
| 1 | Manifest scanning | `tbit_sync_manifest()` | ✅ Done |
| 2 | Batch sync | `tbit_sync()` | ✅ Done |
| 3 | Routing sync | `tbit_sync_routing()` | ✅ Done |
| 4 | Validation | `tbit_validate()` | ⚪ Not started |
| 5 | Status | `tbit_status()` | ⚪ Not started |

---

## Current State

### Completed Chunks

**Chunk 1 — Manifest scanning** (29 tests)
- `tbit_sync_manifest()`: scans flat input_files/ dir, computes file SHAs, compares against `.tbit/manifest.json`
- Returns data frame with columns: name, file, format, file_sha, status
- Status values: "new", "changed", "unchanged"
- Validates: developer role, local path, flat dir, glob pattern filtering

**Chunk 2 — Batch sync** (42 tests)
- `tbit_sync()`: processes manifest from `tbit_sync_manifest()`, imports files via `rio::import()`, writes via `tbit_write()` per table
- `.tbit_import_file()`: parquet direct via arrow, all other formats via rio
- `.tbit_update_manifest_entry()`: updates `.tbit/manifest.json` per-table with SHAs, format, timestamps
- `.tbit_check_rio()`: runtime check for rio availability
- `continue_on_error`: tryCatch per table, collects errors, continues or stops
- Returns augmented manifest with `result` and `error` columns

**Chunk 3 — Routing sync** (32 tests)
- `tbit_sync_routing()`: syncs all git metadata to S3 (repo-level + per-table)
- `.tbit_sync_table_metadata()`: uploads metadata.json, version_history.json, versioned snapshots per table
- Repo-level: routing.json, manifest.json, migration_history.json → S3 `.metadata/`
- Interactive confirmation via `.confirm` param (default TRUE, FALSE for tests/scripts)
- Graceful per-table error handling with summary
- Filters out non-table dirs (input_files, renv, R, tests, hidden dirs)

### Decisions Made

- `tbit_sync_manifest()` scans flat `input_files/` dir, computes file SHAs, compares against `.tbit/manifest.json`
- `tbit_sync()` processes manifest results using `tbit_write()` per table
- `tbit_sync_routing()` pushes all git metadata to S3 (interactive confirmation)
- `tbit_validate()` checks git-S3 consistency
- `tbit_status()` shows uncommitted changes + sync state

### Session Log

| Date | Summary | Next Steps |
|------|---------|------------|
| 2026-02-15 | Phase 6 created | Implement Chunk 1 |
| 2026-02-15 | Chunk 1 done: tbit_sync_manifest() + 29 tests (618 total) | Chunk 2: tbit_sync() |
| 2026-02-15 | Chunk 2 done: tbit_sync() + 42 tests (660 total) | Chunk 3: tbit_sync_routing() |
| 2026-02-15 | Chunk 3 done: tbit_sync_routing() + 32 tests (692 total) | Chunk 4: tbit_validate() |
