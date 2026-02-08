# Phase 1: Core Utilities

**Status**: 🟡 Not Started  
**Started**: _TBD_  
**Target**: Pure functions with no external dependencies (S3, git)  
**Estimated Effort**: 1 week

---

## Objective

Build and test the foundational utility functions that everything else depends on. These are pure functions that can be fully unit tested without mocking external services.

---

## Scope

### In Scope

| File | Functions | Description |
|------|-----------|-------------|
| `R/utils-sha.R` | `.tbit_compute_data_sha()` | SHA-256 of data frame via parquet |
| | `.tbit_compute_metadata_sha()` | SHA-256 of sorted metadata list |
| | `.tbit_compute_file_sha()` | SHA-256 of any file |
| `R/validate.R` | `is_valid_tbit_repo()` | Public validation function |
| | `tbit_repository_check()` | Internal detailed checks |
| _New_ | `.tbit_validate_name()` | Validate table name (filesystem safe) |
| _New_ | `.tbit_build_s3_path()` | Construct S3 keys from components |
| _New_ | `.tbit_parse_s3_uri()` | Parse `s3://bucket/prefix` URIs |

### Out of Scope (Later Phases)

- S3 operations (Phase 2)
- Git operations (Phase 3)
- Connection management (Phase 4)

---

## Acceptance Criteria

### SHA Functions

- [ ] `.tbit_compute_data_sha()` produces deterministic SHA for same data
- [ ] `.tbit_compute_data_sha()` different SHA for different data
- [ ] `.tbit_compute_data_sha()` same SHA regardless of row order? (decide: yes/no)
- [ ] `.tbit_compute_metadata_sha()` produces deterministic SHA for same metadata
- [ ] `.tbit_compute_metadata_sha()` same SHA regardless of field insertion order (alphabetical sort)
- [ ] `.tbit_compute_file_sha()` matches `sha256sum` command output

### Validation Functions

- [ ] `is_valid_tbit_repo()` returns FALSE for empty directory
- [ ] `is_valid_tbit_repo()` returns TRUE for properly initialized repo
- [ ] `is_valid_tbit_repo()` respects `checks` parameter for selective validation
- [ ] `tbit_repository_check()` returns detailed named list

### Name Validation

- [ ] `.tbit_validate_name()` accepts alphanumeric + underscore
- [ ] `.tbit_validate_name()` rejects special characters, spaces, slashes
- [ ] `.tbit_validate_name()` rejects reserved names (e.g., `.metadata`, `input_files`)

### Path Utilities

- [ ] `.tbit_build_s3_path()` correctly constructs paths with/without prefix
- [ ] `.tbit_parse_s3_uri()` extracts bucket and prefix from URI

---

## Implementation Order

1. **SHA functions** — already partially implemented, complete and test
2. **Path utilities** — needed by validation
3. **Validation functions** — complete implementation
4. **Name validation** — add new function

---

## Test Strategy

All tests in `tests/testthat/test-utils-sha.R` and `tests/testthat/test-validate.R`.

Use `withr::with_tempdir()` for filesystem tests.

---

## Current Chunk

**Chunk**: _Not started_  
**Stage**: ⚪ DESIGN | 🔵 DEVELOP | 🟡 FEEDBACK | ✅ COMPLETE

### Chunk Queue

| # | Chunk | Functions | Status |
|---|-------|-----------|--------|
| 1 | SHA computation | `.tbit_compute_data_sha()`, `.tbit_compute_metadata_sha()`, `.tbit_compute_file_sha()` | ⚪ Not started |
| 2 | Path utilities | `.tbit_build_s3_path()`, `.tbit_parse_s3_uri()` | ⚪ Not started |
| 3 | Name validation | `.tbit_validate_name()` | ⚪ Not started |
| 4 | Repo validation | `is_valid_tbit_repo()`, `tbit_repository_check()` | ⚪ Not started |

### Active Chunk Details

_To be filled when chunk starts:_

**Scope**:  
**Proposed signatures**:  
**Acceptance criteria**:  
**Test file**:  
**Debug/playground snippet**:

---

## Current State

_Not started. Update this section as work progresses._

### Completed Chunks

_None yet_

### Decisions Made

_Record design decisions here as they're made._

### Blockers

_None_

### Deferred Items

Items discovered during this phase but out of scope. Will be moved to backlog on phase completion.

| Item | Why Deferred | Notes |
|------|--------------|-------|
| _None yet_ | | |

---

## Session Log

_Brief notes from each work session._

| Date | Summary | Next Steps |
|------|---------|------------|
| _TBD_ | _Started phase_ | _..._ |

---

## Completion Checklist

Before marking this phase complete:

- [ ] All acceptance criteria met
- [ ] All tests passing
- [ ] `devtools::check()` clean
- [ ] All chunks committed
- [ ] Final push to remote
- [ ] Any API decisions documented in `tbit_specification.md`
- [ ] Deferred items moved to `dev/README.md` backlog
- [ ] This file reviewed for learnings to transfer
- [ ] README.md updated to mark phase complete
- [ ] This file deleted
