# Tasks -- set follow-ups

One task = one commit. Full suite before each commit, count in the message. Stop after each task
for the owner's go-ahead.

## Where things stand

Spec written 2026-10-08. Task 1 done 2026-10-08 (4731 tests); task 2 done 2026-10-09 (4744 tests); task 3 done 2026-10-09 (4744 tests); task 4 (close out) next.

## Tasks

- [x] **1. `datom_find_member()`: rename, export, accept a set** (R1; AC1-AC5, AC9)
  - Rename the internal and its callers and links; accept a set or a member list; refuse anything else.
  - Roxygen + examples, NAMESPACE, `_pkgdown.yml`, NEWS line, `dev/datom_pathways.md` set-read card.
  - Tests: unique name on a set and on `x$members`; ambiguous refusal; narrowing by tags and by
    version prefix; no connection / no storage read; bad `x` refused. Probe each.
  - Acceptance: AC1, AC2, AC3, AC4, AC5, AC9.

- [x] **2. `?datom_schema` and the upgrade messages** (R2; AC6, AC7, AC9)
  - Help page with the two-row table; five messages suggest CRAN then GitHub; four point at
    `?datom_schema`. NEWS line.
  - Tests assert the new text on each of the five; probe one per message.
  - Acceptance: AC6, AC7, AC9.

- [x] **3. Number the two set rules (AC42, AC43 in datom-sets)** (R3; AC8, AC9)
  - Define in `datom-sets/requirements.md`, append the owning task to `datom-sets/tasks.md`, label the
    two tests, probe both, run `Rscript dev/check-spec.R`.
  - Acceptance: AC8, AC9.
  - **Done 2026-10-09.** AC42/AC43 rows added after AC38 in the datom-sets table and cited at the R1
    and R4 acceptance lines; datom-sets Task 29 owns them; the two `test-write-set.R` titles carry the
    ids. Checker: "43 defined, 39 named under tests/, 4 exempt"; task numbering 0..29.
  - **Probes.** Gate: removing either label alone makes the checker fail naming that id. Behaviour,
    `filter = "write-set"`: comment-only control -> 0 failures. AC43: dropping the `datom_member()`
    remedy from the missing-`id` refusal -> only the AC43 test fails. AC42: a first probe adding an
    unknown field reddened eight tests (the writer refuses an unclassifiable field), which is too
    crude to count; re-probed with a recognised field (`size_bytes`) -> the AC42 test and the AC8
    lineage test fail, and AC8's overlap is legitimate (it also asserts the set's metadata names).
  - **AC8 holds only in part.** The checker's "code citations" check fails, but it failed already on
    `dev` at `d9727b2` and `8b8e37b`, before this spec: line citations in the datom-sets spec point
    at lines that later edits moved. Not fixed here; raised with the owner.

- [ ] **4. Close out** (AC10)
  - `R CMD check --as-cran`; harvest learnings (`dev/engineering-notes.md`, spec); update
    `dev/README.md` (Active Specs, Completed Phases, Backlog rows for #103 / #111 / #112); PR into
    `dev`; close #103, #111, #112 after merge.
  - Acceptance: AC10.
