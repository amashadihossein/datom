# Phase 7: Multi-Developer Collaboration & Guardrails

## Overview

This phase addresses a gap in the current tbit design: what happens when multiple
developers work on the same data repository simultaneously? The current implementation
assumes a single developer. This phase adds safety checks, conflict-avoidance
mechanisms, and tooling to make collaborative team workflows safe and well-documented.

**Status**: Complete (all 4 chunks)

**Depends on**: Git operations (Phase 3: `.tbit_git_push`), sync workflow
(Phase 6: `tbit_sync`, `tbit_sync_routing`), connection & init (Phase 4:
`tbit_init_repo`, `tbit_get_conn`)

### Pre-work completed (pre-Phase 7)

- **Bug fix**: `tbit_sync()` was not committing/pushing `manifest.json` to git after writes — S3 got updated but GitHub stayed stale.
- **Write ordering enforced**: All write paths (`tbit_write`, `.tbit_sync_metadata`, `tbit_sync`) now follow strict **local → git → S3** ordering. Git failure blocks S3 writes.
- **Resilience**: `.tbit_git_commit()` made idempotent (returns HEAD SHA on no-op). Re-runs after partial failures pick up where they left off.
- **`.tbit_write_metadata` split** into `.tbit_write_metadata_local()` (disk only) + `.tbit_push_metadata_s3()` (S3 only) to enable gated ordering.
- **Phase 8 complete**: Metadata enrichment (`table_type`, `size_bytes`, `parents`, `original_file_sha`, `endpoint`, `tbit_get_parents()`). All chunks landed.
- **Post-Phase-8 bug fixes** (E2E-driven):
  - `tbit_write()` now updates `manifest.json` per call (was only done in batch by `tbit_sync`).
  - `tbit_init_repo()` pushes `routing.json` + `manifest.json` to S3 after git push.
  - **Idempotent SHA**: metadata SHA uses JSON canonical form (`jsonlite::toJSON` + `serialize=FALSE`) to avoid R type-sensitivity after JSON round-trip. Volatile fields (`created_at`, `tbit_version`) excluded from hash.
  - **Version history dedup guard**: `.tbit_write_metadata_local()` skips append when latest entry has same version SHA.
  - **UX**: `tbit_write()` informs user when skip discards a different commit message.
- **Test suite**: 905 tests, 0 failures.

---

## Problem Space

### Scenario 1: Concurrent Syncs

Two developers (alice and bob) have cloned the same data repo. They each receive
different table updates from the data management team and run `tbit_sync()` at the
same time:

- alice is syncing `dm` and `lb`
- bob is syncing `ex` and `vs`

**Risks**:
- Both may git pull from a stale state, then push. The second push will fail
  (non-fast-forward), but the first leaves git and S3 partially inconsistent
  if the commit includes manifest updates
- `manifest.json` is a single file that both commits modify — merge conflicts
  are likely unless pull-before-push is enforced

**Current behavior**: No protection. Race conditions can leave the manifest in an
inconsistent state.

---

### Scenario 2: Accidental Overwrite of Another Team's S3 Namespace

A second team independently runs `tbit_init_repo()` using the same S3 bucket
and prefix as an existing project. They do not know the namespace is taken.
Their `tbit_sync()` will upload parquet files and overwrite `.metadata/manifest.json`
and `.metadata/routing.json` with their own project's data — silently destroying
the original project's S3 metadata.

**Current behavior**: `tbit_init_repo()` checks whether the local path exists, but
does **not** check whether the S3 namespace is already occupied by another project.

---

### Scenario 3: Project Name Collision

Two teams each initialize a project called `"STUDY_001"` pointing at different
S3 prefixes within the same bucket. Credential env var names are derived from
the project name, so both teams use `TBIT_STUDY_001_ACCESS_KEY_ID`. If a developer
works on both projects, the credentials will silently cross-contaminate.

**Current behavior**: No detection. Manifest reads would succeed but read the
wrong project's data.

---

### Scenario 4: Diverged Git History

Developer alice pushes a sync commit while bob's local clone is behind. Bob's
next `tbit_sync()` creates a commit on top of his stale HEAD. His push fails.
Bob pulls, resolves the merge, and pushes. But his S3 sync has already
run — S3 is now ahead of what will eventually be committed to git.

**Current behavior**: The git push failure is unhandled. S3 may be partially
updated before the git failure is discovered.

---

## Design Decisions

### D1: Pull Before Push — Always

Every operation that writes to git must perform a `git pull` (fetch + merge)
**before** staging any files, not just before pushing. This is the primary
defense against diverged histories.

**Change**: `.tbit_git_push()` currently does fetch+merge+push. Move the pull
to the **start** of the write operation (before writing metadata files), so
git state is fresh when files are written.

**Affected code**: `.tbit_sync_metadata()`, `tbit_sync_routing()`,
`.tbit_git_push()`.

---

### D2: S3 Namespace Safety Check in tbit_init_repo()

