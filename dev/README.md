# datom Development Hub

## Workflow model (read first): spec = phase

A unit of multi-step work is a **Kiro spec** under `.kiro/specs/{feature}/`:
`requirements.md` (goal + acceptance), `design.md` (context, invariants, correctness
properties), `tasks.md` (the chunk breakdown + status). **The spec replaces the legacy
`dev/phase_{n}_{name}.md` phase doc.**

Everything in this document still applies — just remap the terms:

| Legacy term (used below) | Now |
|---|---|
| phase doc `dev/phase_*.md` | the spec `.kiro/specs/{feature}/` |
| Chunks table / Progress Log | `tasks.md` (checkboxes) + commit history |
| Active Phases | Active Specs |
| "delete the phase doc" on completion | **specs persist — never deleted** |

A "chunk" = one task (or a small related group) in `tasks.md` = one commit. All branch,
test-before-commit, chunk-checkpoint, and review discipline below is unchanged. Works the
same in Kiro (native specs) and Copilot (read/maintain the same `.kiro/specs/` files).

## Documentation Hierarchy

This folder contains all development documentation following a hierarchical chain:

```
.github/copilot-instructions.md     ← Entry point for AI/developers
         ↓
dev/README.md                       ← This file: navigation hub
         ↓
dev/datom_specification.md           ← Design spec (authoritative, evolves slowly)
dev/datom_pathways.md               ← Canonical route map across metadata/gov/storage/access
dev/daapr_architecture.md           ← Ecosystem context
dev/datomanager_scope.md             ← datomanager companion package scope (gov lifecycle + migration)
dev/datomanager_overview.md          ← datomanager access enforcement design (roles, grants, IAM; forward-looking)
         ↓
.kiro/specs/{feature}/              ← Active work: requirements.md, design.md, tasks.md
```

## Documentation Lifecycle

### Units of Work (Specs)

A unit of work is a **Kiro spec** under `.kiro/specs/{feature}/` (see Workflow model at top):

1. **Created** when starting a feature (requirements → design → tasks)
2. **Updated continuously** as development proceeds (task status in `tasks.md`)
3. **Completed** when all tasks are checked off and acceptance criteria met
4. **Persists**: the spec stays as durable documentation; additional durable learnings → spec/architecture docs and `dev/engineering-notes.md`

### What Goes Where

| Content Type | Location | Lifecycle |
|--------------|----------|-----------|
| Coding style, conventions | `.github/copilot-instructions.md` | Permanent |
| Architecture, API design | `dev/datom_specification.md` | Permanent, evolves |
| Canonical lookup/traversal routes | `dev/datom_pathways.md` | Permanent, evolves with schema/routing changes |
| Ecosystem context | `dev/daapr_architecture.md` | Permanent |
| Current work, tasks, decisions | `.kiro/specs/{feature}/` | Persists |
| Implementation gotchas discovered | `dev/engineering-notes.md` | Persists |

## Current Development State

### Active Specs

Units of work are **Kiro specs** under `.kiro/specs/{feature}/` (see Workflow model at top).

| Spec | Started | Status | Location |
|------|---------|--------|----------|
| _none_ | — | No spec currently active. | — |

### Drafts (queued, not active)

| Draft | Doc | Captured | Notes |
|-------|-----|----------|-------|
| datomanager Phase 19: gov_migrate_data() | [draft_managed_migration.md](draft_managed_migration.md) | 2026-05-02 | Governed migration verb. Requires gov; atomic copy + `ref.json` switch + `migration_history.json` record; cross-backend s3<->local. datom Phase 22 (storage extension API) shipped 2026-06-10 -- the six `datom_storage_*` / `datom_repo_*` exports are the stable platform surface Phase 19 calls into. datomanager package scaffold is the remaining prerequisite. See draft for Phase 19 spec and acceptance criteria. |

### Completed Phases

