# Implementation Plan

## Overview

Implements the cross-project-parent-lineage feature: a new `datom_parent()`
constructor, a promoted `datom_lineage_union()` helper, `datom_write()`
reworked to consume resolved parent records and derive `source_lineage`,
removal of `datom_validate_lineage()` in favor of a composable recipe, and
the supporting internal validator, docs, and tests. Each task is
test-driven, ASCII-only, <= 80 columns, and keeps the one-connection-per-
project model. Tasks are ordered so shared primitives land before their
consumers.

## Task Dependency Graph

```json
{
  "tasks": {
    "1": { "dependsOn": [] },
    "1.1": { "dependsOn": ["1"] },
    "2": { "dependsOn": [] },
    "2.1": { "dependsOn": ["2"] },
    "3": { "dependsOn": [] },
    "3.1": { "dependsOn": ["3"] },
    "4": { "dependsOn": ["1", "2", "3"] },
    "4.1": { "dependsOn": ["4"] },
    "5": { "dependsOn": ["4"] },
    "5.1": { "dependsOn": ["5"] },
    "5.2": { "dependsOn": ["5"] },
    "6": { "dependsOn": ["1", "5"] },
    "7": { "dependsOn": ["1.1", "2.1", "3.1", "4.1", "5", "5.1", "5.2", "6"] }
  },
  "waves": [
    { "wave": 1, "tasks": ["1", "2", "3"] },
    { "wave": 2, "tasks": ["1.1", "2.1", "3.1", "4"] },
    { "wave": 3, "tasks": ["4.1", "5"] },
    { "wave": 4, "tasks": ["5.1", "5.2", "6"] },
    { "wave": 5, "tasks": ["7"] }
  ]
}
```

## Tasks

- [ ] 1. Promote the lineage union to an exported helper
  - Move the algorithm in `.datom_lineage_union()` (R/lineage.R) into a new
    exported `datom_lineage_union(lineages)` with roxygen (`@param`,
    `@return`, `@export`, and an `@examples` recipe stub).
  - Dedup by the composite key `paste(project, table, version_sha, sep="\t")`;
    return `list()` for empty input; tolerate `NULL` members (a parent may
    have `source_lineage = NULL`) via a compact/guard before flatten;
    preserve retained entry fields unchanged.
  - Route any existing internal call sites to the exported name.
  - Add `datom_lineage_union` to the `_pkgdown.yml` reference index.
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ] 1.1 Unit tests for `datom_lineage_union()`
  - New tests: dedup across lists; empty-in -> empty-out; `NULL` members
    tolerated; fields preserved; single-list identity.
  - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [ ] 2. Add `.datom_validate_parents()` internal validator
  - In R/utils-sha.R, mirror `.datom_validate_source_lineage()`: NULL is
    valid; reject a named list ("must be a list of entry lists"); each entry
    must be a list with `source`, `table`, `version`, `data_sha` as single
    non-empty strings; identify the first invalid entry by index and field.
  - WHERE an entry carries a non-NULL, non-empty `source_lineage`, validate
    it via `.datom_validate_source_lineage()`; treat NULL/empty as valid.
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [ ] 2.1 Unit tests for `.datom_validate_parents()`
  - Valid list passes; named list rejected; missing/empty field rejected
    with entry index + field; non-list entry rejected; per-entry
    `source_lineage` validated when present, NULL/empty accepted.
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [ ] 3. Implement `datom_parent(conn, table, version)` export
  - Add to R/lineage.R with roxygen (`@param`, `@return`, `@export`, and a
    `\dontrun{}` `@examples` block — it needs a live conn/storage read). No
    `data_sha` parameter.
  - Validate args first (abort before any read): `inherits(conn,
    "datom_conn")`; `.datom_validate_name(table)`; `version` single
    non-empty string.
  - Read `paste0(table, "/.metadata/", version, ".json")` via
    `.datom_storage_read_json(conn, key)` inside `tryCatch`; on failure abort
    with a message naming `table`, `version`, and `conn$project_name`.
  - Abort if the snapshot lacks a non-empty `data_sha`.
  - Capture `source_lineage <- snap$source_lineage %||% NULL`.
  - Return `list(source = conn$project_name, table, version,
    data_sha = snap$data_sha, source_lineage)` — no conn retained.
  - Add `datom_parent` to `_pkgdown.yml` reference index.
  - _Requirements: 1.1-1.14, 2.1-2.5, 3.1-3.6, 6.1, 6.2, 6.4_

