# datom Engineering Notes

> **Purpose**: Implementation gotchas and pitfalls, extracted from
> `.github/copilot-instructions.md` so the always-loaded instruction *core* stays small.
> This is the on-demand reference — **consult it before editing `R/`**. New gotchas and
> pitfalls go here, not in the core instructions.
>
> **How it loads**: Kiro pulls this in via a `fileMatch` steering rule when R files are in
> context; Copilot users reference it from chat when working in `R/`. The core
> `.github/copilot-instructions.md` links here prominently.
>
> **Maintenance**: living doc. Entries are vetted against the *current* code. Where a gotcha
> concerns the governance write surface, the pending `gov-seam-liftout`
> (`.kiro/specs/gov-seam-liftout/`) will relocate that surface to datomanager — those entries
> stay accurate until that change lands.
>
> **Vet note for this extraction**: corrected one stale reference — the gov sub-connection
> helper is now `.datom_conn_for(conn, "gov")`, not the former `.datom_gov_conn()`. Remaining
> entries were carried over unchanged and remain valid against the current codebase; a deeper
> line-by-line re-verification against source is a separate task.
>
> **gov-seam-liftout landed (2026-06-20).** The governance **write** surface (5 exports +
> 9 `.datom_gov_*` write helpers) has been removed from datom and now lives in `datomanager`.
> Entries below that concerned removed functions have been updated to the post-lift-out
> reality. datom keeps all gov **reads** + the data-side helpers (`datom_repo_delete`,
> `datom_repo_attach_governance`).

## Active work handoff: datom-cv1 (issue #72) -- updated 2026-07-25

> Transient section for the in-flight `spec/datom-cv1-identity` branch. Delete it at spec
> completion (its durable content is harvested into the spec docs + the Gotchas below).

**Where we are.** Branch `spec/datom-cv1-identity`. Phase 1 (Waves 0-2), **Task 3
(Waves 3-5)**, **Task 4 (Waves 6-7: read-time `parquet_sha` integrity)**, **Task 5 (Wave 8:
full-history dedup + `parquet_sha` persisted into `version_history`)**, **Task 6 (Wave 9:
persisted column index)**, **Tasks 9 + 8 (Waves 10 + 12: ingestion allowlist and the
exported `datom_check_hashable()`)**, and **Task 10 (Wave 11: the `file_sha` ->
`original_file_sha` nomenclature sweep)** are complete and committed. Full suite green at
**2318 passed / 0 failed / 0 warnings / 0 skipped**; `R CMD check` clean (0 errors /
0 warnings / 0 notes). Checked off in `tasks.md`: 1.x, 2, 3.1, 3.2, 3.4, 3.5, 3.6, 4.1, 4.2,
4.3, 5.1, 5.2, 6.1, 6.2, 8.1, 8.2, 9.1, 9.2, **10, 10.1**. **Deferred `*` test: 3.3**
(metadata_sha locale + volatile-membership *property* tests, Properties 13/14 -- the behavior
is already covered by plain tests; the tagged property versions are pre-PR work).
**Next = Wave 13: Tasks 12.1-12.5** (the S1-S6 identity-contract integration tests on the
local backend) -- Wave 12 (8.2, 9.2) already landed with Tasks 8 and 9. Then Wave 14
(docs/NEWS, Tasks 13.1/13.2), Wave 15 (acceptance greps, Task 14.1). Resume from `tasks.md`
in wave order. **Task 11 is a chunk checkpoint** -- stop there for maintainer go-ahead.

**Commit anchors** (branch head `71e8637`, pushed): `3a5f717` Task 6 column index ->
`9722e59` man/ regeneration for Tasks 1-5 -> `b359fb9` Task 9 allowlist -> `5b28463` Task 8
`datom_check_hashable()` -> `71e8637` parent-checkbox correction + this handoff prep
(docs only: `tasks.md` + this file, **no `R/` or `tests/` change**, so the code inventories
below that were verified at `5b28463` remain valid at `71e8637`).

**Outstanding before the PR can merge** (none of these block Wave 13; all are named acceptance
criteria, so an MVP that skips them cannot merge):
1. **Task 3.3** -- Properties 13/14 (`metadata_sha` locale determinism + volatile-field
   membership) as tagged property tests.
2. **Task 12.5's revert-reuse integration test** -- write content A -> write B -> re-write A;
   assert the stored object is not re-uploaded and the reused `parquet_sha` matches A's history
   entry. (The code path went live with Task 5.1; only the E2E assertion is missing.)
3. **Tasks 12, 13, 14, 16** in full (S1-S6 integration tests, docs/NEWS, acceptance greps,
   spec completion). Task 10 is now done.

**Parent-checkbox convention in `tasks.md`:** parent task boxes are checked only when every
sub-task under them is checked. Task 3's parent is deliberately `[ ]` with an inline note --
its code is all done, only the deferred `*` test 3.3 remains. Do NOT redo 3.1-3.6.

**Waves 10 + 12 DONE (allowlist + checker) -- as-built anchors.**
- **`.datom_import_formats` + `.datom_import_format_recourse()` in `R/sync.R`.** The recourse
  helper renders the two advice lines once via `cli::format_inline()` and returns plain text,
  which is what lets the identical string land in a cli abort bullet AND in the `error` cell of
  the manifest data frame with no markup drift. **cli dot-literal gotcha applies**: the formats
  vector must be spliced as `{.val {(.datom_import_formats)}}` -- without the inner parens cli
  reads the leading dot as a style name and the message breaks. The design's message block
  omits those parens; the parens are required, not optional.
- **Allowlist enforcement is in three places, one source.** `.datom_import_file()` gates on
  `tolower(format)` *before* touching the file; `datom_sync_manifest()` flags
  `status = "unsupported_format"` **ahead of** the new/changed/unchanged comparison (a bad
  format is not actionable regardless of whether its bytes moved); `datom_sync()` turns those
  rows into `result = "error"` carrying the recourse and keeps processing siblings. The
  nothing-actionable message became "No new or changed files" -- the old "All files unchanged"
  was factually wrong once a batch could hold an unsupported file.
