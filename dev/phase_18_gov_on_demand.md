# Phase 18: Governance On-Demand

**Status**: Active -- Chunk 1 (schema + resolver plumbing) complete; Chunk 2 next
**Branch**: `phase/18-gov-on-demand` (created 2026-05-02)
**Depends on**: Phase 16 closed (2026-05-02), Phase 17 closed (2026-05-02).
**Supersedes**: `dev/draft_phase_conn_refactor.md` (M2 folds in; M6 absorbed as a chunk).

---

## Goal

Make the governance layer **optional and on-demand**. A new datom project starts with `datom_init_repo(attach_gov = FALSE)` -- just a data git repo + a backend (filesystem or S3) -- and graduates to governance later via `datom_attach_gov()`, typically when migrating to object storage. Once attached, gov cannot be detached.

This dramatically lowers the onboarding barrier (currently: GitHub PAT + AWS keys + gov bucket + gov repo + data bucket + data repo, all on day one). It also aligns the `# GOV_SEAM:` boundary with a real user-visible tier rather than an internal hygiene line, sharpening the eventual companion-package extraction (`datom_access` / `datomanager` / TBD).

---

## Context

### What's mandatory today (and was reaffirmed in Phase 16)

> Git + GitHub remote are mandatory, always... metadata still requires a `data_repo_url` and `gov_repo_url`.

Both halves were locked. Phase 18 **amends** the lock: the data half stays mandatory; the gov half becomes optional. The amendment is a deliberate, public revision -- not a quiet rollback. Chunk 0 lands the principle text update before any code moves.

### Why now

- Phase 16 vignettes made the cost of mandatory-gov visible. Article 1 (First Extract) needs `datom_init_gov()` + `datom_init_repo()` + a GitHub gov repo + (sometimes) AWS keys before the user has versioned a single table. The narrative works, but the friction is real.
- Phase 17 shipped portfolio helpers. Those helpers gracefully degrade when gov is absent (`datom_projects()` errors with a clear message), so we have the pattern.
- The companion-package extraction (referenced repeatedly in spec + copilot-instructions as future work) needs a clean lift-out. Today's seam is fragmented because gov is forced on every project; gov-on-demand makes the seam align with a real tier.

### Two tiers

| Tier | What you have | Package surface |
|------|---------------|-----------------|
| 1 (datom alone) | Versioned tables; GitHub for metadata; filesystem (possibly shared/network) or S3 for data; per-project work, no portfolio. | `datom` only. |
| 2 (datom + companion) | Adds governance: portfolio register, dispatch routing, IAM-style access policies, managed migration. | `datom` + companion. |

`datom_attach_gov()` is the on-ramp from tier 1 to tier 2. It's seamed (companion-bound long-term) but lives in datom for now.

---

## Locked Decisions

1. **Default `attach_gov = FALSE`** in `datom_init_repo()`. Documentation strongly nudges users with long-term ambitions or an existing org gov to attach from day one.
2. **Migration requires gov.** `datom_migrate_data()` (Phase 19) preconditions on `datom_attach_gov()` having been called. Migration is the natural moment to invest in gov.
3. **`local` -> `filesystem` rename: deferred.** Backlog entry added; documentation in this phase describes the filesystem backend in shared-network terms (network mount, cloud-mounted FS) regardless of the type tag.
4. **`parents` and `source_lineage` both ship** (Phase 20, separate). dpbuild populates both. datom never auto-computes (parallels current `parents` behavior).
5. **No detach.** Once `datom_attach_gov()` runs, the project is gov-attached forever. `project.yaml`'s `storage.governance` block, once populated, cannot be removed.
6. **Pre-gov migration is not supported.** A user who wants to move data must first attach gov. This keeps the resolver simple (no sidecar-redirect code path) and gives the "invest to graduate" narrative a single transition moment.
7. **No-gov writes are unguarded against stale conns.** This is fine: pre-gov projects haven't migrated, so the only thing the guard protects against is stale data location, which is impossible until first migration. After `datom_attach_gov()`, the standard guard kicks in.

---

## Companion-package alignment

After Phase 18 ships, the eventual companion package owns:

- `datom_init_gov()` (move out)
- `datom_attach_gov()` (born here, ports out later)
- `datom_decommission()` -- gov-half (split: data-half stays in datom, gov-half ports out)
- `datom_sync_dispatch()` (move out)
- All `# GOV_SEAM:` helpers in `R/utils-gov.R` (move out)

Datom retains:

- All read/write/sync paths (the dual-mode resolver stays)
- `datom_projects()` (pure read; works against a gov clone if installed alongside companion)
- `datom_decommission()` -- data-half
- Everything else

This is a much tighter, more coherent scope than today's seam.

---

## Chunks

