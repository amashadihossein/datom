# Phase 10: Store Abstraction

## Goal

Replace scattered storage params (`bucket`, `prefix`, `region`) and env-var credential conventions with a unified `datom_store` object that bundles storage backend config + credentials + git remote config. Validate connectivity at construction time. Lay groundwork for pluggable storage backends (shared folder, GCS, Azure).

## Motivation

1. **Awkward credential coupling**: User must pre-set `DATOM_{PROJECT}_ACCESS_KEY_ID` env vars *before* calling `datom_init_repo()`, but `project_name` (which defines the naming convention) is a parameter *of* that function. Circular dependency.
2. **S3 params leak into API**: `datom_init_repo(bucket = ..., prefix = ..., region = ...)` exposes AWS-specific concepts. A shared folder backend wouldn't have any of these.
3. **Late failure**: Bad credentials are only detected mid-init after local folders/git have been created, leaving a mess.
4. **No GitHub repo creation**: Users must manually create the GitHub repo before calling `datom_init_repo()`. The sandbox tooling does this via `gh` CLI, but it should be a first-class option.

## Design Decisions

### `datom_store` Object

A typed S3-classed object that encapsulates **everything** about "where data lives and how to authenticate":

```r
# AWS S3 backend
store <- datom_store_s3(
  bucket     = "my-bucket",
  prefix     = "project/",
  region     = "us-east-1",
  access_key = keyring::key_get(...),
  secret_key = keyring::key_get(...),
  github_pat = keyring::key_get(...)
)

# Future: shared folder backend (no storage credentials)
store <- datom_store_folder(
  path       = "/mnt/shared/datom-store",
  github_pat = keyring::key_get(...)
)
```

### Validation at Construction Time (Layered)

**Structural + identity validation** in `datom_store_s3()`:
- AWS keys non-empty, correct format
- STS `GetCallerIdentity` — proves keys are real (~100ms)
- `HeadBucket` on target bucket — proves access
- GitHub `GET /user` — proves PAT is valid
- All checked before returning. `validate = TRUE` default; skip with `FALSE` for tests/offline.

**Access validation** in `datom_init_repo()` / `datom_get_conn()`:
- Reorder so all validation happens *before* any filesystem/git side effects.

### GitHub Repo Auto-Creation

When `create_repo = TRUE` (default `FALSE`) in `datom_init_repo()`:
- Creates the GitHub repo via GitHub REST API (`httr2`, not `gh` CLI)
- Repo name derived from `project_name` (normalized: lowercase, underscores → hyphens)
- Optional `github_org` on the store object for org repos; defaults to personal repo

**Safety guard** (checked in `datom_init_repo()`, not at store construction — because `project_name` determines the repo name):
- If repo doesn't exist → create it, proceed
- If repo exists + empty → reuse (idempotent, handles prior failed init)
- If repo exists + has content → **abort before any local side effects**, with actionable error message

When `create_repo = FALSE`:
- `remote_url` must be provided on the store object
- Existing behavior

### Env Var Bridge (Internal)

`.datom_install_store(store, project_name)` — the single place that knows the naming convention:
- For S3: sets `DATOM_{PROJECT}_ACCESS_KEY_ID`, `DATOM_{PROJECT}_SECRET_ACCESS_KEY`, `GITHUB_PAT`
- For folder: only `GITHUB_PAT` (if developer)
- Called inside `datom_init_repo()` / `datom_get_conn()` before existing credential checks

This preserves backward compatibility for all downstream code that reads env vars.

### Repo Name = Project Name

The `repo_name` for GitHub auto-creation is derived from `project_name`:
- `"STUDY_001"` → `"study-001"` (lowercase, underscores to hyphens)
- User can override via `remote_url` on the store object if they want a different name

### `remote_url` vs `create_repo`

Mutually exclusive paths:
- Provide `remote_url` on the store object → use existing repo
- Set `create_repo = TRUE` on `datom_init_repo()` → create repo from `project_name`
- Error if both `remote_url` and `github_org` are supplied (ambiguous intent)

## Function Signatures

### `datom_init_repo(path, project_name, store, create_repo = FALSE)`

- `store` replaces `bucket`, `prefix`, `region`, `remote_url`
- `create_repo = TRUE` → auto-create GitHub repo (name derived from `project_name`)
- `create_repo = FALSE` → `store$remote_url` must be set
- Validation order: install store → check credentials → check repo safety → **then** local side effects

### `datom_get_conn(path = NULL, store = NULL, project_name = NULL)`

Two paths:
- **Developer** (`path` provided): reads storage config from `.datom/project.yaml`. If `store` also provided, uses it for credentials only (secrets not in yaml). If `store` not provided, falls back to env vars.
- **Reader** (`store` + `project_name`, no `path`): no local repo, store provides everything (storage config + credentials).

### `datom_clone(path, store = NULL, ...)`

