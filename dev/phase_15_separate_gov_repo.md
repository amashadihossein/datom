# Phase 15: Separate Governance Repo

## Status

- **Branch**: `phase/15-separate-gov-repo` (to be created)
- **Started**: TBD
- **Current chunk**: 0 (not started)
- **Test count baseline**: 1177 (end of Phase 14)
- **Test count target**: ≥ 1177 (with new tests for gov-repo split, decommission, two-backend support)

## Goal

Split the governance and data layers into **two independent git repos** — separate histories, separate remotes, separate local clones. One shared governance repo serves many data repos in an org. datom continues to own both for now; a future companion package (working name: `datomaccess` / `datomanager`) will take over governance write operations. Phase 15 establishes the seam so the future handoff is a port surface, not a refactor.

## Context

- Phases 10-13 built the two-**store** architecture: governance and data point to different S3 buckets (or local dirs); `ref.json` lives at the governance store; conn-time ref resolution is wired in.
- **Storage layer is already split.** `ref.json`, `dispatch.json` live at the governance store; `manifest.json` + per-table data/metadata at the data store.
- **Code (git) layer is not.** Both governance and data files commit to the same git repo today. A routing change and a data version bump are indistinguishable at the git layer.
- **datom versions are tied to git commits.** The spec promises routing changes don't bump datom versions; today's single-repo layout violates that promise in spirit.
- **Companion package on the horizon.** A future package (`datomaccess`/`datomanager`/TBD) will own governance write operations. datom will become a client — reading gov state, writing only via seam helpers that the companion can later replace. Phase 15's job: tighten that seam.
- **Cultural principle.** Governance stays self-serve. No platform-team gatekeeper. Each project owner manages their own project folder in gov. datom exposes every gov operation as an R function.

## Design

### Conceptual split

```
Today                              After Phase 15
─────                              ──────────────

One git repo                       Two git repos
  .datom/                            Gov repo (shared, one per org)
    dispatch.json                      projects/
    ref.json                             {project_name}/
    manifest.json                          dispatch.json
    migration_history.json                 ref.json
  {table}/...                              migration_history.json
                                       README.md
                                     Data repo (per project)
                                       .datom/project.yaml
                                       manifest.json
                                       {table}/...

Same remote, same history          Two remotes, two histories
```

### Repo responsibilities

| File | Lives in | Why |
|---|---|---|
| `project.yaml` | data repo (`.datom/`) | Per-project config; declares both store endpoints + gov repo URL. |
| `dispatch.json` | gov repo (`projects/{name}/`) | Routing is a gov-domain operation; should not touch data repo history. |
| `ref.json` | gov repo (`projects/{name}/`) | Current data location pointer; gov-controlled. |
| `migration_history.json` | gov repo (`projects/{name}/`) | Audit trail for migrations; gov-controlled. New file in this phase. |
| `manifest.json` | data repo (root) | Per-version table inventory; data-versioning state. |
| `{table}/data.parquet`, `{table}/metadata.json` | data repo (root) | Per-table state; data-versioning state. |

Note: `dispatch.json` / `ref.json` / `migration_history.json` move to **`projects/{name}/`** subpaths in the gov repo (and at the gov *storage* root). This is what makes one shared gov repo work for many projects.

### GitHub remote always required

Phase 15 standardizes on **GitHub remote required for both repos, both backends.** The local backend differs only in where parquet/data files live (disk vs S3). Auth model:

- `GITHUB_PAT` for git operations (gov + data) — always.
- AWS credentials for data store — only when data backend is S3.
- AWS credentials for gov store — always (gov files live at the gov S3 namespace too, mirrored from the gov clone).

### Local layout

```
~/projects/
  clinical-data/        (data repo, sibling of gov)
  clinical-data-gov/    (gov clone, default sibling location)
```

Default: gov clone is a sibling directory named `{data_repo_basename}-gov`. Override via `datom_store(gov_local_path = "...")`.

One gov clone can serve many data repos — `datom_clone()` and `datom_init_repo()` reuse an existing gov clone if it matches `gov_repo_url`.

### `project.yaml` schema (revised)

