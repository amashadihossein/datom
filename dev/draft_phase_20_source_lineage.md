# Phase 20 (DRAFT): Transitive Source Lineage

**Status**: Draft -- not yet activated
**Depends on**: Phase 18 (gov-on-demand) closed; independent of Phase 19
**Captured**: 2026-05-02 (during Phase 18)

---

## Goal

Add a `source_lineage` metadata field to datom tables that records the **transitive non-derived source** of every table. While `parents` records the immediate inputs (the layer above), `source_lineage` reaches all the way back to the raw, non-derived origin tables. dpbuild populates both fields. datom never auto-computes either; it only stores and queries them.

This complements (does not replace) `parents`. The two fields answer different questions:
- `parents`: "what did this table come from one step back?" (debugging, diff, replay)
- `source_lineage`: "what raw datasets did this table ultimately depend on?" (audit, regulatory disclosure, reproducibility scope)

---

## Locked from Phase 18

1. **`parents` and `source_lineage` both ship.** No replacement, no migration. Decided 2026-05-02.
2. **dpbuild populates both.** datom never auto-computes lineage. Parallels current `parents` behavior. Decided 2026-05-02.

---

## Core Elements (to elaborate when activated)

### Schema

`source_lineage` is a list of source-table descriptors stored in table metadata:

```json
{
  "source_lineage": [
    {
      "project": "raw-clinical-trials",
      "table": "subjects_v3",
      "version_sha": "a1b2c3...",
      "captured_at": "2026-04-15T..."
    },
    {
      "project": "raw-lab-results",
      "table": "lab_panels",
      "version_sha": "d4e5f6...",
      "captured_at": "2026-04-15T..."
    }
  ]
}
```

Each entry pins a specific version of an upstream non-derived table. "Non-derived" means the source is itself authored from outside datom (raw extract, vendor file, manual entry) rather than computed from other datom tables.

### Determination of "non-derived"

A table is non-derived iff its `source_lineage` is empty (the recursion base case). dpbuild sets this flag explicitly when registering a raw extract. datom enforces no semantic check -- if dpbuild reports `source_lineage = []`, the table is treated as a root.

### Transitivity rule

If table T has `parents = [A, B]`, dpbuild sets:

```
T.source_lineage = union(A.source_lineage, B.source_lineage)
```

If A is itself non-derived, `A.source_lineage = [{A's identity}]`. If A is derived, the union flattens through. dpbuild owns the recursion; datom stores the result.

### Query API

A new exported helper:

```r
datom_get_lineage(conn, table, version = NULL, depth = c("source", "parents", "all"))
```

- `depth = "source"`: returns the `source_lineage` list (transitive roots).
- `depth = "parents"`: returns immediate `parents` (existing behavior of `datom_get_parents()`; consider whether to fold in or keep separate).
- `depth = "all"`: returns the full DAG between this table and its sources, walked via `parents` chains across projects (cross-project conn resolution required).

### Cross-project lineage walking

`depth = "all"` requires resolving lineage across projects. Implementation:
1. For each entry in `parents`, derive its conn (same project: reuse `conn`; different project: `datom_get_conn(project_name = ..., store = reader_store)`).
2. Recurse on each parent until reaching a table with empty `source_lineage`.
3. Memoize by `(project, table, version_sha)` to avoid redundant fetches.

This is the most complex element; consider whether to gate `depth = "all"` behind gov attached (so reader conns can be resolved automatically from the gov register) and surface clear errors when lineage spans projects the caller cannot reach.

### Audit / regulatory framing

The vignette story: "what raw data does this published derivative ultimately depend on?" Answers come from `source_lineage` without walking. For regulatory submissions where the question is "list every raw dataset and version that informed this output", `datom_get_lineage(depth = "source")` returns it directly.

### Schema-additive, no migration

Existing tables without `source_lineage` are tolerated. `datom_get_lineage()` returns NULL or an empty list with a clear message when the field is absent. dpbuild backfills opportunistically as tables are rewritten.

### Non-goals for Phase 20

- Auto-computing lineage from data inspection (column overlap, name matching). Out of scope; dpbuild's job to declare.
- Cycle detection beyond a depth limit. dpbuild is expected to produce DAGs; datom adds a depth ceiling as a safety net.
- Mutation of historical lineage. Once written, a version's `source_lineage` is immutable (parallels everything else in datom metadata).

---

## Open Questions (decide at activation)

- Fold `datom_get_parents()` into `datom_get_lineage(depth = "parents")` or keep separate? Lean: keep both, with `datom_get_parents()` as a thin wrapper for backward compat (no users yet, but the name is clearer).
- Should `source_lineage` entries pin `version_sha` strictly, or allow "latest" sentinels? Lean: strict pin always (matches parents behavior; reproducibility is the whole point).
- Cross-project walking when caller lacks reader credentials for an upstream project: hard error or partial result? Lean: partial result with a clear "unreachable" marker.
- Storage location: in the table metadata JSON (alongside `parents`) or a sidecar? Lean: alongside `parents` (already in metadata, schema-additive).

---

## Acceptance Criteria (for activation)

1. Schema documented in `dev/datom_specification.md` (metadata section).
2. `datom_get_lineage()` exported with three depth modes.
3. Cross-project walking works for `depth = "all"` with gov-attached projects.
4. Backward-compat: existing tables without the field handled gracefully.
5. Vignette: "Tracing data lineage" article showing the audit story.
6. dpbuild integration documented in `dev/daapr_architecture.md`.

---

## Notes

This draft preserves the design discussion held during Phase 18 (2026-05-02). When activated, expand into a full chunked plan via the standard phase workflow.

Phase 20 is independent of Phase 19; either can be sequenced first. Lean: Phase 19 first because it's a single-function deliverable with clear acceptance, while Phase 20 is more architectural (cross-project walking, dpbuild contract) and benefits from more design soak time.
