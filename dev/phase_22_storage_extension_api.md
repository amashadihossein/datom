# Phase 22 — Storage Extension API

**Status**: ⏳ Chunk 4 next
**Branch**: `phase/22-storage-extension-api`
**Started**: 2026-06-10

---

## Goal

Export a small, stable, CRAN-committed extension API that exposes datom's existing
storage-dispatch mechanics so a downstream governance package (datomanager) can move
and verify bytes without reaching into internals. Naming convention `datom_storage_*` /
`datom_repo_*` signals infrastructure tier -- intended for package developers, not
end users.

Prerequisite for datomanager Phase 19 (`gov_migrate_data()`).

---

## Context

Spec: `dev/draft_managed_migration.md` Part A.
Authority principle: `dev/datomanager_scope.md`.
Key files to touch: `R/utils-storage.R`, `R/decommission.R`, `R/conn.R` (project.yaml write).
New file: `R/storage.R` (the six exported functions).

---

## Read Before Each Chunk

- `R/utils-storage.R` — dispatch layer (source of promotions)
- `R/utils-s3.R` — `head_object`, `get_object`, `put_object` patterns
- `R/utils-local.R` — `.datom_local_path()`, `fs::file_copy` patterns
- `R/decommission.R` — steps 2-3 to extract for `datom_repo_delete()`
- `R/conn.R` — `new_datom_conn()` fields, project.yaml write patterns

---

## Six Exports

| Function | Status | Source |
|---|---|---|
| `datom_storage_list(conn, ...)` | ✅ done | Promote `.datom_storage_list_objects()` |
| `datom_storage_delete_prefix(conn, ...)` | ✅ done | Promote `.datom_storage_delete_prefix()` |
| `datom_storage_copy(from_conn, to_conn, ...)` | ✅ done | New |
| `datom_storage_verify(from_conn, to_conn, keys, mode)` | ✅ done | New |
| `datom_repo_set_data_store(conn, new_store, ...)` | ☐ todo | New |
| `datom_repo_delete(conn, confirm, force_gov_attached)` | ☐ todo | Extract from decommission.R |

---

## Chunks

| # | Name | Status | Notes |
|---|------|--------|-------|
| 0 | Phase doc + branch setup | ✅ done | Phase doc created, README.md updated, branch pushed |
| 1 | Promote list + delete_prefix | ✅ done | R/storage.R, 26 tests, pkgdown entry |
| 2 | `datom_storage_copy()` | ✅ done | All 4 backend combos; tests with mocked S3 |
| 3 | `datom_storage_verify()` | ✅ done | `structural` + `content` modes; truncation + hash tests |
| 4 | `datom_repo_set_data_store()` | ⏳ next | Read-modify-write; govenance untouched; commit+push |
| 5 | `datom_repo_delete()` | ☐ todo | Extract from decommission.R; guard; refactor decommission |
| 6 | Spec + phase completion | ☐ todo | Update spec, acceptance criteria, phase completion procedure |

---

## Signatures (pinned)

```r
# Chunk 1 -- promotions
datom_storage_list(conn)
datom_storage_delete_prefix(conn, prefix_key = NULL)

# Chunk 2 -- copy
datom_storage_copy(from_conn, to_conn)

# Chunk 3 -- verify
datom_storage_verify(from_conn, to_conn, keys = NULL, mode = c("structural", "content"))

# Chunk 4 -- repo set data store
datom_repo_set_data_store(conn, new_store, message = NULL)

# Chunk 5 -- repo delete
datom_repo_delete(conn, confirm, force_gov_attached = FALSE)
```

---

## Locked Decisions (do not re-open)

1. `datom_storage_copy` -- both args are full `datom_conn` objects. Streaming for all
   4 combos: `local->local` via `fs::file_copy`; others read bytes then write.
   Server-side S3 `copy_object` (same-region S3->S3) is issue #46 -- out of scope.
2. `datom_storage_verify` -- `mode = c("structural", "content")`. Structural = existence
   + byte size (cheap). Content = re-hash bytes (expensive). `keys = NULL` means verify
   all from `datom_storage_list()`.
3. `datom_repo_delete` -- refuses if `is_gov_attached(conn) && !force_gov_attached`.
   Gov user is stopped with "use `gov_decommission()`"; datomanager opts through with
   `force_gov_attached = TRUE`. No hidden behavior.
4. `datom_repo_set_data_store` -- **read-modify-write** on `project.yaml`. Must call
   `yaml::read_yaml()`, `modifyList()` on only `storage.data`, then write back. Never
   reconstruct from conn fields (silently drops `storage.governance` on governed
   projects).