- [ ] 3.1 Tests for `datom_parent()` (new tests/testthat/test-parent.R)
  - Success: resolves `data_sha` and `source_lineage` from a mocked
    snapshot; `source == conn$project_name`; return has exactly the five
    fields and no conn; `jsonlite::toJSON` round-trip succeeds
    (serializable).
  - `source_lineage` NULL when absent from the snapshot.
  - Errors: non-`datom_conn`; invalid `table`; invalid `version`; snapshot
    not found; snapshot missing `data_sha`.
  - Invariant: `formals(datom_parent)` has no `data_sha`.
  - Cross-project: two `mock_datom_conn()` with different `project_name` and
    distinct mocked stores; each produces the correct `source`; a read of the
    wrong project's store would trip the network guard.
  - _Requirements: 1, 2, 3, 6, 10.4, 10.5, 10.6_

- [ ] 4. Rework `datom_write()` parent handling (R/read_write.R)
  - Remove the parent-enrichment block that reads
    `{p$table}/.metadata/{p$version}.json` to add `data_sha`.
  - Remove the mandate branch that aborts when `parents` is non-NULL and
    `source_lineage` is NULL.
  - When `parents` is non-NULL: call `.datom_validate_parents(parents)`;
    derive `source_lineage <- datom_lineage_union(lapply(parents, \(p)
    p$source_lineage))`; then strip each parent to a lean entry
    `list(source, table, version, data_sha)`.
  - Pass the lean parents and derived `source_lineage` to
    `.datom_build_metadata()`; leave local -> git -> storage ordering,
    `.datom_write_metadata_local()`, and `.datom_push_metadata_s3()`
    unchanged.
  - Replace the public `source_lineage` parameter with an internal dotted
    `.source_lineage` (matching `.table_type` / `.original_file_sha`), used
    only by the imported path; update the call site in `R/sync.R` to pass
    `.source_lineage`. Keep `.datom_validate_source_lineage()` on that
    imported path.
  - Update `datom_write()` roxygen: `parents` is a list of `datom_parent()`
    records; `source_lineage` is derived from parents (no public parameter).
  - _Requirements: 4.1-4.5, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 6.3_

- [ ] 4.1 Rewrite parent tests in tests/testthat/test-read-write.R
  - Replace the old enrichment-based tests: writing with resolved
    `datom_parent()` records produces lean `parents[]` (exactly `source`,
    `table`, `version`, `data_sha`; no `source_lineage`) and a
    `source_lineage` equal to the union of parents' lineages.
  - Rejects a raw `list(source, table, version)` lacking `data_sha` with an
    error naming `datom_parent()`.
  - "No enrichment" proof: mock so any parent-snapshot read during write
    fails; write still succeeds.
  - Supplying `source_lineage` alongside parents: derived union wins.
  - NULL parents: no parents recorded; no parents-based `source_lineage`.
  - _Requirements: 4.1, 4.2, 4.3, 5.1, 5.3, 5.4, 5.6, 5.7_

