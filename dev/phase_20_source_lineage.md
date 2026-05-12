# Phase 20: Transitive Source Lineage

**Status**: Chunk 2 -- next
**Branch**: `phase/20-source-lineage`
**Started**: 2026-05-11
**Depends on**: Phase 18 (gov-on-demand) closed

---

## Goal

Add a `source_lineage` metadata field to datom tables that records the **transitive non-derived sources** of every table. While `parents` records the immediate inputs (one step back), `source_lineage` records the flat list of raw, non-derived origin tables reached through any chain of derivations.

dpbuild (or any caller) pre-computes `source_lineage` at write time by unioning the parents' stored `source_lineage` fields. datom stores it, validates its schema, and serves it back. **datom never walks lineage** -- the transitive closure is resolved once, upfront, and stored flat.

The two fields answer different questions:
- `parents`: "what did this table come from one step back?" (debugging, diff, replay)
- `source_lineage`: "what raw datasets does this table ultimately depend on?" (audit, regulatory disclosure, reproducibility scope)

---

## Locked decisions (entering Phase 20)

1. **`parents` and `source_lineage` both ship.** No replacement. (from Phase 18, 2026-05-02)
2. **dpbuild populates both.** datom never auto-computes lineage for derived tables. (from Phase 18, 2026-05-02)
3. **Storage**: `source_lineage` lives in `metadata.json` alongside `parents`. No sidecar. (2026-05-11)
4. **No DAG walking.** No `depth = "all"` mode. Closure is pre-computed by the writer; datom serves flat data. (2026-05-11)
5. **No cross-project conn resolution.** Eliminated by (4). (2026-05-11)
6. **Self-as-source convention for imports**: an imported table's `source_lineage` is `[{self-identity}]`, not `NULL`. Makes the union rule total without a base-case branch. (2026-05-11)
7. **No backward compatibility concerns.** Pre-release; rename/break freely. (2026-05-11)
8. **Imported tables**: `datom_sync()` auto-populates `source_lineage = [self]`. User cannot supply it. (2026-05-11)
9. **Derived tables**: `datom_write()` with `parents` non-NULL **requires** `source_lineage`. Hard error if missing or malformed. (2026-05-11)
10. **Direct `datom_write()` without parents**: `source_lineage` stays NULL (no auto-self convention here -- the canonical raw path is `datom_sync()`). (2026-05-11)
11. **Correctness of contents**: datom validates schema shape only. Semantic correctness (does the union match parents?) is dpbuild's responsibility. A separate audit helper `datom_validate_lineage()` provides on-demand union checking. (2026-05-11)
12. **Walker invariant** (forward-looking): any future code that traverses lineage MUST recurse via `parents`, never via `source_lineage`. Entries in `source_lineage` are terminal leaves by definition. Violating this creates infinite loops via the self-as-source fixed point. (2026-05-11)

---

## Schema

`source_lineage` is a list of source-table descriptors in `metadata.json`:

```json
{
  "data_sha": "...",
  "parents": [...],
  "source_lineage": [
    {
      "project": "raw-clinical-trials",
      "table": "subjects_v3",
      "version_sha": "a1b2c3..."
    },
    {
      "project": "raw-lab-results",
      "table": "lab_panels",
      "version_sha": "d4e5f6..."
    }
  ]
}
```

Each entry has three required string fields: `project`, `table`, `version_sha`. All non-empty. No optional fields in Phase 20 (no `captured_at`, no flags). dpbuild may add fields later; datom passes them through but does not validate them.

**Imported (raw) tables** carry their own identity as the sole entry:

```json
{
  "source_lineage": [
    {"project": "<this-project>", "table": "<this-table>", "version_sha": "<this-version>"}
  ]
}
```

---

## Transitivity rule (for dpbuild reference)

For derived table T with `parents = [A, B, ...]`:

```
T.source_lineage = dedupe(union(p.source_lineage for p in parents))
```

Dedup key is the `(project, table, version_sha)` tuple. dpbuild owns this computation; datom stores the result.

The rule is total because of decision (6): every parent -- raw or derived -- has a non-empty `source_lineage` field.

---

## Chunks

| # | Title | Scope | Status |
|---|-------|-------|--------|
| 1 | Schema plumbing | `source_lineage` parameter on `datom_write()`/`datom_sync()`; validation; auto-self for imports; metadata SHA includes lineage | ✅ done |
| 2 | `datom_get_lineage()` query helper | New export with `depth = c("source", "parents")` modes; flat reads, no walking | ⏳ next |
| 3 | `datom_validate_lineage()` audit helper | On-demand union check: fetch parents' lineages, compare to declared. Report missing/extra/wrong-version deltas. Integrated into `datom_validate()`? (decide in chunk) | ☐ todo |
| 4 | Spec + vignette + pkgdown | Update `dev/datom_specification.md` schema section; new article "Tracing data lineage"; `_pkgdown.yml` entries; dpbuild contract note in `dev/daapr_architecture.md` | ☐ todo |

