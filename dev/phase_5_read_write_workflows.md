# Phase 5: Read/Write Workflows

**Status**: 🟢 In Progress  
**Started**: 2026-02-15  
**Target**: Core read/write operations, query functions  
**Estimated Effort**: 1-2 weeks

---

## Objective

Implement the core data access layer: `tbit_read()`, `tbit_write()`, `tbit_list()`, and `tbit_history()`. These are the primary user-facing operations — everything else (sync, migration) builds on these primitives.

---

## Design Decisions

### Phase Strategy

**Incremental implementation:**
1. Start with read path (simpler, no git)
2. Then write path (git commits + S3 upload)
3. Defer batch ops (sync) to Phase 6

**Testing approach:**
- Mock S3 for unit tests (existing pattern from Phase 2)
- Use real temp git repos (existing pattern from Phase 3)
- Integration tests with full flow (git + S3 mocked)

### Scope Clarifications

**What "read" means:**
- Fetch metadata from S3 (`{table}/metadata.json`, `version_history.json`)
- Resolve version (NULL → current, metadata_sha → lookup)
- Download parquet file (`{data_sha}.parquet`)
- Read with arrow, return data frame
- Routing deferred to Phase 6 (always use default read for now)

**What "write" means:**
- Validate data frame
- Compute data SHA + metadata SHA
- Change detection (compare against existing metadata)
- Convert to parquet (in-memory)
- Write metadata to git (`{table}/metadata.json`, `version_history.json`)
- Git commit + push
- Upload parquet to S3
- Update manifest.json locally + in S3

**Metadata-only write:**
- When data SHA unchanged but metadata differs
- Only updates metadata files in git + S3
- No parquet upload

**tbit_list:**
- Read manifest.json from S3
- Filter by pattern if provided
- Return table summary data frame

**tbit_history:**
- Read version_history.json from S3 for one table
- Return latest N versions with author, timestamp, commit message

---

## Scope

### In Scope

| File | Functions | Description |
|------|-----------|-------------|
| `R/read_write.R` | `tbit_read()` | Read table from S3 (version resolution) |
| | `tbit_write()` | Write table to git + S3 (change detection) |
| | `.tbit_write_table()` | Internal: core write logic |
| | `.tbit_metadata_sha()` | Compute metadata SHA (sorted fields) |
| | `.tbit_has_changes()` | Compare against existing metadata |
| `R/query.R` | `tbit_list()` | List tables from manifest |
| | `tbit_history()` | Show version history |

### Out of Scope

- Routing via `routing.json` — Phase 6
- Batch sync (`tbit_sync_manifest`, `tbit_sync`) — Phase 6
- `tbit_sync_routing()` — Phase 6
- `tbit_status()`, `tbit_validate()` — Phase 6
- Migration operations — future

---

## Dependencies

**Phase 4 deliverables we use:**
- `tbit_conn` (with role, path, bucket, prefix, s3_client)
- `tbit_get_conn()` — connections with credentials
- `.tbit_check_credentials()` — validated env vars

**Phase 3 deliverables we use:**
- `.tbit_git_commit()` — atomic commits
- `.tbit_git_push()` — push with fetch+merge

**Phase 2 deliverables we use:**
- `.tbit_s3_upload()` / `.tbit_s3_download()` — S3 ops
- `.tbit_s3_exists()` — check file existence
- `.tbit_s3_read_json()` / `.tbit_s3_write_json()` — metadata I/O

**Phase 1 deliverables we use:**
- `.tbit_compute_data_sha()` — SHA of data frame
- `.tbit_validate_name()` — table name validation
- `.tbit_full_s3_key()` — construct S3 paths

---

## Chunk Queue

| # | Chunk | Functions | Status |
|---|-------|-----------|--------|
| 1 | Read infrastructure | `.tbit_read_metadata()`, `.tbit_resolve_version()`, `.tbit_read_parquet()` | ⚪ Not started |
| 2 | tbit_read() | User-facing read with version resolution | ⚪ Not started |
| 3 | Write infrastructure | `.tbit_metadata_sha()`, `.tbit_has_changes()`, `.tbit_write_metadata()` | ⚪ Not started |
| 4 | tbit_write() — full write | Data + metadata write with git + S3 | ⚪ Not started |
| 5 | tbit_write() — metadata-only | Update metadata without data change | ⚪ Not started |
| 6 | Query operations | `tbit_list()`, `tbit_history()` | ⚪ Not started |

---

## Current Chunk

**Chunk**: 1 — Read infrastructure  
**Stage**: 🔵 DESIGN

### Proposed functions

```r
# Read metadata.json + version_history.json from S3
.tbit_read_metadata <- function(conn, name)
# Returns: list(current = metadata.json, history = version_history.json)

# Resolve version spec (NULL or metadata_sha) to data_sha
.tbit_resolve_version <- function(metadata_list, version)
# Returns: data_sha

# Download and read parquet from S3
.tbit_read_parquet <- function(conn, name, data_sha)
# Returns: data.frame
```

### Acceptance criteria

- [ ] `.tbit_read_metadata()` fetches both files from S3 using existing S3 utils
- [ ] `.tbit_resolve_version(NULL)` returns current `data_sha` from `metadata.json`
- [ ] `.tbit_resolve_version("abc123...")` looks up in `version_history.json`, returns `data_sha`
- [ ] `.tbit_resolve_version()` aborts if version not found
- [ ] `.tbit_read_parquet()` downloads `{table}/{data_sha}.parquet` from S3
- [ ] `.tbit_read_parquet()` uses `arrow::read_parquet()` to return data frame
- [ ] All functions validate inputs (conn, name)

---

## Current State

### Completed Chunks

_None yet_

### Decisions Made

- Read first (simpler), then write
- Routing deferred to Phase 6 — always use direct arrow read for now
- Use existing S3/git wrappers (no new low-level code needed)

### Blockers

_None_

### Deferred Items

| Item | Why Deferred | Notes |
|------|--------------|-------|
| Routing logic | Needs design clarity, not MVP critical | Phase 6 |
| Batch sync | Build on single read/write primitives | Phase 6 |

---

## Session Log

| Date | Summary | Next Steps |
|------|---------|------------|
| 2026-02-15 | Phase 5 created, chunk queue defined | Design + implement Chunk 1 |

---

## Completion Checklist

- [ ] All acceptance criteria met
- [ ] All tests passing
- [ ] `devtools::check()` clean
- [ ] All chunks committed
- [ ] Final push to remote
- [ ] Any API decisions documented in `tbit_specification.md`
- [ ] Deferred items moved to `dev/README.md` backlog
- [ ] Phase doc deleted
- [ ] README.md updated
