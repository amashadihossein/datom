# Phase 18: Governance On-Demand

**Status**: Active -- Chunks 1-3 complete; Chunk 4 next (read/write paths in no-gov mode)
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
| 9 | **Tests + polish**: unit tests for no-gov paths, `datom_attach_gov()`, transition coverage (no-gov -> attached), failure modes for gov-only commands when gov absent. E2E: `dev/dev-sandbox.R` learns a no-gov mode (`sandbox_up(attach_gov = FALSE)`) and a "promote later" path. **Polish**: `datom_attach_gov()` detects an empty/uninitialized gov remote and redirects the user to `datom_init_gov()` with a clear message (rather than failing inside `.datom_gov_clone_init()` or downstream register). | Medium. |
| 10 | **Phase close**: harvest learnings to spec/instructions; update README; PR. | Low. |

### Recommended escalation moments

- **Chunk 1 design spot-check**: the resolver branches are the foundation; getting them wrong corrupts everything downstream.
- **Chunk 4 design spot-check**: `datom_get_conn()` accepting no-gov stores changes the conn shape; verify field set is consistent across roles.
- **Chunk 9 coverage review** before phase completion: confirm transition coverage actually exercises gov-attach, not just no-gov-only paths.

---

## Acceptance Criteria

1. `datom_init_repo()` accepts a no-gov store (`datom_store(governance = NULL, ...)`) and writes a `project.yaml` without `storage.governance` / `repos.governance`. (Chunk 2 dropped the planned `attach_gov` parameter; intent is expressed via store construction.)
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

### Chunk 2 -- `datom_init_repo()` no-gov path

**Design deviation from plan**: dropped the explicit `attach_gov` parameter. The phase doc proposed `datom_init_repo(attach_gov = FALSE)` as a user-facing switch, but during implementation it became clear the parameter would be redundant: intent is fully expressed by store construction (`datom_store(governance = NULL, ...)` vs `datom_store(governance = gov, ...)`). Adding `attach_gov` as a redundant arg violated DRY without making vignette code samples meaningfully clearer. Vignettes can still socialize the no-gov on-ramp by showing the no-gov `datom_store()` construction directly.

Discovery: gov clone init and `.datom_gov_register_project()` were already gated on `!is.null(gov_local_path)`, which `.datom_resolve_or_default_gov_path()` returns NULL for when both `gov_repo_url` and `gov_local_path` are absent (which Chunk 1 enforced for no-gov stores). So the only code change required in `datom_init_repo()` itself was the `project.yaml` writer.

Changes:
- `R/conn.R` -- `datom_init_repo()` `project.yaml` writer omits `storage.governance` and `repos.governance` blocks when `is.null(store$governance)`. Dispatch and ref payloads only built when gov attached. Roxygen updated.
- `tests/testthat/test-conn.R` -- new section "No-governance (gov-on-demand)" with `setup_init_env_nogov()` helper and 6 test_that blocks: end-to-end no-gov init success, `storage.governance` omitted, `repos.governance` omitted, no gov clone created, `.datom_gov_register_project()` not called, data repo still pushed to remote.

Tests: 1457 PASS / 0 FAIL (was 1443).

**Plan adjustment**: removed `attach_gov` parameter from Chunks 3-9 implementation expectations. `datom_attach_gov()` (Chunk 3) is the only user-facing switch for gov adoption; init-time intent is expressed via store construction. The vignette plan in Chunk 8 is unchanged in spirit (Article 1 shows no-gov init; Article 4 introduces `datom_attach_gov()`).

### Chunk 3 -- `datom_attach_gov()` on-ramp

New exported function `datom_attach_gov(conn, gov_store, gov_repo_url, gov_local_path = NULL, create_repo = FALSE, repo_name = NULL, github_org = NULL, private = TRUE)` lifts a no-gov project into the gov layer.

Design:
- Accepts a developer conn from a no-gov project. Reads `.datom/project.yaml`, derives `project_name`.
- Idempotent: detects already-attached state via `!is.null(conn$gov_root) || !is.null(cfg$storage$governance)`. Matching `gov_repo_url` no-ops; mismatched URL is a hard error (no detach, no swap).
- `create_repo = TRUE` reads `GITHUB_PAT` from env (no PAT arg -- attach reuses developer context), mutually exclusive with `gov_repo_url`.
- Resolves `gov_local_path` via `.datom_resolve_gov_local_path()` (sibling of data clone, named after gov repo).
- Reuses `.datom_gov_clone_init()` / `.datom_gov_validate_remote()` for clone bootstrap.
- Builds an `attach_conn` (input conn + gov fields) to feed `.datom_gov_register_project()`. Synthesizes a `data_snapshot` store-shaped object for `.datom_create_ref()` (resolver only needs root/prefix/region/type).
- Updates `project.yaml` atomically: tmp file + `fs::file_move()`. Storage block ordering preserved (governance before data, then `max_file_size_gb`).
- Commits + pushes the data repo with message `Attach governance: {project_name}`.
- Returns a fresh `datom_conn` with gov fields populated. Input conn becomes stale; caller rebinds.
- GOV_SEAM-tagged for companion-package extraction.

