# Phase 15 Cleanup: Audit Follow-ups

**Status**: Active (planning)
**Branch**: `phase/15-separate-gov-repo` (existing — PR #6 still open, fold cleanup in)
**Depends on**: Phase 15 main work (complete, 1325 tests)
**Started**: 2026-04-27

---

## Goal

Fold pre-CRAN audit findings that are thematically Phase-15 (introduced or touched by Phase 15 code) into the existing PR before merging. Items that require deeper refactoring of conn flow are deferred to a separate phase (see `dev/draft_phase_conn_refactor.md`).

---

## Context

After Phase 15 main work completed (PR #6 opened), a pre-CRAN audit identified ~17 issues across fragility, redundancy, and cleanup categories. 15 of those are Phase-15-introduced or Phase-15-adjacent and small enough to fold into the same PR. 2 (M2, M6 from the audit) touch the conn finalize flow and warrant their own phase.

This phase keeps the PR coherent ("separate gov repo + the cleanup that should have been part of it") rather than landing a known-imperfect state and chasing it with a follow-up PR.

### Read first
- [conn.R](../R/conn.R) — `datom_init_repo`, `datom_init_gov`, `datom_clone`, `_get_conn_*`
- [sync.R](../R/sync.R) — `datom_pull`, `datom_pull_gov`, `datom_sync_dispatch`
- [decommission.R](../R/decommission.R) — `datom_decommission`, `.datom_gh_available`
- [utils-gov.R](../R/utils-gov.R) — GOV_SEAM helpers, especially `.datom_gov_commit` and `.datom_gov_unregister_project`

### Invariants (must not regress)
- 1325 tests pass after every chunk.
- `# GOV_SEAM:` markers stay correct — any new gov-write helper must carry the marker.
- `.init_success` semantics: `datom_init_repo()` only reports success when **all** side effects succeeded.
- Storage abstraction: business logic continues to call `.datom_storage_*()`, never `.datom_s3_*()` or `.datom_local_*()` directly.
- Backend-aware UI labels (Phase 13 contract) — no hardcoded `s3://` strings outside S3-only code paths.

---

## Chunks

Each chunk is a single commit. Run `devtools::test()` after each; report count in commit message.

### Chunk 1 — `datom_init_repo()` robustness (Critical)

**Problem (audit C1):** `tryCatch` around `.datom_gov_register_project()` and the manifest upload converts errors to warnings but still flips `.init_success <- TRUE`. User sees green; state is half-built.

**Problem (audit C2):** `on.exit` cleanup tracks data-side artefacts (`path_existed`, `datom_existed`) but not the gov clone created at step 0. Failed init can leave a half-cloned gov dir that next-run picks up as "already exists."

**Fix:**
- Remove `tryCatch` around `.datom_gov_register_project()` — let it abort and trigger cleanup. The whole point of registration ordering (data-first, gov-after) is so that registration failure aborts cleanly without orphaned advertised state.
- For manifest upload: same — abort on failure. The manifest is part of the data-side contract, not optional polish.
- Track `gov_path_existed_before` and `gov_clone_created_here` flags; on failure, remove the gov clone if we created it.
- Add tests that simulate gov-register failure and manifest-upload failure; assert cleanup runs and no partial state remains.

**Effort:** 1-2 hours.

**Acceptance:**
- All paths through `datom_init_repo()` either succeed fully or roll back fully (no half-states).
- Test suite gains explicit partial-failure coverage.

---

### Chunk 2 — `datom_decommission()` GitHub via API (High)

**Problem (audit H1):** Uses `system2("gh", ...)` and skips with warning if `gh` is unavailable. Inconsistent with `.datom_create_github_repo()` which uses `httr2`. Adds an external CLI dependency unfriendly to CRAN users.

**Fix:**
- Add `.datom_delete_github_repo(repo_url, github_pat)` in [R/utils-github.R](../R/utils-github.R) (or wherever `.datom_create_github_repo` lives) using `httr2::request("https://api.github.com/repos/{owner}/{repo}") |> req_method("DELETE") |> req_auth_bearer_token(pat)`.
- Replace the `system2` block in `datom_decommission()`.
- Note in docs: `delete_repo` scope on the PAT is required (mention in error message on 403).
- Drop `.datom_gh_available()` and the gh-CLI skip path.

**Effort:** ~30 LOC + tests.

**Acceptance:**
- `datom_decommission()` no longer references `system2` or `gh` CLI.
- Test mocks the DELETE call and asserts it fires with correct URL + auth.

---

### Chunk 3 — `sync.R` polish (High)

Bundle three small fixes:

**H2 — backend-blind `s3://` string in `datom_sync_dispatch()` confirmation prompt.**
Replace `paste0("s3://", conn$root, "/", conn$prefix)` with the lookup pattern: `c(s3 = "s3://", local = "file://")[conn$backend] %||% ""` prefix.

**H3 — `datom_pull()` / `datom_pull_gov()` error asymmetry.**
Currently gov-pull errors warn and continue; data-pull errors propagate. Make both abort by default. Cite `datom_pull()` in `.datom_check_ref_current()` error messages so users have a clear next step.

**H4 — dead fallback in `datom_sync_dispatch()`.**
Branch where `gov_local_path` is null writes to `.datom/dispatch.json|ref.json|migration_history.json` (Phase 14 layout). Post-Phase 15 every developer conn has `gov_local_path`. Replace with `cli_abort("datom_sync_dispatch requires a developer connection with a gov clone")`.

**L3 — `datom_sync_dispatch()` confirmation message.**
Says "dispatch metadata for N tables" but actually syncs gov files (dispatch + ref + migration) AND per-table metadata. Refine wording.

**Effort:** ~1 hour.

**Acceptance:**
- Local-backend sandbox run shows correct UI labels (no `s3://` strings).
- Gov-pull failure aborts with a clear message.
- Removing `gov_local_path` fallback breaks no tests (confirms it was dead).

---

### Chunk 4 — Refactor pass: dedup helpers (Medium)

**M1 — `gov_local_path` resolution duplicated 3×.**
Extract `.datom_resolve_or_default_gov_path(store, data_local_path)` in [R/store.R](../R/store.R). Replace the `if (!is.null(store$gov_local_path)) ... else if (!is.null(store$gov_repo_url)) .datom_resolve_gov_local_path(...) else NULL` pattern in `datom_init_repo()`, `datom_clone()`, and `.datom_get_conn_developer()`.

**M3 — `datom_init_gov()` two-path config redundancy.**
`create_repo = TRUE` and `create_repo = FALSE` branches both set `git2r::config(user.name, user.email)` and create the first commit. Converge to a single post-setup block; the branches differ only in *how* the local repo comes into being (init+remote_add vs clone), not in *what config* it needs after.

**M5 — `.datom_gov_unregister_project()` reimplements commit logic.**
Add `staged_deletions = TRUE` flag to `.datom_gov_commit()` that skips the file-existence check and uses `git2r::add(..., force = TRUE)`. Remove the duplicated pull+commit block in `.datom_gov_unregister_project()`.

**M4 — positional `new_datom_conn()` call in `datom_init_repo()` namespace check.**
Switch to named args. Trivial defensive change.

**Effort:** ~1.5 hours.

**Acceptance:**
- 3 call sites for `gov_local_path` resolution become 1 helper + 3 call sites of the helper.
- `datom_init_gov()` has one config/first-commit block, not two.
- `.datom_gov_unregister_project()` calls `.datom_gov_commit(staged_deletions = TRUE)`.

---

### Chunk 5 — Polish (Low)

Bundle remaining low-priority items:

**L1 — Path style consistency.**
Replace `paste0("projects/", project_name)` in [decommission.R](../R/decommission.R) with `glue::glue("projects/{project_name}")` to match [utils-gov.R](../R/utils-gov.R).

**L2 — Document `record_migration` ordering.**
Add a one-liner to spec "Governance Repository Contract" section: "Migration events are prepended (most-recent-first) so the head of `migration_history.json` is the active record."

**L4 — `.datom_gov_destroy()` scope reminder.**
Add a `cli_inform()` at function entry: "Destroying local gov clone only — caller is responsible for storage and GitHub repo deletion (see `datom_decommission` for project-scoped teardown)."

**L5 — `datom_init_gov()` idempotence marker order.**
Move remote URL validation **before** the `projects/.gitkeep` existence check. Defensive ordering; current code is functionally correct but the read order surprises.

**Effort:** ~30 minutes.

**Acceptance:**
- Style sweep complete.
- Spec updated with one new line.
- No behavior changes; pure clarity.

---

## Out of scope (deferred)

Tracked in `dev/draft_phase_conn_refactor.md`:

- **M2** — dedup ref-resolution + migration-detection across `_developer` / `_reader`. Branches differ subtly (developer auto-pulls, reader warns); merging needs care.
- **M6** — `.datom_conn_for(scope = c("data", "gov"))` accessor. Cross-cutting refactor across many call sites; deliberate API cleanup.

These are not blocking CRAN.

---

## Status tracking

| Chunk | Status | Tests | Commit |
|-------|--------|-------|--------|
| 1. init_repo robustness | completed | 1331 | bbca99a |
| 2. decommission via API | completed | 1341 | 18da761 |
| 3. sync.R polish | completed | 1335 | 193bd6c |
| 4. dedup helpers | completed | 1335 | (pending) |
| 5. polish | not-started | — | — |

Update this table at the end of each chunk.

---

## Phase Completion Procedure

When all chunks are done:
1. Run E2E (`dev/dev-sandbox.R` + `dev/e2e-test-local.R`).
2. Migrate any new persistent learnings into spec / copilot-instructions.
3. Update `dev/README.md` Phase 15 entry to mention "+ audit cleanup".
4. Force-push branch, update PR #6 description.
5. Delete this doc (`dev/phase_15_cleanup.md`).
6. Remove from Active Phases table.
