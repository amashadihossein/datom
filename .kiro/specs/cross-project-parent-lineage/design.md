# Design Document

## Overview

This design introduces `datom_parent()` as the single, authoritative way to
declare a parent, reshapes `datom_write()` to consume resolved parent
records and derive `source_lineage` itself, replaces `datom_validate_lineage()`
with the composable primitive `datom_lineage_union()` plus a documented
recipe, and keeps every store access scoped to one connection per project.

The design is deliberately small and additive at the seams: it reuses the
existing storage dispatch layer, the existing metadata assembly and SHA
logic, and the existing lineage-union algorithm (promoted from internal to
exported). The net behavioral change is where parent `data_sha` and lineage
are resolved (now at `datom_parent()` construction, against the parent's own
store) and what `datom_write()` records (lean parent edges plus a derived
`source_lineage`).

Requirements traceability is summarized in the final section.

## Architecture

### Data flow: declaring and writing a derived table

```
                per-project conns (one per store)
   conn_A ──► datom_parent(conn_A, "A", vA) ─┐
   conn_B ──► datom_parent(conn_B, "B", vB) ─┤  list of Parent_Records
                                             │  (pure data, no conn)
                                             ▼
   conn_C ──► datom_write(conn_C, data=C, name="C", parents=list(pA, pB))
                                             │
                    ┌────────────────────────┴───────────────────────┐
                    │ 1. .datom_validate_parents(parents)             │
                    │ 2. source_lineage <- datom_lineage_union(       │
                    │        lapply(parents, `[[`, "source_lineage")) │
                    │ 3. parents_recorded <- strip to                 │
                    │        {source, table, version, data_sha}       │
                    │ 4. .datom_build_metadata(... parents_recorded,  │
                    │        source_lineage ...)                      │
                    │ 5. local write → git → storage (unchanged)      │
                    └─────────────────────────────────────────────────┘
```

Key point: each `datom_parent()` call reads only its own project's store
through the conn it was handed. `datom_write()` reads/writes only `conn_C`.
No function receives more than one connection.

### Data flow: inspecting / recomputing lineage (replaces the validator)

```
   conn_C ─► datom_get_parents(conn_C, "C")  ──► [{source,table,version,data_sha}, ...]

   for each parent p:
     conn_for(p$source) ─► datom_get_lineage(conn_p, p$table,
                                              version = p$version,
                                              depth = "source")  ──► p_lineage

   datom_lineage_union(list_of_p_lineage)  ──► recomputed_union

   compare recomputed_union  vs  datom_get_lineage(conn_C, "C", depth="source")
```

This is a documented recipe, not a function. The caller supplies the correct
conn per parent project.

### Module map

| File | Change |
|---|---|
| `R/lineage.R` | Remove `datom_validate_lineage()`. Add exported `datom_parent()` and exported `datom_lineage_union()` (promoted from `.datom_lineage_union()`). Remove/retire `.datom_lineage_result()`, `.datom_lineage_diff()` (validator-only). |
| `R/read_write.R` | Remove the parent-enrichment block in `datom_write()`. Add parent validation + source_lineage derivation. Record lean parent entries. Replace the public `source_lineage` parameter with an internal `.source_lineage` (used only by `datom_sync()`). |
| `R/sync.R` | Update the imported-table write call to pass `.source_lineage` instead of `source_lineage`. |
| `R/utils-sha.R` | Add `.datom_validate_parents()` mirroring `.datom_validate_source_lineage()`. |
| `R/query.R` | Update roxygen for `datom_get_parents()` / `datom_get_lineage()` to state parent entries include `data_sha`. |
| `NAMESPACE` | Add `datom_parent`, `datom_lineage_union`; remove `datom_validate_lineage`. (roxygen-generated.) |
| `_pkgdown.yml` | Add the two new exports to the reference index; remove `datom_validate_lineage`. |
| `NEWS.md` | Record the removal, the two new exports, and the `parents` contract change. |
| `vignettes/source-lineage.Rmd` | Rewrite the validation section to teach the composable recompute recipe. |
| `dev/engineering-notes.md`, `dev/datom_pathways.md`, `dev/datom_specification.md`, `dev/README.md` | Update entries that describe/reference `datom_validate_lineage`. |
| `dev/e2e-solo-lineage.R`, `dev/e2e-solo-s3.R` | Replace the `datom_validate_lineage()` calls with the recompute recipe (these scripts call the function and would otherwise break). |
| `tests/testthat/` | New `test-parent.R`; rewrite parent tests in `test-read-write.R`; remove the validator tests in `test-query.R`; add union-helper tests. |

## Components and Interfaces

### 1. `datom_parent(conn, table, version)` — new export (R/lineage.R)

Resolves a parent against a single project connection and returns a
pure-data record.

```r
#' Declare a parent for lineage
#' @param conn A datom_conn scoped to the parent's project store.
#' @param table Parent table name (single non-empty string).
#' @param version Parent version (metadata_sha; single non-empty string).
#' @return A list with source, table, version, data_sha, source_lineage.
#' @export
#' @examples
#' \dontrun{
#'   p <- datom_parent(conn, "dm", "v_dm_9f3")
#' }
datom_parent <- function(conn, table, version) { ... }
```

The example is `\dontrun{}` because it needs a live conn + storage read and
would otherwise trip the fail-closed test/network guard under R CMD check
(Req 10.9).

Optional (Req note, not required): emit a soft `cli::cli_warn()` when a
parent's snapshot has a `NULL`/absent `source_lineage`, since that is a
silent lineage gap for an audit-focused record. Left as an optional
enhancement.

Behavior (Req 1, 2, 3, 6):
1. Validate args:
   - `if (!inherits(conn, "datom_conn")) cli::cli_abort(...)` (Req 1.2, 3.6).
   - `.datom_validate_name(table)` (Req 1.3).
   - `version` must be a single non-empty string (Req 1.4).
   Each failure aborts before any store read.
2. Build key `paste0(table, "/.metadata/", version, ".json")` and read via
   `.datom_storage_read_json(conn, key)` wrapped in `tryCatch`:
   - On error, abort distinguishing "not found / unreadable" with a message
     naming `table`, `version`, and `conn$project_name` (Req 2.3, 2.4, 1.6).
3. Extract `data_sha`:
   - If missing or empty, abort naming the missing field (Req 1.8, 2.5).
4. Capture `source_lineage <- snap$source_lineage %||% NULL` (Req 1.9, 1.10).
5. Assemble and return:
   ```r
   list(
     source        = conn$project_name,
     table         = table,
     version       = version,
     data_sha      = snap$data_sha,
     source_lineage = source_lineage
   )
   ```
   No conn retained; the return is plain nested lists/atomics, so it is
   serializable (Req 1.11-1.14, 3.4, 3.5, 6.1, 6.4).

Note (Req 6.4): the signature has no `data_sha` parameter, so a caller
cannot supply or override it — this is the audit invariant, verifiable via
`formals(datom_parent)`.

Error taxonomy (all `cli::cli_abort`, no Parent_Record returned):
| Condition | Message intent |
|---|---|
| conn not a datom_conn | invalid connection |
| table invalid | (delegated to `.datom_validate_name`) |
| version invalid | invalid version |
| snapshot read fails / not found | `parent {table}@{version} not found in project {conn$project_name}` |
| snapshot readable, no data_sha | snapshot missing data_sha |

The "not found" vs "unreadable" distinction (Req 2.3 vs 2.4): the storage
layer aborts on missing keys and on transport errors alike. The design reads
once and, in the abort handler, surfaces the underlying condition message as
context while leading with the not-found phrasing keyed on
`{table}@{version}`. A finer split (existence check then read) is optional
and not required to satisfy the acceptance criteria, which allow a single
"could not be read" error for the unreadable case.

### 2. `datom_lineage_union(lineages)` — new export (R/lineage.R)

Promotes the existing internal `.datom_lineage_union()` to a documented
public function. Same algorithm, public contract.

```r
#' Union and deduplicate source_lineage lists
#' @param lineages A list of source_lineage lists (each a list of entries
#'   with project, table, version_sha). NULL entries are treated as empty.
#' @return A deduplicated list of source_lineage entries.
#' @export
datom_lineage_union <- function(lineages) { ... }
```

Behavior (Req 8):
- Flatten the input lists; dedup key is
  `paste(project, table, version_sha, sep = "\t")` (Req 8.2).
- Empty input or all-empty lists return `list()` (Req 8.3).
- Retained entries are returned unchanged (Req 8.4).
- Tolerate `NULL` members in `lineages` (a parent may have
  `source_lineage = NULL`); treat as an empty contribution.

Implementation reuses the current body of `.datom_lineage_union()`
(`purrr::flatten` + `!duplicated(keys)`), with an added `purrr::compact()` /
NULL-guard so `NULL` parent lineages do not break `flatten`.

### 3. `.datom_validate_parents(parents)` — new internal (R/utils-sha.R)

Mirrors `.datom_validate_source_lineage()` in structure and error style.

```r
#' @keywords internal
.datom_validate_parents <- function(x) {
  if (is.null(x)) return(invisible(TRUE))
  # unnamed list of entry lists (Req 7.1, 7.3)
  # each entry: list with source, table, version, data_sha as single
  #   non-empty strings; identify first invalid entry by index (Req 7.2, 7.4)
  # if entry$source_lineage non-null/non-empty, validate via
  #   .datom_validate_source_lineage(entry$source_lineage) (Req 7.5)
  invisible(TRUE)
}
```

Rejections use `cli::cli_abort` and name the offending entry position and
field, matching the existing helper's message conventions.

### 4. `datom_write()` changes (R/read_write.R)

Replace the current parent-handling section. New sequence inside
`datom_write()` (after the `!is.data.frame(data)` and `.datom_validate_name`
checks, before role/path guards):

```r
if (!is.null(parents)) {
  .datom_validate_parents(parents)                     # Req 7
  # derive the table's source_lineage from parents     # Req 5.1
  parent_lineages <- lapply(parents, function(p) p$source_lineage)
  source_lineage <- datom_lineage_union(parent_lineages)
  # record lean parent edges only                       # Req 5.3, 5.4
  parents <- lapply(parents, function(p) list(
    source   = p$source,
    table    = p$table,
    version  = p$version,
    data_sha = p$data_sha
  ))
}
```

Removed:
- The entire enrichment block that read `{p$table}/.metadata/{p$version}.json`
  to add `data_sha` (Req 4.3, 4.4).
- The mandate branch `if (!is.null(parents) && is.null(source_lineage)) abort`
  — no longer needed, since the union is derived (Req 5.7).

`source_lineage` parameter contract (Req 5.7, 5.8): the public
`source_lineage` parameter is **removed** to avoid a silently-discarded
argument. Derived writes always derive `source_lineage` from the parents'
union. An internal dotted `.source_lineage` argument (matching the existing
`.table_type` / `.original_file_sha` convention) carries the imported
self-entry lineage from `datom_sync()`; `R/sync.R` is updated to pass
`.source_lineage`. On the derived path `.source_lineage` is unused.

`.datom_validate_source_lineage()` is still called for the imported path via
`.source_lineage`; when parents are supplied, validation of the derived union
is implicit (it is produced by `datom_lineage_union` from already-validated
parent entries).

Downstream unchanged: `.datom_build_metadata(..., parents = parents,
source_lineage = source_lineage, ...)` receives the lean parents and derived
lineage; `.datom_compute_metadata_sha()`, `.datom_write_metadata_local()`,
`.datom_push_metadata_s3()`, and the local->git->storage ordering are
untouched (Req 5.2, 5.5). Because `parents` and `source_lineage` both feed
the metadata SHA, the recorded shape change alters `metadata_sha` relative to
`main` — intended and acceptable pre-release.

### 5. Reads (R/query.R)

No behavioral change to `datom_get_parents()` / `datom_get_lineage()`; the
recorded `parents[]` now includes `data_sha`, so:
- Update `datom_get_parents()` roxygen `@return` to list
  `source, table, version, data_sha` (Req 9.3).
- `datom_get_lineage(depth = "source")` already returns
  `metadata$source_lineage` (Req 9.4).

### 6. Removal of `datom_validate_lineage()` (R/lineage.R)

Delete the exported function and its validator-only helpers
`.datom_lineage_result()` and `.datom_lineage_diff()`. Keep the union logic
(now `datom_lineage_union()`). Update:
- `NAMESPACE` (roxygen regeneration removes the export) (Req 9.1, 9.2).
- `_pkgdown.yml` reference index: remove `datom_validate_lineage`, add
  `datom_parent`, `datom_lineage_union` (Req 9.2, 10.7).
- `dev/engineering-notes.md`: revise the two entries that describe
  `datom_validate_lineage()` (the "separate from datom_validate()" entry and
  the "walker invariant" entry) to reflect the composable recipe.
- `dev/datom_pathways.md`, `dev/datom_specification.md`, `dev/README.md`:
  update stale references.
- `dev/e2e-solo-lineage.R`, `dev/e2e-solo-s3.R`: these **call**
  `datom_validate_lineage()` and will break; replace with the recompute
  recipe (`datom_get_parents` + per-parent `datom_get_lineage` +
  `datom_lineage_union`, then compare).
- `NEWS.md`: record removal + the two new exports + the `parents` contract
  change.
- `vignettes/source-lineage.Rmd`: rewrite the "Validating lineage
  consistency" section (it calls and explains the function) to the composable
  recipe. It is `eval = FALSE`, so it will not fail R CMD check, but a CRAN
  vignette must not demo a nonexistent function.
- Replace/remove any roxygen `@seealso` / `\link{datom_validate_lineage}`
  cross-references to avoid broken-link R CMD check warnings.
- Remove the validator cases in `tests/testthat/test-query.R` (the tests
  live there, not in a `test-lineage.R`, which does not exist); retain/relocate
  any union assertions to the `datom_lineage_union` tests.

### 7. Documented recipe (roxygen example, R/lineage.R or a vignette)

Ship as an `@examples` block on `datom_lineage_union()` and/or a short
section in a lineage vignette (Req 9.5, 9.6):

```r
# Recompute a derived table's source_lineage from its parents.
# One connection per project; never one conn across stores.
parents <- datom_get_parents(conn_C, "C")
conns <- list(A = conn_A, B = conn_B)   # keyed by parent$source

parent_lineages <- lapply(parents, function(p) {
  datom_get_lineage(conns[[p$source]], p$table,
                    version = p$version, depth = "source")
})
recomputed <- datom_lineage_union(parent_lineages)

declared <- datom_get_lineage(conn_C, "C", depth = "source")
# compare recomputed vs declared (e.g. setdiff on the composite key)
```

## Data Models

### Parent_Record (returned by `datom_parent()`, in memory)

```r
list(
  source         = "study001",       # = parent conn$project_name
  table          = "dm",
  version        = "v_dm_9f3",        # metadata_sha
  data_sha       = "d_dm_aaa",        # authoritative, from parent snapshot
  source_lineage = list(             # captured; NULL if absent
    list(project = "study001", table = "dm", version_sha = "d_dm_aaa")
  )
)
```

### Recorded_Parent_Entry (persisted in derived table metadata)

```json
{ "source": "study001", "table": "dm", "version": "v_dm_9f3",
  "data_sha": "d_dm_aaa" }
```
No `source_lineage` inside parent entries (Req 5.4).

### Derived table metadata (excerpt, e.g. C from A + B)

```json
{
  "data_sha": "d_C_123",
  "table_type": "derived",
  "parents": [
    { "source": "study001", "table": "dm", "version": "v_dm_9f3",
      "data_sha": "d_dm_aaa" },
    { "source": "labdata",  "table": "ex", "version": "v_ex_7c1",
      "data_sha": "d_ex_bbb" }
  ],
  "source_lineage": [
    { "project": "study001", "table": "dm", "version_sha": "d_dm_aaa" },
    { "project": "labdata",  "table": "ex", "version_sha": "d_ex_bbb" }
  ]
}
```

`source_lineage` is the dedup union of the parents' captured lineages,
computed by `datom_write()` (Req 5.1, 5.2).

## Error Handling

| Site | Condition | Handling |
|---|---|---|
| `datom_parent` | invalid conn/table/version | abort before any read (Req 1.2-1.4) |
| `datom_parent` | snapshot not found / unreadable | abort naming table@version + project (Req 2.3, 2.4) |
| `datom_parent` | snapshot missing data_sha | abort naming field (Req 1.8, 2.5) |
| `.datom_validate_parents` | named list / malformed entry / bad field | abort naming first bad entry+field; no write (Req 7) |
| `datom_write` | parent entry lacks data_sha | caught by `.datom_validate_parents`; error points to `datom_parent()` (Req 4.2) |
| `datom_lineage_union` | NULL/empty members | treated as empty; returns `list()` for empty input (Req 8.3) |

All aborts use `cli::cli_abort`; nothing partially writes because validation
and derivation occur before the local->git->storage pipeline begins.

## Correctness Properties

### Property 1: data_sha fidelity
A Parent_Record's `data_sha` always equals the parent snapshot's `data_sha`;
no code path or parameter lets a caller influence it
(`formals(datom_parent)` has no `data_sha`).
**Validates: Requirements 6.1, 6.4**

### Property 2: union derivation
A derived table's recorded `source_lineage` equals `datom_lineage_union()` of
its parents' `source_lineage`, deduplicated by {project, table, version_sha}.
**Validates: Requirements 5.1**

### Property 3: lean parent entries
Every Recorded_Parent_Entry contains exactly `source, table, version,
data_sha` and no `source_lineage`.
**Validates: Requirements 5.3, 5.4**

### Property 4: union algebra
`datom_lineage_union()` is order-independent and idempotent: permuting inputs
yields the same set, `union(union(x)) == union(x)`, and empty input yields
`list()`.
**Validates: Requirements 8.2, 8.3, 8.4**

### Property 5: all-or-nothing construction
`datom_parent()` either returns a complete five-field record or aborts; it
never returns a partial record.
**Validates: Requirements 1.12, 2.2**

### Property 6: one conn per project
No exported function accepts more than one connection; a parent is bound to
its conn only at construction.
**Validates: Requirements 3.5, 4.5**

## Testing Strategy

All tests mock the storage dispatch layer (`.datom_storage_read_json`,
`.datom_storage_write_json`) and use `mock_datom_conn()`; the fail-closed
guard in `setup.R` ensures no real egress (Req 10.4, 10.5).

New `tests/testthat/test-parent.R` (`datom_parent`):
- resolves data_sha + source_lineage from a mocked snapshot; `source` equals
  conn$project_name; return excludes any conn; is serializable
  (`jsonlite::toJSON` round-trip) — Req 1, 6.
- errors: non-conn arg; invalid table; invalid version; snapshot not found;
  snapshot missing data_sha — Req 1, 2.
- `formals(datom_parent)` has no `data_sha` — Req 6.4.
- cross-project: two `mock_datom_conn()` with different `project_name` and
  distinct mocked stores; a parent built from each carries the right
  `source`; a read for the "wrong" project store would error (guard) — Req
  3, 10.6.

`test-read-write.R` (rewrite parent cases):
- `datom_write` with resolved `datom_parent()` records: records lean
  `parents[]` (4 fields, no source_lineage) and a derived `source_lineage`
  equal to the union — Req 4, 5.
- rejects a raw `list(source, table, version)` lacking data_sha with an error
  naming `datom_parent()` — Req 4.2.
- supplying `source_lineage` alongside parents: derived union wins — Req 5.7.
- no enrichment: mock so that any `.datom_storage_read_json` of a parent
  snapshot during write would fail; write still succeeds (proves enrichment
  removed) — Req 4.3.
- NULL parents: no parents recorded, source_lineage path unchanged — Req 5.6.

`datom_lineage_union` unit tests (relocate from lineage tests):
- dedup by {project, table, version_sha}; empty-in -> empty-out; NULL members
  tolerated; fields preserved — Req 8.

Removal:
- delete the `datom_validate_lineage` cases in `tests/testthat/test-query.R`;
  confirm no references remain (grep across R, tests, vignettes, dev) — Req
  9.1, 9.2.

Quality gates: `devtools::test()` WARN 0; ASCII + <=80 col lint clean;
roxygen + `_pkgdown.yml` updated so `pkgdown::build_site()` has zero missing
topics — Req 10.1-10.3, 10.7, 10.8.

## Requirements Traceability

| Requirement | Design element |
|---|---|
| 1 Parent construction | `datom_parent()` behavior 1-5 |
| 2 Fail-fast | `datom_parent()` error taxonomy |
| 3 Cross-project first-class | `datom_parent()` source derivation; two-mock-store tests |
| 4 Writer accepts resolved records | `datom_write()` validation; enrichment removed |
| 5 Derived lineage + lean shape | `datom_write()` union derivation + Recorded_Parent_Entry; data models |
| 6 data_sha authoritative | `datom_parent()` (no data_sha param); write persists record value |
| 7 Parent structural validation | `.datom_validate_parents()` |
| 8 Union helper | `datom_lineage_union()` |
| 9 Composable inspection replaces validator | removal + reads + recipe |
| 10 Package quality | testing strategy + NAMESPACE/pkgdown/roxygen tasks |

## Resolved Design Decisions (from spec review)

- **`source_lineage` parameter:** removed from the public `datom_write()`
  signature; replaced by an internal dotted `.source_lineage` used only by
  `datom_sync()`. This avoids a silently-discarded public argument (the
  reviewer's footgun). `R/sync.R` updates its call site accordingly.
- **Validator removal confirmed:** removing `datom_validate_lineage()` is an
  intentional public-API removal, signed off. The one-call cross-project
  validator is replaced by `datom_lineage_union()` + the documented recipe.
- **Cleanup surface:** the validator is referenced beyond code — `NEWS.md`,
  `vignettes/source-lineage.Rmd`, `dev/e2e-solo-lineage.R`,
  `dev/e2e-solo-s3.R`, `dev/datom_pathways.md`, `dev/datom_specification.md`,
  `dev/README.md`, `dev/engineering-notes.md`, and possible roxygen
  `@seealso`/`\link`. All are enumerated in the removal task; the e2e scripts
  actively call it and must be reworked to the recipe.
- **Test location:** validator tests are in `tests/testthat/test-query.R`
  (there is no `test-lineage.R`).