```yaml
project_name: clinical-data

storage:
  governance:
    type: s3
    bucket: my-org-gov
    prefix: clinical-data/      # project-scoped key prefix at gov storage
    region: us-east-1
  data:
    type: s3                     # or "local"
    bucket: my-org-data          # or path: /path/to/local
    prefix: clinical-data/
    region: us-east-1

repos:
  data:
    remote_url: https://github.com/my-org/clinical-data.git
  governance:
    remote_url: https://github.com/my-org/clinical-data-gov.git
    local_path: null              # null = sibling default; string = override
```

### `datom_store()` API (revised)

```r
datom_store(
  governance,                    # datom_store_s3 | datom_store_local (gov is always backed by storage too)
  data,                          # datom_store_s3 | datom_store_local
  data_repo_url,                 # renamed from remote_url
  gov_repo_url,                  # NEW
  gov_local_path = NULL          # NEW (sibling default)
)
```

Breaking rename: `remote_url` → `data_repo_url`. Pre-release allows it.

### Seam: `# GOV_SEAM:` helpers

All gov-write operations land in a small set of internal helpers, each marked `# GOV_SEAM:`. These define the port surface the companion package will eventually take over.

| Helper | Purpose |
|---|---|
| `.datom_gov_commit(gov_conn, msg, paths)` | Stage + commit on the gov clone. |
| `.datom_gov_push(gov_conn)` | Push gov clone to remote. |
| `.datom_gov_pull(gov_conn)` | Fetch + fast-forward gov clone. |
| `.datom_gov_write_dispatch(gov_conn, dispatch)` | Write `projects/{name}/dispatch.json` to gov clone + storage. |
| `.datom_gov_write_ref(gov_conn, ref)` | Write `projects/{name}/ref.json` to gov clone + storage. |
| `.datom_gov_register_project(gov_conn, project_name, ...)` | Create `projects/{name}/` folder + initial files; commit + push. |
| `.datom_gov_unregister_project(gov_conn, project_name)` | Remove `projects/{name}/`; commit + push. |
| `.datom_gov_record_migration(gov_conn, event)` | Append to `migration_history.json`; commit + push. |
| `.datom_gov_destroy(gov_store, force = FALSE)` | Tear down whole gov repo + storage. Refuses if registered projects exist unless `force=TRUE`. **`GOV_SEAM:` — currently called only by the dev sandbox; the companion package will eventually own the full gov lifecycle (init → register → destroy) and expose a user-facing `gov_decommission()`.** |

Gov-**read** operations (`.datom_resolve_ref()`, dispatch reads) are **not** marked seam — datom always needs to read gov regardless of who writes it.

Commit message conventions (gov repo):

- `Register project {name}` — `register_project`
- `Unregister project {name}` — `unregister_project`
- `Update dispatch for {name}` — `write_dispatch`
- `Update ref for {name}` — `write_ref`
- `Record migration for {name}: {summary}` — `record_migration`

### Decommission ergonomics

| Operation | Scope | Where |
|---|---|---|
| **A. Decommission project** | one project | `datom_decommission(conn, confirm = project_name)` — datom public API |
| **B. Decommission gov** | whole gov | Future companion package; phase 15 exposes only `.datom_gov_destroy()` for sandbox. |
| **C. Sandbox teardown** | dev playground | `sandbox_down(scope = c("all", "project", "gov"))` in `dev/dev-sandbox.R` |

`datom_decommission(conn, confirm = NULL)`:

- Refuses without `confirm = "{project_name}"` literal match (no interactive prompts — must be scriptable).
- Deletes data S3 prefix (or local dir) + data GitHub repo + local data clone.
- Calls `.datom_gov_unregister_project()` on the shared gov clone (commits + pushes).
- Does **not** touch the gov repo itself or other projects.

### Chunk-by-chunk ordering invariant

Every commit in phase 15 belongs to **exactly one repo**. Audit rule: every git operation in `R/` must be traceable to either a data-repo commit or a gov-repo commit, never both.

### Init ordering: data-first ("register only what's real")