Before writing any files, `tbit_init_repo()` should check whether the target
S3 namespace is already occupied by checking for the existence of
`{prefix}/tbit/.metadata/manifest.json`. If found, abort with a helpful error
showing the existing project name (from manifest content).

**New function**: `.tbit_check_s3_namespace_free(conn)` — reads manifest,
returns `TRUE` if namespace is free, aborts with actionable message if occupied.
Bypass flag: `.force = FALSE` parameter on `tbit_init_repo()` for explicit
override (rare, intentional takeover scenario).

---

### D3: Project Identity Embedded in S3 Metadata

The manifest should store `project_name` at the repo level so namespace
collisions are detectable — not just by path but by declared identity.

**Change to manifest.json**:
```json
{
  "project_name": "STUDY_001",
  "updated_at": "...",
  "tables": {...},
  "summary": {...}
}
```

`tbit_init_repo()` writes this. `tbit_validate()` cross-checks that the
manifest's `project_name` matches `conn$project_name`. A mismatch indicates
a namespace collision.

---

### D4: Stale State Detection

When `tbit_sync()` starts, check that the local git HEAD matches the remote
HEAD. If behind, require pull before proceeding. Do not silently auto-pull
(could mask conflicts) — abort with a clear message.

**New function**: `.tbit_check_git_current(conn)` — compares local HEAD SHA to
remote HEAD SHA via `git2r::fetch()` + ref inspection. Returns `TRUE` if
current, aborts with:

```
✖ Local git branch "main" is behind remote by 2 commits.
ℹ Run git pull (or tbit_pull()) to update before syncing.
```

---

### D5: tbit_pull() — Developer Convenience Function

A thin wrapper around git pull that also refreshes the local manifest from S3.
This ensures the developer's view of the repository is always consistent before
they start work.

```r
tbit_pull(conn)
#> ✔ Pulled 2 commits from origin/main.
#> ✔ Manifest refreshed from S3.
```

Internally:
1. `git2r::fetch()` + `git2r::merge()` (existing `.tbit_git_push()` logic,
   extracted as `.tbit_git_pull()`)
2. Read manifest from S3 and confirm it matches the local `.tbit/manifest.json`

---

### D6: Collaboration Vignette

A new vignette: `vignettes/team-collaboration.Rmd`

Covers:
- Recommended team setup (shared S3 bucket, separate git clones)
- Who should run `tbit_init_repo()` (once, by one person — everyone else clones)
- Daily workflow: pull → receive extract → sync → push
- What to do when sync is rejected (push conflict resolution)
- Reader setup: how to share bucket/prefix/project_name with readers
- Credential management: each developer uses their own AWS credentials, same
  bucket; env var names are derived deterministically from project name

---

## Acceptance Criteria

### Chunk 1: S3 Namespace Safety Check

- [x] `.tbit_check_s3_namespace_free()` implemented and tested
- [x] `tbit_init_repo()` calls it before writing any files
- [x] `tbit_init_repo()` gains `.force = FALSE` parameter
- [x] `manifest.json` written by `tbit_init_repo()` includes `project_name`
- [x] `tbit_validate()` checks `project_name` matches conn
- [x] Tests: namespace free (new project), namespace occupied (same project name),
  namespace occupied (different project name), `.force = TRUE` bypass,
  project_name in manifest, tbit_validate project_name mismatch,
  pre-Phase-7 manifest tolerance, connectivity failure graceful handling

### Chunk 2: Pull-Before-Push Discipline

- [x] `.tbit_git_pull()` extracted as standalone internal function
- [x] `.tbit_sync_metadata()` calls pull at the start, before writing metadata
- [x] `.tbit_check_git_current()` implemented — detects stale local state
- [x] `tbit_sync()` calls `.tbit_check_git_current()` at entry
- [x] Clear, actionable error message when behind remote
- [x] Tests: up to date (no-op), behind remote (error), pull resolves and
  sync proceeds

### Chunk 3: tbit_pull()

- [x] `tbit_pull(conn)` exported and documented
- [x] Pulls git + refreshes manifest from S3
- [x] Works for developer role only (readers have no git)
- [x] Returns invisible summary (commits pulled, manifest status)
- [x] Tests: clean pull, nothing to pull, conflict (merge failure) handled
  with clear message

### Chunk 4: Team Collaboration Vignette

- [x] `vignettes/team-collaboration.Rmd` created
- [x] Covers: init (once), clone, daily workflow, conflict recovery, reader setup
- [x] Explains env var naming convention for teams sharing a bucket
- [x] Shows `tbit_pull()` as the entry point to each work session
- [x] Renders without errors

---

## Current State

**Chunk 1: S3 Namespace Safety Check — COMPLETE** (923 tests, 0 failures)

