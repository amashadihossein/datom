# DRAFT: datomanager Phase 19 -- gov_migrate_data()

**Status**: Draft -- not yet activated. datom Phase 22 (prerequisite) complete 2026-06-10.
**Supersedes**: `draft_phase_19_managed_migration.md` and
`draft_phase_19_managed_migration_updated.md` (both deleted).
**Captured**: 2026-05-02 (during Phase 18). Package boundary clarified 2026-06-02.
Consolidated 2026-06-01. datom Phase 22 complete 2026-06-10.

---

## What this document is

The spec for `gov_migrate_data()` in datomanager. datom Phase 22 (storage extension
API prerequisite) shipped 2026-06-10 -- six `datom_storage_*` / `datom_repo_*` exports
are now the stable platform surface Phase 19 calls into. The remaining prerequisite is
the datomanager package scaffold (see Prerequisites below).

---

## Goal

Replace today's manual migration workflow (external `aws s3 sync` +
`datom_sync_dispatch()`) with a single managed entry point:
`gov_migrate_data(conn, new_data_store, ...)`. The function performs an atomic
data-copy + `ref.json` update + migration-history record in one operation, with
rollback on pre-switch failure.

---

## Why the split (platform vs governance)

The two-package split is not packaging hygiene -- it falls on a real seam between
mechanism and policy.

- **datom = the platform layer.** It provides primitive, composable capabilities any
  data developer can invoke: write a table, read a version, and -- added in Phase 22 --
  **move bytes between stores**. Copying objects from one backend to another is a
  platform primitive. It is policy-free.

- **datomanager = the governance layer.** It turns a raw byte-copy into an *official
  event*: it rewrites the authoritative address (`ref.json`), records the move in
  `migration_history.json`, and commits both to the governed history that all org
  readers resolve against. "This is now the canonical location" is a governance decision,
  not a platform primitive.

The seam: **moving bytes is a platform primitive; declaring the new location
authoritative is governed.** Phase 22 gave the platform the muscle; Phase 19 gives
governance the decision. datomanager orchestrates datom; datom never knows datomanager
exists.

```
gov_migrate_data()  (datomanager, governance)   ->  datom helper called
  1. precondition checks                             (datom_storage_list as probe)
  2. plan                                            datom_storage_list()
  3. copy                                            datom_storage_copy()
  4. verify                                          datom_storage_verify()
  5. SWITCH ref.json        [GOV_SEAM]               (none -- pure gov write)
  6. record migration       [GOV_SEAM]               (none -- pure gov write)
  7. update project.yaml                             datom_repo_set_data_store()
  8. delete source (opt)                             datom_storage_delete_prefix()
```

(`datom_repo_delete()` is NOT used by migration -- it belongs only to decommission. The
two `[GOV_SEAM]` steps are pure gov writes with no datom call; that is the seam.)

Dependency direction is one-way: datomanager Imports datom. No `:::` anywhere -- every
cross-package call goes through an exported `datom::datom_*()` symbol.

---

## Locked decisions (from Phase 18, do not relitigate)

1. **Migration requires gov.** Hard precondition in `gov_migrate_data()`:
   `is.null(conn$gov_root)` -> abort with "attach gov first via `gov_attach()`".
   A migration without governance has no authoritative address to switch. Decided
   2026-05-02.
2. **No sidecar redirect.** Pre-gov projects do not migrate via env-var or MOVED-file
   machinery. They attach gov first. The resolver stays simple. Decided 2026-05-02.
3. **Core split accepted.** datom owns `datom_storage_*` / `datom_repo_*` mechanics;
   datomanager owns the governed `gov_migrate_data()` verb. Confirmed 2026-06-01.
4. **Data-repo write stays datom-owned.** The step-7 rewrite of `project.yaml`'s
   `storage.data` block is a *data-repo* git operation. It is owned by a datom-exported
   helper (`datom_repo_set_data_store()`), which datomanager calls. datomanager never
   touches the data repo directly -- this preserves the two-repos invariant (gov code
   commits only to the gov clone; data-repo writes go through datom). Confirmed
   2026-06-01.
