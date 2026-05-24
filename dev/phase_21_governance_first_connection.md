# Phase 21: Governance-First Connection UX

**Status**: Planning complete; Chunk 1 next
**Started**: 2026-05-23
**Issue**: GitHub #24
**Branch**: `phase/21-governance-first-connection`

---

## Goal

Make connection setup reflect the project's governance state:

1. **Gov-attached project**: data location is resolved from governance (`projects/{project_name}/ref.json`). Users should not need, or be encouraged, to pass direct data bucket/path/prefix/region details. If they do, datom should guide them toward the governance-first path.
2. **No-gov project**: there is no governance source of truth, so direct data location details remain required.

The package UX should make the safe path the obvious path: if governance exists, go through governance; if governance does not exist, provide data location explicitly.

---

## Critical Evaluation of Issue #24

Issue #24 identifies a real design mismatch. The current reader flow requires `store$data` to be fully specified even when `ref.json` already stores the data backend and location. That undermines the governance-as-source-of-truth principle and makes migrations operationally noisy because readers must be re-notified of bucket/path changes.

The issue's proposed direction is directionally correct, but the implementation must be sharper than simply allowing `store$data = NULL` for readers:

- `ref.json` stores **location**, not credentials. The phase must preserve the secret-handling contract: no credentials in governance files, manifests, docs examples, or printed objects.
- Gov credentials and data credentials may be the same in simple deployments, but they are not guaranteed to be the same. The API needs an ergonomic default for shared credentials and a clear escape hatch for separate data credentials without exposing data location details.
- The rule should be project-state driven, not role-only. Developers of a gov-attached project should also be guided away from direct location inputs; no-gov developers and readers must still provide data location because no governance indirection exists.
- The existing `.datom_resolve_data_location()` helper currently validates or redirects a caller-supplied data store. Phase 21 should turn it into a bootstrap source when governance is attached, while preserving its write-time safety semantics.
- Backward compatibility is not a constraint, but user guidance is. Errors should say what shape to use next, not merely reject old arguments.

---

## Current State

Relevant code paths:

- `datom_store()` currently requires a `data` component and validates it as a full store component.
- `datom_get_conn()` branches into developer (`path + store`) and reader (`project_name + store`) flows.
- `.datom_get_conn_reader()` reads `ref.json` only after a full `store$data` exists.
- `.datom_get_conn_developer()` reads local `project.yaml`, cross-checks `store$data`, and only then resolves `ref.json`.
- `.datom_resolve_data_location()` returns ref location but compares it to `store$data`, so it cannot bootstrap when `store$data` is absent.
- Vignette `handing-off.Rmd` currently tells engineers to send data bucket / prefix / region to readers, which is the UX this phase intends to remove for gov-attached projects.

---

## Design Direction

### Location Source

Use a single invariant:

| Project state | Data location source | User-facing rule |
|---------------|----------------------|------------------|
| Gov attached | `ref.json` in governance | Do not pass data root/prefix/region; datom resolves them. |
| No gov | `store$data` | Pass data root/prefix/region explicitly. |

### Credential Source

Treat credentials separately from location:

1. If a gov-attached connection omits data credentials, datom may reuse governance storage credentials for the data client.
2. If the data store requires different credentials, users should provide a credentials-only data credential object or equivalent API surface that does **not** include root/prefix/region.
3. If data access fails after ref resolution, the error should say: governance resolved the location successfully, but the supplied credentials cannot access it.

The exact API shape is decided in Chunk 1, with a bias toward minimal surface area and avoiding a proliferation of constructors unless necessary.

### Error Guidance

Errors should teach the state model:

- Governance present + direct data location supplied: guide to the governance-first form.
- Governance absent + data location omitted: explain that no-gov projects require direct data location, or attach governance with `datom_attach_gov()`.
- Ref resolution fails for a gov-attached project: do not silently fall back to direct data location for writes or normal reader bootstrap; guide to governance connectivity / registration fixes.

---

## Invariants

1. Never persist or print secrets.
2. Never read data location for a gov-attached project from user-supplied direct coordinates when `ref.json` is available.
3. Never invent data location for a no-gov project; require explicit `store$data` location.
4. Keep write-time `.datom_check_ref_current()` hard-fail behavior.
5. Business logic continues to use `.datom_storage_*()` dispatch, not backend-specific helpers directly.
6. Preserve backend-neutral behavior for S3 and local stores.
7. Keep user-facing messages backend-aware and lookup-based, not S3-hardcoded.

---

## Chunks

| Chunk | Name | Scope | Tests | Status |
|-------|------|-------|-------|--------|
| 1 | Decide API shape | Read callers/tests, choose how `datom_store()` represents gov-resolved location plus optional data credentials; document rejected alternatives in this phase doc. | No code tests unless API spike is needed. | ⏳ next |
| 2 | Store validation and printing | Update `datom_store()` validation, object shape, print output, and roxygen so gov-attached stores can omit direct data location while no-gov stores cannot. | `test-store.R` constructor/print/error cases. | ☐ todo |
| 3 | Ref bootstrap connection path | Refactor `.datom_resolve_data_location()`, `.datom_get_conn_reader()`, and `.datom_get_conn_developer()` so gov-attached conns build data clients from ref-resolved location and credentials. | `test-conn.R` reader/developer, S3/local, separate credential cases. | ☐ todo |
| 4 | Guidance and failure modes | Replace fallback/warning behavior with state-aware messages for direct-location misuse, missing no-gov location, failed ref read, and data credential denial. | Snapshot/error expectation tests near connection tests. | ☐ todo |
| 5 | Docs and vignettes | Update handoff, design-ref-json, credentials, and reference docs to show governance-first reader handoff and no-gov explicit-location handoff. | Build docs checks as appropriate; no new exports unless chosen in Chunk 1. | ☐ todo |
| 6 | E2E and audit | Run full `devtools::test()`, then a local sandbox E2E covering no-gov explicit location and gov-attached ref-resolved location. Update spec/instructions if permanent rules changed. | Full suite count plus sandbox transcript. | ☐ todo |

---

## Acceptance Criteria

1. A gov-attached reader can build a connection with governance store + `project_name` and no direct data bucket/path/prefix/region.
2. A gov-attached developer can build a connection without manually supplying direct data location when the data repo records governance attachment.
3. A no-gov connection still requires explicit data location and errors clearly if omitted.
4. Passing stale direct data coordinates for a gov-attached project is no longer the recommended path; the user is guided to ref-resolved setup.
5. Data credentials remain runtime-only and masked; no credential values are written to `project.yaml`, `ref.json`, manifests, docs, or printed objects.
6. Migration ergonomics improve: a reader reconnects through governance after `ref.json` changes without being told new data coordinates.
7. Vignettes no longer instruct gov-attached reader handoffs to include data bucket/path/prefix/region.
8. Full test suite passes with count recorded in the chunk-completing commit.

---

## Model Escalation Cues

- **After Chunk 1**: consider a design spot-check if the chosen credential API adds a new exported constructor or changes `datom_store()` semantics substantially.
- **After Chunk 3**: consider a purity audit because connection construction touches store validation, ref resolution, and backend client creation.
- **Before Phase Completion**: run a test coverage review to confirm gov-attached/no-gov matrix coverage is balanced.

---

## Progress Log

- **2026-05-23**: Phase created from issue #24. Initial evaluation concluded the bug is valid, but the solution should separate data location from data credentials and apply the governance-first rule based on project governance state, not only reader role.
