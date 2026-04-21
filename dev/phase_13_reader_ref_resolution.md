# Phase 13: Conn-Time Ref Resolution

## Goal

Wire `.datom_resolve_ref()` into `datom_get_conn()` for **both readers and developers** so that every connection is ref-validated at creation time. Backend-neutral (S3 and local). Add a write-time ref guard to prevent orphaned data after migration. Add actionable error messaging when governance resolves but the data store is unreachable (stale credentials / missing directory after migration).

## Context

- Phases 11-12 built the two-store architecture (governance vs data) and the `ref.json` plumbing (`.datom_create_ref()`, `.datom_resolve_ref()`).
- Currently `.datom_resolve_ref()` is **defined and tested** but never called from any production code path. Both `_get_conn_reader` and `_get_conn_developer` hardcode data location from the store object passed in.
- The dispatch.json `context` routing (TODO at `R/read_write.R:34`) is explicitly deferred by the spec: "will be added when downstream consumers exist." **Not in scope for this phase.**
- Backlog item "Stale data credentials error message" (medium priority) is unblocked by this work.

## Design

### Current flow (both roles)
```
User passes store → _get_conn_{reader,developer}(store, ...) → conn uses store$data directly
```

### Target flow
```
Conn time (both roles):
  1. If store$governance present → build gov_conn, call .datom_resolve_ref(gov_conn)
  2. Detect migration: store$data location ≠ ref location?
  3. If migrated + developer → auto-pull git, re-read project.yaml
     - project.yaml now matches ref → proceed (pull fixed it, info message)
     - still mismatched → error ("ref.json and project.yaml disagree after pull")
  4. Build data client using ref-resolved location + store$data credentials
  5. Validate data store reachable (HeadBucket / dir_exists)
     - Reachable + migrated (reader) → warn ("update your store config")
     - Unreachable + migrated → error ("credentials can't access new location")
     - Unreachable + not migrated → error ("data store unreachable")
  6. Return conn — ref-validated

Read time: no re-check (stale conn → clean error → user rebuilds conn)

Write time: re-resolve ref from gov, compare against conn$root
  - Match → proceed
  - Mismatch → error ("data location changed since conn was created, rebuild conn")
```

### Key decisions
- **Ref resolution at conn time, both roles**: The conn is born ref-validated. Developers already need the governance store for push, so this adds no new dependency.
- **Developer auto-pull on migration**: If ref ≠ project.yaml, auto-pull git to sync local state. Developer's local config stays consistent — no hidden overrides.
- **Reader warn on migration**: Readers have no git to pull. Warn and use ref address with their credentials. They update their store config to stop the warning.
- **Write-time ref guard**: Writes re-resolve ref and **hard-abort on any failure** (network, missing file, malformed — any reason). Writing without a verified location risks orphaning data — there is no safe fallback. Errors if the data location changed since conn creation.
- **Conn-time ref failure is warn-only**: Governance informs, it does not gate reads. If ref.json is unreadable at conn time, warn with details and proceed using store$data location. Data reachability is what gates access — not governance reachability.
- **No read-time check**: Stale reads fail cleanly (404/403) → user rebuilds conn → self-healing. No silent corruption risk.
- **Credentials still come from the store object**: ref.json tells you *where* the data is, not *how to authenticate*. The user's store$data credentials are used against the ref-resolved location. (For local backend, no credentials — just the path.)
- **Migration mismatch outcome depends on reachability**: If ref location ≠ store$data location, use the ref location with the user's existing credentials. If reachable → warn ("data migrated, update your store config"). If unreachable (403 / missing dir) → actionable error ("data migrated but your credentials can't access the new location").
- **Backend-neutral**: Ref resolution applies to both S3 and local backends. No special-casing by backend.
- **No governance = no ref check**: Legacy stores without a governance component skip ref resolution (backward compatible).

## Chunks

### Chunk 1: Wire ref resolution into conn path (both roles)
- Extract ref resolution into a shared helper (e.g., `.datom_resolve_data_location()`) called by both `_get_conn_reader` and `_get_conn_developer`
- When `store$governance` is present: call `.datom_resolve_ref()`, use ref-resolved `root`/`prefix`/`region` for data conn
- Keep store$data credentials (S3) or use ref-resolved path (local)
- Detect migration (store$data location ≠ ref location):
  - Developer: auto-pull git → re-read project.yaml → error if still mismatched
  - Reader: warn ("update your store config"), proceed with ref address

### Chunk 2: Data store reachability check
- After building conn with ref-resolved location, validate data store is reachable
- S3: `HeadBucket` on resolved root; 403 → actionable error ("credentials may need updating after migration")
- Local: `fs::dir_exists()` on resolved root; missing → actionable error ("data directory not found at ref-resolved path")
- On network error (S3): warning (offline use still allowed, will fail at read time)

### Chunk 3: Write-time ref guard
- In `datom_write()`, before writing data: re-resolve ref from `conn$gov_*` fields
- Compare ref root/prefix against `conn$root`/`conn$prefix`
- Mismatch → `cli::cli_abort("Data location changed since connection was created. Rebuild your connection with datom_get_conn().")`
- No gov fields on conn (legacy) → skip check
- Helper: `.datom_check_ref_current(conn)` — reusable if other write-like ops need it later

### Chunk 4: Tests
- Unit tests for ref-resolved connections — reader + developer, S3 + local
- Test developer migration mismatch → auto-pull syncs local state
- Test developer migration mismatch → error if project.yaml still disagrees after pull
- Test reader migration mismatch → warning (both backends)
- Test S3 403 actionable error (mocked)
- Test local missing-directory actionable error
- Test without governance store (legacy/no gov component) still works for both roles
- Test write-time ref guard: mismatch → error
- Test write-time ref guard: match → proceeds
- Test write-time ref guard: no gov → skips

### Chunk 5: Update TODO and backlog
- Remove the stale TODO at `R/read_write.R:34` — clarify it's deferred per spec
- Update backlog in `dev/README.md` — mark "Stale data credentials" as resolved
- Update spec if any design decisions changed

## Acceptance Criteria

- [x] `datom_get_conn()` resolves `ref.json` at conn time for both readers and developers (S3 and local)
- [x] Developer migration mismatch → auto-pull, proceed if project.yaml syncs, error if not
- [x] Reader migration mismatch + reachable → warning
- [x] Migration mismatch + unreachable → actionable error
- [x] Unreachable without migration → error
- [x] No governance component → skip ref resolution (backward compatible, both roles)
- [x] `datom_write()` re-checks ref before writing; errors on mismatch
- [x] Ref failure at write time → hard abort (any reason)
- [x] Ref failure at conn time → warn and proceed (governance informs, does not gate)
- [x] All existing tests pass (count ≥ 1153) — **1177 pass**
- [x] New tests for ref resolution, reachability, write-time guard

## Current State

| Chunk | Status |
|-------|--------|
| 1. Wire ref resolution (both roles) | complete |
| 2. Reachability check | complete |
| 3. Write-time ref guard | complete |
| 4. Tests | complete |
| 5. Update TODO/backlog | complete |