5. **Prefix = package** (decided 2026-06-09). `datom_*` = datom (platform, all reads,
   solo-project self-serve writes); `gov_*` = datomanager (governed lifecycle writes);
   `access_*` = datomanager (future). No symbol is exported by two packages, so there is
   no R namespace masking and no per-verb gov-state branching -- the prefix carries the
   authority model. gov **reads** stay `datom_*`. Full rule + rename map in
   `dev/datomanager_scope.md` ("Naming Convention" + "Authority Principle").
6. **Data-repo-helper rule is uniform, not migration-only** (decided 2026-06-09). Every
   data-repo mutation datomanager needs goes through a datom-owned `datom_repo_*` helper.
   This covers decommission too: `datom_decommission()` does not move wholesale --
   `datom_repo_delete()` (delete GitHub repo + clone) stays in datom and is the complete
   solo-project teardown; `gov_decommission()` orchestrates it. See
   `dev/datomanager_scope.md`.

---

# datomanager Phase 19: gov_migrate_data()

## Function shape

```r
# datomanager -- the governed migration verb.
# Orchestrates by calling datom::datom_storage_*() and datom::datom_repo_set_data_store().
gov_migrate_data(
  conn,
  new_data_store,         # datom_store_s3 / datom_store_local component
  reason = NULL,          # human-readable note for migration_history.json
  dry_run = FALSE,        # plan + estimate without copying
  verify = TRUE,          # post-copy verification (structural by default)
  delete_source = FALSE,  # irreversible; only after verify passes
  ...
)
```

Single call with `dry_run`, not a two-call `plan()`/`execute()` -- follows the
`terraform plan` pattern but stays one function.

## The eight steps (and who owns each)

1. **Precondition checks** [datomanager]: gov attached (`!is.null(conn$gov_root)`); conn
   is developer; ref + project.yaml in sync (`datom::.datom_check_ref_current()` -- already
   exported? if not, promote in Phase 22); `new_data_store` reachable (probe via
   `datom::datom_storage_list()` on a conn built against it); namespace at new location is
   free; new store != current (else no-op with message).
2. **Plan** [datomanager orchestrates; `datom::datom_storage_list()` provides objects]:
   enumerate objects under current data location; estimate bytes; report. Stop here if
   `dry_run = TRUE`.
3. **Copy** [`datom::datom_storage_copy()`]: stream objects old -> new. On failure:
   rollback via `datom::datom_storage_delete_prefix()` on the new location.
4. **Verify** [`datom::datom_storage_verify()`]: structural by default; content via the
   `mode` argument threaded from a datomanager-level option. Fail -> rollback as in step 3.
5. **Switch** [datomanager, GOV_SEAM] -- **commit point**: write new `ref.json` at gov
   (`projects/{name}/ref.json`); commit + push gov repo; mirror to gov storage. From here,
   all readers resolve to the new location.
6. **Record** [datomanager, GOV_SEAM]: append to `projects/{name}/migration_history.json`
   via `.datom_gov_record_migration()`. Commit + push gov repo.
7. **Update local** [`datom::datom_repo_set_data_store()`]: rewrite `project.yaml`'s
   `storage.data` block on the **data** clone; commit + push the data repo. datomanager
   does not touch the data repo itself -- it calls the datom helper.
8. **(Optional) Delete source** [`datom::datom_storage_delete_prefix()`]: only if
   `delete_source = TRUE` and verify passed; irreversible.

## Atomicity story

- Steps 1-4 are read-only against the **old** store; rollback is trivial (delete partial
  new-location objects).
- Step 5 (gov ref switch) is the commit point. Once gov is updated, readers resolve to the
  new location; stale code redirects cleanly through `ref.json`.
