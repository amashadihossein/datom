# Phase 10: Remotes Refactor

## Goal

Replace scattered storage params (`bucket`, `prefix`, `region`) and env-var credential conventions with a unified `datom_remotes` object that bundles storage backend config + credentials + git remote config. Validate connectivity at construction time. Lay groundwork for pluggable storage backends (network drive, GCS, Azure).

## Motivation

1. **Awkward credential coupling**: User must pre-set `DATOM_{PROJECT}_ACCESS_KEY_ID` env vars *before* calling `datom_init_repo()`, but `project_name` (which defines the naming convention) is a parameter *of* that function. Circular dependency.
2. **S3 params leak into API**: `datom_init_repo(bucket = ..., prefix = ..., region = ...)` exposes AWS-specific concepts. A network drive backend wouldn't have any of these.
3. **Late failure**: Bad credentials are only detected mid-init after local folders/git have been created, leaving a mess.
4. **No GitHub repo creation**: Users must manually create the GitHub repo before calling `datom_init_repo()`. The sandbox tooling does this via `gh` CLI, but it should be a first-class option.

## Design Decisions

### `datom_remotes` Object

A typed S3-classed object that encapsulates **everything** about "where data lives and how to authenticate":

```r
# AWS S3 backend
remotes <- datom_remotes_s3(
  bucket     = "my-bucket",
  prefix     = "project/",
  region     = "us-east-1",
  access_key = keyring::key_get(...),
  secret_key = keyring::key_get(...),
  github_pat = keyring::key_get(...)
)

# Future: network drive backend (no storage credentials)
remotes <- datom_remotes_network(
  path       = "/mnt/shared/datom-store",
  github_pat = keyring::key_get(...)
)
```

### Validation at Construction Time (Layered)

**Structural + identity validation** in `datom_remotes_s3()`:
- AWS keys non-empty, correct format
- STS `GetCallerIdentity` — proves keys are real (~100ms)
- `HeadBucket` on target bucket — proves access
- GitHub `GET /user` — proves PAT is valid
- All checked before returning. `validate = TRUE` default; skip with `FALSE` for tests/offline.

**Access validation** in `datom_init_repo()` / `datom_get_conn()`:
- Reorder so all validation happens *before* any filesystem/git side effects.

### GitHub Repo Auto-Creation

When `create_repo = TRUE` (default `FALSE`):
- `datom_init_repo()` creates the GitHub repo via GitHub REST API (`httr2`, not `gh` CLI)
- Repo name derived from `project_name` (normalized: lowercase, underscores → hyphens)
- Optional `github_org` for org repos; defaults to personal repo
- If repo already exists and `create_repo = TRUE`, reuse it (idempotent)

When `create_repo = FALSE`:
- `remote_url` must be provided on the remotes object
- Existing behavior

### Env Var Bridge (Internal)

`.datom_install_remotes(remotes, project_name)` — the single place that knows the naming convention:
- For S3: sets `DATOM_{PROJECT}_ACCESS_KEY_ID`, `DATOM_{PROJECT}_SECRET_ACCESS_KEY`, `GITHUB_PAT`
- For network drive: only `GITHUB_PAT` (if developer)
- Called inside `datom_init_repo()` / `datom_get_conn()` before existing credential checks

This preserves backward compatibility for all downstream code that reads env vars.

### Repo Name = Project Name

The `repo_name` for GitHub auto-creation is derived from `project_name`:
- `"STUDY_001"` → `"study-001"` (lowercase, underscores to hyphens)
- User can override via `remote_url` on the remotes object if they want a different name

### `remote_url` vs `create_repo`

Mutually exclusive paths:
- Provide `remote_url` on the remotes object → use existing repo
- Set `create_repo = TRUE` on `datom_init_repo()` → create repo from `project_name`
- Constructor errors if both `remote_url` and auto-creation params are supplied

## Class Hierarchy