- [ ] 5. Remove `datom_validate_lineage()` and update the full reference surface
  - Delete `datom_validate_lineage()`, `.datom_lineage_result()`, and
    `.datom_lineage_diff()` from R/lineage.R (keep `datom_lineage_union()`).
  - Regenerate NAMESPACE (roxygen) so the export is gone; remove
    `datom_validate_lineage` from `_pkgdown.yml`.
  - Remove the validator cases in **`tests/testthat/test-query.R`** (there is
    no `test-lineage.R`); retain any union assertions under task 1.1.
  - Rework the `datom_validate_lineage()` **calls** in `dev/e2e-solo-lineage.R`
    and `dev/e2e-solo-s3.R` to the recompute recipe (they would otherwise
    break).
  - Update stale references in `dev/engineering-notes.md` (the two entries),
    `dev/datom_pathways.md`, `dev/datom_specification.md`, and
    `dev/README.md`.
  - Replace or remove any roxygen `@seealso` / `\link{datom_validate_lineage}`
    cross-references so R CMD check reports no broken links.
  - _Requirements: 9.1, 9.2, 9.8_

- [ ] 5.1 Rewrite the lineage vignette
  - Rewrite the "Validating lineage consistency" section of
    `vignettes/source-lineage.Rmd` (it calls and explains
    `datom_validate_lineage()`) to teach the composable recompute recipe
    using `datom_get_parents()`, per-parent `datom_get_lineage()`, and
    `datom_lineage_union()`. Keep `eval = FALSE` chunks consistent.
  - _Requirements: 9.5, 9.6, 9.7_

- [ ] 5.2 Update NEWS.md
  - Record the removal of `datom_validate_lineage()`, the addition of
    `datom_parent()` and `datom_lineage_union()`, and the `parents` contract
    change (records now require resolved `datom_parent()` records;
    `source_lineage` is derived).
  - _Requirements: 9.9_

- [ ] 6. Update reads and document the recompute recipe
  - Update `datom_get_parents()` roxygen `@return` (R/query.R) to list
    `source, table, version, data_sha`.
  - Add the recompute recipe as an `@examples` block on
    `datom_lineage_union()` (and/or a short lineage vignette section):
    `datom_get_parents(conn_C, "C")` -> per parent
    `datom_get_lineage(conn_for_project, parent$table,
    version = parent$version, depth = "source")` ->
    `datom_lineage_union(...)` -> compare to
    `datom_get_lineage(conn_C, "C", depth = "source")`. Read each parent
    through a conn scoped to that parent's project; never one conn across
    stores.
  - _Requirements: 9.3, 9.4, 9.5, 9.6_

- [ ] 7. Quality gates and full verification
  - Run `devtools::document()` to sync NAMESPACE and `.Rd`.
  - Run `devtools::test()`; ensure WARN 0 and all pass.
  - Lint: ASCII-only and <= 80 cols on every changed `R/*.R`.
  - Confirm `pkgdown::build_site()` has zero missing/extra topics for the two
    added exports and the removed one, and that no `.Rd` retains a broken
    `\link{datom_validate_lineage}` (R CMD check WARN 0).
  - Confirm `vignettes/source-lineage.Rmd` no longer references the removed
    function.
  - Grep the whole repo (R, tests, vignettes, dev, NEWS) for lingering
    `datom_validate_lineage` references.
  - _Requirements: 10.1, 10.2, 10.3, 10.7, 10.8, 10.9_

## Notes

- Pre-release (v0.0.0.9001): breaking the `parents` contract and removing
  `datom_validate_lineage()` are acceptable; `metadata_sha` shifts for
  tables with parents because the recorded shape changes (intended).
- All storage access is mocked in tests via `.datom_storage_read_json` /
  `.datom_storage_write_json`; the fail-closed guard in
  tests/testthat/setup.R enforces no real network egress. Cross-project
  tests use exactly two distinct mock stores.
- Resolved from spec review: the public `source_lineage` parameter of
  `datom_write()` is removed and replaced by an internal `.source_lineage`
  (imported path only); `datom_validate_lineage()` removal is signed off; the
  validator's tests live in `tests/testthat/test-query.R`.
- Downstream dp_dev / dpbuild migration to `datom_parent()` is out of scope
  and tracked separately.
