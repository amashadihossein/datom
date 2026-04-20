# Phase 12: Filesystem Backend

## Goal

Add a local filesystem storage backend so datom works without S3. Enables CRAN vignettes, offline development, and lower-cost workflows on shared filesystems.

## Context

- Storage dispatch layer already exists (`utils-storage.R`) with `switch(backend, s3 = ...)` — adding `local` is a new arm
- GitHub PAT always required (decided during design). No "demo mode" without governance
- Git always required. GitHub always required for non-trivial use
- For CRAN vignette: `eval = FALSE` with pre-computed outputs (no credential-free escape hatch)
- `conn$bucket` renamed to `conn$root` (Chunk 0) — backend-neutral naming for the root location
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

### `conn$root` (generalized from `bucket`)

Rename `conn$bucket` → `conn$root` to be backend-neutral. S3: root = bucket name. Local: root = directory path. Azure: root = container. Each backend's functions interpret `root` in context. Done as Chunk 0 before adding local backend.

### `conn$client` for local

`NULL` — not needed. `.datom_local_*()` functions use `conn$root` (path) + `conn$prefix` directly via `fs::`.

## Chunks

### Chunk 0: Generalize conn field names (`bucket` → `root`)

**Scope**: Pure mechanical rename — no behavior change. Makes conn fields backend-neutral before adding local backend.

**Changes**:
- `conn$bucket` → `conn$root` everywhere (R/, tests/)
- `conn$gov_bucket` → `conn$gov_root` everywhere
- `new_datom_conn()` parameter `bucket` → `root`, `gov_bucket` → `gov_root`
- `mock_datom_conn()` in test helper updated
- `.datom_gov_conn()` updated
- `print.datom_conn()` labels updated
- `ref.json` field: `bucket` → `root` (and `.datom_create_ref()` / `.datom_resolve_ref()`)
- `utils-s3.R`: `conn$root` mapped to `Bucket =` in paws API calls
- Display messages in `query.R`, `sync.R`, `ref.R` updated

**Not changed**: `region`/`gov_region` — kept for now (only S3 uses it; local ignores via NULL). `datom_store_s3$bucket` field unchanged (store objects are backend-specific).

**Tests**: All existing tests pass with renamed fields. Test count ≥ 1039.

**Status**: Complete

### Chunk 1: `datom_store_local()` constructor

**Scope**: Store component constructor, validation, predicates, print method.

**Functions**:
- `datom_store_local(path)` — exported constructor
- `is_datom_store_local(x)` — exported predicate
- `print.datom_store_local(x, ...)` — S3 print method
- Update `.is_datom_store_component()` to include `datom_store_local`

**Status**: Complete

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

Key: full storage key built via `.datom_build_storage_key(conn$prefix, key)`, then resolved against `conn$root` (root path) using `fs::path()`.

**Tests**: Each function with temp directories.

**Status**: Complete

### Chunk 3: Dispatch wiring

**Scope**: Add `local` arm to every `switch` in `utils-storage.R`.

**Changes**: Each `.datom_storage_*()` function gets `local = .datom_local_*()`.

**Tests**: Existing dispatch tests + new local dispatch tests.

**Status**: Complete

### Chunk 4: Connection + init integration

**Scope**: Wire local stores through `datom_store()`, `new_datom_conn()`, `datom_init_repo()`, `datom_get_conn()`, `datom_clone()`.

**Changes**:
- `datom_store()` accepts `datom_store_local` components (already via `.is_datom_store_component()` update in chunk 1)
- `new_datom_conn()` accepts `backend = "local"`, relaxes `root` validation (path instead of S3 bucket name)
- `datom_init_repo()` builds local conn with `client = NULL`, skips S3 namespace check for local backend
- `datom_get_conn()` developer + reader paths work with local stores (no `.datom_s3_client()` calls for local)
- `project.yaml` serialization: `type: local`, `root: /some/dir` instead of S3-specific fields

**S3-specific store field accesses that need backend-aware handling**:
- `.datom_create_ref()` (ref.R:30) — reads `data_store$bucket` and `data_store$region`. Local store has `$path` not `$bucket`, and no `$region`. Need backend-neutral accessor or store method.
- `.datom_render_readme()` (conn.R:411) — reads `store$data$bucket`, `$region` for README template. Local needs different template or conditional fields.
- `datom_init_repo()` S3 namespace check (conn.R:263-275) — reads `store$data$access_key`, `$secret_key`, creates `.datom_s3_client()`. Must skip or branch for local.
- `datom_init_repo()` S3 push block (conn.R:452-475) — creates S3 clients from store credentials. Local backend uses `.datom_storage_*()` dispatch instead.
- `.datom_get_conn_developer()` (conn.R:660-710) — reads `store$data$bucket`, `$access_key`, `$secret_key`, creates S3 clients. Local: `client = NULL`, root from `$path`.
- `.datom_get_conn_reader()` (conn.R:729-763) — same pattern as developer path.
- `project.yaml` cross-check (conn.R:668-675) — reads `data_storage$root` from yaml, compares to `store$data$bucket`. Local: compare to `store$data$path`.

**Design approach**: Each store type should expose a `$root` field (S3: bucket, local: path) so business logic can use `store$data$root` uniformly. Alternatively, add a generic accessor. Decision made during implementation.

**Tests**: Init + get_conn + clone round-trips with local stores. Cross-check tests with local yaml.

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

Chunk 0 complete (commit `5b043de`). Chunk 1 complete (commit `4047b83`). Chunk 2 complete (commit `2f59653`). Chunk 3 complete (commit `7442995`). Starting Chunk 4.

**Branch**: `phase/12-filesystem-backend` (off `main`)

**Key context for new sessions**:
- `conn$root` is the generalized field (was `conn$bucket`). S3 stores still have `$bucket` on the store object; the conn maps it to `$root`.
- `project.yaml` now uses `root` (not `bucket`) under `storage.data` and `storage.governance`.
- `ref.json` uses `root` (not `bucket`) under `current` and `previous` entries.
- `datom_store_s3$bucket` is **unchanged** — store objects remain backend-specific.
- `datom_store_local$path` is the local store field. Constructor auto-creates dirs, normalizes to absolute path.
- `.is_datom_store_component()` recognizes both `datom_store_s3` and `datom_store_local`.
- All `.datom_local_*()` functions implemented in `R/utils-local.R` — mirror `.datom_s3_*()` API.
- Dispatch wired: all `.datom_storage_*()` functions route `backend = "local"` to `.datom_local_*()`.
- `region`/`gov_region` remain on conn (not removed). Local backend will set them to NULL.
- Test count: 1113. Must not drop below this.
- Key files: `R/conn.R` (constructor, init, get_conn), `R/utils-storage.R` (dispatch), `R/utils-s3.R` (S3 backend), `R/utils-local.R` (local backend), `R/store.R` (store constructors), `R/ref.R` (ref.json).

## Acceptance Criteria

- [ ] `datom_store_local()` constructor works with validation
- [ ] All `.datom_local_*()` functions pass tests
- [ ] Dispatch routes `backend = "local"` correctly
- [ ] `datom_init_repo()` → `datom_write()` → `datom_read()` works end-to-end with local stores + GitHub
- [ ] `project.yaml` round-trips local store config
- [ ] `devtools::check()` clean (0 errors, 0 warnings, 0 notes)
- [ ] Full test suite count ≥ 1039 (no regressions)