| Phase | Completed | Tests | Summary |
|-------|-----------|-------|---------|
| Spec: gov-seam-liftout (datom side) | 2026-06-20 | 1873 | GOV_SEAM lift-out, datom side. Removed the governed **write** surface (5 exports: `datom_init_gov`, `datom_attach_gov`, `datom_decommission`, `datom_sync_dispatch`, `datom_pull_gov`; 9 `.datom_gov_*` write helpers) — it now lives in `datomanager`. datom retains all gov **reads** (`datom_projects`, `datom_pull` (data-repo-only), the six gov-read helpers, `R/ref.R` resolvers). Additive: `gov_backend` 12th conn field + `.datom_conn_for(conn,"gov")` resolves gov dispatch from it (C6); new export `datom_repo_attach_governance()` (C4-compliant data-side `governance.json` write for `datomanager::gov_attach()`); internal `.datom_sync_data_metadata()` split from `datom_sync_dispatch` (data-only half; called by `datom_validate(fix=TRUE)` + `datom_write(NULL,NULL)`). `datom_init_repo()` decoupled from gov registration (solo-only). Added `dev/e2e-solo-local.R` (solo init→write→read→`datom_repo_delete`, passing). R CMD check 0E/0W/1 benign NOTE; dev version 0.0.0.9001. **No pathway impact** (route shapes unchanged). Companion-package starter code recoverable from git history before the merge. |

### Completed Phases (legacy)