- Steps 6-7 are best-effort cleanup. If they fail, the project *is* migrated but the local
  clone / migration history is stale; recovery is `gov_pull()` +
  `gov_sync_dispatch()` (gov) and `datom_pull()` (data).
- Step 8 is irreversible; only after explicit opt-in.

## Failure modes to design for

- Partial copy failure mid-stream: rollback by deleting copied objects at new location.
- Gov ref switch succeeds but push verify fails: project is migrated; user recovers via
  `gov_sync_dispatch()`.
- Concurrent migration (two developers): gov-side optimistic locking via
  `migration_history.json` last-entry pre-check + push-with-fail-on-conflict.
- New store == current store: no-op with informative message (caught in step 1).
- Step 7 fails after step 5/6 succeed: gov is authoritative and correct; data repo's
  `project.yaml` is stale. `.datom_resolve_data_location()` already auto-pulls + re-reads
  on developer mismatch, so this self-heals on next conn; document it.

## migration_history.json schema

Gov already has the file. Phase 19 appends entries:

```json
{
  "timestamp": "2026-05-02T14:23:00Z",
  "actor": {"github_login": "...", "git_email": "..."},
  "from": {"type": "local", "root": "/old/path", "prefix": "..."},
  "to":   {"type": "s3",    "root": "new-bucket", "prefix": "...", "region": "..."},
  "reason": "promote to S3 for team collab",
  "objects_copied": 1234,
  "bytes_copied": 5678901234,
  "verified": true,
  "verify_mode": "structural"
}
```

(`verify_mode` added vs the old draft so the audit record states which verification depth
ran.)

## Non-goals for Phase 19

- Gov-store migration (the `storage.governance` location). Out of scope; gov is sticky
  once attached.
- Multi-project bulk migration. One project per call.
- Concurrent live migration with active writes. Document a "freeze writes" advisory step.

## Phase 19 acceptance criteria

1. `gov_migrate_data()` exported from **datomanager**, marked `# GOV_SEAM:` where it
   performs gov writes (steps 5-6).
2. datomanager calls datom only via `datom::datom_storage_*()` /
   `datom::datom_repo_set_data_store()` -- no `:::`.
3. datom Phase 22 complete (six functions exported, signatures documented in the datom
   spec).
4. Atomic semantics: pre-switch failure leaves no trace; post-switch failure documented +
   self-healing path verified.
5. Cross-backend matrix tested (at minimum local->s3 and s3->local).
6. `migration_history.json` entries written and verified.
7. Reader role detects new location after `gov_pull()`.
8. Vignette: "Migrating between stores" article.
9. E2E sandbox supports a migration leg.

---

## Prerequisites before this phase activates

1. ~~**datom Phase 22**~~: complete 2026-06-10. Six `datom_storage_*` / `datom_repo_*`
   exports with stable, documented signatures are in `main`.
2. **datomanager repository** must exist (even as a skeleton) so Phase 19 can be
   developed there. Per `dev/datomanager_scope.md`, the lift-out renames the 5 exported
   gov functions to `gov_*` (extracting `datom_repo_delete()` to stay in datom) and moves
   the 9 GOV_SEAM helpers (~2 days) before Phase 19's full scope.

## Open questions (decide at activation)

- Does datomanager's step-1 precondition need a thin exported probe from datom, or can
  it call `.datom_check_ref_current()` directly? Lean: add a narrow exported probe rather
  than exposing the internal guard.
- In-flight reader conns after switch: today's stale-conn behavior covers it (read-time
  check fails clean, user rebuilds). Confirm no extra work needed.

## Notes

Consolidates: Phase 18 design discussion (2026-05-02), package-boundary clarification
(2026-06-02), platform/governance framing + numbering fix (2026-06-01), `gov_*` prefix
decision + uniform data-repo-helper rule / decommission split (2026-06-09), datom Phase 22
completion (2026-06-10).
When activated, expand into a full chunked plan via the standard phase workflow.
