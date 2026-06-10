# DRAFT: Managed Data Migration (datom Phase 22 + datomanager Phase 19)

**Status**: Draft -- not yet activated. Consolidated 2026-06-01.
**Supersedes**: `draft_phase_19_managed_migration.md` and
`draft_phase_19_managed_migration_updated.md` (both deleted).
**Captured**: 2026-05-02 (during Phase 18). Package boundary clarified 2026-06-02.
Consolidated and renumbered 2026-06-01.

---

## What this document is

A single source of truth for the managed-migration capability, which spans **two
packages** and therefore **two phases**:

| Phase | Package | Deliverable |
|-------|---------|-------------|
| **Phase 22** | datom | Storage extension API (`datom_storage_*`, `datom_repo_*`) -- the byte-moving + data-repo mechanics, exported and CRAN-stable. Prerequisite for Phase 19. |
| **Phase 19** | datomanager | The governed verb `gov_migrate_data()` -- orchestrates the mechanics and owns the ref switch + migration record. |

> **Numbering note**: datom Phase 21 (Governance-First Connection UX) already shipped
> 2026-05-29. The datom-side prerequisite here is **Phase 22**, not 21. The earlier
> `_updated` draft mislabeled it Phase 21; that is corrected throughout.

Build order: datom Phase 22 first (export the mechanics), then datomanager Phase 19
(build the verb on top). They are developed at different times, in different packages,
but kept in one doc while datomanager is still co-resident in this repo. Split when
datomanager spins out.

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
  data developer can invoke: write a table, read a version, and -- new in Phase 22 --
  **move bytes between stores**. Copying objects from one backend to another is a
  platform primitive. It is policy-free.

- **datomanager = the governance layer.** It turns a raw byte-copy into an *official
  event*: it rewrites the authoritative address (`ref.json`), records the move in
  `migration_history.json`, and commits both to the governed history that all org
  readers resolve against. "This is now the canonical location" is a governance decision,
  not a platform primitive.

The seam: **moving bytes is a platform primitive; declaring the new location
authoritative is governed.** Phase 22 gives the platform the muscle; Phase 19 gives
governance the decision. datomanager orchestrates datom; datom never knows datomanager
exists.

```
datom (platform)                     datomanager (governance)
  datom_storage_copy()      <-------  gov_migrate_data()
  datom_storage_verify()    <-------    1. precondition checks
  datom_storage_list()      <-------    2. plan
  datom_storage_delete_prefix() <----   3. copy      (calls datom)
  datom_repo_set_data_store() <------    4. verify    (calls datom)
  datom_repo_delete()         <------    5. SWITCH ref.json   [GOV_SEAM]
   (used by gov_decommission,           6. record migration  [GOV_SEAM]
    not migration)                       7. update project.yaml (calls datom)
                                         8. optional delete source (calls datom)
```

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
   no-gov self-serve writes); `gov_*` = datomanager (governed lifecycle writes);
   `access_*` = datomanager (future). No symbol is exported by two packages, so there is
   no R namespace masking and no per-verb gov-state branching -- the prefix carries the
   authority model. gov **reads** stay `datom_*`. Full rule + rename map in
   `dev/datomanager_scope.md` ("Naming Convention" + "Authority Principle").
6. **Data-repo-helper rule is uniform, not migration-only** (decided 2026-06-09). Every
   data-repo mutation datomanager needs goes through a datom-owned `datom_repo_*` helper.
   This covers decommission too: `datom_decommission()` does not move wholesale --
   `datom_repo_delete()` (delete GitHub repo + clone) stays in datom and is the complete
   no-gov teardown; `gov_decommission()` orchestrates it. See `dev/datomanager_scope.md`.

---

# Part A -- datom Phase 22: Storage Extension API

## Goal

Export a small, stable, CRAN-committed extension API that exposes datom's existing
storage-dispatch mechanics so a downstream governance package (datomanager) can move and
verify bytes without reaching into internals. Naming convention `datom_storage_*` /
`datom_repo_*` signals **infrastructure tier** -- intended for package developers, not
end users.

