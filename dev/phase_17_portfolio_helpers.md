# Phase 17: Portfolio Helpers (`datom_summary`, `datom_projects`)

**Status**: Active -- Chunk 1 complete; Chunk 2 next
**Branch**: `phase/17-portfolio-helpers` (created 2026-04-29)
**Depends on**: Phase 16 Chunk 4 closed (PR #9 merged 2026-04-29).
**Blocks**: Phase 16 Chunk 5 (Article 8 audit/reproducibility uses both helpers).

## Progress log

- **2026-04-29**: Phase activated. Branch cut from main `cb17766`. Phase doc registered in `dev/README.md`.
- **2026-05-01**: Chunk 1 complete. `datom_summary()` + `print.datom_summary()` shipped in `R/summary.R`. 11 `test_that` blocks (24 expectations) in `tests/testthat/test-summary.R`. `_pkgdown.yml` updated. Test suite: 1393 PASS / 0 FAIL (was 1369; +24 expectations from the new tests). pkgdown reference index builds clean.

---

## Goal

Add two small portfolio-level helpers to the public API:

1. **`datom_summary(conn)`** -- one-liner overview of the currently connected project. Aggregates the manifest into a print-friendly structured value: project name, role, backend/root/prefix, table count, total versions, latest activity timestamp.
2. **`datom_projects(x)`** -- list of all projects registered in the governance repo. Accepts either a `datom_conn` (uses its gov clone / gov_client) or a `datom_store` (for users who want to enumerate the portfolio before connecting to any one project). Returns a data frame: name, data_backend, data_root, registered_at.

These are the manager- and audit-facing helpers Phase 16 Chunk 5 (Articles 8 + 9) needs. Splitting them out of Phase 16 keeps that phase pure-docs.

Anything beyond these two (e.g. `datom_diff`, `datom_reproduce`, table-level summaries, governance-wide quotas) is **out of scope**; defer to its own phase.

---

## Context

### Why now

Article 7 (`governing-a-portfolio.Rmd`, just merged) demonstrates the gov registry by calling `fs::dir_ls(gov_clone/projects)`. That works but reads as a workaround. Article 8 (audit & reproducibility) needs to do something stronger -- aggregate across projects, point at last activity timestamps, name the data backend per project. That requires a real listing helper.

`datom_summary()` is the single-project peer of `datom_projects()`: useful in its own right (a one-line "where am I" print after building a conn), and the natural narrative bridge from Article 7's "here's my one project" to Article 8's "here are my N projects."

### Why scope is just these two

Two reasons:

- **Article 8 needs them and nothing else.** Article 8's narrative is regulator request -> pinned reads -> validation across the portfolio. The shape of those calls is clear from the existing API; only `datom_projects()` is missing as a top-level entry. `datom_summary()` is small, parallel, and tightens Article 7's mid-article transitions enough to be worth shipping in the same phase.
- **Other helper ideas are speculative.** `datom_diff` (compare two versions) needs a design discussion about what "diff" means for parquet; `datom_reproduce` overlaps with dpbuild's territory. Both are real, but neither is needed for Phase 16; both deserve their own phase planning.

### What both helpers read from

**`datom_summary(conn)`**: reads the same `.metadata/manifest.json` `datom_list()` already reads, plus the conn fields. No new storage IO contracts.

**`datom_projects(x)`**:
- Developer (conn with `gov_local_path`): reads `projects/*/ref.json` from the local gov clone. No network. Reflects the last `datom_pull_gov()`.
- Reader (conn or store with `gov_client`, no clone): reads `projects/*/ref.json` over the wire via `.datom_storage_read_json()` against the gov client. One read per project after a list-objects.
- Either way, the data the helper needs is already in `ref.json`'s `current` block + filesystem mtime / git log; no new persisted state.

---

## API design

### `datom_summary(conn)`

```r
datom_summary <- function(conn) { ... }
```

Returns an S3 object `datom_summary` with a print method. Internal structure:

```r
list(
  project_name    = "STUDY_001",
  role            = "developer",
  backend         = "s3",
  root            = "your-org-datom-data",
  prefix          = "study-001/",
  table_count     = 4L,
  total_versions  = 12L,        # sum across tables (from include_versions=TRUE manifest)
  last_updated    = "2026-04-29T10:23:00Z",
  remote_url      = "https://github.com/your-org/study-001-data"  # NULL for local-only or readers
)
```

Print form (concise, multi-line, no boxes):

```
-- datom project summary
* Project:    STUDY_001
* Role:       developer
* Backend:    s3 -- your-org-datom-data/study-001/
* Tables:     4 (12 versions total)
* Last write: 2026-04-29 10:23 UTC
* Remote:     github.com/your-org/study-001-data
```

Reader-role connections show `* Remote: <not visible to readers>` since data git URL is in `project.yaml`, which readers don't fetch.

### `datom_projects(x)`

```r
datom_projects <- function(x) { ... }
# x: a datom_conn OR a datom_store
```

Returns a data frame, one row per registered project. Columns:

| Column | Type | Source |
|---|---|---|
| `name` | character | directory name under `projects/` |
| `data_backend` | character | `ref.json$current$type` |
| `data_root` | character | `ref.json$current$root` |
| `data_prefix` | character | `ref.json$current$prefix` (NA if absent) |
| `registered_at` | character (ISO8601) | mtime of `projects/{name}/ref.json` (clone) or last-modified from object metadata (storage) |

Sort by `name`. No fancy filtering for v1 -- callers who want filters can `subset()` the result.

Failure modes:

- No gov clone and no gov client: hard error with an actionable message.
- A project folder lacks `ref.json`: warn and skip that row (corrupt registry entry shouldn't take down the listing).
- Network read fails for a single project (reader path): warn and skip.

### Internal helpers

The two helpers share a small lookup of "registered project names":

```r
.datom_gov_list_projects <- function(conn_or_store) {
  # returns a character vector of project names from
  # gov clone if available, else gov storage list-objects.
}
```

Lives in `R/utils-gov.R` next to the other gov helpers, tagged `# GOV_SEAM:` per the gov-seam contract.

---

## Chunks

| # | Content | Scope |
|---|---|---|
| 1 | `datom_summary()` impl + roxygen + print method + `R/summary.R` + tests | One file in R/, one in tests/. ~80 LoC + ~120 LoC tests. |
| 2 | `datom_projects()` impl + roxygen + `.datom_gov_list_projects()` helper + tests | Two helper files; ~120 LoC + ~150 LoC tests. |
| 3 | `_pkgdown.yml` reference + NEWS.md + phase completion | YAML + Markdown + delete phase doc. |

Chunks 1 and 2 are independent (no shared code beyond the gov-list helper, which Chunk 2 introduces). Chunk 3 is the closer.

---

## Acceptance criteria

1. `datom_summary()` exported, fully roxygen-documented, with a `print.datom_summary` method.
2. `datom_projects()` exported, accepts both `datom_conn` and `datom_store`, returns a data frame with the columns above.
3. Tests cover: developer + reader paths for both functions; empty registry; missing-`ref.json` skip; network-failure-per-project warn-and-skip (mocked).
4. `_pkgdown.yml` reference index lists both new exports.
5. `NEWS.md` gains a "Phase 17" entry naming both helpers.
6. `devtools::test()` green; total count up by ~12-18 from baseline 1369. Report final count in the closing commit message.
7. `R CMD check` 0E/0W, NOTE no worse than baseline.
8. Phase 16 Chunk 5 (Article 8) can call `datom_summary()` and `datom_projects()` without further changes.

---

## Invariants -- read before each chunk

- **No new storage formats.** Both helpers read existing JSON files; they do not introduce new persisted state.
- **Reader path must work without `GITHUB_PAT` for data**, but does require gov-side credentials (storage). This is the same contract as `datom_get_conn()` for readers.
- **No interactive prompts.** Helpers are scriptable.
- **Error messages name the actionable next step.** "No gov clone and no gov client" is not enough -- say "build a `datom_store` with `gov_repo_url` and rerun, or pass an existing developer `datom_conn`."

---

## Open items

- **`registered_at` source on the storage path**. For local backends, mtime of `ref.json` is fine. For S3, `LastModified` from `HeadObject` is the natural equivalent but adds N round-trips. Option: only populate `registered_at` for gov-clone callers; leave NA for storage-only readers, document that. Decide during Chunk 2.
- **Should `datom_summary()` show recent commits?** The five most recent commit messages from the data clone would be a strong audit signal. Cost: one git log call. Lean: no for v1 -- keep summary cheap; Article 8's audit narrative will lean on `datom_history()` for that detail.
- **Per-project size in `datom_projects()`?** Tempting (one row per project, plus a `bytes` column would be powerful). Cost: list-objects per project, potentially expensive. Lean: defer; can ship as opt-in `include_size = TRUE` later.

---

## Notes

This phase exists because Phase 16 Chunk 5 needs these helpers. It is not a "grab bag of utility functions" phase; the scope is narrowly the two helpers needed to write Article 8 honestly. Anything that creeps in beyond `datom_summary()` and `datom_projects()` should be split into its own phase.
