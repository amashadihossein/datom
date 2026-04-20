# Phase 12: Filesystem Backend

## Goal

Add a local filesystem storage backend so datom works without S3. Enables CRAN vignettes, offline development, and lower-cost workflows on shared filesystems.

## Context

- Storage dispatch layer already exists (`utils-storage.R`) with `switch(backend, s3 = ...)` — adding `local` is a new arm
- GitHub PAT always required (decided during design). No "demo mode" without governance
- Git always required. GitHub always required for non-trivial use
- For CRAN vignette: `eval = FALSE` with pre-computed outputs (no credential-free escape hatch)
- `conn$bucket` reused as root directory path for local backend (avoids changing all callers)
- Local store path layout mirrors S3: `{root}/{prefix}/datom/{table}/...`

## Design Decisions

### Role derivation unchanged

```r
role <- if (!is.null(github_pat)) "developer" else "reader"
```

GitHub PAT backs the role claim in both S3 and local backends. Local without PAT = reader (no governance bypass).

### Backend × PAT matrix

| Storage | PAT | Role | Git remote |
|---------|-----|------|------------|
| Local | Yes | developer | GitHub |
| Local | No | reader | GitHub (read-only) |
| S3 | Yes | developer | GitHub |
| S3 | No | reader | none (S3 direct) |

### `datom_store_local(path)` design

- `path` = root directory (analogous to bucket)
- Validation: directory exists or is creatable, writable
- No credentials to validate (filesystem permissions are implicit)
- Class: `datom_store_local`

### `conn$bucket` for local

Reuse `bucket` field to hold root directory path. Backend-specific functions know how to interpret it. No structural changes to `datom_conn`.

### `conn$client` for local

`NULL` — not needed. `.datom_local_*()` functions use `conn$bucket` (path) + `conn$prefix` directly via `fs::`.

## Chunks

### Chunk 1: `datom_store_local()` constructor

**Scope**: Store component constructor, validation, predicates, print method.

**Functions**:
- `datom_store_local(path)` — exported constructor
- `is_datom_store_local(x)` — exported predicate
- `print.datom_store_local(x, ...)` — S3 print method
- Update `.is_datom_store_component()` to include `datom_store_local`

**Tests**: Constructor validation, predicate, print output, component check.

**Status**: Not started

### Chunk 2: `.datom_local_*()` backend functions

**Scope**: Filesystem implementations mirroring `.datom_s3_*()`.

**Functions**:
- `.datom_local_upload(conn, local_path, key)` — `fs::file_copy()`
- `.datom_local_download(conn, key, local_path)` — `fs::file_copy()` (reverse)
- `.datom_local_exists(conn, key)` — `fs::file_exists()`
- `.datom_local_read_json(conn, key)` — `jsonlite::fromJSON()`
- `.datom_local_write_json(conn, key, data)` — `jsonlite::toJSON()` + `writeLines()`
- `.datom_local_list_objects(conn, prefix)` — `fs::dir_ls()` (if needed)
- `.datom_local_delete(conn, key)` — `fs::file_delete()` (if needed)

Key: full storage key built via `.datom_build_storage_key(conn$prefix, key)`, then resolved against `conn$bucket` (root path) using `fs::path()`.

**Tests**: Each function with temp directories.

**Status**: Not started

### Chunk 3: Dispatch wiring

**Scope**: Add `local` arm to every `switch` in `utils-storage.R`.

**Changes**: Each `.datom_storage_*()` function gets `local = .datom_local_*()`.

**Tests**: Existing dispatch tests + new local dispatch tests.

**Status**: Not started

### Chunk 4: Connection + init integration

**Scope**: Wire local stores through `datom_store()`, `new_datom_conn()`, `datom_init_repo()`, `datom_get_conn()`, `datom_clone()`.

**Changes**:
- `datom_store()` accepts `datom_store_local` components (already via `.is_datom_store_component()` update in chunk 1)
- `new_datom_conn()` accepts `backend = "local"`, relaxes `bucket` validation (path instead of S3 bucket name)
- `datom_init_repo()` builds local conn with `client = NULL`
- `datom_get_conn()` reader path works with local stores
- `project.yaml` serialization: `type: local`, `path: /some/dir` instead of `bucket/region/access_key/secret_key`

**Tests**: Init + get_conn + clone round-trips with local stores.

**Status**: Not started

### Chunk 5: E2E + vignette

**Scope**: End-to-end workflow with local stores, CRAN vignette prep.

**Work**:
- Local sandbox helpers in `dev/dev-sandbox.R`
- Full write/read/sync/validate cycle with local stores + GitHub
- CRAN vignette strategy (eval=FALSE or pre-computed)
- `devtools::check()` clean

**Status**: Not started

### Chunk 6: Polish + spec update

**Scope**: Migrate learnings, clean up.

**Work**:
- Update `datom_specification.md` with local backend design
- Update `copilot-instructions.md` with new naming conventions
- Backlog review
- Phase completion procedure

**Status**: Not started

## Current State

Starting chunk 1.

## Acceptance Criteria

- [ ] `datom_store_local()` constructor works with validation
- [ ] All `.datom_local_*()` functions pass tests
- [ ] Dispatch routes `backend = "local"` correctly
- [ ] `datom_init_repo()` → `datom_write()` → `datom_read()` works end-to-end with local stores + GitHub
- [ ] `project.yaml` round-trips local store config
- [ ] `devtools::check()` clean (0 errors, 0 warnings, 0 notes)
- [ ] Full test suite count ≥ 1039 (no regressions)
