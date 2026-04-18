# Phase 10: Store Abstraction

## Goal

Replace scattered storage params (`bucket`, `prefix`, `region`) and env-var credential conventions with a two-component `datom_store` object (governance + data) that bundles storage backend config + credentials + git remote config. Validate connectivity at construction time. Lay groundwork for pluggable storage backends.

## Motivation

1. **Awkward credential coupling**: User must pre-set `DATOM_{PROJECT}_ACCESS_KEY_ID` env vars *before* calling `datom_init_repo()`, but `project_name` (which defines the naming convention) is a parameter *of* that function. Circular dependency.
2. **S3 params leak into API**: `datom_init_repo(bucket = ..., prefix = ..., region = ...)` exposes AWS-specific concepts. A shared folder backend wouldn't have any of these.
3. **Late failure**: Bad credentials are only detected mid-init after local folders/git have been created, leaving a mess.
4. **No GitHub repo creation**: Users must manually create the GitHub repo before calling `datom_init_repo()`. The sandbox tooling does this via `gh` CLI, but it should be a first-class option.
5. **No governance/data separation**: Routing files and data files are co-located. Phase 11 needs them separated — this phase establishes the two-component store shape so Phase 11 can wire governance to routing without restructuring the object.

## Design Decisions

### `datom_store_s3()` — Component Constructor

A type-specific constructor for an S3 storage component. Each component (governance or data) gets its own:

```r
gov <- datom_store_s3(
  bucket     = "org-governance",
  prefix     = "med-mm-001/",
  region     = "us-east-1",
  access_key = keyring::key_get(...),
  secret_key = keyring::key_get(...)
)

data <- datom_store_s3(
  bucket     = "study-bucket",
  prefix     = "trial/",
  region     = "us-east-1",
  access_key = keyring::key_get(...),
  secret_key = keyring::key_get(...)
)
```

Returns an S3-classed object (`datom_store_s3`) with validated credentials and storage access.

Future backends (`datom_store_local()`, `datom_store_gcs()`) will have their own constructors with backend-appropriate params. This is more R-idiomatic than a single `datom_store(type = ...)` factory — each backend has exactly the right params, no unused fields.

### `datom_store()` — Composite Constructor

Bundles governance + data components, plus git config:

```r
store <- datom_store(
  governance = datom_store_s3(bucket = "org-gov", ...),
  data       = datom_store_s3(bucket = "study-bucket", ...),
  github_pat = keyring::key_get(...)
)
store$role  # "developer" (github_pat provided)
```

```r
# Reader — no github_pat
store <- datom_store(
  governance = datom_store_s3(bucket = "org-gov", ...),
  data       = datom_store_s3(bucket = "study-bucket", ...)
)
store$role  # "reader"
```

### Role Derivation

`github_pat` presence on the composite store determines role:

- `github_pat` provided → `store$role = "developer"`
- `github_pat` omitted/NULL → `store$role = "reader"`

Downstream enforcement:
- `datom_init_repo()` requires developer store (errors if reader)
- `datom_clone()` requires `github_pat` (from store) — errors if reader
- `datom_get_conn()` accepts both; reader store → reader conn, developer store → developer conn

### Validation at Construction Time (Layered)

**In `datom_store_s3()` (per component):**
- AWS keys non-empty, correct format
- STS `GetCallerIdentity` — proves keys are real (~100ms)
- `HeadBucket` on target bucket — proves access
- `validate = TRUE` default; skip with `FALSE` for tests/offline

**In `datom_store()` (composite):**
- Both components must be valid store objects
- GitHub `GET /user` — proves PAT is valid (skipped for reader role)

**In `datom_init_repo()` / `datom_get_conn()`:**
- All validation happens *before* any filesystem/git side effects

### GitHub Repo Auto-Creation

When `create_repo = TRUE` (default `FALSE`) in `datom_init_repo()`:
- Creates the GitHub repo via GitHub REST API (`httr2`)
- Repo name derived from `project_name` (normalized: lowercase, underscores → hyphens)
- Optional `github_org` on the composite store for org repos; defaults to personal repo

**Safety guard:**
- If repo doesn't exist → create it, proceed
- If repo exists + empty → reuse (idempotent)
- If repo exists + has content → **abort before any local side effects**

