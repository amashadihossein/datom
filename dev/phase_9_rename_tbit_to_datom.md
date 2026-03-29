# Phase 9: Rename tbit → datom

## Goal

Rename the package from `tbit` to `datom` — all function prefixes, class names, env var prefixes, S3 path segments, config directory, file names, docs, and dev infrastructure. Clean cut, no backward compatibility layer.

## Context

- No CRAN release yet → no public API contract
- No downstream consumers → daapr/dpbuild/dpdeploy don't depend on tbit yet
- No production data in S3 under `tbit/` prefix
- New S3 test bucket: `datom-test` (replaces `tbit-test`)
- Rollback tag: `pre-rename-to-datom` at commit `703a044`

## Rename Categories

| # | Category | Pattern | Example |
|---|----------|---------|---------|
| 1 | Internal function prefix | `.tbit_` → `.datom_` | `.tbit_compute_data_sha` → `.datom_compute_data_sha` |
| 2 | Exported function prefix | `tbit_` → `datom_` | `tbit_read` → `datom_read` |
| 3 | S3 class name | `tbit_conn` → `datom_conn` | `inherits(x, "tbit_conn")` → `inherits(x, "datom_conn")` |
| 4 | Env var prefix | `TBIT_` → `DATOM_` | `TBIT_{PROJECT}_ACCESS_KEY_ID` → `DATOM_{PROJECT}_ACCESS_KEY_ID` |
| 5 | S3 storage path segment | `"tbit"` in path building | `prefix/tbit/table/` → `prefix/datom/table/` |
| 6 | Local config directory | `.tbit/` → `.datom/` | `.tbit/project.yaml` → `.datom/project.yaml` |
| 7 | Metadata field | `tbit_version` → `datom_version` | In volatile list + metadata builders |
| 8 | Package identity | `Package: tbit` → `Package: datom` | DESCRIPTION, NAMESPACE, README, URLs |
| 9 | Prose references | `tbit` in comments/docs | roxygen, vignettes, dev docs |

## Acceptance Criteria

- [ ] All 964 tests pass after rename
- [ ] `devtools::document()` succeeds (NAMESPACE + man pages regenerated)
- [ ] `devtools::check()` passes with 0 errors, 0 warnings
- [ ] No remaining `tbit` references in R/, tests/, DESCRIPTION, NAMESPACE (except git history)
- [ ] Dev docs updated consistently
- [ ] Phase doc deleted per completion procedure

## Chunks

### Chunk 1: R source files (`R/*.R`) — DESIGN
**Scope**: All 12 R source files + file rename `R/tbit-package.R` → `R/datom-package.R`

**sed replacement order** (order matters — longest match first):
1. `.tbit_` → `.datom_` (internal functions, `.tbit/` dir references)
2. `tbit_` → `datom_` (exported functions, class name)
3. `TBIT_` → `DATOM_` (env var prefix)
4. Remaining `tbit` → `datom` (prose in comments, string literals like S3 path segment)

**Verification**:
- `devtools::document()` succeeds
- `grep -r "tbit" R/` returns 0 hits
- Tests will NOT pass yet (test files still say `tbit`) — that's expected

**Status**: [x] Complete — 0 `tbit` hits in R/, NAMESPACE regenerated with datom_ exports

---

### Chunk 2: Tests (`tests/testthat/`) — DESIGN
**Scope**: All 11 test files + `helper-mock.R` + `tests/testthat.R`

**Same sed patterns as Chunk 1**, applied to test files.

Key renames inside tests:
- `mock_tbit_conn` → `mock_datom_conn`
- `tbit_conn` class references → `datom_conn`
- `TBIT_` env vars in test setup/teardown → `DATOM_`
- `.tbit/` paths in test fixtures → `.datom/`

**Verification**:
- `devtools::test()` — 964 tests pass
- `grep -r "tbit" tests/` returns 0 hits

**Status**: [x] Complete — 0 `tbit` hits in tests/, fixed `Tbit`→`Datom` reserved name case

**Note**: Had to pull `Package: datom` from Chunk 3 into Chunk 2 because `utils::packageVersion("datom")` failed when DESCRIPTION still said `tbit`. Also fixed `inst/templates/README.md` (Mustache template with `{{{tbit_version}}}` → `{{{datom_version}}}`).

---

### Chunk 3: Package infrastructure — DESIGN
**Scope**:
- `DESCRIPTION` (package name, Title, URLs → `amashadihossein/datom`)
- `_pkgdown.yml`
- `inst/templates/README.md`
- File rename: `tbit.Rproj` → `datom.Rproj`
- `devtools::document()` to regenerate NAMESPACE + all man/ pages

**Verification**:
- `devtools::document()` succeeds
- `devtools::test()` — 964 tests pass
- `grep -r "tbit" DESCRIPTION NAMESPACE inst/ _pkgdown.yml` returns 0 hits

**Status**: [ ] Not started

---

### Chunk 4: Documentation & dev files — DESIGN
**Scope**:
- `README.md`, `README.Rmd`
- 3 vignettes (`clinical-data-versioning.Rmd`, `credentials.Rmd`, `team-collaboration.Rmd`)
- `dev/README.md`
- `dev/tbit_specification.md` → rename file to `dev/datom_specification.md` + content
- `dev/daapr_architecture.md`
- `dev/tbitaccess_overview.md` → rename file to `dev/datomaccess_overview.md` + content
- `.github/copilot-instructions.md`
- `dev/dev-sandbox.R` (including `tbit-test` → `datom-test`)
- `dev/e2e-test.R` (including `tbit-test` → `datom-test`)
- `data-raw/simulate_study_data.R`

**Verification**:
- `devtools::check()` — 0 errors, 0 warnings
- `grep -rl "tbit" . --include="*.R" --include="*.Rmd" --include="*.md" --include="*.yml" | grep -v .git/ | grep -v docs/` returns 0 hits

**Status**: [ ] Not started

---

## Decisions Log

| Decision | Rationale |
|----------|-----------|
| No backward compat | Pre-CRAN, no downstream consumers, no production data |
| `datom-test` bucket | Fresh start, old `tbit-test` data irrelevant |
| Skip `docs/` | Generated by pkgdown, not source of truth |
| sed-based bulk rename | Mechanical task, review diffs for correctness |

## Post-Phase Cleanup (after all chunks complete)

- [ ] Rename GitHub repo: Settings → `datom` (auto-redirects old URLs)
- [ ] Rename local directory: `mv tbit datom`
- [ ] Update git remote if needed: `git remote set-url origin https://github.com/amashadihossein/datom.git`
- [ ] Push rollback tag: `git push origin pre-rename-to-datom`
- [ ] Regenerate pkgdown site (`docs/`)

## Current State

Phase doc created. Awaiting approval to begin Chunk 1.