```
datom_remotes (base class)
├── datom_remotes_s3      — bucket, prefix, region, access_key, secret_key, session_token
├── datom_remotes_network — path (future)
├── datom_remotes_gcs     — bucket, prefix, credentials (future)
└── datom_remotes_azure   — container, prefix, credentials (future)

All carry:
├── github_pat (for git operations; NULL for reader-only)
├── remote_url (resolved GitHub URL; NULL if create_repo)
├── github_org (for repo creation; NULL for personal)
├── validated (logical — did connectivity checks pass?)
└── identity (list — aws_account_id, github_user, etc.)
```

## Chunks

### Chunk 1: `datom_remotes_s3()` Constructor + Validation

**Files**: `R/remotes.R` (new), `tests/testthat/test-remotes.R` (new)

- `datom_remotes_s3()` constructor with all params
- Structural validation (non-empty strings, correct types)
- Identity validation when `validate = TRUE`:
  - STS `GetCallerIdentity` (AWS)
  - `HeadBucket` (bucket access)
  - GitHub `GET /user` (PAT validity)
- `print.datom_remotes_s3()` — shows config, masks secrets
- Tests with mocked S3/GitHub responses

### Chunk 2: `.datom_install_remotes()` + Env Var Bridge

**Files**: `R/remotes.R`, `tests/testthat/test-remotes.R`

- `.datom_install_remotes(remotes, project_name)` — sets env vars
- `.datom_create_github_repo(project_name, org, pat, private)` — GitHub REST API via `httr2`
- Tests for env var setting, name derivation

### Chunk 3: Refactor `datom_init_repo()`

**Files**: `R/conn.R`, `tests/testthat/test-conn.R`

- Replace `bucket`, `prefix`, `region`, `remote_url` params with `remotes`
- Add `create_repo = FALSE` param
- Reorder: install remotes → validate access → create GitHub repo (if requested) → then fs/git side effects
- Update `project.yaml` writer to include `storage.type` from remotes class
- Update all existing tests

### Chunk 4: Refactor `datom_get_conn()` + `datom_clone()`

**Files**: `R/conn.R`, `tests/testthat/test-conn.R`

- Add optional `remotes` param to `datom_get_conn()` and `datom_clone()`
- If provided, install remotes using project_name from `project.yaml`
- If not provided, existing env var fallback still works
- Update all existing tests

### Chunk 5: Update Sandbox + E2E Tooling

**Files**: `dev/dev-sandbox.R`, `dev/e2e-test.R`

- `sandbox_up()` constructs `datom_remotes_s3()` and passes through
- Delete `sandbox_credentials()` — replaced by `datom_remotes_s3()`
- Simplify `e2e-test.R` flow
- Update `sandbox_recover()` to work with new pattern
- Run full E2E

### Chunk 6: Documentation + Cleanup

**Files**: `man/`, vignettes, `NAMESPACE`

- roxygen2 docs for all new exports
- Update credentials vignette
- Update getting-started vignette
- Remove dead `storage.credentials.*` from project.yaml template
- `devtools::document()`, `devtools::check()`

## Acceptance Criteria

- [ ] `datom_remotes_s3()` validates credentials and storage access at construction time
- [ ] `datom_init_repo(remotes = ...)` replaces `bucket`/`prefix`/`region`/`remote_url` params
- [ ] `datom_init_repo(create_repo = TRUE)` creates GitHub repo via API (no `gh` CLI)
- [ ] `datom_get_conn(remotes = ...)` and `datom_clone(remotes = ...)` accept remotes object
- [ ] No filesystem/git side effects before validation passes in `datom_init_repo()`
- [ ] Sandbox tooling uses `datom_remotes_s3()` instead of `sandbox_credentials()`
- [ ] Full test suite passes, count ≥ 962
- [ ] E2E workflow succeeds via `dev/e2e-test.R`
- [ ] `print.datom_remotes_s3()` masks secrets
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
