# Implementation Plan: datom-cv1 Canonical Hash & Three-SHA Identity

Issue [#72](https://github.com/amashadihossein/datom/issues/72). One task = one chunk = one
commit (code + tests + this file). Run full `devtools::test()` before each commit and record
the count in the commit message. Follow the read-before-writing discipline: trace the full call
chain in the named function AND its callers before editing.

## Overview

Bottom-up build so every commit leaves the suite green: the standalone reference plus the
`datom-cv1` engine (`.datom_column_kind()` / `.datom_hash_recourse()` / shared encoders /
`.datom_canonical_hash()`) first, then the three-SHA write-path wiring, read-time integrity,
the full-history dedup guard, the persisted column index, the exported table-contract checker,
the ingestion allowlist, the `file_sha` nomenclature sweep, the cross-cutting identity-contract
integration tests, and finally docs/NEWS and the acceptance-gate checks.

Testing uses the existing plain `testthat` (+ `mockery` + `withr`) stack — **no** property-based-
testing harness is added. The 17 correctness properties from the design are validated by
deterministic `testthat` tests over the enumerated edge-case fixtures (Requirement 16.1), each
tagged `Feature: datom-cv1, Property {n}`. The R gates (`devtools::test()`,
`R CMD check --as-cran`, `Rscript dev/datom_cv1_reference.R`) are executed by the maintainer/CI;
sub-agent verification in this environment is authoring the code and tests, not running R here.

## Tasks

- [x] 1. Canonical hash engine (`datom-cv1`) and reference implementation
  - [x] 1.1 Create `R/hashable.R` classifier and recourse map
    - Add internal `.datom_column_kind(x)` — the single supported-type classifier implementing
      the exact dispatch order (`bit64::integer64` → factor → `Date`/`IDate` → `POSIXct` →
      `difftime`/`hms` → `data.table::ITime` → `haven_labelled`/`labelled`/`labelled_spss`
      fall-through → other-classed refused → unclassed atomics → other-type refused); returns
      the kind tag (`"i64"`, `"chr"`, `"date"`, `"time"`, `"drtn"`, `"num"`) or `NULL`.
    - Add internal `.datom_hash_recourse(x)` — the single source of truth for recourse strings:
      returns `NULL` when `.datom_column_kind(x)` is non-`NULL`, else the canonical string for
      the first matching offender category. Implement all 9 recourse-map rows verbatim from the
      design Error Handling table, in the pinned detection order (`POSIXlt` before generic list;
      nested-data-frame list before generic list; class-specific `units`/`sfc`/`yearmon`/
      `yearqtr`/`chron` before the other-classed fallback; `complex`; `raw`; other-classed).
      Detection is `inherits()`/`typeof()`/`is.list()` only — add no new package dependency.
    - _Requirements: 2.2, 10.4, 11.1_
  - [x]* 1.2 Write unit tests for the classifier and recourse map
    - Each of the 9 offender categories returns its exact canonical string; every supported type
      returns `NULL` kind and `NULL` recourse; `haven_labelled` is treated as supported.
    - _Requirements: 2.2, 10.4, 11.1, 11.5_
  - [x] 1.3 Implement the shared numeric encoder and character encoder in `R/utils-sha.R`
    - One shared numeric encoder used by `num`/`date`/`time`/`drtn`:
      `writeBin(as.double(x), size = 8, endian = "little")`, canonicalize every `NaN` payload to
      one canonical `NaN`, convert `-0.0` → `+0.0`, preserve `NA_real_` as distinct from `NaN`.
    - Character encoder: one-byte-per-row NA mask (`0x01`/`0x00`) then each value `enc2utf8()`-ed
      and NUL-terminated; no Unicode normalization.
    - _Requirements: 2.3, 2.4, 2.13_
  - [x]* 1.4 Write property test for the numeric encoder
    - **Property 4: Numeric encoding semantics** (`0/0` == `NaN`, `-0` == `+0`, `NA_real_` !=
      `NaN`, no rounding / ULP difference differs)
    - **Validates: Requirements 2.3, 2.12, 2.13, 16.1**
  - [x]* 1.5 Write property test for the character encoder
    - **Property 5: Character encoding semantics** (`NA` vs `""` differ; NFC vs NFD differ),
      CJK fixture built via `intToUtf8()`
    - **Validates: Requirements 2.4, 16.1**
  - [x] 1.6 Implement `.datom_canonical_hash()` and the `.datom_compute_data_sha()` wrapper
    - `.datom_canonical_hash(data)` in `R/utils-sha.R`: zero I/O, no `as.data.frame()` / no
      coercion, no arrow; guards (`is.data.frame`, non-zero rows/cols); reads via `data[[i]]`,
      `names()`, `nrow()`/`ncol()`. All-offenders pre-scan via `.datom_hash_recourse()` aborting
      **once** listing every offender (design abort message verbatim, incl. the trailing `i`
      hint). Per-column digest `sha256(utf8(tag) || utf8(colname) || 0x00 || payload)` dispatched
      on `.datom_column_kind()`; final hash
      `sha256("datom-cv1" || f64le(nrow) || f64le(ncol) || concat(col_digest_hex...))`. Returns
      `list(data_sha, column_hashes)` (per-column digests computed once).
    - Rewrite `.datom_compute_data_sha(data)` as a thin wrapper `= .datom_canonical_hash(data)$data_sha`
      with the rev-7 signature and no `sort_columns`/`sort_rows` params (preserves the scalar
      contract for the `datom_sync()` self-lineage caller).
    - **In the same commit**, replace the sort-only tests in `test-utils-sha.R`: remove the two
      existing `sort_columns`/`sort_rows` tests and add positive assertions that a column reorder
      and a row reorder each change the hash. This is non-optional and must land here — removing
      the `sort_columns`/`sort_rows` params from `.datom_compute_data_sha()` makes the existing
      sort-only tests throw "unused argument", reddening the suite unless they are removed in the
      same commit (green-per-commit).
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.1, 2.2, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 3.1, 3.5, 11.2, 11.3, 11.4_
  - [x]* 1.7 Write property tests for the canonical hash engine
    - **Property 1: Container-class and attribute independence** — **Validates: Requirements 1.4**
    - **Property 2: Determinism** — **Validates: Requirements 1.7**
    - **Property 3: Type-tag disambiguation** (`"1"` vs `1`; all-`NA` logical vs character) — **Validates: Requirements 2.2, 16.1**
    - **Property 6: integer64 verbatim encoding** — **Validates: Requirements 2.5**
    - **Property 7: Factor levels/orderedness not identity** — **Validates: Requirements 2.6**
    - **Property 8: Temporal encoding semantics** (tzone equal; secs vs mins differ; ITime==hms) — **Validates: Requirements 2.7, 2.8, 2.9**
    - **Property 9: Labelled columns strip to base type** — **Validates: Requirements 2.10**
    - **Property 10: Row and column order are significant** — **Validates: Requirements 3.2, 3.3**
    - Plus guard tests: non-frame aborts; zero-row and zero-col abort. _Requirements: 1.6_
  - [x] 1.9 Create the standalone reference implementation `dev/datom_cv1_reference.R`
    - The reference script already exists verbatim in issue #72's embedded code block — lift it
      verbatim rather than retyping it (retyping risks byte-layout drift from the pinned spec).
    - Base R + `digest` only, zero I/O, no sort args; identical byte layout to
      `.datom_canonical_hash()`; pure ASCII with all Unicode fixtures built via `intToUtf8()`;
      includes a self-test that exits 0 and prints the portable golden constants.
    - Run the pure-ASCII check on the lifted file:
      `all(as.integer(readBin(f, "raw", file.size(f))) < 128L)` must be TRUE.
    - _Requirements: 15.1, 15.2, 15.3_
  - [x]* 1.10 Write golden-vector, NIST, parity, and metadata_sha golden tests
    - Write the golden-vector tests (numeric; int/lgl/dbl parity; character incl. NFC/NFD and CJK;
      factor; Date variants; POSIXct tzone equality; difftime secs vs mins; hms vs ITime;
      integer64 incl. NaN-bit-space; one mixed data.frame; one `.datom_compute_metadata_sha()`
      golden) with the expected hex constants as clearly-marked `<PENDING-GOLDEN>` placeholders.
      R is unavailable in the authoring environment, so the golden hex cannot be computed during
      coding; the placeholders MUST FAIL LOUDLY (e.g. `expect_identical(actual, "<PENDING-GOLDEN>")`
      or an explicit `stop()` guard) — never `skip()` — until a maintainer fills them in.
    - The NIST SHA-256 `"abc"` vector
      (`ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`) is a fixed public
      constant and IS hard-coded now (not a placeholder). Add the ASCII assertion on
      `dev/datom_cv1_reference.R`.
    - **MAINTAINER STEP (requires R):** run `Rscript dev/datom_cv1_reference.R` on the reference
      platform, paste the printed golden constants into the tests replacing the `<PENDING-GOLDEN>`
      placeholders, and commit. Do NOT introduce a Python (or any third) implementation to
      bootstrap the constants — the standalone R reference script is the single golden source.
    - **Property 11: Reference-implementation parity** over the full fixture set (skipped when
      `dev/datom_cv1_reference.R` is absent) — **Validates: Requirements 15.1, 15.4, 2.1, 2.11**
    - _Requirements: 15.5, 15.6, 15.7_

- [x] 2. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
  - MAINTAINER STEP (requires R, see task 1.10): run `Rscript dev/datom_cv1_reference.R` on the
    reference platform and replace the `<PENDING-GOLDEN>` placeholders in the golden-vector tests
    with the printed constants before this checkpoint can pass — the placeholders fail loudly by
    design and are not skippable.

- [ ] 3. Three-SHA metadata and write-path wiring
  - **All code sub-tasks are DONE and committed** (3.1, 3.2, 3.4, 3.5, 3.6). This parent stays
    unchecked solely because the deferrable `*` test 3.3 (Properties 13/14) is outstanding --
    the *behavior* is already covered by plain tests, but the tagged property versions are
    required before the PR merges. Do not redo 3.1-3.6.
  - [x] 3.1 Extend `.datom_build_metadata()` (in `R/read_write.R`) with the new fields
    - Add `hash_algo = "datom-cv1"` (always), `parquet_sha = NULL` (declared; set later by
      `datom_write()`), `column_hashes = NULL`, and `original_file_sha` included **only when
      non-NULL** (imported path sets it; derived path omits it entirely, not present-with-NULL).
    - _Requirements: 5.1, 5.2_
  - [x] 3.2 Update `.datom_compute_metadata_sha()` (in `R/utils-sha.R`) ordering and volatile set
    - Change `sort(names(semantic))` to `sort(names(semantic), method = "radix")`; set
      `volatile <- c("created_at", "datom_version", "parquet_sha", "column_hashes")`; keep
      hashing the JSON canonical form (never the R object).
    - _Requirements: 6.1, 7.1, 7.2, 7.3, 7.4_
  - [ ]* 3.3 Write property tests for `metadata_sha`
    - **Property 13: metadata_sha locale determinism** (`LC_COLLATE=C` vs `en_US.UTF-8`; skip if
      locale unavailable) — **Validates: Requirements 6.1, 6.2**
    - **Property 14: metadata_sha volatile-field membership** (`parquet_sha`/`column_hashes`
      invariant; `original_file_sha`/`hash_algo` significant) — **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 14.4**
  - [x] 3.4 Refactor `.datom_has_changes()` to return `list(change_type, current)`
    - Return the already-read `current` metadata (or `NULL` for a brand-new table → `"full"`);
      update the second caller `.datom_sync_metadata()` (in `R/utils-sha.R`) to read `$change_type`.
    - Update any existing tests of `.datom_has_changes()` (and its string-return expectations) in
      the same commit so the return-shape change lands green.
    - This is change-detection plumbing (the `.datom_has_changes()` return-shape refactor + caller
      updates), not the S-scenario behaviors; the S1–S6 acceptance behaviors are delivered by
      task 3.5 and the 12.x integration tests. What this refactor actually enables is reuse of the
      already-read `current` for the `metadata_only` `parquet_sha` carry-forward (Requirement 5.6)
      and the `none` re-derivation detection (Requirement 9.6) — the only clauses tagged here.
    - _Requirements: 5.6, 9.6_
  - [x] 3.5 Revise `datom_write()` order and `parquet_sha` determination
    - New order: (1) ref guard, (2) `.datom_canonical_hash(data)` → `data_sha` + `column_hashes`
      (all-offenders abort fires here, before any mutation), (3) write temp parquet + `size_bytes`
      + `new_parquet_sha = digest(file = tmp)`, (4) build metadata + `metadata_sha`, (5)
      `.datom_has_changes()` → `{change_type, current}`, (6) `none` → no-op return, (7) determine
      `parquet_sha` — `metadata_only` reuses `current$parquet_sha` (skip upload); `full` + key
      absent uploads and uses `new_parquet_sha`; `full` + key present (revert-to-older) reuses the
      most recent history `parquet_sha` for this `data_sha` without overwriting (legacy fallback:
      upload `new_parquet_sha`), (8) set `meta$parquet_sha` before `.datom_write_metadata_local()`,
      (9) keep the parquet upload **after** the git push (load-bearing serialization point).
    - _Requirements: 5.3, 5.4, 5.5, 5.6, 5.7, 9.2, 9.3, 9.4, 9.5, 9.6_
  - [x]* 3.6 Write unit tests for `datom_write()` `parquet_sha` branches
    - Cover full+absent (upload, new sha), full+present/revert (reuse history sha, no overwrite),
      metadata_only (carry `current$parquet_sha`, no upload), and `none` no-op.
    - _Requirements: 5.4, 5.5, 5.6, 9.6_

- [x] 4. Read-time integrity verification
  - [x] 4.1 Extend `.datom_resolve_version()` to return `list(data_sha, parquet_sha)`
    - Both branches return the list (NULL-version → `current`; history-lookup → resolved entry;
      `parquet_sha` may be `NULL`/`""` for pre-cv1). Update the `datom_read()` call site to thread
      `resolved$data_sha` and `resolved$parquet_sha`.
    - _Requirements: 8.1, 8.2_
  - [x] 4.2 Add the integrity check to `.datom_read_parquet()`
    - Signature gains `parquet_sha = NULL`; after download and before `arrow::read_parquet()`,
      when `parquet_sha` is non-empty compute `actual = digest(file = tmp)` and abort with the
      verbatim tamper message (naming table, key, expected + actual) on mismatch; when
      absent/empty (pre-cv1) skip silently and read succeeds.
    - _Requirements: 8.1, 8.3, 8.4_
  - [x]* 4.3 Write unit tests for read-time integrity
    - Corrupt stored byte → tamper abort before parse; legacy metadata without `parquet_sha` →
      read succeeds; expected matches → read succeeds.
    - _Requirements: 8.3, 8.4_

- [x] 5. Full-history `metadata_sha` dedup guard
  - [x] 5.1 Replace the latest-only guard in `.datom_write_metadata_local()`
    - Scan the entire history with `purrr::some(history, ~ identical(.x$version %||% "",
      metadata_sha))` (O(history), early exit); append only when absent; always write
      `metadata.json` (current pointer). Persist `parquet_sha` in the appended `version_history`
      entry alongside the existing `original_file_sha`.
    - _Requirements: 5.7, 12.1, 12.2, 12.3, 12.4_
  - [x]* 5.2 Write property test for full-history dedup
    - **Property 17: Full-history version dedup** — **Validates: Requirements 12.1, 12.2, 12.3, 12.4**

- [x] 6. Persisted column index
  - [x] 6.1 Persist `column_hashes` as an ordered array in `metadata.json`
    - Thread the `column_hashes` from `.datom_canonical_hash()` through `.datom_build_metadata()`
      / `datom_write()` into `metadata.json` as an ordered array of `{name, sha}` in table column
      order, with no truncation (computed once, reused for both `data_sha` and the index).
    - _Requirements: 14.1, 14.2_
  - [x]* 6.2 Write property test for the column index
    - **Property 12: Column index integrity** (order matches `names(data)`; each `sha` equals the
      standalone per-column digest; `data_sha` recomputable from `column_hashes` + dims;
      single-column change flips exactly that entry) — **Validates: Requirements 14.1, 14.2, 14.3, 14.5**

- [x] 7. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Table-contract checker `datom_check_hashable()`
  - [x] 8.1 Export `datom_check_hashable()` in `R/hashable.R` and list it in `_pkgdown.yml`
    - Map every column through `.datom_hash_recourse()`; return (invisibly) a data frame with
      `column`, `class` (collapsed `class(x)` or `typeof(x)`), `status` (`"ok"`/`"unsupported"`),
      `recourse` (`NA` when ok). Print a cli `✓` summary when clean, else one `✗` per offender
      with its recourse. Add runnable roxygen examples requiring no network/store; regenerate docs;
      add to `_pkgdown.yml` reference.
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
  - [x]* 8.2 Write recourse test-pairs and table-contract tests
    - **Property 15: Table-contract recourse is single-sourced and complete** — for every
      recourse-map row, `datom_check_hashable()` flags the column AND `.datom_canonical_hash()`
      aborts with the identical string; a multi-offender table aborts exactly once naming all;
      applying each recourse makes the fixture hashable; a clean table reports all `ok`; a refusal
      leaves no git/storage/manifest state.
    - **Validates: Requirements 10.4, 11.1, 11.2, 11.4, 11.5**

- [x] 9. Ingestion allowlist for `datom_sync`
  - [x] 9.1 Add `.datom_import_formats` and enforce it across the sync path (`R/sync.R`)
    - Define the named constant (`csv, tsv, txt, psv, parquet, sas7bdat, xpt, sav, zsav, por,
      dta, xls, xlsx`); gate `.datom_import_file()` on `tolower(format)` with the verbatim
      allowlist abort; make `datom_sync_manifest()` flag non-allowlisted files up front with
      `status = "unsupported_format"` (still processing allowlisted siblings); surface the same
      recourse in the `datom_sync()` `error` column for such rows.
    - _Requirements: 13.1, 13.2, 13.3, 13.4_
  - [x]* 9.2 Write ingestion-allowlist tests
    - **Property 16: Ingestion allowlist enforcement** — each allowlisted extension dispatches to
      the expected (stubbed) reader; `.json`/`.rds`/`.xml` abort with the recourse;
      `datom_sync_manifest()` marks an `.rds` `unsupported_format` and still processes a sibling
      `.csv`.
    - **Validates: Requirements 13.1, 13.2, 13.4, 16.3**

- [ ] 10. `file_sha` nomenclature rename sweep
  - [ ] 10.1 Eliminate the bare `file_sha` token across `R/`/`man/`, update tests, and run the grep gate
    - Rename `.datom_compute_file_sha()` → `.datom_compute_original_file_sha()`; update
      `datom_sync_manifest()` (local var + returned column), `datom_sync()` (`required_cols` +
      `tbl_file_sha`), `.datom_update_manifest_entry()` param, and `R/query.R`
      `.datom_status_input_files()` (call + local var). Regenerate `man/` via
      `devtools::document()` so the `.Rd` page renames.
    - **In the same commit**, update the tests referencing the old name/column: the rename
      changes `datom_sync_manifest()`'s returned column and `datom_sync()`'s `required_cols`,
      and `test-sync.R` builds manifest fixtures with the `file_sha` column that error until
      those tests are updated — so this must land here (green-per-commit) and is non-optional.
    - As part of this same commit, run the nomenclature grep gate and assert
      `grep -rn "file_sha" R/ man/ vignettes/` matches only `original_file_sha`/`parquet_sha`.
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [ ] 11. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 12. Identity-contract integration tests (local backend)
  - [ ]* 12.1 Write the S1 skip-before-parse test
    - Stub `.datom_import_file()`; assert zero calls when the manifest reports the input
      `unchanged`.
    - _Requirements: 9.1, 16.5_
  - [ ]* 12.2 Write the S2 / S5 / S6 classification tests
    - S2 full (byte + content change → upload at `name/{data_sha}.parquet`, new version); S5
      derived first write (`full`, addressed by `data_sha`, no `original_file_sha`); S6 identical
      re-derive (same `data_sha` + parents → `none`, no commit/upload/history).
    - _Requirements: 9.2, 9.5, 9.6, 16.5_
  - [ ]* 12.3 Write the S3 re-export loop and carry-forward test
    - Bytes change, content identical → `metadata_only`, no upload, `original_file_sha` recorded,
      `parquet_sha` carried forward; a subsequent scan reports `unchanged`.
    - _Requirements: 9.3, 16.5_
  - [ ]* 12.4 Write the S4 duplicate-version regression test
    - Syncing an older content-matching file appends no duplicate `version`; `datom_read(version=)`
      resolves without "ambiguous".
    - _Requirements: 9.4, 12.3, 16.5_
  - [ ]* 12.5 Write the parquet_sha integrity, revert-to-older, and provenance integration tests
    - Corrupt stored byte → tamper abort; legacy metadata lacking `parquet_sha` → read succeeds;
      revert-to-older content reuses the history `parquet_sha` without overwriting the stored
      object; `hash_algo == "datom-cv1"` and imported-path `original_file_sha` present after
      `datom_write()`. Whole suite runs under the fail-closed network guard.
    - _Requirements: 5.5, 8.3, 8.4, 16.5, 16.6_

- [ ] 13. Documentation, vignettes, and NEWS
  - [ ] 13.1 Rewrite `design-version-shas.Rmd` and `getting-started.Rmd`
    - Reframe around the three-SHA nomenclature and identity contract, with a "The datom table
      contract" section (framing, where-this-bites, the recourse table rendered from
      `.datom_hash_recourse()`, the ingestion allowlist) using `datom_check_hashable()` as the
      runnable entry point; record the identity decisions (int/dbl/lgl unify; tzone/factor
      levels/labels/NaN payloads/−0 not identity; NFC≠NFD; order significant, no sorting; doubles
      bit-exact) with rationale; scope the cross-language claim (guaranteed within R + renv);
      state the allowlist escape-hatch provenance tradeoff.
    - DECISION (recourse table): render it in an `eval = TRUE` chunk (a per-chunk override of the
      vignettes' global `eval = FALSE` default) that calls `datom_check_hashable()` /
      `.datom_hash_recourse()` — both pure, no network, no store — so the documented table is
      generated from the single-source recourse map and the doc and code cannot drift.
    - _Requirements: 17.1, 17.2, 17.3, 17.5_
  - [ ] 13.2 Update `NEWS.md`
    - Note that pre-release `data_sha` values change with no migration path; record the three
      deliberate narrowings (list/exotic columns refused with recourse; `datom_sync` allowlist
      only; internal `sort_columns`/`sort_rows` removed).
    - _Requirements: 17.4_

- [ ] 14. Acceptance-gate checks
  - [ ] 14.1 Run the static acceptance grep/gates
    - Confirm `grep -rn "sort_columns\|sort_rows" R/ tests/` is empty;
      `grep -rn "file_sha" R/ man/ vignettes/` matches only `original_file_sha`/`parquet_sha`;
      `grep -rn "as.data.frame" R/utils-sha.R` is empty; `datom_check_hashable` is in
      `_pkgdown.yml`. Note the maintainer/CI-run R gates (`R CMD check --as-cran`,
      `Rscript dev/datom_cv1_reference.R`, four-environment goldens) in the commit message.
    - _Requirements: 3.4, 4.3_

- [ ] 15. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 16. Spec completion
  - Harvest durable learnings (metadata fields + redefined `data_sha`/volatile set →
    `dev/datom_specification.md`; gotchas → `dev/engineering-notes.md`); update the
    `dev/README.md` Active Specs table; run the maintainer R gates and a `dev/dev-sandbox.R`
    E2E; PR with `Closes #72`. Specs persist — do not delete.

## Notes

- Tasks marked `*` are test/verification sub-tasks that MAY be deferred within the branch during
  development, but ALL are REQUIRED before the PR merges — several (the 4-environment goldens,
  reference parity, the S1–S4 regressions, and the recourse test-pairs) are named acceptance
  criteria in requirements/#72 and an MVP that skips them cannot merge. Tasks 1.8-folded (into
  1.6) and 10.2-folded (into 10.1) are NOT deferrable (they are required for the suite to compile
  in their own commit) and are therefore non-optional. Per the repo stack these "property" tests
  are deterministic `testthat` tests over enumerated fixtures — **not** a PBT harness.