- `path` is always required (local clone destination)
- `store` is the preferred way to supply remote info — extracts `remote_url` and `github_pat`
- Without `store`, pass `remote_url` and optionally `github_pat` as named args (captured from `...`)
- Remaining `...` forwarded to `git2r::clone()`
- After clone, returns `datom_get_conn(path)` as today (still needs store/env vars for S3 access)

## Class Hierarchy

```
datom_store (base class)
├── datom_store_s3      — bucket, prefix, region, access_key, secret_key, session_token
├── datom_store_folder  — path (future)
├── datom_store_gcs     — bucket, prefix, credentials (future)
└── datom_store_azure   — container, prefix, credentials (future)

All carry:
├── github_pat  (for git operations; NULL for reader-only)
├── remote_url  (resolved GitHub URL; NULL if create_repo)
├── github_org  (for repo creation; NULL for personal)
├── validated   (logical — did connectivity checks pass?)
└── identity    (list — aws_account_id, github_user, etc.)
```

## Chunks

### Chunk 1: `datom_store_s3()` Constructor + Validation

**Files**: `R/store.R` (new), `tests/testthat/test-store.R` (new)

- `datom_store_s3()` constructor with all params
- Structural validation (non-empty strings, correct types)
- Identity validation when `validate = TRUE`:
  - STS `GetCallerIdentity` (AWS)
  - `HeadBucket` (bucket access)
  - GitHub `GET /user` (PAT validity)
- `print.datom_store_s3()` — shows config, masks secrets
- Tests with mocked S3/GitHub responses

### Chunk 2: `.datom_install_store()` + GitHub Repo Creation

**Files**: `R/store.R`, `tests/testthat/test-store.R`

- `.datom_install_store(store, project_name)` — sets env vars per convention
- `.datom_create_github_repo(project_name, org, pat, private)` — GitHub REST API via `httr2`
- Tests for env var setting, name derivation, repo creation

### Chunk 3: Refactor `datom_init_repo()`

**Files**: `R/conn.R`, `tests/testthat/test-conn.R`

- Replace `bucket`, `prefix`, `region`, `remote_url` params with `store`
- Add `create_repo = FALSE` param
- Reorder: install store → validate access → create GitHub repo (if requested) → then fs/git side effects
- Update `project.yaml` writer to include `storage.type` from store class
- Update all existing tests

### Chunk 4: Refactor `datom_get_conn()` + `datom_clone()`

**Files**: `R/conn.R`, `tests/testthat/test-conn.R`

**`datom_get_conn(path = NULL, store = NULL, project_name = NULL)`**:
- Developer path (`path`): reads config from `project.yaml`; `store` optional for credentials
- Reader path (`store` + `project_name`): replaces old `bucket`/`prefix`/`project_name` params
- Error if neither `path` nor `store` + `project_name` supplied

**`datom_clone(path, store = NULL, ...)`**:
- `path` always required (local destination)
- `store` preferred: extracts `remote_url` + `github_pat`
- Without `store`: `remote_url` and `github_pat` accepted as named args in `...`
- After clone, calls `datom_get_conn(path)` — needs store/env vars for S3 at that point
- Update all existing tests

### Chunk 5: Update Sandbox + E2E Tooling

**Files**: `dev/dev-sandbox.R`, `dev/e2e-test.R`

- `sandbox_up()` constructs `datom_store_s3()` and passes through
- Delete `sandbox_credentials()` — replaced by `datom_store_s3()`
- Simplify `e2e-test.R` flow
- Update `sandbox_recover()` to work with new pattern
- Run full E2E

### Chunk 6: Documentation + Cleanup

**Files**: `man/`, vignettes, `NAMESPACE`

- roxygen2 docs for all new exports (`datom_store_s3`)
- Update credentials vignette
- Update getting-started vignette
- Remove dead `storage.credentials.*` from project.yaml template
- `devtools::document()`, `devtools::check()`

## Acceptance Criteria

- [ ] `datom_store_s3()` validates credentials and storage access at construction time
- [ ] `datom_init_repo(store = ...)` replaces `bucket`/`prefix`/`region`/`remote_url` params
- [ ] `datom_init_repo(create_repo = TRUE)` creates GitHub repo via API (no `gh` CLI)
- [ ] `datom_get_conn(store = ...)` and `datom_clone(store = ...)` accept store object
- [ ] No filesystem/git side effects before validation passes in `datom_init_repo()`
- [ ] Sandbox tooling uses `datom_store_s3()` instead of `sandbox_credentials()`
- [ ] Full test suite passes, count ≥ 962
- [ ] E2E workflow succeeds via `dev/e2e-test.R`
- [ ] `print.datom_store_s3()` masks secrets
- [ ] `storage.type` written to `project.yaml`

## Status

| Chunk | Status | Notes |
|-------|--------|-------|
| 1 | not started | |
| 2 | not started | |
| 3 | not started | |
| 4 | not started | |
| 5 | not started | |
| 6 | not started | |

## Dependencies

- `httr2` — for GitHub REST API (repo creation, PAT validation). Check if already in DESCRIPTION; if not, add.
- `paws.storage` — already a dependency (STS + S3 checks)
