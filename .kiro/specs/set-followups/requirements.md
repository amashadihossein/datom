# Requirements -- set follow-ups

**Issues**: [#112](https://github.com/amashadihossein/datom/issues/112),
[#103](https://github.com/amashadihossein/datom/issues/103),
[#111](https://github.com/amashadihossein/datom/issues/111).
**Branch**: `spec/set-followups`, cut from `dev` at `8b8e37b`. **PRs into `dev`, not `main`.**
**Test baseline**: 4705 (measured on `dev` at `8b8e37b`, 2026-10-08).

## Source

Three small items left over from the sets work, agreed point by point with the owner in chat on
2026-10-08. Every decision below was made in that exchange; this document is self-contained.

## Goal

Close three gaps that the sets release left open: a reader cannot ask a set which version it cites
without downloading the data; a user told to upgrade datom is not told which version; and two set
rules have tests that nothing would notice disappearing.

## Requirements

### R1. A public by-name member lookup (#112)

1. `.datom_find_member()` is renamed `datom_find_member()` and exported. There is **one** function;
   no wrapper. Its three internal callers (`R/set-members.R`, `R/set-edit.R`, `R/lineage.R`) and
   every roxygen link to the old name use the new name.
2. Signature: `datom_find_member(x, member, tags = NULL, version = NULL)`. `x` is a set
   (`datom_set`) **or** a set's member list; given a set, the function looks in `x$members`.
   Anything else is refused with a clear message.
3. Behaviour is the existing internal's, unchanged: returns exactly one member record; refuses an
   ambiguous name with the existing message naming every candidate; narrows by `tags` and by
   `version` (full or prefix).
4. It needs **no connection and reads no storage**, so a reader who holds a set but has access to
   none of its members can use it.
5. Roxygen with runnable examples, `@export`, `NAMESPACE`, a `_pkgdown.yml` reference entry, a NEWS
   line, and the set-read route card in `dev/datom_pathways.md`.

### R2. Which datom reads which format (#103)

1. A help page, `?datom_schema`, with a table mapping each format version (`schema_version`) to the
   first release that reads it. Today two rows: format 1 = every repo written before 0.2.0 (no
   `schema_version` field; absence means 1); format 2 = written by 0.2.0, read by 0.2.0 and later.
   One sentence on when a row is added (only when the number moves, which is only on a break).
2. The five "upgrade datom" messages suggest `install.packages("datom")` first, and GitHub
   (`remotes::install_github('amashadihossein/datom')`) for development builds. The five: format too
   new (`R/utils-validate.R`), manifest unreadable (`R/manifest-rebuild.R`), unknown field and
   restructured file (`R/forward-compat.R`, two messages), writer floor (`R/forward-compat.R`).
3. The four format-related messages (all but the writer floor, which already names the exact version
   needed) also point at `?datom_schema`.
4. No condition class changes; only message text.

### R3. Gate the two unnumbered set rules (#111)

1. In `.kiro/specs/datom-sets/requirements.md`, define **AC42** (a written set's metadata document
   carries exactly the fields R1.3 lists, asserted with `setequal()` on the written file) and
   **AC43** (a hand-assembled member list is refused, with a message pointing at `datom_member()`),
   each beside the statement it numbers.
2. Append a task to `.kiro/specs/datom-sets/tasks.md` that owns AC42 and AC43 and says it was added
   after completion by the `set-followups` spec.
3. Label the two existing tests in `tests/testthat/test-write-set.R` with the identifiers.
4. Each is probed: break the behaviour, confirm the named test fails, restore.

## Acceptance checks

- [x] AC1 `datom_find_member(x, "lb")` on a set read back returns the one record; the same call on
      `x$members` returns the identical record.
- [x] AC2 An ambiguous name is refused with the message naming both candidates; `tags =` and
      `version =` (prefix) each narrow it to one.
- [x] AC3 The lookup works with no connection and no storage access (a test proves no storage read).
- [x] AC4 A non-set, non-list `x` is refused with a clear message.
- [x] AC5 No reference to `.datom_find_member` remains in `R/` or `tests/`.
- [x] AC6 `?datom_schema` exists, renders in `R CMD check`, and carries the two-row table.
- [x] AC7 Each of the five upgrade messages suggests `install.packages("datom")`; the four
      format-related ones name `?datom_schema`; the writer-floor one does not.
- [x] AC8 `Rscript dev/check-spec.R` (default spec, datom-sets) passes, reporting 43 criteria defined
      with AC42 and AC43 named under `tests/`. **Met 2026-10-09 after one owner-agreed change**: the
      "code citations" check had failed on `dev` before this spec, because most of datom-sets' line
      citations had drifted. Rather than fix line numbers that re-drift, Task 4 made line problems
      in a closed spec a note, added check 4b (cited function names still exist), and set the
      convention to cite by function name. The checker now exits 0.
- [x] AC9 Each new guard or behaviour above has a test that was watched failing when that behaviour
      alone was broken.
- [x] AC10 Full suite passes with the count reported; `R CMD check --as-cran` 0 errors, 0 warnings.