All chunks are routine for the default working model. No escalation flagged at plan time. If Chunk 3's union-comparison logic grows (e.g. specific delta reporting with cli styling) it may warrant a coverage spot-check before commit -- surface at the time, not now.

---

## Chunk 1: Schema plumbing

**Read first**:
- [R/read_write.R#L180-L215](R/read_write.R#L180-L215) -- `.datom_build_metadata()` current shape
- [R/read_write.R#L385-L460](R/read_write.R#L385-L460) -- `datom_write()` current shape (parents handling)
- `datom_sync()` in [R/read_write.R](R/read_write.R) -- imported-table write path
- [R/utils-metadata.R](R/utils-metadata.R) -- `.datom_compute_metadata_sha()` volatile-field list

**Invariants**:
- Imported tables (via `datom_sync()`): `source_lineage = [{self}]`, set automatically, NOT user-supplied.
- Derived tables (via `datom_write()` with `parents`): `source_lineage` REQUIRED, user-supplied, schema-validated.
- Derived tables without `parents` (rare): `source_lineage = NULL`, no auto-self.
- Schema validation: each entry is a list with `project`, `table`, `version_sha` as non-empty single strings. Extra fields allowed (pass-through). Whole-field must be a list of such entries or NULL.
- Metadata SHA: `source_lineage` IS version-bearing (a change in declared lineage = a new version). Not in the volatile list.

**Tasks**:
1. New internal helper `.datom_validate_source_lineage(x)` -- structural validation, abort with cli error pointing to the bad entry.
2. Extend `.datom_build_metadata()` signature: add `source_lineage = NULL` param. Insert into metadata after `parents`.
3. Extend `datom_write()` signature: add `source_lineage = NULL` param. After validating `parents`, validate the pair:
   - `!is.null(parents) && is.null(source_lineage)` -> abort (structural mandate).
   - `!is.null(source_lineage)` -> call `.datom_validate_source_lineage()`.
4. Extend `datom_sync()` to auto-build `source_lineage = list(list(project = <project_name>, table = <name>, version_sha = <new metadata_sha>))` and pass to `.datom_build_metadata()`.
   - Bootstrap concern: `version_sha` is the metadata_sha, which depends on the metadata (including `source_lineage`). Self-reference. Resolution: compute metadata_sha with `source_lineage = [{project, table, version_sha = "<self>"}]` as a placeholder, then **substitute the actual sha** back in after computing. Test: round-trip stability.
   - Alternative: store `version_sha = NULL` or `version_sha = "<self>"` literally for the self-entry and document the convention. **Decide in implementation** -- lean toward placeholder-substitute because it makes downstream code uniform (every entry has a real sha).
5. Tests in [tests/testthat/test-read-write.R](tests/testthat/test-read-write.R): write+sync paths with valid/invalid `source_lineage`; missing-when-required; auto-self correctness for `datom_sync()`; metadata SHA changes when `source_lineage` changes; metadata SHA stable across JSON round-trip.

**Acceptance**: `devtools::test()` clean, test count up by ~8-12. Existing tests unaffected.

---

## Chunk 2: `datom_get_lineage()`

**Read first**:
- [R/query.R#L170-L230](R/query.R#L170-L230) -- `datom_get_parents()` pattern

**Design**:
```r
datom_get_lineage(conn, name, version = NULL, depth = c("source", "parents"))
```
- `depth = "source"` (default): returns the `source_lineage` list as stored. NULL if absent.
- `depth = "parents"`: returns the `parents` list (same as `datom_get_parents()`).

Single storage read of the table's metadata.json. No walking. No cross-project calls. `datom_get_parents()` is retained as a thin wrapper -- both stay exported.

**Tasks**:
1. New export in `R/query.R`. Match `datom_get_parents()` error handling exactly (version-resolution, abort messages).
2. Roxygen + Rd.
3. Tests in [tests/testthat/test-query.R](tests/testthat/test-query.R): each depth mode; current vs versioned metadata; missing field returns NULL; bad `depth` value rejected with `match.arg()`-style error.
4. `_pkgdown.yml`: add entry.

**Acceptance**: ~6-10 new tests, `devtools::check()` clean.

---

## Chunk 3: `datom_validate_lineage()`

**Read first**:
- `datom_validate()` in [R/validate.R](R/validate.R) (or wherever the existing validator lives)

**Design**:
```r
datom_validate_lineage(conn, name, version = NULL)
```

For table T with `parents`, fetches each parent's metadata, unions their `source_lineage` fields, dedupes, and compares to T's declared `source_lineage`. Returns a structured result:
- `$status`: `"ok"` | `"mismatch"` | `"unchecked"` (e.g. table has no parents)
- `$missing`: entries in computed union but absent from declared
- `$extra`: entries in declared but absent from computed union
- `$message`: human-readable summary via cli

Cross-project parents: if a parent's `project` differs from `conn$project_name`, the function attempts to resolve via gov register (if gov attached) or aborts with "parent in project {.val X} unreachable -- attach governance or pass a reader conn". Decide in chunk whether to take an optional `cross_project_resolver` argument. Lean: don't, keep it simple; cross-project audit is a future need.

**Tasks**:
1. New export in a new file `R/lineage.R` (or `R/validate.R` if it fits).
2. Helper: same-project parent metadata fetch (existing pattern).
3. Union + dedup utility (reusable; expose internally as `.datom_lineage_union()`).
4. Tests: all-match, missing element, extra element, wrong version_sha, table with no parents (status = "unchecked"), bad inputs.
5. `_pkgdown.yml`: add entry.
6. **Open question**: integrate into `datom_validate()` as an optional check? Lean yes if `datom_validate()` already iterates tables; otherwise keep separate. Decide in chunk.

**Acceptance**: ~10-15 new tests, `devtools::check()` clean.

---

## Chunk 4: Spec + vignette + pkgdown

**Tasks**:
1. `dev/datom_specification.md`: extend the metadata schema section with `source_lineage` (schema, transitivity rule, walker invariant).
2. New vignette `vignettes/source-lineage.Rmd` -- the audit story. Outline:
   - Setup: study with raw `dm`, `lb`; derived `dm_clean` from `dm`; derived `analysis_pop` from `dm_clean` + `lb`.
   - Show `datom_get_lineage(conn, "analysis_pop", depth = "parents")` -> `dm_clean`, `lb`.
   - Show `datom_get_lineage(conn, "analysis_pop", depth = "source")` -> raw `dm`, raw `lb` directly.
   - The audit pitch: regulatory-style "what raw data informs this output?" answered in one call.
   - Show `datom_validate_lineage()` catching a deliberate mismatch (manually-crafted bad metadata).
3. `_pkgdown.yml`: add the article to the Govern or Reference group.
4. `dev/daapr_architecture.md`: add a short subsection on the dpbuild lineage contract -- dpbuild reads parents' `source_lineage`, unions, dedupes, passes to `datom_write()`. Mechanical, not user-typed.
5. Migrate any Phase-20 learnings into `.github/copilot-instructions.md` "Gotchas" if patterns emerged (especially the walker invariant).

**Acceptance**: `pkgdown::build_site()` clean, all 28+1+1 exports indexed, vignette renders ASCII-only.

---

## Acceptance criteria (phase-level)

1. `source_lineage` parameter on `datom_write()`, auto-populated by `datom_sync()`.
2. Hard error on `parents` non-NULL + `source_lineage` NULL or malformed.
3. `datom_get_lineage()` exported with `depth = c("source", "parents")`.
4. `datom_validate_lineage()` exported.
5. Schema documented in `dev/datom_specification.md`.
6. Vignette "Tracing data lineage" renders and is linked in `_pkgdown.yml`.
7. dpbuild integration note in `dev/daapr_architecture.md`.
8. `devtools::test()` total count documented in every commit; `devtools::check()` clean.
9. E2E sandbox run (`dev/dev-sandbox.R`) exercises a derived-table write with `source_lineage` and a lineage query; passes end-to-end.

---

## Progress Log

### 2026-05-11 -- Phase opened
- Branch `phase/20-source-lineage` created from `main`.
- Phase doc created from the draft, expanded with the design decisions made during planning conversation (decisions 3-12 above).
- Pre-conditions for design captured: no DAG walking, no cross-project conn resolution, self-as-source for imports, structural mandate for derived tables, datom validates schema only (semantic correctness via on-demand `datom_validate_lineage()`).
- Walker invariant flagged: any future traversal must follow `parents`, never `source_lineage` (avoids self-as-source infinite loop).
- Draft file `dev/draft_phase_20_source_lineage.md` deleted.
- Chunk 1 next.

### 2026-05-12 -- Chunk 1 done (schema plumbing)
- `.datom_validate_source_lineage()` added to `R/utils-sha.R`: validates NULL, empty list, or list of entries with non-empty `project`/`table`/`version_sha` strings; extra fields pass through.
- `.datom_build_metadata()` extended with `source_lineage = NULL` param; field inserted into metadata after `parents`.
- `datom_write()` extended with `source_lineage = NULL` param. Structural mandate enforced: `parents` non-NULL and `source_lineage` NULL -> hard error.
- `datom_sync()` auto-builds `source_lineage = [{self}]` for imported tables. Bootstrap decision: `version_sha` in the self-entry uses `data_sha` (content-addressed, no circularity with `metadata_sha`).
- `source_lineage` IS version-bearing (in `metadata_sha`, not in volatile list). SHA stable across JSON round-trip confirmed by test.
- 22 new tests (1530 -> 1552). 0 failures.
- Chunk 2 next.