When `create_repo = FALSE`:
- `remote_url` must be provided on the composite store

### Env Var Bridge (Internal, Temporary)

`.datom_install_store(store, project_name)` — the single place that injects store credentials into env vars so existing S3 code works unchanged:

- For S3 components: sets `DATOM_{PROJECT}_ACCESS_KEY_ID`, `DATOM_{PROJECT}_SECRET_ACCESS_KEY`, `GITHUB_PAT`
- Called inside `datom_init_repo()` / `datom_get_conn()` before existing credential checks

This is a **temporary bridge** — Phase 11 removes it by wiring `.datom_s3_client()` to accept credentials directly from the store.

### `project.yaml` — Two-Component Structure

```yaml
project_name: med_mm_001
storage:
  governance:
    type: s3
    bucket: org-governance
    prefix: med-mm-001/
    region: us-east-1
  data:
    type: s3
    bucket: study-bucket
    prefix: trial/
    region: us-east-1
git:
  remote_url: https://github.com/org/med-mm-001.git
```

Secrets are never persisted. The `type` field enables future backend dispatch. The two-component structure is established now so Phase 11 doesn't need to restructure the config.

### `remote_url` vs `create_repo`

Mutually exclusive paths:
- Provide `remote_url` on the composite store → use existing repo
- Set `create_repo = TRUE` on `datom_init_repo()` → create repo from `project_name`
- Error if both provided

## Function Signatures

### `datom_init_repo(path, project_name, store, create_repo = FALSE)`

- `store` (composite) replaces `bucket`, `prefix`, `region`, `remote_url`
- `create_repo = TRUE` → auto-create GitHub repo
- Validation order: check store → check repo safety → **then** local side effects
- Writes two-component `project.yaml`
- **Both governance and data stores receive their respective files** (routing files to governance, manifest to data — but file assignment is Phase 10 plumbing only; Phase 11 enforces the full separation)

### `datom_get_conn(path = NULL, store = NULL, project_name = NULL)`

Two paths:
- **Developer** (`path` provided): reads storage config from `project.yaml`. If `store` also provided, uses it for credentials (secrets not in yaml).
- **Reader** (`store` + `project_name`, no `path`): no local repo, store provides everything.

### `datom_clone(path, store)`

- `path` always required (local clone destination)
- `store` required — extracts `remote_url` and `github_pat`
- After clone, returns `datom_get_conn(path)` as today

## Class Hierarchy

```
datom_store (composite)
├── governance  → datom_store_s3 (or future: datom_store_local, datom_store_gcs)
├── data        → datom_store_s3 (or future: datom_store_local, datom_store_gcs)
├── role        ("developer" if github_pat provided, "reader" if NULL)
├── github_pat  (for git operations; NULL for reader)
├── remote_url  (resolved GitHub URL; NULL if create_repo)
├── github_org  (for repo creation; NULL for personal)
├── validated   (logical)
└── identity    (list — github_user, etc.)

datom_store_s3 (component)
├── bucket, prefix, region
├── access_key, secret_key, session_token
├── validated   (logical)
└── identity    (list — aws_account_id, etc.)
```

## Chunks

### Chunk 1: `datom_store_s3()` Component Constructor + Validation

**Files**: `R/store.R` (new), `tests/testthat/test-store.R` (new)

- `datom_store_s3()` constructor with S3-specific params
- Structural validation (non-empty strings, correct types)
- Identity validation when `validate = TRUE`:
  - STS `GetCallerIdentity` (AWS)
  - `HeadBucket` (bucket access)
- `print.datom_store_s3()` — shows config, masks secrets
- Tests with mocked S3 responses

### Chunk 2: `datom_store()` Composite Constructor + GitHub Validation

**Files**: `R/store.R`, `tests/testthat/test-store.R`

- `datom_store(governance, data, github_pat, remote_url, github_org)` constructor
- Validates both components are store objects
- Role derivation from `github_pat`
- GitHub `GET /user` validation (skipped for reader)
- `print.datom_store()` — shows both components, role, masks secrets
- Tests for developer and reader composite stores

### Chunk 3: `.datom_install_store()` + GitHub Repo Creation