- **`datom_check_hashable()` is the only new export in this spec.** It maps columns through
  `.datom_hash_recourse()` and returns `column`/`class`/`status`/`recourse` invisibly. Its
  offender bullets are built with the same `{.field name} ({.cls class}): recourse` shape as
  the `.datom_canonical_hash()` abort, so the two reports read identically. Keep the report
  ASCII-only in source: the cli `cli_alert_success` / `cli_alert_danger` calls render the
  tick/cross glyphs at runtime -- never type them into `R/`.
- **Examples are runnable (no `\dontrun{}`)** because the checker is pure: no conn, no store,
  no network. R CMD check executes them, so they must stay side-effect free.
**Wave 11 DONE (Task 10, `file_sha` -> `original_file_sha` sweep) -- as-built anchors.**
The gate `grep -rn "file_sha" R/ man/ vignettes/` now returns 44 hits, **all** of them
`original_file_sha`. What the sweep actually touched:
- `.datom_compute_file_sha()` -> `.datom_compute_original_file_sha()` in `R/utils-sha.R`; its
  roxygen title gained the three-SHA framing so the helper's role is legible at the definition.
- `R/sync.R` eight sites: two `@return`/`@param` roxygen lines, the empty-frame column, the
  local var + row column in `datom_sync_manifest()`, `required_cols` in `datom_sync()`,
  `tbl_file_sha` -> `tbl_original_file_sha`, and the `.datom_update_manifest_entry()` param.
- `R/query.R` `.datom_status_input_files()` call + local var; `R/read_write.R:742` call site
  (`file_sha =` -> `original_file_sha =`).
- **The on-disk format did not change.** Every comparison already read
  `existing$original_file_sha` and `.datom_update_manifest_entry()` already wrote
  `entry$original_file_sha` -- the bare token only ever lived in *in-memory* names (the returned
  data-frame column, locals, one param). So there is no manifest migration and no stored-format
  churn, exactly as the design predicted. This is why the suite count did not move: 2318/0/0/0
  before and after.
- **Correction to an earlier revision of this note:** it claimed `devtools::document()` writes
  the renamed `.Rd` but does **not** delete the old page, so you must `git rm` it. That is
  **wrong** -- verified by running it. roxygen2 tracks the pages it generated and deleted
  `man/dot-datom_compute_file_sha.Rd` itself; `git status` showed the ` D` unprompted. Plain
  `devtools::document()` is sufficient for renamed internal helpers.
- **`dev/dev-sandbox.R` needed no change** even though it calls `datom_sync_manifest()`: it only
  reads `manifest$status` and passes the frame straight to `datom_sync()`. Checked, not assumed.
- **Detection gotcha for any future `*_sha` sweep.** `grep -v "original_file_sha\|parquet_sha"`
  filters whole *lines*, so it hides a bare token sitting on a line that also contains a
  legitimate one (e.g. `customers = list(original_file_sha = file_sha)` in `test-sync.R`). Use a
  token-precise scan instead -- and note macOS BSD `grep` has no `-P`, so use perl:
  `perl -ne 'print if /(?<!original_)(?<!parquet_)\bfile_sha\b/'`. `\bfile_sha\b` alone is not
  enough either: `_` is a word character, so it does **not** match inside
  `.datom_compute_file_sha` or `tbl_file_sha`. Rename the function first, then sweep bare tokens.
- **Doc debt was cleared separately.** Tasks 1-5 had added `@keywords internal` helpers without
  running `devtools::document()`, so `man/` was stale; that regeneration is its own commit
  (9722e59) ahead of the two feature commits. If `man/` looks noisy in a future diff, run
  `devtools::document()` before assuming a real change.

**Wave 13 must-remembers (Tasks 12.1-12.5, the NEXT work -- S1-S6 identity-contract
integration tests).** Read the design's S1-S6 scenario table and Requirement 16.5/16.6 first.
Verified groundwork so the wave does not rediscover it:
- **Requirement 16.6 is already satisfied, suite-wide.** `tests/testthat/setup.R` installs the
  fail-closed network guard: it swaps `.datom_s3_client()` and `httr2::req_perform()` for
  aborting stubs unless `DATOM_ALLOW_REAL_NETWORK=1`. So "the whole suite runs under the
  fail-closed guard" needs **no new work** in 12.5 -- just do not add a test that dials out, and
  do not set that env var. libgit2 sockets are *not* trappable at the R level; the git rule is
  convention only (local bare repos, never a real URL to an executed clone/fetch).
- **Fixture pattern.** `tests/testthat/helper-mock.R` provides only `mock_datom_conn()` and
  `muffle_conn_warnings()`. The prevailing writable-conn idiom in `test-sync.R` is
  `withr::with_tempdir({ conn <- mock_datom_conn(list()); conn$role <- "developer";
  conn$path <- getwd(); ... })`, building `.datom/manifest.json` with `jsonlite::write_json(...,
  auto_unbox = TRUE)`. Real `datom_store_local()` stores appear in `test-conn.R` / `test-repo.R`
  / `test-store.R` (not in `test-read-write.R`) -- consult those for a genuine local backend.