`datom_init_repo()` writes data first, then registers in gov. Rationale: gov registration is the *advertising* step — once a project appears in gov, readers can discover it. If gov registration preceded data creation and the data step failed, gov would advertise a project that resolves to nothing, and any reader hitting that entry would see a broken pointer (a **public** failure visible to the whole org). With data-first ordering, a partial failure leaves a data repo that no one can discover yet (a **private** failure the initiating developer cleans up locally). Asymmetric blast radius justifies asymmetric ordering. The companion package should preserve this invariant when it takes over gov writes.

## Pre-flight Housekeeping (on `main`, before branching)

These are small fixes worth landing before the phase 15 branch opens, to avoid carrying drift into the phase:

1. **`datom_repository_check` NAMESPACE/Rd drift.** `man/datom_repository_check.Rd` exists but no `export()` in `NAMESPACE`. Decide: export it or mark `@keywords internal` and rebuild Rd. Verify with `pkgdown::build_site()` (no missing-topic errors).
2. **NEWS.md unreleased header.** Add `# datom (development version)` header to `NEWS.md` if missing, so phase 15 can accumulate user-visible bullets cleanly.

These are committed directly to `main` (one commit each), then phase 15 branches from updated `main`.

## Chunks

### Chunk 1 — Config schema + store API

- Update `datom_store()` signature: rename `remote_url` → `data_repo_url`; add `gov_repo_url`, `gov_local_path`.
- Update `project.yaml` schema (`repos.data.remote_url`, `repos.governance.remote_url`, `repos.governance.local_path`).
- Helper: `.datom_resolve_gov_local_path(data_local_path, override)` — returns sibling default or override.
- Update `print.datom_store` and validation to surface both repo URLs.
- Update template `inst/templates/project.yaml` if any.
- Tests: store construction with both URLs, gov_local_path resolution, validation errors on missing URLs.

**No git operations yet.** Pure config plumbing.

### Chunk 2 — `# GOV_SEAM:` helpers (read-side gov clone abstraction)

- New file: `R/utils-gov.R`.
- Helpers: `.datom_gov_clone_exists(gov_local_path)`, `.datom_gov_clone_open(gov_local_path)`, `.datom_gov_clone_init(gov_repo_url, gov_local_path)` — clone if missing, open if present, validate remote matches.
- Add `gov_local_path` to `datom_conn` (extend `new_datom_conn()`).
- Path helpers: `.datom_gov_project_path(gov_local_path, project_name)` returns `{gov_local_path}/projects/{name}/`.
- Tests: clone-init idempotence, mismatch detection (different remote URL), missing remote.

**Backend-neutral.** Gov repo is git + GitHub regardless of data backend.

### Chunk 3 — `# GOV_SEAM:` write helpers

- `.datom_gov_commit()`, `.datom_gov_push()`, `.datom_gov_pull()`.
- `.datom_gov_write_dispatch()`, `.datom_gov_write_ref()` — write to gov clone (commit + push) AND to gov storage (S3/local).
- `.datom_gov_register_project()`, `.datom_gov_unregister_project()`.
- `.datom_gov_record_migration()` — appends to `migration_history.json` (creates with `[]` if missing).
- All marked `# GOV_SEAM:` with one-line rationale comment.
- Tests: each helper exercised in isolation against a temp gov clone.

### Chunk 4 — `datom_init_gov()` (new exported function)

- Signature: `datom_init_gov(gov_store, gov_repo_url, gov_local_path = NULL, private = TRUE)`.
- Steps: validate inputs → check namespace free at gov storage → create GitHub repo → clone locally → seed gov repo skeleton (`README.md`, `projects/.gitkeep`) → initial commit + push.
- Idempotent: if gov repo already exists with matching URL, returns silently.
- Tests: happy path (S3 + local data backend), idempotence, namespace collision, GitHub failure rollback.

### Chunk 5 — Refactor `datom_init_repo()` to gov-first ordering