## Functions to export

Most of the mechanics already exist internally (the `.datom_storage_*` dispatch layer in
[R/utils-storage.R](R/utils-storage.R) routing to `.datom_s3_*` / `.datom_local_*`). The
genuinely new work is `copy` and `verify`; the rest is promotion + a documented public
signature.

| Function | New or promote | Purpose |
|---|---|---|
| `datom_storage_copy(from_conn, to_conn)` | **New** | Enumerate and stream all objects under the datom namespace from `from_conn` to `to_conn`, cross-backend. Returns a data frame / list of copied keys + byte sizes. |
| `datom_storage_verify(from_conn, to_conn, keys = NULL, mode = c("structural", "content"))` | **New** | Confirm a copy landed intact. See verify contract below. |
| `datom_storage_list(conn)` | Promote | Exported wrapper over `.datom_storage_list_objects()`. Returns full storage keys under the datom namespace. |
| `datom_storage_delete_prefix(conn)` | Promote | Exported wrapper over `.datom_storage_delete_prefix()`. Deletes all objects under the conn's datom namespace. Used for rollback and (opt-in) source deletion. |
| `datom_repo_set_data_store(conn, new_data_store, message = NULL)` | **New** | Rewrite `storage.data` in `project.yaml` on the data clone; commit + push the data repo. The data-side half of a migration's bookkeeping. Owned by datom so the two-repos invariant holds. |
| `datom_repo_delete(conn, confirm, force_gov_attached = FALSE)` | **New** | Delete the data GitHub repo + local clone. Extracted from `datom_decommission()`'s data-side steps. The complete no-gov teardown (paired with `datom_storage_delete_prefix()`); also the helper `gov_decommission()` calls. See guard note below. |

No user-facing *governed* migration verb lives in datom. These six are the entire Phase 22
surface.

## Verify contract (pin this before exporting)

datom already content-addresses every parquet object via `data_sha`. "Verify" therefore
has two distinct, legitimate meanings; the `mode` argument selects between them
explicitly rather than conflating "sample vs full":

- **`mode = "structural"` (default)**: For every key copied, confirm the destination
  object exists and its byte size matches the source. Cheap -- one `head`/stat per object,
  no byte transfer. Catches truncated/missing objects, which is the dominant copy failure
  mode. This is the default because it is fast and sufficient for almost all cases.
- **`mode = "content"`**: Re-read destination bytes, recompute the content hash, and
  compare against the source hash. Expensive (full re-download for remote backends) but
  gives true bit-level integrity. Opt-in for paranoid / regulated runs.

`keys = NULL` means "verify everything `datom_storage_copy()` reported". Passing an
explicit key vector verifies a subset (e.g. a sample). The old draft's
`mode = c("sample","full")` is **dropped** -- sampling is expressed by passing a subset
of `keys`, integrity depth is expressed by `mode`. Two orthogonal axes, two arguments.

## Cross-backend matrix (datom_storage_copy)

| from | to | Mechanism |
|------|----|-----------|
| local | local | `fs::file_copy()` per object. |
| local | s3 | Stream via paws `put_object`. |
| s3 | local | Stream via paws `get_object` + write. |
| s3 | s3 | `copy_object` when same region/credentials; otherwise stream through. |

All routing stays inside datom's existing `switch(conn$backend, ...)` dispatch; no new
backend abstraction is introduced.

## No-gov vs gov: the authority principle (reframe, not a warning)

