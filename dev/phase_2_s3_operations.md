# Phase 2: S3 Operations

**Status**: 🟢 In Progress  
**Started**: 2026-02-09  
**Target**: Low-level S3 operations that all higher-level functions depend on  
**Estimated Effort**: 1 week

---

## Objective

Build and test the internal S3 utility functions. These wrap `paws.storage` with proper error handling, credential management, and the redirect chain pattern from the spec.

---

## Design Decisions

### Lightweight conn for now

Phase 4 builds a proper `tbit_conn` S3 class. For Phase 2, S3 functions accept a list:

```r
conn <- list(
  bucket = "my-bucket",
  s3_client = paws.storage::s3(
    config = list(credentials = list(...), region = "us-east-1")
  )
)
```

### Testing approach

- **Unit tests**: Mock `paws.storage` calls with `mockery::stub()` or `testthat::local_mocked_bindings()`
- **Integration tests**: Real S3 — gated behind `skip_if(Sys.getenv("TBIT_TEST_BUCKET") == "")` 
- **Error simulation**: Test 403, 404, network failure paths

### JSON serialization

Use `jsonlite` (standard in R ecosystem, already a dependency of paws).

---

## Scope

### In Scope

| File | Functions | Description |
|------|-----------|-------------|
| `R/utils-s3.R` | `.tbit_s3_client()` | Create paws S3 client from credentials |
| | `.tbit_s3_upload()` | Upload file to S3 (PutObject) |
| | `.tbit_s3_download()` | Download file from S3 (GetObject) |
| | `.tbit_s3_exists()` | Check if S3 object exists (HeadObject) |
| | `.tbit_s3_read_json()` | Read + parse JSON from S3 |
| | `.tbit_s3_write_json()` | Serialize + upload JSON to S3 |
| | `.tbit_s3_resolve_redirect()` | Follow .redirect.json chain |

### Out of Scope

- Connection class (`tbit_conn`) — Phase 4
- Git operations — Phase 3
- Read/write workflows — Phase 5

---

## Current Chunk

**Chunk**: 1 — S3 Client & Write JSON  
**Stage**: 🔵 DESIGN

### Chunk Queue

| # | Chunk | Functions | Status |
|---|-------|-----------|--------|
| 1 | S3 client + write JSON | `.tbit_s3_client()`, `.tbit_s3_write_json()` | 🔵 Design |
| 2 | Core S3 ops | `.tbit_s3_upload()`, `.tbit_s3_download()`, `.tbit_s3_exists()` | ⚪ Not started |
| 3 | JSON read | `.tbit_s3_read_json()` | ⚪ Not started |
| 4 | Redirect resolution | `.tbit_s3_resolve_redirect()` | ⚪ Not started |

---

## Current State

Phase just started.

### Completed Chunks

_None yet_

### Decisions Made

- Lightweight conn list for Phase 2 (full class in Phase 4)
- Mock-based unit tests + optional integration tests
- jsonlite for JSON serialization

### Blockers

_None_

### Deferred Items

| Item | Why Deferred | Notes |
|------|--------------|-------|
| _None yet_ | | |

---

## Session Log

| Date | Summary | Next Steps |
|------|---------|------------|
| 2026-02-09 | Phase 2 created, Chunk 1 design | Implement .tbit_s3_client() |

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