| Chunk | Content | Risk |
|---|---|---|
| 0 | **Phase activation**: this doc + `dev/README.md` Active table update + draft removal + principle amendment in `.github/copilot-instructions.md` and `dev/datom_specification.md`. | Low (docs only). |
| 1 | **Schema + resolver**: `project.yaml` no-gov shape (`storage.governance` block absent or `null`); `.datom_resolve_data_location()` no-gov branch reads `storage.data` from `project.yaml`; `is_datom_store()` accepts a store with `governance = NULL`. Plumbing only -- no user-facing function changes yet. | Medium (touches the resolver). |
| 2 | **`datom_init_repo(attach_gov = FALSE)`** path: writes `project.yaml` without gov, no `ref.json`/`dispatch.json`/`migration_history.json`, no gov clone, no gov repo creation. Data repo + GitHub repo creation works as today. | Medium. |
| 3 | **`datom_attach_gov()`**: idempotent promotion. Initializes gov clone if absent, writes `projects/{name}/{ref,dispatch,migration_history}.json`, updates `project.yaml`'s `storage.governance` block, commits to gov repo. Marked `# GOV_SEAM:`. New export. | Medium. |
| 4 | **Read/write paths in no-gov mode**: `datom_read` / `datom_write` resolve location from `project.yaml`; skip ref-current write guard; everything else unchanged. `datom_get_conn()` accepts no-gov stores. | High (read/write surface). |
| 5 | **Decommission no-gov branch**: skip `.datom_gov_unregister_project()` step when gov absent. Data + GitHub + local clone teardown only. | Low. |
| 6 | **`.datom_conn_for(scope)` accessor** (M6 absorbed). Single accessor `(.datom_conn_for(conn, "data"|"gov"))` replaces ad-hoc `conn$gov_client` / `.datom_gov_conn(conn)` picking across `R/conn.R`, `R/sync.R`, `R/ref.R`, `R/utils-gov.R`, `R/validate.R`. Pure refactor, no behavior change. | Medium (touches many files). |
| 7 | **Gov-only commands fail clearly when gov absent**: `datom_projects()`, `datom_pull_gov()`, `datom_sync_dispatch()`, `datom_decommission()` (gov-half) all detect `is.null(conn$gov_root)` and emit a single uniform error: "this project has no governance attached; use `datom_attach_gov()` to enable." | Low. |
| 8 | **Vignettes**: Article 1 (First Extract) drops `datom_init_gov()` and uses `attach_gov = FALSE`; Article 4 (Promoting to S3) introduces `datom_attach_gov()` alongside the S3 promotion -- the natural moment. Articles 5-9 unchanged structurally. Resume scripts updated where they construct stores. README rewritten to drop gov from the primary example. | Medium (locked text changes). |
| 9 | **Tests**: unit tests for no-gov paths, `datom_attach_gov()`, transition coverage (no-gov -> attached), failure modes for gov-only commands when gov absent. E2E: `dev/dev-sandbox.R` learns a no-gov mode (`sandbox_up(attach_gov = FALSE)`) and a "promote later" path. | Medium. |
| 10 | **Phase close**: harvest learnings to spec/instructions; update README; PR. | Low. |

### Recommended escalation moments

- **Chunk 1 design spot-check**: the resolver branches are the foundation; getting them wrong corrupts everything downstream.
- **Chunk 4 design spot-check**: `datom_get_conn()` accepting no-gov stores changes the conn shape; verify field set is consistent across roles.
- **Chunk 9 coverage review** before phase completion: confirm transition coverage actually exercises gov-attach, not just no-gov-only paths.

---

## Acceptance Criteria

1. `datom_init_repo()` defaults to `attach_gov = FALSE`; existing tests adapted.
2. `datom_attach_gov()` exported, idempotent, marked `# GOV_SEAM:`, with full test coverage.
3. `datom_read` / `datom_write` / `datom_list` / `datom_history` work against a no-gov project end-to-end.
4. `datom_decommission()` works for no-gov and gov-attached projects.
5. Gov-only commands (`datom_projects`, `datom_pull_gov`, `datom_sync_dispatch`) emit a uniform "no governance attached" error when called against a no-gov conn.
6. Vignettes Article 1 simplifies; Article 4 shows the gov-attach moment alongside S3 promotion. README's primary example is no-gov.
7. E2E sandbox supports no-gov and promote-later flows.
8. `devtools::test()` passes with no regressions in pre-existing test count for shared paths.
9. `pkgdown::build_site()` clean.
10. Principle text in `.github/copilot-instructions.md` and `dev/datom_specification.md` reflects gov-on-demand.

---

## Invariants -- Read Before Each Chunk