Changes:
- `R/conn.R` -- new `datom_attach_gov()` (~280 lines incl. roxygen) inserted after `datom_init_gov()`.
- `_pkgdown.yml` -- `datom_attach_gov` added to Connection & Setup group after `datom_init_gov`.
- `man/datom_attach_gov.Rd` + `NAMESPACE` regenerated.
- `tests/testthat/test-conn.R` -- new section `datom_attach_gov()` with `setup_attach_env()` helper and 7 test_that blocks: non-conn rejection, reader rejection, non-store-component rejection, mutual exclusion of `create_repo`/`gov_repo_url`, missing-URL rejection, end-to-end attach (project.yaml updated, gov clone seeded, data commit added, returned conn populated), idempotent re-call (no new commits), URL mismatch rejection.

Tests: 1464 PASS / 0 FAIL (was 1457; +7 new).


---

## Chunk 4 -- Read First (for the next session)

Chunk 4 makes read/write paths work end-to-end against a no-gov project. This is the highest-risk chunk in the phase; the recommended workflow is **design spot-check before code**.

### Files to read in full before editing

- [R/ref.R](R/ref.R) -- `.datom_resolve_data_location()` (line 225) and `.datom_check_ref_current()` (line 389). The resolver is already NULL-safe for `store$governance == NULL` (Chunk 1 confirmed). The write-time guard is the one that needs a no-gov branch: today it errors when ref disagrees with store; in no-gov mode there is no ref, so the guard must short-circuit.
- [R/conn.R](R/conn.R) -- `datom_get_conn()` (line ~1180), `.datom_get_conn_developer()` (line 1280), `.datom_get_conn_reader()` (line 1377). Both call `.datom_resolve_data_location()` and build a `datom_conn`. Audit which gov fields are referenced downstream and confirm they are NULL-safe.
- [R/read_write.R](R/read_write.R) -- `datom_write()` calls `.datom_check_ref_current(conn)` at line 438. Other call sites in `datom_read` / `datom_list` / `datom_history` should be inventoried.
- [R/sync.R](R/sync.R), [R/validate.R](R/validate.R) -- callers of gov fields. `datom_validate()` is flagged in Open Items (skip dispatch check when gov absent).

### Invariants for Chunk 4

- **No-gov reads + writes never touch a gov client.** If the code path requires `conn$gov_client` or `conn$gov_local_path`, that path is gov-only and must short-circuit when `is.null(conn$gov_root)`.
- **No-gov writes are unguarded against stale conns** (locked decision #7). The `.datom_check_ref_current()` call in `datom_write()` becomes a no-op when gov is absent; do not invent a substitute guard.
- **Reader role pre-gov needs `data_repo_url`** (Open Items). A reader without gov has no ref to resolve from, so they must supply the data repo URL explicitly. Confirm the field set on `datom_get_conn(role = 'reader')` for the no-gov case before implementing.
- **The Chunk 3 `datom_attach_gov()` returns a fresh conn**: after attach, `datom_get_conn()` on the same project must produce a conn with the same gov-populated shape. The two paths must converge.
- **`datom_validate()` skips dispatch consistency check when gov absent**, reports it in summary (do not error).

### Suggested chunk decomposition (for the next session to confirm)

1. Audit + design spot-check (escalate). Map every read of `conn$gov_*` across `R/`. Decide: short-circuit at caller, or short-circuit inside the helper?
2. `.datom_check_ref_current()` no-gov branch + `datom_write()` regression tests.
3. `datom_get_conn()` no-gov developer path (parallels Chunk 2's `datom_init_repo` work).
4. `datom_get_conn()` no-gov reader path (depends on Open Items resolution for `data_repo_url`).
5. `datom_read` / `datom_list` / `datom_history` end-to-end tests against a no-gov project.
6. `datom_validate()` no-gov summary line.

### Test infrastructure already in place

- `setup_init_env_nogov()` in [tests/testthat/test-conn.R](tests/testthat/test-conn.R) (line ~886) -- builds a no-gov developer init env. Reusable.
- `setup_attach_env()` in [tests/testthat/test-conn.R](tests/testthat/test-conn.R) (Chunk 3) -- builds a no-gov project + bare gov repo, ready for attach. Reusable for transition tests.

Baseline: **1464 PASS / 0 FAIL** at start of Chunk 4.
