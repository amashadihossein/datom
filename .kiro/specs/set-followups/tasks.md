# Tasks -- set follow-ups

One task = one commit. Full suite before each commit, count in the message. Stop after each task
for the owner's go-ahead.

## Where things stand

Spec written 2026-10-08. No task started.

## Tasks

- [ ] **1. `datom_find_member()`: rename, export, accept a set** (R1; AC1-AC5, AC9)
  - Rename the internal and its callers and links; accept a set or a member list; refuse anything else.
  - Roxygen + examples, NAMESPACE, `_pkgdown.yml`, NEWS line, `dev/datom_pathways.md` set-read card.
  - Tests: unique name on a set and on `x$members`; ambiguous refusal; narrowing by tags and by
    version prefix; no connection / no storage read; bad `x` refused. Probe each.
  - Acceptance: AC1, AC2, AC3, AC4, AC5, AC9.

- [ ] **2. `?datom_schema` and the upgrade messages** (R2; AC6, AC7, AC9)
  - Help page with the two-row table; five messages suggest CRAN then GitHub; four point at
    `?datom_schema`. NEWS line.
  - Tests assert the new text on each of the five; probe one per message.
  - Acceptance: AC6, AC7, AC9.

- [ ] **3. Number the two set rules (AC42, AC43 in datom-sets)** (R3; AC8, AC9)
  - Define in `datom-sets/requirements.md`, append the owning task to `datom-sets/tasks.md`, label the
    two tests, probe both, run `Rscript dev/check-spec.R`.
  - Acceptance: AC8, AC9.

- [ ] **4. Close out** (AC10)
  - `R CMD check --as-cran`; harvest learnings (`dev/engineering-notes.md`, spec); update
    `dev/README.md` (Active Specs, Completed Phases, Backlog rows for #103 / #111 / #112); PR into
    `dev`; close #103, #111, #112 after merge.
  - Acceptance: AC10.
