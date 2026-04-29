# Draft Phase: Conn Finalize & Backend Accessor Refactor

**Status**: Draft (queued, not active)
**Branch**: TBD (`phase/{n}-conn-refactor`)
**Depends on**: Phase 15 cleanup merged.
**Numbering note**: User mentioned this might become Phase 17, but Phase 16 (`phase_16_vignettes.md`) already references "Phase 17 (small utility helpers — `datom_summary`, `datom_projects`)". Two candidates for "Phase 17" exist — assign final number when this phase is activated.

---

## Goal

Two thematically-linked refactors deferred from the Phase 15 audit. Both touch connection-flow code that just stabilized in Phase 15 — folding them into the Phase 15 PR was rejected as too risky. Both are quality/maintainability improvements with no behavior change.

---

## Items

### Item 1 (audit M2) — Dedup ref-resolution + migration-detection in `_developer` / `_reader`

**Location:** [R/conn.R](../R/conn.R) — `.datom_get_conn_developer()` and `.datom_get_conn_reader()`.

**Issue:** ~30 lines of structurally identical logic in each function: resolve ref, detect migration mismatch, decide what to do about it. The branches differ on:
- **Developer mismatch:** auto-pull git + re-read `project.yaml`; abort if still mismatched.
- **Reader mismatch:** warn and proceed using ref-resolved location with reader's existing creds.

**Proposed fix:** Extract `.datom_finalize_conn_with_ref(conn, role)` that branches on `role` internally. The shared scaffolding (resolve, compare, detect mismatch) lives in the helper; only the *response* to mismatch differs.

**Risk:** The branches share a shape but their semantics are different (auto-recovery vs. warn-and-continue). Merging hides the asymmetry — readers of the helper need to understand both roles to follow control flow. Worth doing, but needs care: explicit `switch(role, developer = {...}, reader = {...})` blocks inside the helper, not clever conditionals.

**Effort:** Half day including tests.

---

### Item 2 (audit M6) — `.datom_conn_for(scope = c("data", "gov"))` accessor

**Location:** Many call sites across [R/conn.R](../R/conn.R), [R/sync.R](../R/sync.R), [R/ref.R](../R/ref.R), [R/utils-gov.R](../R/utils-gov.R), [R/validate.R](../R/validate.R).

**Issue:** `datom_conn` carries `client` (data) and `gov_client` (gov). Call sites hand-pick: `if (scope == "gov") conn$gov_client else conn$client`, or build a sub-conn via `.datom_gov_conn(conn)`. Two patterns, both leaky.

**Proposed fix:** Single accessor:

```r
.datom_conn_for <- function(conn, scope = c("data", "gov")) {
  scope <- match.arg(scope)
  switch(scope,
    data = conn,
    gov  = .datom_gov_conn(conn)
  )
}
```

Then all call sites become `.datom_conn_for(conn, "gov")` instead of `.datom_gov_conn(conn)` + ad-hoc client picking. Future backends (GCS) become a one-line addition to the dispatch in [utils-storage.R](../R/utils-storage.R) — no scattered `if (backend == ...)` updates needed.

**Risk:** Pure refactor, but touches many files. Audit each call site to confirm semantics didn't drift.

**Effort:** Half day including tests.

---

## Why deferred from Phase 15

- Phase 15 main work just stabilized the conn flow; both items touch it.
- Cross-cutting (M6 especially) — would expand PR #6's blast radius beyond "separate gov repo."
- Neither blocks CRAN — they're maintainability wins, not bug fixes.
- Better as a deliberate refactor phase with its own chunk-level care.

---

## Acceptance criteria (when activated)

- All tests pass (≥1325 + any new tests for the helpers).
- E2E sandbox run shows no regressions.
- Call-site count for `gov_local_path` resolution reduced (M2 wave) or `conn$gov_client` direct access reduced (M6 wave).
- No new asymmetries introduced (e.g. `.datom_finalize_conn_with_ref` should not be called from anywhere except the two `_get_conn_*` functions).