---

## Invariants / Must-Never Rules

- Never call `.datom_s3_*()` or `.datom_local_*()` from the new exported functions;
  always go through `.datom_storage_*()` dispatch.
- `datom_repo_set_data_store()` must not touch `storage.governance`. Verify with a
  regression test that `storage.governance` survives a round-trip.
- `datom_repo_delete()` must NOT replace `datom_decommission()` -- decommission calls
  it as a sub-step. Never remove decommission.
- cli dot-literal gotcha: wrap any `.`-prefixed call in parens inside cli_* calls:
  `{(.datom_build_storage_key(...))}`.
- No phase/chunk numbers in `R/` source comments.

---

## Acceptance Criteria

1. Six functions exported with documented, stable signatures, listed in `_pkgdown.yml`.
2. `datom_storage_copy()` passes the cross-backend matrix (at minimum local->s3 and
   s3->local with mocked paws; local->local real).
3. `datom_storage_verify()` both modes tested; `structural` catches a truncated object,
   `content` catches a corrupted-bytes object.
4. `datom_repo_set_data_store()` rewrites only `storage.data`, leaves
   `storage.governance` untouched, commits to the data clone only.
5. `datom_repo_delete()` removes GitHub repo + clone; refuses a gov-attached conn unless
   `force_gov_attached = TRUE`; `confirm` interlock enforced.
6. Spec updated: new "Storage extension API" section.
7. No `:::`-reachability; every function is a clean export.
8. Full test suite green; count reported in commit.

---

## Progress Log

### Chunk 0 -- 2026-06-10
Shipped: Phase doc created, branch `phase/22-storage-extension-api` created from `main`,
`dev/README.md` Active Phases table updated.
Decisions: None new; all locked decisions carried from pre-session prompt.
Tests: 1763 (baseline before chunk 1; includes prior issue #27 fix that added tests).

### Chunk 1 -- 2026-06-10
Shipped: `datom_storage_list()` + `datom_storage_delete_prefix()` in `R/storage.R`.
26 tests in `tests/testthat/test-storage.R` (S3 mocked via mockery, local real tempdir).
`_pkgdown.yml` new "Storage Extension API" section. NAMESPACE + man pages regenerated.
Decisions: Internal `.datom_storage_list_objects()` and `.datom_storage_delete_prefix()`
retained unchanged -- wrappers delegate to them. Return-value gotcha noted: local backend
returns `1L` (dir removed) not object count; docstring updated to reflect this.
Tests: 1763 (26 new storage tests; full suite 0 fail, 26 pre-existing warnings in test-conn.R).

### Chunk 2 -- 2026-06-10
Shipped: `datom_storage_copy(from_conn, to_conn)` in `R/storage.R`.
Two private helpers added to same file: `.datom_storage_rel_key()` (strips namespace prefix
from full keys returned by list) and `.datom_copy_one()` (dispatches on from/to backend pair).
41 new tests (67 storage total) covering all 4 backend combos: local->local real tempdir,
local->s3 mocked put_object, s3->local mocked get_object, s3->s3 both mocked. Verified
rel-key stripping, correct full-key construction at destination, byte count in return df.
Decisions: Fail-fast on individual object error (no partial-result accumulation); rollback
orchestration is Phase 19 concern. Return df visible (not invisible) since caller feeds
it to datom_storage_verify(). Static-analysis lint false positives on cli-interpolated
variables are harmless -- code is correct.
Tests: 1804 (0 fail, 26 pre-existing warnings).

### Chunk 3 -- 2026-06-10
Shipped: `datom_storage_verify(from_conn, to_conn, keys, mode)` in `R/storage.R`.
Three private helpers: `.datom_storage_byte_size()` (HEAD/stat), `.datom_storage_content_hash()`
(get_object+digest / digest file), `.datom_verify_one()` (per-key check, returns ok+issue).
44 new tests (111 storage total). Key coverage: structural catches size mismatch + missing
destination; content catches corrupted bytes; S3 mocked for both modes; keys=NULL lists
from from_conn; subset keys; correct column types (key/ok/issue).
Decisions: Destination missing/inaccessible is ok=FALSE (not hard error), enables bulk-verify
with partial failures visible in result df. Source missing is a hard error (always expected
to exist). `issue` column uses NA_character_ for passing objects.
`_pkgdown.yml` updated with verify entry.
Tests: 1848 (0 fail, 26 pre-existing warnings).
