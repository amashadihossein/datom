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

Spec approved 2026-09-27 and committed. Task 1 done 2026-09-28 and pushed. **Resume at task 2**
(`datom_parent(x = )`); the owner has not yet approved starting it, so ask first (rule 5d).
**Current test count: 4295** -- this, not the 4282 baseline above, is what task 2's count must not
drop below.

Starting cold: `git checkout spec/set-sync-ergonomics && git pull`, then read `requirements.md` (R5 is
task 2) and `design.md` (section 1 lists the code facts already checked, section 6 is task 2). Before
editing `R/`, read `dev/engineering-notes.md`, at least "A test can observe a layer that cannot
distinguish the two behaviours" and "Probing a guard". Task 2 needs a probe for each refusal it adds.
Section 1's facts for task 2 were re-checked on 2026-09-28 and still hold: `datom_parent(conn, table,
version)` is in `R/lineage.R`, and the single-member resolver `.datom_find_member(members, name, tags,
version)` in `R/set-members.R` is the one `datom_fetch_member()` uses. The owner's original prompt is
untracked and not needed: every decision is in `requirements.md`.

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

- [ ] **2. `datom_parent(x = )`** (R5, AC11)
  - Design 6. Tests: resolver parity with `datom_fetch_member()`, ambiguous, set-kind, vector
    `table`, mutual exclusion, existing positional calls.

- [ ] **3. `datom_add_member()` on a `datom_set`, with `conn =`** (R4, AC10)
  - Design 5, including the `add` action in the edit log and commit message.
  - Tests: by record, by name with `conn`, name without `conn` refused, draft unchanged (commit
    message too), clash rules on a `datom_set`.

- [ ] **4. Provenance check in `datom_write_set()`** (R6, AC12)
  - Design 7. Tests: mismatch stops before any local write; matching parents pass; parent not in the
    set passes; baseline pair (one member at the parent's version) passes.

- [ ] **5. Preview: `datom_sync_manifest(sources = )`** (R1, R2; AC1-AC3, AC5-AC7)
  - **Escalation flag: design spot-check first.**
  - Design 2 and 3. New `R/sync-set.R`; branch in `R/sync.R`. Existing sync tests unchanged.

- [ ] **6. Apply: `datom_sync(sources = , tags = , x = )`** (R3; AC4, AC8, AC9)
  - Design 4. Properties P1-P3, P5.

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