- Pre-flight validation (all of it, no side effects).
- Step 1: ensure gov clone (call `.datom_gov_clone_init()` — clones existing or expects `datom_init_gov()` was run).
- Step 2: namespace-free check at **both** levels: gov folder (`projects/{name}/` does not exist) AND data S3 prefix / local dir.
- Step 3: create data GitHub repo + local clone.
- Step 4: write `project.yaml` to data clone.
- Step 5: write `manifest.json` to data clone.
- Step 6: data commit + push (data repo).
- Step 7: `.datom_gov_register_project()` — writes dispatch.json + ref.json + migration_history.json to gov clone, commits, pushes.
- Step 8: write same files to gov storage (parallel mirror so readers without git access can resolve).
- Two distinct commits in two histories. No commit touches both repos.
- Tests: full init for S3 + local backends, partial-failure rollback, gov pre-existing project collision.

### Chunk 6 — `datom_clone()` + `datom_pull()` two-repo semantics

- `datom_clone(path, store)`: clones data repo at `path`, gov repo at `gov_local_path` (sibling default unless override). Reuses existing gov clone if matching remote URL; errors on mismatch.
- Dirty gov clone handling: refuse if gov clone has uncommitted changes (avoids surprises).
- `datom_pull(conn)`: pulls data repo AND gov repo (default). Clear cli messaging per repo.
- New `datom_pull_gov(conn)`: gov-only pull (rare, mostly for diagnostics).
- Tests: fresh clone, reuse existing gov clone, mismatch, dirty gov, pull both.

### Chunk 7 — Refactor `datom_sync_dispatch()` to commit on gov

- Today: only uploads to S3 (no git).
- New: writes dispatch.json via `.datom_gov_write_dispatch()` (gov commit + push + storage upload).
- Update commit message: `Update dispatch for {project_name}`.
- Same for `datom_sync_manifest` if/where ref-related; verify scope.
- Tests: sync produces gov commit; data repo unaffected; both backends.

### Chunk 8 — `datom_decommission()` + sandbox teardown

- New: `datom_decommission(conn, confirm = NULL)`. Refuses without `confirm = project_name`.
- Order: delete data parquet/metadata at storage → delete data GitHub repo → remove local data clone → `.datom_gov_unregister_project()` (gov commit + push) → delete gov storage `projects/{name}/` folder.
- `sandbox_down(scope = c("all", "project", "gov"))`:
  - `"project"`: project decommission only (leaves gov intact).
  - `"gov"`: `.datom_gov_destroy()` only (refuses if projects registered without `force`).
  - `"all"` (default for sandbox): project decommission, then gov destroy.
- Tests: decommission leaves gov intact + other projects intact; sandbox scopes work; refuses without confirm.

### Chunk 9 — Data-side write purity audit + migration detection

- Audit every function in `R/` that does git operations on the data clone. Verify none touch gov files.
- Update `.datom_resolve_data_location()` with **role-aware** ref read paths:
  - **Developer connection** (has `gov_local_path`): read `projects/{name}/ref.json` from the local gov clone. Faster, works offline, reflects last `datom_pull_gov()`.
  - **Reader connection** (no gov clone): read via `gov_client` from gov storage. **This is the existing post-Phase-13 behavior and must continue to work unchanged.**
  - Branch on presence of `conn$gov_local_path` (or equivalent indicator), not on backend or role flag directly.
- Verify `.datom_check_ref_current()` continues to read via `gov_client` for the write-time hard-abort guard. (Write-time guard intentionally hits storage, not the local clone, to catch stale clones.)
- Tests: write/read flow does not produce gov commits; developer migration-mismatch detection works against gov clone; reader path against gov storage unchanged from Phase 13.

### Chunk 10 — E2E + sandbox + spec/docs

- Update `dev/dev-sandbox.R` for two-repo + scoped teardown.
- E2E for both backends: full `datom_init_gov()` → `datom_init_repo()` → `datom_write()` → `datom_sync_dispatch()` → `datom_decommission()` flow.
- Update `dev/datom_specification.md`: gov-repo model, file layout, commit conventions, seam contract, decommission semantics.
- Update `_pkgdown.yml` for new exports (`datom_init_gov`, `datom_decommission`, `datom_pull_gov`).
- Update `NEWS.md` under `# datom (development version)`:
  - Breaking: `remote_url` → `data_repo_url`.
  - New: `datom_init_gov()`, `datom_decommission()`, `datom_pull_gov()`.
  - Changed: `datom_clone()` clones gov repo too; `datom_pull()` pulls both repos; `datom_sync_dispatch()` now produces a gov commit.