Implementation summary:
- `.tbit_check_s3_namespace_free(conn)` in `R/utils-validate.R`: uses `head_object` via `.tbit_s3_exists()` to check for `.metadata/manifest.json`, reads `project_name` from manifest if occupied, aborts with actionable error.
- `tbit_init_repo()` gains `.force = FALSE` param; namespace check runs after credential validation but before any file creation. Connectivity failures are swallowed (warned) so offline init still works.
- `manifest.json` now includes `project_name` at the top level (set by `tbit_init_repo()`, preserved by `.tbit_update_manifest_entry()`).
- `.tbit_validate_project_name(conn)` in `R/validate.R`: cross-checks manifest's `project_name` against `conn$project_name`. Tolerates pre-Phase-7 manifests (no `project_name` field).
- 18 new tests across `test-utils-validate.R`, `test-validate.R`, and `test-conn.R`.

**Chunk 2: Pull-Before-Push Discipline — COMPLETE** (942 tests, 0 failures)

Implementation summary:
- `.tbit_git_pull(path)` extracted as standalone internal in `R/utils-git.R`: opens repo, verifies remote, fetches, merges upstream (if upstream branch exists), aborts on merge conflict.
- `.tbit_check_git_current(path)` in `R/utils-git.R`: fetches from remote, compares local HEAD vs upstream HEAD via `git2r::ahead_behind()`. Aborts with actionable error ("behind remote by N commits, run tbit_pull()") when stale. Gracefully handles: no remote (passes), no upstream branch (passes), network errors (warns, passes).
- `.tbit_git_push(path)` refactored to call `.tbit_git_pull(path)` first, then push.
- `.tbit_sync_metadata()` calls `.tbit_git_pull()` before reading metadata.
- `tbit_sync()` calls `.tbit_check_git_current()` after validation, before processing.
- 19 new tests in `test-utils-git.R` covering: pull fetch+merge, pull no-op, pull conflict abort, pull no remote, pull non-git dir, check up-to-date, check behind remote, check error message suggests tbit_pull, check no remote (passes), check no upstream (passes), check ahead (passes), check network error tolerance, check non-git dir.
- Existing mock-based tests in `test-sync.R` (7 blocks) and `test-read-write.R` (7 blocks) updated to stub the new functions.

**Ready for Chunk 3**: tbit_pull() export

**Chunk 3: tbit_pull() — COMPLETE** (962 tests, 0 failures)

Implementation summary:
- `tbit_pull(conn)` exported in `R/sync.R`: validates conn (developer role, has path), records HEAD SHA before pull, calls `.tbit_git_pull()`, counts commits merged via `git2r::ahead_behind()`, then refreshes local `.tbit/manifest.json` from S3.
- Manifest refresh: checks `.tbit_s3_exists()` first, reads S3 manifest, compares JSON representation with local, overwrites local only when different. Creates `.tbit/` dir if needed.
- Returns invisible list: `commits_pulled` (integer), `branch` (string), `manifest` (`"refreshed"`, `"unchanged"`, or `"s3_unavailable"`).
- S3 connectivity errors are caught and surfaced as warnings — git pull still succeeds.
- 10 new tests in `test-sync.R`: rejects non-conn/reader/no-path, nothing to pull (0 commits), counts 2 upstream commits, manifest refreshed when different, manifest unchanged when identical, S3 error → `"s3_unavailable"`, merge conflict abort, invisible return, creates .tbit dir from scratch.

**Ready for Chunk 4**: Team Collaboration Vignette

**Chunk 4: Team Collaboration Vignette — COMPLETE** (962 tests, 0 failures)

Implementation summary:
- `vignettes/team-collaboration.Rmd` created with `eval = FALSE` (no live S3/git in vignette builds).
- Sections: Overview, Roles, One-Time Setup (init + S3 namespace safety), Joining (clone + connect), Daily Workflow (pull → receive → sync → validate), Handling Conflicts (push rejected + merge conflict resolution), Setting Up Readers (S3-only access), Credential Management (env var naming convention, multiple projects), Recommended Team Practices (5 tips), Summary table.
- `tbit_pull` added to pkgdown reference under Sync Operations.
- Renders without errors via `rmarkdown::render()`.

**Phase 7 is complete.** All 4 chunks landed. 962 tests, 0 failures.

---

## Deferred (Out of Scope for Phase 7)

| Item | Reason |
|------|--------|
| S3-level locking (object locks, DynamoDB) | Overkill for team sizes tbit targets; git is the authority |
| Automatic merge conflict resolution | Too risky to automate; make conflicts visible, not invisible |
| Multi-project credentials validation (cross-contamination) | Credential isolation is an AWS IAM concern, not tbit's |
| Real-time collaboration (concurrent session detection) | Out of scope for v1 |

---

## Notes / Learnings

- The pull-before-push pattern emerged from a real session where a reader
  connection used a mismatched prefix, leading to a 403 that looked like a
  permissions error. The root cause was stale local state. Enforcing pull at
  sync entry is the structural fix.
- Namespace collision risk was identified when debugging the vignette's reader
  workflow — the user used `clinical-data-bucket` (placeholder) instead of
  their real bucket. `tbit_init_repo()` having no S3 safety check means a
  typo in the bucket/prefix could silently overwrite another team's S3 metadata.