- **12.5's revert-reuse assertion is the one with live code behind it.** `.datom_resolve_parquet_sha()`
  + `.datom_lookup_history_parquet_sha()` went in with Task 5.1; only the E2E assertion is
  missing (write A -> write B -> re-write A; the stored object must not be re-uploaded and the
  reused `parquet_sha` must equal A's history entry).
- **The manifest column is now `original_file_sha`** (Wave 11). Any new manifest fixture must use
  that name or `datom_sync()`'s `required_cols` check aborts.

**Task 14.1 acceptance-gate gotcha (verified now, so Wave 15 does not stall on it).** Three of
the four static gates already pass at `71e8637`: `grep -rn "sort_columns\|sort_rows" R/ tests/`
is empty, and `datom_check_hashable` is present in both `_pkgdown.yml:56` and `NAMESPACE:9`. But
the fourth gate as written in `tasks.md` -- "`grep -rn "as.data.frame" R/utils-sha.R` is empty"
-- **will never be empty and must not be "fixed" by deleting the match.** The single hit is
`R/utils-sha.R:256`, a roxygen line documenting the guarantee: "no `as.data.frame()` or coercion,
and never invokes arrow." The gate's *intent* is that no executable coercion exists; the doc
comment asserts exactly that. Wave 15 should either scope the gate to code (e.g. pipe through
`grep -v "^\s*#"`) or record the one documented false positive in the commit message. Do not
strip the comment to make a literal grep pass -- that would delete the statement of the invariant
the gate exists to protect.

**Task 6 DONE (Wave 9) -- confirm-and-assert, zero `R/` change.** As the prior handoff
predicted, the `column_hashes` threading already existed (Tasks 1.6 / 3.1 / 3.5), so 6.1 added
only assertions: a no-truncation check (`^[0-9a-f]{64}$` per entry) on the existing
`test-read-write.R` metadata test, plus a new wide-frame test (6 columns spanning int / dbl /
lgl / chr / factor / Date) asserting `length(column_hashes) == ncol(data)` and the persisted
`name` vector `identical()` to `names(data)`. 6.2 is the tagged `Feature: datom-cv1, Property
12` test in `test-utils-sha.R`, consolidating all four facts (order == `names(data)`; each
`sha` == standalone `.datom_col_digest()`; `data_sha` recomputable from `column_hashes` + dims
using the verbatim-lifted header formula; a one-column edit flips exactly that entry and leaves
the others `identical()`). If a future change ever reddens the recompute assertion, the
byte-layout in `.datom_canonical_hash()` changed -- fix the code, not the test.

**DORMANT marker now RESOLVED (Task 5.1).** `version_history` entries persist `parquet_sha`
(added in `.datom_write_metadata_local()` when `metadata$parquet_sha` is non-NULL), so:
(a) the revert-to-older reuse branch in `.datom_resolve_parquet_sha()` is now live (its TODO
comment was updated to describe the active behavior), and (b) `datom_read(name, version = <old>)`
verifies integrity once the pinned version was written post-5.1 (pre-5.1 / pre-cv1 entries carry
no `parquet_sha` and still skip -- the intended grace). **Still TODO: the Task 12.5 end-to-end
revert-reuse integration test** (write content A -> write B -> re-write A; assert the stored
object is not re-uploaded and the reused `parquet_sha` matches A's history entry).

**Two design decisions made during Task 3 (beyond the written spec -- fold into spec docs at
completion):**
- **`size_bytes` is now volatile** (excluded from `metadata_sha`), joining `parquet_sha`.
  Rationale: `size_bytes` is the parquet file size, which drifts with the arrow version for
  identical logical content -- exactly the drift we exclude `parquet_sha` for. Leaving it
  semantic would let an arrow upgrade mint spurious `metadata_only` versions. This amends the
  Task 3.2 / Requirement 7 volatile set. The `59f1...` golden is unaffected (its fixture has
  no `size_bytes`).
- **`parquet_sha` reuse uses a history lookup, not `.datom_storage_exists()`.**
  `.datom_resolve_parquet_sha()` decides upload-vs-reuse by scanning local `version_history`
  for a recorded `parquet_sha` on this `data_sha` (`.datom_lookup_history_parquet_sha()`),
  rather than the design's literal `.datom_storage_exists()` gate. A recorded `parquet_sha` is
  the precise pin we must not clobber and implies the object exists, so the lookup subsumes the
  existence check with identical behavior across all three branches and one fewer storage
  round-trip -- and it avoided threading a new storage mock through ~15 `datom_write` tests.

**Task 6 must-remembers (persist column index -- the NEXT task, Wave 9).** Read the design's
"Persisted column index (Group D, Requirement 14)" section and Property 12.
- **The threading is ALREADY DONE** (landed with Tasks 1.6 / 3.1 / 3.5), so 6.1 is a
  confirm-and-assert task, NOT new plumbing. `.datom_canonical_hash()` returns
  `column_hashes` (ordered `list(list(name=, sha=), ...)` in column order, computed once and
  reused for `data_sha`); `.datom_build_metadata(..., column_hashes = ...)` puts it in the meta
  list unconditionally; `datom_write()` passes `column_hashes = hashed$column_hashes`; it is
  excluded from `metadata_sha` (volatile set). Existing coverage already asserts the persisted
  shape: `test-read-write.R` "full datom_write records ... column_hashes in metadata.json"
  (presence, length 2, order id->v), `.datom_build_metadata` carry-through
  (`test-read-write.R:680`), and the return shape + a `data_sha`-recompute
  (`test-utils-sha.R:506-519`). So **6.1 may only need a no-truncation assertion** (full 64-char
  hex per entry, all columns present for a wider frame) beyond what exists -- or just verify and
  check the box.
- **6.2 is the real remaining work: the tagged `Feature: datom-cv1, Property 12` test.**
  Consolidate four facts: (a) `column_hashes` order == `names(data)`; (b) each entry's `sha`
  equals the standalone `datom:::.datom_col_digest(name, data[[name]])`; (c) `data_sha` is
  recomputable from the stored `column_hashes` + dims; (d) changing exactly one column flips
  exactly that column's entry (others unchanged). **Exact recompute formula** (from
  `.datom_canonical_hash()` in `R/utils-sha.R` -- copy it verbatim so the test cannot drift):
  ```r
  shas   <- vapply(meta$column_hashes, function(e) e$sha, character(1))
  header <- c(charToRaw("datom-cv1"),
              writeBin(as.double(c(nrow, ncol)), raw(), size = 8L, endian = "little"))
  recompute <- digest::digest(c(header, charToRaw(paste(shas, collapse = ""))),
                              algo = "sha256", serialize = FALSE)
  # expect_identical(recompute, meta$data_sha)
  ```
  Note `writeBin(as.double(c(nrow, ncol)), ...)` is a single call over a length-2 vector ==
  `f64le(nrow) || f64le(ncol)`. The `test-utils-sha.R:512-519` block already does exactly this
  recompute against `.datom_canonical_hash()` output -- lift that pattern, add the per-column
  `.datom_col_digest()` equality and the single-column-diff assertion, and tag it Property 12.
- **Do NOT jump to Task 8/9/10 yet** -- follow `tasks.md` wave order (Wave 9 = 6.1 + 6.2; both
  touch the column index, no collision in a single-agent session).

**Test-run harness reminder** (unchanged): write the runner to a temp `.R` file and `Rscript`
it (the shell mangles multi-line `Rscript -e`); the full-suite one-liner is in the "Environment
note" below. Commit code + `tasks.md` + this handoff together; long messages via `git commit -F`.

**Task 4 DONE (read-time integrity, Waves 6-7) -- as-built anchors (verify, do not reinvent).**
Implemented against the design's "Read-time integrity (Requirement 8)" section; read chain is
`datom_read` -> `.datom_read_metadata` -> `.datom_resolve_version` -> `.datom_read_parquet`.
- **4.1 `.datom_resolve_version(metadata_list, version, name)`** now returns
  `list(data_sha, parquet_sha)` on **both** branches (NULL-version -> `current$data_sha` /
  `current$parquet_sha`; history-lookup -> the matched entry's `data_sha` / `parquet_sha`).
  `parquet_sha` is `NULL`/`""` for pre-cv1 entries AND for any version-pinned read until Task
  5.1 persists it into history -- so `datom_read(name)` (current pointer, carries `parquet_sha`
  since Task 3.5) verifies, while `datom_read(name, version = <old>)` skips verification until
  5.1. Intended pre-cv1 grace, not a bug. All existing guard aborts (missing `data_sha`,
  ambiguous prefix, non-character version, etc.) are unchanged; `.datom_validate_sha()` was NOT
  added here (short version prefixes are intentional -- see the "Validate SHA-like inputs"
  gotcha below).
- **4.2 `.datom_read_parquet(conn, name, data_sha, parquet_sha = NULL)`** gained the param and
  extends #74's existing seam (no parallel path). The check sits AFTER
  `.datom_storage_download()` and BEFORE `arrow::read_parquet()`: when `parquet_sha` is
  non-empty it computes `actual <- digest::digest(file = tmp, algo = "sha256")` and, on
  `!identical(actual, parquet_sha)`, aborts with the verbatim design tamper message
  (`Stored parquet for {.val {name}} failed its integrity check.` / `x Key: {.val {s3_key}}` /
  `x Expected {.field parquet_sha}: {.val {parquet_sha}}` / `x Actual SHA-256: {.val {actual}}`
  / `i The stored object may be corrupted or tampered with. Do not trust this data.`). Empty/
  NULL `parquet_sha` skips silently (Requirement 8.4).
- **Only ONE caller** of each (both inside `datom_read()`); the call site now does
  `resolved <- .datom_resolve_version(...)` then
  `.datom_read_parquet(conn, name, resolved$data_sha, parquet_sha = resolved$parquet_sha)`.
  `R/query.R`'s `datom_get_lineage()` opens `{version}.json` directly and was untouched.
- **Test note (return-shape change):** the direct `.datom_resolve_version()` tests in
  `test-read-write.R` were updated from bare-string to `$data_sha` (mirroring Task 3.4's
  `.datom_has_changes()` migration), plus new parquet_sha-resolution cases and the 4.3 integrity
  tests. The mismatch test proves "abort before parse" by having the download write non-parquet
  bytes: if the integrity check were skipped, arrow would fail parsing with a different error,
  so the `"integrity check"` match would not hold.

**Environment note (this workspace).** A working R toolchain is present here: R 4.5.2 with
`devtools`, `arrow`, `digest`, `testthat`, `mockery`, `withr`, `git2r`, `rio`, and also
`tibble` + `bit64`. So the spec/tasks assumption that "R is unavailable in the authoring
environment, goldens stay as PENDING placeholders" does **not** hold here -- the suite runs
directly and all golden constants are already filled from a real run. Run the full suite via a
temp script (the shell mangles multi-line `Rscript -e`; write R to a temp file and `Rscript`
it):

```r
options(crayon.enabled = FALSE)
suppressMessages(devtools::load_all(quiet = TRUE))
res <- as.data.frame(testthat::test_dir("tests/testthat",
  reporter = testthat::ListReporter, stop_on_failure = FALSE))
cat("PASS:", sum(res$passed), " FAIL:", sum(res$failed),
    " WARN:", sum(res$warning), " SKIP:", sum(res$skipped), "\n")
```

Other workflow tips: long git commit messages -> write to a temp file and `git commit -F`;
`gh issue view N` needs `GH_PAGER=cat` or it hangs.

**Technical anchors already implemented (verify, do not reinvent).**
- Byte-layout single source of truth is `dev/datom_cv1_reference.R` (Rbuildignored). Running
  it prints the goldens (numeric `48b4c0cb...`, mixed `47c94f30...`) and passes 27/27
  self-tests. The package `.datom_canonical_hash()` **must** stay byte-identical to it; the
  parity test (`test-utils-sha.R`, Property 11) enforces this and skips when `dev/` is absent.
- `R/hashable.R`: `.datom_column_kind()` (single classifier -> kind or NULL),
  `.datom_hash_recourse()` (single-source recourse strings), `.datom_class_label()`. The
  `sfc` check is deliberately hoisted **above** the generic list rules (sfc is list-based) so
  its recourse is reachable -- do not move it back below them.
- `R/utils-sha.R`: `.datom_encode_numeric()` / `.datom_encode_character()` (raw payloads),
  `.datom_col_digest()`, `.datom_canonical_hash()` (returns `list(data_sha, column_hashes)`),
  `.datom_compute_data_sha()` (thin wrapper, no sort params).
- Test fakes: `hms`/`ITime`/`integer64` are faked via `structure(..., class = ...)` to avoid
  adding `Suggests`; `one_col(x)` helper builds a single-column frame preserving class.
- The `metadata_sha` golden `59f1f1d9...` in `test-utils-sha.R` was **verified stable** under
  task 3.2's upcoming radix-sort + volatile-set change (its fixture has no
  `parquet_sha`/`column_hashes` and only simple lowercase names). Keep that fixture as-is so
  the golden does not need re-deriving after 3.2.

**Task 3 must-remembers (from design.md Invariants).**
- The parquet upload stays **after** the git push in `datom_write()` -- load-bearing (git push
  is the serialization point). Never refactor to upload-before-push.
- `metadata_sha` **excludes** `parquet_sha` + `column_hashes` and **includes**
  `original_file_sha` + `hash_algo`.
- `original_file_sha` appears in metadata **only when non-NULL** (imported path); the derived
  path omits it entirely (not present-with-NULL).
- `.datom_sync()`'s self-lineage `version_sha` stays `data_sha`, not `metadata_sha`.
- While editing `.datom_sync_metadata()` for task 3.4, clean the one remaining non-ASCII arrow
  character still in `R/utils-sha.R` (in that function's body).

## Gotchas

- **cli pluralization**: `{?s}` requires a quantity reference immediately before it (e.g., `{length(x)} variable{?s}`). Without the quantity, cli throws a confusing error.
- **git2r::default_signature()**: Fails on freshly `git2r::init()`'d repos that lack local config. Always call `git2r::config(repo, user.name = ..., user.email = ...)` after init.
- **git2r::merge()**: Expects a string (branch name), not a branch object. Use `upstream_ref$name`.
- **cli dot-literals**: In cli >= 3.4.0, `{.something}` inside any `cli_*()` call is interpreted as a cli style, not an expression. Wrap **any** function call or variable starting with `.` in parentheses: `{(.datom_build_storage_key(...))}`, `{(.sandbox_storage_label(store$data))}`. This applies to `cli_li`, `cli_alert_*`, `cli_abort`, etc. — not just `cli_abort`.
- **glue + cli markup incompatibility**: `glue::glue()` parses `{...}` itself, so passing a cli-markup string like `"Mismatch for {.val {name}}"` through `glue()` will fail or mangle output. Keep cli markup out of strings passed to `glue()`. For values stored in variables (e.g. a `message` field built in a helper) use `paste0()` to assemble the string; call `cli::cli_alert_*()` separately for display, passing the cli markup directly to the cli function rather than through a variable.
- **`datom_history()` returns full SHAs by default**: `short_hash = FALSE` is the default. The `version` column is a functional identifier meant to be passed back to `datom_parent(conn, table, version)` and `datom_get_lineage(version=)` -- those open `{table}/.metadata/{version}.json`, so an 8-char abbreviation silently fails with "file not found". Use `short_hash = TRUE` only for display purposes.
- **`source_lineage` self-entry bootstrap**: `datom_sync()` auto-populates `source_lineage = [{project, table, version_sha}]` for imported tables. The `version_sha` in that self-entry uses `data_sha` (the parquet content SHA), NOT `metadata_sha`. This avoids a circular dependency: `metadata_sha` is computed from the metadata which includes `source_lineage` which would need to embed `metadata_sha`. `data_sha` is content-addressed and computed before metadata is assembled. Any future change to the auto-self logic must preserve this ordering.
- **Walker invariant for lineage traversal**: Code that walks lineage must follow `parents`, NEVER `source_lineage`. `source_lineage` entries are terminal leaves -- they describe raw sources, not traversable edges. For imported tables, the self-entry in `source_lineage` creates a fixed point that would produce an infinite loop if followed. `datom_get_lineage()` is intentionally read-only with no recursion, and the composable lineage-consistency recipe (below) is likewise a set of reads, not a walk.
- **Lineage consistency is a composable recipe, not a dedicated function**: `datom_validate_lineage()` was removed. `datom_write()` derives a derived table's `source_lineage` from its parents' union at write time and lineage is version-pinned, so a recompute equals the recorded value in normal operation. To check consistency, compose existing reads: `datom_get_parents(conn, name)` -> for each parent read `datom_get_lineage(parent_conn, parent$table, version = parent$version, depth = "source")` through a conn scoped to that parent's project -> `datom_lineage_union(...)` -> compare to `datom_get_lineage(conn, name, depth = "source")`. This honors the one-connection-per-project model (each parent is read through its own conn) and keeps semantic checks in the caller's workflow, orthogonal to `datom_validate()`'s git/S3 storage-consistency pass.
- **`.datom_git_commit()` is idempotent**: Returns HEAD SHA (instead of erroring) when staged files are unchanged. This is by design — enables safe re-runs after partial failures in the local → git → S3 pipeline.
- **metadata SHA uses JSON canonical form**: `.datom_compute_metadata_sha()` hashes `jsonlite::toJSON()` output with `serialize = FALSE`, not the R object. This is critical — R's `serialize()` is type-sensitive (`10L` ≠ `10`), so metadata round-tripped through JSON would produce a different SHA. Always test SHA stability with a JSON round-trip.
- **metadata SHA excludes volatile fields**: `created_at` and `datom_version` are stripped before hashing. Adding new metadata fields that should NOT affect versioning must be added to the `volatile` vector in `.datom_compute_metadata_sha()`.
- **version_history dedup guard**: `.datom_write_metadata_local()` skips appending when the latest entry has the same version SHA. This prevents duplicates but means the guard relies on metadata_sha correctness.
- **`datom_pull()` is git-only**: No S3 manifest refresh — git is the source of truth for all metadata. The manifest is committed to git and pulled with everything else.
- **`governance.json` mirror -- git canonical, storage derived**: The git copy at `.datom/governance.json` is written and committed first; the storage mirror at `{prefix}/datom/.metadata/governance.json` is pushed in the same step. Never write only one. If the mirror is missing, `.datom_sync_governance_json(conn)` regenerates it from the git copy. The file is write-once -- do not update it after creation.
- **S3 namespace check swallows connectivity errors**: `.datom_check_namespace_free()` in `datom_init_repo()` warns but doesn't fail on network errors — offline init still works, S3 push will fail later anyway.
- **`git2r::clone()` target path**: Must not exist or must be an empty directory. `datom_clone()` validates this upfront.
- **`paws.storage` has no STS**: `sts` is in `paws.security.identity`, not `paws.storage`. Validation uses `HeadBucket` only (validates both credentials and bucket access).
- **Storage abstraction**: Business logic must call `.datom_storage_*()`, never `.datom_s3_*()` or `.datom_local_*()` directly. The dispatch layer in `R/utils-storage.R` routes based on `conn$backend`.
- **`datom_conn` has two clients**: `client` (data store) and `gov_client` (governance store). Use `.datom_conn_for(conn, "gov")` to create a sub-connection for governance operations (this replaced the former `.datom_gov_conn()` helper).
- **`conn$root` is backend-neutral**: S3: root = bucket name. Local: root = directory path.
- **`conn$client` is NULL for local backend**: `.datom_local_*()` functions use `conn$root` + `conn$prefix` directly via `fs::`. Never check `is.null(conn$client)` to determine backend — use `conn$backend` instead.
- **`datom_store_local$path` vs `datom_store_s3$bucket`**: Store components have backend-specific field names. Use `.datom_store_root()` accessor for backend-neutral access.
- **`.datom_storage_delete_prefix()` local backend returns `1L`, not object count**: The local backend removes the directory and returns `1L` (removed) or `0L` (not found). The S3 backend returns the count of deleted objects. Tests and callers that expect a file count will fail -- use structural checks (`dir_exists`) to verify deletion on local.
- **`ref.json` lives at governance store**: Created by `datom_init_repo()`, resolved by `.datom_resolve_ref()`. Contains `current` data location (bucket/prefix/region).
- **Ref resolution asymmetry**: Conn-time ref failure is **warn-only** (governance informs, does not gate). Write-time ref failure is a **hard abort for any reason** (`.datom_check_ref_current()`) — writing without a verified location risks orphaning data, there is no safe fallback. Reads don't re-check — stale conn fails cleanly and the user rebuilds.
- **Migration detection is role-aware**: `.datom_resolve_data_location()` compares `store$data` location vs ref location. Developer mismatch → auto-pull git and re-read `project.yaml` (errors if still disagrees). Reader mismatch → warn + proceed with ref-resolved location using the reader's existing credentials.
- **Backend labels should be lookup-based, not binary**: Prefer `c(s3 = "S3", local = "local")[conn$backend] %||% conn$backend` over `if (conn$backend == "s3") ... else ...`. New backends (GCS, etc.) become one-line additions. Applies to UI strings; dispatch still uses `switch()` in `utils-storage.R`.
- **`datom_init_repo()` validates before side effects**: All store/repo validation happens before any filesystem or git operations. On failure, nothing is left behind.
- **`project.yaml` two-component structure**: `storage.governance` + `storage.data` — each has its own `type`, `bucket`, `prefix`, `region`. Secrets are never persisted.
- **Two repos, never one commit touching both**: governance and data live in separate git repos with separate histories. **Post-lift-out, datom only writes the data repo** (`datom_write`, `datom_sync`, `datom_init_repo`, `datom_repo_attach_governance`, `datom_repo_delete`). All gov-repo writes (register, dispatch/ref, decommission pruning, gov init) now live in `datomanager`. Any operation that spans both repos (e.g. `datomanager::gov_attach()`) produces two distinct commits in two histories — datomanager commits the gov repo itself and routes the data-repo commit through datom's exported `datom_repo_*` helpers.
- **Gov files live at `projects/{project_name}/`**: `dispatch.json`, `ref.json`, `migration_history.json` are project-scoped under `projects/` in both the gov repo and gov storage. They are NOT in the data repo's `.datom/` anymore. Anything reading those paths must use the gov clone (`conn$gov_local_path`) or `gov_client` (storage), never the data clone.
- **`# GOV_SEAM:` markers are gone — the seam is now the package boundary**: before the lift-out, gov-write helpers in `R/utils-gov.R` were tagged `# GOV_SEAM:`. Those nine write helpers are removed; `R/utils-gov.R` now holds only gov-**read** helpers (none seam-marked). Do not reintroduce gov-write code in datom — it belongs in `datomanager`. The port contract (helper inventory + commit-message strings + storage layout) is preserved in `dev/datom_specification.md` → "Governance Repository Contract".
- **`datom_init_repo()` is data-only (post-lift-out)**: it initializes the data repo and leaves the project a Solo_Project — no gov clone bootstrap, no `projects/{name}/*.json`, no `.datom/governance.json`, no gov namespace check. A `store$governance` component is silently ignored for registration. Governance attaches later via `datomanager::gov_attach()`, which calls `datom_repo_attach_governance()` for the data-side pointer.
- **`datom_repo_attach_governance()` writes the data->gov pointer (C4)**: it is the only exported, C4-compliant way to write `.datom/governance.json` (git canonical) + its data-storage mirror. `datomanager::gov_attach()` MUST route the data-repo write through it (datomanager never mutates the data repo directly). Mirror failure warns but does not abort — the git copy is canonical. Guards abort before any write: non-developer conn, NULL `conn$path`, empty `gov_repo_url`, invalid `gov_store`, missing `.datom/project.yaml`.
- **`.datom_sync_data_metadata()` is the data-only half of the old `datom_sync_dispatch()`**: `datom_sync_dispatch()` (removed) did gov-write AND data-side metadata sync. The data-side half (mirror manifest + per-table metadata to the data store; no gov) was kept as this internal helper. Callers: `datom_validate(fix = TRUE)` and `datom_write(data = NULL, name = NULL)`. The gov-write half is `datomanager::gov_sync_dispatch()`.
- **Role-aware ref reads**: `.datom_resolve_data_location()` branches on presence of `conn$gov_local_path`. Developer (clone present) reads `projects/{name}/ref.json` from local gov clone (offline-friendly, reflects last gov pull — now `datomanager::gov_pull()`). Reader reads via `gov_client` from storage. Write-time guard `.datom_check_ref_current()` ALWAYS reads from storage (no clone fallback) to catch stale clones.
- **`datom_repo_delete()` requires literal confirm**: `confirm = "{project_name}"` must match exactly (case-sensitive, no trimming). No interactive prompts (must be scriptable). It deletes the data GitHub repo + local clone only — NOT the data store namespace (use `datom_storage_delete_prefix()` for that) and NOT the caller-owned store root. Refuses governed projects (`gov_root` non-NULL) unless `force_gov_attached = TRUE` — solo teardown is the normal path; governed teardown goes through `datomanager::gov_decommission()`, which passes the force flag.
- **`datom_repo_delete()` ownership boundary**: it owns the GitHub repo + local clone, nothing in storage. For solo local-backend sandboxes the data store directory must be mopped up separately (see `.sandbox_wipe_local_component()` in `dev/dev-sandbox.R`). `datom_storage_delete_prefix()` removes the `datom/` namespace inside the store root but never the root itself (caller-owned).
- **NA-safe optional-string guards**: `nzchar(NA)` returns `NA`, which propagates into `if(...)` as "missing value where TRUE/FALSE needed". For optional fields that may round-trip through yaml/json (e.g. `conn$prefix`), guard with `!is.null(x) && !is.na(x) && nzchar(x)` and wrap the `if` predicate in `isTRUE(...)`. Pattern is in `.datom_local_delete_prefix` / `.datom_s3_delete_prefix`.
- **gov teardown / `.datom_gov_destroy()` moved to datomanager**: the whole-gov-repo teardown helper (refuses if registered projects exist unless forced) was one of the nine removed write helpers. `dev/dev-sandbox.R` still references `datom:::.datom_gov_destroy()` and `datom_decommission()` in its **gov** teardown path — that path is now broken until datomanager provides the equivalents. The **solo** sandbox path (`attach_gov = FALSE` + `datom_repo_delete()`) works standalone; use `dev/e2e-solo-local.R` for datom-only E2E. The legacy `dev/e2e-test-local.R` (gov-attached) references removed functions and will not run until datomanager lands.
- **`gov_local_path` defaults to `tools::R_user_dir("datom","data")/<repo_name>`**: `datom_init_gov(gov_local_path = NULL)` resolves to the user data directory, never CWD. This avoids polluting a package source tree or any other working directory the user happens to be in. One gov clone serves many data projects. `.datom_gov_clone_init()` validates remote URL on existing dirs and errors on mismatch.
- **`datom_init_gov()` idempotence is remote-aware**: The early-return guard checks both local `projects/.gitkeep` AND that `git2r::remote_ls()` returns at least one ref. If the remote was wiped/recreated and is now empty, the function re-pushes the local skeleton (with `pull_first = FALSE`) instead of silently no-oping. A completely unreachable remote (fetch errors) propagates as an error -- it does not silently succeed.
- **`.datom_git_push()` accepts `pull_first = TRUE` (default)**: Callers that already know the remote is empty (first push to a new repo, issue #20 re-push after remote wipe) pass `pull_first = FALSE` to skip the pre-push fetch/merge. This avoids libgit2 errors when the remote has no refs yet. Never pass `pull_first = FALSE` for routine pushes to an established remote.
- **`ref.json` carries `current$type`**: Records the data backend (`"s3"` or `"local"`). Set by `.datom_create_ref()` from `.datom_store_backend(data_store)`. Readers depend on this to identify the backend without already holding a store -- e.g. `datom_projects()` populates `data_backend` from this field.
- **Storage list dispatch returns full keys**: `.datom_storage_list_objects(conn, prefix)` and the S3/local backends both return keys in their full storage-key form (`"{prefix}/datom/..."`), NOT relative to the prefix arg. Callers extract project names / paths via regex; do not assume relative-to-prefix output.
- **`.datom_gov_list_projects()` is a pure read**: lives in `R/utils-gov.R`, which after the lift-out holds **only** gov-read helpers. Read helpers stay with datom; only gov **writes** moved to datomanager. Same rule applies to any future `.datom_gov_read_*()` helper — keep reads in datom.

- **PAT plumbing: `.datom_git_pull()`/`.datom_git_push()` accept `pat` but callers must pass it**: the credential helper `.datom_git_credentials(url, pat)` returns NULL for a NULL/empty PAT (so public repos work unauthenticated), which means a caller that forgets `pat = conn$github_pat` silently falls back to unauthenticated and fails only on private repos. All callers pass it now; guard against regressions with `grep -rn "\.datom_git_pull(\|\.datom_git_push(" R/ | grep -v "pat ="` (should return only non-caller lines). `.datom_gov_clone_init()` takes a `pat` param threaded to the clone.
- **`.datom_git_push()` sets upstream tracking after a successful push**: `git2r::push()` does NOT set upstream. Without it, `.datom_git_pull()` and `.datom_check_git_current()` no-op (their `branch_get_upstream()` is NULL), so on the *initializing* developer's machine `datom_pull()` silently does nothing and the stale-state guard always passes. After a successful push, if upstream is NULL, `.datom_git_push()` fetches (so the remote-tracking ref exists) then `branch_set_upstream()`; the whole upstream step is wrapped in tryCatch -> `cli_warn` so it never fails an already-successful push. Clones are unaffected (git sets upstream on clone), and the `is.null(upstream)` guard makes it a no-op on established branches.
- **`datom_clone()` must set a local git identity**: like `datom_init_repo()`, it calls `.datom_git_ensure_local_identity()` on the fresh clone. Without it the first `datom_write()` after a clone fails inside `git2r::commit()` ("user.name not found") on a host with no global git config (CI, fresh box).
- **Validate SHA-like inputs before splicing into a storage key**: `.datom_validate_sha(x, arg)` (in `R/utils-validate.R`) enforces 6-64 lowercase hex. Call it wherever a user-supplied `version`/`data_sha` becomes part of a key — `datom_get_lineage()` (version, non-NULL), `datom_parent()` (version), `.datom_read_parquet()` (data_sha). On the local backend an unvalidated `"../../x"` escapes the namespace via `fs::path()`. NB: `datom_read()`'s `.datom_resolve_version()` intentionally accepts short prefixes; the 6-char minimum covers that, so do NOT add the validator there. `datom_get_parents()` inherits the check by delegating to `datom_get_lineage()`. (Test fixtures for these functions must use hex versions/SHAs, not placeholders like `"v_dm_9f3"`.)
- **Namespace-check S3 client in `datom_init_repo()` needs `session_token`**: the temporary check client is built directly via `.datom_s3_client()`; pass `session_token = store$data$session_token` or STS temporary creds make the HeadObject fail, the tryCatch downgrades it to a warning, and the "namespace already occupied" guard is silently skipped. No `endpoint` is available at that call site (neither `datom_init_repo()` nor the store carries one).
- **Developer conn cross-check compares BOTH root and prefix**: `.datom_get_conn_developer()` checks `project.yaml` root AND prefix against the store, normalizing both prefixes with `.datom_normalize_prefix()` (so NULL/"" compare equal). Two projects can share a bucket under different prefixes, so a matching root is not sufficient — a wrong-prefix store would otherwise silently operate on the other project's namespace.
- **`.datom_storage_rel_key()` strips the prefix literally, not as a regex**: use `startsWith()` + `substring()`, never `sub(paste0("^", ns_root), ...)`. Prefixes may contain regex metacharacters (`.`, `+`, `(`), which corrupt a regex-based strip in `datom_storage_copy()`/`datom_storage_verify()`.
- **Manifest `size_bytes` uses `as.numeric()`, not `as.integer()`**: `.datom_update_manifest_entry()` reads `size_bytes` as numeric; `as.integer()` returns NA above 2^31 (2 GB) and poisons `summary$total_size_bytes`. `version_count` stays integer.
- **`.datom_mask_secret(secret, reveal_prefix = TRUE)`**: default reveals the first 4 chars (fine for GitHub PATs — `ghp_`/`github_pat_` is a public type tag, and AWS access-key `AKIA` prefix is an identifier, not entropy). The `datom_store_s3`/`datom_store_s3_creds` print methods pass `reveal_prefix = FALSE` for `secret_key` and `session_token` so those are masked fully. `datom_store` objects hold plaintext credentials in memory — SECURITY.md warns against `saveRDS()`/`.RData` of stores.

- **`_pkgdown.yml` index must be kept in sync**: Adding a new exported symbol requires a matching entry in `_pkgdown.yml`. `pkgdown::build_site()` errors with "N topics missing from index" otherwise. Check after every phase that adds exports.
- **Non-ASCII characters in R source and vignettes**: R CMD check warns on any non-ASCII character in `R/*.R` files (even in comments), and pkgdown/knitr can silently mangle them in `.Rmd` vignettes too. Use only ASCII everywhere -- `--` instead of em-dash, `->` instead of `->`, `...` instead of ellipsis (`\u2026`), straight quotes. Bulk-check with `LC_ALL=C grep -lr '[^[:print:][:space:]]' vignettes/*.Rmd R/*.R`. **Scope note:** the ASCII rule covers `R/*.R` and `vignettes/*.Rmd` *source* only. The generated `README.md` legitimately contains non-ASCII smart-typography (en-dashes, curly quotes) because `output: github_document` applies pandoc smart punctuation to the ASCII `README.Rmd` source. This is normal, pre-existing, present on `main`, and does **not** trip R CMD check -- do NOT "fix" it. Exclude `README.md` from ASCII sweeps.
- **pkgdown renders every `vignettes/*.Rmd`, regardless of the `_pkgdown.yml` index**: to *exclude* an article from the built site you must physically relocate the `.Rmd` out of `vignettes/` (e.g. into build-ignored `dev/`), not just drop it from the `articles:` index. Conversely, every `.Rmd` left in `vignettes/` MUST appear in exactly one `articles:` group or `pkgdown::build_site()` is noisy/incomplete. Verify the index matches disk: parse `_pkgdown.yml`, `setdiff()` the indexed basenames against `basename(Sys.glob("vignettes/*.Rmd"))` both ways -- both must be empty. (The earlier index gotcha below is the `reference:`/exports analogue of this.)
- **Deferred vignette suite lives in `dev/vignettes-deferred/`**: after the GOV_SEAM lift-out, the 9 gov-interface articles (S3 promotion, handoff, second-engineer, credentials, buckets/prefixes, and the `ref.json`/`governance.json`/`dispatch`/`two-repos` design notes) plus their `resume_article_4-8.R` scripts were parked there verbatim (build-ignored via `^dev$`), blocked on datomanager's gov API. Two pure-gov articles (`governing-a-portfolio`, `auditing-reproducibility`) were handed off entirely and live at `datomanager/dev/vignettes-from-datom/`. `dev/vignettes-deferred/README.md` holds the reassembly map (original `_pkgdown.yml` grouping, journey order, removed-export list). When datomanager's gov surface ships, rework those articles against it rather than rewriting from memory.
- **(historical) `datom_attach_gov()` backend-correct snapshot + gov-remote precondition**: `datom_attach_gov()` was removed in the lift-out (attachment is now `datomanager::gov_attach()`). Two lessons it taught remain relevant for datomanager's reimplementation: (1) when building the data-store snapshot for `ref.json`, map `conn$root` to `bucket` (s3) or `path` (local) before calling `.datom_create_ref()` — `.datom_store_root()` reads `$bucket`/`$path`, so passing `root = conn$root` yields an empty root; (2) attaching requires an initialised gov remote (the seeded `projects/.gitkeep` skeleton), not a bare empty GitHub repo.
- **`conn$gov_backend` is the 12th interface field (C6)**: set to the governance store's backend (`"s3"`/`"local"`) independent of `conn$backend`; NULL on solo projects. `.datom_conn_for(conn, "gov")` resolves gov-scoped storage dispatch from `gov_backend`, NOT `conn$backend` — so a mixed-backend project (data on S3, gov on local) routes each scope correctly. If `gov_backend` is NULL and a caller forces a gov-scoped op, the sub-conn has `backend = NULL` and storage dispatch fails on first IO — correct, since gov-only commands gate on `.datom_require_gov()` first.
- **`datom_repo_set_data_store()` must use read-modify-write on `project.yaml`**: Read the full yaml first (`yaml::read_yaml()`), then `modifyList` only the `storage.data` subtree, then write back. Never reconstruct the full yaml from conn fields -- that silently drops `storage.governance` on governed projects. The `storage.governance` block is write-once and permanent once populated; overwriting it with NULL or an empty list is a silent data loss.
- **`datom_conn` carries `gov_root = NULL` for no-gov projects**: `is.null(conn$gov_root)` is the canonical "no governance attached" test. Do not use `is.null(conn$gov_client)` -- local-backend gov conns also have `gov_client = NULL` by convention. `.datom_require_gov(conn, what)` encapsulates the uniform error; call it at user-facing function entry for gov-only commands.
- **`sandbox_store_local()` / `sandbox_store()` accept `attach_gov = TRUE` (default)**: when `attach_gov = FALSE`, the gov component is `NULL` and no gov dir is created. `sandbox_up()` branches on `!is.null(store$governance)`. `sandbox_promote_gov(env, gov_store)` mirrors Article 4's flow for testing the no-gov -> gov transition end-to-end.

- **Gov-guard messages intentionally name datomanager — this is NOT a C1 violation**: `.datom_require_gov()` and the `datom_get_conn()` "governance store ignored" warning deliberately point users to `gov_attach()` / `gov_decommission()` "(from the datomanager package)" (design Component 8 / Task 5.2). C1 / R6 mean datom has no **hard runtime dependency** on datomanager — it must load and run without it installed and must not fail mysteriously. A helpful guidance string naming the companion package is the sanctioned UX. Do NOT "fix" these messages to strip datomanager — a solo E2E that asserted the gov error must *not* name datomanager was the bug, not the message. The correct solo assertion: the error mentions `governance` and points to `gov_attach`.
