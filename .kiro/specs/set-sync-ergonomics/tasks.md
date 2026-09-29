# Tasks -- set sync ergonomics

**Issue**: [#121](https://github.com/amashadihossein/datom/issues/121).
**Branch**: `spec/set-sync-ergonomics`, from `dev` at `7d55a8b`. PRs into `dev`.
**Test baseline**: 4282.
**Order**: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9. One commit per task, full suite before each,
count in the message. Chunk checkpoint after every task.

**Model escalation flags (set at planning):**
- **Design spot-check before task 5** -- the sync branch is the cross-cutting change.
- **Test coverage review before task 9** -- confirm every guard was watched going red (AC15).

## Where things stand

Spec approved 2026-09-27 and committed. Tasks 1-4 done 2026-09-28. **Resume at task 5**
(the preview, `datom_sync_manifest(sources = )`); ask the owner before starting it (rule 5d).
**Its design spot-check is done** (2026-09-28, on the working model at the owner's request): the
findings are the "Spot-check additions" blocks in design sections 2, 3 and 4. The three open points
at the end of design section 3 were **all answered by the owner 2026-09-28**: A -- a member excluded
by `pattern` gets a row with the new status `excluded`; B -- a `new` row the set already holds stops
as stale; C -- a source whose label disagrees with its manifest's project name stops at the preview.
Requirements R2.2, R3.2, R3.6 and the new R2.10 carry them.
**Current test count: 4406** -- what task 5's count must not drop below.

Starting cold: `git checkout spec/set-sync-ergonomics && git pull`, then read `requirements.md` (R1
and R2 are task 5) and `design.md` (section 1 lists the code facts already checked; sections 2 and 3
are task 5, including their spot-check blocks and open points). Before editing `R/`, read
`dev/engineering-notes.md`, at least "A test can observe a layer that cannot distinguish the two
behaviours" and "Probing a guard". Each refusal a task adds needs a probe. The owner's original
prompt is untracked and not needed: every decision is in `requirements.md` and `design.md`.

Where the code a task 5 session needs lives: the two sync verbs and
`.datom_refuse_import_on_product()` in `R/sync.R`; `.datom_edit_conns()`,
`.datom_current_artifact_versions()`, `.datom_repoint_member()` and `datom_update_members()` (the
closest existing sweep, including its "gone" and "shared name" handling) in `R/set-edit.R`;
`datom_get_set()` in `R/set.R`; `.datom_storage_exists()` in `R/utils-storage.R`. Test fixtures to
copy: `local_edit_project()` in `tests/testthat/test-set-edit.R` (real repo + bare remote + local
store, product config) and `sync_product_repo()` in `tests/testthat/test-sync.R`. A second project
(the source) needs its own store and a connection labelled with its project name; the
mislabelled-connection test in `test-set-edit.R` builds two stores and is the pattern to follow.

---

- [x] **1. Example data: add `vs`** (R7, AC13)
  - **Done 2026-09-28, 4295 tests (+13).** Before editing, the unmodified simulator was re-run and
    reproduced all four CSVs and `R/sysdata.rda` byte-for-byte (R 4.5.2), so the post-edit diff is
    attributable to the edit alone. After the edit: same result, `sysdata.rda` included, so nothing
    needed restoring. `vs` is 432 rows (`SYSBP`, `DIABP`, `PULSE`, integer `VSORRES`), on exactly the
    `lb` subject/visit/date triples.
  - Added beyond the plan: a test pinning a **value fingerprint** of each original table (sha256 over
    the parsed columns, not the file bytes, so line endings and checkout settings cannot move it), plus
    `ae` locked at 84 rows. Probe: moving the `vs` block ahead of `ae` in the simulator reddened the
    `ae` fingerprint; restored and regenerated afterwards. The simulator header now says new domains
    go last in the random stream, and why.
  - Append `vs` generation after `ae` in `data-raw/simulate_study_data.R`; write `vs.csv`.
  - The script writes with relative paths, so run it from the repo root:
    `Rscript data-raw/simulate_study_data.R`.
  - Verify the four existing CSVs byte-identical and `sysdata.rda` values identical (design 8)
    **before** keeping anything. If any existing CSV changed, stop and report; do not commit.
  - `datom_example_data("vs")`, roxygen (`@param domain`, the "four domains" sentence), then
    `devtools::document()`; tests in `tests/testthat/test-example-data.R` (row count, columns,
    cutoff, and that the existing domains' row counts are unchanged).
  - Owner cares most about: **the values of the other example tables must not change.**

- [x] **2. `datom_parent(x = )`** (R5, AC11)
  - **Done 2026-09-28, 4330 tests (+35).** `datom_parent(conn, table, version = NULL, x = NULL,
    tags = NULL)`. The old body moved unchanged into `.datom_parent_record()`, which both routes call;
    the set route (`.datom_parents_from_set()`) resolves each name with `.datom_find_member()` and
    validates `tags` with the same call and remedy as `datom_fetch_member()`. Loop is `lapply()`, not
    `purrr::map()`, so the resolver's condition classes reach the caller.
  - Refusal classes: `datom_parent_version_or_set` (both or neither), `datom_parent_tags_without_set`
    (name chosen here, owner agreed), `datom_parent_not_a_table`; ambiguous / not found keep the
    resolver's `datom_member_ambiguous` / `datom_member_not_found`.
  - Probes (restored from a copy, control reddened nothing): removing each of the three refusals, the
    `table` shape check, and label narrowing each reddened its own test; swapping `lapply()` for
    `purrr::map()` reddened nothing until the class test used `expect_error(inherit = FALSE)`, since
    testthat otherwise matches a wrapped error's parent. Learning added to `dev/engineering-notes.md`.
  - Parity fixture lists the baseline `lb` first, so a resolver ignoring labels picks the wrong member
    for the live case.

- [x] **3. `datom_add_member()` on a `datom_set`, with `conn =`** (R4, AC10)
  - **Done 2026-09-28, 4380 tests (+50).** `datom_add_member(x, member, version = NULL, tags = NULL,
    conn = NULL)`. A name resolves through `conn`, or the draft's own connection when omitted; a
    `datom_set` never borrows a `conn` field (branched on class, not `conn %||% x$conn`), so a name
    there needs `conn` (`datom_member_conn_required`). `conn` that is not a connection:
    `datom_not_a_conn`. On a `datom_set`: link added through the shared factory, identity emptied,
    `add` row logged, not-written line printed. Drafts unchanged apart from `conn =`.
  - Found while writing it: the clash check digests members, and the digest refuses any field but
    `id` / `tags`, so a set read back (every member has `$fetch`) would have errored on every add.
    Existing members are stripped of links before the check.
  - Added beyond the plan: the new member gets a `$fetch` link, so every member of a read set still
    has one. Commit subject lists `add` first, then `repoint`, then `drop`.
  - Docs whose claims this made false were rewritten: the `R/set-draft.R` header (points 1-2 said
    the verb never takes `conn` and that a record is the only cross-project route; point 7 added),
    the `datom_assemble_set()` "one draft" bullet, the cross-project test's title, and the
    `dev/datom_specification.md` signature.
  - Probes (fixed copy, `cmp` after each; control reddened nothing): the conn-required refusal, the
    class branch, the conn type check, link stripping in the clash check, the link, identity
    emptying, the log append, the not-written line, the set/draft wording, the draft early return,
    the `add` commit verb, its display line and its order -- each reddened its own test. The first
    harness run restored nothing (`on.exit()` at `Rscript` top level); recorded in
    `dev/engineering-notes.md`.
  - Design 5, including the `add` action in the edit log and commit message.
  - Tests: by record, by name with `conn`, name without `conn` refused, draft unchanged (commit
    message too), clash rules on a `datom_set`.
  - **Decided 2026-09-28 (owner):** adding to a `datom_set` prints one line, `Nothing has been
    written. Write the set with datom_write_set(conn, x).`, matching `datom_update_members()`. Adding
    to a draft stays silent, as today. A skipped duplicate prints only its existing note.
  - Facts for this task re-checked 2026-09-28 and still hold (design 1): the draft-only class check
    and `datom_not_a_draft` in `R/set-draft.R`; `.datom_set_commit_messages()` and
    `.datom_edit_lines()` in `R/set-edit.R` know `repoint` / `remove` only; the clash helper
    `.datom_draft_member_clash()` takes a plain member list. `datom_member_conn_required` is new. The
    one existing refusal test (`test-set-draft.R`, "the add verb needs a draft") passes a connection,
    not a set, so it stays; keep `datom_assemble_set` in the widened message, which it matches.

- [x] **4. Provenance check in `datom_write_set()`** (R6, AC12)
  - **Done 2026-09-28, 4406 tests (+26).** `.datom_check_set_parents()` in `R/set.R`, called right
    after `.datom_check_set_payload()`; the snapshot read is `.datom_member_parents()`, with the
    format check outside its handler. Refusal classes `datom_set_parent_mismatch` (all mismatches
    in one message, one line each, short hashes) and `datom_set_member_unreadable`; a too-new
    snapshot keeps `datom_schema_unsupported`. New roxygen section in `datom_write_set()`.
  - **No kind filter**, unlike design 7's wording: every own-project member is a table, because a
    product repo holds one set and a set listing itself is refused just before. A filter there
    could never be probed. A parent entry not shaped as three strings is skipped (datom always
    writes three).
  - **One earlier test changed** (`test-set-edit.R`, "a member whose artifact is gone is reported
    and left, and still writes"): its "gone" member pinned a version that never existed, which the
    new unreadable refusal stops at write. It now writes a real `ghost` table and drops it from both
    manifest copies, which is what "gone" is in practice and what the test's own comment ("the pin
    still reads") assumed.
  - Probes (fixed copy, `cmp` after each; control reddened nothing): no abort; call removed; call
    moved before tidy/validation; call moved after the payload file write; baseline rule; project
    match; own-project filter; first-mismatch-only; unreadable skipped; format check inside the
    handler; format check removed; `purrr::map()` for `lapply()` -- each reddened its own test
    (the class tests use `inherit = FALSE`).
  - Design 7. Tests: mismatch stops before any local write; matching parents pass; parent not in the
    set passes; baseline pair (one member at the parent's version) passes.
  - **Design 7 corrected 2026-09-28 (owner), read it rather than this summary:** the check sits
    right after `.datom_check_set_payload()`, not before tidying; it checks each snapshot's format
    number; an unreadable snapshot stops the write (`datom_set_member_unreadable`). Extra tests for
    those: a malformed member still gets the validator's message; a too-new snapshot stops the
    write; a member whose snapshot is missing stops it, with nothing written in each case.

- [ ] **5. Preview: `datom_sync_manifest(sources = )`** (R1, R2; AC1-AC3, AC5-AC7)
  - **Escalation flag: design spot-check first.** Done 2026-09-28; see design 2-3 "Spot-check
    additions" and the answered points A and C (R2.2 `excluded`, R2.10).
  - Design 2 and 3. New `R/sync-set.R`; branch in `R/sync.R`. Existing sync tests unchanged.
  - The context helper and the branch land in `datom_sync_manifest()` only. `datom_sync()` gets its
    branch in task 6, so no commit ships an apply verb that accepts `sources =` and does nothing with
    it; until then it refuses a product repo exactly as today. Ordinary-path tests in `test-sync.R`
    must pass untouched.
  - Tests to write, beyond AC2/3/5/6/7: presence probe (storage unreachable is an error, not "first
    version"); a source holding a set gives it no row; each member-placement row in design 3's table;
    arguments from the other context stop; zero-row frame keeps its columns.
  - Before editing `R/`, read the engineering-notes entries on `tryCatch` erasing "not there" vs
    "could not look", on condition classes lost through `purrr::map()` (use `lapply()` where a
    refusal class must reach the caller), and "Probing a guard".

- [ ] **6. Apply: `datom_sync(sources = , tags = , x = )`** (R3; AC4, AC8, AC9)
  - Design 4, including its "Spot-check additions" and open point B (design 3). Properties P1-P3, P5.
  - Adds the context branch to `datom_sync()` (above its manifest column check, design 2).

- [ ] **7. Vignette code and offline dry run** (R8.1-R8.3)
  - Rewrite `citable-sets.Rmd` per design 9; `#>` blocks become `[pending run]`.
  - Month-4 extract includes `vs`.
  - `dev/e2e-vignettes-s3.R` local backend: whole walk green; `start-on-s3` outputs unchanged.
  - Add the new verbs to `dev/e2e-sets.R` claims.

- [ ] **8. Credentialed run (owner) and transcripts in** (R8.4, AC14)
  - Owner runs `dev/e2e-vignettes-s3.R` with credentials; agent fills blocks mechanically.

- [ ] **9. Close out** (AC15, AC16)
  - **Escalation flag: test coverage review first.**
  - `NEWS.md` (sync on product repos, add to saved sets, parents from a set, the new write refusal,
    `vs`), roxygen for both sync verbs documenting the save asymmetry.
  - `dev/datom_pathways.md` route card; `dev/README.md` completed row; learnings to
    `dev/engineering-notes.md`.
  - `R CMD check --as-cran` 0E/0W; PR into `dev`.