- **Data git + GitHub remain mandatory.** Only the gov half becomes optional. Do not introduce a no-git mode.
- **Once attached, gov cannot be detached.** No `datom_detach_gov()`. Ever. The check is: `if storage.governance is populated in project.yaml, gov is on for this project`.
- **No sidecar redirect.** Pre-gov projects do not migrate. If they want to migrate, they attach gov first. Do not add MOVED-file or env-var redirect machinery in this phase.
- **`# GOV_SEAM:` discipline tightens.** Any new gov-write helper introduced in this phase must be marked. `datom_attach_gov()` itself is seamed.
- **Filesystem backend documentation uses shared-network framing.** Vignettes describe the filesystem backend as supporting network mounts and cloud-mounted FS, not just laptop disks.
- **No phase/chunk numbers in `R/` source comments.** Standard rule.

---

## Open Items / To Decide During Work

- **Storage shape of `project.yaml`'s `storage.governance` when gov is absent**: omit the key entirely, or write `governance: null` explicitly? Lean: omit. Smaller diff, clearer intent. Resolver checks `is.null(cfg$storage$governance)`.
- **`datom_attach_gov()` on a project that already has a gov-pointer in `project.yaml` but no actual gov clone**: idempotent re-clone, or hard error? Lean: re-clone to `gov_local_path` (same idempotency rule as `datom_get_conn`).
- **Reader role pre-gov**: a reader has only `project_name` + the data repo URL. Without gov, what does `datom_get_conn(project_name = ...)` do? Lean: requires the data repo URL directly. Add a `data_repo_url` field to the reader path of `datom_get_conn()` for the no-gov case. Confirm in Chunk 4 design spot-check.
- **`datom_validate()` no-gov mode**: `dispatch.json` consistency check is moot. Validator should report "no governance attached -- skipping dispatch check" in summary, not error. Confirm in Chunk 4.
- **Multi-project gov clone**: today one gov clone serves many data projects. With on-demand attach, is the user expected to have already cloned the org gov repo before calling `datom_attach_gov()`? Lean: `datom_attach_gov()` clones into `gov_local_path` if absent, validates URL match if present. Same as `datom_init_repo()` does today.

---

## Future Work (spawned during this phase)

- **`local` -> `filesystem` rename** (recorded in backlog under Phase 18): rename the backend type tag, store constructor, predicate, dispatch arms, and project.yaml schema entries. Atomic schema bump. Defer until there's a second compelling reason to touch the schema.
- **Phase 19 (already on roadmap)**: `datom_migrate_data()`. Phase 18 establishes the precondition (gov attached); Phase 19 builds the orchestrator.
- **Phase 20 (planned)**: transitive provenance (`source_lineage` field). Schema-additive, dpbuild-populated, `datom_get_lineage()` query helper.
- **Companion-package extraction**: the actual lift-out of gov code into a separate package. Phase 18 makes this a much tighter scope than today's `# GOV_SEAM:` seam permitted.

---

## Notes

- This phase amends a Phase-16-locked principle. The amendment is the first Chunk 0 commit so the principle text is current before any code moves.
- The conn refactor draft (`dev/draft_phase_conn_refactor.md`) is superseded: M2 (dedup `_developer`/`_reader`) is folded into Chunks 1+4 because gov-on-demand rewrites the same surface; M6 (`.datom_conn_for(scope)`) is absorbed as Chunk 6.
- Pre-release status: no users, no backward-compat concerns. Default flips and schema changes are acceptable without migration plumbing.

---

## Progress Log

### Chunk 0 -- Activation (`f554a57`)

Plan doc landed. Principle amended in `.github/copilot-instructions.md` and `dev/datom_specification.md` (data git+GitHub mandatory; gov optional via `datom_attach_gov()`). `dev/README.md` updated: Phase 18 in Active table, conn-refactor draft removed, `local`->`filesystem` rename added to backlog. `dev/draft_phase_conn_refactor.md` deleted (M2 + M6 absorbed into Chunks 1/4/6).

### Chunk 1 -- Schema + resolver plumbing

Surgical scope landed. Discovery: `.datom_resolve_data_location()` already short-circuits with `if (is.null(store$governance)) return(NULL)` (R/ref.R), and `.datom_build_init_conn()` already handles `gov_store = NULL` (R/conn.R) -- both NULL-safe today. The only gate forbidding a no-gov store was `datom_store()` itself.

Changes:
- `R/store.R` -- `datom_store(governance = NULL, ...)` accepted. `gov_repo_url` and `gov_local_path` must also be NULL when governance is NULL (consistency check). Identity unpacking is NULL-safe. `print.datom_store` shows "not attached" for the gov line when absent. Roxygen updated.
- `tests/testthat/test-store.R` -- 8 new test blocks: NULL-governance default, explicit NULL, developer + reader roles with no gov, gov-arg consistency rejection (`gov_repo_url` and `gov_local_path`), print rendering, resolver returns NULL for no-gov store.

No user-facing function changes. `datom_init_repo()`, `datom_get_conn()`, `project.yaml` writer, and conn-resolution flows still require gov today -- those are Chunks 2-4.

Tests: 1443 PASS / 0 FAIL (was 1416). pkgdown not rebuilt (no new exports or doc refs).

