# Phase 19 (DRAFT): Managed Data Migration

**Status**: Draft -- not yet activated
**Depends on**: Phase 18 (gov-on-demand) closed
**Captured**: 2026-05-02 (during Phase 18)

---

## Goal

Replace today's manual migration workflow (external `aws s3 sync` + `datom_sync_dispatch()`) with a single managed entry point: `datom_migrate_data(conn, new_data_store, ...)`. The function performs an atomic data-copy + `ref.json` update + `.datom_gov_record_migration()` invocation in one operation, with rollback on failure.

---

## Locked from Phase 18

1. **Migration requires gov.** Hard precondition: `is.null(conn$gov_root)` -> abort with "attach gov first via `datom_attach_gov()`". Decided 2026-05-02.
2. **No sidecar redirect.** Pre-gov projects do not migrate via env-var or MOVED-file machinery. They attach gov first. The resolver stays simple. Decided 2026-05-02.

---

## Core Elements (to elaborate when activated)

### Function shape

```r
datom_migrate_data(
  conn,
  new_data_store,         # datom_store_s3 or datom_store_local component
  reason = NULL,          # human-readable note for migration_history.json
  dry_run = FALSE,        # plan + estimate without copying
  verify = TRUE,          # post-copy SHA verification
  ...
)
```

### Phases of the operation

1. **Precondition checks**: gov attached, conn is developer, ref + project.yaml in sync, new_data_store reachable, namespace at new location is free.
2. **Plan**: enumerate objects under current data location; estimate bytes; report.
3. **Copy**: stream objects from old to new store via the storage abstraction (cross-backend supported: S3->S3, S3->local, local->S3, local->local).
4. **Verify** (if `verify = TRUE`): list new location, cross-check object count + sample SHA.
5. **Switch**: write new `ref.json` at gov (`projects/{name}/ref.json`); commit + push gov repo; mirror to gov storage.
6. **Record**: append to `projects/{name}/migration_history.json` via `.datom_gov_record_migration()` (already exists). Commit + push.
7. **Update local**: rewrite `project.yaml`'s `storage.data` block in the data clone; commit + push the data repo.
8. **(Optional) Delete old data**: separate flag `delete_source = FALSE` default. When TRUE and verify passed, delete old location's namespace.

### Atomicity story

- Steps 1-4 are read-only against the old store; rollback is trivial (delete partial new-location objects).
- Step 5 (gov ref switch) is the commit point. Once gov is updated, readers will resolve to the new location.
- Steps 6-7 are best-effort cleanup. If they fail, the project is migrated but the local clone / migration history is stale; recovery is `datom_pull_gov()` + `datom_sync_dispatch()`.
- Step 8 is irreversible; only run after explicit user opt-in.

### Failure modes to design for

- Partial copy failure mid-stream: rollback by deleting copied objects at new location.
- Gov ref switch succeeds but verify of step 5 push fails: project is migrated; user must `datom_sync_dispatch()` to recover gov state.
- Concurrent migration attempt (two developers): gov-side optimistic locking via `migration_history.json` last-entry pre-check + push-with-fail-on-conflict.
- New data store is the same as current: no-op with informative message.

### `migration_history.json` schema

Today's gov already has the file. Phase 19 adds entries with:

```json
{
  "timestamp": "2026-05-02T14:23:00Z",
  "actor": {"github_login": "...", "git_email": "..."},
  "from": {"type": "local", "root": "/old/path", "prefix": "..."},
  "to":   {"type": "s3",    "root": "new-bucket", "prefix": "...", "region": "..."},
  "reason": "promote to S3 for team collab",
  "objects_copied": 1234,
  "bytes_copied": 5678901234,
  "verified": true
}
```

### Cross-backend matrix

| from | to | Notes |
|------|----|-------|
| local | local | `fs::file_copy()` per object; trivial. |
| local | s3 | Stream via paws `put_object`. |
| s3 | local | Stream via paws `get_object` + write. |
| s3 | s3 | `copy_object` when same region/credentials; otherwise stream. |

### Non-goals for Phase 19

- Gov-store migration (the `storage.governance` location). Out of scope; gov is sticky once attached.
- Multi-project bulk migration. One project per call.
- Concurrent live migration with active writes. Document a "freeze writes" advisory step.

---

## Open Questions (decide at activation)

- Should `datom_migrate_data()` live in datom or the future companion package? Lean: companion (it's a gov-write surface; mark `# GOV_SEAM:`).
- Two-call API (`plan()` then `execute()`) vs single call with `dry_run`? Lean: single call, follow the `terraform plan` pattern but keep it one function.
- Verify mechanism: full SHA round-trip per object (slow, exhaustive) vs sampling (fast, probabilistic)? Lean: sample by default, full via flag.
- What happens to in-flight reader conns after switch? Today's stale-conn behavior covers this (read-time check fails clean, user rebuilds).

---

## Acceptance Criteria (for activation)

1. `datom_migrate_data()` exported, marked `# GOV_SEAM:`.
2. Atomic semantics: pre-switch failure leaves no trace; post-switch failure documented.
3. Cross-backend matrix tested (at minimum local->s3 and s3->local with mocked paws).
4. `migration_history.json` entries written and verified.
5. Reader role detects new location after `datom_pull_gov()`.
6. Vignette: "Migrating between stores" article.
7. E2E sandbox supports a migration leg.

---

## Notes

This draft preserves the design discussion held during Phase 18 (2026-05-02). When activated, expand into a full chunked plan via the standard phase workflow.
