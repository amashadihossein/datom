# Phase 13: Reader Ref Resolution

## Goal

Wire `.datom_resolve_ref()` into the **reader path** of `datom_get_conn()` so that S3-only readers can discover where data lives by reading `ref.json` from the governance store. Add actionable error messaging when governance resolves but the data store is unreachable (stale credentials after migration).

## Context

- Phases 11-12 built the two-store architecture (governance vs data) and the `ref.json` plumbing (`.datom_create_ref()`, `.datom_resolve_ref()`).
- Currently `.datom_resolve_ref()` is **defined and tested** but never called from any production code path. The reader connection (`_get_conn_reader`) hardcodes data location from the store object passed in.
- The dispatch.json `context` routing (TODO at `R/read_write.R:34`) is explicitly deferred by the spec: "will be added when downstream consumers exist." **Not in scope for this phase.**
- Backlog item "Stale data credentials error message" (medium priority) is unblocked by this work.

## Design

### Current reader flow
```
User passes store → _get_conn_reader(store, project_name) → conn uses store$data directly
```

### Target reader flow
```
User passes store → _get_conn_reader(store, project_name) → 
  1. Build gov_conn from store$governance
  2. .datom_resolve_ref(gov_conn) → get current data location (root, prefix, region)
  3. Cross-check: if store$data location ≠ ref location, warn (migration detected)
  4. Build data client using ref-resolved location + store$data credentials
  5. Validate data store reachable → actionable error if 403/unreachable
```

### Key decisions
- **Ref resolution is reader-only**: Developers have `project.yaml` in their local git repo — that's their source of truth. Only readers (no git) need ref.json.
- **Credentials still come from the store object**: ref.json tells you *where* the data is, not *how to authenticate*. The user's store$data credentials are used against the ref-resolved location.
- **Migration mismatch = warning, not error**: If the user's store$data points to the old bucket but ref.json says data moved, warn and use the ref location. The user's credentials may or may not work against the new location.
- **Local backend: no ref resolution**: ref.json is an S3/remote concern. Local backend readers skip ref resolution.

## Chunks

### Chunk 1: Wire ref resolution into reader path
- Modify `.datom_get_conn_reader()` to call `.datom_resolve_ref()` when `store$governance` is present and backend is `"s3"`
- Use ref-resolved `root`/`prefix`/`region` to override `store$data` location when building the conn
- Keep store$data credentials (access_key, secret_key, session_token)
- Emit `cli::cli_warn()` if ref location differs from store$data location

### Chunk 2: Data store reachability check
- After building conn with ref-resolved location, validate data store is reachable
- For S3: `HeadBucket` call on the resolved root
- On 403: actionable error message — "Governance says data is at {root}, but your credentials can't access it. Your store credentials may need updating after a migration."
- On network error: warning (offline use still allowed, will fail at read time)

### Chunk 3: Tests
- Unit tests for ref-resolved reader connections
- Test migration mismatch warning
- Test 403 actionable error (mocked)
- Test local backend skips ref resolution
- Test reader without governance store (legacy/no gov component) still works

### Chunk 4: Update TODO and backlog
- Remove the stale TODO at `R/read_write.R:34` — clarify it's deferred per spec
- Update backlog in `dev/README.md` — mark "Stale data credentials" as resolved
- Update spec if any design decisions changed

## Acceptance Criteria

- [ ] Reader-mode `datom_get_conn()` with S3 governance store resolves `ref.json` to find data location
- [ ] Migration mismatch (store$data ≠ ref) emits warning
- [ ] Unreachable data store (403) emits actionable error with migration context
- [ ] Local backend readers skip ref resolution
- [ ] Legacy readers (no governance component) still work unchanged
- [ ] All existing tests pass (count ≥ 1153)
- [ ] New tests for ref resolution in reader path
- [ ] E2E test passes

## Current State

| Chunk | Status |
|-------|--------|
| 1. Wire ref resolution | not started |
| 2. Reachability check | not started |
| 3. Tests | not started |
| 4. Update TODO/backlog | not started |
