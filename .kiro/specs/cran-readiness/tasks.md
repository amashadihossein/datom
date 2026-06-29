# Tasks

## Workstream A — Mechanical blockers (Req 1–3)

- [x] 1. Move `glue` and `yaml` from Suggests to Imports in DESCRIPTION; add `utils` to Imports
  - Edit `DESCRIPTION`: add `glue`, `utils`, `yaml` to `Imports` (alphabetical); remove `glue` and `yaml` from `Suggests`.
  - Verify `git2r` and `rio` remain in Suggests.
  - **Files:** `DESCRIPTION`

- [x] 2. Add `@importFrom rlang %||%` directive and regenerate NAMESPACE
  - In `R/datom-package.R`, add `#' @importFrom rlang %||%` inside the `## usethis namespace:` block.
  - Run `devtools::document()` to regenerate `NAMESPACE`.
  - Verify NAMESPACE now contains `importFrom(rlang,"%||%")`.
  - **Files:** `R/datom-package.R`, `NAMESPACE`

## Workstream B — Metadata & documentation polish (Req 4, 6–9)

- [x] 3. Bump version to 0.1.0 and quote software names in DESCRIPTION
  - Set `Version: 0.1.0` in DESCRIPTION.
  - Single-quote `'git'`, `'GitHub'`, `'S3'` in the Description field per CRAN policy.
  - **Files:** `DESCRIPTION`

- [x] 4. Fix license holder consistency
  - Update `LICENSE.md` line 3: `Copyright (c) 2025 datom authors` → `Copyright (c) 2025 Afshin Mashadi-Hossein`.
  - **Files:** `LICENSE.md`

- [x] 5. Rewrite NEWS.md as user-facing 0.1.0 release notes
  - Replace all content with a `# datom 0.1.0` entry describing the released feature set.
  - Remove all Phase references and references to functions no longer in the package (`datom_init_gov`, `datom_pull_gov`, `datom_decommission`).
  - Group features: Core read/write/version, Sync, Query & lineage, Storage management, Governance attachment, Example data helpers.
  - **Files:** `NEWS.md`

- [x] 6. Add cran-comments.md and update .Rbuildignore
  - Create `cran-comments.md` with placeholder structure (test environments, check results, downstream deps).
  - Add `^cran-comments\.md$` to `.Rbuildignore`.
  - **Files:** `cran-comments.md` (new), `.Rbuildignore`

## Workstream C — Examples (Req 5)

- [x] 7. Add/convert examples for store constructors and predicates
  - `datom_store_local()`: runnable example with tempdir path.
  - `is_datom_store_local()`: runnable predicate example.
  - `datom_store()`: runnable composite example with `governance = NULL`, local data store.
  - `is_datom_store()`: runnable predicate example.
  - `datom_store_s3()`: runnable constructor with fake placeholder credentials (no validation at construction).
  - `is_datom_store_s3()`: runnable predicate example.
  - `datom_store_s3_creds()`: runnable constructor with fake credentials.
  - `is_datom_store_s3_creds()`: runnable predicate example.
  - **Files:** `R/store.R`

- [x] 8. Add/convert examples for init, write, read, list, history (local-backend, `\donttest{}`)
  - `datom_init_repo()`: `\donttest{}` example using `datom_store_local()` in tempdir (requires git2r + git identity).
  - `datom_write()`: `\donttest{}` example writing `datom_example_data("dm")` to local repo.
  - `datom_read()`: `\donttest{}` example reading it back.
  - `datom_list()`: `\donttest{}` example listing tables.
  - `datom_history()`: `\donttest{}` example showing version history.
  - **Files:** `R/conn.R`, `R/read_write.R`, `R/query.R`

- [x] 9. Add/convert examples for sync, status, validate, lineage (local-backend, `\donttest{}`)
  - `datom_sync_manifest()`: `\donttest{}` example building manifest from extdata CSVs.
  - `datom_sync()`: `\donttest{}` example syncing the manifest.
  - `datom_status()`: `\donttest{}` example showing status.
  - `datom_validate()` / `is_valid_datom_repo()`: `\donttest{}` example validating.
  - `datom_summary()`: `\donttest{}` example.
  - `datom_get_parents()` / `datom_get_lineage()` / `datom_validate_lineage()`: `\donttest{}` examples.
  - **Files:** `R/sync.R`, `R/query.R`, `R/validate.R`, `R/summary.R`, `R/lineage.R`

- [x] 10. Add/convert examples for network-dependent functions (`\donttest{}`)
  - `datom_clone()`: convert existing `\dontrun{}` → `\donttest{}`.
  - `datom_pull()`: `\donttest{}` example.
  - `datom_get_conn()`: `\donttest{}` example.
  - `datom_projects()`: `\donttest{}` example.
  - `datom_repo_set_data_store()`: convert `\dontrun{}` → `\donttest{}`.
  - `datom_repo_delete()`: convert `\dontrun{}` → `\donttest{}`.
  - `datom_repo_attach_governance()`: convert `\dontrun{}` → `\donttest{}`.
  - `datom_storage_list()`: convert `\dontrun{}` → `\donttest{}`.
  - `datom_storage_delete_prefix()`: convert `\dontrun{}` → `\donttest{}`.
  - `datom_storage_copy()`: convert `\dontrun{}` → `\donttest{}`.
  - `datom_storage_verify()`: convert `\dontrun{}` → `\donttest{}`.
  - **Files:** `R/conn.R`, `R/repo.R`, `R/storage.R`

- [x] 11. Remove `\dontrun{}` from internal function examples (utils-path.R)
  - `.datom_storage_key()` and `.datom_parse_s3_uri()` are internal (`@keywords internal`) but still have `\dontrun{}` examples. Convert to `\donttest{}`.
  - **Files:** `R/utils-path.R`

## Validation gate

- [ ] 12. Run `devtools::check()` and confirm 0 errors, 0 warnings, acceptable notes
  - Run `R CMD check --as-cran` (or `devtools::check()`) locally.
  - Verify no errors or warnings.
  - Fill in actual results in `cran-comments.md`.
  - **Performed by:** Maintainer (R not available in this environment).

## Post-check correction (examples tagging)

First `devtools::check()` run surfaced: `\donttest{}` examples **are run** by
`--run-donttest`, and connection-based functions cannot run (no offline mode —
`datom_init_repo()` pushes to a GitHub remote). All connection/network/credential examples
reverted from `\donttest{}` to `\dontrun{}`; `is_valid_datom_repo()` rewritten as a genuinely
runnable filesystem example. This is a deliberate deviation from Req 5.1: `\dontrun{}` is the
CRAN-correct tag for credential/network-gated examples. ~12 exported functions now have
runnable examples (was zero). See design.md "CORRECTION" note.