- Any task that changes a function signature, return shape, or a data-frame column name MUST
  include the updates to existing tests that exercise it in the SAME commit — this is what
  green-per-commit actually requires.
- Each task references specific granular requirement clauses for traceability. Every requirement
  (1–17) and every correctness property (1–17) is covered by at least one task.
- The parquet upload stays after the git push in `datom_write()` (Task 3.5) — this ordering is
  load-bearing (git push is the serialization point) and must never be refactored.
- `.datom_column_kind()` is the single classifier and `.datom_hash_recourse()` the single
  recourse source; the hash gate, the encoder, the checker, and the vignette recourse table all
  bind to them so they cannot drift.
- R is unavailable in the authoring environment; `devtools::test()`, `R CMD check --as-cran`, and
  `Rscript dev/datom_cv1_reference.R` are run by the maintainer/CI.
- The Task Dependency Graph waves are the safe SEQUENTIAL execution order; tasks within a wave
  touch adjacent code in `R/utils-sha.R` / `R/hashable.R`, so if execution is fanned out to
  parallel agents on one branch, honor wave order sequentially to avoid edit collisions.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.3", "1.9"] },
    { "id": 1, "tasks": ["1.6", "1.2"] },
    { "id": 2, "tasks": ["1.4", "1.5", "1.7", "1.10"] },
    { "id": 3, "tasks": ["3.1", "3.2"] },
    { "id": 4, "tasks": ["3.4", "3.3"] },
    { "id": 5, "tasks": ["3.5"] },
    { "id": 6, "tasks": ["4.1", "3.6"] },
    { "id": 7, "tasks": ["4.2"] },
    { "id": 8, "tasks": ["5.1", "4.3"] },
    { "id": 9, "tasks": ["6.1", "5.2"] },
    { "id": 10, "tasks": ["9.1", "8.1", "6.2"] },
    { "id": 11, "tasks": ["10.1"] },
    { "id": 12, "tasks": ["8.2", "9.2"] },
    { "id": 13, "tasks": ["12.1", "12.2", "12.3", "12.4", "12.5"] },
    { "id": 14, "tasks": ["13.1", "13.2"] },
    { "id": 15, "tasks": ["14.1"] }
  ]
}
```
