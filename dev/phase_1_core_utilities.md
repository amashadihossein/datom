# Phase 1: Core Utilities

**Status**: � In Progress  
**Started**: 2026-02-07  
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

**Chunk**: 1 — SHA Computation  
**Stage**: 🔵 DEVELOP → 🟡 FEEDBACK

### Chunk Queue

| # | Chunk | Functions | Status |
|---|-------|-----------|--------|
| 1 | SHA computation | `.tbit_compute_data_sha()`, `.tbit_compute_metadata_sha()`, `.tbit_compute_file_sha()` | 🟡 Ready for QA |
| 2 | Path utilities | `.tbit_build_s3_path()`, `.tbit_parse_s3_uri()` | ⚪ Not started |
| 3 | Name validation | `.tbit_validate_name()` | ⚪ Not started |
| 4 | Repo validation | `is_valid_tbit_repo()`, `tbit_repository_check()` | ⚪ Not started |

### Active Chunk Details

**Scope**: Three internal SHA-256 functions for content-addressing  
**Files**: `R/utils-sha.R`, `tests/testthat/test-utils-sha.R`  
**Design decision**: Column/row sorting OFF by default (input preserved as-is), optional via `sort_columns`/`sort_rows` params  
**Test file**: `devtools::test(filter = "utils-sha")`  
**Debug/playground snippet**:
```r
devtools::load_all()
df <- data.frame(x = 1:3, y = c("a", "b", "c"))
sha1 <- .tbit_compute_data_sha(df)
sha2 <- .tbit_compute_data_sha(df[, c("y", "x")])  # different — column order matters
sha3 <- .tbit_compute_data_sha(df[, c("y", "x")], sort_columns = TRUE)  # same as sha1

meta <- list(name = "test", data_sha = sha1)
.tbit_compute_metadata_sha(meta)  # the "tbit version"
```

---

## Current State

Chunk 1 implemented, ready for QA.

### Completed Chunks

_None yet — Chunk 1 awaiting QA_

### Decisions Made

- **Column/row sorting**: OFF by default. Input data is preserved as-is. Optional `sort_columns` and `sort_rows` params available for deduplication use cases.

### Blockers

_None_

### Deferred Items

Items discovered during this phase but out of scope. Will be moved to backlog on phase completion.

| Item | Why Deferred | Notes |
|------|--------------|-------|
| _None yet_ | | |

---

## Session Log

| Date | Summary | Next Steps |
|------|---------|------------|
| 2026-02-07 | Implemented SHA functions with sort options, created tests | QA: run tests, debug walkthrough |

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