**Files**: `R/store.R`, `tests/testthat/test-store.R`

- `.datom_install_store(store, project_name)` — sets env vars per convention (temporary bridge)
- `.datom_create_github_repo(project_name, org, pat, private)` — GitHub REST API via `httr2`
- Repo name derivation from project_name
- Safety guard (exists + content → abort)
- Tests for env var setting, name derivation, repo creation
- Use `withr::local_envvar()` in tests to prevent env var pollution across test runs

### Chunk 4: Refactor `datom_init_repo()`

**Files**: `R/init.R`, `tests/testthat/test-init.R`

- Replace `bucket`, `prefix`, `region`, `remote_url` params with `store`
- Add `create_repo = FALSE` param
- Reorder: validate store → create GitHub repo (if requested) → then fs/git side effects
- Write two-component `project.yaml` (`storage.governance` + `storage.data`)
- Update all existing tests

### Chunk 5: Refactor `datom_get_conn()` + `datom_clone()`

**Files**: `R/conn.R`, `R/clone.R`, tests

**`datom_get_conn(path = NULL, store = NULL, project_name = NULL)`**:
- Developer path (`path`): reads two-component config from `project.yaml`; `store` optional for credentials
- Reader path (`store` + `project_name`): store provides everything
- Error if neither `path` nor `store` + `project_name` supplied

**`datom_clone(path, store)`**:
- `store` required: extracts `remote_url` + `github_pat`
- After clone, calls `datom_get_conn(path)`
- Update all existing tests

### Chunk 6: Update Sandbox + E2E

**Files**: `dev/dev-sandbox.R`, `dev/e2e-test.R`

- `sandbox_up()` constructs `datom_store()` with two `datom_store_s3()` components
- Delete `sandbox_credentials()` — replaced by store constructors
- Simplify E2E flow
- Update `sandbox_recover()` to work with new pattern
- Run full E2E

### Chunk 7: Documentation + Cleanup

**Files**: `R/*.R`, vignettes, `man/`

- roxygen2 docs for all new exports (`datom_store_s3`, `datom_store`)
- Update credentials vignette
- Update getting-started vignette
- `devtools::document()`, `devtools::check()`

## Acceptance Criteria

- [ ] `datom_store_s3()` validates credentials and bucket access at construction time
- [ ] `datom_store()` bundles governance + data components with role derivation
- [ ] `datom_init_repo(store = ...)` replaces `bucket`/`prefix`/`region`/`remote_url` params
- [ ] `datom_init_repo(create_repo = TRUE)` creates GitHub repo via API (no `gh` CLI)
- [ ] `datom_get_conn(store = ...)` and `datom_clone(store = ...)` accept composite store
- [ ] No filesystem/git side effects before validation passes in `datom_init_repo()`
- [ ] `project.yaml` uses `storage.governance` + `storage.data` structure
- [ ] `.datom_install_store()` bridge injects credentials into env vars (temporary)
- [ ] `print()` methods mask secrets
- [ ] Sandbox tooling uses `datom_store()` instead of `sandbox_credentials()`
- [ ] Full test suite passes, count ≥ 962
- [ ] E2E workflow succeeds via `dev/e2e-test.R`

## Status

| Chunk | Status | Notes |
|-------|--------|-------|
| 1 | ✅ done | `datom_store_s3()` + 43 tests (1005 total) |
| 2 | ✅ done | `datom_store()` composite + 61 tests (1066 total). httr2 added. |
| 3 | ✅ done | `.datom_install_store()` bridge + `.datom_create_github_repo()` + 21 tests (1087 total) |
| 4 | ✅ done | Refactored `datom_init_repo()` → store object, two-component project.yaml, +4/-7 tests (1090 total) |
| 5 | ✅ done | Refactored `datom_get_conn()` + `datom_clone()` → store objects, two-component yaml compat (1088 total) |
| 6 | ✅ done | sandbox_store() replaces sandbox_credentials(), sandbox_up(store) uses create_repo=TRUE, e2e updated (1088 total) |
| 7 | not started | |

## Dependencies

- `httr2` — for GitHub REST API (repo creation, PAT validation). Check if already in DESCRIPTION; if not, add.
- `paws.storage` — already a dependency (STS + S3 checks)