| Phase | Completed | Tests | Summary |
|-------|-----------|-------|---------|
| Phase 22: Storage Extension API | 2026-06-10 | 1897 | Six exports: `datom_storage_list`, `datom_storage_delete_prefix`, `datom_storage_copy` (all 4 backend combos), `datom_storage_verify` (structural + content modes), `datom_repo_set_data_store` (read-modify-write `project.yaml`), `datom_repo_delete` (extracted from `datom_decommission`; gov guard). New files: `R/storage.R`, `R/repo.R`. `datom_decommission()` refactored to call `datom_repo_delete()`. 197 new tests. pkgdown + NAMESPACE clean. Spec updated with Storage Extension API section. |
| Phase 21: Governance-First Connection UX | 2026-05-29 | 1700 | Closes issue #24. Two deliverables: (1) `governance.json` dual-pointer file -- written to `.datom/governance.json` (git canonical) + `{prefix}/datom/.metadata/governance.json` (storage mirror) by `datom_init_repo()` and `datom_attach_gov()`; read back by the developer four-state matrix and reader data-first probe; cleaned up by `datom_decommission()`. (2) `datom_store_s3_creds(access_key, secret_key)` credentials-only S3 component -- readers on gov-attached projects no longer need to know the data bucket/prefix/region; location is resolved from `ref.json` at conn time. New exports: `datom_store_s3_creds()`, `is_datom_store_s3_creds()`. New vignette: `design-governance-json.Rmd` (dual-pointer pattern, schema, lifecycle). Updated vignettes: `handing-off.Rmd` (engineer handoff reduced to 2 items), `credentials-in-practice.Rmd` (`datom_store_s3_creds` section). Spec updated with `governance.json` schema + `datom_store_s3_creds` entry. E2E assertion blocks added to `e2e-test-local.R` (Flows 1-6). |
| Phase 20: Source Lineage | 2026-05-12 | 1602 | Transitive source lineage field in metadata.json. `datom_sync()` auto-populates a self-entry for imported tables. `datom_write()` structural mandate: `source_lineage` required when `parents` is non-null. New exports: `datom_get_lineage(depth = "source" | "parents")` (single-read, no DAG walk) and `datom_validate_lineage()` (union parents' lineages, diff against declared; returns status/missing/extra/wrong_version). Spec updated; vignette "Tracing Data Lineage" added; dpbuild lineage contract documented in daapr_architecture.md. |
| Phase 18: Governance on-demand | 2026-05-03 | 1528 | Made governance optional and on-demand. New flow: `datom_store(governance = NULL)` for solo projects; `datom_attach_gov()` for the promotion moment (typically alongside S3 migration). `datom_init_repo()` writes `project.yaml` without `storage.governance` when no gov store supplied. Gov-only commands (`datom_projects`, `datom_pull_gov`, `datom_sync_dispatch`) emit a uniform "no governance attached -- use `datom_attach_gov()`" error. `.datom_conn_for(conn, scope)` accessor replaces `.datom_gov_conn()` for all scope-switching. `datom_decommission()` no-gov branch skips gov teardown cleanly (latent bug fixed: local no-gov conns no longer accidentally delete `cwd/projects/{name}`). Vignettes rewritten: Article 1 drops gov entirely; Article 4 introduces `datom_attach_gov()` paired with S3 promotion. README primary example is no-gov. Sandbox learns `attach_gov = FALSE` mode and `sandbox_promote_gov()` helper. Acceptance criteria 1-10 all met. |
| Phase 16: Vignette overhaul | 2026-05-11 | 1530 | Replaced the legacy three vignettes with a 10-article user-journey track (STUDY-001 over six months: first extract -> monthly cadence -> bulk sync -> S3 promotion -> reader handoff -> second engineer -> portfolio governance -> audit/reproducibility -> daapr-stack outlook -> credentials reference) plus a 6-article design-notes track (D1 datom model; D2 ref.json; D3 dispatch.json; D4 two-repo split; D5 version SHAs; D6 serverless). All article IO chunks `eval = FALSE`; jump-in readers get continuity via `inst/vignette-setup/resume_article_N.R` (idempotent, env-var-overridable). Simulator extended with LB + AE domains. `_pkgdown.yml` reorganized into Get Started / Scale Up / Govern / Reference / Design groups. Coverage review confirms all 28 exports appear in at least one article. Phase-16 continuation (May 11): fixed two real package bugs surfaced by live-running the vignettes (datom_attach_gov synthetic data snapshot had empty root -- backend field mismatch; fixed in R/conn.R with regression test); added `buckets-and-prefixes.Rmd` convention article (Pattern A: bucket-per-study, empty prefix for raw; named prefixes for derived; dedicated gov bucket); aligned all 17 vignettes to Pattern A defaults and ASCII-only source (R CMD check safe); fixed broken `credentials.html` link in `looking-ahead`; expanded `credentials-in-practice` to 3 credential options; issued #19 (init_gov CWD default) and #20 (init_gov idempotence local-only). |
| Phase 17: Portfolio helpers | 2026-05-02 | 1416 | Added two manager/audit-facing helpers: `datom_summary(conn)` (single-project one-liner; reads `.metadata/manifest.json`; S3 class with print method; developer path includes data git remote URL) and `datom_projects(x)` (portfolio listing; accepts `datom_conn` or `datom_store`; returns data frame with name/data_backend/data_root/data_prefix/registered_at; clone-first read with storage fallback; corrupt entries warn-and-skip). Internal additions: storage list dispatch (`.datom_storage_list_objects` + `.datom_s3_list_objects` mirroring existing local helper); `.datom_gov_list_projects()` pure-read helper in `R/utils-gov.R` (NOT a `GOV_SEAM` -- reads stay with datom, only gov writes are seamed). Pre-release schema bump: added `current$type` field to `ref.json` so readers can identify the data backend without already holding a store. Unblocks Phase 16 Chunks 5-6. |
| Phase 15: Separate Gov Repo (+ audit cleanup) | 2026-04-29 | 1343 | Split governance and data into two independent git repos with separate histories, remotes, and local clones. New shared governance repo (one per organization / gov bucket) holds `projects/{name}/{ref,dispatch,migration_history}.json`; data repo holds tables + manifest. New exports: `datom_init_gov()`, `datom_decommission()`, `datom_pull_gov()`. Refactored: `datom_init_repo()` (data-first, gov-register), `datom_clone()` + `datom_pull()` (two-repo), `datom_sync_dispatch()` (commits on gov). Breaking: `remote_url` -> `data_repo_url`. New `# GOV_SEAM:` contract isolates gov-write helpers in `R/utils-gov.R` for future companion-package handoff. Role-aware ref reads (developer reads from local clone, reader from storage; write-time guard always hits storage). Sandbox supports scoped teardown (`scope = "all" \| "project" \| "gov"`). **Pre-CRAN audit cleanup** folded in (5 chunks): hard-abort on post-push gov/manifest failures with gov-clone rollback (C1+C2); `datom_decommission()` repo deletion via `httr2` instead of `gh` CLI (H1); backend-blind UI in `datom_sync_dispatch()`, symmetric pull errors, dropped dead pre-Phase-15 fallback (H2-H4+L3); deduped `gov_local_path` resolution / `datom_init_gov()` config / `.datom_gov_unregister_project()` commit logic (M1+M3+M4+M5); style polish (L1+L2+L4+L5). E2E-driven fixes: NA-safe prefix guards in `.datom_local_delete_prefix` / `.datom_s3_delete_prefix`; sandbox mops up data store root after decommission (caller-owned root principle); idempotent `gh repo` deletion in sandbox teardown. |
| Phase 14: Public Release Prep | 2026-04-21 | 1177 | Pre-public cleanup: fix LICENSE/`.Rbuildignore` (`tbit` rename remnants), add `NEWS.md`, drop CRAN badge, fix R CMD check warning (non-ASCII in `R/ref.R`), add `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, issue/PR templates, GitHub Actions (R-CMD-check + pkgdown), untrack `dev/archive/` + `dev/datomaccess_overview.md` via `.gitignore`, scrub Phase/Chunk refs from `R/` comments, centralize `dev/dev-sandbox.R` credentials to `Sys.getenv()`, fix `_pkgdown.yml` missing `datom_store_local` entries. |
| Phase 13: Reader Ref Resolution | 2026-04-21 | 1177 | Conn-time ref resolution wired into both `_get_conn_reader` and `_get_conn_developer` (S3 + local). New helpers: `.datom_resolve_data_location()`, `.datom_check_data_reachable()`, `.datom_check_ref_current()`. Developer migration mismatch → auto-pull git + re-read `project.yaml`. Reader mismatch → warn + proceed with ref-resolved location. Reachability check (HeadBucket / `dir_exists`) gates conn creation. Conn-time ref failure is warn-only; write-time ref failure is a hard abort (prevents orphaned data). `datom_status` and sandbox UI now backend-aware (`Tables on S3`/`Tables on local`, `Data:`/`Governance:` labels instead of hardcoded `s3://`). `.sandbox_wipe_local_component()` added so `sandbox_down()` handles local backends too. Named-lookup pattern adopted for backend UI labels (anticipates GCS/other backends). |
| Phase 12: Filesystem Backend | 2026-04-19 | 1153 | `datom_store_local()` constructor, `.datom_local_*()` backend functions (`utils-local.R`), dispatch wiring (`switch` arms in `utils-storage.R`), `conn$bucket`→`conn$root` rename, `new_datom_conn(backend=)`, `datom_init_repo()`/`datom_get_conn()` local paths, `project.yaml` type:local, `.datom_store_backend/root/region()` accessors, `.datom_build_init_conn()` helper, `ref.json` backend-neutral, README template backend-neutral, E2E test script (`dev/e2e-test-local.R`), `sandbox_store_local()`, `devtools::check()` clean. |
| Phase 11: Routing Separation | 2026-04-18 | 1039 | `routing.json` → `dispatch.json`, credential wiring (no env var bridge), gov/data store split, storage abstraction layer (`.datom_storage_*()` dispatch), `ref.json` replaces `.redirect.json`, conn fields `client`/`gov_client`/`backend`, `.datom_build_storage_key()`, spec + copilot-instructions updated, README updated, sandbox fixed, `devtools::check()` clean. E2E passes. |
| Phase 10: Store Abstraction | 2026-04-18 | 1083 | `datom_store_s3()` + `datom_store()` constructors, `.datom_create_github_repo()` via httr2, `datom_init_repo(store=, create_repo=TRUE, repo_name=)`, `datom_get_conn(store=)`, `datom_clone(path, store)`, two-component `project.yaml` (governance+data), `.datom_install_store()` env-var bridge, HeadBucket validation (STS removed — not in paws.storage), print methods with masked secrets, vignettes rewritten. `devtools::check()` clean. | Full package rename: all function prefixes (`datom_`/`.datom_`), S3 class (`datom_conn`), env vars (`DATOM_`), S3 path segment, `.datom/` config dir, metadata field (`datom_version`), package identity, docs. `devtools::check()` clean. |
| Phase 7: Multi-Developer Collaboration | 2026-03-28 | 964 | S3 namespace safety check in `datom_init_repo()`, pull-before-push discipline (`.datom_git_pull`, `.datom_check_git_current`), `datom_pull()` export (git-only, no S3 refresh — git is source of truth), `datom_clone()` export, team collaboration vignette, credentials vignette, `project_name` in manifest, `.force` bypass, `datom_validate()` project_name cross-check |
| Phase 8: Metadata Enrichment & Table Types | 2026-03-28 | 905 | `table_type`, `size_bytes`, `parents`, `original_file_sha` in version_history, `datom_get_parents()`, `endpoint` param, `.access/` namespace safety. Post-phase bug fixes: manifest update in `datom_write`, `datom_init_repo` S3 push, idempotent SHA computation (JSON canonical form, volatile field exclusion, version_history dedup guard) |
| Phase 6: Sync & Validation | 2026-02-15 | 130 | datom_sync_manifest, datom_sync (rio import), datom_sync_routing, datom_validate (git-S3 consistency), datom_status |
| Phase 5: Read/Write Workflows | 2026-02-15 | 143 | datom_read (version resolution), datom_write (change detection, parquet+metadata), .datom_sync_metadata, datom_list, datom_history |
| Phase 4.5: S3 Refactor | 2026-02-15 | 99 | Refactored S3 utils from (s3_client, bucket, s3_key) to (conn, s3_key), added mock_datom_conn helper |
| Phase 4: Connection & Init | 2026-02-15 | 115 | datom_conn S3 class, datom_get_conn (developer/reader), datom_init_repo, credential derivation |
| Phase 3: Git Operations | 2026-02-14 | 47 | git2r wrappers: check, author, branch, commit, push (fetch+merge+push) |
| Phase 2: S3 Operations | 2026-02-10 | 99 | S3 client, upload/download/exists, JSON read/write, redirect resolution |
| Phase 1: Core Utilities | 2026-02-09 | 131 | SHA, paths, name validation, repo validation |

### Developer Tooling

**dev/dev-sandbox.R**: Automated setup/teardown for testing workflows

- `sandbox_up()`: Creates GitHub repo + runs `datom_init_repo()` + populates with example data
- `sandbox_down()`: Wipes S3 namespace + deletes GitHub repo + removes local directory
- `sandbox_reset()`: Full teardown + setup in one call
- Replaces manual 5-step workflow (create repo, walk vignette, delete S3, delete repo, delete local)
- Requires `gh` CLI, AWS credentials, `GITHUB_PAT`

### Backlog (Deferred Features)

Items discovered during development but intentionally deferred. Review periodically.

| Item | Discovered In | Reason Deferred | Priority |
|------|---------------|-----------------|----------|
| renv::init() in datom_init_repo | Phase 4 | Adds complexity, tangential to core data versioning | Low |
| Manifest manipulation APIs (descriptions, staging, QA tagging) | Phase 7 | Two-step scan+sync is sufficient; richer manifest APIs belong in a sister package or future datom release | Medium |
| datomanager package creation | Phase 15 | Companion governance package (settled name: `datomanager`). Scope doc: `dev/datomanager_scope.md`. Owns GOV_SEAM write surface (renamed `gov_*` on lift-out) + `gov_migrate_data()` (Phase 19). datom Phase 22 (storage extension API) complete 2026-06-10; datomanager scaffold is the remaining gate. Effort: ~2 days for lift-out, then Phase 19. **Starter code for the gov-write reimplementation:** the tried-and-tested helper bodies + their tests are preserved in datom git history at the commit just before the `gov-seam-liftout` merge -- retrieve with `git show <sha>:R/utils-gov.R`, `git show <sha>:R/decommission.R`, `git show <sha>:tests/testthat/test-utils-gov.R` (find `<sha>` via `git log --oneline -- R/utils-gov.R`). Reimplement behavior-equivalent with git2r + own storage IO (contract C3/D2 forbid calling datom internals); contract C5 (commit strings) + C8 (storage layout) pin the observable behavior. | High (next major) |
| Backend rename: `local` -> `filesystem` | Phase 18 | "Local" implies laptop disk, but the backend supports network mounts and cloud-mounted FS too. Atomic schema bump touching store constructor, predicate, dispatch arms, `project.yaml`, `ref.json`. Defer until there's a second compelling reason to touch the schema. | Low |
| `gov_migrate_data()` (managed migration) | Phase 15 | Today migration is manual (`aws s3 sync` + `datom_sync_dispatch()`). Atomic data-copy + ref.json update + `.datom_gov_record_migration()` deferred. Lives in datomanager (Phase 19); calls datom `datom_storage_*` / `datom_repo_*` helpers (all six now exported in Phase 22). | Medium |
| Restore `ubuntu-latest (devel)` in `.github/workflows/R-CMD-check.yaml` | Phase 17 | Disabled 2026-05-02 because Posit PPM has no R-devel Linux binaries; every PR paid a 15-25 min source-compile tax for arrow / paws.storage / friends. Restore as part of the pre-CRAN checklist (CRAN expects devel to pass). | Pre-CRAN |
| CODEOWNERS automation on `projects/{name}/` | Phase 15 | Self-serve project ownership; belongs in companion package, not datom. | Low (companion) |
| Gov repo concurrency primitives | Phase 15 | Pull-before-push handles current contention. Advisory locks deferred until contention is observed. | Low |

**Backlog lifecycle**:
1. Discovered during phase work → add here with context
2. When planning next phase → review for inclusion
3. If promoting to spec → move to `datom_specification.md` "Deferred to v2" section
4. If abandoned → delete with brief note why

## Quick Context for New Sessions

When starting a new development session:

1. Check the **Active Specs** table above
2. Open the active spec under `.kiro/specs/{feature}/` (requirements, design, tasks)
3. In `tasks.md`, find the next unchecked task
4. Continue from where we left off

---

## Collaborative Development Workflow

Within each spec, we work in **chunks** — small, testable units of work (each chunk = one task, or a small related group, in `tasks.md`).

### Chunk Lifecycle

```
1. DESIGN    → Propose scope, functions, acceptance criteria
                 ↓
              User approves or adjusts
                 ↓
2. DEVELOP   → Implement code + tests
                 ↓
              User reviews, runs tests, QA
                 ↓
3. FEEDBACK  → User confirms or requests changes
                 ↓
              Iterate until approved
                 ↓
4. COMPLETE  → Mark chunk done, pick next chunk
```

### Chunk Size Guidelines

- **1-3 functions** per chunk (testable in one session)
- **Clear boundary** — chunk should work independently
- **User can QA** — real tests they can run

### Communication Pattern

At each stage, I will:

| Stage | I Provide | You Provide |
|-------|-----------|-------------|
| DESIGN | Proposed functions, signatures, tests | Approval or adjustments |
| DEVELOP | Implementation + test file + debug snippet | Run tests, step through, try it out |
| FEEDBACK | Respond to issues | Confirm done or request changes |

### Chunk Delivery Checklist

After each chunk is implemented, I deliver **five things in order**:

1. **Write tests** — full test coverage for the chunk's functions
2. **Run tests** — execute and fix until all pass (green suite)
3. **Minimalist walkthrough snippet** — a clean, self-contained R snippet for you to paste into the console and step through interactively (use `debugonce()` to drop into any function)
4. **Update the spec as part of the same commit** — every chunk, no exceptions:
   - Check off the completed task(s) in `tasks.md`
   - If the chunk changes metadata schema, storage layout, governance refs, lineage, access control, role resolution, migration, or decommissioning, update `dev/datom_pathways.md` or explicitly record "no pathway impact"
   Also update the `dev/README.md` Active Specs table status line. `tasks.md` + commit history are the audit trail; if they're not updated, the chunk isn't done.
5. **Commit after walkthrough** — once you've kicked the tires and confirmed it works, I commit (code + `tasks.md` status together) with a concise message, then you push

> **`tasks.md` is the at-a-glance dashboard.** Task checkboxes show status at a glance; a fresh session reads `tasks.md` first to find the next unchecked task. Commit history is the detailed audit trail.

### QA Methods

- **Run tests**: `devtools::test(filter = "chunk_name")`
- **Debug walkthrough**: Step through with breakpoints or `browser()`
- **Try interactively**: Playground snippets provided with each chunk

### Code Style for Debuggability

To support step-through debugging:

- **Meaningful intermediates**: Avoid long pipe chains; use named variables
- **Small functions**: Each does one thing, easy to step into
- **Playground snippets**: Each chunk includes copy-paste code to try interactively

### Branch Workflow

Every spec gets its own feature branch:

1. **Create branch**: `git checkout -b spec/{feature}` (from `main`)
2. **Develop on branch**: All commits for the spec go here
3. **PR when complete**: Open a pull request to `main`
4. **Merge + delete**: Squash-merge or merge, then delete the branch

The spec is created/edited *on the branch* (not on `main`). Specs persist after merge — the
Spec Completion Procedure does **not** delete them (this replaces the old phase-doc deletion).

### Git Commit Cadence

Within chunks (on the spec branch):

- **Commit frequently**: After each logical unit (function + test, fix, etc.)
- **Push at milestones**: Task complete, spec complete, or good stopping point
- **Message format**: `{feature}: brief description` (optionally reference the task)

Example:
```bash
# Start the spec branch
git checkout -b spec/store-relocate

# Within the first task
git add R/remotes.R tests/testthat/test-remotes.R
git commit -m "store-relocate: datom_remotes_s3 constructor + validation"

# More work...
git commit -m "store-relocate: .datom_install_remotes + env var bridge"

# Spec complete — PR to main
git push -u origin spec/store-relocate
# Open PR, merge, delete branch
```

## Maintenance Rules

1. **Keep `tasks.md` current** as you work (status, decisions, blockers)
2. **Split large specs** when scope exceeds a few sessions
3. **Never let the spec go stale** — if context changes, update requirements/design immediately
4. **Specs persist** — do not delete them on completion (they are durable documentation)
5. **Update this README** when spec status changes
6. **Capture deferrals immediately** — when you skip something, document it in the Backlog
7. **Review backlog** before starting each spec
8. **Keep pathway map current** — schema/routing changes must update `dev/datom_pathways.md` or record "no pathway impact"

## Spec Completion Procedure (formerly Phase Completion)

When all of a spec's tasks are done, perform these steps **in order before starting the next spec**:

1. **Harvest persistent content** from the phase doc:
   - Design decisions that affect the overall API → migrate to `dev/datom_specification.md`
   - Canonical lookup/traversal route changes → migrate to `dev/datom_pathways.md`
   - Coding patterns/conventions discovered → migrate to `.github/copilot-instructions.md`
   - Ecosystem learnings → migrate to `dev/daapr_architecture.md`
   - Deferred items → move to the **Backlog** table in this README

2. **Update this README**:
   - Move phase from Active → Completed table (with date, test count, summary)
   - Update backlog if needed

3. **Specs persist — do NOT delete them.** (Replaces the old "delete the phase doc" step.)
   The spec under `.kiro/specs/{feature}/` is durable documentation: mark its tasks complete
   and leave it in place. Harvest only *additional* durable learnings into the permanent docs
   per step 1.

4. **PR + merge + delete branch**:
   - Open a PR from `phase/{n}-{name}` to `main`
   - Merge (squash or regular)
   - Delete the feature branch (remote and local)

**Rule**: Kiro specs persist as durable documentation — do not delete them. (Legacy
`dev/phase_*.md` files, if any are ever created, still must not survive past completion —
migrate their content and remove them.)
