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
| 2 | Batch sync | `tbit_sync()` | ⚪ Not started |
| 3 | Routing sync | `tbit_sync_routing()` | ⚪ Not started |
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