- Update `.github/copilot-instructions.md` Gotchas with phase 15 invariants (every commit one repo, gov seam discipline, project-scoped paths).
- Run full `devtools::test()` and `devtools::check()`. Confirm count ≥ 1177.

## Acceptance Criteria

- [ ] `datom_store()` takes `data_repo_url` + `gov_repo_url`; old `remote_url` removed.
- [ ] `project.yaml` has `repos.data` + `repos.governance` sections.
- [ ] `datom_init_gov()` exists and creates a working shared gov repo (S3 + local data backends).
- [ ] `datom_init_repo()` produces exactly two commits across two repos, never one commit touching both.
- [ ] `datom_clone()` clones both repos with sibling default; override works; existing gov clone is reused.
- [ ] `datom_pull()` pulls both; `datom_pull_gov()` exists for gov-only.
- [ ] `datom_sync_dispatch()` produces a gov commit; data repo unaffected.
- [ ] `datom_decommission(conn, confirm = name)` removes one project from gov + tears down its data; refuses without confirm; leaves gov + other projects intact.
- [ ] `dispatch.json`, `ref.json`, `migration_history.json` all live at `projects/{name}/` in both gov clone and gov storage.
- [ ] Every gov-write helper marked `# GOV_SEAM:` with rationale comment.
- [ ] Audit: no data-write code path produces gov commits; no gov-write code path produces data commits.
- [ ] Sandbox teardown supports `scope = "all" | "project" | "gov"`.
- [ ] E2E passes for S3 and local data backends.
- [ ] `devtools::check()` clean; test count ≥ 1177; `pkgdown::build_site()` clean.
- [ ] Spec, copilot-instructions, NEWS updated.

## Open Questions / Risks

- **Migration of existing data products.** Out of scope for phase 15 (`datom_migrate_data()` deferred). Documenting that pre-phase-15 repos require manual migration is acceptable for now (no production deployments exist).
- **`gov_local_path` directory naming.** Default `{data_basename}-gov` may collide with user's existing folder. `.datom_gov_clone_init()` validates the remote URL on existing dirs and errors on mismatch — covers the collision case.
- **CODEOWNERS automation.** Deferred — companion package concern.
- **Companion package boundaries.** This phase keeps the seam tight via `# GOV_SEAM:` markers but doesn't introduce a plugin/registry mechanism. Premature abstraction risk avoided.
- **Concurrency on gov repo.** Two developers running `datom_sync_dispatch()` simultaneously could conflict on push. Phase 15 relies on git's standard pull-before-push discipline (already in `.datom_gov_push()` design); explicit lock mechanism deferred.

## Decisions Locked In

- GitHub remote required for both repos, both backends. No local-only git mode.
- `datom_decommission(confirm = name)` literal match; no interactive prompts.
- `dispatch.json` / `ref.json` / `migration_history.json` live at `projects/{name}/` (project-scoped paths in shared gov).
- `manifest.json` stays at data repo root (data-versioning state, not gov).
- `migration_history.json` is created (empty `[]`) by `.datom_gov_register_project()`. `datom_migrate_data()` deferred.
- CODEOWNERS automation deferred.
- NEWS.md follows tidyverse convention (user-visible only); phase 14 not backfilled.
- `# GOV_SEAM:` marker on every gov-write helper. No plugin/registry yet.
- `remote_url` → `data_repo_url` is a clean rename (pre-release; no deprecation shim).

## Phase Completion Procedure

When all acceptance criteria are met:

1. Final `devtools::test()` + `devtools::check()` clean run.
2. Migrate persistent learnings into `dev/datom_specification.md` and `.github/copilot-instructions.md` (gotchas, conventions).
3. Update `dev/README.md`: move from Active Phases → Completed Phases (with date, test count, summary).
4. Delete this file.
5. Open PR to `main`. After merge, delete `phase/15-separate-gov-repo` branch local + remote.