The earlier draft framed `datom_storage_copy()` as a footgun for solo devs ("copy succeeds,
conn still points at the old location -- label it loudly"). That framing was wrong: the fix
is already in the API. The governing question is **which file is the location authority**:

- **No-gov project -- `project.yaml` is authority.** There is no `ref.json`. So
  `datom_storage_copy()` + `datom_repo_set_data_store()` together are a *complete*,
  legitimate self-relocation -- not a half-migration. The second primitive closes the loop.
  Likewise `datom_storage_delete_prefix()` + `datom_repo_delete()` is a *complete* teardown.
  Both are fully within datom; no governance is involved because there is none to involve.
- **Gov-attached project -- `ref.json` is authority.** A copy alone is genuinely
  incomplete, because the authoritative address lives in gov. You **must** go through
  `datomanager::gov_migrate_data()` (or `gov_decommission()`), which switches `ref.json`
  and records history.

The Phase 18 lock is on the *governed verb*, not on a solo dev relocating their own bytes.
So we do not gate `datom_storage_copy()` on gov -- gating belongs in the governed verb. The
only residual sharp edge is a gov user calling `datom_repo_delete()` directly (deletes the
data side, orphans the gov registration). Because that helper is also what
`gov_decommission()` calls, it cannot simply refuse on gov-attached conns; instead it
carries `confirm = project_name` **plus** `force_gov_attached = FALSE`. An interactive gov
user is stopped with "use `gov_decommission()`"; datomanager opts through visibly by passing
`TRUE`. Explicit parameter, not hidden behavior.

> **Convenience-wrapper question (open).** `datom_relocate_data()` -- a one-call wrapper
> over `copy` + `set_data_store` for the no-gov case -- is *reserved vocabulary*, not
> necessarily shipped in Phase 22. Lean: ship the two primitives; add the wrapper only if
> the two-call dance proves annoying. The naming principle is what matters now.

## Phase 22 acceptance criteria

1. Six functions exported with documented, stable signatures, listed in `_pkgdown.yml`.
2. `datom_storage_copy()` passes the cross-backend matrix (at minimum local->s3 and
   s3->local with mocked paws; local->local real).
3. `datom_storage_verify()` both modes tested; `structural` catches a truncated object,
   `content` catches a corrupted-bytes object.
4. `datom_repo_set_data_store()` rewrites only `storage.data`, leaves
   `storage.governance` untouched, commits to the data clone only.
5. `datom_repo_delete()` removes GitHub repo + clone; refuses a gov-attached conn unless
   `force_gov_attached = TRUE`; `confirm` interlock enforced.
6. Spec updated: new "Storage extension API" section documenting the six signatures and
   the verify contract.
7. No `:::`-reachability requirement leaks; every function is a clean export.
8. Full test suite green; count reported in commit.

---

# Part B -- datomanager Phase 19: gov_migrate_data()

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

## Prerequisites before either phase activates

1. **datom Phase 22** must ship first: the six `datom_storage_*` / `datom_repo_*`
   functions exported with stable, documented signatures.
2. **datomanager repository** must exist (even as a skeleton) so Phase 19 can be
   developed there. Per `dev/datomanager_scope.md`, the lift-out renames the 5 exported
   gov functions to `gov_*` (extracting `datom_repo_delete()` to stay in datom) and moves
   the 9 GOV_SEAM helpers (~2 days) before Phase 19's full scope.

## Open questions (decide at activation)

- Is `.datom_check_ref_current()` already export-worthy, or does Phase 22 add a thin
  public probe for datomanager's step-1 precondition? Lean: add a narrow exported probe
  rather than exposing the internal guard directly.
- Final name for the data-repo helper: `datom_repo_set_data_store()` vs
  `datom_repo_update_data_pointer()`. Lean: `datom_repo_set_data_store()` (mirrors store
  vocabulary).
- Ship `datom_relocate_data()` (no-gov one-call relocate wrapper) in Phase 22, or just
  reserve the name and ship the `copy` + `set_data_store` primitives? Lean: reserve the
  vocabulary, ship primitives; add the wrapper only if the two-call dance proves annoying.
- In-flight reader conns after switch: today's stale-conn behavior covers it (read-time
  check fails clean, user rebuilds). Confirm no extra work needed.

## Notes

This consolidates the Phase 18 design discussion (2026-05-02), the package-boundary
clarification (2026-06-02), the platform/governance framing + numbering fix (2026-06-01),
and the `gov_*` prefix decision + uniform data-repo-helper rule / decommission split
(2026-06-09).
When activated, expand each part into a full chunked plan via the standard phase
workflow.
