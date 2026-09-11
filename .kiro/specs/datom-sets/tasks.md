# Tasks -- datom sets (second artifact kind)

**Source issue**: [#89](https://github.com/amashadihossein/datom/issues/89) -- plus **three delta
comments on that issue** that amend it (joint-repo decision; E1 question resolutions; the sv1
payload/encoding restructure). All three are already applied here, so this spec -- not the issue
body alone -- is the current truth.
**Branch**: `spec/datom-sets`, cut from `dev`. **PRs into `dev`, not `main`** -- **0.1.2 is submitted
and awaiting CRAN**, so `main` stays frozen for the same reason it always did: if CRAN asks for
another fix, `main` must keep matching what they received (see `dev/README.md` "Branching During CRAN
Submission" for current heads). `main` is also protected and takes only PRs, enforced for admins.
Draft PR [#97](https://github.com/amashadihossein/datom/pull/97) is open and accumulates the task
commits.
**Test baseline**: 2460 at spec start -> 2482 after Task 1 -> 2572 after Task 2 -> 2612 after
Task 3 -> 2660 after Task 4 -> 2664 after Task 18 -> 2675 after the two operator-facing fixes
that followed it (see the 2026-08-26 rows in the Decisions log) -> 2686 after Task 19 -> 2740
after Task 5 -> 2748 after the escape-code fix that followed it -> 2836 after Task 6 -> 2861 after the
four review findings that followed it -> 2863 after its purity audit -> **2867 after the two loose
ends the second review pass found -> 2898 after Task 20 -> 2902 after the review that followed it
-> 2905 after the classify-late guard -> 2959 after Task 21 -> 2965 after the three review findings
that followed it -> 3050 after Task 22 -> **3053 after the three review findings that followed
it**. Report the count in every commit
message; it must never drop.

---

## Where things stand

**Done**: Task 0 (spec), **Task 1** (stale docstring sweep + relative-key helpers), **Task 2**
(`datom-sv1`), **Task 3** (`datom_storage_read_json()` + the relative-key validator), **Task 4**
(the reader-side `schema_version` gate), **Task 18** (the `.datom_check_git_current()`
fetch-failure defect, #104), **Task 19** (allowlist identity hashing, #100) **Task 5** (one
manifest reader + one skeleton builder), **Task 6** (the artifact-namespace rename plus the
old-format conversion), **Task 20** (unfamiliar fields survive a write), **Task 21** (the writer
refusals) and **Task 22** (the reader-side rebuild), plus three things
that are not tasks: the prerequisite #89
named ([#95](https://github.com/amashadihossein/datom/issues/95) / PR #96, landed on `dev` *before*
this branch was cut, deliberately outside this history), `dev/check-spec.R`, and
`.kiro/steering/communication.md`.

**TASK 22 IS CLOSED. EVERY PHASE E TASK THAT HAD TO RUN EARLY IS DONE; ITS SIXTH (TASK 23, ADDED LATER) RUNS IMMEDIATELY BEFORE TASK 11. NOTHING IS OWED BEFORE TASK 7.** A reader that meets a
manifest whose artifact list it cannot use no longer reports an empty repo. It lists storage instead,
reconstructs the index from the per-artifact documents that hold the same facts, and **warns once**
naming the upgrade. Two conditions bring it there -- the artifact key is absent after the conversion,
or the document declares a format above what this build supports -- and they are the same two that make
a **writer** refuse. Same evidence, opposite responses; that asymmetry is the reads-limp / writes-stop
rule and must not be "unified". It lives in the new `R/manifest-rebuild.R`, is reached only from inside
`.datom_read_manifest()` when `operation = "read"`, and **writes nothing** at any role. **Four things a
later change must not undo.** (1) The trigger is **absent**, never *empty* -- empty is what a new repo
and a truncated file both look like. (2) A rebuilt row is stamped `kind = "table"`, because nothing in
per-artifact metadata says what kind an artifact is until Task 7; an untyped row is uncounted, so a
rebuilt repo would list its artifacts while reporting zero of them. (3) `current_version` is the
version **recorded** in the history, never recomputed -- and not simply the newest entry, since a write
reverting to earlier content appends none. (4) The artifact loop is `lapply()`, not `purrr::map()`,
because purrr re-signals a mapped function's condition as its own and the caller dispatches on the
class. Full reasoning in Task 22's DONE record.

**Also from Task 22: `original_format` is now written into per-artifact metadata**, not only onto the
manifest row, which is what made it recoverable. It is classified **not identity** -- the symmetric
choice with its sibling `original_file_sha` would have re-minted a version for every imported table in
every repo, on content that did not move.

**TASK 21 IS CLOSED.** A write now stops at a door before it does
anything, when this build cannot fully account for the repo it is writing into: the repo declares a
minimum datom version this build is below, the manifest declares a format this build does not know, the
conversion cannot reach an artifact list, or any of the three documents the write touches carries a
top-level field this build cannot classify. All of it is one function,
`.datom_check_write_entry()` in `R/forward-compat.R`, and it reads the clone's copies only -- local
file reads, no network. **Two things about it a later change must not undo.** (1) The vocabulary check
runs on the **converted** manifest, never the raw one: a pre-rename document keeps its list under the
old key, so checking the raw document would refuse every existing repo. (2) The shape refusal is
"still absent **after** the conversion ran", not "absent" -- the other wording deadlocks the upgrade
it exists to protect. **One deviation from the written design, recorded rather than quiet**: design
10.7's step 1 fetch is not implemented, because a fetch does not refresh the working tree and so cannot
make any of the four checks read a fresher document; the freshness problem it was aimed at is solved by
re-running the sequence after the one route that pulls. Full reasoning in Task 21's DONE record.

**Two things Task 21 leaves for whoever adds a field to a datom-owned document next.** (1) There are
now **three** vocabularies, one per document scope, all append-only:
`.datom_metadata_known_fields()`, `.datom_manifest_entry_known_fields` and
`.datom_manifest_known_fields`. Each has a test asserting that every field a real write produces is on
it, so an unclassified field fails there rather than refusing every subsequent write on a real repo.
(2) **Never delete a name from one of them.** `tables` sits on the manifest list marked retired, as the
worked example: a build that pruned an old name would meet an older document, fail to place a key it
should know, and refuse it -- blocking the upgrade direction, which always has to work.

**Task 6's rename shipped
2026-09-08 -- `manifest$tables` is now `manifest$artifacts`, entries carry `kind`, both manifests and
every per-artifact metadata document declare `schema_version: 2`, and a write into a repo whose format
this build does not know is refused before any hashing or file write. The conversion that keeps
existing repos readable lives in the new `R/manifest-upgrade.R`: reads convert in memory and leave the
file alone, writes convert the file and then stamp the version reached. All five of Task 6's open
calls were taken at their stated defaults, each recorded with what shipped in the DONE record at the
end of that task.

**Task 20 shipped the same day**: a top-level field this build cannot place now survives a write
instead of being deleted by the rebuild. It lives in a new `R/forward-compat.R` and is called from two
places, `datom_write()` and the manifest entry updater. **Three things about it that a later change
must not undo.** (1) The manifest's **top level** needed no code -- it survives because that document
is read, edited and written back rather than rebuilt, so a refactor to rebuilding it would end the
guarantee without failing anything except the one test written for exactly that. (2) **Only
unplaceable fields are carried.** A field datom knows still disappears when the write does not set it,
which is what stops a stale "this came from a CSV" claim outliving the version it described. (3)
`.datom_metadata_known_fields()` is a **function** because `R/` is sourced alphabetically and that
file sorts before the one holding the two halves it joins -- as a stored vector the package would not
install. **A fourth surface exists that the requirement does not name**: an entry in
`version_history.json`, safe by the same edit-don't-rebuild property and now pinned by a test, because
Task 7 and Task 15 both add fields to those entries.

**It took four commits, not one, and two things the follow-ups changed will bite whoever edits this
code next.** A review found four defects in the first commit, a purity audit followed, and a second
review pass found two loose ends; all of it is in the Decisions log (2026-09-08) and in Task 6's DONE
record. The two worth knowing before you touch anything:

* **Selecting artifacts by `kind` goes through `.datom_artifacts_of_kind()` and nowhere else.** The
  predicate had been written out at four sites and one copy lost a tolerance, which aborted
  `datom_status()` on a manifest entry the conversion step deliberately preserves. Do not re-inline it.
* **`datom_list()`'s zero-row frame is built by `.datom_empty_artifact_frame()`** and must carry the
  same columns a populated result would, `version_count` included when `include_versions = TRUE`. Two
  commits fixed two halves of that one defect; a third would be embarrassing.

**The purity audit E2 required is DISCHARGED, and its method is the reusable part.** Both of its
questions were answered by breaking the code on purpose and counting what reddened, not by reading:
deleting the artifact key from the shared reader reddens 64 assertions across 36 tests, and making an
untyped entry abort inside the selection helper reddens exactly one. It also caught two tests that
were passing whatever the code did.

**Start here.** Branch `spec/datom-sets`, working tree clean, **3053** tests
(FAIL 0 / WARN 0 / SKIP 0), `dev/check-spec.R` 9/9, and `R CMD check` 0/0/0 on docs and
code/documentation agreement (tests and examples run separately). Next is **Task 7**.

**The submission freeze still holds**: 0.1.2 is in flight, so `main` must keep matching what CRAN
received, and this branch PRs into `dev`. Branch heads live in `dev/README.md` "Branching During CRAN
Submission" rather than here, so there is one copy to keep true. One thing worth knowing before
touching anything git-adjacent: three tools misbehave silently in a git worktree because `.git` is a file
there rather than a directory, and one of them cost us the 0.1.2 submission record -- see
`dev/engineering-notes.md`, "In a git worktree, `.git` is a FILE".

**Next when work resumes**: **Task 7 -- `kind` in per-artifact metadata, the set metadata builder, and
`document_sha` in the history entries.** This is the first task of the set work proper: the five Phase E
tasks that had to run early are all done, and Phase E's sixth (Task 23) runs later, immediately before
the task it protects. Nothing is owed before Task 7. **Five things the finished tasks leave sitting
under it, so they are not re-derived.**

1. **Two forcing functions will go red the moment you touch a builder, and that is the design.** The
   classification test in `test-utils-sha.R` derives its field inventory from the builders themselves,
   so every field this task adds fails until it is classified -- `kind` into the identity list, each
   set field decided one by one against design.md section 4's matrix. The vocabulary test in
   `test-forward-compat.R` does the same for the write-side field lists. Neither is a test to update;
   each is the point at which the decision gets made.
2. **A second forcing function fires from the opposite direction.** `test-utils-sha.R` also asserts
   that nothing is classified *before* something writes it, with a short exception list carrying a
   reason per name. Adding a field to a list without adding it to a builder now fails there.
3. **Task 22 hardcoded `kind = "table"` on a rebuilt manifest row, and this task is the owner of that
   line.** Once metadata declares its own kind, `.datom_rebuild_manifest_entry()`
   (`R/manifest-rebuild.R`) should read it from the document and fall back to `"table"` only for
   documents written before it did. The comment at the site says so. Left as-is, a rebuilt set is
   reported as a table.
4. **`document_sha` in `version_history.json` is safe; in `metadata.json` it is not.** History entries
   are prepended to, never rebuilt, so a field on an older entry survives. A metadata document is
   rebuilt from scratch on every write, and `document_sha` is a name this build already classifies and
   never writes -- so the carry-forward rule, which rescues only names a build **cannot** place, does
   not rescue it. Moving the field into `metadata.json` is a decision with a consequence, not a
   tidy-up.
5. **Nothing writes a `kind = "set"` entry yet, so a counter filter passes whether or not it is there.**
   Any assertion about set counts needs a hand-built manifest holding a set entry beside table entries;
   `dev/engineering-notes.md` has the two spellings that go quietly wrong.

**Task 7 was cold-start audited on 2026-09-10 and is startable.** Its body now carries the audit, and
the two things most likely to derail a fresh session are in it: **adding `kind` re-mints a version for
every existing table**, which is an accepted owner decision from 2026-08-23 rather than a defect (both
of the obvious fixes were closed off then), and **this task legitimately moves two pinned identity
goldens**, which is the one licensed exception to "if a golden fails, the code drifted". Two of the
task's own statements were wrong and were corrected: it cited a field matrix in design.md section 4
that does not exist -- R1.3 is the field list -- and it said to keep `document_sha` out of the metadata
document, which contradicts R1.3 and would break the read gate. P36 was rescoped, since its first
clause asserted the opposite of what this task does.

**One task was added after Task 22 and is NOT next: Task 23, `project.yaml` declares its format.** It
sits at the end of the list but **executes immediately before Task 11**, because Task 11 is what starts
writing `mode: product` into that file and Task 23 is what lets an older build notice. Recorded now
because the reading half cannot be added to a build that has already shipped -- the same filter Phase E
used. Nothing about it blocks Task 7 through Task 10.

**Two things Task 19 leaves for whoever adds a metadata field next.** (1) `metadata_sha` now selects
fields by **allowlist**: `.datom_metadata_identity_fields` is identity,
`.datom_metadata_excluded_fields` is the documented not-identity list, and a field in **neither** is
silently outside identity. The classification test in `test-utils-sha.R` derives its inventory from
the builders, so it fails until the new field is classified -- that is the forcing function, and
**Task 7 will trip it deliberately** when it adds `kind` and the set metadata builder. (2) The union
of those two constants is the vocabulary Task 21's writer check reads; it is append-only from here.

**EXECUTION ORDER IS NOT TASK ORDER.** Phase E was appended rather than inserted so that nothing
renumbered a third time. The order is `18 -> 19 -> 5 -> 6 -> 20 -> 21 -> 22 -> 7 -> 8 -> 9 -> 10 ->
23 -> 11 onward`, and Phase
E's preamble says why each edge exists. Task 19 before Task 7 is the one that matters most: an
identity allowlist seeded from *table* metadata and landed after the set metadata builder would
silently drop set-specific fields from identity. **Task 23 before Task 11** is the other edge that is
not cosmetic: Task 11 starts writing `mode: product` into `project.yaml`, and Task 23 is what gives an
older build a way to notice -- a reading half cannot be added to a build that has already shipped, so
writing the field first would leave a permanent population treating a product repo as an ordinary data
repo. Task 11's body states the dependency, so the constraint holds from both ends rather than
depending on somebody checking the order at release time.

**Phase E exists because six things cannot be retrofitted.** The filter: does deferring it postpone
the cost, or permanently exclude every install shipped meanwhile? Allowlist hashing,
carry-unknown-fields, the writer refusals, the floor's reading half, the rebuild, and
`project.yaml`'s format check only ever help
builds that already contain them. Everything else from the same review round -- the bump rules, the
schema history table, the policy prose, the floor's tooling -- lands later without stranding anyone.
The aim is that **0.1.1 is the last release needing a transition plan.**
**Five of the six are done; the sixth is Task 23**, added later and the only one that does not run
early -- it runs immediately before the task it protects (Task 11). Phase E's preamble has the edge.

**Phase B is DONE, both halves** -- Task 5 the shared reader, Task 6 the rename itself. It was one task
until 2026-08-23 and became two (owner-decided, after the E2 design audit) because the rename's failure
mode is silent, so landing the reader first is what made the rename's own failure loud. Task 6's
escalation E2 is fully discharged: the design spot-check before it, the purity audit after.

**The gap that caused the split, and what closed it.** Nothing upgraded an existing repo's manifest:
every repo written before Task 6 keeps its artifact list under `tables` and declares no schema version,
the reader-side check tolerates that as v1, so such a repo would have passed the check and then met a
reader looking for `artifacts` -- every discovery command reporting an empty repo without erroring.
Neither thing that might have healed it did: the entry updater stamped no schema version, and a
no-change write returns at `R/read_write.R:793` before the manifest is touched. Closed by R22 --
**reads upgrade in memory, writes upgrade on disk** -- shipped in Task 6 as `R/manifest-upgrade.R`. The
full reasoning, including why refusing loudly was not an option, is in design.md 10.1 and 10.2, and it
is worth reading before any later format change rather than re-deriving it.

**Task 4's gate now fires, because Task 6 is what writes the number.** Three things about it that a
later change must preserve. `.datom_check_schema_version()` is the **one** implementation and gets
reused rather than reimplemented -- Task 6 gave it an `operation` word and nothing else. Its
**placement relative to error handling is load-bearing**: three reader sites wrap their read in a
handler that softens failures, and a check placed inside one reworded the upgrade instruction as
"could not read manifest" (`datom_status()` went further and downgraded it to a warning while
continuing). Task 4 held that line with a comment at each site; Task 5 replaced the comment with
structure, by having the shared reader **return** IO failures as data and **throw** schema refusals, so
there is no handler left for a caller to put the check inside. And the **check runs before the
conversion chain**, never after: there is no upgrade step for a version this build does not know, so the
dispatcher must never see one (I32).

**Task 3's validator is now the thing to reuse, not to rewrite.**
`.datom_validate_rel_key()` (`R/utils-validate.R`) guards any *caller-supplied* whole key. The
Task 1 key builders in `R/utils-path.R` deliberately do **not** call it -- they compose keys from
parts already validated by `.datom_validate_name()` / `.datom_validate_sha()`, so their output
cannot contain a `..` segment or a `datom` segment and the check would be dead code. Reach for the
validator when a key arrives from outside datom; reach for the builders when datom composes one.

**THE GOLDENS ARE PUBLISHED AS OF TASK 2, SO THE ENCODING IS FROZEN.** Changing any sv1 byte rule
from here is a conscious `datom-sv2` bump with a new `hash_algo` identifier -- not a spec edit, not a
code fix. The three places that hold it: `R/hashable-set.R` (implementation),
`dev/datom_sv1_reference.R` (normative byte rules + marker table), and the hard-coded constants in
`tests/testthat/test-hashable-set.R`. If a golden ever fails, the code drifted; do not update the
constant. E1's discharge record and the four deltas it produced are in the Decisions log
(2026-08-17); nothing about it is open.

**Open with the owner**: **nothing.** Task 6's six defaulted items were all taken at their defaults on
2026-09-08 and each is recorded with what shipped in that task's DONE record; its purity audit is
discharged. **One of the six was later reversed** by review and is logged as a reversal:
`datom_list()`'s empty result now carries the columns a populated one does, where the recorded default
had been to leave that difference alone. Nothing else is open either: the
AC33(a) anchoring item that sat here on 2026-08-26 was decided the same day and **implemented as
decided on 2026-08-28** -- the realistic fixture was pinned in its own commit under the pre-change
code, and the `name`-bearing golden became AC33(b)'s test.

**Also on this branch, outside the task list**: three operator-facing fixes -- two that followed
Task 18 (the merge-conflict message, and `datom_validate(fix = TRUE)` no longer claiming to repair a
missing payload) and one that followed Task 5 (terminal escape codes stripped from the three error
strings datom *returns*, rather than prints) -- plus
[#105](https://github.com/amashadihossein/datom/issues/105) and a `dev/README.md`
Backlog row capturing five deferred ideas for making a push-rejected write rarer and recoverable
without git skill. Nothing there blocks Task 6.

**Superseded note**: this slot previously read "nothing". Task 2 added three encoder refusals the spec did not spell out
(named list in a value position; unexpected field at the payload root or in a member record) -- all
three prevent content sitting outside identity, none changes a golden, and all are logged below
(2026-08-18) rather than left to be rediscovered.

**Before each commit** (the chunk gate):

```
Rscript -e 'devtools::test()'      # report the count; it must not drop
Rscript dev/check-spec.R           # structural gate on this spec -- see dev/README.md
```

`check-spec.R` runs **nine** checks: dangling `R*/I*/P*/AC*` references, orphaned criteria, task
numbering, tasks missing an `Acceptance:` clause, code citations pointing outside the file, retired
wording surviving as a live instruction, **duplicated content agreeing** (check 6), ASCII, and
**every `Task N` reference resolving to a task that exists** (check 8, added with the 2026-08-23
renumber and verified by reintroducing a dangling reference).

**Check 6 guards the encoding pseudocode**, which is written out in all three spec files: it asserts
all six encoder rules are present in every file and byte-identical modulo whitespace. That exists
because a delta once fixed the formula in `design.md` only, leaving `requirements.md` and `tasks.md`
stating the opposite *inside the task that froze the goldens*. Now that the goldens are published the
pseudocode is a **record of what shipped**, so a disagreement between the three copies is a
documentation defect rather than an implementation risk -- and the copy that matters most is the one
the next reader trusts.

**Check 6 also guards the execution order**, added 2026-09-10 for the same reason: the
`18 -> 19 -> ...` sequence is written out three times -- the state block at the top of this file,
Phase E's preamble further down, and the status cell in `dev/README.md` -- and adding Task 23 swept
one and left two saying the order ended at Task 7. Caught by a reader, which is what a gate is for.
The copies are compared **against each other**, never against an expected sequence, because the order
changes legitimately and a check holding today's answer would need editing every time it moved.
`dev/README.md` is read for this one clause even though it is not a spec file, since that is where the
third copy lives and the one a person meets first. Verified by reintroducing the exact defect: both a
stale preamble and a stale README FAIL, and the output names which copy is behind.

It is **structural only**, and do not over-trust it: on the round that added check 6 it passed on all
six sites of the defect it was supposed to catch, because its retired-wording suppression list was
too permissive. Both it and check 6 have since been **verified by deliberately reintroducing the
defect** and confirming a FAIL. Do that for any new check you add -- a green run is not evidence.
Reasoning defects still need a reader.

**Read before editing `R/`**: `dev/engineering-notes.md`. The three most relevant entries for the
remaining tasks are the **two key shapes** (full vs relative -- mixing them double-prefixes
silently and does not error), **payload key vs snapshot key** (different directories, both `.json`
for a set), and the new **`datom-sv1` set identity** section (what the encoder refuses and why, and
the one trap that a test caught during Task 2).

**One repeating defect pattern, worth knowing.** Five review rounds found the same class: an encoding
change swept some places and left others stating the old mechanism -- the invariant/property tables in
design.md, Task 2's own bullets, the pseudocode copies. The last round left **six** such sites and the
gate passed on all six.

What to do if you change the encoding -- which now means shipping `datom-sv2`, so all of this applies
to the *new* regime's documentation, and the sv1 copies become historical rather than edited:

1. **Pseudocode: edit all three copies** (`requirements.md` R2.10, `design.md` 7.2, `tasks.md` Task
   2). Mechanically guarded now -- check 6 will catch you.
2. **Prose: sweep requirements, the design invariant/property tables, and the task bullets**, then add
   the retired phrasing to the `retired` denylist in `dev/check-spec.R`. Not mechanically guarded
   until you add the phrase.
3. **Counts and ranges: never restate one.** A spelled-out criteria count and a literal
   first-to-last AC range both went stale here; check 6 now forbids an explicit AC bound anywhere in
   the spec. Derive the list, don't restate its edges. (Check 6 is strict enough that even *quoting*
   a stale range as an example trips it -- which is why this bullet describes the shape in words.)
4. **Prove any new gate fails before trusting it.** Two consecutive rounds shipped a check that
   passed on the defect it existed to catch.

One task (or a small related group) = one chunk = one commit. Mark the checkbox in the **same
commit** as the code, and update the `dev/README.md` Active Specs status line. Per Operational
Discipline rule 5d, **STOP after each chunk** and wait for explicit go-ahead.

**Escalation flags** (design.md section 12) are marked inline. A flagged task **must** re-surface
its escalation recommendation in that chunk's checkpoint message, whether or not it still seems
necessary.

---

## Task 0 -- Spec creation

- [x] **0. Create the spec and register it**
  - `.kiro/specs/datom-sets/{requirements,design,tasks}.md` translated from #89 at full detail
  - Register in the `dev/README.md` Active Specs table
  - Prerequisite #95 (copilot-instructions compatibility posture) landed on `dev` separately via
    PR #96, deliberately outside this branch's history
  - _No code. Docs only._

---

## Phase A -- Contract-neutral groundwork

- [x] **1. Housekeeping: stale docstrings + relative-key helpers**
  - Fix the stale "task 5.1" `parquet_sha` claims at `R/read_write.R:110-113`, `205-206`, `413`,
    and reword the already-correct-but-now-inconsistent comment at `393` (R13.3 has the site
    table). History **has** persisted `parquet_sha` since #72; only pre-#72 legacy entries lack
    it. Drop the internal task references entirely per the Don'ts. **Note #89's `95-97` citation
    is wrong** -- that is the function title; verified with `grep -n "task 5\.1"`.
  - Add `.datom_artifact_payload_key()` / `.datom_artifact_meta_key()` /
    `.datom_artifact_snapshot_key()` to `R/utils-path.R` -- **relative** keys, per design.md
    Deviation D1. `.datom_build_storage_key()` stays unchanged as the backend-internal full-key
    builder.
  - Fold `.datom_validate_sha()` / `.datom_validate_name()` guards into the helpers (I9).
  - Migrate existing `paste0` key call sites in `R/read_write.R`, `R/query.R`, `R/lineage.R`,
    `R/validate.R` to the helpers. Behavior-identical -- assert with the existing suite.
  - File the separate issue for the `metadata_sha` emitter-drift exposure (design.md section 16).
    Do **not** implement it here.
  - **DONE 2026-08-17.** Filed as [#98](https://github.com/amashadihossein/datom/issues/98).
    Four stale "task 5.1" docstrings reworded (105-108, 205-206, 393, 413) plus **three
    pre-existing phase/chunk comments** the Don'ts forbid, found while sweeping
    (`R/conn.R`, `R/governance_json.R`, `R/utils-gov.R` -- the last was doubly stale, pointing at
    a gov write surface that has since been lifted out). Three relative-key helpers added to
    `R/utils-path.R` and **16 of 17** hand-rolled key sites migrated across 7 files
    (`read_write.R`, `query.R`, `lineage.R`, `validate.R`, `sync.R`, `utils-sha.R`).
    tests: **2482** (+22).
  - **Deliberate exclusion**: `R/sync.R:250` still builds its key with `paste0`. It splices a
    *discovered filename* (already `{sha}.json`) rather than a bare sha, so the helper's sha guard
    does not fit, and adding one would change behavior -- a stray `.json` in `.metadata/` would
    start aborting instead of being uploaded. Commented in place.
  - **SCOPE DEVIATION -- OWNER-APPROVED 2026-08-17, the guard stays.** This chunk was scoped
    behavior-identical,
    and folding `.datom_validate_sha()` into the payload-key helper is **not**: it closed a real gap
    (`.datom_validate_one_table()` spliced `meta$data_sha`, read from a file, into a storage key with
    **no** validation -- #74's guard sweep missed this site, so a corrupt or hostile `metadata.json`
    containing `../../x` could probe outside the namespace on the local backend). One test fixture
    used `data_sha = "d1"`, a value that cannot occur in real data since every sha is 64 hex, and it
    was updated to a realistic digest. Observable behavior for *valid* data is unchanged, and a new
    test pins that a corrupt `data_sha` still surfaces as a `data_missing_s3` finding rather than
    aborting the validation run.
  - _Requirements: R5.2, R13.3. Invariants: I9. **Acceptance: none by design** -- this chunk is
    contract-neutral (docstring wording plus behavior-identical key helpers), so the existing
    suite passing unchanged *is* the assertion. Recorded explicitly so the absence is not read as
    an omission. No pathway impact._

- [x] **2. `datom-sv1` canonical set-content hash** &nbsp; **[ESCALATION E1 -- design review DONE 2026-08-17; implemented 2026-08-18. The goldens below are PUBLISHED: the encoding is frozen.]**
  - **All five open questions are settled** (owner-decided 2026-08-15, design.md 7.5). The
    escalation is now a **design review of the encoding specification**, not a debate: exact byte
    rules, whether the tag table leaves a collision surface, and whether the goldens cover the
    7.3 agreement cases. The goldens still freeze the encoding -- a later change needs a conscious
    `datom-sv2` bump.
  - **Q1 whole payload.** `data_sha` covers members **and** their tags (a description is a tag). A tag
    or description edit **mints a new version** -- intended, not a bug to engineer away (R2.6).
    This makes AC2 two-sided: identical *payload* is a no-op, identical *members with a changed
    tag* is **not**.
  - **Q2 absence is omission; `NA` is an error.** Adopt datom's existing "omitted, not nulled"
    convention (`R/read_write.R:302-305`) as the canonical form. A literal `NA` reaching the
    encoder **aborts** with "not encodable -- omit the field instead". Goldens carry the
    **refusal**, not an `NA` encoding. Note `null` therefore has **no marker** in the encoding (R2.7).
  - **Q3 empty set refused.** `datom_write_set()` with zero members aborts, mirroring
    `.datom_canonical_hash()`'s zero-dim abort (`R/utils-sha.R:310-312`). Update AC5: refusal is
    the tested behavior (R2.8).
  - **Q4 `schema_version` stays out** of the payload and the hash -- container format, not content;
    in identity it would re-mint every set on a format bump (R2.9).
  - **Q5 emitter-free hash.** **No serializer in the identity path.** The construction is the
    hash-of-hashes in the next bullet -- **not** a walk with per-type dispatch, which was the
    superseded formulation (F-A). `jsonlite` may format the **stored** file however it likes,
    because stored-byte integrity is `document_sha`'s separate job. **Identity and storage integrity
    never share a dependency.**
  - **The encoding is a hash-of-hashes over 3 primitives + 2 shape rules** (R2.10, design.md 7.2),
    **not** a runtime type-dispatch walk -- that earlier formulation had a structural gap (F-A) and
    is superseded:

    ```
    str(s)    = h(0x01 || utf8(s))
    strset(v) = h(0x02 || concat(str(e) for e in sort(unique(v), radix)))
    map(m)    = h(0x03 || concat(str(k) || strset(m[k]) for k in sort(keys(m), radix)))
    member(x) = h(0x04 || map(x.id) || map(x.tags))
    set(p)    = h(0x05 || map(p.tags) || concat(sort(unique(member(m) for m in p.members), radix)))
    data_sha  = h(0x06 || utf8("datom-sv1") || set(payload))
    ```

    Member digests sort as **lowercase hex**, `method = "radix"`, emitted as raw bytes.

    Mirrors cv1's per-column-digests-then-hash-the-concatenation pattern, so both references share
    one house construction.
  - **No length prefixes**: every intermediate is a fixed 32 bytes, so concatenation is already
    unambiguous. **`f64le` disappears from sv1 entirely** -- `.datom_encode_numeric()` is not used
    at all, not even for lengths. sv1 shares no numeric primitive with cv1.
  - **Every collection is sorted and deduped -- `members` included, with no carve-out.** An earlier
    draft made member order identity; **retired** (R2.12 carries the three arguments, chiefly that a
    script-generated member list would mint spurious versions on an insertion-order refactor).
    Sorting members means sorting their fixed 32-byte digests. A single string equals a one-element
    set (R2.13).
  - **No Unicode normalization** (R2.16). Radix sort is byte order; NFC and NFD are different tags.
    Golden asserts they differ. Do not add `stringi` -- normalization tables are versioned Unicode
    data, and putting them in the identity path is #72's failure mode with a different vendor.
  - **Pin `strset(character(0)) = h(0x02)`** as a golden (R2.17), for the same reason design.md 7.2 already
    pins the empty map: an encoder whose correctness rests on an upstream validation refusal breaks
    silently the day that refusal is relaxed.
  - **Not this task, but caused by it -- flag it forward.** Order- and shape-insensitivity means
    several spellings share one `data_sha`, which is a write-path correctness problem, not an encoder
    one: R2.15 (canonicalize before the local write) and R7.5 (never re-emit for a known `data_sha`;
    bind `validate(fix = TRUE)` too). Owned by Tasks 9 and 14. Design.md 7.2.3 explains why. Left
    undone, the failure is a **refused read of a valid version**, and every per-chunk test passes.
  - **`id` is encoded with `map`, not positionally**, so a fifth id field later is just another key.
    Validation, not the encoder, enforces "id has exactly these four keys, each single-valued".
  - **The encoder does NOT validate, and this task does not own AC27.** Grammar enforcement lives in
    `.datom_validate_members()` (Task 8, per-member) and `datom_write_set()` (Task 9, payload-level),
    because design.md 7.2 and R2.10 both put the encoder out of validation's job -- and because the
    payload-level cases are invisible from here: the encoder never sees two members at once in a way
    that distinguishes "same `id`, different `tags`" from two ordinary members. An earlier draft had
    Task 2 and Task 9 both claiming AC27; **retired**.
  - Payload shape is **fixed** (R2.12): optional set-level `tags`, then `members[]` each with
    an `id` record `{project, name, kind, version}` and optional per-member `tags`. Depth is bounded by the schema,
    not by what a caller nests.
  - **The R2.5 hard constraint still governs**, with its mechanism restated: write-time and
    read-time hashes must agree, and they now do **by construction** rather than via a
    serialize/parse cycle. Every mutation is **unrepresentable**, not handled (design.md 7.3):
    numbers and booleans are not in the grammar; `NA` aborts; `null` has no marker; and
    scalar-vs-one-element-array is **immaterial because the two hash equal** (R2.13). **Do not write
    an f64 rule and do not write an atomic-vs-list rule** -- both were removed, and an earlier draft
    of this bullet still instructed them. The one supporting condition is structural: read with
    `simplifyVector = FALSE` so `members[]` stays a list of records rather than collapsing to a data
    frame. **Already satisfied** by both backends (`R/utils-local.R:110`, `R/utils-s3.R:209`).
  - `.datom_sv1_str()` / `.datom_sv1_strset()` / `.datom_sv1_map()` +
    `.datom_canonical_set_hash()` go in a **new `R/hashable-set.R`**. *(Decided at the E1 review,
    2026-08-17 -- an earlier draft left this as "decide at the review", which would have dangled once
    the review closed.)* Rationale: cv1's equivalents sit in `R/utils-sha.R`, already 565 lines and
    holding three unrelated concerns (`.datom_encode_numeric`, `.datom_canonical_hash`,
    `.datom_compute_metadata_sha`); sv1 shares **no** primitive with any of them, so co-locating buys
    nothing and worsens the biggest file. A sibling file also mirrors the existing
    `R/hashable.R` naming, which is where #72 put the cv1-adjacent surface.
    **`.datom_encode_numeric()` is NOT used** -- sv1 has no numeric primitive at
    all now that length prefixes are gone, so there is nothing to share with cv1 beyond
    `digest::digest(..., algo = "sha256", serialize = FALSE)`. (Superseded instruction: an earlier
    draft said to reuse it verbatim for `f64le` framing.)
  - `dev/datom_sv1_reference.R`: standalone, `digest`-only, self-testing, prints goldens --
    mirroring `dev/datom_cv1_reference.R`. It is the **normative home of the byte rules and the tag
    table**, written against the encoding spec and **not** against any emitter's output.
  - Extend `.github/workflows/cv1-reference-parity.yaml` (do not add a second workflow) to run the
    sv1 reference and assert package/reference parity on x86_64 **and** arm64.
  - **Goldens are gated on this delta landing** -- post-goldens, any of the above becomes a breaking
    `datom-sv2` bump rather than a spec edit. Hard-coded in tests, cross-architecture asserted, and
    covering the **seven** identity-boundary fixtures of AC13, which is authoritative -- **Equal**:
    (a) tag-value order, (b) tag-value duplication, (c) **member order**, (d) single string vs
    one-element array, (e) member duplication. **Different**: (f) NFC vs NFD. **Pinned constant**:
    (g) `strset(character(0)) == h(0x02)`. Note (c) and (d) each **reverse** an earlier fixture that
    required a difference. Plus the AC27 grammar refusals.
  - **DONE 2026-08-18.** New `R/hashable-set.R` (the encoder: `.datom_sv1_str/_strset/_map/_member/_set`
    plus `.datom_canonical_set_hash()` and two byte helpers), new `dev/datom_sv1_reference.R`
    (standalone, `digest`-only, **44** self-tests, prints the goldens), new
    `tests/testthat/test-hashable-set.R`, and `.github/workflows/cv1-reference-parity.yaml` extended
    in place to run the sv1 reference and both parity test files on x86_64 and arm64 with the
    existing nothing-may-skip assertion. No new export, so NAMESPACE and `_pkgdown.yml` are
    untouched; nine internal `man/dot-datom_sv1_*.Rd` pages generated. tests: **2572** (+90),
    FAIL 0 / WARN 0 / SKIP 0.
  - **The published goldens** (recorded here so a reader need not run anything to know what is
    frozen):

    | Constant | Value |
    |---|---|
    | `strset(character(0))` = `h(0x02)` | `dbc1b4c900ffe48d575b5da5c638040125f65db0fe3e24494b76ea986457d986` |
    | `map(NULL)` = `h(0x03)` | `084fed08b978af4d7d196a7446a86b58009e636b611db16211b65a9aadff29c5` |
    | `str("a")` | `e3254ea61c09ead5a01d3bf07e946a561c6c2cd1c46b8ca1bfa8729d26a7d09f` |
    | golden payload `data_sha` | `e87c6e7be35a0198356e19a77d1acdd57e8f17f3f425320f3297206583d36c7a` |
    | minimal payload `data_sha` | `f434fcd31c1393721087859182cbdd9fad0372b65dc1dfd6b36d2cfe14c3e782` |

    The three primitive pins were **cross-checked against an independent SHA-256 implementation**
    (`printf '\x02' | shasum -a 256` and friends), so they assert that the marker bytes really are
    what the specification says rather than only that datom agrees with itself. Intermediates are
    pinned as well as the final values, carrying forward the cv1 lesson that a golden mismatch which
    names the *stage* is a quick fix while one that names only the total is a bisect.
  - **THREE ENCODER REFUSALS THE SPEC DID NOT SPELL OUT.** All three exist for one reason -- an
    ignored field is payload content that never enters identity, so two different payloads would
    share one `data_sha` **and one storage address**. That is the failure the whole regime exists to
    prevent, so silence was not an option; and none of them changes a golden.
    1. **A named list in a value position is refused.** This is the sharp one, and a test caught it
       while being written. Element-wise, `list(b = "c")` and `list("c")` are indistinguishable: both
       are a one-element list holding one string. An encoder that checked only elements would
       therefore hash `{"a": {"b": "c"}}` exactly as `{"a": ["c"]}`, silently dropping the inner key
       out of identity. The check is `is.list(v) && !is.null(names(v))` -> abort.
    2. **An unexpected field at the payload root is refused** -- which is also how R2.9 becomes
       structural rather than aspirational: a payload carrying `schema_version` aborts instead of
       being quietly hashed without it.
    3. **An unexpected field in a member record is refused** (anything besides `id` and `tags`).
  - **Two implementation notes for anyone touching the encoder.** Intermediates are **raw 32-byte
    vectors, not hex** -- hex appears in exactly two places, the member collation key and the final
    `data_sha`, which is what the spec names. And the `NA` refusal sits **after** the type gate,
    except for an all-`NA` logical which is caught before it: `is.na()` on a closure warns rather
    than answering, so a `tags = list(t = mean)` fixture emitted a warning against a suite that holds
    at WARN 0. A bare `NA` is a logical, so it still reports "omit the field" rather than a type
    error, which is the advice R2.7 wants.
  - **`strset(list())` equals `strset(character(0))`.** `[]` is the parsed spelling of an empty
    string set, and write/read agreement requires the two to hash equal -- so the R2.17 pin covers
    both spellings, not just the R one.
  - **AC13-P is asserted through the real local-backend store** (`.datom_storage_write_json()` ->
    `.datom_storage_read_json()`), not a hand-rolled `jsonlite` round trip, so it also proves the
    backends preserve `members[]` as a list of records. That structural condition is additionally
    asserted on the parsed object directly rather than inferred from the hashes matching.
  - **Deliberately not done here** (flagged forward, unchanged): R2.15 canonicalization and R7.5
    byte-identity are Tasks 9 and 14; AC27 grammar enforcement with user-facing recourse is Tasks 8
    and 9. The encoder refuses what it cannot encode; it does not name offending keys with remedies.
  - _Requirements: R2.1-R2.14, R2.16, R2.17 (**not** R2.15 -- that is Task 9's, per the flag-forward
    bullet above). Invariants: I13, I24. Properties: P1, P2, P3, P4, P5, P6,
    P8, P12, P15, P28, P30, P31, P33. Acceptance: **AC13 (both levels)**, AC3, AC5. **Not AC27** --
    see the encoder-does-not-validate bullet. No pathway impact._

- [x] **3. Export and harden storage JSON GET** &nbsp; **[SCOPE REDUCED 2026-08-18: the write export is dropped; DONE 2026-08-21]**
  - **Deliverable: `datom_storage_read_json()` only.** Wraps `.datom_storage_read_json()`
    (`R/utils-storage.R:66`). Harden: conn class check, relative-key validation, clear abort on an
    absent key, no direct `.datom_s3_*()` reachability (I7).
  - **`datom_storage_write_json()` is NOT built.** Owner-decided; R12.4a, I14 and AC23 are retired
    with it and P18 is restated. The short form: the export's stated purpose was to let a downstream
    package write *its own document* into datom's namespace, that document was a set, and
    `datom_write_set()` (Task 9) now writes it as a first-class artifact -- so no consumer remains.
    It also cuts against the Authority Principle in `dev/datomanager_scope.md` ("data-repo mutations
    always route through datom ... datomanager never touches the data repo directly"), whose
    expression is a **purpose-built verb per need**, not a generic byte channel; the
    `governance.json` data-side mirror is the precedent, where datom gave datomanager
    `datom_repo_attach_governance()` rather than a generic write. Deferral is the cheap direction:
    adding an export later is additive, removing one after release is breaking. Backlog trigger is
    recorded in `dev/README.md` -- **datomanager needing to write JSON into its own gov namespace**,
    which is a *different* export (gov-scoped, no managed-key rules) and must re-derive its refusal
    list rather than inherit R12.4a's.
  - **Do not add a role check.** Reads are policy-free and no `datom_storage_*` export checks
    `conn$role` (see the landing-zone table).
  - **Landing zone, verified against the tree 2026-08-18** (so a fresh session does not have to
    re-derive any of it):

    | What | Where | Note |
    |---|---|---|
    | file for the export | **`R/storage.R`** | its header states the family contract ("exported wrappers over the internal storage dispatch layer") and the naming split `datom_storage_*` vs `datom_repo_*`. Not a new file. |
    | roxygen example to copy | `datom_storage_list()` (`R/storage.R:51`, example block just above it) | this **is** "the established bare-git-remote + local-store style": `requireNamespace("git2r")` guard, `tempfile()`, `git2r::init(bare = TRUE)`, `datom_store(validate = FALSE)`, `datom_init_repo()`, `datom_get_conn()`, `datom_write()`, `unlink()`. All four existing storage exports use it verbatim. |
    | pkgdown entry | `_pkgdown.yml`, the package-developer storage section (currently lists the four `datom_storage_*` plus two `datom_repo_*`) | add the new export there; the index must match exports exactly or `pkgdown::build_site()` errors. |
    | tests | `tests/testthat/test-storage.R` | reuse its `make_local_storage_conn()` fixture for the local backend and its `mockery` pattern for S3. |
    | role check | **none** -- no existing `datom_storage_*` export checks `conn$role`, including the destructive `datom_storage_delete_prefix()` | the family is deliberately policy-free; role gating lives on the git-mutating verbs (Task 12). Do not add one here without deciding to break that symmetry. |
    | `.access/` today | **appears nowhere in `R/`** (verified by grep) | R19.6's "safe by construction" claim therefore holds as stated -- and with the write export dropped, datom still offers no general-purpose write path, so nothing in this task can break it. |
  - **There is no relative-key validator to reuse** -- `R/utils-validate.R` has only
    `.datom_validate_name()` (`R/utils-validate.R:18`) and `.datom_validate_sha()`
    (`R/utils-validate.R:68`), and nothing validates a key. So "relative-key validation" means
    writing it. Two things it must catch, and they are different in kind:
    1. **Traversal / shape** (`..` segments, leading `/`, empty, non-scalar) -- an I9 concern, and it
       applies to a **read** as much as to a write. "Reads are unrestricted" was always about
       *managed keys*, never about escaping the namespace: on the local backend an unvalidated
       `../../x` walks out via `fs::path()`, which is what #74's guard sweep existed for. This is
       the load-bearing half of the task now that the write export is dropped.
    2. **A full key passed where a relative one belongs** -- the double-prefix hazard in
       `dev/engineering-notes.md`. Worth catching because it does **not** error today: the call
       resolves under `{prefix}/datom/{prefix}/datom/...` and simply finds nothing, which reads as
       "the object is missing" rather than "the key was wrong". A key already containing a `datom/`
       segment is the detectable form.
  - **P18 needs nothing from this task.** Restated with the write export's removal: no public API can
    put storage ahead of git because every public write is a purpose-built verb that commits first --
    a read cannot violate it at all. Do not add a git gate to a byte-level primitive.
  - Roxygen with a runnable offline example in the established bare-git-remote + local-store style
    (exemplar cited above); `_pkgdown.yml` entry.
  - **DONE 2026-08-21.** New `.datom_validate_rel_key()` in `R/utils-validate.R` (the validator that
    did not exist), new export `datom_storage_read_json()` appended to `R/storage.R`, `_pkgdown.yml`
    entry in the existing Storage Extension API section, two `man/` pages, NAMESPACE. Tests split by
    subject: validator units in `tests/testthat/test-utils-validate.R`, export behavior in
    `tests/testthat/test-storage.R` reusing `make_local_storage_conn()` for local and `mockery` for
    S3. tests: **2612** (+40), FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all eight checks
    pass. Landing zone was accurate as recorded -- nothing in the verified table had drifted.
  - **The absent-key abort probes `.datom_storage_exists()` up front**, costing one extra round trip
    per read. Bought deliberately: the local backend already aborts clearly, but S3 surfaces the
    provider's error naming the **full** key, which is precisely the wrong thing to show a caller
    whose bug is key-shape confusion. One message, both backends, and it names the relative key that
    was passed.
  - **The full-key refusal keys on a `datom` path segment**, and that is sound rather than heuristic:
    `datom` is in `.datom_reserved_names` (`R/utils-validate.R:2-6`), so no legitimate relative key
    can contain it as a segment. Verified in the same pass that the guard is on a whole `..` segment
    and not on the dot character -- `.metadata/manifest.json`, `my.data/abc.json` and
    `dm/..hidden.json` all still pass, each with a test.
  - **No role check, as specified**, and now pinned by a test rather than left as an absence: a
    `role = "reader"` conn reads successfully. The family symmetry (no `datom_storage_*` export gates
    on role, including the destructive delete) cannot now be broken silently.
  - **Deliberately NOT retrofitted into the Task 1 key helpers.** They compose keys from parts already
    validated -- `.datom_validate_name()` admits only `[a-zA-Z0-9_ ()-]` and must start with a letter,
    `.datom_validate_sha()` only hex -- so their output cannot contain a `..` or `datom` segment and
    the check would be dead code. Recorded because the two guards look like duplicates and the
    obvious "cleanup" is to merge them; the distinction is *composed from validated parts* versus
    *supplied whole by a caller*.
  - _Requirements: R12.4 (narrowed to GET; R12.4a retired with the write export). Invariants: I7
    (I14 retired). Properties: P18 (satisfied without new code -- a read cannot violate it).
    Acceptance: **none of the set-specific ACs** -- AC23 was the only one this task carried and it is
    retired with the export it tested. The assertions are the hardening tests themselves: non-conn
    refused, traversal refused, full key refused, absent key aborts clearly, and a round trip through
    the local backend returns the parsed object. Recorded explicitly so the absence is not read as an
    omission. No pathway impact._

- [x] **4. `schema_version` gate (reader side)** &nbsp; **[DONE 2026-08-21]**
  - `.datom_check_schema_version(meta, source)` -- one implementation, one message.
  - Wire into **both** entry points: `.datom_read_metadata()` (the `datom_read()` path, which
    never touches the manifest -- verified `R/read_write.R:58-65`) and the manifest readers
    (`datom_list()`, `datom_summary()`, `datom_status()`).
  - `SUPPORTED_SCHEMA <- 2L`. Asymmetric: refuse newer, tolerate older; absent defaults to `1`.
  - Add `schema_version` **and** `document_sha` to the `volatile` list (that list is now
    `.datom_metadata_excluded_fields`, `R/utils-sha.R:444-447`, promoted from a local variable by
    Task 19; both names are still on it).
  - Nothing wrote `schema_version: 2` at the time this task shipped -- the gate landed
    tested-but-inert on purpose, so that Task 6's writer bump could not be the first exercise of
    untested gate code. Task 6 has since landed and the gate now fires.
  - _Requirements: R9, R7.4. Invariants: I4. Properties: P10, P11. Acceptance: AC7._
  - _Pathway impact: read route gains a version gate -- update `dev/datom_pathways.md`._
  - **DONE 2026-08-21.** New `.datom_check_schema_version()` + `.datom_supported_schema` in
    `R/utils-validate.R`, wired into **six** call sites (see the next bullet), both names added to
    the `volatile` list with the roxygen rationale paragraph updated alongside it, and two route
    cards in `dev/datom_pathways.md` (the existing read route gains step 2a; a new
    "can this build read this repo" card carries the call-site list and the tryCatch warning).
    tests: **2660** (+48), FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all eight checks
    pass. Also not a task: `.kiro/steering/communication.md`, recording the owner's chat-response
    conventions after this task's design round needed three restatements to land.
  - **SIX call sites, not the four the task named** -- owner-approved scope widening. The task
    listed the reader paths that go through storage; the same manifest is also read from the git
    clone by `datom_sync_manifest()` and `.datom_status_input_files()`, and that copy can be ahead
    of the installed build by an ordinary route: a collaborator upgrades datom and writes, this
    developer pulls. Left ungated, those two commands read a manifest shape this build does not
    know. The four in-pipeline local reads (`R/sync.R:202`, `R/read_write.R:860`,
    `.datom_update_manifest_entry()`, `R/validate.R:257`) were **deliberately excluded** at the time:
    the check belongs where a document enters datom, so a refusal happens before work starts rather
    than partway through a write. **Two of those four are no longer excluded, and the record is left
    here rather than rewritten**: Task 6 routed the mirror route's read through the shared reader, so
    it is checked and converted, and Task 21 put the whole write entry on the function that read sits
    in -- because `datom_validate(fix = TRUE)` calls that function directly and so never passed
    `datom_write()`'s door. The entry updater and `datom_validate()`'s project-name read are still
    excluded, for the reason stated.
  - **THE WIRING IS NOT SIX IDENTICAL ONE-LINERS, and that is the whole difficulty of this task.**
    Three of the six wrap their read in error handling that softens failures, so a check placed
    inside it produces a *different* outcome per site. `datom_list()` and `datom_summary()` would
    reword the upgrade instruction as "Could not read manifest", demoting the only actionable line
    to a footnote. `datom_status()` is worse: its handler downgrades errors to
    `available = FALSE` and continues, so that one command would stay silent while the other five
    stopped -- the exact degradation R9 exists to end. All three now read inside the handler and
    check outside it, with a comment at each site saying why. `datom_status()`'s block was
    restructured for it, and a test pins that an *ordinary* storage failure is still tolerated --
    making the schema check fatal must not make an unreachable bucket fatal.
  - **Two condition classes, so "all six behave the same" is provable rather than asserted**:
    `datom_schema_unsupported` (too new) and `datom_schema_invalid` (present but unusable). Every
    site's test asserts the class, not the message text.
  - **A present-but-unusable value aborts rather than being coerced**, which the requirement did
    not specify. Two reasons, either sufficient: `as.integer("two")` is `NA`, and `NA > 2` reaches
    `if()` as "missing value where TRUE/FALSE needed" -- an internal-looking error for what is
    really a corrupt file; and a string comparison against a number can read as *supported* by
    accident. Refused: non-numeric, `NA`, fractional, `< 1`, non-scalar, logical, list.
  - **Constant is `.datom_supported_schema`, not R9's `SUPPORTED_SCHEMA`** -- house style for
    internal constants (`.datom_reserved_names`, `.datom_import_formats`). R9's spelling is
    pseudocode. Note the leading dot makes it a **cli style** inside a message string, so it is
    spliced as `{(.datom_supported_schema)}`; a test asserts the ceiling renders as `v2` rather
    than vanishing into markup.
  - **The write side is NOT covered here, and it is the more damaging direction** -- an older build
    writing into a newer repo produces a manifest that is half one format and half the other.
    Assigned to Task 6 rather than bolted on here: a write is several steps (local files, one
    commit, then the storage mirror), so the check has to sit ahead of all of them, and Task 6 is
    where those steps are in view. Owner-decided 2026-08-21.
  - **Adding the two names to `volatile` is inert for every document already written**, since no
    metadata carries either field yet -- so I4 holds by construction rather than by migration. A
    test asserts presence-versus-absence of both is immaterial to `metadata_sha`, so the inertness
    is pinned rather than inferred from the suite staying green.
  - **The boundary is strictly greater-than**, with its own test. At `>=` the entire read path
    would break the moment Task 6 writes `schema_version: 2`.
  - **Spec code citations were re-derived** after these insertions shifted line numbers in five
    files (`R/query.R`, `R/read_write.R`, `R/summary.R`, `R/sync.R`, `R/utils-sha.R`) -- including
    every site in Task 6's checklist, which would otherwise have sent the next session hunting.
    Verified by content with `SPEC_CHECK_SHOW_CITATIONS=1`, not by arithmetic: two were already off
    by one before the shift. **Bare numbers inside historical log rows were left as-is** -- the
    2026-08-17 row that records one citation being corrected to another still names the old number,
    because it documents what was true on that date; only live `path:line` citations were updated.
    (The literal pair is not repeated here: check 4 now fails on a citation resolving to a blank
    line, and quoting a deliberately-wrong number would trip it -- the same call as the check 6 note
    below about quoting a stale AC range.)

---

## Phase B -- Manifest namespace **[BREAKING]**

**One change, two commits.** Task 5 moves every manifest read and every empty-manifest default onto
one internal helper and changes nothing observable. Task 6 then renames the key, in that one place.
**Split on 2026-08-23** (owner-decided, after the design audit below): as a single task it had grown
to a nine-site rename plus a write-side refusal, five counter filters, two read consolidations, an
old-format transition and a fixture sweep across ten test files -- and its failure mode is silent, so
a green suite is not evidence that any of it worked. Task 5 is the part that can be verified on its
own; landing it first is what makes Task 6's failure loud.

- [x] **5. One manifest reader, one skeleton builder** &nbsp; **[contract-neutral; DONE 2026-08-29]**
  - **The problem this exists to make fixable.** After the rename a reader looks for `artifacts`
    while every repo written so far says `tables` and carries no `schema_version` field at all. The
    reader-side check does not stop it: it tolerates an absent version as v1
    (`R/utils-validate.R:237`), so the repo passes and the reader then finds nothing where the list
    should be. `datom_list()` returns an empty frame (`R/query.R:94`), `datom_summary()` reports
    zero (`R/summary.R:68`), `datom_status()` reports zero (`R/query.R:488`), and **nothing errors**
    -- the failure E2 exists to prevent, arriving through the front door instead of through a
    partial rename. `datom_read()` is unaffected (it never touches the manifest,
    `R/read_write.R:93`), so this is a discovery blackout rather than data loss. Silence is what
    disqualifies it, not severity.
  - **Fixing it needs one place to stand.** There are five manifest reads today, each with its own
    absent-file default and its own failure policy, so an upgrade added now would be added five
    times. This task creates the one place; Task 6 uses it.
  - **New: `.datom_read_manifest(conn, scope)`** in `R/sync.R`, where `scope` selects the storage
    copy (`.metadata/manifest.json`) or the clone copy (`.datom/manifest.json`). It returns a
    **result record**, not a bare document: `list(ok =, absent =, manifest =, error =)`.
  - **The load-bearing detail is which failure is returned and which is thrown.** An IO failure is
    returned as data (`ok = FALSE`); a schema refusal is **thrown**. That is what makes it
    impossible to soften the upgrade message by accident. Task 4 found three readers wrapping their
    read in a handler that softens failures, and a check placed inside one reworded the upgrade
    instruction as "could not read manifest" -- `datom_status()` went further and downgraded it to a
    warning while continuing. Until this task, that placement was preserved by a comment at each of
    those three sites; now it is preserved by the shape of the helper, because there is no handler
    left for a caller to put the check inside. (Those comments are gone, so the line citations they
    carried are not reproduced here.)
  - Route the five read sites through it, each keeping its **current** failure behaviour verbatim
    (call sites as shipped): `datom_list()` (`R/query.R:80`) and `datom_summary()`
    (`R/summary.R:50`) abort with their own wording on an unreadable manifest; `datom_status()`
    (`R/query.R:468`) still tolerates one and reports it unavailable;
    `.datom_status_input_files()` (`R/query.R:593`) and `datom_sync_manifest()` (`R/sync.R:392`)
    still fall back to an empty manifest when the clone has no file.
  - **New: `.datom_manifest_skeleton(project_name = NULL)`** (`R/sync.R:759`) -- the one
    empty-manifest shape. It replaced three hand-built copies, now three calls to it:
    `R/query.R:600`, `R/sync.R:408`, and the one inside the entry updater at `R/sync.R:969`, which
    is the copy that would have written the old key after the rename (see Task 6). Use
    `datom_init_repo()`'s spelling,
    `structure(list(), names = character(0))` (now `R/sync.R:762`, inside the skeleton itself),
    not a bare `list()`: an empty bare
    list serializes as a JSON **array**, an empty named list as an **object**. Inert today (the
    skeleton is never written empty) and correct for the one case where it would be.
  - **`.datom_check_namespace_free()` is excluded by name** (`R/utils-validate.R:168-181`). It reads
    a *different project's* manifest inside a handler that softens failure to `<unreadable>`, and
    that softening is right there: the message is best-effort context for a refusal that has already
    been decided. Sweeping it onto the shared helper would put a throwing check inside an
    error-softening handler, which is the exact shape this task removes everywhere else.
  - **The four in-pipeline local reads stay excluded**, on Task 4's stated principle: the check
    belongs where a document enters datom, so a refusal happens before work starts rather than
    partway through a write.
  - **New: `tests/testthat/fixtures/manifest-v1.json`** -- one preserved file per historical schema
    version, frozen, never edited. Contents: no `schema_version`, a `tables` block with one real
    table entry, a `summary` block. It is the only mechanical evidence that old repos still read,
    and being a file rather than an inline fixture is what stops a later sweep from quietly
    rewriting it to the new shape.
  - **Two existing tests are v1-compatibility tests and must not be swept in Task 6**:
    `datom_list tolerates a manifest with no schema_version` (`test-query.R:930`) and
    `datom_summary tolerates a manifest with no schema_version` (`test-summary.R:180`). Both build a
    `tables` block with an entry and assert a **non-empty** result. Rewritten to `artifacts` they go
    green while asserting nothing. Add the third: `datom_sync_manifest` has the same-named test
    (`test-sync.R:1308`) but its `tables` block is **empty**, so it passes either way and proves
    nothing -- give the clone-copy readers a non-empty old-format fixture too.
  - **No new export. No on-disk change. No schema bump.** The key is still `tables` when this task
    ends; `git diff` on any repo must be empty after running the suite.
  - _Requirements: R22 (R22.4, R22.6, R22.7). Invariants: I28. Properties: P35. Acceptance: AC30
    (the frozen fixture reads non-empty), AC32 (a schema outcome is never reported as an unreadable
    manifest, at any reader). **One instruction about test SHAPE, not about the criterion**: the
    behaviour this task ships is an abort at all five readers, and Task 22 changes it to
    warn-and-rebuild for the manifest reader. So write that assertion where it is easy to find and
    amend -- **do not bury it in a loop over the five readers**, because one of the five stops
    aborting later. AC32's wording is invariant across that boundary; the test is not. No pathway
    impact -- route shapes unchanged; record explicitly._
  - **DONE 2026-08-29.** `.datom_read_manifest()` and `.datom_manifest_skeleton()` added to
    `R/sync.R` in a new "Shared manifest access" section; five read sites routed through the first;
    three hand-built empty manifests replaced by the second; `tests/testthat/fixtures/manifest-v1.json`
    frozen, with a `fixtures/README.md` saying these files are never edited. tests: 2686 ->
    **2740** (+54), FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all nine checks pass. No
    pathway impact -- the route shapes and gate positions are unchanged; only the number of places
    the manifest is read moved, from five to one.
  - **Both new guards were proven to fail before being trusted**, per this spec's own rule. (1)
    Pointing `datom_list()` at `manifest$artifacts` -- what Task 6 will do -- turns the frozen-fixture
    test red, so it really is evidence that old-format repos still list their contents rather than a
    test that would pass either way. (2) Wrapping the schema check in a handler inside
    `.datom_read_manifest()` turns three tests red, including `datom_sync_manifest`'s existing
    refusal test, so the returned-versus-thrown split is pinned rather than assumed. Both probes were
    reverted; the workspace carries neither.
  - **The `error` field holds the whole condition, not its message text.** Two callers need different
    things from it: `datom_list()` and `datom_summary()` splice `conditionMessage()` into their own
    abort, and the two clone readers re-signal the original failure with `stop()` so a corrupt local
    manifest still fails with the parser's own error and no datom wrapper. Keeping only the text would
    force the second case to manufacture a look-alike error, which loses the condition class -- and
    class is what the suite asserts on elsewhere.
  - **`absent = TRUE` is a positive claim and storage never makes it.** For the clone copy it is a
    free `fs::file_exists()`. For storage, separating a missing object from an unreachable store
    needs an extra request on every `datom_list()`, `datom_summary()` and `datom_status()` call, and
    no caller treats the two differently, so the field is left `FALSE` there, meaning "not known to
    be absent". Pinned by a test, since the tempting later optimisation is to infer absence from the
    error message. If a caller ever needs the distinction, probe `.datom_storage_exists()`; do not
    parse the message.
  - **A corrupt clone manifest is a failure, not an absence, and that distinction is now tested.**
    Both clone readers fall back to an empty manifest when the file does not exist. A present but
    unparseable file must not take that branch: it would report every input file as new, which is a
    wrong answer delivered confidently. The helper separates the two, and each clone reader
    re-signals the parse failure.
  - **`datom_status()` lost its `read_ok` flag.** It had one because a manifest that legitimately
    parses to `NULL` must still count as read, and a `NULL` check could not tell those apart. The
    helper's `ok` field carries that distinction now, so the flag was redundant rather than dropped.
  - **The entry updater keeps its own direct read, deliberately.** `.datom_update_manifest_entry()`
    (`R/sync.R:984`) reads `.datom/manifest.json` mid-write, and a compatibility refusal there would
    stop a write partway through instead of at the door. Only its empty shape moved to the shared
    builder. A comment at the site says so, because the obvious tidy-up is to route the read through
    the shared reader as well.
  - **The two clone readers' fallback is now `.datom_manifest_skeleton()` rather than
    `list(tables = list())`.** Behaviour-identical for lookups -- both answer `NULL` for any name --
    and it removes the last two places that spelled an empty manifest by hand.

- [x] **6. `manifest$tables` -> `manifest$artifacts`, typed by `kind`** &nbsp; **[ESCALATION E2 --
  FULLY DISCHARGED: design spot-check 2026-09-01, implemented 2026-09-08, purity audit run and
  discharged the same day. Nothing owed -- see the DONE record at the end of this task]**
  - Write side (**3** sites -- an earlier draft said 2 and missed the third):
    `.datom_update_manifest_entry()` (`R/sync.R:1004,1014-1024`); the **absent-manifest skeleton**,
    which Task 5 collapsed into `.datom_manifest_skeleton()` (`R/sync.R:759`, called at
    `R/sync.R:969`); and `datom_init_repo()`'s seed (`R/conn.R:522-528`).
    **The skeleton stamps `schema_version: 2` itself** (owner-decided 2026-08-29), so no repo ever
    exists in a state that declares no format at all. Note what that does *not* cover: a manifest
    read from disk in the old shape still needs the upgrade to stamp it, because the skeleton is
    only reached when there is no file. Two paths, one for a document being created and one for a
    document being converted, and both have to stamp.
    **The skeleton was the dangerous one**: left unrenamed it writes a `tables` key after the
    rename, and it only fires on a fresh or repaired repo, so tests against an existing fixture pass
    while the bug ships. Task 5 reduced it to one place, which is the point of the split.
  - Read side: **one** site now -- `.datom_read_manifest()` (`R/sync.R:812`) -- plus the six field
    accesses that read the artifact key off the returned document (`R/query.R:92,109`,
    `R/query.R:488`, `R/query.R:605`, `R/summary.R:68`, `R/sync.R:411`).
  - Each entry gains `kind` (`"table"` for everything existing). `summary` gains `total_sets`;
    `total_tables` / `total_size_bytes` / `total_versions` keep **current** semantics (tables
    only).
  - **FIVE counters silently widen to include sets, not three.** The three in the summary block
    (`R/sync.R:1032,1033,1036`) plus two computed independently of it: `datom_summary()`'s
    `table_count` counts entries rather than reading the summary block (`R/summary.R:69`), and
    `datom_status()`'s count does the same and prints as "Tables on S3" (`R/query.R:488`). Each
    needs a `kind == "table"` filter. There are no sets until Task 9, so **every test passes either
    way** unless it is driven by a hand-built manifest containing a `kind: "set"` entry -- so write
    that fixture, and assert `datom_summary()`'s counted number and the stored `summary` block
    agree.
  - **"Surface `kind`" means two different things.** `datom_list()` returns per-artifact rows, so it
    gains a `kind` column -- **including in both empty-frame early returns** (`R/query.R:94,103`),
    not only the populated path. Those two already omit `current_data_sha`, which populated rows
    carry, so the column set has drifted here once already. `datom_summary()` has no per-artifact
    axis: it gains `set_count` alongside `table_count`, plus a line in `print.datom_summary()`, and
    `table_count` keeps its tables-only meaning (owner-decided 2026-08-23).
  - Manifest and per-artifact metadata now write `schema_version: 2`. **Both are stamped; the number
    moves to 2 because this change is genuinely breaking** (the artifact list is renamed, which is
    row one of R9.5's test). Stamping and incrementing are separate decisions from here on -- a later
    release that merely adds a field stamps the same number, so no pinned build is refused for a
    change it could have tolerated.
  - **The old-format upgrade, which is what makes the rename safe** (R22): add
    `.datom_manifest_upgrade_v1_to_v2()` (move `tables` to `artifacts`, stamp `kind = "table"` on
    every entry) and the dispatcher `.datom_manifest_upgrade()`, both in a **new
    `R/manifest-upgrade.R`** (owner-decided 2026-08-29). Reason: a shipped step is frozen forever
    and one more arrives with every future format change, so they accumulate -- a file whose entire
    contents are "never edit these" is easier to protect than a section of `R/sync.R`, which is
    already 881 lines and holds sync, import and manifest concerns. Same split reasoning as
    `R/hashable-set.R`. Apply it in the **one** place Task
    5 created. Concretely, inside `.datom_read_manifest()` (`R/sync.R:812`) the order is: read,
    then `.datom_check_schema_version()` -- which throws on a document too new to touch at all --
    then the upgrade chain on what survives, then return. `manifest` simply comes back upgraded.
    **The record gained a fifth field on 2026-09-08**, `declared` -- the version a document announced
    before conversion -- so a caller that goes on to write the converted document can say the format
    moved without re-deriving the comparison or reading the file twice. An earlier version of this
    line said the four fields (`ok` / `absent` / `manifest` / `error`) do not change shape. Task 22 later adds a rebuild branch at the same point, so keep the step separable
    rather than inlined into the return. Read upgrades in memory and leaves the file alone; write
    upgrades the file, then stamps the version. Never stamp a version onto a document that was not upgraded first, and never
    write a v2-shaped entry into a file still declaring v1 -- that is how a file ends up half in
    each format. Concretely, without this: a repo with twelve tables gets one entry added under the
    new key while the old key sits untouched, and `total_tables` reads **1**.
  - **The write-side refusal, inherited from Task 4** (owner-decided 2026-08-21). Task 4 gated the
    six reader entry points; an **older** build writing into a **newer** repo is the more damaging
    direction and is still open. Reuse `.datom_check_schema_version()`; do not write a second one.
    Placement is the whole question, and it has two parts. (a) It needs the **manifest**, which
    `datom_write()` never reads -- gating only the per-artifact metadata leaves the manifest
    unprotected. (b) It must sit directly after the `datom_conn` class check and **above** the two
    routing returns at `R/read_write.R:719` and `R/read_write.R:723`, because
    `.datom_sync_data_metadata()` mirrors the whole local manifest to storage (`R/sync.R:212`)
    without ever reaching the manifest-writing step, so a check placed after the router misses it.
    A write is several steps -- local files, one commit, then the storage mirror -- so the check
    goes ahead of all of them: stopping halfway leaves a half-finished write, which is worse than
    the disagreement it was trying to prevent.
  - **`.datom_check_schema_version()`'s message says "which this build cannot read"**
    (`R/utils-validate.R:269`). On a refused **write** that sentence is wrong. Give it an operation
    word, or accept it knowingly and say so.
  - **Must land atomically**: the rename, the five counters, the upgrade step and the tests, in one
    commit. A partial rename presents as "everything looks fine, the list is just empty."
  - _Requirements: R8 (incl. R8.4, R8.5), R9 (writer side), R22 (R22.2, R22.3, R22.5, R22.8).
    Invariants: I2, I4, I29, I30.
    Properties: P10 (restated -- this task is where it is defended), P34. Acceptance: AC7 (the v2
    writer half of the schema gate), AC30 (the frozen v1 fixture still reads non-empty **after** the
    rename), AC31 (a write into an old-format repo upgrades the file and the counters cover every
    pre-existing artifact). Add a test that `datom_list()` and `datom_summary()` surface `kind` and
    that `total_sets` counts only sets -- the rename's own failure mode is silent, so it needs a
    positive assertion, not just the absence of errors. No new pathway (route shapes unchanged) --
    record explicitly. **Confirmed on landing**: `dev/datom_pathways.md` gained no route. The
    "can this build read it" route gained a step (convert after checking) and its write-side
    paragraph now names the door instead of deferring to this task, but both are transforms and
    gates on a document already fetched -- no new lookup, no new traversal._
  - **Escalation rationale**: touches `datom_list()`, `datom_summary()`, `datom_status()` and the
    sync manifest updater together, plus the writer-side check inherited from Task 4 and the
    old-format upgrade added by the 2026-08-23 audit; failure mode is silent writer/reader
    disagreement. (An earlier draft also named `datom_validate()` -- **corrected 2026-08-21**, see
    the cold-start audit below: it reads the manifest only for `project_name` and never touches the
    artifact key.)
  - **COLD-START AUDIT, 2026-08-21** -- the documented path (`dev/README.md` -> the state block ->
    this task -> `dev/engineering-notes.md`) was walked as a fresh reader and every claim checked
    against the tree. The nine-site enumeration was **accurate as recorded** (Task 5 has since
    collapsed the read half to one site), and all citations were re-derived after Task 4's
    insertions. Two things needed fixing and one is worth budgeting for:
    1. **`datom_validate()` does NOT read `manifest$tables`** -- verified by grepping every
       reference to the key in `R/`. Its only manifest read is `.datom_validate_project_name()`
       (`R/validate.R:257`), which looks at `project_name` and nothing else, and
       `.datom_validate_tables()` enumerates artifacts without consulting the manifest at all. So
       the rename does not touch it, and the escalation rationale above previously sent a reader
       hunting in a file with nothing in it. **Corrected 2026-09-09**: this line said it enumerates
       "from a storage listing", which is wrong -- it enumerates from the **clone**
       (`fs::dir_ls(repo_path, type = "directory")`, `R/validate.R:386`) and then checks storage per
       name. The conclusion above is unaffected, but the wrong version matters for Task 22, whose
       rebuild has to serve a reader with no clone: it would send that reader looking for a
       storage-side enumerator that does not exist.
    2. **THREE DECOY SITES that look like the rename and must not be renamed.** Each is a
       user-facing **return-value** field named `tables`, not the manifest key:
       `datom_sync()`'s result (`R/sync.R:171`, `R/sync.R:222`), `datom_validate()`'s result
       (`R/validate.R:205`), and `datom_status()`'s result (`R/query.R:495`). A `grep tables`
       sweep hits all three. Renaming them is a **separate** breaking change to three return
       shapes that R8 does not ask for -- R8.1 renames the manifest key only. If it ever looks
       desirable, it needs its own decision and its own NEWS entry.
    3. **Test surface is wide**: ten test files mention `tables`, re-counted 2026-08-29 after
       Tasks 18/19/5 added to them (`test-sync.R` 45 hits, `test-query.R` 39, `test-validate.R` 24,
       `test-read-write.R` 17, `test-summary.R` 9, `test-conn.R` 4, plus four with one each). Many
       are manifest fixtures that must move to `artifacts`; some are decoys per item 2. Budget for
       the fixture sweep being the bulk of the chunk, and remember the rename's own failure mode is
       silent -- a fixture left on `tables` against a reader expecting `artifacts` presents as an
       empty list, not an error.
    4. **SIX TESTS AND ONE FILE MUST STAY ON THE OLD KEY.** They are the only evidence that repos
       written before this rename still read, so sweeping them to `artifacts` leaves them green
       while asserting nothing -- and the regression then ships clean. Verified present
       2026-08-29:
       `tests/testthat/fixtures/manifest-v1.json` (frozen; `fixtures/README.md` says so) and its
       readers `datom_list reads the frozen old-format manifest as non-empty`
       (`tests/testthat/test-query.R:941`), `datom_status input file scan sees entries in an
       old-format manifest` (`tests/testthat/test-query.R:1049`), `datom_summary reads the frozen
       old-format manifest as non-empty` (`tests/testthat/test-summary.R:191`) and
       `datom_sync_manifest sees entries in an old-format manifest in the clone`
       (`tests/testthat/test-sync.R:1327`); plus the two older tolerance tests
       `datom_list tolerates a manifest with no schema_version`
       (`tests/testthat/test-query.R:930`) and `datom_summary tolerates a manifest with no
       schema_version` (`tests/testthat/test-summary.R:180`). Note the same-named
       `datom_sync_manifest` tolerance test (`tests/testthat/test-sync.R:1308`) has an **empty**
       `tables` block, so it proves nothing either way -- Task 5 added the non-empty clone-copy
       test above precisely because of that.
  - **DESIGN AUDIT, 2026-08-23** -- run before implementation per the E2 flag, and the reason this
    phase is now two tasks. It found the old-format transition described above (nothing upgraded a
    v1 manifest, and neither of the two things that might have self-healed it does: the entry
    updater stamps no version, and a no-change write returns at `R/read_write.R:793` before the
    manifest is touched), the two v1-compatibility tests that must not be swept, the five counters
    rather than three, the two empty-frame early returns, the placement of the write-side refusal
    above the routing returns, and two acceptance criteria this task cannot exercise (AC4 needs
    `datom_write_set()`, Task 9; AC22 is Task 11's and is already largely implemented by
    `.datom_check_namespace_free()`) -- both now removed from the clause above and left with the
    tasks that own them. Verified independently against the tree before acceptance; the one
    overstatement was that a clone can lack a local manifest, which is true but close to
    unreachable because `.datom/manifest.json` is git-tracked. **`dev/check-spec.R` cannot catch any
    of this** and says so itself, in the comment explaining why the manifest key is not on the
    retired-wording list: the risk lives in `R/`, which that script does not read. This phase has
    the least mechanical protection and the most silent failure mode of any work in this spec.
  - **DONE 2026-09-08, in one commit, as planned below.** The design was proposed 2026-09-01 and
    the session stopped for owner go-ahead per rule 5b; CRAN's post-acceptance fix intervened and
    shipped as 0.1.2 (test-only, no `R/` file), so the plan stood untouched and was implemented from
    it verbatim. **The five open calls were taken at their stated defaults**, each of which is
    recorded with its consequence below. Tests 2748 -> **2836** (+88), FAIL 0 / WARN 0 / SKIP 0;
    `Rscript dev/check-spec.R` all nine checks pass. What shipped, beyond the plan: nine internal
    `man/` pages regenerated, no new export, NAMESPACE and `_pkgdown.yml` untouched.
    - **E2 status.** The design spot-check half was discharged by the proposal below, produced after
      reading the audits and re-reading every cited site in `R/`. **The purity-audit half is now
      due** -- 6 `R/` files edited, 1 added, ~40 fixtures swept across 8 test files, and a failure
      mode that shows up as an empty list rather than an error. Per rule 5d it is surfaced in this
      chunk's checkpoint message; per the default taken below it runs in-line, before Task 20 starts.
    - **Plan, by file -- implemented as written.** New **`R/manifest-upgrade.R`**: `.datom_manifest_upgrade_v1_to_v2()` renames
      the artifact key **in place** (`names(m)[names(m) == "tables"] <- "artifacts"`, so position and
      any unrecognised sibling keys survive -- which is also what Task 20 wants) and stamps
      `kind = "table"` first in each entry; `.datom_manifest_upgrade()` derives the declared version,
      applies each step in order via `purrr::reduce`, guarded by `if (declared < supported)` because
      R's `seq()` counts down (R22.10), then records the version it reached.
      `R/sync.R`: the skeleton (`R/sync.R:759`) renames its key and stamps `schema_version: 2`; the
      shared reader (`R/sync.R:812`) gains one line -- chain **after** `.datom_check_schema_version()`
      and before the return, kept separable for Task 22's rebuild branch; the entry updater
      (`R/sync.R:946`) chains what it read from disk, writes `kind` on the entry, stamps the version,
      and filters its three summary counters (**all four kind selections went through one helper,
      `.datom_artifacts_of_kind()`, on 2026-09-08** -- the predicate was spelled out at each site and
      one of those copies had lost a tolerance); `datom_sync_manifest()`'s lookup moves to the new key.
      `R/query.R`: `kind` column in `datom_list()`'s populated path **and** both empty returns;
      `datom_status()`'s count filtered; the input-file scan's lookup moved. `R/summary.R`:
      `table_count` filtered, new `set_count`, new print line. `R/conn.R`: the seed is built from the
      skeleton plus `updated_at` and a zeroed summary, so the stamp is not spelled a third time.
      `R/read_write.R`: `schema_version` into `.datom_build_metadata()` (already classified excluded
      in `.datom_metadata_excluded_fields`, so identity does not move and the classification test
      stays green), plus the write-entry check above both routing returns. `R/utils-validate.R`: an
      operation word in the refusal message.
    - **Two stamping sites, restated because the plan depends on it.** Created-from-nothing gets the
      number from the skeleton; converted-from-old gets it from the dispatcher, which sets it only
      after the steps ran (I29). The seed is routed through the skeleton rather than stamping itself,
      which is the only reason there are two sites and not three.
    - **Docs that ship in the same commit.** `dev/datom_specification.md`'s `.datom/manifest.json`
      example still shows `tables` and no `schema_version`; a NEWS entry for a breaking rename; the
      `tasks.md` checkbox and the `dev/README.md` status line; and "no pathway impact" recorded
      explicitly.
    - **Test plan.** The load-bearing new fixture is a **hand-built manifest carrying a `kind: "set"`
      entry beside table entries** -- without it every counter change passes whether or not it was
      made, since nothing writes a set until Task 9. It asserts the two counted numbers
      (`datom_summary()`), the two stored numbers (the `summary` block), and that counted and stored
      **agree**. Then: unit tests for the step and the dispatcher (converts; identity on a
      current-version document; **zero** steps run there; twice equals once); a write into an
      old-shape repo leaves the new key, no old key, the number stamped and every pre-existing table
      still counted (AC31); the write-entry refusal on **all three** write routes including the
      mirror-everything one; stamping mints no new version for unchanged content; `kind` present in
      both empty returns.
      **The sweep rule, and how it goes quietly wrong**: a swept fixture must declare
      `schema_version: 2` **and** carry `kind` on its entries. Declaring the number without `kind`
      makes the counters read zero, because R22.8 deliberately has no missing-`kind` fallback -- the
      counter tests above are what catch that. The six tests and the frozen file named in item 4 stay
      on the old key; the two frozen-fixture readers gain AC30's `kind = "table"` assertion, which
      touches the assertions and not the fixture.
    - **FIVE OPEN CALLS, ALL FIVE TAKEN AT THEIR DEFAULT (2026-09-08).** The owner said nothing on
      any of them, which the defaults were written to make safe. Each is stated below as it was
      proposed, with what shipped noted at the end of the item.
      1. **The mirror-to-storage route converts before mirroring and leaves the clone file alone.**
         `datom_write(NULL, NULL)` and `datom_validate(fix = TRUE)` reach
         `.datom_sync_data_metadata()`, which today copies the clone's manifest to storage byte for
         byte -- so a build that knows the new shape would push the old one. Plan: read it through the
         shared reader, mirror the converted form, do **not** rewrite the local file, because this
         route does not commit and rewriting it would leave the repo dirty. Accepted cost: for a
         window the clone is old-shape and storage is new-shape; both are internally consistent and
         both read correctly. Side benefit: `datom_validate(fix = TRUE)` bypasses `datom_write()`'s
         door, and routing its read through the shared reader is what stops it mirroring a manifest it
         cannot understand. *Default: as described.* **Shipped as described**, and pinned by a test
         that mirrors the frozen v1 fixture and asserts both halves: storage receives the converted
         document, and the clone file's digest is unchanged.
      2. **An operation word in `.datom_check_schema_version()`'s message.** It says the format is one
         "this build cannot read", which is wrong on a refused write. Plan: an optional argument, so
         every existing call site and its asserted text are unchanged. *Default: add it.* **Shipped
         as `operation = c("read", "write")`.** A refused write now says the build "cannot write"
         that format. **All three** write-route tests assert the word -- only one did when this was
         first written, and the other two were tightened on 2026-09-08 rather than the claim being
         weakened.
      3. **The clone manifest is read twice on a write** -- once by the entry check, once by the
         updater that edits it. Task 21 asks for this to be decided rather than drifted into. Plan:
         accept two reads of a small local file, and say why in the commit -- the door's copy cannot be
         threaded down, because the sync route pulls from the remote in between, so a document read at
         the door can be stale by the time the file is edited. *Default: accept two reads.* **Two
         reads shipped, but the reason above is WRONG and was corrected 2026-09-08.** Nothing pulls
         between the two reads **on this route**: the door runs first, the updater about a hundred lines
         later, and the pull is inside the push after both of them. `datom_sync()` does not change that
         -- it calls `datom_write()` per file, so the door runs inside each call. (The metadata-only
         route is different and pulls right after the door, which makes the door's check stale there;
         it writes no manifest, so nothing can end up half in each format, and Task 21's entry sequence
         is where that has to be dealt with. Recorded in Task 21's bullets.) The **decision** stands on
         a plainer footing: the door deliberately runs before any hashing so that a refusal leaves
         nothing half-written, and threading its document down to the updater would carry state
         through every intervening step, each of which must stay free to abort. It is a local file
         read, not a round trip.
      4. **The entry check is skipped when there is no clone path.** A reader-role conn has no clone
         to inspect and already fails a few lines later with a clearer message about developer role.
         *Default: skip, and let the existing error stand.* **Shipped**, and tested: a reader-role
         connection passes the door and still fails on the developer-role message.
      5. **`datom_list()`'s two empty returns gain `kind` but not `current_data_sha`.** Those returns
         omit a column the populated rows carry -- pre-existing drift this task's body already notes.
         Fixing it changes a public shape nobody asked to change. *Default: leave the drift,
         recorded.* **REVERSED by review, 2026-09-08 -- the drift is gone.** Both empty returns come
         from `.datom_empty_artifact_frame()`, which now carries every column a populated result
         carries, `version_count` included when `include_versions = TRUE`. The default's reason was
         already spent when it was written: the same commit added a `kind` column to that very shape.
         And the difference was a defect, not a cosmetic one -- `rbind()` of frames with different
         columns errors, so a caller collecting listings across projects broke as soon as one was
         empty. Fixed in two goes, one column each; see the Decisions rows.
    - **Also open, also defaulted -- and now DONE**: the post-landing purity audit ran in-line and is
      discharged (2026-09-08); its method and result are in the bullet below and in the Decisions log.
      **Sequenced after the review fixes, owner-decided 2026-09-08**: an audit of a
      state that is about to change produces findings that go stale, and two of the fixes land
      squarely in what the audit inspects (three fresh copies of one predicate, and a public shape).
      So the audit is the last check, not the first.
    - **THREE THINGS THE PLAN DID NOT SAY, decided while implementing.**
      1. **The upgrade dispatcher takes the declared version as an argument** rather than reading it
         off the document. The number can only come from the check, which refuses a document too new
         to convert, so passing it in is what makes "check first, then convert" structural: there is
         no way to call the converter without having obtained the number from the check (I32).
      2. **The entry updater runs the check on what it read from disk**, purely to obtain that
         number. It cannot fire for a write that came through `datom_write()`, because the door
         already refused a too-new manifest before any hashing; the alternative was guessing the
         version of a document about to be edited, which is how a file ends up half in each format.
         Task 5's decision that the updater keeps its own **read** is unchanged.
      3. **A document that did not parse to a named list is returned untouched** by the converter.
         Stamping one would turn `null` on disk into an object in memory -- inventing a document
         where the file had none.
    - **EVERY GUARD WAS PROVEN TO FAIL BEFORE BEING TRUSTED**, per this spec's own rule, and each
      probe was reverted. (a) Disabling the conversion in the shared reader reddens **18**
      assertions: all four frozen-fixture readers, both no-`schema_version` tolerance tests, the
      mirror route, and the two reader tests added here. (b) Removing the `kind` filters reddens five
      tests across all three counting sites -- the stored `summary` block, `datom_summary()`'s
      counted numbers, and `datom_status()`'s. (c) Moving the write door below `datom_write()`'s
      routing returns reddens both non-table routes, which is the placement the 2026-08-23 audit
      flagged. (d) Dropping the conversion from the entry updater reddens the ten assertions that say
      a pre-existing table is still counted after a write. Without (b) and (d) the suite passes with
      the bug in it.
    - **FOUR FINDINGS FROM THE POST-LANDING REVIEW, all fixed 2026-09-08 in a follow-up commit.** Each
      was verified against the code before being accepted, and each was proven to redden a test before
      the fix was trusted. (1) **Three counters aborted on an entry that is not a named list** -- the
      v1 step preserves such an entry, having no shape to convert, and the counters dereferenced it.
      `datom_status()` was the damaging one: the count sits outside the handler that lets it describe
      a connection when the manifest cannot be trusted. Fixed by routing all four selections through
      `.datom_artifacts_of_kind()` rather than repeating a guard four times. (2) **A conversion that
      persisted was silent**, so `datom_validate(fix = TRUE)` could degrade a colleague's install;
      writes now say what moved, reads still say nothing. (3) **`stop(read$error)` could be
      `stop(NULL)`** on the mirror route, aborting with an empty message. (4) **`datom_list()`'s empty
      result lacked `current_data_sha`**, so `rbind()` failed when one side was empty -- which
      reversed open call 5. Two claims in this record were also wrong and are corrected in place: only
      one of the three door tests asserted the message word (the other two were tightened), and the
      double read was justified by a pull that does not happen where it was said to.
    - **TWO LOOSE ENDS FROM A SECOND REVIEW PASS, both closed 2026-09-08.** (1) The zero-row frame was
      still one column short in the narrower case: `version_count` is opt-in, a caller **can** ask for
      it and get an empty repo, and a comment claimed they could not. The frame now takes the flag and
      carries the column exactly when a populated result would, so `rbind()` works for that call too --
      the fix, not a reworded comment, because it is the same defect the `current_data_sha` reversal
      was about. (2) The metadata-only write route pulls from the remote immediately after the door,
      so the door's manifest check is stale on that route; harmless in this task's code because the
      route writes no manifest, and now written into Task 21's bullets, where the entry sequence has to
      either own the fetch or re-check after it.
    - **PURITY AUDIT, 2026-09-08 -- discharged, two tests tightened, no code changed.** Run last
      rather than first, so that it audited the state that actually shipped. Method and result, so
      neither is re-derived:
      1. **Is the suite blind to the failure this task exists to prevent?** No. Dropping the artifact
         key from the shared reader's returned document -- the silent blackout itself -- reddens **64
         assertions across 36 tests**, spanning all five readers plus five `datom-cv1` end-to-end
         scenarios. The fixture sweep did not cost the suite its teeth.
      2. **Did any swept fixture end up declaring the version but carrying no `kind`, which reads as
         zero artifacts?** No. Making an untyped entry abort inside the selection helper reddens
         exactly **one** test -- the one that deliberately passes an untyped entry to assert it is not
         counted. Checked this way rather than by grepping the fixtures, because an entry spread over
         several lines defeats the pattern and a false negative here is invisible.
      3. **Two tests were passing whatever the code did.** `print.datom_summary shows the set count`
         asserted that a `Sets:` line exists, which holds against a count that is always zero; it now
         asserts the number. `returns empty data frame when pattern matches nothing` asserted an empty
         result from a non-empty fixture, which holds equally if the manifest was never read; it now
         asserts the unfiltered call returns a row first.
      4. **Duplicated logic**: after the follow-up commit each of the five concerns has exactly one
         home -- the reader, the skeleton, the conversion, the kind selection, and the zero-row frame.
         Stamping is still the two sites I29 requires (the skeleton for a document being created, the
         dispatcher for one being converted) and a third has not appeared.
      5. **No surviving read of the old key in `R/`**, and every remaining `tables` in the tests is one
         of: a v1 document handed to the conversion, one of the six preserved old-key tests, a
         deliberately malformed JSON string, a namespace fixture that only reads `project_name`, or one
         of the three documented return-value decoys.
      6. **`R CMD check`** (docs, Rd, code/doc agreement; tests and examples skipped as they run
         separately): 0 errors, 0 warnings, 0 notes.
      **One gap it did not close, named rather than fixed**: the write door inspects the manifest only.
      `.datom_sync_metadata()` (`R/utils-sha.R:549`) copies a per-artifact metadata document from the
      clone straight to storage, and a document pulled from a collaborator on a newer datom would go
      through unchecked. Pre-existing -- before Task 6 there was no write-side check at all -- so this
      narrows the hole rather than leaving it where it was. Closing it belongs with Task 21, which is
      already writing the entry sequence that reads all three documents at the door.

---

## Phase C -- The set artifact

- [ ] **7. `kind` in metadata + set metadata builder + `document_sha`**
  - `kind: "table" | "set"` -- **semantic**, participates in `metadata_sha`. A **new field**, not
    a `table_type` value; `table_type` stays validated to exactly `imported`/`derived` (I12).
  - `.datom_build_metadata()` gains `kind = "table"`; new `.datom_build_set_metadata()` produces
    the collapsed field set using **conditional assign** so fields are omitted, not nulled.
    **The authoritative field list is R1.3** -- seven fields, named there -- with R1.4 giving what is
    absent and why. It is **not** in design.md section 4, which this bullet used to cite: that section
    is about tags replacing structure and contains no field matrix, so the citation sent a fresh reader
    looking for a table that does not exist.
  - **The set builder's two concrete values, because both are easy to get wrong by copying the table
    builder.** `data_sha` comes from `.datom_canonical_set_hash(payload)` (`R/hashable-set.R:421`),
    already shipped by Task 2, and `hash_algo` is the string **`"datom-sv1"`** -- the encoder embeds
    that string inside the digest but nothing stamps the field, so the builder must. Copying
    `"datom-cv1"` across would leave a set claiming the table regime while hashing under the set one.
  - `document_sha` persisted in `version_history.json` entries from day one, mirroring the
    `parquet_sha` conditional-add in `.datom_write_metadata_local()` (R7.2).
  - **`document_sha` ALSO GOES IN A SET'S `metadata.json` -- R1.3 lists it as one of the seven.** This
    bullet previously said to keep it out of the metadata document, which contradicts R1.3 and would
    break the read gate: R7.1 requires the stored payload verified **before parsing**, and the reader
    has nowhere else to get the expected hash from. The Task 20 concern that produced the old wording
    does not survive contact with R1.3 either -- carry-forward only matters for a field **nothing
    writes**, and once the set builder writes it there is no rewrite that can lose it. It stays on the
    excluded (not-identity) list: it is a fact about stored bytes, and hashing it would make a set's
    identity depend on its own serialization.
  - **`document_sha` is inert at this task, so decide whether the plumbing lands here.** Nothing
    computes a `document_sha` until the set **write** path exists (Task 9), so the
    `version_history.json` conditional-add added here writes nothing and the set builder's field is
    only reachable from a test. R7.2 says "from day one", which argues for adding it now; the
    alternative is deferring both to Task 9 and carrying no unreachable code. **Default: add it now**,
    with a comment saying what makes it live, because it is one line, it mirrors `parquet_sha` exactly,
    and a deferred line is a line Task 9 has to remember.
  - **CLASSIFY EVERY FIELD THIS TASK ADDS -- Task 19 landed the allowlist, so an unclassified field
    is silently outside identity.** `kind` is **semantic** and goes in the **hash list**; every field
    `.datom_build_set_metadata()` emits needs the same decision, one by one, against design.md
    section 4's matrix. Left unclassified, `kind` stops affecting `metadata_sha` and a table and a
    set can share a version identity -- which the 2026-08-23 decision closed off deliberately, and
    which no other test in this task would catch. Task 19's classification test is written to
    enumerate what the builders emit rather than hardcode names, so it **fails** until each new field
    is classified; extend it to cover the set builder. `document_sha` is already on the
    excluded list from Task 4, so leave it there -- but note it now becomes a field a builder **emits**,
    which takes it off the classified-before-written exception list (see the audit below).
  - **COLD-START AUDIT, 2026-09-10** -- the documented path (`dev/README.md` -> the state block ->
    this task -> `dev/engineering-notes.md`) was walked as a fresh reader and every claim checked
    against the tree. **Startable.** Two of this task's own statements were wrong and are corrected
    above (the design.md section 4 citation; "keep `document_sha` out of the metadata document").
    **No escalation flag** -- design.md section 12 carries E1 and E2 only -- so nothing is owed under
    rule 5d. Five things a fresh session would otherwise have to derive or discover the hard way:
    1. **ADDING `kind` RE-MINTS A VERSION FOR EVERY EXISTING TABLE, AND THAT IS AN ACCEPTED OWNER
       DECISION, NOT A DEFECT TO ENGINEER AWAY.** `kind` is identity, so a rebuilt table document
       hashes differently from the recorded one, `.datom_has_changes()` returns `metadata_only`, and
       the next write of every table in every repo mints a version on unchanged content. Verified by
       computing both hashes. The decision is in the Decisions log (2026-08-23) and **only** there,
       which is why a fresh session would reach for the two fixes it explicitly closed off: `kind`
       cannot be left out of the hash (a table and a set could then share a version identity) and
       cannot live only in the manifest (AC4's cross-kind check reads it from per-artifact metadata,
       precisely because the manifest can lag a partial write). Accepted as bounded and in the safe
       direction -- an **extra** version, not a changed one; same content, same storage address,
       parquet reused, nothing re-uploaded. Say it in NEWS.
    2. **P36 AS WRITTEN SAYS THE OPPOSITE OF WHAT THIS TASK DOES, and this task cites it.** Its first
       clause read "adding any field to a metadata document leaves every existing `metadata_sha`
       unchanged" without qualification, which is true only for a field outside the identity list.
       Scoped on this audit, the way P35 and AC32 were scoped when Task 22 changed their subject --
       the property was never "no addition moves a hash", it was "identity ignores what it does not
       name".
    3. **THIS TASK MOVES TWO PINNED GOLDENS, AND IT IS THE FIRST ONE ALLOWED TO.** `builder-derived
       metadata_sha goldens are stable` (`tests/testthat/test-utils-sha.R:1002`) holds two hardcoded
       hashes computed from `.datom_build_metadata()`; adding `kind` moves both. The standing
       instruction "if a golden fails the code drifted -- do not update the constant" is about the
       **sv1** goldens and applying it here would deadlock the task. Record both new values with the
       reason beside them, so the next reader can tell a licensed move from a drift.
    4. **THE FULL SET OF TESTS THIS REDDENS IS SIX SITES, not one.** `builder-derived metadata_sha
       goldens are stable` (`tests/testthat/test-utils-sha.R:1002`); `the pinned fixtures carry exactly
       the keys datom's writers emit` (`tests/testthat/test-utils-sha.R:1024` -- `kind` joins the
       `always` vector); `every field a metadata builder emits is classified`
       (`tests/testthat/test-utils-sha.R:1040` -- the forcing function, and the one to **extend** to
       the set builder); `nothing is classified before something writes it, except by decision`
       (`tests/testthat/test-utils-sha.R:1084` -- `document_sha` comes **off** the exception vector
       once the set builder emits it); `every field the metadata builder emits is in the metadata
       vocabulary` (`tests/testthat/test-forward-compat.R:210`); and `the metadata builder emits no
       kind, which is the only reason the rebuild may hardcode it`
       (`tests/testthat/test-manifest-rebuild.R:381`).
    5. **THAT LAST ONE IS A HANDOFF, NOT A FAILURE TO SILENCE.** It exists to make this task notice
       `R/manifest-rebuild.R:200`, where a rebuilt manifest row is stamped `kind = "table"` because
       nothing in per-artifact metadata says otherwise. Once this task adds the field, change that line
       to read `kind` from the document and keep `"table"` as the fallback for documents written before
       it existed, then replace the test with one asserting a set's metadata yields a row typed
       `"set"`. Deleting it instead leaves a rebuilt set reported as a table: the set counters read
       zero while the artifact still lists, and nothing errors.
  - _Requirements: R1 (R1.3 is the field list, R1.4 the exclusions), R7.1, R7.2, R9.5 (classify each
    added field). Invariants: I1, I12.
    Properties: P36 as scoped by this task's audit (the classification half -- this is the first task
    to add a field after the allowlist exists). Acceptance: AC8 (metadata half), AC33 (d) **extended to
    the set builder** -- Task 19 could only exercise the table half, since this task is what creates the
    set builder -- plus **R1.3's own inline acceptance** (exactly seven keys, asserted with
    `setequal()` so an added field fails). **Scope note on all three**: nothing writes a set until
    Task 9, so each is assertable here on the **builder's output** only. "A written set's metadata"
    and AC8's "writing a set does not alter any member's lineage" belong to Task 9._

- [ ] **8. `datom_member()` + validator + self-reference check**
  - `datom_member(conn, name, version)` mirroring `datom_parent()` (`R/lineage.R`): validate,
    read `{name}/.metadata/{version}.json`, derive `project` from `conn$project_name` and `kind`
    from the snapshot (defaulting to `"table"` for pre-`kind` metadata). Returns
    `{id: {project, name, kind, version}, tags: {...}}` as pure data.
  - **Signature gains tags**: `datom_member(conn, name, version, tags = NULL)` -- an optional named
    list of text values, validated against the R2.11 grammar at construction time (R4.6). Tags are
    **per-member** because they replace dpbuild's `dp$input` / `dp$output` / `dp$metadata` nesting,
    which classifies items rather than the collection. A value may be a string **or** a character
    vector, because the whole point of tags over folders is that an item can be in several
    categories at once.
  - `.datom_validate_members()` mirroring `.datom_validate_parents()`, including the `remedy`
    string pointing at `datom_member()`. It owns the **per-member** half of AC27 -- cases (a) non-text
    value, (b) `NA`, (c) `""` tag value. It **cannot** own the payload-level half: it sees one member
    at a time, so "same `id` twice with different `tags`" is invisible from here, and set-level `tags`
    never pass through it at all. Those are Task 9's (AC27 d/e). An earlier draft assigned all of
    AC27 here while Task 2 also claimed it; **retired** -- one half each, stated explicitly.
  - **Refuse self-reference** (R4.5, AC9): a set listing itself as a member. One cheap check. The
    set's own identity is known from `project.yaml` (R10.3a).
  - **Deliberately NOT built: cycle detection, a visited-set guard, or a depth limit** (R4.3/R4.4,
    design.md 5 and 20.11). Members pin immutable versions, so the graph is acyclic **by
    construction** -- a set cannot reference something that contains it, because that thing did not
    exist when its members were chosen (same property as git history). And datom resolves **one
    level** and never traverses, so nothing could loop even if a cycle existed. An earlier draft
    specified all three; they solved a problem that cannot occur. **Do not reintroduce them as
    defensive code** (I10a).
  - _Requirements: R4 (incl. R4.3-R4.5), R2.11, R2.7. Invariants: I9, I10, I10a, I24.
    Acceptance: AC9, **AC27 (a, b, c -- the per-member half)**._

- [ ] **9. `datom_write_set()`**
  - **Two gates first, before any hashing or IO** (R10.3a, I15): the repo must declare
    `mode: product`, and `name` must equal `project.yaml`'s `set:` field. These are what make
    "one repo = one set" real, and the second is the precondition the **self-reference check** (R4.5)
    relies on -- it needs the set's own identity before the write. **Not** a cycle walk: there is
    none, and I10a forbids reintroducing one.
  - **Signature: `datom_write_set(conn, members, tags = NULL, ...)`** (R12.2). The `tags` argument
    is **required structure, not decoration** -- R2.12 puts `tags` at the payload root, R2.6 hashes
    it, and AC2's converse half (a changed description mints a version) cannot be tested without it.
    R1.4 deliberately withholds `metadata =`, so this is the only channel.
  - Payload derived from members (each with optional per-member tags) plus optional **set-level
    tags** -- and **nothing else**. No view or navigation config: folder structure is a consumer-side
    projection over tags, never stored (R4.7, I25). No `metadata =` parameter -- user metadata is
    tags (R1.4/R6.2).
  - Written **git-canonical + storage-mirrored**, with **different paths on each side** (R6.1a):
    git at the **stable path `{name}/set.json`** (modified in place, so `git diff` shows
    member-level changes and git owns the history), storage at the **content-addressed**
    `{name}/{data_sha}.json` via the Task 1 helper (so a reader fetches an exact version by
    address). **Do not content-address the git path** -- that makes every version a new file and
    forces history to be read by listing filenames, which is hand-maintaining what git maintains
    (R6.1b, R20, AC24). No retention rule is needed: git retention is definitional, and P17 holds
    via `git show <commit>:{name}/set.json`.
  - **TIDY, then VALIDATE, then hash** -- in that order (R2.14, R2.15, I26; design.md 21.4 steps
    0a/0b). Tidying first clears the benign spellings so validation only ever sees genuine ambiguity;
    validating first would make the tidy rules unreachable. Six things are tidied **silently and must
    not abort**: tag-value order, tag-value duplication, single-vs-array shape, member order, an
    exact-duplicate member (same `id` *and* `tags`), and `character(0)` dropping its key. Assert on
    the **file bytes** (AC29a), not the return value.
  - **Canonical order: map keys radix; tag values radix + dedupe; single values unboxed; members
    deduped by digest then sorted by `project` || `name` || `version`** (R2.15). Note the file sorts
    by **name, not digest** -- digest order would relocate a member whenever its tags change, so
    `git diff` would report a delete plus an insert instead of one changed field, undoing R6.1a's
    entire purpose. The hash still sorts by digest; two sort keys, each with its own reason.
    Unboxing rather than always-array because `auto_unbox = TRUE` is already the house default.
  - **This task owns the payload-level half of AC27** -- the cases only a whole-payload view can see:
    (d) the same `id` listed twice with **different** `tags` is **refused** (dedup does not catch it,
    since the digest covers tags, so both entries would survive and a consumer would find one member
    in two conflicting folders); (e) zero members; plus set-level `tags` grammar, which never passes
    through `datom_member()`. **And the allow-case (R2.14a)**: the same `project`+`name` at two
    different `version`s must write successfully with both members present -- its own test, because
    `project`+`name` looks like the natural duplicate key and tightening to it would silently break a
    legitimate use (a current table beside a locked baseline).
  - **Never re-emit a payload for a `data_sha` already in history** (R7.5 rule 1, I27, AC29b): reuse
    the stored object and **carry the recorded `document_sha` forward**. Mirror
    `.datom_lookup_history_parquet_sha()` (`R/read_write.R:404-409`, `422-439`) -- it already does
    exactly this for parquet, including the `upload = FALSE` return. **This is the defect that passes
    every per-chunk test**: recomputing `document_sha` from fresh bytes while reusing the stored
    object records a hash of bytes nobody stored, and it surfaces later as a refused read of a valid
    version. Reachable by an ordinary tag-value reorder, not just a dependency upgrade -- see
    design.md 7.2.3.
  - **Reuse unchanged**: change detection (`.datom_has_changes()`), the git-gates-storage ordering
    (`datom_write()` steps 7-10), and dedup. Git push stays the serialization point (I5).
  - Cross-kind name uniqueness refusal (AC4) -- checked against **storage**
    `{name}/.metadata/metadata.json`, not the manifest, which can lag.
  - Manifest entry with `kind = "set"` and `member_count`. **`member_count` is the count AFTER
    tidying** -- the canonical member count, not what the caller passed. Pinned because tidying can
    drop an exact duplicate, so the two can differ; today they rarely do, which is exactly why an
    unstated rule would be settled by accident.
  - _Requirements: R5, R6 (incl. R6.1a/b), R7.5, R2.14, R2.14a, R2.15, R10.3a, R12.2, R8 (set
    entries). Invariants: I2, I5, I6, I11, I15, I25, I26, I27. Properties: P7, P13, P17, P25, P29,
    P32. Acceptance: AC2, AC3, AC4, AC5, AC24, AC29 (a and b),
    **AC27 (d, e, set-level tags, every tidy assertion, and the R2.14a allow-case)**._

- [ ] **10. `datom_read_set()` + `datom_read()` refusal**
  - `datom_read_set()`: resolve version -> read payload -> **verify `document_sha` before
    parsing** -> return members + payload. A missing `document_sha` is an **error, not a skip**
    (design.md section 8) -- sets have no legacy population, so reproducing the `parquet_sha`
    grace would build a silent-degradation path on purpose.
  - Works with **no git clone** (AC1a) -- storage-only readers are the primary consumer.
  - **Return member pointers; do not resolve them to data.** AC1 distinguishes *resolving the
    pointers* (always works through this one conn) from *resolving to data* (needs a conn for the
    member's project). Same-project members work through the same conn; cross-project members are
    the caller's to resolve (R18.1) -- datom has no name-to-location lookup. Getting this wrong
    mis-implements a set read as "requires access to everything in it", which would contradict the
    non-conjunctive access decision (R3.3).
  - **Both kind-mismatch directions abort with a pointer** (R12.3): `datom_read()` on a set ->
    `datom_read_set()` (AC6); `datom_read_set()` on a table -> `datom_read()` (AC14). Without the
    converse, a healthy table gets reported as a missing payload.
  - **One level only -- do not traverse** (R4.3, I10, AC15). A member that is itself a set is
    returned as a **pointer**; its own members are not fetched. Resist "helpfully" flattening the
    tree: a consumer wanting the full tree composes repeated reads, exactly as
    `datom_get_parents()` leaves further steps to the caller. Read cost must be a function of this
    set's direct member count, never of the depth beneath it (P16).
  - _Requirements: R12.3, R7.1, R7.2, R6.4, R4.3. Invariants: I3, I8, I10. Properties: P9, P16.
    Acceptance: AC1, AC6, AC14, AC15, **AC28**. AC28 is the integrity gate -- both halves: a
    mismatched payload is refused before parsing, **and** a missing/empty `document_sha` is an error
    rather than a skip. The second half is what a naive copy of `.datom_read_parquet()`'s
    `if (!is.null(...) && nzchar(...))` guard gets wrong._
  - _Pathway impact: new route card "Given a set + version, resolve its members"._

---

## Phase D -- Project mode, validation, docs

- [ ] **11. Project mode gating the import path**
  - **BLOCKED ON TASK 23, which must land first.** Not a preference: this task is what starts writing
    `mode: product`, and Task 23 is what gives an older build a way to notice. The reading half cannot
    be added to a build that has already shipped, so any release that writes `mode` without a release
    that reads the number leaves a permanent population that treats a product repo as an ordinary
    data repo. Landing Task 23 immediately before this one is what makes "same release" structural
    instead of something to remember at release time. See Task 23 for the reasoning and the scope
    limit.
  - `project.yaml` gains `mode: product` + `set: {name}` (R10.2). One repo = one set = one
    product.
  - **Decide whether this bump moves `project.yaml`'s format number, using R9.5's table rather than
    instinct.** Adding `mode` is an addition, so the default answer is **no bump** -- and the default
    is probably right, because an older build that ignores `mode` gets a silent no-op from
    `datom_sync()` rather than a wrong write. Record the call either way; a bump here costs every
    pinned build its access to the repo.
  - `datom_sync_manifest()` / `datom_sync()` refuse on a product repo with a clear message
    instead of silently no-op'ing.
  - `datom_status()` reports mode.
  - The table write path is **not** gated -- product repos legitimately write derived tables.
  - `datom_init_repo()` gains the means to declare `mode`/`set` at init; the Task 9 gates read it.
  - `mode: product` is also the **identity badge** the build package checks at attach time
    (R10.5) -- the mode carries two meanings, both of which must hold.
  - **New namespace-separation guard** (R17.3, AC22): initializing a `mode: product` repo refuses a
    namespace that already holds another project's manifest, naming the occupying project and
    pointing at using a distinct prefix. Extends the existing `.datom_check_namespace_free()` path
    rather than adding a parallel check. **Justify it in the message and docs on blast radius**
    (prefix-delete and teardown operate on a whole namespace, so a shared prefix means deleting the
    product can delete raw data) -- **not** on access control, which is per-artifact and finer than
    a namespace anyway (R17.4, R19.1).
  - _Requirements: R10 (incl. R10.3a, R10.5), R17. Invariants: I15. Acceptance: AC22._

- [ ] **12. Foreign-content discipline + `datom_repo_commit()`**
  - **Elevate machine-commit isolation from accident to guarantee** (R14.1, I16). Already true by
    implementation -- `.datom_git_commit()` takes an explicit file list (`R/utils-git.R:182`) --
    so this is primarily a **test** so a future add-all refactor fails CI rather than an audit:
    dirty `R/foo.R` + `datom_write()` of a table, assert the commit tree excludes it **and** it is
    still dirty afterward (AC16). Both halves -- the second catches a helpfully-cleaned tree.
  - **Assert tolerance of non-datom paths** (R14.2). This already holds by construction --
    `.datom_validate_tables()` filters on the presence of `metadata.json`, so `dp/` is skipped for
    that reason, not because of the hardcoded exclusion list (design.md section 19.7). So again:
    tests, not new code. `datom_status()` may *report* foreign dirty files as git state; it must
    not classify them as a datom defect, and `datom_validate()` must not surface them at all.
  - **New exports: `datom_repo_commit(conn, message, paths = NULL, push = TRUE)` and
    `datom_repo_push(conn)`** (R15) -- the sanctioned git-mutation surface, so downstream packages
    never import `git2r` (I17). **Both verbs are required**: `push = FALSE` without a standalone
    push verb means "push what I already committed" is only expressible as another commit attempt,
    and in a product repo `paths = NULL` is add-all -- so a push-only caller would risk committing
    human WIP (design.md section 19.8, I20).
  - **Commit is idempotent, push is convergent, neither implies the other.** R15.5's no-op means no
    *commit*; with `push = TRUE` and the branch ahead, the push still runs -- otherwise one failed
    push leaves the remote silently behind forever, since every later call finds a clean tree and
    returns early. The ahead count needs no new machinery: `.datom_check_git_current()` already
    calls `git2r::ahead_behind()` and reads `[[2]]` (behind); `[[1]]` is ahead (R15.9).
  - **Mind the two delta corrections** (design.md section 19.6), both of which change the
    implementation:
    - `.datom_git_commit()` does **not** abort on empty staging -- it returns HEAD's SHA. It
      aborts on an **empty `files` argument** and on **nonexistent files**. So `paths = NULL`
      cannot delegate with `files = character(0)`, and the wrapper must determine "nothing to do"
      itself (status check, or HEAD before/after) to honor R15.5's `invisible(NULL)` no-op.
    - The on-a-branch guard lives in `.datom_git_branch()` and is only reached via
      `.datom_git_push()`, so it does **not** fire when `push = FALSE`. Assert it explicitly up
      front (R15.7).
  - Roxygen: document that `paths = NULL` means what `git add .` means, including that it may
    sweep in dirty datom files left by a previously failed write -- intentional, and
    `datom_validate(fix = TRUE)` is the repair path (design.md section 19.7).
  - Tests: gitignore-respecting add-all; explicit `paths` stages exactly those; reader conn
    refused; empty staging creates no commit and is not an error; `push = FALSE` leaves the remote
    untouched; **clean tree + `push = TRUE` + branch ahead advances the remote with no new commit**
    (AC17). For `datom_repo_push()`: advances the remote, second call is a no-op, reader conn
    refused, on-a-branch guard inherited (AC21).
  - _Requirements: R14, R15 (incl. R15.8/R15.9). Invariants: I16, I17, I20. Properties: P19, P22,
    P23, P24. Acceptance: AC16, AC17, AC21. No pathway impact._

- [ ] **13. `datom_write_set(include_paths = )` -- the joint commit**
  - Follow-on to Task 9 rather than folded into it: Task 9 is already large (two gates, dual-write,
    dedup, name uniqueness, manifest), and the dedup edge below deserves its own commit.
  - `include_paths`: repo-relative paths staged **into the same commit** as the payload and
    metadata, so the joint version is **structural, not recorded** (R12.5). Ordering unchanged:
    local writes -> one commit -> push -> storage mirror.
  - **Storage mirror stays datom-artifacts-only** -- `include_paths` content is never mirrored
    (I18, AC18).
  - **Validation before any hashing or IO** (matching R10.3a placement): a nonexistent path is an
    **error**, not a skip; a path overlapping `{artifact}/**` or `.datom/**` is **refused**
    (AC20). **Two separate test cases**, not one bundled assertion, so a regression identifies
    which gate broke.
  - **The sharp edge**: an unchanged set stays a **no-op even when `include_paths` files are
    dirty** -- no commit, no version, informational message pointing at `datom_repo_commit()`
    (R12.5, I19, AC19). AC2's idempotency must not acquire a side channel that commits code; that
    would be the machine-moment add-all failure arriving through a different door.
  - Update P17's claim in the docs: with `include_paths`, checkout of a set version's commit
    yields code + environment + data pointers, not pointers alone.
  - _Requirements: R12.5. Invariants: I18, I19. Properties: P17 (strengthened), P20, P21.
    Acceptance: AC18, AC19, AC20._

- [ ] **14. `datom_validate()` branches on `kind`**
  - `.datom_validate_one_table()` at `R/validate.R:444` builds the payload key with the kind
    **hardcoded** to `"table"`: `.datom_artifact_payload_key(name, meta$data_sha, "table")`, which
    resolves to `.parquet` and so fails 100% of the time on a set. (Task 1 replaced the original
    `paste0()` here, and the helper already accepts `kind = "set"` -- so this is a call-site change,
    not new key logic. Earlier drafts of this task described the `paste0()` form.)
  - **table**: existing parquet check, unchanged. **set**: payload exists at
    `{name}/{data_sha}.json` **and** every member resolves *as far as the connections allow* --
    same-project members fully checked, cross-project members checked as well-formed pointers
    unless the caller supplies that project's conn (R11.2). datom does no name-to-location lookup
    of its own (R18.1), so a validator claiming to fully check cross-project members would either
    be lying or silently requiring governance.
  - New status code `members_unresolvable`, distinguishable from a missing payload (P14).
  - **Member checking is one level deep** (R4.3, I10): each member pointer resolves to an existing
    artifact. The validator does not descend into nested sets -- validating an inner set is a
    separate `datom_validate()` call against that set's own project.
  - Scope note: R11.2 specifies a **storage-side** check (payload exists, members resolve). An
    earlier draft here promised a git-vs-storage comparison "which R6.1b's git retention makes
    possible" -- **removed**, because R6.1b reversed per-version payload files in git: git now holds
    one mutable `{name}/set.json`, so only the *current* version is comparable without `git show`.
    Do not add unrequested git-side comparison.
  - **`fix = TRUE` must not break `document_sha`** (R7.5 rule 2, I27, AC29c). Repair re-uploads from
    the clone, so it is a live path to overwriting a stored payload. It must **reuse the recorded
    `document_sha` and never recompute it** for an existing version. Same trap shape as the
    `commit_sha` one (R21.7, I22): a repair path silently undoing a write-path guarantee. AC29c is
    the clause a naive implementation fails while passing everything else.
  - _Requirements: R11, R4.3, R7.5. Invariants: I10, I27. Properties: P14, P16, P32.
    Acceptance: **AC29 (c)** -- named here explicitly because an earlier draft discussed it in this
    task's body while listing it in no acceptance line anywhere, leaving the clause the spec twice
    calls "the one a naive implementation fails while passing everything else" owned by nobody. AC15
    (one-level member checking). **P14 has no AC of its own** -- add one here asserting `ok` for a
    healthy set and *distinguishable* statuses for a missing payload versus an unresolvable member;
    R11.3 calls this in scope rather than deferred, so it must not ship untested._

- [ ] **15. Version-to-commit link (`commit_sha`)**
  - Applies to **all** artifact kinds, not just sets -- `version_history.json` is shared. Placed
    after Task 14 because the repair-path behavior below needs `datom_validate()` to exist.
  - Add `commit_sha` to the **storage copy** of the `version_history.json` entry, beside `author`
    and `commit_message` (R21.5). **No volatile-list entry needed**: `metadata_sha` hashes
    `metadata.json`, not `version_history.json`, so this has zero identity impact.
  - Captured in `.datom_push_metadata_s3()` (step 7 of the write order, after the push), because
    the git copy of the history file is **inside** the commit it would name (R21.6). The git copy
    therefore never carries it, and does not need to -- `git log -p {name}/set.json` gives it to
    anyone with the clone (R21.8).
  - **The trap, and the reason this is its own task** (R21.7, I22, AC25): `datom_validate(fix =
    TRUE)` re-uploads metadata from the clone and would **silently strip `commit_sha`**. Treat the
    field as **derived, never authored** -- the repair path must **re-derive** it from `git log` on
    the artifact path. A naive implementation passes every other test and fails only this one,
    silently.
  - Document the version semantics this encodes (R21.1-R21.3): a version is content-derived and
    **code-invariant**, so a code-only change producing identical content mints **no** new version
    and leaves the recorded `commit_sha` alone (AC26). Roxygen should say this plainly -- it is the
    behavior most likely to be reported as a bug.
  - _Requirements: R20, R21. Invariants: I21, I22, I23. Properties: P26, P27. Acceptance: AC25,
    AC26. No pathway impact (no new lookup route -- the existing history read gains a field)._

- [ ] **16. Acceptance-criteria test sweep + E2E** &nbsp; **[soft escalation: coverage review]**
  - Confirm **every AC defined in `requirements.md`** has a dedicated test -- derive the list, do not
    trust a range written here. A hardcoded range has now gone stale **twice**: it once stopped at
    AC26 and omitted AC27, and it then stopped at AC28 and omitted AC29. `dev/check-spec.R` now
    asserts this line names no explicit upper bound, so the defect cannot recur. Then add what the
    per-chunk tests
    missed. Two are easiest to skip and both need special fixtures: **AC15** (nesting resolves one
    level) needs a set-containing-a-set fixture and an assertion that the inner payload is *not*
    read; **AC16** (machine-commit isolation) needs a foreign dirty file seeded in the fixture repo,
    which no other test creates.
  - New `dev/e2e-sets.R` in the style of `dev/e2e-cv1-identity.R`: offline, no PAT, no AWS, real
    bare-git remote + real local store, every claim asserted, non-zero exit on mismatch (AC12).
    Include a `mode: product` repo with foreign `R/`, `dp/`, and `renv.lock` content so the joint
    commit and the machine-commit isolation are exercised end to end, not only in unit tests.
  - Full `devtools::test()` count reported; `R CMD check --as-cran` 0E/0W (AC10, AC11).
  - _Acceptance: every AC defined in `requirements.md` -- derive the list, do not restate a bound._
  - **Escalation rationale**: the full acceptance-criteria set plus a new hash regime is a lot
    of surface to claim covered on a default model's word.

- [ ] **17. Docs + Spec Completion Procedure**
  - `dev/datom_pathways.md`: the set-resolution route card; note the `kind` branch and the
    `schema_version` gate on the read route (R13.1).
  - `dev/datom_specification.md`: set artifact kind, `datom-sv1`, `schema_version` contract,
    `artifacts` namespace (R13.2).
  - `NEWS.md`: the `artifacts` rename with its discovery-only exposure, the `schema_version`
    gate, the new exports (R13.4).
  - `dev/engineering-notes.md`: gotchas discovered (expect at least the relative-vs-full key
    distinction from Deviation D1).
  - `_pkgdown.yml` reference entries for all new exports.
  - `dev/README.md`: move the spec Active -> Completed with date, test count, summary. **The spec
    persists -- do not delete it.**
  - Also document the two forward-compatibility mechanisms **together**, never separately: the
    vocabulary check and the schema number cover complementary sets and neither is sufficient alone
    (R23.5). And say plainly that every write-side refusal binds **0.1.1 forward only** (R23.7).
  - PR into `dev`, merge, delete branch.
  - _Requirements: R13, R9.6 (the schema history table ships here if #103 has not landed
    separately), R23.5, R23.7. Acceptance: **none of its own by design** -- this task ships no
    behaviour, so it has no criterion to assert. Its gate is the Spec Completion Procedure in
    `dev/README.md` plus AC10/AC11 (suite green, `R CMD check --as-cran` 0E/0W), both already owned
    by Task 16. Stated explicitly because silence in this slot previously read as an omission: this
    clause was **absent** until 2026-08-23 and the gate did not catch it, since Task 17's body ran to
    the end of the file and absorbed a later `Acceptance:` string._

---

## Phase E -- Forward-compatibility controls for 0.1.1 **[appended; five run EARLY, one does not]**

**These are appended but they do NOT run last.** Appending avoids a third renumber (see the
2026-08-23 shift record in the Decisions log); the execution order is stated here instead.

```
18 -> 19 -> [Task 5] -> [Task 6] -> 20 -> 21 -> 22 -> 7 -> 8 -> 9 -> 10 -> 23 -> 11 onward
```

- **18** is a prerequisite defect fix; the write-entry sequence sits on that function.
- **19** must land before **Task 7**: an allowlist seeded from *table* metadata and landed after the
  set metadata builder would silently drop set-specific semantic fields from identity -- the
  classification failure, on the first artifact of a brand-new kind.
- **20**, **21**, **22** need Phase B's single reader (Task 5) and the upgrade chain (Task 6).
- **23 must land before Task 11, and that is the one edge in this phase that does not point early.**
  Task 11 is what starts writing `mode: product` into `project.yaml`; Task 23 is what lets an older
  build notice. Writing the field first would leave a permanent population treating a product repo as
  an ordinary data repo. It sits immediately before Task 11 rather than at the front, because that is
  exactly sufficient -- nothing between here and Task 10 writes to `project.yaml` -- and rather than
  last, because a note saying "ship these together" is checked by memory at release time while a task
  order is not.

**Why these six and not others.** The filter is **does deferring it postpone the cost, or permanently
exclude every install shipped meanwhile?** All six only ever help builds that already contain them,
so deferring any one strands every 0.1.1 install forever. Everything else from the same review round
-- the bump rules, the schema history table, the policy prose, the floor's tooling -- lands later
without stranding anyone. If 0.1.1 gets crowded, those slip; these do not.

**Task 23 was added on 2026-09-10, after Task 22 shipped**, so it is the one item here that did not
come out of the 2026-08-23 review round. It meets the same filter, which is why it lives in this phase
rather than in Phase D beside the task it blocks.

**The aim, stated so it can be checked**: 0.1.1 is the **last** release that needs a transition plan.

- [x] **18. Fix `.datom_check_git_current()`'s fetch-failure return** &nbsp; **[DONE 2026-08-26]**
  - `return(invisible(TRUE))` sat inside the `tryCatch` error handler (`R/utils-git.R:435-448`
    post-fix; it was `422-429` when the defect was recorded), so
    it returned from the **handler**, not from the function. After a failed fetch, execution continued
    and compared `HEAD` against **stale cached** upstream refs. An offline user whose cached upstream
    is ahead got a hard abort where the comment says "network errors should not block offline work".
  - A live defect independent of this spec, and Task 21's entry sequence is proposed to sit on this
    function -- so it is fixed first and on its own.
  - Filed as [#104](https://github.com/amashadihossein/datom/issues/104); it is a bug fix, not spec
    work, and it is reachable in ordinary use (fetch once on a good connection, go offline, run the
    sync route).
  - **The fix**, restated here so this task does not depend on the issue being reachable: capture the
    fetch outcome and return from the function proper.

    ```r
    fetched <- tryCatch({
      git2r::fetch(repo, name = remote_name, credentials = cred)
      TRUE
    }, error = function(e) {
      cli::cli_alert_warning("Could not fetch from remote: {conditionMessage(e)}")
      FALSE
    })
    if (!fetched) return(invisible(TRUE))
    ```

  - **How to test it -- no git2r mocking required.** Tests go in `tests/testthat/test-utils-git.R`,
    in the existing `.datom_check_git_current()` block. `create_repo_with_remote()` gives
    `info$work_path` and `info$bare_path`, and the neighbouring "aborts when behind remote" test
    already builds most of the scenario. Sequence for the failing case: build the repo, have a second
    clone push a commit, fetch once so the remote-tracking ref is **cached ahead**, then break the
    remote (point its URL at a nonexistent path, or remove `info$bare_path`), then call the function.
    Today it warns and then **aborts** on the stale-but-ahead refs; after the fix it warns and
    returns. Add the companion case too -- fetch fails with cached refs **level** -- since that one
    passes today by accident and must keep passing for the right reason.
  - Keep the healthy-connection tests in that block green unchanged: they are what proves the fix did
    not turn the guard off.
  - _Requirements: none (defect fix). Acceptance: a repo whose fetch fails **warns and proceeds**,
    including when cached upstream refs are ahead of local -- the case that aborts today. Assert both
    the warning and the absence of an abort. No pathway impact -- record explicitly._
  - **DONE 2026-08-26.** The fix is the captured-outcome form above, with the reason it is written
    that way in a comment at the site so the next reader does not "tidy" the `return()` back inside
    the handler. Two tests added to the existing `.datom_check_git_current()` block in
    `tests/testthat/test-utils-git.R`, both no-mock as specified. tests: **2664** (+4),
    FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all nine checks pass. No pathway impact --
    the write route is unchanged; this restores the offline tolerance the route already claimed.
  - **The ahead-case test was proven non-vacuous before being trusted**, per the rule this spec
    applies to its own gates: stashing the `R/` change and re-running the file makes it **error** on
    the stale-ahead abort, and restoring the change makes it pass. The level-case test passes either
    way by design -- it exists because that case passes today for the wrong reason (nothing
    unfavourable to compare against, rather than the failure being handled), so it pins the accident
    as deliberate.
  - **No git2r mocking, and the mechanism is worth knowing**: `git2r::remote_set_url()` pointed at a
    nonexistent path makes `fetch()` raise for real ("unsupported URL protocol"), so the offline
    condition is genuine rather than stubbed. The neighbouring "tolerates network errors gracefully"
    test still stubs `git2r::fetch` and still has **no upstream branch**, which is why it never
    caught this: with no upstream the function returns before the comparison, so it passed on the
    defect. Left as-is -- it covers the no-upstream path.
  - **The warning is a cli alert, so it is a MESSAGE, not a condition of class `warning`.** Assert it
    with `expect_message()`; `expect_warning()` fails and reads as the fix not warning at all.
  - **This narrows a live safety check, deliberately.** An offline write now proceeds without knowing
    it is behind. The backstop is `.datom_git_push()`, which pulls and aborts if the push is rejected
    (`R/utils-git.R:267-277`, with the storage steps after it), so a write cannot land on storage from
    a stale base -- the same argument design.md 10.7 already makes for warn-and-proceed at the door.
    Recorded in the function's roxygen too, since "warns and returns TRUE" looks like a swallowed
    error to anyone reading the guard cold.

- [x] **19. Allowlist identity hashing (#100) + the classification test** &nbsp; **[DONE 2026-08-28]**
  - `.datom_compute_metadata_sha()` selected fields by **exclusion**, which
    cannot be forward-compatible: a build that has never heard of a field cannot know to ignore it, so
    it folds the field into the hash and reports a change on content that did not move. (Line numbers
    in this task's body describe the **pre-change** file; after the change the two constants are at
    `R/utils-sha.R:422-447` and the two functions at `R/utils-sha.R:469` and `R/utils-sha.R:501`.)
  - Hash a **named list** of fields; ignore everything else. **Seed it with exactly the fields hashed
    today so every existing identity is byte-identical.** Optional fields need marking optional --
    `parents`, `source_lineage`, `original_file_sha`, `custom` are conditionally present.
  - **An allowlist fails the opposite way from a denylist.** A denylist silently *includes* an unknown
    field; an allowlist silently *excludes* a new one, so identity quietly stops responding to real
    content changes. The classification test is the only thing that catches that direction: assert
    every field any metadata builder can emit -- **table and set** -- is classified, in the hash list
    or on a documented excluded list, so a new field cannot ship without a decision.
  - **Its justification has changed and the old one must not survive into the code comments.** Filed
    as "older writers keep working"; after the vocabulary decision (Task 21) they do not, by design.
    What it buys now: **readers compute correct identities, and a repo does not accumulate spurious
    versions**.
  - **THE CLASSIFICATION TEST MUST DERIVE THE FIELD SET FROM THE BUILDERS, NOT HARDCODE IT.** This is
    the difference between a forcing function and a decoration. AC33(d) names table **and** set
    fields, but the set builder does not exist yet -- Task 19 runs before Task 7 by design -- so at
    this point only the table half is exercisable. A hardcoded list of today's field names would
    therefore pass forever and never notice Task 7 adding `kind`. Instead enumerate what a builder
    actually emits (call `.datom_build_metadata()` with every optional argument supplied and take
    `names()`), then assert each name is in the hash list or on the documented excluded list. Written
    that way the test **fails the moment Task 7 touches the builder**, which is what makes the
    forward obligation self-enforcing rather than remembered.
  - **The field inventory is fully discoverable from one function, verified 2026-08-26.** Every
    top-level key of a metadata document is assigned inside `.datom_build_metadata()`
    (`R/read_write.R:302-311` for the five conditional ones) with exactly one exception,
    `meta$parquet_sha` at `R/read_write.R:806`, which is volatile. Nothing else in `R/` writes a
    top-level metadata key. So seeding the allowlist does not require a hunt: the semantic set today
    is `data_sha`, `hash_algo`, `table_type`, `nrow`, `ncol`, `colnames` always, plus
    `original_file_sha`, `parents`, `source_lineage`, `custom` when present. Recorded because an
    allowlist seeded from an incomplete inventory silently drops content out of identity, and the
    grep that proves the inventory complete is cheaper to record than to redo.
  - **AC33(a)'s pinned value exists but its fixture is NOT a realistic document. DECIDED
    2026-08-26 -- implement the two steps below; do not re-deliberate.** The golden
    `59f1f1d936c5d65472733a924493ce2362255d442ebea6d41f7c3c9e7069d326`
    (then at `tests/testthat/test-utils-sha.R:899-904`; the repurposed test is now at
    `tests/testthat/test-utils-sha.R:921`) hashes
    `list(data_sha, name, nrow, ncol, table_type, hash_algo)` -- and **`name` is a field no builder
    emits.** Verified: `metadata.json` is written as exactly the object `.datom_build_metadata()`
    produced (`R/read_write.R`, `write_json(metadata, ...)` inside
    `.datom_write_metadata_local()`), and that object has no `name` key; the `name` at
    `R/read_write.R:794` and `R/read_write.R:869` is `datom_write()`'s **return value**, not the
    document.
    So a builder-derived allowlist will not contain `name`, this fixture's hash **will** change, and
    the golden test fails -- while **no real identity moves at all**, because no stored document ever
    carried the field. The fixture is unrealistic in a second way too: it has no `colnames`, which
    the builder always emits. Hitting that on day one and reflexively re-pinning the constant would
    destroy the only pinned evidence AC33(a) rests on.
  - **The two steps, in this order** (owner-decided 2026-08-26):
    1. **Anchor first, before touching `.datom_compute_metadata_sha()`.** Add a pinned fixture built
       by `.datom_build_metadata()` itself, with every optional argument supplied, and record its
       `metadata_sha` under **today's** code. That value is AC33(a)'s evidence and **must not move**
       across this task. Do this as its own step: a pin computed in the same edit as the change it
       polices is worth much less.
    2. **Repurpose the `name`-bearing golden as AC33(b)'s test rather than retiring it.** `name` *is*
       an unknown extra field, which is exactly the case AC33(b) asserts -- a document carrying one
       hashes identically to one without it. So assert that equality, and its pinned constant becomes
       the no-`name` value. The fixture that was going to break becomes the assertion for the
       property that breaks it.
  - **Rejected: adding `name` to the allowlist** to keep the old golden byte-identical. It is the
    tempting option and the cheapest in test churn, but the allowlist would then name a field datom
    never writes, breaking the one property that makes the list readable -- that it *is* what the
    builders emit. A later reader would reasonably conclude a `name` field exists somewhere.
  - **Superseded wording**: an earlier draft of this bullet called the above a "recommendation, not a
    decision" and told the implementer to settle it first. It is settled.
  - _Requirements: R9.5, R23.1 (the excluded list is the vocabulary's other half). Properties: P36.
    Acceptance: AC33 (all four clauses). The cv1 identity-contract suite
    (`tests/testthat/test-identity-contract.R`) must stay green, and the pinned-value assertion in
    AC33a is the one that proves this was behaviour-preserving. No pathway impact -- record
    explicitly._
  - **DONE 2026-08-28, in two commits, the ordering being the point.** Commit 1 (`fb84a72`) added the
    pins under the **unchanged** denylist code; commit 2 changed the selection. Two namespace-level
    constants in `R/utils-sha.R` -- `.datom_metadata_identity_fields` (ten fields, seeded to exactly
    what was hashed before) and `.datom_metadata_excluded_fields` (the seven-name `volatile` vector,
    promoted from a local variable so Task 21 can read the union as its vocabulary). Selection is
    `intersect(names(metadata), .datom_metadata_identity_fields)`. tests: 2675 -> **2686** (+11),
    FAIL 0 / WARN 0 / SKIP 0. `Rscript dev/check-spec.R` all nine checks pass. No pathway impact --
    route shapes and gate positions are unchanged.
  - **Behaviour preservation is asserted, not inferred from a green suite.** Both pins from commit 1
    hold unchanged after the change: `f4d88543...` (every optional field supplied) and
    `d0c1ea75...` (none), which is AC33(a) and AC33(c). Before implementing, the two selections were
    also run side by side over six document shapes -- builder output with and without optionals, both
    again after a JSON round trip, and two hand-built fixtures -- byte-identical on all six.
  - **The whole suite showed exactly TWO failures under the change, both anticipated**, which is
    worth recording because it bounds the blast radius: the `metadata_sha` golden and Property 13.
    Everything in `test-read-write.R` and `test-identity-contract.R` survived untouched, because
    every one of those call sites computes-then-compares over real field names rather than pinning a
    value.
  - **THE FUNCTION IS NOW TWO FUNCTIONS, and Property 13 is why.** `.datom_compute_metadata_sha()`
    selects; the new `.datom_metadata_sha_from_fields()` sorts, serialises and digests. Property 13
    proves field ordering does not move with `LC_COLLATE`, using a fixture of names that genuinely
    collate differently (`Zeta`, `_leading`, `beta`). An allowlist drops all of them, leaving one
    field and nothing to order -- the test would have passed while asserting nothing. And it cannot
    be rebuilt from real names: **all ten identity field names sort identically under `C` and
    `en_US.UTF-8`** (checked), so no fixture made of them can discriminate. The split gives the
    ordering property something honest to bind to.
  - **Rejected: declare the list in radix order and drop the sort.** Locale independence would become
    structural, since nothing would be sorted at runtime. Rejected because hash stability would then
    depend on how somebody *types a constant* -- reordering it for readability would silently change
    every recorded version. Sorting keeps the order derived. The reasoning is in
    `.datom_metadata_sha_from_fields()`'s roxygen so the next reader does not "simplify" it back.
  - **The classification test derives its inventory from the builder and was proven to fail before
    being trusted**, per this spec's own rule. Adding a junk field to `.datom_build_metadata()` makes
    it go red naming the field -- **while every pinned hash stays green**, which is precisely the
    failure direction an allowlist has and a denylist does not. It carries a converse arm too:
    nothing in the identity list may be a field datom never writes, which is what mechanically blocks
    the rejected shortcut of allowlisting `name`. Adding `"name"` to the list turns that arm red, plus
    AC33(b). Both probes were reverted; the workspace carries neither.
  - **Three tests were quietly going vacuous and are re-fixtured**: `metadata SHA is deterministic`,
    `is order-independent` and `is a 64-char hex string` were built from `name` / `author` / `x`, all
    of which the allowlist drops -- leaving `data_sha` alone to carry assertions about several fields.
    They now use real field names, and the order-independence one gained a positive check that the
    shared fields really do reach the hash.
  - **The `name`-bearing golden was reused rather than retired, as decided.** It now asserts AC33(b)
    with its constant re-pinned to the no-`name` value
    `cce751b3f74d9f45c79ec96e4a19529580fec36b6ea37b39800b3a8a58e94ac8` -- which is what today's code
    already produced for that fixture minus the field, so it is not a fresh pin off the new
    implementation. A second unknown key (`some_future_field`) was added beside it: `name` is a
    historical accident, whereas a field arriving from a newer datom is the case the allowlist exists
    for, and only the second one reads as forward-looking.
  - **Two documentation sites were going to contradict the code, and one was ALREADY stale.**
    `dev/engineering-notes.md` said new non-versioning fields must be added to the `volatile` vector
    -- exactly inverted now -- and told the reader to keep the `59f1f1d9` fixture as-is; both entries
    are rewritten, the second carrying the transferable lesson that a pinned identity fixture must be
    a document the package can actually write. `vignettes/design-version-shas.Rmd` prints the
    algorithm as runnable-looking code and **listed five excluded fields when Task 4 had made it
    seven**, so it was wrong before this task touched it; it now shows the allowlist form and
    explains the forward-compatibility reason in plain terms.
  - **Deliberately NOT done here: [#98](https://github.com/amashadihossein/datom/issues/98).** The
    `dev/README.md` backlog row suggests pairing it with #100 so there is one identity-affecting
    change to verify. They cannot ship together: removing `jsonlite` from the identity path changes
    the hashed **bytes**, so every recorded identity moves -- the direct negation of AC33(a). #98
    stays a separate, deliberately breaking change.
  - **One gap left open, named rather than closed quietly.** A document with **no** identity fields at
    all now hashes an empty object instead of hashing its junk, so two unrelated corrupt documents
    hash equal. Reachable only from a corrupt file, and adding a refusal is an unrequested behaviour
    change, so no guard was added (I10a's spirit: no defensive code for a state nothing produces).
    Recorded so a later reader knows it was seen.

- [x] **20. Carry unrecognised fields forward on write (#100's missing half)** &nbsp; **[DONE 2026-09-08]**
  - Today the write path rebuilds metadata from scratch (`.datom_build_metadata()`), so an older build
    does not merely miscompute -- it **deletes** the field it did not understand.
  - Preserve unrecognised **top-level** keys at **three** levels: per-artifact metadata documents,
    manifest **entries**, and manifest **top-level** keys.
  - **The reason is information loss, not churn.** Churn settles after one version per handoff either
    way, because a build that deletes the field agrees with itself on its next run. Today most such
    fields are recomputable; the rule exists for the ones that will not be. So the test asserts the
    field **survives a round trip**, never a version count.
  - Note this now only bites where a write is permitted at all (Task 21 refuses most such writes), and
    it is kept because the manifest-level and cross-role cases still exercise it.
  - _Requirements: R23.8. Properties: P38. Acceptance: AC34. No pathway impact -- record explicitly._
  - **FIVE OPEN CALLS, ALL FIVE EXPLICITLY APPROVED (2026-09-08).** Recorded in Task 6's shape so the
    round stays checkable. These were **approved outright, not taken on silence** -- the owner
    answered "choices are fine" -- so each is a decision rather than a default that happened to hold.
    1. **The prior document is read from the clone, not from storage.** *Approved.* Shipped as
       `.datom_prior_metadata()`. Storage's copy is free to read at the point the merge happens, so
       this was a real choice: the clone wins because it is the file being overwritten, it costs no
       round trip, and it is where a pull from a newer collaborator lands.
    2. **A new file, `R/forward-compat.R`, rather than folding the helper into an existing one.**
       *Approved.* Task 21 adds three more functions to the same concern, which would otherwise land
       in three different files.
    3. **A preserved field is not announced.** *Approved.* Nothing is lost, so there is nothing to
       act on, and Task 21's refusal will make most of these writes stop anyway -- a message added
       now would be dead within one task.
    4. **The manifest row's vocabulary does not pre-list the set row's `member_count`.** *Approved.*
       Task 9 trips the forcing function when it adds the field, which is the point.
    5. **All three levels are built even though Task 21 makes two of them hard to reach.**
       *Approved.* See the bullet on that below: the row-level case is never covered by Task 21 at
       all, and `datom_validate(fix = TRUE)` bypasses the door.
  - **DONE 2026-09-08.** New `R/forward-compat.R` holds the whole of it:
    `.datom_carry_unknown_fields()` (copy onto a rebuilt document every top-level field of the prior
    document whose name this build cannot place), `.datom_metadata_known_fields()`,
    `.datom_manifest_entry_known_fields` and `.datom_prior_metadata()`. Two call sites:
    `datom_write()` step 5a (`R/read_write.R:808-821`) for the per-artifact document, and
    `.datom_update_manifest_entry()` (`R/sync.R:1004-1018`) for the artifact's manifest row. New
    `tests/testthat/test-forward-compat.R`, three internal `man/` pages, no new export, NAMESPACE and
    `_pkgdown.yml` untouched. tests 2867 -> **2902** (+35), FAIL 0 / WARN 0 / SKIP 0;
    `Rscript dev/check-spec.R` 9/9. **No pathway impact** -- no new lookup and no new traversal; two
    documents gain fields on the way out of a step that was already there.
  - **THERE IS A FOURTH SURFACE THE REQUIREMENT DOES NOT NAME: an entry in `version_history.json`.**
    Safe by the same property as the manifest's top level -- the history list is read and the new
    version is **prepended** (`R/read_write.R:529`), so an entry already in it is never rebuilt -- and
    equally unpinned until now. It is worth pinning rather than arguing because **two later tasks add
    fields to these entries**: Task 7's `document_sha` and Task 15's `commit_sha`. A build that
    normalised an old entry to today's field set would destroy exactly those, on a document describing
    a version it may know nothing about. One test (an unfamiliar field on an existing entry survives a
    later write, in git and in storage) and a comment at the site. Proven non-vacuous: rebuilding the
    existing entries from known names reddens both halves.
  - **`document_sha` IS THE ONE NAME THIS BUILD RECOGNISES AND NEVER WRITES, and that interacts with
    the narrowness rule -- decide it in Task 7 rather than meeting it.** Verified mechanically: the
    vocabulary holds 17 names, the metadata builder emits 16, and the odd one out is `document_sha`,
    which Task 4 classified as not-identity before anything wrote it. Because the merge carries only
    names it **cannot** place, a metadata document arriving with `document_sha` on it would have that
    field **dropped** on rewrite -- and dropped silently, since the field takes no part in identity, so
    no version moves to signal it. Unreachable today (nothing writes the field) and still unreachable
    after Task 7 as currently specified, which puts `document_sha` in `version_history.json`, where the
    fourth-surface property above protects it. What Task 7 must not do is put `document_sha` into a
    metadata document without also deciding what a build that does not emit it should do with one --
    the answer is not "carry it", because the rule cannot see it as unplaceable. The general shape,
    which is the reusable part: **a name that is classified but never emitted is invisible to
    carry-forward**, so classifying a field ahead of writing it is not free.
  - **THE THIRD LEVEL NEEDED NO CODE, AND THAT IS THE ONE WORTH KNOWING BEFORE TOUCHING THIS AREA.**
    The manifest's **top level** already survives, because `.datom_update_manifest_entry()` reads the
    document, edits three keys and writes it back -- an unfamiliar key beside `artifacts` is never
    touched. It is tested anyway: the guarantee is a property of *editing rather than rebuilding*, so a
    later refactor that assembled a fresh document would take it away without failing anything else.
    Proven by probe: making that function build from the skeleton instead of reading the file reddens
    the top-level test. A comment at the site says so.
  - **ONLY UNPLACEABLE FIELDS ARE CARRIED, and the alternative is worse rather than merely different.**
    A field datom knows keeps exactly today's behaviour, including disappearing when the write does not
    set it. The deciding case is `original_format` on a manifest row: a table imported from a CSV and
    later written straight from a data frame has no format to declare, and the row must stop claiming
    one. A blanket "keep whatever the new document does not mention" would leave that claim standing
    against a version it does not describe -- a wrong statement, where the thing being avoided is only
    a missing one. Two tests pin it (`custom` on the metadata document, `original_format` on the row)
    plus a unit test, and all three redden under a blanket merge.
  - **The merge happens after the version identity is computed**, next to the `parquet_sha`
    assignment, not inside the builder. Identity already ignores fields it cannot place, so both
    positions give the same hash today; attaching afterwards means a carried field cannot reach a hash
    **at all**, so no later change to the identity field list can pull one in. A test asserts the
    other half of the same point from outside: planting an unfamiliar field in both copies of a
    document leaves the next write a no-op, so such a field mints no version by itself.
  - **The prior document is read from the CLONE, not from storage** (`.datom_prior_metadata()`). It is
    the file being overwritten, it is a local read rather than a round trip, and it is where a pull
    from a collaborator on a newer datom lands. Storage cannot legitimately hold a newer document than
    the clone, because git is written first and gates the mirror; if it does, that is drift and
    `datom_validate()` owns drift. Same copy Task 21's checks read (R23.1a), so the door and this
    merge cannot disagree about which document they are talking about.
  - **`.datom_metadata_known_fields()` is a function, not a stored vector, and it has to be.** `R/` is
    sourced alphabetically (DESCRIPTION declares no `Collate`), and `forward-compat.R` sorts **before**
    `utils-sha.R` where both halves of the classification live -- so a constant built from them here
    would be built from values that do not exist yet and the package would fail to install. Same trap
    the `R/manifest-upgrade.R` header records for its step table, reached from the opposite direction.
  - **The manifest row gets its own vocabulary and its own forcing function.** Eight names today,
    listed by hand rather than derived from the row builder -- a vocabulary read off the builder's own
    output could never disagree with it. The test writes a real artifact with both optional row fields
    supplied and asserts every field on the resulting row is classified, so adding one without
    classifying it fails rather than making that field look unplaceable and get carried forward stale
    on every later write. **Task 9 will trip it** when it adds `member_count`, deliberately: the field
    is not pre-listed.
  - **EVERY GUARD WAS PROVEN TO FAIL BEFORE BEING TRUSTED, and each probe was reverted.** (a) Removing
    the metadata merge reddens both halves of the metadata round trip, git and storage. (b) Removing
    the row merge reddens both halves of the row round trip. (c) Rebuilding the manifest instead of
    editing it reddens the top-level test **and** the row test. (d) Widening the merge to keep every
    absent field reddens all three narrowness tests. (e) Adding an unclassified field to the metadata
    builder reddens the metadata forcing function **while every pinned identity hash stays green** --
    which is the allowlist's failure direction, visible only to that test. (f) Adding one to the row
    builder reddens the row forcing function. Each of (e) and (f) names the offending field.
  - **What Task 21 will make hard to reach, kept anyway -- and the first version of this bullet had
    the scope wrong.** It said the refusal inspects top-level keys only, so an unplaceable field
    **inside a manifest row** would never trigger it, which made the row merge the live case.
    **Wrong**: R23.1 scopes the check to three documents and names manifest **entries** as one of them,
    so "top-level keys only" means *do not descend into a value* -- not *ignore entries*. Corrected
    2026-09-08 by the Task 21 cold-start audit, and swept in all four places it had reached.
    The accurate position: once the refusal lands, **all three** of the levels this task coded become
    unreachable through `datom_write()`'s door. Two things keep them earning their place, and the first
    is stronger than what the wrong version claimed: the **version-history entry** is not in R23.1's
    scope list at all, so its survival rests on nothing but this task's property -- which is why the
    test for it matters rather than being belt-and-braces; and `datom_validate(fix = TRUE)` reaches
    storage through `.datom_sync_data_metadata()` without passing that door.
  - **Three code citations elsewhere in this spec were ALREADY WRONG before this change**, found while
    re-deriving the ones this change shifted, and fixed: two lines cited as `datom_write()`'s return
    value and one cited as its in-pipeline manifest read all pointed at unrelated statements, as did
    the `meta$parquet_sha` citation in Task 19's body. Check 5 cannot see this class -- it asserts a
    cited line is not blank, nothing more -- so re-read citations by content after any insertion into
    `R/`. This is the third consecutive session to find some.

- [x] **21. Writer refusals: vocabulary check, floor read, unreachable-shape check, entry sequence** &nbsp; **[DONE 2026-09-09]**
  - **Vocabulary check** (R23.1): refuse a write when a datom-owned document carries a **top-level**
    key this build cannot classify. Evidence-based -- no version comparison, no config, no network.
    `custom` is **opaque** and classified as a whole.
  - **THREE SCOPES, THREE LISTS -- and Task 20 already built two of them.** R23.1's scope is three
    documents (per-artifact `metadata.json`, manifest **entries**, manifest **top level**), and
    "top-level keys only" means *do not descend into a value*, not *skip the entries*. So there are
    three vocabularies to check against, and as of 2026-09-08 the state is:
    | Scope | List | Status |
    |---|---|---|
    | per-artifact `metadata.json` | `.datom_metadata_known_fields()` (`R/forward-compat.R`) | exists -- the union of the identity list and the documented not-identity list |
    | a manifest **entry** | `.datom_manifest_entry_known_fields` (`R/forward-compat.R`) | exists -- eight names, with a test asserting every field a written row carries is on it |
    | the manifest's **top level** | none | **write it.** Five names today: `schema_version`, `project_name`, `artifacts`, `summary`, `updated_at` -- verified by grepping every top-level assignment (`R/sync.R:761-763`, `R/sync.R:1030-1031`, `R/manifest-upgrade.R:134`, `R/conn.R:523-524`) |
    Both existing lists are **append-only** and are read by the carry-forward rule as well, so the
    check and the carry-forward cannot disagree about what "unrecognised" means -- keep the new one on
    the same footing. **One decoy while grepping**: `datom_sync()` has a local data frame also called
    `manifest` and assigns `manifest$result` / `manifest$error` to it (`R/sync.R:560-561`); those are
    result columns, not manifest keys.
  - **Read the CLONE's copies, not storage** (R23.1a). This is the detail that makes the check
    possible at entry at all: the sequence has the manifest by then but **not** per-artifact
    metadata, which `datom_write()` does not touch until pipeline step 4 inside
    `.datom_has_changes()` (`R/read_write.R:341-349`, the storage read being the last of those lines).
    All three documents exist as local files
    (`{conn$path}/.datom/manifest.json`, `{conn$path}/{name}/metadata.json`), so this is a file read,
    it costs no round trip, and it works on the mirror-everything route where there is no single
    artifact name. **Do not implement the manifest half and skip the artifact half** -- that is the
    likely silent outcome if nothing is at hand, and it would remove the check from the one document
    that is never rebuildable and is where identity lives.
  - **The vocabulary list is append-only** (R23.2, I31). Never stop recognising a name that has ever
    existed, including names no longer written; retire by marking. A build that forgets a name refuses
    an **older** file and blocks the upgrade direction, which must always work. Give this the same
    weight as the frozen upgrade steps.
  - **Do not write directional logic** (R23.2a): a newer build's vocabulary is a superset of every
    older one's, so the check cannot fire on the upgrade path. A guard for it would be dead code
    guarding an unreachable state.
  - **Floor: the reading half only** (R23.3). One **optional** `project.yaml` field; absent means no
    floor, so no existing repo changes behaviour. It rides on the conn, since `datom_get_conn()`
    already parses that file. Compare and refuse at the write entry. One guard: whoever sets it must
    already satisfy it. **Deferred**: the purpose-built raising verb, tooling, docs.
    Ship the reading half now because it **cannot be retrofitted** -- a build that does not look for
    the field can never be bound by it, which is exactly why nothing can stop a 0.1.0 writer.
  - **Unreachable shape** (R23.4, I33): run the chain first; if the expected key is present
    afterwards, proceed; if still absent, refuse -- do **not** overwrite. Note the earlier phrasing
    ("refuse when the expected key is absent") would have **deadlocked the v1-to-v2 upgrade itself**.
  - **The entry sequence** (design 10.7): fetch, floor, read-and-check-then-chain, unreachable-shape,
    vocabulary, proceed -- all directly after the `datom_conn` class check and **above** the routing
    returns at `R/read_write.R:719` and `R/read_write.R:723`, because `.datom_sync_data_metadata()`
    mirrors the whole manifest to storage (`R/sync.R:212`) without reaching the manifest-writing step.
    All of it before any hashing, local write, or commit (I34).
  - **The double read is already decided, by Task 6**: the entry updater reads the same file again at
    pipeline step 6, and Task 6 accepted two reads of a small local file rather than threading the
    door's copy down. **The reason is not staleness on the table-write route** -- an earlier draft said
    the sync route pulls from the remote between the two, and on that route it does not: the pull is
    inside the push, after both reads. The reason is that the door runs before any hashing so a refusal
    leaves nothing half-written, and threading its document to the updater would carry state through
    every step in between, each of which must stay free to abort. Nothing left to decide there; keep
    it that way or say why.
  - **ON THE METADATA-ONLY ROUTE THE DOOR'S READ REALLY IS STALE, AND THIS SEQUENCE HAS TO ACCOUNT FOR
    IT.** `datom_write(conn, name = )` reaches `.datom_sync_metadata()`, which **pulls from the remote
    as its first act** (`R/utils-sha.R:559`) -- after the door has already read and checked the clone's
    manifest. So a collaborator's newer-format manifest can arrive in that pull, and the route carries
    on into a repo this build has just been told it understands. **Harmless in Task 6's shipping code**,
    because this route writes per-artifact metadata and never the manifest, so there is no way for it
    to leave a document half in each format. It stops being harmless here: step 1 of the entry sequence
    is a fetch, and if the checks at steps 2-5 run before a route's own pull, they are checking a state
    the route then replaces. Either the sequence owns the pull -- one fetch at step 1, no route pulling
    again afterwards -- or the checks that matter re-run after it. Decide which; do not leave both.
  - **THE ONE HOLE TASK 6'S PURITY AUDIT LEFT FOR THIS TASK, so it is not met by surprise.** The write
    door added by Task 6 inspects the **manifest** only. `.datom_sync_metadata()` (`R/utils-sha.R:549`)
    copies a per-artifact metadata document from the clone straight to storage, so a document pulled
    from a collaborator on a newer datom goes through unchecked. Pre-existing -- before Task 6 there was
    no write-side check at all, so that task narrowed the hole rather than opening it -- and this
    sequence is where it closes, because step 5 already reads all three documents at the door. Note
    this is the **same route** as the staleness item below: it pulls after the door has read, so
    whichever way that is settled has to cover this too.
  - **Say plainly that this binds 0.1.1 forward only** (R23.7). 0.1.0 has none of these checks and
    cannot be given them.
  - _Requirements: R23 (R23.1, R23.2, R23.2a, R23.3, R23.3a, R23.4, R23.5, R23.6, R23.7), R22.10.
    R23.1a. Invariants: I31, I32, I33, I34. Properties: P37. Acceptance: AC35, AC36, AC38 (a). Add a
    case asserting the check covers **per-artifact metadata**, not only the manifest -- an
    implementation that checks the manifest alone passes every other clause. **Pathway impact: yes**
    -- the write route gains an entry gate; update `dev/datom_pathways.md`._
  - **DONE 2026-09-09, in one commit.** The whole sequence is `.datom_check_write_entry(conn, artifact)`
    in `R/forward-compat.R`, called from `datom_write()` where the manifest-only door used to sit --
    directly after the `datom_conn` class check, above both routing returns, above any hashing or local
    write. Four steps in order: the floor (`.datom_check_writer_floor()`), the manifest through
    `.datom_read_manifest(conn, "clone", operation = "write")` which checks the format and then
    converts, the reachable-shape refusal, and the vocabulary check on the manifest's top level, on
    each artifact entry, and on each per-artifact `metadata.json` this write will touch. Tests 2905 ->
    **2959** (+54), FAIL 0 / WARN 0 / SKIP 0; `dev/check-spec.R` 9/9; `R CMD check` docs and
    code/documentation agreement 0/0/0. Four `man/` pages added, one deleted, two updated; no new
    export, NAMESPACE and `_pkgdown.yml` untouched. **Pathway impact recorded**: a new route card,
    "Given a write request, decide whether this build may write here", and the schema card's write-side
    paragraph now points at it instead of describing a door that no longer exists.
    - **`.datom_check_write_schema()` IS GONE, absorbed rather than kept beside the new sequence.** It
      read the clone's manifest itself and checked nothing else. Keeping it would have meant two doors
      reading the same file at the same moment with no way to say which ran first, and the order is
      load-bearing: the floor is a policy refusal that should fire before anything about format is
      considered, and the format check has to run before the conversion because there is no conversion
      step for a version this build has never heard of. Its three tests now drive
      `.datom_check_write_entry()`.
    - **`.datom_read_manifest()` gained an `operation` argument** and nothing else, so the entry
      sequence reads the manifest through the one shared reader as R23.1a requires rather than reading
      it a second way. Without it the refusal would have said the format was one this build "cannot
      read", on a write it had just stopped.
    - **THE FETCH -- step 1 of design 10.7 -- IS DELIBERATELY NOT IMPLEMENTED, and this is the one
      deviation in the task.** A fetch updates remote-tracking refs and **not the working tree**, so it
      cannot make any of steps 2-5 read a fresher document; the only thing that would is the
      behind-comparison in `.datom_check_git_current()`, which **aborts**. Adding that abort to
      `datom_write()` would newly refuse an offline write that works today, and would make the
      mirror-everything route -- which touches no git at all -- depend on `git2r`, a **Suggests**
      package. Cost of leaving it out: none of the four checks is any less correct, because each reads
      a file the route is about to write. What is left uncovered is the narrow race in the other
      bullet below, which is covered there instead. Reversible in one line if the abort is wanted.
    - **THE STALENESS QUESTION IS ANSWERED BY RE-CHECKING, NOT BY OWNING THE PULL.** The task named two
      options and said to pick one. `.datom_sync_metadata()` pulls from the remote as its first act,
      after the door has read the clone, so a collaborator's newer manifest or metadata document can
      arrive in that pull. That route now calls `.datom_check_write_entry(conn, name)` again
      immediately after the pull, against what the pull left on disk. The rejected option was for the
      sequence to own the freshness -- one fetch at the door and no route pulling afterwards -- which
      fails on its own terms twice: a fetch does not refresh the working tree, and dropping that
      route's pull would leave its commit on a stale base. Re-running is free: every step is a local
      file read and none of them mutates anything, which is why the function is documented as callable
      more than once. Pinned by a test that mocks the pull into planting an unfamiliar field and
      asserts the write is refused naming it.
    - **THE HOLE TASK 6's PURITY AUDIT HANDED FORWARD IS CLOSED.** `.datom_sync_metadata()` copies a
      per-artifact metadata document from the clone straight to storage, and nothing checked its
      declared format. Step 4 of the sequence now runs `.datom_check_schema_version()` on each
      per-artifact document as well as the vocabulary check, so a document pulled from a collaborator
      on a newer datom is refused. Same route as the staleness item above, and the re-check after the
      pull is what makes the closure hold there.
    - **THREE SCOPES, THREE LISTS -- the third one shipped here.** `.datom_manifest_known_fields` holds
      six names: the five a manifest carries plus **`tables`, marked retired**. That is the append-only
      rule made mechanical rather than remembered, and it is what AC35(c) asserts: a build that pruned
      the old name would meet an **older** document, fail to place a key it should know, and refuse
      it -- blocking the upgrade direction. In practice the conversion renames the key before the check
      sees it, so the entry earns its place as the worked example and as insurance if the check is ever
      consulted on an unconverted document. Its forcing function writes a real artifact and asserts
      every top-level field of the resulting manifest is classified.
    - **The vocabulary check runs on the CONVERTED manifest, never the raw one**, and getting this
      backwards is how the forward path deadlocks: a pre-rename document's list is under `tables`, so a
      check on the raw document would refuse every existing repo -- turning R23.4's first row into a
      refusal by a different mechanism than the one R23.4 warns about. AC35(d)'s test asserts a v1-shaped
      clone manifest writes normally, and asserts the pre-state so it cannot pass by the fixture edit
      silently not having taken.
    - **`artifact = NULL` means every artifact in the clone**, which is the mirror-everything route --
      the one with no artifact name in its arguments. Enumeration goes through the new
      `.datom_clone_artifact_names()` in `R/sync.R`, factored out of `.datom_sync_data_metadata()`,
      which now calls it too. One helper rather than two spellings, because the door has to inspect
      exactly the set the route writes; discovering it twice is how those two drift apart.
    - **The floor rides on the conn** (`conn$min_writer_version`, read from `project.yaml` in
      `.datom_get_conn_developer()`) as R23.3a specifies. A value that will not parse as a version
      **aborts** rather than being treated as no floor: reading a typo in a policy field as an absent
      policy field is the failure the mechanism exists to prevent, arriving through the mechanism.
      **AC36(c) is not implemented and is not owed here** -- "setting a floor above the setting build's
      own version is refused" is a guard on the *setter*, and R23.3 defers the setter. There is no code
      path in this build that sets the field, so the clause has nothing to bind to; it ships with the
      raising verb, which the `dev/README.md` Backlog row already owns.
    - **A consequence worth stating plainly: the refusal makes all three of Task 20's coded levels
      unreachable through `datom_write()`.** Expected, and the four round-trip tests that drove them
      through the real write path now hold the door open with a mock on the vocabulary check, named and
      explained at the fixture. What stays genuinely live is the **version-history entry**, which R23.1
      does not scope, so the test written for it in Task 20's review round is the load-bearing one. The
      merge is kept and kept tested for one forward-looking reason: the day a release widens what the
      door accepts, the merge behind it has to already work, and a merge that quietly broke while
      unreachable would ship as a silent field deletion on the first write that got through.
    - **EVERY NEW GUARD WAS PROVEN TO FAIL BEFORE BEING TRUSTED**, seven probes, each reverted and each
      naming the tests it reddened. Disabling the vocabulary check reddens **6** tests; the floor **3**;
      the reachable-shape refusal **1**; emptying the per-artifact loop **5**, which is the clause an
      implementation checking only the manifest would fail; pruning `tables` from the manifest
      vocabulary **1**, the retired-name arm; dropping the per-artifact schema check **1**, the hole
      Task 6 left; and disabling the re-check after the pull **1**. The last three would each have
      shipped green without their probe.
    - **THREE REVIEW FINDINGS, all verified against the code before acceptance; two fixed in a
      follow-up commit, one recorded.** Two of them are the same route arriving for the third task
      running, which is itself the finding worth carrying: `datom_validate(fix = TRUE)` reaches storage
      by calling `.datom_sync_data_metadata()` **directly** (`R/validate.R:183`), so it does not pass
      `datom_write()`'s door at all.
      1. **The repair path bypassed the whole sequence.** No floor, no vocabulary, no per-artifact
         format check -- and the NEWS entry claimed the checks run on every write route, which was
         false. Damage was bounded, because that route copies documents rather than rebuilding them,
         so nothing was being deleted. It still mattered for the floor, whose stated purpose includes
         a block for a reason that is **not about format**, and those cannot be enumerated ahead of
         time -- so "this route only copies" is not an argument that the floor may be skipped there.
         **Fixed by putting the entry on the function rather than on each caller**, directly after its
         role and path guards. The `datom_write()` route now runs it twice, which costs nothing (local
         reads, no mutation, and the function is documented as callable more than once) and means the
         next caller cannot forget. Probed: removing it reddens two tests.
      2. **The same route read the manifest with the wrong verb.** `R/sync.R` used the shared reader's
         default `operation = "read"`, so a too-new manifest met on the way to storage would report a
         format this build "cannot read" -- during a write. Fixed with one argument. **Unreachable in
         practice once finding 1 is fixed**, since the entry refuses first, so the test has to mock the
         entry out to reach it; without that mock the assertion passed whatever the read said, which
         the probe caught. Kept anyway on the rule this spec applies everywhere: a message that is
         correct only because something upstream refused first starts lying the day the refusal moves.
      3. **The staleness fix covers one of the two pulling routes -- ACCEPTED RESIDUAL, not fixed.**
         The table-write route also pulls, inside `.datom_git_push(pull_first = TRUE)` at step 7
         (`R/read_write.R:849`), which is **after** step 6 has already written the metadata document and
         edited the manifest. So the door's answer can be stale there too, and re-checking cannot help:
         the write is already built by then. Left as it is, deliberately, because the backstop is real
         and design 10.7 already argues for it -- the push aborts on rejection or on a merge conflict,
         and the storage steps are 8-10, so a write cannot land on storage from a base this build has
         not seen. Recorded because the Task 21 summary said the staleness problem was "solved", which
         is true of the metadata-only route and overclaims for this one.
    - **Live code citations re-derived by content**, in all three spec files, after this change shifted
      lines in five `R/` files: the two routing returns, the mirror route's manifest read, the entry
      updater, `datom_sync_manifest()`'s read and its artifact lookup, `.datom_has_changes()`'s storage
      read, and the local metadata write's `git_paths`. Dated Decisions rows were left frozen per the
      2026-08-23 policy. Check 5 sees none of this class -- it asserts only that a cited line is not
      blank.

- [x] **22. Self-healing manifest rebuild (#101) + persist `original_format`** &nbsp; **[DONE 2026-09-10]**
  - Rebuild when the expected artifact key is **absent**, or when the declared version is **above**
    what this build supports (R22.11, R22.12). **Never on empty** -- empty is what a new repo and a
    truncated file both look like, so rebuilding on empty costs a listing per call on healthy repos
    and hides corruption.
  - **Reader warns and rebuilds; writer refuses** (R22.11). Same condition, opposite responses. A
    storage-only reader rebuilds **in memory for that session** and writes nothing. Warn **once**,
    pointing at the upgrade -- a silent repair is a silent degradation.
  - **The rebuild reads the recorded `version`** from `version_history.json` (`R/read_write.R:501`) and
    **never** recomputes it. Recomputing walks into the denylist defect in precisely the scenario the
    rebuild exists for, and would publish a `current_version` matching no version in the history --
    worse than the empty list it replaced. (Task 19 removes that defect, but the rebuild must not
    depend on having been run by a build that has the fix.)
  - **Persist `original_format` into per-artifact metadata.** It is written into the manifest entry
    (`R/sync.R:1060`) and never into metadata, so it is the one manifest field a rebuild cannot recover.
    Additive, and free now that Task 19 has landed -- **which is why it is sequenced here and not
    earlier**.
  - **Guard the dispatcher loop and test the no-op** (R22.10): R's `seq()` counts **down** when
    `from > to`, so guard with `if (declared < supported)` and assert a current-version document runs
    **zero** steps. **Already done by Task 6 -- see the audit below; do not rewrite it.**
  - **This task AMENDS THE TESTS Task 5 wrote**, though not the criterion they test. Task 5 shipped
    "a too-new manifest aborts at all five readers"; from here the manifest **reader** warns and
    rebuilds while the **writer** refuses, and per-artifact metadata still aborts at any role. AC32
    and P35 are worded to hold on both sides of that change, so nothing in the spec needs restating --
    but the assertions do, and leaving them would leave the suite asserting the opposite of the design,
    which is the one place this spec's recurring swept-some-places defect must not reach. **It is three
    files and eight assertions, not one file -- enumerated in the audit below.**
  - **COLD-START AUDIT, 2026-09-09** -- the documented path (`dev/README.md` -> the state block ->
    this task -> `dev/engineering-notes.md`) was walked as a fresh reader and every claim in this task
    checked against the tree. **Startable, after the eight items below.** Two of this task's own code
    citations had drifted and are repointed above (`R/read_write.R:501` -> `493`, `R/sync.R:1002` ->
    `1060`); the "never into metadata" claim **verifies** -- nothing in `R/` writes a top-level
    `original_format` onto a metadata document.
    1. **THE TEST SURFACE IS THREE FILES AND EIGHT ASSERTIONS.** This task's body said "the assertion
       in `test-query.R`", which undercounts by enough to leave the suite asserting the opposite of the
       design. Every assertion on the `datom_schema_unsupported` class was enumerated. **These must
       flip to warn-and-rebuild**: `datom_list refuses a manifest declaring a newer schema`
       (`tests/testthat/test-query.R:903`), `datom_status aborts on a newer schema rather than
       reporting it` (`tests/testthat/test-query.R:961`), `datom_status refuses a local clone declaring
       a newer schema` (`tests/testthat/test-query.R:996`, which is the input-file scan's clone read
       reached through `datom_status()`), `datom_summary refuses a manifest declaring a newer schema`
       (`tests/testthat/test-summary.R:157`), `datom_sync_manifest refuses a local manifest declaring a
       newer schema` (`tests/testthat/test-sync.R:1266`), and **the load-bearing one** --
       `.datom_read_manifest throws a too-new document rather than returning it`
       (`tests/testthat/test-sync.R:1453`), which is the shared reader's own returned-versus-thrown
       contract, plus its two `names the copy it refused` assertions
       (`tests/testthat/test-sync.R:1540`, `tests/testthat/test-sync.R:1574`). **These must NOT be
       touched**: the per-artifact read path (`tests/testthat/test-read-write.R:182`), the three write
       routes (`tests/testthat/test-read-write.R:2596`, `2610`, `2631`), the two write-entry tests
       (`tests/testthat/test-forward-compat.R:713`, `891`), and the two unit tests of the check itself
       (`tests/testthat/test-utils-validate.R:360`, `400`). All five readers do have coverage today, so
       none has to be written from scratch.
    2. **TASK 21 ALREADY SHIPPED THE WRITER HALF OF R22.11. Do not build it twice.** A writer meeting a
       too-new manifest is already refused at the write entry (`datom_schema_unsupported`, with
       `operation = "write"` in the message), and a writer meeting an **absent** artifact list after the
       chain is already refused (`datom_shape_unreachable`). Both of R22.12's triggers therefore already
       produce the writer's response. **What is left of R22.11 is the reader half**, plus
       `original_format`.
    3. **TASK 21 ALSO SUPPLIED THE DISCRIMINATOR, by accident, and it removes the hard part.**
       "Reader warns and rebuilds, writer refuses" needs the shared reader to know which it is serving,
       and until Task 21 it could not: `.datom_read_manifest()` took only a scope. It now takes
       `operation`, added for a message-wording reason, and **every writer call site already passes
       `"write"`** -- verified: the write entry and the mirror route both do, and the entry updater
       calls `.datom_check_schema_version()` directly with `"write"`. So the branch is
       `operation == "read"` -> warn and rebuild, `"write"` -> throw, with no new plumbing and no
       role inspection.
    4. **R22.10 IS ALREADY IMPLEMENTED AND AC38(b) AND (c) ARE ALREADY TESTED**, both by Task 6. The
       guard is `if (declared >= .datom_supported_schema) return(manifest)` in
       `.datom_manifest_upgrade()`, and the tests are `the dispatcher runs zero steps on a
       current-version document` (`tests/testthat/test-manifest-upgrade.R:92`) and `applying the
       dispatcher twice equals applying it once` (`tests/testthat/test-manifest-upgrade.R:114`). The
       first one **counts** step invocations through a mocked step table rather than comparing output,
       which is what makes it real. Nothing to add; re-deriving them would waste the chunk.
    5. **THERE IS NO STORAGE-SIDE ARTIFACT ENUMERATOR TO REUSE, and a Task 6 audit row says
       otherwise -- that row is WRONG.** It claimed `.datom_validate_tables()` "enumerates artifacts
       from a storage listing". It does not: it enumerates from the **clone**
       (`fs::dir_ls(repo_path, type = "directory")`, `R/validate.R:386`) and then checks storage per
       name. That matters because a storage-only reader has no clone, and the rebuild exists precisely
       for that reader. What does exist is the primitive `.datom_storage_list_objects(conn, prefix)`
       (`R/utils-storage.R:126`), recursive, both backends; artifact names come from keys shaped
       `{name}/.metadata/metadata.json`. **It returns FULL keys** -- including the `{prefix}/datom/`
       portion -- which is the two-key-shapes trap in `dev/engineering-notes.md`, so strip before
       matching. Cost of a rebuild is one listing plus two reads per artifact; budget for that when
       deciding what AC37(c) is protecting.
    6. **A REBUILT ENTRY MUST STAMP `kind`, OR EVERY COUNTER READS ZERO.** `kind` is not in
       per-artifact metadata until Task 7, and this task runs before it, so the rebuild cannot recover
       the field from the document -- it must write `kind = "table"`. That is correct today because
       nothing writes a set until Task 9, and it is **not** optional: R22.8 deliberately gives the
       counters no missing-`kind` fallback, so an untyped rebuilt entry is silently uncounted by
       `.datom_artifacts_of_kind()` and a rebuilt repo reports zero artifacts while listing them. Task 7
       and Task 9 must revisit this line; a comment at the site should say so.
    7. **`original_format`'s CLASSIFICATION IS A DECISION WITH A CONSEQUENCE, not a formality.**
       `original_file_sha` is already **in** the identity list (`R/utils-sha.R:422-425`), so the
       symmetric-looking choice for its sibling is identity too -- and that would re-mint a version for
       **every imported table in every repo**, on content that did not move. Classifying it excluded
       costs nothing and keeps this task's own claim ("additive, and free") true. State the choice and
       its reason rather than letting the classification test's red be settled by whichever list is
       typed first.
    8. **AC37(c)'s EMPTY-REPO FIXTURE MUST BE CURRENT-SHAPED.** The clause is that a genuinely empty
       repo triggers no rebuild and performs **no storage listing**. A current-shape empty manifest
       carries `artifacts` present-and-empty, so the absent-key trigger does not fire -- that is the
       fixture the test needs. An **empty v1** manifest is a different state: the conversion leaves no
       artifact key at all (deliberately, per the v1 step's own docs), so it *does* trigger a rebuild.
       Both behaviours are correct under R22.12, but a v1 fixture here fails the test for the right
       reason with a misleading diagnosis.
  - _Requirements: R22.11, R22.12, R22.10, R22.4 (the Design A qualification), R9.5 (per-file rule).
    Invariants: I32. Properties: P34, P36, P35, P11. Acceptance: AC37 (all six clauses), AC38 (b and
    c), and AC32 **still holding** after the behaviour change -- assert the new outcome is not reported
    as an unreadable manifest either. **Pathway impact: yes** -- the
    manifest read route gains a reconstruction branch; update `dev/datom_pathways.md`._
  - **DONE 2026-09-10.** tests: **3050** (+85). New file `R/manifest-rebuild.R`; the branch lands in
    `.datom_read_manifest()` at the point Task 6 left for it. `dev/datom_pathways.md` gains a card of
    its own ("Given a manifest whose artifact list this build cannot reach, still list the repo") and
    the schema card gains the one exception plus a fifth step. New test file
    `tests/testthat/test-manifest-rebuild.R`, plus two shared fixtures in `helper-mock.R`
    (`mock_stored_artifact()`, `mock_rebuildable_store()`) so a test can hand a reader a manifest it
    must reconstruct and still get a correct answer back.
  - **Eight assertions in three files were flipped, as the audit above enumerated**, and every one of
    them **passed unchanged after the code change for the wrong reason** -- the mock storage had no
    listing, so the rebuild failed and the original refusal was re-signalled. That is exactly the
    "suite asserting the opposite of the design" failure this task was warned about, and it would have
    survived a green run. Each flipped test now says AMENDED at the top and states what did *not*
    change, since the reason those assertions existed still holds: the outcome must be its own, never
    reworded into "could not read manifest".
  - **The writer's half was not rebuilt** (audit item 2) and R22.10 was not re-derived (audit item 4).
    What Task 21 shipped is reused as-is; two new tests assert the refusal still fires for a writer on
    the same document a reader rebuilds, so the asymmetry is pinned in the one function that decides
    it rather than inferred from two files.
  - **Three decisions this task took, each with the consequence rather than the principle.**
    (1) **`original_format` is classified NOT identity.** Its sibling `original_file_sha` *is*
    identity, so the symmetric choice looks right and is wrong: it would re-mint a version for every
    imported table in every repo, on content that did not move. (2) **`kind = "table"` is hardcoded on
    a rebuilt row**, with a comment naming Task 7 and Task 9 as the owners of that line -- an untyped
    row is uncounted, so a rebuilt repo would list its artifacts while reporting zero of them.
    (3) **A rebuild persists nothing, at any role.** Design 10.4 only requires in-memory for a
    storage-only reader; writing the clone's copy from a read was available for a developer and was
    not taken, because a read that quietly rewrote a repo's index is a larger surprise than the one it
    is fixing. The recorded copy is repaired by the next ordinary write.
  - **One thing the requirement does not name, decided here: which recorded version is the current
    one.** "Read the `version` from `version_history.json`" reads as "take the newest entry", and that
    is wrong in a case that already exists -- a write reverting to content already in the history
    appends **no** entry, so the current state is an older row and the newest one describes different
    content. Selection narrows by `data_sha`, then by the `created_at` the history entry copies
    verbatim (`.datom_recorded_current_version()`, three unit tests). Nothing is recomputed in any
    branch, and a history that records nothing usable yields a row with **no** version rather than a
    manufactured one.
  - **AC37(f) has one documented exception: `last_updated`.** The writer stamps the wall clock at the
    moment it rewrites a row and that moment is in no document, so the rebuild uses the version's own
    `created_at`. The test asserts every other field equal and this one present and plausible, and
    says so at the assertion -- so it reads as a decision rather than as a gap to be "fixed" by
    inventing a timestamp.
  - **Two R-level traps cost most of the debugging and are now in `dev/engineering-notes.md`**
    ("Two ways a condition's class silently disappears on its way to a handler"). Both matter here
    because the whole fork is decided *by* a condition's class: `stop(cnd)` inside one `tryCatch()`
    handler is caught by that same `tryCatch()`'s `error` handler, and `purrr::map()` re-signals a
    mapped function's condition as its own indexed error with the original demoted to a parent. The
    first turned every compatibility refusal into an IO failure; the second is why the artifact loop
    in `R/manifest-rebuild.R` is `lapply()` and must stay `lapply()`.
  - **Every guard was verified by breaking it on purpose**, per this spec's standing rule that a green
    run is not evidence. Dropping the namespace-root strip reddens the rebuild file past testthat's
    failure cap; triggering on *empty* instead of *absent* reddens 9; removing `kind = "table"`
    reddens 9 across three files; recomputing `current_version` reddens 1.
  - **The empty-v1 distinction from audit item 8 is now mechanical, not a comment.** A current-shape
    empty manifest carries its artifact list present-and-empty and triggers nothing; an empty **v1**
    manifest comes out of the conversion with no artifact key and does trigger. Both are correct under
    the same rule, and the two tests sit next to each other so the pair reads as one statement.
  - **REVIEWED after it landed; three findings, two fixed and one recorded (tests -> 3053).**
    (1) The hardcoded `kind = "table"` was guarded by a comment. It now has a forcing function in the
    rebuild's own test file, asserting the metadata builder emits **no** `kind`, so the day Task 7 adds
    the field the failure lands next to the line that has to change. Something did already redden --
    `test-utils-sha.R`'s pinned fixture list -- but in a test about identity hashing that says nothing
    about the rebuild, so the revisit still depended on memory. (2) `.datom_recorded_current_version()`
    fell back to the newest history entry when **nothing** matched the current content, contradicting
    the test two lines away that pins "no version beats a manufactured one". It now returns nothing;
    the remaining ambiguous case still takes the newest **candidate**, which is different in kind
    because both candidates describe the current content. (3) Recorded rather than fixed: nothing
    memoises the rebuild, so it repeats per call while the repo stays broken -- see the Decisions row
    and the note now in the `R/manifest-rebuild.R` file header. Both fixes were probed by reversion.

- [ ] **23. `project.yaml` declares its format** &nbsp; **[EXECUTES IMMEDIATELY BEFORE TASK 11 -- see the scheduling bullet]**
  - **The gap.** `project.yaml` carries fields a writer must **obey**, and has no way to say "this repo
    needs a newer datom". A build that does not recognise such a field walks past it and acts as
    though the repo had not asked for anything. `min_writer_version` is already in that position
    today: a build older than Task 21 does not read it, so a repo that raises the floor is not
    protected against exactly the builds the floor exists to stop. Task 11 adds `mode: product` and
    `set: {name}` to the same file, which is the second instance of the same shape and the reason this
    is worth doing now rather than later.
  - **Reading half -- CANNOT BE RETROFITTED.** `.datom_get_conn_developer()` parses the file at
    `R/conn.R:937`. One call to the existing `.datom_check_schema_version()` after it, with `cfg` and
    the yaml path. Absent already means v1, so no existing repo changes behaviour. **Reader-role
    connections never see this file** (a reader has no clone), which is the right scope -- the harm is
    a *write* into a repo whose policy this build cannot read -- but say so, because "one gate covers
    every role" would be wrong.
  - **THERE IS A SECOND READ SITE, AND ONE GATE DOES NOT COVER IT.** Verified, not assumed:
    `.datom_resolve_data_location()` re-reads `project.yaml` **after a git pull** (`R/ref.R:327`), and
    it is called from `R/conn.R:1030` -- *after* the parse at 937. So a config arriving in that pull is
    never checked. The same parse is also what `conn$min_writer_version` is read from
    (`R/conn.R:1081`), so a pulled floor raise is missed in that session too -- pre-existing, and named
    here rather than left to be found later. Either gate the post-pull re-read as well, or record the
    residual explicitly the way the table-write pull staleness was recorded. Do not leave it
    unmentioned.
  - **Writing half -- retrofittable at any time.** Stamp the field in `datom_init_repo()`'s config
    block (`R/conn.R:509-521`, beside the existing `datom_version`). Increment it by R9.5's table like
    any other document, which means **Task 11's addition of `mode` does not move it** unless that task
    argues otherwise.
  - **DO NOT extend the vocabulary check to this file.** It was the first idea and it is the wrong
    tool. That check's power comes from the document being machine-written: an unrecognised key there
    **is** evidence a newer datom wrote it. `project.yaml` is hand-edited -- storage migrations,
    prefixes, descriptions, and whatever else a team keeps there -- so an unrecognised key is as likely
    a typo or a private note, and a refusal would block every write in the repo until somebody found
    it. R9.8 carries the general rule as a table, and AC39(d) is a test that a stray key is still
    tolerated, which is what stops the extension being made later as a tidy-up.
  - **SCHEDULING, and it is the whole reason this is a task rather than a note.** The reading half must
    ship **no later than** the release that starts writing `mode`. Order inside one release does not
    matter, so the constraint is only visible if datom-sets is ever split across releases with Task 11
    in the earlier one. Rather than leave that as something to remember at release time, this task
    **executes immediately before Task 11** and Task 11 states the dependency. That makes the
    guarantee structural.
  - **Correcting three things said while proposing this, so they are not inherited as fact.**
    (1) `project.yaml` is **not** the only datom-owned document without a format number --
    `version_history.json`, `governance.json`, `ref.json` and `dispatch.json` have none either.
    Verified: only the manifest and per-artifact metadata carry one. It is the only **hand-edited**
    one, and the only one carrying writer policy, which is the argument that actually supports a
    number here. (2) The harm is **not** "running `datom_sync()` on a set". Task 11's own body says
    today's behaviour on a product repo is a silent no-op, and that is what an older build gets -- an
    unhelpful answer, not a corrupting one. (3) Once a repo actually contains a set, an older
    **writer** is already stopped by Task 21's vocabulary check, because Task 7 adds `kind` to
    per-artifact metadata. Per R9.5 that addition does **not** bump any number, so the number would
    never have caught it -- the vocabulary check does. **So the window this task protects is narrower
    than it first looks: a product repo that does not yet hold a set** -- which is precisely the state
    a repo is in immediately after init, and the state in which somebody reaches for `datom_sync()`.
  - _Requirements: R9.8, R9.4 (why not `datom_version`), R9.5 (the bump rule), R10.2 (the fields that
    make it matter), R23.1 (the mechanism this deliberately does not use). Acceptance: AC39 (all four
    clauses), with (d) as the one a later tidy-up would break. **Pathway impact: yes** -- the
    "decide whether this build can read it" card gains `project.yaml` as a third document, with its
    own row in that card's "where it is called" list._

---

## New exports introduced by this spec

Track so `_pkgdown.yml` and NAMESPACE stay complete:

| Export | Task |
|---|---|
| `datom_storage_read_json()` | 3 -- **shipped 2026-08-21** |
| ~~`datom_storage_write_json()`~~ | **dropped 2026-08-18** -- deferred to the Backlog; see Task 3 |
| `datom_member()` | 8 |
| `datom_write_set()` | 9 (extended with `include_paths` in 13) |
| `datom_read_set()` | 10 |
| `datom_repo_commit()` | 12 |
| `datom_repo_push()` | 12 |

Task numbers here are **bare**, so the 2026-08-23 renumber did not touch them mechanically and they
were corrected by hand. Check 8 cannot see them either -- it only reads numbers written as
`Task N`. If this table is ever renumbered again, re-derive it from the task headings rather than
trusting the column.

---

## Decisions log

Record decisions as they are made, so a fresh session does not relitigate them.

| Date | Decision | Where |
|---|---|---|
| 2026-08-09 | Branched from `dev`, not `main`. `dev/README.md` "Branching During CRAN Submission" governs while 0.1.0 is in review; the `from main` wording in copilot-instructions item 0b is the no-freeze default. | requirements.md header |
| 2026-08-09 | #89's "keys go through `.datom_build_storage_key()`" cannot be followed literally -- that function returns a **full** key while `.datom_storage_*()` takes **relative** keys. Honor the intent with relative-key helpers instead. | design.md Deviation D1 |
| 2026-08-09 | `datom_member()` deliberately does **not** carry `data_sha` (unlike `datom_parent()`). `data_sha` exists on parents to support cross-project lineage resolution, which sets explicitly do not do. | design.md section 5 |
| 2026-08-09 | Missing `document_sha` on a set read is an **error**, not a skip. The `parquet_sha` skip branch is a pre-cv1 migration grace; sets have no legacy population. | design.md section 8 |
| 2026-08-09 | `metadata_sha`'s own emitter-drift exposure is filed as a separate issue, not folded into this spec. | design.md section 16, Task 1 |
| 2026-08-09 | **Independent spec review.** All 12 findings verified against the code and accepted; none rejected. Full audit trail with per-finding verification method and resolution. | design.md section 18 |
| 2026-08-09 | ~~**(F1)** Write-time cycle detection is exhaustive within a project only; read-side visited-set + depth guarding is a requirement.~~ **SUPERSEDED 2026-08-11 -- see the entry below.** The premise was false. | design.md 20.11 |
| 2026-08-09 | **(F2)** `datom-sv1` hashes the **parsed-JSON** data model, not the in-memory R object. Reproduced on the branch: `NA_real_` -> string `"NA"`, doubles -> integers, `NA_character_` -> `null`. A type-tagged encoder over the in-memory object would disagree with itself across the round trip. Elevated from open question to hard constraint. **Mechanism superseded 2026-08-15 by Q5** -- the original `serialize -> parse -> encode` normalization is replaced by eliminating each mutation at source; the constraint itself stands unchanged. | R2.5, design.md 7.1/7.3 |
| 2026-08-09 | **(F2/Q5)** Which serializer defines sv1's canonical form -- `jsonlite` vs an sv1-owned minimal emitter -- is now the load-bearing open question, because the round-trip constraint forces the choice into the open. Coupled to the section 16 issue. | design.md section 7 Q5, E1 |
| 2026-08-09 | **(F3)** The public `datom_storage_write_json()` refuses datom-managed keys (`.metadata/` segments, payload-shaped keys under existing artifacts). Reads unrestricted. Public-contract decision settled in the spec. | R12.4a, I14 |
| 2026-08-09 | **(F4)** A set's metadata is **exactly** R1.3's seven fields. `size_bytes` dropped (no consumer), `custom` dropped (payload already owns user metadata, R6.2) -- so `datom_write_set()` has no `metadata =` parameter. | R1.4, design.md section 4 |
| 2026-08-09 | **(F5)** `datom_write_set()` requires `mode: product` **and** a name matching `project.yaml`'s `set:`, both checked before any hashing or IO. This is what makes "one repo = one set" enforced rather than aspirational. | R10.3a, I15 |
| 2026-08-09 | ~~**(F7)** Set payloads live in git at `{name}/{data_sha}.json` and all historical payloads are retained.~~ **SUPERSEDED 2026-08-11 -- see the stable-path entry below.** Git now holds one mutable `{name}/set.json`; only storage is content-addressed, and the retention rule is redundant. What still holds from F7: the `governance.json` *ordering* transfers but its singleton *layout* does not, and P17 survives via `git show <commit>:{name}/set.json`. | R6.1a/b, P17 |
| 2026-08-09 | **(F12)** The stale "task 5.1" text is at `R/read_write.R:110-113, 205-206, 413`, with `393` already correct and therefore contradicting. #89's `95-97` citation was wrong and the first spec draft propagated it. | R13.3, Task 1 |
| 2026-08-11 | **Spec delta D1-D8 applied** from #89. **The `mode: product` repo IS the joint repo** (data + code + `renv.lock`); no separate fourth repo. Decisive reason: cross-repo pinning is circular -- the code repo wants to record which set version it produced and the set payload wants to record which code commit produced it, so one is always stale by one commit. A joint version requires one commit graph. | design.md section 19, R14 |
| 2026-08-11 | **datom is the single git-mutating actor** (I17). Downstream packages never import `git2r`; all stage/commit/push/pull goes through a datom export. Writing files on disk is *not* a git operation and needs no datom API -- hence **no `datom_gitignore_*` API**, ever. | I17, R16, design.md 19.5 |
| 2026-08-11 | **Machine vs human commit moments is the load-bearing distinction.** `dpbuild`'s add-all was safe only because every commit was human-invoked. datom commits at machine-chosen moments, so add-all there would snapshot arbitrary WIP human code. Machine moments stage datom paths only (R14.1); human moments get add-all via `datom_repo_commit(paths = NULL)` (R15.1). | design.md 19.4 |
| 2026-08-11 | `include_paths` (R12.5) is the **only** way a machine-moment commit may carry a non-datom path, and only because the caller enumerated it. Never add-all. | R14.3, I16 |
| 2026-08-11 | An idempotent set re-write stays a no-op **even with dirty `include_paths`** (I19). AC2 must not acquire a side channel that commits code -- that would be the add-all failure through a different door. Caller is directed to `datom_repo_commit()`. | R12.5, AC19 |
| 2026-08-11 | **(delta correction C1)** `.datom_git_commit()` does **not** abort on empty staging -- it returns HEAD's SHA. It aborts on an empty `files` **argument** and on nonexistent files. So `datom_repo_commit(paths = NULL)` cannot delegate with `files = character(0)`, and must determine "nothing to do" itself to honor the `invisible(NULL)` no-op contract. | design.md 19.6, R15.5, Task 12 |
| 2026-08-11 | **(delta correction C2)** The on-a-branch guard lives in `.datom_git_branch()`, reached only via `.datom_git_push()`, so it does not fire when `push = FALSE`. Assert it explicitly. | design.md 19.6, R15.7, Task 12 |
| 2026-08-11 | `datom_repo_commit(paths = NULL)` may sweep in dirty datom files left by a failed write. **Deliberately not special-cased**: it moves git ahead of storage (the safe direction), `datom_validate(fix = TRUE)` is the existing repair path, and excluding them would make the function lie about `git add .` semantics. | design.md 19.7 |
| 2026-08-11 | Tasks renumbered: two tasks inserted after 10 (foreign-content discipline + `datom_repo_commit()`; `include_paths`). Old 11/12/13 -> 13/14/15. | tasks.md Phase D |
| 2026-08-11 | **(F13)** Push decoupling had only one half -- `push = FALSE` with no way to push later. **Both proposed fixes adopted**, because they solve different problems. Add **`datom_repo_push()`** (R15.8): routing push intent through `commit()` would force a push-only caller through the `paths = NULL` add-all path, which in a product repo commits whatever human WIP it finds -- the R14 hazard through a third door -- and would leave `message` a silently-ignored required argument. **And** make push **convergent** (R15.5 qualified, R15.8): a no-op means no *commit*, not no push, because otherwise one failed push leaves the remote silently behind forever as every later call returns early on a clean tree. | design.md 19.8, I20, P23, P24 |
| 2026-08-11 | Supporting the export over the wrapper-only fix: datom **already exports standalone `datom_pull()`** (`R/sync.R:45`) with no push counterpart, and the `datom_repo_*` family already exists -- so this closes an asymmetry rather than inventing a shape. Cost is one thin wrapper plus one array index: `.datom_check_git_current()` already calls `git2r::ahead_behind()` and reads `[[2]]`; `[[1]]` is the ahead count. | design.md 19.8, R15.9 |
| 2026-08-11 | **(F14)** AC20 stays one criterion but is **tested as two cases** (nonexistent path; datom-owned overlap), so a regression identifies which gate broke. | AC20, Task 13 |
| 2026-08-11 | **Artifact topology settled**: one repo = one namespace (`{root}/{prefix}/datom/`) = one manifest, 1:1:1. A set lands in the **product repo's** namespace, never with onboarded source data. Two manifests with the same schema, zero shared files. Matches the documented house convention (`buckets-and-prefixes.Rmd`: "prefix per product"). | R17, design.md 20.1-20.5 |
| 2026-08-11 | **New init guard** (R17.3): a `mode: product` repo refuses a namespace already holding another project's manifest. Justified on **blast radius** -- prefix-delete/teardown operate on a whole namespace, so a shared prefix means deleting the product can delete raw data -- plus one-manifest ownership. Enforced rather than documented because the utility of mixing is ~zero (a second prefix costs nothing) while the failure is destructive. | R17.3/R17.4, AC22, Task 11 |
| 2026-08-11 | **Correction: datom needs NO governance for cross-project members or parents.** The mechanism is caller-supplies-connection; the project name is a label and datom performs no name-to-location lookup anywhere. An earlier claim that cross-bucket products "effectively expect gov attached" was wrong -- it conflated datom's write-time needs with the access layer's read-time SOURCES lookup. | R18.1, design.md 20.3 |
| 2026-08-11 | **Location precedence, inherited not invented**: explicit address in the project's own config works standalone; `ref.json` in the gov repo takes priority once governance exists; `governance.json` is the flag for whether it is attached. Member resolution follows this exact precedence. Therefore **member records carry a logical project name and never a location** -- an embedded location would go stale on a bucket move, which is what `ref.json` exists to prevent. | R18.2/R18.3 |
| 2026-08-11 | **Correction: the access unit is the artifact, not the namespace.** Roles are table-level and a derived table's requirement is the union of its **leaf ancestors'** roles, so two derived tables in one product/bucket/prefix get different requirements automatically. Per-artifact IAM is expressible because every artifact has its own folder. The namespace rule therefore **keeps its conclusion but changes its justification** (blast radius + ownership, not access) -- a rule defended by a wrong argument gets relitigated. | R19.1/R19.2, R17.4, design.md 20.6 |
| 2026-08-11 | **A set gates on nothing** -- no parents means the lineage walk finds no leaves, so no roles are required unless explicitly overridden. Same conclusion as the non-conjunctive access decision, now confirmed against the access layer's algorithm. Corollaries recorded because they surprise people: **granting a product does not grant its members**, and a **sensitive member list uses the explicit-override path**. | R19.3-R19.5, design.md 20.7 |
| 2026-08-11 | **SUPERSEDED 2026-08-18 -- the write export is retired, so this refusal has nothing to attach to; do not implement it.** ~~The JSON write export must also refuse **`.access/`** -- the namespace reserved for the access-enforcement package, where datom is safe today only *by construction*. This export is the first general-purpose write path that could break that reservation.~~ | R12.4a/R19.6, AC23, Task 3 |
| 2026-08-11 | **`role` terminology collision**: datom's `role` (developer/reader) vs the access layer's "role" (permission set). **datom keeps `role`; the burden is on the future package to pick a different term** -- it does not exist yet so the rename is free there and breaking here. Recorded in `dev/datomanager_overview.md` for whoever builds it. | design.md 20.9 |
| 2026-08-11 | **Clarified: there is no lineage walk.** `source_lineage` is a precomputed transitive union maintained at write time -- imported tables get a self-entry, derived tables get the union of their parents' unions -- so "which raw sources feed X" is **one read, zero hops**, and it cannot drift because parents pin immutable versions. Design section 20.6 initially repeated the access design's "walk upward" framing; corrected. | design.md 20.10 |
| 2026-08-11 | **`dev/datomanager_overview.md` is stale on this point and now says so.** It predates Phase 20, so it requires only `parents` and builds a walk -> session-cache -> *precomputed leaf map* ladder. `source_lineage` **is** that leaf map, already stored per table. Added item 3a plus stale-markers on the affected sections: delete the walk, do not rebuild `ROLE_LEAVES`, keep the access *semantics*. | dev/datomanager_overview.md |
| 2026-08-11 | **RESOLVED -- all nesting machinery removed** (supersedes F1 and the two OPEN entries that preceded this). Cycle detection, the visited-set guard, and the depth limit are **gone**, for two independent reasons either of which suffices: (1) **datom resolves one level and never traverses** -- a member that is a set comes back as a pointer and the consumer reads it separately, so nothing can loop; (2) **the graph is acyclic by construction** -- members pin immutable versions that must already exist, so a set cannot reference something containing it, exactly as git history cannot cycle. The "cross-project cycle" earlier constructed does not close: the second write creates a new version rather than mutating the referenced one, giving `B1@v2 -> A1@v1 -> B1@v1`, which terminates. | R4.3-R4.5, I10/I10a, P16, AC9/AC15, design.md 5 + 20.11 |
| 2026-08-11 | Replacements after the removal: **R4.3** one-level resolution, **R4.4** acyclic by construction, **R4.5** refuse self-reference (the one check that stays -- acyclic and harmless, but never meaningful). **I10** no traversal, **I10a** no cycle/depth guard may creep back as defensive code. **P16** restated as "read cost is bounded by direct member count". **AC9** restated as self-reference refusal, **AC15** restated as "nesting resolves one level" -- a test that the tree is *not* flattened. | requirements.md R4, design.md 13-14 |
| 2026-08-11 | **Retired: the transitive-member-closure question** (formerly E1 Q6). It existed only to replace a traversal with one read; there is no traversal, so it would be payload weight buying nothing and would enter set identity for no benefit. E1 is back to one hard constraint + five open questions. | design.md 7, 20.11 |
| 2026-08-11 | **Git owns history; datom writes projections** (R20). The test: *would someone holding the repo use this file to answer a history question?* `version_history.json` and `manifest.json` pass -- only git-less **readers** need them, and the giveaway that they are projections rather than duplicates is that they carry `author` and `commit_message`, literally git commit fields. | design.md 21.1 |
| 2026-08-11 | **Correction: the git payload moves to a stable path `{name}/set.json`**; storage stays content-addressed at `{name}/{data_sha}.json`. A content-addressed *git* filename makes every version a new file, so `git diff` reports "file added" instead of which members changed, and history gets read by listing filenames -- hand-maintaining what git maintains. The "retain all historical payloads" rule is dropped as redundant (git retention is definitional); P17 holds via `git show <commit>:{name}/set.json`. | R6.1a/b, P25, AC24, design.md 21.2 |
| 2026-08-11 | **Version semantics -- option 1 chosen.** A version stays **content-derived and code-invariant**, identically for tables and sets; the commit is recorded **provenance**, not identity. So a code-only change producing identical content mints **no** new version (already true for tables, deliberately kept true for sets), and one version maps to **one or more** commits with `commit_sha` naming the first. | R21.1-R21.3, I23, P27, AC26, design.md 21.3 |
| 2026-08-11 | **Rejected: commit-as-version** (circular -- the commit contains the metadata that would name it; a composite version would break `datom_read(version = )` as a single string). **Rejected: code/env content hashes in the payload**, which *would* work mechanically, because a set exists to be **citable** and a comment typo or lint fix would then mint a new product version. The strongest counter-argument -- restricting it to `renv.lock`, since env drift can silently change future behavior -- is recorded in case it returns. | R21.4, design.md 21.3 |
| 2026-08-11 | **`commit_sha` goes in the `version_history.json` entry**, storage copy only (the git copy is inside the commit it would name), captured after the push. Zero identity impact and **no volatile-list entry needed**, because `metadata_sha` hashes `metadata.json`, not `version_history.json`. | R21.5/R21.6, Task 15 |
| 2026-08-11 | **The trap: `datom_validate(fix = TRUE)` would silently strip `commit_sha`** when it re-uploads metadata from the clone. Resolved by treating the field as **derived, never authored** -- the repair path re-derives it from `git log`, so storage holds nothing unrecoverable and the "mirror is derived from git" invariant survives. AC25's third clause exists to catch this; a naive implementation passes everything else. | R21.7, I22, P26 |
| 2026-08-11 | **Precedent checked, not assumed** (public sources): dpbuild keeps no commit hash in the product repo -- `.daap/daap_log.yaml` is inside the commit -- and dpdeploy publishes it to a storage-side `dpboard-log` pin that dpi's `dp_list()` reads **with no git**. That log's composite key is `(dp_name, pin_version, git_sha)`, independently confirming that one content version can pair with several commits. datom needs no separate deploy pass (it already uploads after push) and adds no board-level index (per-artifact history already carries the sibling git fields). **Corrects an earlier claim in this conversation that dpbuild had no git-less readers -- dpi is exactly that.** | R21.9, design.md 21.5 |
| 2026-08-11 | Tasks: **new Task 15** (version-to-commit link) inserted after validate, since its repair-path behavior needs `datom_validate()` to exist. Old 14/15 -> 15/16. | tasks.md Phase D |
| 2026-08-15 | **E1 Q1 -- OWNER-DECIDED: whole-payload hashing.** `data_sha` covers members **and** their tags (a description is a tag). A set is citable, and "same cite, different tags" would lie to the consumer. A tag or description edit therefore **mints a new version** -- intended behavior. Consequence applied: **AC2 was wrong** as written ("identical member list is a no-op") and is now two-sided -- identical *payload* is a no-op, identical members with a changed tag is **not**. | R2.6, AC2, design.md 7.5 |
| 2026-08-15 | **E1 Q2 -- OWNER-DECIDED: dissolved by the omission rule.** A payload has no data cells, so `NA` could only arrive via optional fields. datom's existing "omitted, not nulled" convention (verified `R/read_write.R:302-305`) becomes the canonical form: absence means the field **does not exist**; `null` / `NA` / `""` are never representations of absence. A literal `NA` reaching the encoder is an **error**, not an encoding case, and goldens carry the refusal. Knock-on: the walk has **no `null` tag** (the earlier draft's `0x04` is dropped), and this is where sv1 legitimately diverges from cv1, which needs an NA mask byte because table cells *can* be missing. | R2.7, design.md 7.2/7.5 |
| 2026-08-15 | **E1 Q3 -- OWNER-DECIDED: empty set refused.** Mirrors cv1's zero-dim abort (verified `R/utils-sha.R:310-312`). Marginal utility -- the build package simply does not write the set until its first output exists -- and an empty citable product is semantically murky. Cheap to relax later, awkward to retract. AC5 updated: refusal is the **tested** behavior, not a documented maybe. | R2.8, AC5 |
| 2026-08-15 | **E1 Q4 -- OWNER-DECIDED: `schema_version` stays out of the payload and hash.** It describes the container format, not the content; in identity a format bump would re-mint every set with unchanged members -- the same failure the `volatile` list exists to prevent (verified `R/utils-sha.R:415-416`). | R2.9 |
| 2026-08-15 | **E1 Q5 -- OWNER-DECIDED: emitter-free structural hash.** Neither `jsonlite` nor a bespoke sv1 emitter is canonical, because **no serializer is in the identity path**. ~~sv1 is a deterministic walk of the parsed payload: radix-sorted keys recursively, fixed per-type leaf encoding with a domain-separation tag per type, `sha256("datom-sv1" \|\| encoded-walk)`.~~ **The walk formulation was SUPERSEDED 2026-08-16 by F-A** -- replaced by the hash-of-hashes construction; the *decision* (no serializer in the identity path) stands unchanged. Stored-file formatting is free, because stored-byte integrity is `document_sha`'s separate job -- **identity and storage integrity never share a dependency**. Goldens and `dev/datom_sv1_reference.R` are written against ~~the walk spec~~ **the encoding specification as it now stands (superseded wording: "the walk spec")**, not any emitter's output. | R2.10, design.md 7.2/7.4 |
| 2026-08-15 | **R2.5's force stands; its mechanism is superseded.** The write/read agreement constraint is unchanged, but it is no longer achieved by normalizing through `serialize -> parse -> encode`. Each mutation is eliminated at source instead: numbers always f64 (kills integer-vs-double), `NA` aborts (kills the `"NA"` string and `null` cases), and scalar-vs-array is decided by an explicit R-type rule. **Verified bonus**: the one supporting condition -- reading with `simplifyVector = FALSE` -- is *already* satisfied deliberately by both backends (`R/utils-local.R:110`, `R/utils-s3.R:209`, the latter documented as "keep lists as lists"). So the decision is supported by existing infrastructure rather than imposing a new read-path requirement. | R2.5, design.md 7.1/7.3 |
| 2026-08-15 | **sv1 does not inherit the `metadata_sha` emitter exposure** (section 16). The earlier "cannot both be right" tension is resolved one-sidedly: sv1 is clean by construction, which *sharpens* rather than softens the case for the separate `metadata_sha` issue, since it becomes the only hash in datom whose value depends on a third-party formatter. Scope of that issue unchanged; priority arguably rises. | design.md 7.4, 16 |
| 2026-08-15 | **E1 downgraded from open-question debate to design review.** Gate for Task 2 is now: exact byte rules, whether the tag table leaves a collision surface, and whether the goldens cover the 7.3 agreement cases. Goldens still freeze the encoding -- a later change needs a conscious `datom-sv2` bump. | design.md E1, Task 2 |
| 2026-08-17 | **Final pre-implementation review (independent, adversarial). 20 findings, all triaged; the 5 blockers are fixed.** Verified the factual ones against the tree first. **Blockers**: (1) Task 2's R2.5 bullet still instructed "numbers always f64" and "scalar-vs-array decided by an explicit R-type rule" -- both removed mechanisms, in the bullet that governs the goldens; (2) Task 2's Q5 bullet still specified the superseded type-dispatch walk *immediately before* the bullet declaring it superseded, so a top-down reader implements the wrong one; (3) **I13 as worded mandated the removed serialize/parse pass and contradicted AC13**; (4) **no public parameter existed for set-level tags**, which R2.12 requires, R2.6 hashes, and AC2's converse half tests -- while R1.4 withholds `metadata =`, so the surface could not express a required payload; (5) **a third manifest write site exists** at `R/sync.R:721` (the absent-manifest skeleton) that the "two write sites / eight total" enumeration missed. | R2.5, R12.2, I13, design.md 9 |
| 2026-08-17 | **(review) `R/sync.R:969` is the dangerous manifest site.** It builds `list(project_name = ..., tables = list(), summary = list())` when `.datom/manifest.json` is absent, so left unrenamed it writes a `tables` key *after* the rename -- and it fires only on a fresh or repaired repo, so per-chunk tests against an existing fixture pass while the bug ships. Counts corrected to **3 write + 6 read = 9 sites**. One sub-claim of the review was **wrong**: `R/conn.R:522` *is* the `tables` line (the review said 520); citation left as-is. | design.md 9, Task 6 |
| 2026-08-17 | **(review) three code citations were wrong when written** (verified `R/` is byte-identical since `b57cdba`, so this is not drift): `R/validate.R:386` -> **391**; the `parquet_sha` verification gate `R/read_write.R:217` -> **227**; `.datom_resolve_version()`'s history read `R/read_write.R:177` -> **187** (with `129` for the current-metadata read). Also `R/utils-git.R:154-159` -> `131-161`, abort at `160`. These matter because design.md section 1 instructs "cite these rather than re-deriving them", so wrong numbers propagate into code comments. | design.md 1 |
| 2026-08-17 | **(review) duplicate members were undefined -- now refused** (R2.14). ~~`set()` concatenates member digests with **no** `sort` and **no** `unique`, so `[m, m]` and `[m]` hash differently: members are the one position where duplication *is* identity.~~ **SUPERSEDED 2026-08-17 by D2** -- `set()` now sorts and dedupes, so `[m, m]` and `[m]` hash **equal** and the encoder was never ambiguous. The refusal survives with a different justification: R2.15 canonicalization would silently drop the second copy, and a set listing the same datom version twice has no meaning, so an abort is the honest outcome. Nothing said whether it was legal, so the goldens would have frozen an accident either way. | R2.14, AC27 |
| 2026-08-17 | **(review) the empty-tag-value refusal had no test, and `""` was undefined** -- both settled in R2.14 and AC27. `character(0)` means "no labels", which R2.7 spells by omitting the key; `""` is a label with no name and is likewise refused. R2.7 only said `""` never represents *absence*, which left the separate question of whether it is a legal *label* to be decided by the encoder by accident. | R2.14, AC27 |
| 2026-08-17 | **(review) the `document_sha` integrity gate had no acceptance criterion** -- the one thing design section 8 calls "building a silent-degradation path on purpose" if got wrong. New **AC28** covers both halves: mismatched bytes refused *before parsing*, and a **missing/empty** `document_sha` an **error rather than a skip**. The second half is what a naive copy of `.datom_read_parquet()`'s `if (!is.null(...) && nzchar(...))` guard gets wrong. Task 10 now claims it. | AC28, I3, P9 |
| 2026-08-17 | **(review) Tasks 6 and 14 had no `Acceptance:` line at all**, and Task 16's sweep stopped at AC26 (omitting AC27). Both fixed; Task 14 also now owns a test for P14, which had no AC despite R11.3 calling it "in scope rather than deferred". Seven properties were orphaned (defined, referenced by no task) -- P25/P29 attached to Task 9, P4/P8/P28/P30/P31 to Task 2. | Tasks 6, 9, 10, 14, 16 |
| 2026-08-17 | **(review) three more stale-mechanism references removed**: Task 9 named "the cycle walk's root" as a precondition (there is no cycle walk, and I10a forbids one); Task 14 promised a git-vs-storage payload comparison justified by "R6.1b's git retention", which R6.1b reversed; and the **pathway route card in design section 17 instructed "or recurse"**, contradicting I10 -- that one becomes shipped user documentation in Task 17. Also fixed: the section 19.3 repo sketch still showed `{data_sha}.json` in the git tree, the exact layout AC24 fails. | Tasks 8, 13, design.md 17, 19.3 |
| 2026-08-17 | **(review) "structural walk" wording survived in R2.2 and three design summary rows**, contradicting R2.10 three paragraphs later. That wording is what seeded F-A, so leaving it in the summaries is how it returns. Restated. Plus cosmetics: P8 asserted independence from `size_bytes`, which R1.4 removed from set metadata (vacuous); the AC count "nine" is now 28; and the one-spelling rule was cross-referenced to R2.10 instead of R2.7. | R2.2, P8, design.md 7 |
| 2026-08-16 | **(F-A, BLOCKER -- verified) the closed grammar could not derive the payload shape.** R2.11 said `value ::= string \| [string, ...] \| object`, but R2.12 required `members: [{...}, ...]` -- an **array of objects**, which had no production; R2.10 reinforced it ("only three types to tag") and the encoder's `0x05` was named *string* array. Confirmed by reading both against each other: two requirements that could not both be true, same class as F4. An implementer would have improvised -- read `0x05` as a generic array, or invent a fourth tag -- and **frozen the choice into the golden vectors**, which is what E1 exists to prevent. | design.md 7.2.1 |
| 2026-08-16 | **(F-B -- verified) tag-value array order was identity, and should not have been.** design.md justified order-as-identity with "member order is a curatorial choice the user sees and controls" -- right for `members[]`, wrong for tag values, which the same rule also caught. Confirmed: R2.12 covered member order and tag *key* order but was **silent on tag value order**, so it fell through to the generic array rule. Since a multi-valued tag models *simultaneous folder membership* (R4.6), which is unordered, `domain: ["safety","efficacy"]` vs reversed would have minted a new **citable version** for a semantically null reorder. Does not weaken Q1: a tag *edit* minting a version is intended, a *reorder* is not an edit. | design.md 7.2.2 |
| 2026-08-16 | **Resolution 1 -- `id` split from `tags` in the payload** (R2.12). The payload holds exactly two kinds of content: a well-specified reference record with fixed single-string keys, and an open tag map. Made structural rather than four fixed fields sitting loose beside a nested map. Tags stay per-member (R4.6 unchanged). | R2.12, R4.1, R4.6 |
| 2026-08-16 | **Naming: `id` -- CONFIRMED (owner, 2026-08-16).** Chosen over `ref` / `pointer` / `datom_id`: `ref` collides conceptually with `ref.json`, which means data *location*; `datom_id` is redundant inside datom's own payload; `pointer` is wordy; and project+name+version genuinely *is* the member's identity. **Now settled -- the key name is hashed, so it is frozen by the goldens exactly like the encoding.** Changing it after Task 2 is a `datom-sv2` bump, not an edit. | R2.12 |
| 2026-08-16 | **Resolution 2 -- the walk is replaced by a hash-of-hashes over 3 primitives + 2 shape rules** (R2.10). `str` / `strset` / `map`, then `member` / `set`. Mirrors cv1's per-column-digests-then-hash-the-concat pattern. **Closes F-A** because there is no generic `value` type left to be incomplete: every position's shape is fixed by where it sits, so the encoder never dispatches on runtime type and cannot have a gap. **Closes F-B** because ~~`members` is the only `concat` without a `sort`~~ **SUPERSEDED 2026-08-17 by D2** -- members are now sorted and deduped too, so the claim is stronger than it was: *every* collection is sorted, with no carve-out at all. Tag keys and values were always sorted, and values deduped, so "is this ordered?" is never a judgment call. | R2.10, P30, P31 |
| 2026-08-16 | **`f64le` disappears from sv1 entirely.** Every intermediate is a fixed 32 bytes, so concatenation is already unambiguous (`h("a")||h("b")` is 64 bytes and cannot collide with `h("ab")` at 32) -- no length prefixes needed. Consequence: `.datom_encode_numeric()` is not used **at all**, not even for lengths, so sv1 shares no numeric primitive with cv1. | design.md 7.2 |
| 2026-08-16 | **`id` is encoded with `map`, not positionally.** A fifth id field later is then just another key -- no positional convention, no absent-versus-empty question -- and one encoder serves both `id` and `tags`. Id values are single strings encoded as one-element strsets; validation separately enforces "exactly these four keys, each single-valued", keeping the encoder out of validation's job. | R2.10 |
| 2026-08-16 | **Resolution 3 -- a single string equals a one-element set** (R2.13). `type: "output"` and `type: ["output"]` hash identically, because every map value passes through `strset`. This **reverses** AC13's surviving fixture, which required them to differ: both spellings mean one label named output, so distinguishing them would mint a citable version over a purely syntactic authoring choice -- the same objection that killed tag-value ordering. Net effect: **every AC13 hazard becomes unrepresentable rather than handled**, so P28's goal is reached completely rather than partially. | R2.13, P28, AC13 |
| 2026-08-16 | **R2.5's residual condition narrows to structure.** With leaves order-, duplication- and shape-insensitive, `simplifyVector = FALSE` matters only so `members[]` stays a list of records instead of collapsing into a data frame -- leaf-level simplification is now immaterial. Both backends already do it deliberately. | R2.5, design.md 7.3 |
| 2026-08-16 | **AC13 fixtures replaced**: (a) tag-value order equal, (b) tag-value duplication equal, ~~(c) member order different~~ **SUPERSEDED 2026-08-17 by D2 -- member order is now equal**, (d) single string vs one-element array equal. The old "length-1 vs bare string must differ" fixture is **inverted**, and the number/boolean fixtures were already inapplicable. | AC13 |
| 2026-08-15 | **The payload is text-only, and that is a closed grammar** (R2.11). Values are UTF-8 strings or arrays of strings; **no numbers, booleans, `null`, or nesting beyond the fixed shape** (R2.12). Rationale: tags replace folder-style organisation and folder labels are text, so numbers and booleans buy nothing datom uses while costing an integer-vs-double rule, a boolean tag, and a wider golden matrix. A numeric tag is written `"500"` and parsed downstream, exactly as a folder name would be. | R2.11, I24, AC27 |
| 2026-08-15 | ~~**Consequence: the walk collapses from five type tags to three** (string / string-array / object)~~ **SUPERSEDED 2026-08-16 by F-A** -- the type-dispatch walk is replaced outright by the hash-of-hashes construction, so there is no type-tag list at all. The *reasons* below still hold (numbers/booleans/null are not in the grammar); only the mechanism changed. (string / string-array / object). Three of R2.5's four agreement hazards become **unrepresentable rather than handled** -- int-vs-double and `NA_real_` because there are no numbers, `null` because absence is omission. Only scalar-vs-length-1-array remains an actual rule. `.datom_encode_numeric()` is no longer reused for payload values; only its `f64le` length framing is shared, for lengths datom computes itself. | design.md 7.2/7.3, Task 2 |
| 2026-08-15 | **Tags are per-member** (R4.6), and `datom_member()` gains `tags = NULL`. What they replace is dpbuild's nested product list (`dp$input$raw_ae()`, `dp$output$derived1`, `dp$metadata$data_def`), whose top-level names classify **items**, not the collection -- confirmed by #89's own rejected alternative, which flattened to `(name, project, version, tag_key, tag_value)`, one row per member per tag. Set-level tags are also allowed, for facts about the collection such as a description. | R4.6, Task 8 |
| 2026-08-15 | **A tag value may be a string OR an array of strings**, and that is the *only* reason arrays exist in the grammar. The motivating limitation of folders is that an item cannot be in two at once, so multi-valued tags (`domain: ["safety", "efficacy"]`) are the point rather than an extension. | R2.11, R4.6 |
| 2026-08-15 | **#89's "view config" is retired; no navigation structure is stored at all** (R4.7, I25). Folder-like hierarchy is a **projection**: prioritise one ordering of tag keys at gov level and you get one structure, prioritise another and you get a different one -- so structure is presentation, not content. This retires the "nested view config does not survive the flattening" argument, since navigation *is* the tags, and it is what makes the text-only grammar sufficient. Bonus property: arbitrarily many folder structures cost nothing because none is stored. | R4.7, I25, P29 |
| 2026-08-15 | Closures stay downstream: dpbuild's inputs are lazy closures, whereas a datom member is a pointer and `datom_read()` is the lazy fetch. Assembling closures is the build package's job -- the layering #89 asked for. No datom change. | design.md s4 |
| 2026-08-15 | **Git-commit-linkage follow-ups asked and confirmed as-is, no change** (R20/R21): (a) lagging `commit_sha` into the git copy on a subsequent write, (b) moving the linkage into governance, (c) recording *all* producing commits rather than the first. Examined; the existing spec answers hold -- (a) leaves the newest version permanently unlinked, (b) makes a git-less-reader convenience depend on gov being attached, (c) turns an immutable history entry into an append target. Logged so they are not re-litigated. | R20, R21 |
| 2026-08-11 | **Process lesson recorded, not patched over.** The nesting machinery entered via review finding F1, which correctly spotted a contradiction between two spec statements and was resolved by *adding* guards rather than by testing whether either statement was true. Both were false. When a review surfaces a contradiction, **check the premises before building something to reconcile them**. | design.md 18 (F1 row), 20.11 |
| 2026-08-11 | **AC1 split** into (a) resolve pointers -- always works, no clone -- and (b) resolve to data -- needs that member's project conn. Conflating them mis-implements a set read as "requires access to everything in it". `datom_validate()`'s member check scoped the same way (R11.2), reusing `members_unresolvable`. | AC1, R11.2, Tasks 9 and 13 |
| 2026-08-17 | **Task 1 scope deviation -- OWNER-APPROVED, the guard stays.** Folding `.datom_validate_sha()` into `.datom_artifact_payload_key()` exceeded the chunk's behavior-identical scope, because it closed a real path-traversal gap at `.datom_validate_one_table()` (`R/validate.R:393`) that #74's sweep missed -- a file-supplied `data_sha` spliced into a storage key unvalidated -- and cost one test fixture using an impossible `data_sha = "d1"`. Kept rather than reverted: the alternative leaves a known gap behind a tracking issue competing with 15 remaining tasks, for a purity cost of one fixture line. Behavior for valid data is unchanged. | Task 1, I9, `R/utils-path.R` |
| 2026-08-17 | **Reader-side version diff needs no schema change -- option 3 chosen.** A git-less reader can already diff two set versions with three small JSON reads: `version_history.json` (which carries `data_sha` per entry today, `R/read_write.R:485-491`) to map version -> `data_sha`, then the two content-addressed payloads. **Rejected: persisting per-member digests in metadata** as a `column_hashes` analogue (see design.md 15 for both rejected options). The decisive points: the payload diff reports **actual values** where digests report only "something changed"; `column_hashes` earns its place solely because the alternative is downloading parquet, which does not transfer to a small text payload (design.md 4, "a member index would be metadata-for-metadata"); and there is **no code to reuse** -- `column_hashes` has no consumer in `R/` and `datom_diff` is unbuilt (#73). Member digests remain **additive and volatile**, so they can be added later without a schema break or identity change if a cross-version change timeline proves to be a real need. **No impact on Task 2**: sv1's encoding is identical under this decision, since it would only have published intermediates the hash-of-hashes already computes. | design.md 4 + 15, R6, Task 10 |
| 2026-08-17 | **E1 design review (Task 2 gate) -- four deltas, all owner-approved before goldens freeze.** The encoding itself reviewed clean: domain separation is sound (distinct marker byte per constructor, so cross-type collisions reduce to sha256 collisions); "framing is free" verified (every entry fixed-width -- `map` entry 64 bytes, `member` 64, `set` 32+32n -- so concatenation parses unambiguously without length prefixes); `sort(method = "radix")` is C-locale byte order as claimed; `id`-vs-`tags` slot swapping cannot collide. The four findings are all **additive**, not a redesign, so no model escalation beyond this review. | design.md 7.2-7.2.3, R2.12-R2.17, R7.5 |
| 2026-08-17 | **(D2) Member order is NO LONGER identity** -- `set()` sorts and dedupes member digests like every other collection. **Owner-raised**: order buys nothing since nothing consumes a set positionally. Three arguments, any one sufficient: it contradicted R4.7 (arrangement is presentation, which is why no hierarchy is stored); it contradicted 7.2.2's own reasoning, which killed tag-value ordering for the identical reason; and decisively, the expected producer is a **script**, so an insertion-order refactor would mint a new product version with byte-identical content -- the #72 failure class. Costs one `sort()` over fixed-width digests. **Bonus: 7.2's only carve-out disappears** -- every collection is sorted and deduped, one rule with no exceptions. Reverses P3 and AC13(c); R2.14's duplicate-member rationale changes (the encoder was never ambiguous, and now R2.15 would drop the copy silently, which is better surfaced as an abort). | R2.12, R2.14, P3, P30, AC13(c), design.md 7.2 + 15 |
| 2026-08-17 | **(D1) The payload is canonicalized BEFORE the local write** (R2.15, I26) -- sort map keys, sort + dedupe tag values, **unbox single values**, sort + dedupe members. **Owner-proposed**, and better than the reviewer's original framing, which only guarded the write path: canonicalizing at the source means one content has exactly one byte spelling in git and in storage, so the ambiguity is removed rather than managed. Unboxing (not always-array) because `auto_unbox = TRUE` is already the house default in datom's metadata writers -- the free direction -- and it keeps the `git diff` of R6.1a readable. **Shape unification was a gap in the reviewer's first draft of this delta**, caught by the owner: sorting alone still leaves `"output"` vs `["output"]` as two spellings. sv1 stays order- and shape-insensitive regardless, since the hash domain is a *parsed file* that may predate this rule or have been hand-edited: canonicalization is belt, insensitivity is braces. | R2.15, I26, AC29a, Task 9 |
| 2026-08-17 | **(D3) One `data_sha`, one byte spelling, enforced over time** (R7.5, I27). Two rules, both required: never re-emit a payload for a `data_sha` already in history (reuse the stored object, **carry the recorded `document_sha` forward** -- the exact `.datom_lookup_history_parquet_sha()` pattern at `R/read_write.R:404-409`), **and** hold `datom_validate(fix = TRUE)` to the same rule, since it re-uploads from the clone and so is a live path to overwriting a stored object with non-matching bytes. Same trap shape as the `commit_sha` one (R21.7/I22): a repair path silently undoing a write-path guarantee. **Sharper for sets than tables**: divergent bytes for one `data_sha` need an `arrow` upgrade for a table but only a tag-value reorder for a set, and only sets keep the payload in git. **Deliberately assigned to Tasks 8 and 13, not 2** -- it is a consequence of Task 2's decisions but not encoder code, and a Task 9 implementer assuming "new bytes mean a new `document_sha`" ships a defect that every per-chunk test passes. | R7.5, I27, P32, AC29, Tasks 8 + 13 |
| 2026-08-17 | **(D4) No Unicode normalization; tag bytes are hashed as given** (R2.16). NFC and NFD are different tags. Rejected NFC-first because **normalization tables are versioned Unicode data**, so a Unicode release could re-mint hashes -- the #72 failure mode with the Unicode Consortium in `arrow`'s role, and sv1 exists to keep everything versioned out of its identity path (7.4). Also avoids adding `stringi` to a lean `Imports`, and stays consistent with cv1, which already treats NFC-vs-NFD as identity-relevant (`dev/e2e-cv1-identity.R`). Stated normatively because it would otherwise be settled by accident, and a non-R implementation might normalize by default. Golden asserts they differ. | R2.16, P33, AC13(f) |
| 2026-08-17 | **(D5) `strset(character(0)) = h(0x02)` is pinned** (R2.17). Validation refuses empty tag values and R2.15 cannot produce one, but the encoder must not depend on that -- the argument design.md 7.2 already makes for the empty map: an encoder whose correctness rests on an upstream refusal breaks silently the day the refusal is relaxed. Carried as a golden. | R2.17, AC13(g) |
| 2026-08-17 | **(D6) AC13 grows from four fixtures to seven**, and AC29 is new. Equal: tag-value order, tag-value duplication, **member order**, single-vs-one-element-array, **member duplication**. Different: **NFC vs NFD**. Constant: **empty strset**. Two fixtures now **reverse** earlier "must differ" versions -- member order (D2) and single-vs-array (the 2026-08-16 delta). AC29 covers canonicalization on the file bytes, no-re-upload on a known `data_sha`, and the `validate(fix = TRUE)` clause that a naive implementation fails while passing the other two. | AC13, AC29 |
| 2026-08-17 | ~~**Process: D2's sweep hit the four places tasks.md warns about**, confirming the documented defect pattern rather than discovering a new one.~~ **CORRECTED same day -- it was six sites, not four, and the first sweep missed two of them.** Independent review found three (Task 2's goldens bullet, plus two log rows in present tense); tightening `check-spec.R` then found a sixth. Worse, **two were live instructions, not log rows**: Task 2's fixture list still said "member order different" *in the task that freezes the goldens*, and `requirements.md` R2.10 still carried "`members` is the only `concat` without a `sort`". An implementer working top-down from either would have frozen the wrong fixture, and undoing that is a `datom-sv2` bump. | R2.10, R2.12, AC13, Task 2 |
| 2026-08-17 | **`check-spec.R`'s retired-wording check was close to vacuous, and this is the round that proved it.** It passed on all six D2 sites. Cause: `MARKER_RE` -- the suppression list -- carried generic negation and impossibility cues ("never", "cannot", "not needed", "not required", "acyclic", "impossible", "unrepresentable", "immaterial", "dissolve", "collapse") on the reasoning that the commonest legitimate mention is a sentence saying the thing is NOT done. That reasoning fails at scale: those are ordinary vocabulary in this spec, so nearly every +/- 2 line window contained one. **The clearest case is self-suppression** -- "`members` is the only `concat` without a `sort` ... is never a judgment call" was excused by the word `never` in its own sentence. Fixed by narrowing to explicit supersession and explicit prohibition only; the tightened check immediately found the sixth site unaided. Tradeoff stated in the script: a false positive costs one marker word, a false negative ships a retired instruction that reads authoritative. | dev/check-spec.R |
| 2026-08-17 | **Denylist additions from D2**: "only unsorted concat", "only `concat` without a `sort`", "order is curatorial", "duplication \*is\* identity", "member order different", "member order.{0,20}differ". The last two are the phrasings that actually survived the first sweep, so they are the ones with demonstrated escape history. | dev/check-spec.R |
| 2026-08-17 | **A recurring trap shape, now named after its second instance: a repair path silently undoing a write-path guarantee.** `datom_validate(fix = TRUE)` re-uploads from the clone, so it is a general-purpose way to overwrite storage with derived content. Instance 1 was `commit_sha`, which repair would have **stripped** (R21.7, I22, AC25's third clause); instance 2 is `document_sha`, which repair would **invalidate** by re-emitting bytes for an existing `data_sha` (R7.5 rule 2, I27, AC29c). Both were caught only because someone asked "what does `fix = TRUE` do to this field?" **Any future spec adding a metadata field should answer that question explicitly**, and the acceptance criterion belongs on the repair path, not only the write path -- in both instances the repair clause is the one a naive implementation fails while passing everything else. | R7.5, R21.7, I22, I27, AC25, AC29 |
| 2026-08-17 | **Thorough post-delta review: 19 findings, all fixed.** Prompted by two prior sweeps each missing defects. **The decisive one was self-inflicted**: the sv1 pseudocode exists in all three spec files, the D2 fix touched only `design.md`, and `requirements.md` + `tasks.md` were left stating `concat( member(m) ... )` with no sort -- the second of those inside the task that freezes the goldens, eleven lines above prose saying the opposite. Every multi-member golden would have been wrong. Seven blockers total; the rest were ownership gaps and stale counts. | R2.10, design.md 7.2, Task 2 |
| 2026-08-17 | **TIDY FIRST, THEN VALIDATE -- owner-decided, and it reverses the reviewer's recommendation.** The reviewer proposed validate-then-canonicalize to keep the R2.14 refusals reachable. The owner's principle is better: *handle any trivial error without pestering the user; refuse only what is deliberate or unhandleable*. Six spellings are now **tidied silently** because nobody can reasonably care about them -- tag-value order, tag-value duplication, single-vs-array shape, member order, an exact-duplicate member, and `character(0)` dropping its key. Five are **refused** because each would require guessing intent -- non-text values, `NA`, `""` as a tag value, same-`id`-different-`tags`, and zero members. Tidy-first also composes better than validate-first: it clears the benign cases so validation only ever sees genuine ambiguity. | R2.14, R2.15, AC27, design.md 21.4 |
| 2026-08-17 | **Working through "which duplicates are benign" exposed a case both sweeps missed: same `id`, DIFFERENT `tags`.** `set()` dedupes by `member()` digest and the digest covers tags, so these have *different* digests and **dedup does not catch them** -- both entries survive, and a consumer projecting tags finds one member in two conflicting folders. That is one fact with two spellings; the intended form is a single entry with a multi-valued tag. **Refused**, because both ways to tidy it guess: merging tags is right if the caller meant both categories and nonsense if two code paths disagreed, and picking one entry is arbitrary. | R2.14, AC27(d) |
| 2026-08-17 | **Same NAME at different VERSIONS is legal and is NOT a duplicate (R2.14a) -- owner-raised.** `adsl@a1b2` and `adsl@f9e8` are different members with different content; a product carrying a current table beside a locked baseline is atypical but entirely sensible. **The duplicate check keys on the FULL `id`, never on `project`+`name`.** Given its own test precisely because `project`+`name` looks like the natural key, so the first reader to "tighten" it would silently break a legitimate use. Three consequences recorded: the R2.15 file sort key **must** include `version` (or two versions of one name have no defined relative order and canonical form is undefined); consumers disambiguate by tag, datom adds no warning since one firing on legitimate use is noise; and a future reader-side diff cannot key on `project/name` alone -- it should key on `project/name` where unique and fall back to including `version` where not. **The diff demo shown in this conversation had exactly that bug.** | R2.14a, R2.15, AC27 |
| 2026-08-17 | **(L2) The file's member sort key differs from the hash's, deliberately -- owner-approved.** Hash sorts `member()` digests (self-contained: the encoder never needs to know what an `id` looks like, which is what keeps "a fifth id field is just another key" true). The **file** sorts by `project` \|\| `name` \|\| `version`, because digest order would relocate a member whenever its tags change -- so `git diff` would report a delete plus an insert in a different place, with everything between shifting, instead of one changed field. That undoes R6.1a's entire purpose, which is D1's own justification. Both keys are fully deterministic, so "one content, one byte spelling" holds either way. Cheap now, and **expensive later**: once payloads ship, changing canonical file order is a canonical-form change that I27 forbids. | R2.15, R6.1a, P25, AC24 |
| 2026-08-17 | **AC27 ownership split; AC29c given an owner.** AC27 was claimed by **both** Task 2 and Task 9 while `design.md` 7.2 says the encoder stays out of validation's job -- and neither owner could enforce two of its clauses: `datom_member()` sees one member at a time so cannot detect a duplicate, and set-level `tags` never pass through it. Resolved: per-member grammar (non-text, `NA`, `""`) to Task 8; payload-level cases (same-`id`-different-`tags`, zero members, set-level tag grammar, every tidy assertion, and the R2.14a allow-case) to Task 9; **Task 2 owns none of it**. Separately, **AC29c had no acceptance line anywhere** -- discussed in Task 14's body, listed nowhere, outside Task 16's sweep range. The clause the spec twice calls "the one a naive implementation fails while passing everything else" was owned by nobody; now Task 14's. | AC27, AC29, Tasks 2/8/9/14 |
| 2026-08-17 | **AC13 split into payload-level and encoder-level, because its umbrella was unsatisfiable.** The umbrella asserted write/read `data_sha` agreement for every fixture, but (g) `strset(character(0))` is a primitive constant with no payload and no `data_sha`, and (e) member-duplication cannot be built through the public path since R2.14 tidies it. **AC13-P** keeps the umbrella (a, b, c, d, f); **AC13-E** calls the encoder directly (e, g). Also pinned: (f) NFC/NFD fixtures **must use `\u` escapes**, since they ship in `tests/` and AC11 holds `R CMD check --as-cran` at zero warnings. | AC13, AC11 |
| 2026-08-17 | **`check-spec.R` gains a root-cause check, and it is verified non-vacuous.** The two classes that survived three sweeps were both **duplicated content**, which no prose denylist can reach: the encoder pseudocode is written out in all three files, and the AC count/range was hardcoded in four places and went stale twice (stopped at AC26 omitting AC27; then at AC28 omitting AC29). New check 6 compares the six encoder rules across files after whitespace normalization, and forbids any explicit AC upper bound. **Tested by reintroducing the exact `set(p)` defect that survived three sweeps** -- the check fails, names `set(p)`, and prints the odd file out. Recorded because the previous round's lesson was shipping a check nobody proved worked. | dev/check-spec.R |
| 2026-08-17 | **Lesser fixes in the same pass**: `design.md` 21.4's write-order table -- the only end-to-end set write order -- had **no canonicalization step and no validation step**, and uploaded the payload unconditionally in contradiction of R7.5/I27/AC29b; now carries steps 0a/0b and a conditional step 6. Member-digest sort collation pinned to lowercase hex + radix (`strset`/`map` spelled it; the member sort did not). R7.5 rule 2 now forbids **re-uploading the bytes** as well as recomputing the hash -- forbidding only the recompute still permitted the worst outcome. `member_count` pinned as the **post-tidy** count. Task 2's `Requirements:` line no longer claims R2.15. Three stale "the E1 review is still pending" blocks updated (`tasks.md`, `design.md` 12, `dev/README.md`). Call-site count corrected 8 -> 9 at `design.md` 12. R2.14/R2.13 numbering left out of reading order deliberately -- the numbers record decision order, and renumbering would churn every reference. | R2.15, R7.5, R8, design.md 12 + 21.4 |
| 2026-08-17 | **(review hardening 1) R2.15 step 4's sort tie is unreachable, and that is now stated.** Two members can share `project` \|\| `name` \|\| `version` in exactly one situation -- the **same `id` with different `tags`**, which survives dedup because the `member()` digest covers tags. Because tidy runs before validation, the sort can meet that tie and R's stable radix sort resolves it to caller input order; harmless, since R2.14 refuses that payload one step later so no tie reaches a written payload. Recorded because an implementer reaching step 4 will ask what to do about ties and might add a **dead-code tiebreaker** or escalate. Explicitly **not** fixed by hoisting the refusal before tidy: the phase separation is worth more than removing an unreachable edge, and inverting it would make the tidy rules unreachable instead. Also noted that the key omits `kind` safely -- AC4 refuses cross-kind name collisions, so `kind` could never break a tie the rest of the key did not already decide. | R2.15, R2.14, AC4 |
| 2026-08-17 | **(review hardening 2) `check-spec.R` check 6 detected disagreement but not ABSENCE -- fixed, and the reviewer found one hole while there were two.** Comparing present copies is insufficient: delete a rule from one file and the survivors still agree. **Demonstrated before fixing** -- deleting `str(s)` from `requirements.md` gave `ok  duplicated content agrees -- 6 encoder rules consistent`, exit 0, the count still reading 6 because the key survived via the other two files. The second hole, unreported: with a rule deleted from **all three** files the key vanished from the loop's index and was **not checked at all**. Both closed by iterating `CODE_KEYS` rather than observed keys and asserting presence in every spec file. Matters most for `requirements.md`, where R2.10 *defines* the encoding -- if the formula vanishes there the requirement stops stating what it requires, and the next editor updates the two files that still carry it without learning a third did. Verified non-vacuously in both directions: one-file deletion and all-file deletion each FAIL naming the missing file(s), and restore returns to pass. | dev/check-spec.R |
| 2026-08-17 | **Cold-start audit: five things would have tripped a fresh session; all fixed.** Asked whether Task 2 could be started in a new session, the documented cold-start path (`dev/README.md` Active Specs -> this file's state block -> the task) was walked as a cold reader. **(1) The state block contradicted itself** -- "it carries the E1 escalation, and per rule 5d that recommendation must be surfaced *before* implementing" followed two sentences later by "that review is DONE". A fresh session obeying rule 5d would have re-run the review, relitigating settled decisions and re-freezing specified goldens. Rewritten as an explicit **discharge record**, and Task 2's heading now reads "design review DONE 2026-08-17; implement, do not re-review". **(2) The `check-spec.R` description listed five checks when there are eight**, omitting check 6 -- the one that guards the pseudocode Task 2 is about to implement from. **(3) The "repeating defect pattern" advice was stale**: it said to add retired phrasing to the denylist, which is now known to be the weaker half; the pseudocode is guarded mechanically and prose is not, so the advice is split into four numbered steps. **(4) `R/hashable-set.R` vs extending `R/utils-sha.R` said "decide at the review"** -- a dangling instruction once the review closed. Decided: new `R/hashable-set.R`, because sv1 shares no primitive with `utils-sha.R`'s three unrelated concerns and that file is already 565 lines. **(5) One Q5 log row still said goldens are "written against the walk spec"**, retired wording outside its strikethrough. | tasks.md state block, Task 2 |
| 2026-08-17 | **Check 6 is strict enough to flag a spec author *quoting* a stale AC range as a bad example.** Hit while writing the anti-pattern guidance itself. Resolved by describing the shape in words rather than exempting the check -- same call as the `manifest$tables` note in the `retired` denylist, where a phrase is load-bearing in the instruction forbidding it. Recorded because the tempting fix is to loosen the check, and loosening is exactly what made the retired-wording check vacuous for six sites. | dev/check-spec.R |
| 2026-08-18 | **THE SV1 GOLDENS ARE PUBLISHED; THE ENCODING IS FROZEN.** Task 2 shipped the encoder, the standalone reference, and hard-coded goldens, with reference/package parity asserted on both architectures. Any byte-rule change from here is a conscious `datom-sv2` bump with a new `hash_algo`, not a spec edit and not a code fix -- so a failing golden means the code drifted. The values are tabulated in Task 2's DONE block. Nothing about the encoding as reviewed changed during implementation: all four E1 deltas (member order out of identity, canonicalize-before-write, `document_sha` byte identity, no Unicode normalization) plus the empty-`strset` pin landed as specified. | Task 2, R2.10, `R/hashable-set.R` |
| 2026-08-18 | **(implementation, and the one real find) a NAMED list in a value position must be refused, and the spec never said so.** Element-wise, `list(b = "c")` and `list("c")` are indistinguishable -- both are a one-element list holding one string -- so an encoder that validated only elements would hash `{"a": {"b": "c"}}` **identically to** `{"a": ["c"]}`. The inner key would sit outside identity, giving two different payloads one `data_sha` and therefore one storage address, which is the exact class of failure sv1 exists to prevent. Caught by a test written for P31 ("there is no object-valued position"), which is worth noting: the property was in the spec, the consequence was not, and it took writing the assertion to find the gap. Fixed in both the package and the reference (they must stay byte-identical), and it changes no golden -- it only converts a silent mis-encoding into an abort. | R2.11, P31, `R/hashable-set.R` |
| 2026-08-18 | **(implementation) the encoder also refuses an unexpected field at the payload root or inside a member record.** Same reasoning as the row above: an ignored field is content outside identity. Two useful consequences. It makes R2.9 **structural** rather than aspirational -- a payload carrying `schema_version` aborts instead of being quietly hashed without it -- and it means "a fifth `id` field is just another key" stays true at the `id` level (where `map` encodes whatever it is given) without also making the *member record* silently extensible. Not a contradiction of "the encoder does not validate": grammar enforcement with recourse (which key, what types are allowed) is still Tasks 7 and 8; these three refusals are the narrower "this cannot be encoded without losing content" class. | R2.9, R2.12, Tasks 2/7/8 |
| 2026-08-18 | **(implementation) `strset(list())` must equal `strset(character(0))`.** `[]` is the parsed-JSON spelling of an empty string set, and R2.5 write/read agreement requires both spellings to hash equal, so the R2.17 pin covers the parsed form too. Same shape of reasoning as R2.13 one level down. | R2.17, R2.5 |
| 2026-08-18 | **(implementation) two mechanical details, recorded because both are easy to get wrong on a re-read.** (1) Intermediates are **raw 32-byte vectors, not hex**: hex appears in exactly the two places the spec names it -- the member collation key and the final `data_sha`. Byte order and lowercase-hex C-locale order agree, so the collation claim holds either way. (2) The `NA` refusal sits **after** the type gate, with an all-`NA` logical caught ahead of it, because `is.na()` on a closure warns rather than answering -- a `tags = list(t = mean)` fixture otherwise emitted a warning against a suite held at WARN 0. A bare `NA` is logical, so it still gets R2.7's "omit the field" advice rather than a type error. | R2.7, `R/hashable-set.R` |
| 2026-08-18 | **(implementation) AC13-P is asserted through the real local-backend store**, not a hand-rolled `jsonlite` round trip, so the fixtures also prove the production write/read path preserves `members[]` as a list of records. That structural condition (the one residual of R2.5) is additionally asserted **on the parsed object** rather than inferred from the hashes matching, since a hash match cannot distinguish "structure preserved" from "two different structures that happen to hash the same". | R2.5, AC13, Task 2 |
| 2026-08-18 | **Cold-start audit for Task 3: enough context to start, after four additions.** The documented path (`dev/README.md` -> this state block -> the task -> `dev/engineering-notes.md`) was walked as a fresh reader and every claim checked against the tree. What was missing: **(1)** no file was named for the two exports -- decided **`R/storage.R`**, whose header already states the family contract, rather than a new file; **(2)** "the established bare-git-remote + local-store style" was a description with no citation, so it is now a pointer to a concrete exemplar (the example block above `R/storage.R:51`, used verbatim by all four existing storage exports); **(3)** "relative-key validation" implied a helper that **does not exist** -- `R/utils-validate.R` has only `.datom_validate_name()` (`R/utils-validate.R:18`) and `.datom_validate_sha()` (`R/utils-validate.R:68`) -- and the two things it must catch are different in kind, a traversal/shape concern that applies to **both** exports (reads are unrestricted as to *managed keys*, not as to escaping the namespace) and the full-key-where-relative-belongs case that silently double-prefixes rather than erroring; **(4)** no fixture or pkgdown location was named. Also recorded: **no `datom_storage_*` export checks `conn$role`**, including the destructive delete, so adding one here would break a family symmetry deliberately; `.access` appears nowhere in `R/`, so R19.6's by-construction claim verifies today; and P18 is satisfied by the managed-key refusal, not by any git interaction, so nobody should try to git-gate a byte-level primitive. | Task 3, R12.4a, I7, P18 |
| 2026-08-18 | **Two Task 3 decisions deliberately left for DESIGN rather than settled here.** (a) Whether the payload-key refusal is **existence-dependent** (R12.4a's literal wording, one storage probe per write) or **shape-only** (simpler, stricter, cheaper, and not defeatable by writing a payload before its artifact exists). Recommendation is shape-only -- a refusal is cheap to relax and a hole is expensive to find -- but it narrows a stated requirement, so it gets an explicit decision instead of a quiet reinterpretation. (b) How strict "payload-shaped" is: `{name}/{64-hex}` versus `.datom_validate_sha()`'s 6-64 hex range, which decides whether a downstream package may write `myset/abc123.json` as scratch. Both are public-contract choices of the same class as review finding F3, which is what produced R12.4a. | R12.4a, AC23, Task 3 |
| 2026-08-18 | **A trap noted for Task 3's docs**: the write export's roxygen example must use an **unmanaged** key. The natural-looking `"dm/abc.json"` after a `datom_write(name = "dm")` is precisely what the new guard refuses, so an example copied from a sibling export would abort under `R CMD check` -- a self-inflicted AC11 failure. | AC23, AC11, Task 3 |
| 2026-08-18 | **`CRAN-SUBMISSION` is not a tracked record and never was.** Verified with `git log --all -- CRAN-SUBMISSION` (empty) and its absence from `origin/main` and `origin/dev`, correcting the assumption that `main` held a submission record to protect. Per usethis, the file is a handoff artifact from `submit_cran()` that `use_github_release()` consumes and **deletes**, and **in its absence usethis assumes HEAD is the submitted state** -- so with the old acceptance order (merge `dev` into `main`, then tag) a missing artifact would silently name the merge commit rather than the submitted one. Resolved on this branch: `/CRAN-SUBMISSION` added to `.gitignore` (it sat untracked *and* un-ignored, so `git add .` could have carried it to `main` by merge -- newly relevant with Task 12 adding an add-all verb), `dev/README.md` gained a `CRAN-SUBMISSION` section plus a submitted-SHA table, and acceptance step 4 now publishes the release **before** merging. The artifact itself was left untouched. | dev/README.md, `.gitignore` |
| 2026-08-18 | **THE JSON WRITE EXPORT IS DROPPED -- owner-decided, and it dissolves both pending Task 3 decisions.** `datom_storage_write_json()` will not be built; Task 3 ships `datom_storage_read_json()` alone. **Owner-raised, and the challenge was the right one**: writing should be spelled `datom_write_set()`, and JSON is datom's internal design choice rather than a public surface. Verified before agreeing: the export's stated motivation in #89 was "a downstream package cannot write its own document into datom's namespace", the document was a set, and Task 9 now writes sets as first-class artifacts -- so **no consumer remains**. `datomanager` does not need it either: the Authority Principle in `dev/datomanager_scope.md` says "data-repo mutations always route through datom ... datomanager never touches the data repo directly", and its expression is a **purpose-built verb per need** (`datom_repo_set_data_store()`, `datom_repo_delete()`, `datom_repo_attach_governance()`), with the `governance.json` data-side mirror as the precedent for choosing a named export over a generic write. **A claim of mine was wrong and the owner caught it**: I said "datomanager does its own storage IO", which is true only of the **gov** namespace -- the `dev/README.md` backlog line I was paraphrasing has been corrected to say so. Retired with the export: R12.4a, I14, AC23. Restated: P18 (now satisfied because no general-purpose write exists, not because one is fenced) and R19.6 (`.access/` stays safe **by construction**, since datom adds no write path at all). Retained verbatim for revival: R12.4a's refusal analysis. **Deferral is the cheap direction** -- additive to add later, breaking to remove after release. | R12.4, R12.4a, I14, AC23, P18, R19.6, Task 3 |
| 2026-08-18 | **The one argument that survived for the write export, recorded as the Backlog trigger.** datomanager will need s3/local dispatch to write JSON into its **own gov namespace**, and reimplementing that duplicates platform code. That is a **different export** -- gov-scoped, with no managed-key refusal list -- for a package that does not exist yet, so it is speculative capability today. If the trigger fires, scope it to the caller's own namespace and **re-derive** the refusal list rather than assuming R12.4a's still fits. | R12.4a, `dev/README.md` Backlog |
| 2026-08-18 | **Process note: a review can be right about a hazard and still miss that the capability is unnecessary.** Review finding F3 correctly identified that a public JSON write could clobber managed keys, and its resolution (R12.4a's refusal list, I14, AC23) was sound *given* the export. What no round asked was **who still needs this export** -- a question that only had a new answer because `datom_write_set()` had since been specified. Recorded because the failure mode is invisible from inside a hardening exercise: every subsequent review inherits the premise that the capability is wanted. | design.md 18 (F3 row), R12.4a |
| 2026-08-18 | **The parity workflow was extended in place, as instructed, and its file name deliberately still says cv1.** It now runs both reference scripts and both parity test files across the x86_64 + arm64 matrix, keeping one matrix for a property that spans architectures, and it prints the sv1 goldens beside the cv1 ones so a divergence between jobs is readable in the logs rather than only as a failed expectation. The file keeps its name so existing links and any branch protection stay valid; the header comment now says it covers both regimes. | `.github/workflows/cv1-reference-parity.yaml`, R2.4, P12 |
| 2026-08-21 | **(implementation) the absent-key abort costs one extra storage round trip, on purpose.** `datom_storage_read_json()` probes `.datom_storage_exists()` before reading so the "not found" message is identical on both backends and names **the relative key the caller passed**. Without it the two backends diverge in the worst place: the local backend aborts clearly, while S3 surfaces the provider's own error naming the **full** key -- so a caller whose actual bug is key-shape confusion gets shown the very transformation they got wrong. Recorded because the probe looks like a redundant call to anyone optimizing reads later. | Task 3, `R/storage.R` |
| 2026-08-21 | **(implementation) the full-key refusal keys on a `datom` path segment, and that is exact rather than heuristic.** `datom` is in `.datom_reserved_names` (`R/utils-validate.R:2-6`), so it can never appear as a segment of a legitimate relative key -- which is what makes a cheap segment test a complete one for the double-prefix hazard. Also pinned in tests: the traversal guard fires on a whole `..` **segment**, not on the dot character, so `.metadata/manifest.json`, `my.data/abc.json` and `dm/..hidden.json` all remain valid keys. Worth stating because the tempting implementation is `grepl("\\.\\.", key)`, which would refuse datom's own metadata directory convention. | Task 3, `R/utils-validate.R` |
| 2026-08-21 | **(implementation) `.datom_validate_rel_key()` is deliberately NOT folded into the Task 1 key builders**, and the reasoning is the inverse of Task 1's own approved scope deviation. There, folding `.datom_validate_sha()` into a builder closed a real gap because a **file-supplied** sha reached a key unvalidated. Here there is no gap to close: the builders compose keys from parts already validated (`.datom_validate_name()` admits only `[a-zA-Z0-9_ ()-]` and must start with a letter; `.datom_validate_sha()` only hex), so their output cannot contain a `..` or `datom` segment and the check would be dead code. The distinction to carry forward is **composed from validated parts** versus **supplied whole by a caller** -- only the second needs a key validator, which is why the new export is its only call site. | Task 3, Task 1, I9 |
| 2026-08-21 | **(implementation) the no-role-check decision is now pinned by a positive test**, not left as an absence. A `role = "reader"` conn reads successfully, so the `datom_storage_*` family's policy-free symmetry (not even the destructive `datom_storage_delete_prefix()` gates on role) fails loudly if a future change breaks it. Same reasoning as Task 6's note that a silent failure mode needs a positive assertion rather than the absence of errors. | Task 3, Task 12 |
| 2026-08-21 | **The schema check covers SIX call sites, not the four Task 4 named -- owner-decided.** The task listed the reader paths that read through storage. The same manifest is also read from the **git clone** by `datom_sync_manifest()` and `.datom_status_input_files()`, and that copy goes ahead of the installed build by an ordinary route: a collaborator upgrades datom and writes, this developer pulls. The original justification for excluding them ("the spec says reader side") was scope citation rather than a reason, and did not survive being asked for. The four **in-pipeline** local reads stay excluded on a stated principle: the check belongs where a document **enters** datom, so a refusal happens before work starts rather than partway through a write. | R9.2, Task 4 |
| 2026-08-21 | **The WRITE-side schema check is Task 6's, not Task 4's -- owner-decided.** An **older** build writing into a **newer** repo is the more damaging direction: after the `artifacts` rename it would add `tables`-shaped entries to an `artifacts` manifest, leaving one file half in each format, where the read-side failure is merely a wrong or empty answer. Deferred rather than bolted on because a write is several steps (local files -> one commit -> storage mirror) and the check must sit ahead of **all** of them -- aborting mid-pipeline leaves a half-finished write, which is worse than the disagreement being prevented. Task 6 has those steps in view; Task 4 did not. | R9, Tasks 4 + 6 |
| 2026-08-21 | **(implementation) placing the check relative to existing error handling is the actual difficulty of Task 4, and gets a different wrong answer at each site.** Three of the six readers wrap their manifest read in a handler that softens failures. Inside it, `datom_list()` and `datom_summary()` reword the upgrade instruction as "Could not read manifest" -- demoting the one actionable line to a footnote under a wrong headline. `datom_status()` is worse: its handler turns errors into `available = FALSE` and continues, so that one command would have stayed **silent** while the other five stopped, which is precisely the degradation R9 exists to end. All three now read inside the handler and check outside it. A companion test pins that an ordinary storage failure is **still** tolerated by `datom_status()`: making the schema check fatal must not make an unreachable bucket fatal. | R9.1, R9.2, Task 4 |
| 2026-08-21 | **(implementation) two condition classes, so "all six behave consistently" is provable rather than asserted.** `datom_schema_unsupported` for a too-new document, `datom_schema_invalid` for a present-but-unusable value. Every call site's test asserts the **class**, not message text, which is what makes a future divergence at one site fail loudly. Recorded because the question that produced it -- "can you confirm all six behave consistently?" -- could not be answered from the code as it stood: the answer was no, and the three softening handlers were why. | Task 4 |
| 2026-08-21 | **(implementation) a present-but-unusable `schema_version` aborts rather than being coerced**, which R9's pseudocode did not cover. Two reasons, either sufficient: `as.integer("two")` is `NA` and `NA > 2` surfaces through `if()` as "missing value where TRUE/FALSE needed" -- an internals-looking error for what is really a corrupt file (the same `nzchar(NA)` class already recorded in `dev/engineering-notes.md`); and an uncoerced string comparison against a number can read as *supported* by accident. Refused: non-numeric, `NA`, fractional, below 1, non-scalar, logical, list. | R9, Task 4 |
| 2026-08-21 | **(implementation) the constant is `.datom_supported_schema`, and its leading dot is a cli trap.** R9 writes `SUPPORTED_SCHEMA`; house style for internal constants is dot-prefixed (`.datom_reserved_names`, `.datom_import_formats`), so R9's spelling is read as pseudocode. The dot then makes `{.datom_supported_schema}` a **cli style** rather than a value inside a message string -- it must be spliced `{(.datom_supported_schema)}`, the same trap already recorded for `{.val {(.datom_import_formats)}}`. A test asserts the ceiling renders as `v2` rather than disappearing into markup. | Task 4, `dev/engineering-notes.md` |
| 2026-08-21 | **(implementation) adding `schema_version` + `document_sha` to the `volatile` list is inert for every document already written**, since no metadata carries either field yet -- so I4 holds by construction, with no migration and no re-minted versions. Pinned by a test that presence-versus-absence of both is immaterial to `metadata_sha`, rather than inferred from the suite staying green. The roxygen paragraph above the list, which enumerates each excluded field **and its reason**, was updated in the same edit: leaving it stale is the Task 1 defect class exactly. | I4, R7.4, R9.3 |
| 2026-08-21 | **(implementation) the version boundary is strictly greater-than, with its own test.** At `>=`, the entire read path would break the moment Task 6 writes `schema_version: 2` -- a one-character defect that no other test in this task would catch, since every other fixture is either far newer or absent. | R9.1, Tasks 4 + 6 |
| 2026-08-21 | **Spec code citations were re-derived after Task 4 shifted line numbers in five files**, including every site in Task 6's nine-site checklist -- left stale, the next session would have opened the wrong lines while following an instruction that says to cite rather than re-derive. Verified **by content** (`SPEC_CHECK_SHOW_CITATIONS=1`), not by arithmetic, which is how two pre-existing off-by-ones were found. Bare numbers inside historical log rows were deliberately **not** touched (e.g. the 2026-08-17 row recording `R/read_write.R:217 -> 227`): they record what was true on that date, and rewriting them would falsify an audit trail to fix a number nobody follows. Check 4 only asserts a cited line **exists**, so it cannot catch this class -- content review is still required after any insertion into `R/`. | dev/check-spec.R, Task 6 |
| 2026-08-21 | **`.kiro/steering/communication.md` added (not a task).** Task 4's design round needed three restatements before it landed, all for the same reason: responses led with spec vocabulary (`gate`, `R9.2`, `AC7`) and assumed the owner held the spec in working memory. The rule captures what worked -- explain the thing before naming it, 1-2 sentences per point, questions in their own tagged section, reasons rather than scope citations -- and is scoped to **chat responses only**, explicitly not to `R/` comments, roxygen, spec documents, or commit messages, which keep the existing conventions. | `.kiro/steering/communication.md` |
| 2026-08-21 | **Cold-start audit for Task 6: startable as written, after two corrections.** The documented path was walked as a fresh reader and every claim verified against the tree. The nine-site enumeration holds. **(1) `datom_validate()` does not read `manifest$tables`** -- its only manifest read is `.datom_validate_project_name()`, which looks at `project_name`, and `.datom_validate_tables()` enumerates from a **storage listing** instead; the escalation rationale named it anyway, which would have sent a reader hunting in a file with nothing in it. Rationale corrected to name `datom_status()`, which does read the key. **(2) Three decoy sites** are return-value fields also called `tables` -- `datom_sync()`'s result (`R/sync.R:171`, `R/sync.R:208`), `datom_validate()`'s (`R/validate.R:184`), `datom_status()`'s (`R/query.R:495`). A `grep tables` sweep hits all three, and renaming them is a separate breaking change to three public return shapes that R8 does not ask for. Recorded because the rename's failure mode is silent either way: touch them and three return shapes change unannounced; miss a real site and the list just reads empty. Also recorded: the test surface spans ten files, so the fixture sweep is the bulk of the chunk. | R8.1, Task 6 |
| 2026-08-23 | **E2 DESIGN AUDIT -- BLOCKING GAP: there was no v1-to-v2 transition, and the rename would have blanked discovery on every existing repo.** Verified in the tree before acceptance. An existing manifest keeps its list under `tables` and declares no `schema_version`; `.datom_check_schema_version()` tolerates the absence as v1, so the document passes and the reader then finds nothing under `artifacts` -- `datom_list()` empty (`R/query.R:94`), `datom_summary()` zero (`R/summary.R:69`), `datom_status()` zero (`R/query.R:488`), no error. `datom_read()` is unaffected (`R/read_write.R:93`), so it is a discovery blackout, not data loss -- **silence is the disqualifier, not severity**. Nothing self-heals it: `.datom_update_manifest_entry()` stamps no version on either branch, and a no-change write returns at `R/read_write.R:787` before the manifest is touched. **Design.md section 11 does not cover this** -- it analysed an old reader meeting a new repo, where the recourse is "upgrade"; here the upgrade is the cause. Two things recorded as met by Task 4 were falsified by the queued rename: **P10** and AC7's tolerate-older half. | **R22** (new), I28/I29/I30, P10 restated, P34/P35, AC30/AC31/AC32, design.md 10.1/10.2 |
| 2026-08-23 | **OWNER-DECIDED: read upgrades in memory, write upgrades on disk.** `read -> upgrade in memory -> use` leaves the file alone; `read -> upgrade in memory -> edit -> stamp -> write` changes it. The decisive argument is **who can act**: a loud refusal would be the posture's usual preference, but a reader holds storage credentials and no clone, so refusing a v1 manifest strands the population least able to repair it until some developer happens to write. Three alternatives rejected in design.md 15 with reasons: an inline `%||%` fallback (five copies of the same logic, the next schema change misses one silently), refuse-plus-repair-verb (readers cannot repair), and a clean break on pre-release grounds (the `datom-cv1` precedent does not carry -- that break was in content identity, which a re-export regenerates, and the manifest has no rebuild verb; a break must also be loud, which costs the detection step, leaving the transform only a few lines more). | R22.2/R22.3, design.md 10.2 + 15 |
| 2026-08-23 | **OWNER-DECIDED: Phase B splits into Task 5 (contract-neutral) and Task 6 (the rename); old Tasks 6-16 shift to 7-17.** As one task it carried a nine-site rename, the inherited write-side refusal, five counter filters, two read consolidations, the transition above, and a fixture sweep across ten test files -- and its failure mode is silent, so a green suite would not have distinguished working from broken (Operational Discipline rule 3: ambiguous scope before starting is the signal to split). Task 5 creates the one reader and the one skeleton builder and changes nothing observable, so the upgrade has a single place to live instead of five; Task 6 then renames the key there. Renumbering was done in descending order and every `Task N` reference across the three spec files was repointed, including historical Decisions rows -- unlike stale *code* citations, a stale task number points a reader at the wrong task rather than merely recording what was once true. **`dev/check-spec.R` gained check 8** for exactly this: every `Task N` reference must resolve to a task that exists, verified by reintroducing a dangling reference and confirming a FAIL. | tasks.md Phase B, dev/check-spec.R |
| 2026-08-23 | **The upgrade's shape: one step per adjacent version pair, and a shipped step is frozen** (I30). A dispatcher reads the declared version and applies every step up to current, in order, so a v1 file on a v3 build runs v1-to-v2 then v2-to-v3. No direct v1-to-v3 function is written -- one-per-pair grows with the square of the version count and gives the two paths somewhere to disagree. A released step is never edited, not even to tidy it: it is written against files that exist unchanged in the world, and mis-converting one yields a well-formed file for the wrong version, which is silent. Same discipline as the frozen sv1 goldens, for the same reason -- the inputs are no longer in our hands. | R22.5, I30, P34 |
| 2026-08-23 | **The failure-kind split, which replaces a comment with structure.** The shared reader **returns** an IO failure as data and **throws** a schema refusal. Task 4 found three readers wrapping their manifest read in a handler that softens failures, and a check placed inside one reworded the upgrade instruction as "could not read manifest" while `datom_status()` downgraded it to a warning and continued; Task 4 held the line with a comment at each site. Returning one failure and throwing the other removes the handler the check could be placed inside, while callers keep their differing IO policies because the IO outcome is a value they inspect. AC32 tests both halves together, since the regression is a trade between them. | R22.4, P35, AC32 |
| 2026-08-23 | **OWNER-DECIDED: no missing-`kind` fallback in the counters.** Filter on `kind == "table"` and add no "or absent" arm. Every entry has a `kind` by the time a counter runs, because the upgrade stamps it -- so the fallback would only ever fire on a read path that skipped the upgrade, and it would make that mistake produce roughly-correct numbers instead of visibly wrong ones. A safety net that catches the one failure we want noisy is worse than none. One line, reversible if a real case for tolerance appears. | R22.8, design.md 15 |
| 2026-08-23 | **OWNER-DECIDED: "surface `kind`" means two different things.** `datom_list()` returns per-artifact rows, so it gains a `kind` column -- **including both empty-result returns** (`R/query.R:94,103`), which already omit `current_data_sha` that populated rows carry, so the column set has drifted there once already. `datom_summary()` has no per-artifact axis: it gains `set_count` beside `table_count` plus a line in `print.datom_summary()`, and `table_count` keeps its tables-only meaning. Recorded because "surface `kind`" was undefined for an aggregate object and would otherwise have been settled by whoever typed first. | R8.4, Task 6 |
| 2026-08-23 | **Three audit corrections of substance, each verified against the tree.** (1) **Five counters widen to include sets, not three**: the three in the summary block (`R/sync.R:1016,1017,1020`) plus two computed independently of it -- `datom_summary()`'s `table_count` (`R/summary.R:69`) and `datom_status()`'s count (`R/query.R:488`), both of which count entries rather than reading the summary. No test catches any of them until a fixture contains a `kind: "set"` entry, because there are no sets until Task 9. (2) **The write-side refusal must sit above the two routing returns** at `R/read_write.R:702` and `R/read_write.R:706`: `.datom_sync_data_metadata()` mirrors the whole local manifest to storage (`R/sync.R:177`) without reaching the manifest-writing step, so a check after the router misses it -- and it needs the *manifest*, which `datom_write()` never reads. (3) **`.datom_check_schema_version()`'s message says "which this build cannot read"** (`R/utils-validate.R:269`), which is wrong on a refused write; give it an operation word or accept it knowingly. | Task 6, R22.3 |
| 2026-08-23 | **Two v1-compatibility tests must survive Task 6's sweep, and a third has to be added.** `datom_list` / `datom_summary` "tolerates a manifest with no schema_version" (`test-query.R:894`, `test-summary.R:163`) each build a `tables` block **with an entry** and assert a non-empty result; rewritten to `artifacts` they go green while asserting nothing, and the regression ships clean. The cold-start audit's two fixture categories (sweep, or leave as a decoy) did not cover them, so a **third category** exists: v1-compatibility fixtures, which stay on `tables` and keep asserting non-empty. The same-named `datom_sync_manifest` test (`test-sync.R:1283`) is **not** one of them -- its block is empty, so it passes either way -- which means the clone-copy readers have no old-format coverage at all and need a new test. Made structural rather than remembered by moving the evidence into a frozen file (R22.7). | AC30, R22.7, Task 5 |
| 2026-08-23 | **E2 discharged without a model switch, and recorded so the flag does not read as unaddressed.** The working model is already the most capable one available to the owner, so the escalation is answered by an independent close review of the spec before implementation, owned by the owner. The design spot-check half of the trigger was performed and produced the eight rows above; the purity-audit half still applies **after** Task 6 lands. | design.md 12 (E2) |
| 2026-08-23 | **One audit claim was overstated and is recorded as such.** The review argued that leaving the local-manifest read duplicated means "a repo with no local manifest reports every input file as new". True mechanically, but close to unreachable: `.datom/manifest.json` is git-tracked, so any clone has it, and it is absent only before init or after someone deletes it. The consolidation is still worth doing because Task 5 touches those sites anyway and the dangerous write-side skeleton lives in the same group -- but the justification is one-place-to-change, not a live bug. | Task 5 |
| 2026-08-23 | **The renumber's own defect pattern, caught by reading rather than by the gate.** Two places held task numbers the mechanical sweep could not see, both because the number is not written as `Task N`: the **New exports** table's bare `Task` column (`datom_member()` said 7, now 8; `datom_write_set()` 8 -> 9; `datom_read_set()` 9 -> 10; `datom_repo_commit()` / `datom_repo_push()` 11 -> 12; `include_paths` 12 -> 13) and two spelled-out counts of `check-spec.R`'s own checks ("eight", and "Six checks" in `dev/README.md`, the latter already stale by one before today). Check 8 cannot see either, and its comment says so. Same class as the five review rounds recorded above: **a change swept some places and left others stating the old thing.** The countermeasure that works is the one already written into this spec -- never restate a count or a range, derive it -- so the exports table now carries a line telling the next reader to re-derive from the task headings. | dev/check-spec.R (check 8 limitation), tasks.md exports table |
| 2026-08-23 | **OWNER-DECIDED: `kind` entering identity is accepted.** Because it is semantic, the first write after upgrading mints a `metadata_only` version for every existing table -- same content, same storage address, parquet reused, nothing re-uploaded. Accepted as a bounded one-time cost in the safe direction: it produces an extra version rather than changing an existing one, so the reproducibility guarantee is not violated. The alternatives were closed off before the decision: `kind` cannot be excluded from the hash (a table and a set could then share a version identity) and cannot live only in the manifest (AC4's cross-kind check reads it from per-artifact metadata precisely because the manifest can lag a partial write). Recorded because nothing in the spec acknowledged it and it is the shape #72 was fought over -- a package upgrade producing versions. | R1.1, Task 7 |
| 2026-08-23 | **OWNER-DECIDED: stamp the schema number always, increment it only on a break.** Review had these as one question and they separate cleanly. Stamping costs nothing -- the field is excluded from identity, so a stamped file mints no version -- and it lets any build state what shape it holds; the owner's framing was good housekeeping. Incrementing costs every pinned build its access to everything written afterwards, because the check is a refusal. So the number moves only for a rename, a removal, a meaning or type change, or a container restructure; an added field leaves it alone. **This supersedes the recommendation earlier the same day to leave per-artifact metadata unstamped** -- that concern was right about the harm and wrong about the cause, which is incrementing rather than stamping. The test is written into R9.5 as a table so it is not a judgment made under release pressure, and the call is made at design time alongside the escalation flags. Also **corrected in the same round**: an earlier claim that stamping costs *current* pinned readers their access was wrong -- no released build checks the number at all, so the entire cost is for builds from this release onward. | R9.5, design.md 10.3 |
| 2026-08-23 | **Publish the schema-to-package mapping** (R9.6). One schema version spans many releases, so neither `schema_version` nor `datom_version` answers the only question a refusal raises -- *which datom do I need?* A table in the package docs maps each schema version to the release range that reads it. Filed as [#103](https://github.com/amashadihossein/datom/issues/103) rather than built here. | R9.6 |
| 2026-08-23 | **REJECTED: a declarative transform file travelling with the repo**, so an older build could translate a newer manifest back to the shape it knows (owner-proposed, and the strongest alternative considered). Merits acknowledged: it is data rather than code, so nothing is executed from a data store; it composes exactly as the forward chain does; and it can hide a new concept so an old build never learns sets exist. Rejected because **the interpreter must ship in the old build**, so it cannot help anything already released -- the wall it was meant to remove; because **the mapping format is frozen the day it ships**, so the first thing it cannot express leaves us where we are today with a language to maintain as well; because a rename map covers renames and moves but not meaning changes, container restructures or concept splits, and supporting those means designing a language; and because **the cost is the testing** -- worth nothing unless CI installs historical releases and reads current repos through them, a matrix that grows every release and is the first thing dropped under deadline. Decisive: its own simplest case, dual-write, delivers most of the value with none of the machinery and does work for released builds -- specified in [#102](https://github.com/amashadihossein/datom/issues/102), to be built only when a break needs it. | design.md 15, #102 |
| 2026-08-23 | **The division that came out of this round, and the most durable thing in it: the manifest may break, per-artifact metadata may never.** The manifest is **derived** -- every fact in it also lives in per-artifact metadata or the storage listing -- so a build that cannot read it can rebuild one, which is what makes an escape hatch possible. Per-artifact metadata **is** the source of truth: nothing can rebuild it, and a legacy-shaped second copy hashes differently from the recorded version (`R/read_write.R:342` recomputes identity from the stored file), so dual-write there would help old readers by making older writers mint a version on every run. **This spec has the division the right way round by accident** -- it breaks the file with a hatch and only adds to the file without one. Recorded so the next change has that shape on purpose. Written into `.github/copilot-instructions.md` so it outlives this feature. | R22.9, design.md 10.4 |
| 2026-08-23 | **Forward compatibility is a writer-side problem, and the four rules that follow from it.** A new build can always read old files, because it knows both shapes; an old build can only read new files if the writer left it something it already understands. Nothing can be retrofitted into an installed package. So: (1) additive only by default; (2) a field's name and meaning are fixed forever; (3) dual-write with a declared sunset when a break is genuinely unavoidable; (4) the schema number is the alarm for when 1-3 failed, not the mechanism. Recorded in `.github/copilot-instructions.md` rather than here, since it governs every future change and not just this one. | `.github/copilot-instructions.md` |
| 2026-08-23 | **Found while vetting "additive changes are free": they are free for readers and NOT for writers, because identity hashing uses a denylist.** `.datom_compute_metadata_sha()` hashes every field in the document minus a list of seven to ignore (`R/utils-sha.R:415-416`). A build that has never heard of a field cannot know it was meant to ignore it, so it folds the unknown field into the hash, disagrees with the recorded version, and reports a change on content that did not move -- on **every run**, not once. Remedy is an **allowlist**: hash a named list of fields and ignore anything else. Set the list to the fields hashed today and every existing identity is byte-identical, so it is behaviour-preserving now and forward-compatible later. Honest limit: it makes *bookkeeping* additions free (the common case) and not *semantic* ones, so the `kind` cost above stands. Filed as [#100](https://github.com/amashadihossein/datom/issues/100) -- not sets work, and it touches the identity function every artifact depends on. Paired with [#98](https://github.com/amashadihossein/datom/issues/98), which removes the JSON emitter from the same function: one identity-affecting change to verify instead of two. | R9.5, #100 |
| 2026-08-23 | **`original_format` is manifest-only, which would make a manifest rebuild lossy.** Verified: it is written into the manifest entry (`R/sync.R:1002`) and never into per-artifact metadata, so it is the one manifest field not recoverable from a storage listing plus per-artifact files. Rather than accept a lossy rebuild, persist it into metadata -- additive, and free once identity hashing uses an allowlist. Bundled into [#101](https://github.com/amashadihossein/datom/issues/101), since the rebuild is what makes it matter -- and ordered after #100, because persisting a metadata field is only free once identity hashing uses an allowlist. | R22.9, #101 |
| 2026-08-23 | **RENUMBER SHIFT RECORD, and the policy that replaces sweeping.** The 2026-08-23 Phase B split moved **old Tasks 6-16 to 7-17**; Task 5 became Task 6 and a new contract-neutral Task 5 was inserted. **This is the last sweep of historical rows.** From here, dated Decisions rows are **FROZEN**: a renumber adds one shift record like this one and touches nothing else. Reason: three renumbers produced three crops of stale references, and the last one left a row *half* swept -- three references bumped, two not -- so it read as a claim about a task that did not exist on its date. A shift record is self-maintaining; a sweep never is. The pre-existing 2026-08-11 row mixing three numbering generations ("new Task 15 ... Old 14/15 -> 15/16") is left as the illustration. Reconciled once today rather than reverted to as-of-date numbering, because prior rounds had already swept most rows and finishing one half-done sweep is smaller and safer than undoing three. `dev/check-spec.R` check 8 now **notes** how many `Task N` references sit inside dated rows, as a reminder at the moment a renumber is happening. | tasks.md, dev/check-spec.R |
| 2026-08-23 | **DESIGN A: the manifest's schema number keeps bumping and stays true to the shape.** For the manifest specifically the **reader's** response to a too-new number becomes **warn and rebuild**; a **writer** still refuses. Design B (manifest carries no number; dispatch by shape) rejected on three grounds, the third decisive: it would stamp then freeze the number, so a file would read v2 while carrying a v5 shape; it would leave the upgrade chain with one step forever, paying for a generality never exercised; and **it cannot distinguish corruption from the future** -- a truncated manifest and a future-shaped manifest both present with the expected key missing, so both would rebuild, contradicting the requirement that a corrupt manifest still fails visibly. The number is the only thing separating the two. **Task 6 bumps to 2, unchanged.** Note this supersedes a proposal from the same review round to never bump for a manifest shape change once the rebuild exists. | R9.5 (per-file rule), R22.11, design.md 10.5, AC37 |
| 2026-08-23 | **OWNER-DECIDED: writer refusal is a VOCABULARY check, not a version comparison.** A build refuses a write when a datom-owned document carries a **top-level** key it cannot classify -- neither in its identity list nor on its documented excluded list. Evidence-based: no version comparison, no configuration, no network. Chosen over a declared minimum writer version as the primary mechanism for one reason -- **it cannot be forgotten.** A floor protects a repo only if somebody remembers to raise it; the vocabulary check fires on the evidence regardless. The objection that this makes every addition writer-breaking, contradicting "additive changes are free", was **raised and overruled**: writes are infrequent, done by few people, and change content, so **a false refusal costs one person an install while a miss costs corrupted data**. Refusing too often is the right direction to err. | R23.1, R23.6, design.md 10.6, AC35 |
| 2026-08-23 | **The vocabulary list is APPEND-ONLY, with the same weight as a frozen upgrade step.** No build may stop recognising a field name that has ever existed, **including names it no longer writes**; retire by marking, never by deleting. A build that forgets a name meets an **older** file, fails to classify a key it should know, and refuses it -- **blocking the upgrade direction, the one direction that must always work.** Corollary recorded so nobody codes around it: the good direction is **structurally safe**, because a newer build's vocabulary is a superset of every older one's, so the check cannot fire on the upgrade path. No directional logic; a guard for it would be dead code guarding an unreachable state. | R23.2, R23.2a, I31, P37 |
| 2026-08-23 | **Coverage is complementary; neither mechanism is sufficient alone, and saying so is part of the requirement.** The vocabulary check catches **additions and renames**. It cannot catch **removals** (the old name is still in an append-only vocabulary, so nothing looks unrecognised), **type or meaning changes**, or **container restructures** -- none of which introduce a new name. Every one of those bumps the schema number by R9.5, so the version check catches them. A **policy block for a non-format reason** is caught by neither and is the floor's own case. | R23.5, R9.5 |
| 2026-08-23 | **OWNER-DECIDED: the floor ships its READING half in 0.1.1; everything else about it is deferred.** One **optional** `project.yaml` field, absent meaning no floor so no existing repo changes behaviour; it rides on the conn since `datom_get_conn()` already parses that file; compare and refuse at the write entry; one guard, that whoever sets it must already satisfy it. Deferred: the purpose-built raising verb (agreed in principle, consistent with the R15 named-verbs precedent -- a normal commit cannot validate that the raiser satisfies the new value), tooling, docs. **Reason the reading half cannot wait**: a build that does not look for the field can never be bound by it, which is precisely why nothing can stop a 0.1.0 writer. Its trigger cases, recorded so a later reader knows why it exists: a **meaning** change that adds no field, and a policy block for a non-format reason ("0.1.4 wrote bad hashes"). | R23.3, R23.3a, AC36 |
| 2026-08-23 | **#100's justification changed and the old one must not survive into the code.** Filed as "older writers keep working". After the vocabulary decision they do not, by design. What the allowlist now buys: **readers compute correct identities, and a repo does not accumulate spurious versions.** Both still hold. Recorded because a stale rationale in a comment outlives the discussion that produced it. | #100, Task 19, design.md 10.6 |
| 2026-08-23 | **Three corrections accepted from the reviewing side, each verified against the tree first.** (1) The `seq()` loop-guard finding was mis-attributed: **there is no `seq(` anywhere in the three spec files**, so a sketch written in conversation had been reclassified as a defect in a written artifact. It is implementation guidance -- guard the loop, test that a current-version document runs zero steps -- not a spec fix (R22.10). (2) The rationale for carrying unknown fields forward was wrong: churn settles after one version per handoff **either way**, because a build that deletes the field agrees with itself on its next run. The real argument is **information loss**, so the test asserts a round trip rather than a version count (R23.8, AC34). (3) The connectivity concern was overstated: `.datom_git_push()` **aborts** on push failure (`R/utils-git.R:267-277`) and the storage steps are 8-10, after it, so a write cannot reach storage without a successful push -- warn-and-proceed at the door is defensible with the push as the backstop, and the residual is narrow (fetch fails, push succeeds). | R22.10, R23.8, design.md 10.7 |
| 2026-08-23 | **Found and scheduled as its own fix: `.datom_check_git_current()` does not return early on a failed fetch.** `return(invisible(TRUE))` sits inside the `tryCatch` **error handler** (`R/utils-git.R:422-429`), so it returns from the handler rather than the function; execution continues and compares `HEAD` against **stale cached** upstream refs. An offline user whose cached upstream is ahead gets a hard **abort** where the comment states network errors should not block offline work. A live defect independent of this spec -- and Task 21's write-entry sequence is proposed to sit on that function, which is why it is Task 18 and lands first. Filed as [#104](https://github.com/amashadihossein/datom/issues/104). | Task 18, #104 |
| 2026-08-23 | **Scope filter for 0.1.1, and the five items it selects.** The filter: *does deferring it postpone the cost, or permanently exclude every install shipped meanwhile?* Five items only ever help builds that already contain them -- allowlist hashing, carry-unknown-fields, the writer refusals, the floor's reading half, and the rebuild -- so deferring any one strands every 0.1.1 install forever. Everything else from this review round (bump rules, the schema history table, policy prose, the floor's tooling) lands later without stranding anyone. **If 0.1.1 gets crowded, those slip; these five do not.** #101 pulled into 0.1.1 on exactly this basis. Appended as Phase E rather than inserted, to avoid a third renumber; execution order is stated in the phase preamble and in the state block, because appended does **not** mean last. | tasks.md Phase E |
| 2026-08-23 | **The write-path entry sequence is fixed in one place** (design 10.7): fetch, floor check, read-and-schema-check-then-chain, unreachable-shape check, vocabulary check, proceed. All of it directly after the `datom_conn` class check and **above** the two routing returns at `R/read_write.R:702` and `R/read_write.R:706`, because `.datom_sync_data_metadata()` mirrors the whole manifest to storage without ever reaching the manifest-writing step. All six steps precede any hashing, any local file write, and any commit, so a refusal leaves no partial state -- the spec's own argument being that aborting mid-pipeline leaves a half-finished write, which is worse than the disagreement prevented. The step-7 pull inside `.datom_git_push()` stays as the backstop for the genuine race (a floor raised between entry check and push). | I34, R22.10, R23.4, design.md 10.7, Task 21 |
| 2026-08-23 | **Enforcement begins at 0.1.1; 0.1.0 writers cannot be stopped, and the spec now says so.** 0.1.0 has no schema check, no vocabulary check and no floor read, and none can be added to a released build. Previous wording ("an older build writing into a newer repo") did not separate the population that can be stopped from the one that cannot. For 0.1.0 the remedy is a **NEWS entry, not engineering**: the only lever that would make it fail loudly -- relocating the manifest so its existing "could not read manifest" abort fires -- costs a storage-layout change, a `datom_validate()` change (`R/validate.R:236-238`) and two filenames carried forever, against an exposed population that is the team. | R23.7 |
| 2026-08-23 | **(review) Design A had not been swept into the criteria, and it reached FIVE sites, not the three the review named.** Design A changed the manifest **reader's** response to a too-new version from abort to warn-and-rebuild. R22.11 and AC37b said so; **AC32** still asserted the abort "at all of them", **R22.4** still said a schema refusal is "thrown" unqualified, and -- found while checking those two -- **P35** -- now superseded -- stated that no handler may convert the abort into a warning, which forbade the exact remedy Design A adopts, while **P11** claimed a below-current reader aborts at both entry points. Two of the five are a **property** and an **acceptance criterion**, which is the worst place for a stale mechanism: the suite would have asserted the opposite of the design. **The fix is a scoping, not a reversal** -- refuse-newer still holds absolutely for per-artifact metadata at any role and for the manifest on the writer path. What P35 and R22.4 were really protecting is restated as the thing that survives: **a schema outcome is never reported as an unreadable manifest**, whether it aborts or takes its own deliberate path. This is the spec's recurring swept-some-places defect, on its sixth appearance, and the count went up again on inspection -- the review found three, a re-derivation found five. | AC32, R22.4, P35, P11, Tasks 5 + 22 |
| 2026-08-23 | **AC32 is deliberately recorded as true in two forms rather than reworded once.** Task 5 ships the abort at all five readers and claims AC32; Task 22 replaces the manifest reader's half with warn-and-rebuild. Rather than back-date the criterion, both forms are stated with the task boundary that separates them, Task 5's citation says "in its Task 5 form", and Task 22 explicitly **restates** AC32 and P35 the way Task 6 restates P10. Task 5 also carries an instruction not to bury the abort assertion in a loop over the five readers, because one of the five stops aborting later -- a loop is exactly what makes that amendment easy to miss. | AC32, P35, Task 5, Task 22 |
| 2026-08-23 | **(review) the vocabulary check had no per-artifact document in hand where it was placed, and the resolution is a third option neither side had proposed.** Verified: `datom_write()` does not touch stored artifact metadata until pipeline step 4, inside `.datom_has_changes()` (`R/read_write.R:334-343`), while the check sits at entry step 5 -- so as written it could only ever cover the manifest, and the likely silent outcome was an implementer skipping the artifact half because nothing was at hand. That would remove the check from the document that is **never rebuildable** and where identity lives. The two options offered were an extra storage GET at entry (a second read of an object `.datom_has_changes()` reads anyway, and N reads on the mirror-everything route) or moving the artifact half down to pipeline step 4 (still pre-mutation, but it makes "before any hashing" false for one check). **Chosen instead: read the CLONE's copies** -- all three documents exist as local files (`{conn$path}/.datom/manifest.json`, `{conn$path}/{name}/metadata.json`, `R/read_write.R:463-469`), so it is a file read with no round trip, it works on every route including the one with no single artifact name, and it targets the copy a pull from a newer collaborator actually lands in. Sound because git is written before storage (I5), so storage cannot legitimately hold a newer document than the clone; if it does, that is drift and `datom_validate()` owns it. AC35 gains clause (e) because an implementation checking only the manifest passes every other clause. | R23.1a, AC35 (e), design.md 10.7, Task 21 |
| 2026-08-23 | **(review) the write-entry sequence read the manifest without naming WHICH manifest -- the sibling of the gap closed one round earlier.** `.datom_read_manifest()` takes a scope, and step 3 of design 10.7 did not supply one. **It is the clone**, and R23.1a now governs the whole sequence rather than only its vocabulary step: the manifest at step 3 and all three documents at step 5. The two steps needed saying for **opposite** reasons, which is why one sentence would not have covered both. At step 5 the sequence does not hold the per-artifact document at all (`datom_write()` reaches stored artifact metadata only at pipeline step 4, `R/read_write.R:334-343`), so silence means an implementer checks the manifest alone. At step 3 the unstated default pulls the other way -- the too-new-repo framing reads as storage-flavoured and every check Task 4 wired was, so silence lands on **storage**, adding a network read to every write and inspecting the wrong copy. The clone is right at both for the same four reasons: it is the document the write mutates (`R/sync.R:964`), it is a file read rather than a round trip, it is where a pull from a newer collaborator lands, and storage cannot legitimately be ahead of git (I5). | R23.1a, design.md 10.7, Task 21 |
| 2026-08-23 | **(review) AC32 collapsed to ONE invariant form; accepted, with one part of the proposal declined.** The insight had been applied to P35 and not to the criterion: the invariant was never the abort, it was that a schema outcome is not disguised as an IO failure. AC32 now asserts only that the outcome is **its own** -- not reworded as "could not read manifest", not downgraded to a storage warning -- and says nothing about *which* outcome, which is AC37b's job and differs by role and by task. So it holds unchanged across the Task 5 / Task 22 boundary. Removed with it: the two-forms record, Task 5's "in its Task 5 form" citation, and Task 22's restatement of AC32. **Declined**: dropping the don't-bury-it-in-a-loop instruction. Its justification never depended on AC32's wording -- the **behaviour** still changes at Task 22, so the assertion in `test-query.R` still has to be found and amended, and a loop over the five readers is exactly what makes that easy to miss. Recast as an instruction about test shape rather than about the criterion, and Task 22 now says it amends the test rather than restating the criterion. | AC32, Task 5, Task 22 |
| 2026-08-26 | **(implementation) Task 18 narrows a live safety check, and that is the accepted trade rather than an oversight.** With the fetch-failure return fixed, an offline write proceeds **without knowing whether it is behind** -- the cached upstream refs are deliberately not compared, because they can be arbitrarily stale and acting on them is what produced the abort. Accepted because the backstop is real: `.datom_git_push()` pulls and aborts if the push is rejected (`R/utils-git.R:267-277`) and the storage steps come after it, so a write cannot land on storage from a stale base. Recorded in the function's roxygen as well as here, since a guard that warns and returns `TRUE` reads as a swallowed error to anyone meeting it cold. Same argument design.md 10.7 already makes for warn-and-proceed at the write entry. | Task 18, #104, design.md 10.7 |
| 2026-08-26 | **(implementation) the defect was invisible to the test that existed for exactly this path.** `.datom_check_git_current tolerates network errors gracefully` stubs `git2r::fetch` to raise -- but its fixture has **no upstream branch**, so the function returns before reaching the comparison and the test passed on the defect. Both new tests therefore establish an upstream first, and the ahead-case one was **proven to fail** against the unfixed function before being trusted (stash the `R/` change, re-run, it errors on the stale-ahead abort). The level-case test passes either way by design: it pins an accident (nothing unfavourable to compare against) as deliberate. Also recorded in `dev/engineering-notes.md`: the handler-`return()` trap is a general R gotcha, and a `cli_alert_warning()` needs `expect_message()`, not `expect_warning()`. | Task 18, `dev/engineering-notes.md` |
| 2026-08-26 | **Two operator-facing fixes landed with Task 18, not as tasks -- both are recourse quality for the state a rejected push leaves behind.** Task 18 makes an offline write *proceed*, so it also makes "rejected at push" more reachable, and the recourse was examined in the same session. (1) The merge-conflict abort told the caller to "pull latest changes" -- but the pull is what produced the conflict, so the first line a confused operator read was wrong. Replaced with the resolution that actually works for datom's own generated JSON: keep the remote copy (`git checkout --theirs`) and re-run the write, because step 6 rebuilds `metadata.json` outright, appends to history behind a dedup guard, and rewrites only this artifact's manifest entry. Also states that storage is untouched, since "conflict" reads as "half-published" to anyone who does not know git gates storage. (2) `datom_validate(fix = TRUE)` printed "Fix applied" for findings it cannot fix: the repair calls `.datom_sync_data_metadata()`, which uploads manifest and per-artifact metadata **only** -- a missing parquet is not in the clone and never was. It now names those artifacts and points at re-running `datom_write()` with the source data. Same trap shape the log already names twice (a repair path quietly not delivering what it claims), and the third instance, so the pattern is now: **any repair path must state what it does NOT repair.** tests 2664 -> **2675**. | `R/utils-git.R`, `R/validate.R`, Task 18 |
| 2026-08-26 | **Cold-start audit for Task 19: startable, after closing one gap that spanned two tasks.** The documented path was walked as a fresh reader and every claim checked against the tree. What held: the citation `R/utils-sha.R:410-420` is accurate, the `volatile` denylist is the seven fields described, AC33's four clauses and P36 are complete and unambiguous, and AC33(a)'s pinned value already exists (`test-utils-sha.R:899-904`). **The gap: Task 7 adds `kind` plus an entire set metadata builder and said nothing about classifying either.** After Task 19 an unclassified field is silently *outside* identity, so `kind` would stop affecting `metadata_sha` and a table and a set could share a version identity -- exactly what the 2026-08-23 decision closed off, and invisible to every other test in Task 7. **The fix is a forcing function, not a reminder**: Task 19's classification test must **derive** the field set from what the builders emit rather than hardcode today's names, so it fails the moment Task 7 touches a builder. A hardcoded list would have passed forever, which is the same swept-some-places shape this log records six times -- caught here before implementation rather than after. Task 7 now carries the obligation explicitly, with R9.5, P36 and AC33(d) added to its criteria line. | Tasks 19 + 7, AC33, P36 |
| 2026-08-26 | **OWNER-DECIDED: anchor AC33(a) on a realistic fixture, and repurpose the `name`-bearing golden as AC33(b)'s test.** Two ordered steps, now in Task 19's body. **(1)** Before touching `.datom_compute_metadata_sha()`, pin the `metadata_sha` of a document built by `.datom_build_metadata()` with every optional argument supplied, computed under **today's** code -- that is AC33(a)'s evidence and it must not move. Ordering is the point: a pin computed in the same edit as the change it polices is worth much less. **(2)** The `name`-bearing golden is not retired but **reused** -- `name` *is* an unknown extra field, precisely AC33(b)'s case, so the fixture that was going to break becomes the assertion for the property that breaks it, with its constant becoming the no-`name` value. **Rejected: adding `name` to the allowlist** to keep the old constant byte-identical -- cheapest in churn, but the list would then name a field datom never writes, destroying the one property that makes it readable (that it *is* what the builders emit) and inviting a later reader to conclude a `name` field exists. | Task 19, AC33 (a) + (b) |
| 2026-08-26 | **RESOLVED SAME DAY by the row above -- retained for the verification it records, not as an open item.** ~~(audit) OPEN FOR THE OWNER AT TASK 19 START~~: **the pinned `metadata_sha` golden's fixture carries a field no builder emits, so a correct allowlist changes that hash.** The fixture is `list(data_sha, name, nrow, ncol, table_type, hash_algo)` and **`name` is not a metadata field** -- verified that `metadata.json` is written as exactly `.datom_build_metadata()`'s object, which has no `name` key (the `name` at `R/read_write.R:774` / `R/read_write.R:834` is `datom_write()`'s return value). So under a builder-derived allowlist the golden fails while **no stored identity moves**, because no real document ever had the field. The hazard is the reflex: re-pin the constant and AC33(a) loses the only pinned evidence it rests on, in the task whose entire claim is behaviour preservation. **Recommendation, not a decision**: pin a *realistic* fixture under today's code first, so there is a true before/after anchor, and let the `name`-bearing golden change for a stated reason. Flagged rather than settled because AC33(a) is the clause that proves this task was safe, and how it is anchored is a public-contract-shaped choice. | Task 19, AC33 (a) |
| 2026-08-26 | **(audit) the metadata field inventory is provably complete from one function, and that is what makes the allowlist safe to seed.** Every top-level key of a metadata document is assigned inside `.datom_build_metadata()`, with exactly one exception -- `meta$parquet_sha` (`R/read_write.R:786`), which is volatile. Verified by grepping every `meta$<key> <-` and `metadata$<key> <-` in `R/`. This matters because an allowlist seeded from an incomplete inventory drops content out of identity **silently**, which is the failure direction an allowlist has and a denylist does not; recording the result means the next session does not repeat the grep or, worse, skip it. The semantic set today: `data_sha`, `hash_algo`, `table_type`, `nrow`, `ncol`, `colnames`, plus `original_file_sha`, `parents`, `source_lineage`, `custom` when present. | Task 19, R9.5 |
| 2026-08-26 | **(implementation) the new helper's own test caught a substring bug in it, which is worth the row because the same shape will recur.** `.datom_validate_unfixable_tables()` selects the artifacts whose payload is missing, and status codes are comma-joined -- so `grepl("data_missing_s3", ...)` matches **`metadata_missing_s3`**, which contains it. That reported every metadata-only finding as unrepairable: exactly backwards, since those are the ones the sync does fix. Now split on `,` and compared as whole tokens. Second correction in the same helper: it originally guarded `all(c("name","status") %in% names(...))` and the real column is **`table`**, so the guard converted a wrong column name into a silent `character()` -- reinstating the overclaiming message the helper exists to remove. Guard deleted deliberately: a renamed column must error here. Same reasoning as the no-missing-`kind`-fallback decision -- a safety net that fires only when something upstream is already broken hides the breakage. | `R/validate.R` |
| 2026-08-23 | **(review footnote, pre-existing) a retired phrase was suppressing on an incidental word, and it is now pinned to an intentional one.** The `tasks.md` occurrence of "convert the abort into a warning" sat inside a record whose nearest marker was **"reversal"**, matching via the `revers` stem -- the right outcome by accident, and fragile, because `revers` is ordinary vocabulary in this spec and could mask a genuine hit later. The record now carries an explicit "superseded". Verified by re-running the gate's window test with `revers` removed from `MARKER_RE`: still suppressed. `MARKER_RE` itself is left alone -- the maintenance lesson already in `dev/check-spec.R` is that broadening it toward ordinary vocabulary is what made the check nearly vacuous once, and `revers` is close to that line. Worth revisiting the next time that list is touched. | dev/check-spec.R |
| 2026-08-29 | **`.kiro/steering/communication.md` extended (not a task).** Three additions, each from a message the owner could not act on. (1) **Every section is labelled by purpose** -- TLDR, What changes, Why, FYI, Need from you -- because a reader cannot otherwise tell background from a decision request from the agent's own justification, and the cost of guessing wrong is either an unanswered question or an unwanted implementation. (2) **No homework**: a sentence that needs a file opened, a task re-read or a decision recalled is not written yet; name a thing and gloss it in the same breath, and never signal that something is significant instead of saying what happens. (3) **Questions must be answerable without having read the rest of the message**, with no type names inside them, naming the two outcomes being chosen between. Two real messages from this session are recorded in the file as the worked counter-examples. | `.kiro/steering/communication.md` |
| 2026-08-29 | **(implementation) the failure record carries the whole condition, not its message text.** Two callers want different things from it: `datom_list()` / `datom_summary()` splice `conditionMessage()` into their own abort, while the two clone readers re-signal the original with `stop()` so a corrupt local manifest still fails with the parser's own error and no datom wrapper around it. Text alone would force the second case to build a look-alike error, losing the condition class -- and class, not wording, is what the suite asserts on at every other schema site. | Task 5, R22.4 |
| 2026-08-29 | **(implementation) `absent = TRUE` is a positive claim, and the storage scope never makes it.** For the clone copy it is a free `fs::file_exists()`. For storage it would need an extra request on every `datom_list()`, `datom_summary()` and `datom_status()` call to separate a missing object from an unreachable store, and no caller treats those differently -- so the field stays `FALSE` there, meaning "not known to be absent". Pinned by a test, because the tempting later shortcut is to infer absence from the error message; the right move if a caller ever needs it is `.datom_storage_exists()`. Contrast Task 3, which bought exactly that probe on purpose -- there it improved a user-facing message, here there is no message to improve. | Task 5, Task 3 |
| 2026-08-29 | **(implementation) a corrupt manifest in the clone is a failure, not an absence.** Both clone readers fall back to an empty manifest when the file does not exist. A present-but-unparseable file must not take that branch: it would report every input file as new -- a confident wrong answer, which is the failure class this whole phase exists to remove. The record separates the two states and each reader re-signals the parse failure, with a test at both readers. | Task 5, R22.6 |
| 2026-08-29 | **(implementation) both new guards were proven to fail before being trusted.** Pointing `datom_list()` at `manifest$artifacts` -- what Task 6 does -- turns the frozen-fixture test red, so it is real evidence that old-format repos still list their contents. Wrapping the schema check in a handler inside `.datom_read_manifest()` turns three tests red, including `datom_sync_manifest`'s pre-existing refusal test, so the returned-versus-thrown split is pinned rather than assumed. Both probes reverted. This is the rule the spec already applies to `check-spec.R` gates, applied to `R/` guards. | Task 5, AC30, AC32 |
| 2026-08-29 | **(implementation) `datom_status()` lost its `read_ok` flag, and it was not dropped -- it moved.** The flag existed because a manifest that legitimately parses to `NULL` must still count as read, which a `NULL` check on the document cannot express. The shared reader's `ok` field carries that distinction for every caller now. | Task 5 |
| 2026-08-29 | **(implementation) the entry updater keeps its own direct read; only its empty shape moved.** `.datom_update_manifest_entry()` (`R/sync.R:946`) reads the clone's manifest mid-write, and a compatibility refusal there would stop a write partway through rather than at the door -- Task 4's stated principle. So the read stays out of the shared reader while the hand-built empty manifest becomes a call to `.datom_manifest_skeleton()`. A comment at the site says why, because routing the read through the shared reader is the obvious tidy-up and it is wrong. | Task 5, Task 4 |
| 2026-08-29 | **Spec code citations re-derived by content after Task 5's insertions**, in all three spec files plus the two `design.md` survey tables. Three had drifted onto blank lines and were caught by the gate; the rest were checked with `SPEC_CHECK_SHOW_CITATIONS=1` rather than by arithmetic. Two citations were **removed** rather than repointed: the comments at `datom_list()` and `datom_summary()` that held the check outside their read handlers no longer exist, because the helper's shape holds that line now. Dated Decisions rows left frozen, per the 2026-08-23 policy. | dev/check-spec.R, Task 5 |
| 2026-08-29 | **One operator-facing fix landed after Task 5, not as a task: terminal escape codes stripped from stored error text.** `cli` formats abort messages with colour and hyperlink escapes, and `conditionMessage()` returns them, so any field that **stores** the text stores `\033[31m` with it. Invisible when the message is printed and ugly when the string is, which is why no test caught it -- plain `Rscript` and CI have colour off, so cli emits none. Three returned fields carried it, and the worst was not the one that surfaced: `datom_sync()`'s `error` column is a data frame cell, so a failed sync prints escape codes inline in a table. Fixed with `cli::ansi_strip()` at the three stored copies only; every printed message keeps its colour. **Verified pre-existing before being fixed** -- the previous commit was checked out into a throwaway worktree and run with colour forced on, giving a byte-identical 305-character string, so Task 5 neither caused nor worsened it. Scope was checked rather than assumed: the five other places that capture `conditionMessage()` into a local use it for pattern matching or splice it into a message, so three sites is the whole of it. Each test forces colour **on**, because with it off the assertion passes no matter what the code does; all three were confirmed to redden when the fix is reverted. tests 2740 -> **2748**. | `R/query.R`, `R/sync.R`, `dev/engineering-notes.md` |
| 2026-08-29 | **Spec citations re-derived twice in one session, and the second round found the class the gate cannot see.** The escape-code fix added three comment lines to `R/sync.R`, which shifted every citation below them. Three resolved to blank lines and the gate caught those; **four others had drifted onto unrelated code and passed** -- `R/sync.R:744-756`, cited as the manifest entry builder's field list, was pointing at the import-format vector, and `R/sync.R:570-574`, cited as the imported self-lineage entry, was pointing at the sync loop. Two of the four were already wrong before this session. The lesson is the one `dev/README.md` already states and this is now the second consecutive session to prove it: check 4 asserts only that a cited line is **not blank**, so after any insertion into `R/` the citations must be re-read with `SPEC_CHECK_SHOW_CITATIONS=1` and compared against what they claim. A green gate is not evidence. | dev/check-spec.R |
| 2026-08-29 | **OWNER-DECIDED: the frozen upgrade steps get their own file, `R/manifest-upgrade.R`.** `.datom_manifest_upgrade_v1_to_v2()` and the dispatcher live there rather than beside the reader in `R/sync.R`. Reason: a released step is never edited -- it is written against files that exist unchanged in the world -- and one more step arrives with every future format change, so they accumulate. A file whose entire contents are "never edit these" is easier to protect than a section of a file that is already 881 lines and holds sync, import and manifest concerns. Same reasoning that split `R/hashable-set.R` out of `R/utils-sha.R`. Recorded because Task 6 named the functions and no file, which is the dangling-instruction class the Task 2 audit flagged. | Task 6, I30, R22.5 |
| 2026-08-29 | **OWNER-DECIDED: `.datom_manifest_skeleton()` stamps `schema_version: 2` itself.** A manifest built from scratch declares its format immediately, so no repo exists in a state that declares nothing -- not even between being created and receiving its first artifact. **The consequence that needs saying**: this covers only the no-file path, since the skeleton is unreachable when a manifest exists. A document read from disk in the old shape still gets its number from the upgrade step, so stamping lives in two places by design -- one for a document being created, one for a document being converted -- and an implementer who stamps only in the builder leaves every existing repo unstamped. | Task 6, R9.5, R22.3 |
| 2026-09-01 | **PARKED MID-DESIGN ON TASK 6 for a CRAN interrupt.** 0.1.1 was accepted and CRAN then reported a failure in its automated check runs, which takes priority and is worked on `main`, not here. Task 6's design was proposed and the session stopped for go-ahead per rule 5b, so **nothing was implemented**: clean tree at `dbae253`, 2748 tests, `check-spec.R` 9/9. The plan, the test plan and **five open calls each carrying the default to take on silence** are recorded in Task 6's PAUSE block rather than in this row, so there is one copy to keep true. Two things the interrupt does to this branch, recorded because neither is visible from inside it: the fix will land on `main` and merge in, staling `R/` line citations in a way check 4 catches only when they go fully blank; and the acceptance bookkeeping (publish the release, then merge `dev` into `main`, then delete `dev`) may end the submission freeze that governs this branch's PR target, so `dev/README.md` "Branching During CRAN Submission" must be re-read on resume rather than assumed. | Task 6, dev/README.md |
| 2026-09-08 | **RESUMED. The CRAN interrupt is closed and it changed nothing in this spec.** The failure CRAN reported after accepting 0.1.1 was in test fixtures, not package code: they hardcoded `refs/heads/master` when pushing to a throwaway remote, and `git2r::init()` honours git's `init.defaultBranch`, so on a machine configured for any other name the push named a branch that had never been created -- 26 failures on four Linux flavors, all the same error, all during setup. Shipped as **0.1.2** ([#106](https://github.com/amashadihossein/datom/issues/106) / [#108](https://github.com/amashadihossein/datom/issues/108), PRs #107/#109/#110), **no `R/` file touched**, so Task 6's design stands as proposed and its five open calls are still unanswered. **Both hazards the 2026-09-01 row flagged are discharged, and the answers differ from what that row expected**: the fix merged in via `main -> dev -> spec/datom-sets` and staled **no** citations, because it touched only `tests/` (re-verified: 107 citations, all in range, none blank); and the submission freeze **did not end** -- 0.1.2 is now in flight, so `main` must still match what CRAN received and this branch still PRs into `dev`. Branch at `7dc3d78`, level with origin and with `main`, clean tree, **2748** tests verified after the merge under both `init.defaultBranch=master` and `=main`, `check-spec.R` 9/9. **One durable lesson came out of it, and it is git-adjacent rather than datom-adjacent**: in a git worktree `.git` is a FILE, so any tool testing for a `.git` *directory* silently gets the wrong answer -- `R CMD build` swept the pointer file into the tarball, `devtools::submit_cran()` skipped writing `CRAN-SUBMISSION` altogether (`devtools:::uses_git()` is `dir_exists()`), and the `.gitignore` rule for that artifact turned out to exist only on this branch. All three fail without saying anything and leave the submission intact, which is why they went unnoticed. Recorded in `dev/engineering-notes.md`. | Task 6, dev/README.md, dev/engineering-notes.md |
| 2026-09-08 | **TASK 6 IMPLEMENTED: `manifest$tables` is now `manifest$artifacts`, and every existing repo still reads.** Landed in one commit as planned, with all six of the task's defaulted items taken at their defaults. What shipped: the rename plus `kind` on every entry; `schema_version: 2` stamped on both manifests and on every per-artifact metadata document; the conversion chain in a new `R/manifest-upgrade.R` (a v1 step that renames the key **in place** so unrecognised sibling keys survive with their position, plus a dispatcher that runs each step in order and records the version reached); five counters filtered on `kind == "table"` with `total_sets` / `set_count` beside them; a `kind` column on `datom_list()` including both empty returns; and a write-side refusal at `datom_write()`'s door, above the routing returns and before any hashing. **Three things the plan did not settle, decided while implementing.** (1) The dispatcher **takes the declared version as an argument** rather than reading it off the document, because the only correct source for that number is the check that refuses a document too new to convert -- so "check first, then convert" is structural rather than remembered (I32). (2) The entry updater **runs that check on what it read from disk** purely to obtain the number; it cannot fire for a write that came through `datom_write()`, whose door already refused a too-new manifest, and the alternative was editing a document whose version was guessed. Task 5's decision that the updater keeps its own **read** is unchanged. (3) A document that did not parse to a named list is **returned untouched** -- stamping one would turn `null` on disk into an object in memory. **Every guard was proven to fail before being trusted, and two of the four would otherwise have shipped green**: disabling the conversion reddens 18 assertions across all four frozen-fixture readers, both tolerance tests and the mirror route; removing the `kind` filters reddens five tests across all three counting sites; moving the door below the routing returns reddens both non-table write routes; dropping the conversion from the entry updater reddens the ten assertions that say a pre-existing table is still counted. All probes reverted. Tests 2748 -> **2836**, FAIL 0 / WARN 0 / SKIP 0; `check-spec.R` 9/9. **Citations across all three spec files were re-derived by content afterwards** -- this change shifted every line below its edits in six `R/` files, and the gate catches only the ones that land on a blank line. **The purity audit E2 asks for is now due**, in-line, before Task 20. | Task 6, R8, R9.5, R22, I29, I30, I32, P10, P34, AC7, AC30, AC31 |
| 2026-09-08 | **OWNER-DECIDED: bump `schema_version` only when an old reader would get a WRONG answer, not merely a stale one -- and stop old writers by other means.** Recorded because the mechanism cannot express the combination a future change will want. `.datom_check_write_schema()` runs the *same* comparison every reader runs, so the number is one dial driving two gates: raise it and old readers are refused along with old writers. "Old readers proceed, old writers refused" is therefore unreachable by bumping. The two mechanisms that reach it are the **vocabulary check** (a build refuses a document carrying a top-level key it cannot classify -- this is the one that covers a plain added field, where the number must NOT move) and the **writer floor** (for stopping writers for reasons that are not about format at all). Task 6's bump to 2 is correct under this rule: an old reader meeting `artifacts` reports an empty repo silently, which is a wrong answer, not a stale one. The rule earns its keep at the next change, where the tempting move is to bump for a content-bearing addition and refuse a reader that could have read the file perfectly well. | R9.5, R23.2, R23.3, Task 21 |
| 2026-09-08 | **REVERSED, one sitting later: `datom_list()`'s empty results now carry `current_data_sha`.** Task 6 recorded the opposite default with the reason "fixing it changes a public shape nobody asked to change." That reason was already spent when it was written -- the same commit added a `kind` column to that very shape and announced it in NEWS -- and the drift is a real defect, not a cosmetic one: `rbind()` of two frames with different columns errors outright, so a caller collecting listings across projects breaks the moment one of them is empty. Spending the break once, inside a window that is already breaking, beats owing it a release of its own. Recorded as a reversal rather than edited into the original call, because the useful lesson is the shape of the mistake: a "do not change a public shape" argument is worth much less in a release that is already changing that shape, and it should be re-tested against the rest of the commit rather than carried over from the plan. | R8.4, Task 6, AC30 |
| 2026-09-08 | **A write that converts a manifest now announces it; reads stay silent.** From the post-landing review. Conversion is one-way for everybody else sharing the repo: after it, a build predating the rename lists the repo as empty **without erroring**, though `datom_read()` still works because the data path never touches the manifest -- a discovery blackout, not lost access. The flip was silent, and `datom_validate(fix = TRUE)` reaches it while reading as a repair, so a colleague's install could degrade because someone else ran a verification command. One line now fires from the two places that **persist** a conversion (the entry updater, which rewrites the tracked file, and the metadata sync, which mirrors to storage), naming the consequence and pointing at NEWS for the format-to-release mapping. **Reads deliberately say nothing**: a read changes nothing on disk, and a line on every `datom_list()` call is noise nobody can act on. The reader's record gained `declared` so the persisting caller does not re-derive the comparison or read the file twice. | R22.2, R22.3, R9.6, Task 6 |
| 2026-09-08 | **The counters' kind filter is one helper, because a predicate written out four times is a predicate that can differ once.** The post-landing review found the three counting sites aborting on an entry that is not a named list -- with "$ operator is invalid for atomic vectors" -- which the v1 conversion step **deliberately preserves**, since an entry with no shape has nothing to convert. `datom_status()` was the damaging one: it exists to describe a connection when the manifest cannot be trusted, and the count sits outside the error handling that gives it that tolerance, so a hand-edited manifest took the whole diagnostic down. Fixed by routing all four selections through `.datom_artifacts_of_kind()` rather than adding the same guard in four places. **What deliberately did not change**: an entry with no `kind` is still uncounted, no fallback to `"table"` -- skipping a shapeless entry and tolerating a missing type are different, and the second would let a read path that skipped the conversion produce roughly-right numbers instead of visibly wrong ones (R22.8). | R22.8, I28, Task 6 |
| 2026-09-08 | **PURITY AUDIT DISCHARGED for Task 6 -- run LAST, after the review fixes, on owner's call.** The sequencing decision is worth keeping: an audit of a state about to change produces findings that go stale, and two of the four review fixes landed squarely in what an audit inspects (three fresh copies of one predicate, and a public return shape). So the audit went last. **Both questions it existed to answer were settled mechanically, not by reading.** (1) Is the suite blind to the silent blackout? No -- deleting the artifact key from the shared reader's returned document reddens **64 assertions across 36 tests**, covering all five readers and five `datom-cv1` end-to-end scenarios, so the ~40-fixture sweep did not cost the suite its teeth. (2) Did any swept fixture declare the version but omit `kind`, which counts as zero artifacts? No -- making an untyped entry abort inside the selection helper reddens exactly **one** test, the one that deliberately passes an untyped entry to prove it is not counted. That probe replaced a regex over the fixtures, which cannot see an entry spread across lines and fails silently when it misses one. **Two tests were passing whatever the code did and were tightened**: a print test asserting that a `Sets:` line exists (true with a count of zero -- now asserts the number) and a pattern-filter test asserting an empty result from a non-empty fixture (equally true if the manifest was never read -- now asserts the unfiltered call returns a row first). Nothing else changed: each of the five concerns has one home, stamping is still the two sites I29 requires, no read of the old key survives in `R/`, and `R CMD check` is 0/0/0. **One gap named rather than fixed**: the write door inspects the manifest only, and `.datom_sync_metadata()` (`R/utils-sha.R:538`) copies a per-artifact document from the clone to storage unchecked -- pre-existing, narrowed rather than introduced by Task 6, and it belongs with Task 21's entry sequence, which already reads all three documents at the door. | Task 6, Task 21, E2, I29, R22.8, R23.1a |
| 2026-09-08 | **Two loose ends from a second review pass, both closed the same day.** (1) **The zero-row frame was still one column short**, in the case the first fix did not reach: `version_count` is opt-in, so `datom_list(include_versions = TRUE)` on an empty repo returned five columns where the same call on a populated repo returns six -- and a comment asserted no caller could ask for that. Fixed by having the frame take the flag rather than by rewording the comment, because it is the same defect the `current_data_sha` reversal was about and the same argument settles it. Proven non-vacuous: dropping the column reddens the new test. (2) **The metadata-only write route makes the door's check stale.** `datom_write(conn, name = )` reaches `.datom_sync_metadata()`, which pulls from the remote as its first act (`R/utils-sha.R:559`) -- after the door has read and checked the clone's manifest -- so a collaborator's newer-format manifest can arrive in that pull and the route carries on. Harmless in shipped code, because the route writes per-artifact metadata and never the manifest, so nothing can end up half in each format. Not harmless for Task 21, whose entry sequence begins with a fetch and then checks: if a route pulls again afterwards, the checks describe a state the route has already replaced. Written into Task 21's bullets as a decision it must make -- own the fetch, or re-check after it, not both. Also tightened: Task 6's record said "the only pull is inside the push", which is true of the table-write route and not of this one. | Task 6, Task 21, R8.4, I34, R23.4 |
| 2026-09-08 | **TASK 20 IMPLEMENTED: a field this build cannot place now survives a write instead of being deleted by the rebuild.** New `R/forward-compat.R` with one merge helper and two vocabularies, called from `datom_write()` and from the manifest entry updater. **The finding that shaped it: only two of the three levels needed code.** The manifest's **top level** already survives, because that document is read, edited and written back rather than rebuilt -- so the guarantee there is a property of *editing*, and a later refactor to assembling a fresh document would remove it without failing anything else. Tested for exactly that, and proven by probe: building from the skeleton instead of reading the file reddens the top-level test. **The narrowness is the other decision, and the alternative is wrong rather than merely different**: only unplaceable fields are carried, so a field datom knows still disappears when the write does not set it. `original_format` decides it -- a table imported from a CSV and later written straight from a data frame has no format to declare, and a blanket keep-what-the-new-document-omits would leave that claim standing against a version it does not describe. A wrong statement is worse than a missing one, and three tests redden under the blanket form. **Placed after the version identity is computed**, beside the `parquet_sha` assignment: identity already ignores what it cannot place, so both positions hash the same today, but attaching afterwards means a carried field cannot reach a hash at all and no later change to the identity list can pull one in. **Six probes, each reverted**: removing either merge reddens both halves of its round trip (git and storage); rebuilding the manifest reddens the top-level test and the row test; widening the merge reddens all three narrowness tests; and an unclassified field added to either builder reddens that builder's forcing function, naming the field -- the metadata one while every pinned identity hash stays green, which is the allowlist's failure direction and visible only there. Tests 2867 -> **2898**, FAIL 0 / WARN 0 / SKIP 0; `check-spec.R` 9/9. No pathway impact. | Task 20, R23.8, P38, AC34 |
| 2026-09-08 | **`.datom_metadata_known_fields()` is a function and not a stored vector, because `R/` is sourced alphabetically.** DESCRIPTION declares no `Collate`, so `forward-compat.R` is sourced **before** `utils-sha.R`, where the identity list and the not-identity list both live. A constant joining them here would be built from values that do not exist yet and the package would fail to install. Same trap `R/manifest-upgrade.R`'s header records for its step table, arrived at from the opposite direction -- there the rule is that a step must be defined *above* the table in the same file, here it is that a derived constant must not reach across files that sort later. Deriving at call time also means the union cannot fall out of step with either half. Worth a row because the obvious tidy-up is to make it a constant "for symmetry" with the two it joins. | Task 20, `R/forward-compat.R` |
| 2026-09-08 | **The manifest row's vocabulary is hand-listed, not derived, and that is what makes its test a forcing function.** Eight names today. A vocabulary read off the row builder's own output could never disagree with the builder, so it would assert nothing; listing it by hand and then asserting every field of a real written row appears in it is what fails when someone adds a field without classifying it. The failure matters more than it looks: an unclassified row field would be treated as unplaceable and carried forward from the previous row on every later write, so it would go stale rather than being recomputed. **Task 9 will trip this deliberately** when it adds the set row's member count -- the name is not pre-listed. The metadata document needs no equivalent new list, since Task 19's classification test already polices that builder and this task only joins its two halves. | Task 20, Task 9, Task 19 |
| 2026-09-08 | **Three live code citations were already wrong before this change, found while re-deriving the ones it shifted.** Two lines cited as `datom_write()`'s return-value `name` and one cited as its in-pipeline manifest read all pointed at unrelated statements, as did Task 19's citation of where `parquet_sha` is assigned. None was caused by this session: verified against the previous commit before repointing. Check 5 cannot see this class -- it asserts only that a cited line is not blank -- so the standing instruction holds and is now proven for a third consecutive session: after any insertion into `R/`, re-read citations **by content** with `SPEC_CHECK_SHOW_CITATIONS=1`. One imprecise citation was deliberately left: `R/sync.R:179` lands on the comment above the mirror route's manifest read rather than on the read itself, and the surrounding claim in Task 4's record -- that this site is an excluded raw local read -- was overtaken by Task 6 routing it through the shared reader. Left as a historical record rather than rewritten. | dev/check-spec.R, Task 20, Task 19 |
| 2026-09-08 | **A FOURTH SURFACE the carry-forward requirement does not name: an entry in `version_history.json`.** Raised in review of Task 20. It is safe by the same property as the manifest's top level -- the history list is read and the new version is **prepended**, so an entry already in it is never rebuilt -- so no code was needed. It was worth **pinning** rather than leaving as an observation for one specific reason: **two later tasks add fields to those entries** (Task 7's `document_sha`, Task 15's `commit_sha`), and a build that normalised an old entry to today's field set would destroy exactly those, on a record describing a version it may know nothing about. One test plus a comment at the site telling the next reader not to normalise entries on the way past. Proven non-vacuous: rebuilding the existing entries from known names reddens both halves of it. Same reasoning as the manifest top level, which is also code-free and tested anyway -- **a guarantee that rests on the shape of a function rather than on a check needs a test, because a refactor removes it without failing anything else.** tests 2898 -> **2902**. | Task 20, Task 7, Task 15, R23.8 |
| 2026-09-08 | **`document_sha` is the one name this build classifies and never writes, which makes it invisible to carry-forward -- Task 7 owns the consequence.** Verified mechanically rather than by reading: the vocabulary holds 17 names, the metadata builder emits 16, and the difference is `document_sha`, classified as not-identity by Task 4 before anything wrote it. Carry-forward only rescues names a build **cannot** place, so a metadata document arriving with `document_sha` on it loses the field on rewrite -- and silently, because the field takes no part in identity, so no version moves to signal the loss. **Unreachable today and still unreachable under Task 7 as specified**, which puts the field in `version_history.json`, where the fourth-surface property protects it. Recorded because the tempting later tidy-up is to move it into `metadata.json` beside the other hashes, and that is a decision with a consequence rather than a relocation. The reusable shape: **classifying a field ahead of writing it is not free** -- it buys identity-stability early and costs carry-forward protection until a builder emits it. | Task 20, Task 7, Task 4, R23.8 |
| 2026-09-08 | **Process, from review of Task 20's own checkpoint message: a summary asserted five open calls "taken as defaulted" when the task's record contained none, and asserted the commit was unpushed without checking.** Both are the same failure in different clothes -- reporting a state from memory of what was planned rather than from what is written down or true. Fixed by recording the five calls in Task 6's shape, with the correction that they were **explicitly approved** rather than defaulted on silence, which is a stronger claim and the accurate one. The countermeasure for the second is procedural: verify remote state before describing it, exactly as the operational rule already requires before *retrying* a remote-mutating action. Recorded because Task 6's open-call discipline is what made the last two rounds checkable, and a summary that invokes that discipline without the record behind it spends its credibility for nothing. | Task 20, Task 6 |
| 2026-09-08 | **CLASSIFY A FIELD WHEN YOU START WRITING IT, NEVER EARLIER -- now guidance plus a guard, owner-approved.** The `document_sha` finding generalises into a rule for whoever edits this package: classifying a name ahead of the code that produces it looks like preparation and quietly costs the field its protection, because carry-forward rescues only names a build **cannot** place. **The asymmetry that let it through, found by asking whether any guard existed**: the identity list has always carried a converse arm (nothing on it may be a field datom never writes -- added to block the rejected `name` shortcut), and neither the **not-identity** list nor the **manifest-row** list had one. `document_sha` sits on the first of those two. Both now do, with an explicit exception vector holding exactly one name and its reason; the row list needs no exception, since its eight names are precisely what a row carries with both optional fields supplied. **Three probes, each reverted**: a junk name on either list reddens that list's arm naming the field, and emptying the exception vector reddens it naming `document_sha` -- so the vector is load-bearing rather than decorative. The prose half is in `.github/copilot-instructions.md` (always loaded) and `dev/engineering-notes.md` (the mechanism, read before editing `R/`); the same edit fixed two stale claims there -- the carry-forward bullet said three levels where there are four, and the section heading said "two pitfalls" while carrying three, which is the restate-a-count defect these documents keep catching elsewhere. **Deliberately not user-facing**: this is a test and two developer documents, nothing in a user's session. tests 2902 -> **2905**. | Task 20, Task 7, R23.8, `dev/engineering-notes.md` |
| 2026-09-08 | **COLD-START AUDIT FOR TASK 21: startable, after one correction and three additions. No escalation flag on it** (design.md 12 carries E1 and E2 only), so nothing is owed under rule 5d. The documented path was walked as a fresh reader and every claim in the task's body checked against the tree. **What held**: `R/utils-sha.R:559` really is the pull that makes the metadata-only route's door read stale; `R/sync.R:177` is the mirror route; the routing-return citations are right after this session's repointing; `datom_get_conn()` does parse `project.yaml` (`R/conn.R:930`), so the floor can ride on the conn as specified; and `custom` is on the identity list and hashed whole, so "opaque and classified as a whole" is true in code. **THE CORRECTION, and it is one I introduced yesterday**: Task 20's record claimed the refusal "inspects top-level keys only, so an unplaceable field inside a manifest row never trips it". R23.1 scopes the check to **three** documents and names manifest **entries** as one of them -- "top-level keys only" means *do not descend into a value*, not *ignore entries*. So all three of Task 20's coded levels become unreachable through the write door, and the case that stays live is the **version-history entry**, which R23.1's scope list does not include: the test written for it in the review round is load-bearing rather than belt-and-braces. The wrong claim had reached four places and is swept in all of them -- the classic defect this log records seven times, this time self-inflicted within one day of writing the rule against it. **THREE ADDITIONS to Task 21's body.** (1) **Three scopes means three lists, and Task 20 built two of them** -- `.datom_metadata_known_fields()` and `.datom_manifest_entry_known_fields` -- leaving only the manifest's **top level**, whose five names (`schema_version`, `project_name`, `artifacts`, `summary`, `updated_at`) were derived by grepping every top-level assignment rather than guessed, with the `datom_sync()` result-frame columns of the same name flagged as a decoy. Without this a reader would have reached for the metadata lists, which name `data_sha` and `colnames`. (2) **The hole Task 6's purity audit handed forward is now in the task's own body** -- `.datom_sync_metadata()` copies a per-artifact document to storage unchecked -- rather than only in Task 6's record, and it is noted as the same route as the staleness item, so one decision covers both. (3) One citation repointed: `R/read_write.R:334-343` landed on roxygen, and the storage read it was pointing at is at `349`. | Task 21, Task 20, R23.1, R23.1a |
| 2026-09-09 | **TASK 21 IMPLEMENTED: a write now stops when this build cannot fully account for the repo it is writing into.** One function, `.datom_check_write_entry()` (`R/forward-compat.R`), called where the manifest-only door used to sit -- after the `datom_conn` class check, above both routing returns, above any hashing or local write. Four steps in a fixed order: the **floor** (`min_writer_version` in `project.yaml`, read onto the conn, absent means no limit), the **manifest** through the one shared reader with the refusal worded for a write, the **shape the conversion reached**, and the **vocabulary** on the manifest's top level, on each artifact entry, and on each per-artifact `metadata.json` the write will touch. All clone copies -- local file reads, no network. `.datom_check_write_schema()` is **gone**, absorbed rather than kept beside the new sequence: two doors reading the same file at the same moment have no way to say which runs first, and the order is load-bearing (a policy refusal before anything about format; the format check before the conversion, because there is no conversion step for a version this build has never heard of). **Seven probes, each reverted and each naming what it reddened**: the vocabulary check 6 tests, the floor 3, the shape refusal 1, emptying the per-artifact loop 5, pruning the retired name 1, the per-artifact schema check 1, the re-check after the pull 1. The last three would each have shipped green without their probe. Tests 2905 -> **2959** (+54), FAIL 0 / WARN 0 / SKIP 0; `check-spec.R` 9/9. **Pathway impact**: a new route card, and the schema card's write-side paragraph now points at it. | Task 21, R23, I31, I32, I33, I34, P37, AC35, AC36, AC38(a) |
| 2026-09-09 | **DEVIATION, recorded rather than quiet: design 10.7's step-1 fetch is NOT implemented.** A fetch updates remote-tracking refs and **not the working tree**, so it cannot make any of the four checks read a fresher document -- every one of them reads a file the route is about to write. The only thing that would refresh them is the behind-comparison in `.datom_check_git_current()`, which **aborts**; adding that to `datom_write()` would newly refuse an offline write that works today, and would make the mirror-everything route -- which touches no git at all -- depend on `git2r`, which is in **Suggests**. So the step buys nothing for the checks and costs two behaviour changes. What it was really aimed at, staleness on the one route that pulls, is solved directly by the row below. Reversible in one line if the abort is wanted for its own sake. | design.md 10.7, Task 21 |
| 2026-09-09 | **THE STALENESS QUESTION IS ANSWERED BY RE-CHECKING, NOT BY OWNING THE PULL.** Task 21's body named two options and required one. `.datom_sync_metadata()` pulls from the remote as its first act, after the door has read the clone, so a collaborator's newer manifest or metadata document can arrive in that pull and the route would carry on into a repo it had been told it understands. That route now calls `.datom_check_write_entry()` **again** immediately after the pull, against what the pull left on disk. Rejected: the sequence owning the freshness -- one fetch at the door, no route pulling afterwards -- which fails twice on its own terms, since a fetch does not refresh the working tree and dropping that route's pull would leave its commit on a stale base. Re-running costs nothing: every step is a local file read and none mutates anything, which is why the function is documented as callable more than once. Pinned by a test that mocks the pull into planting an unfamiliar field. | R23.4, I34, Task 21, Task 6 |
| 2026-09-09 | **The hole Task 6's purity audit handed forward is closed, on the same route.** `.datom_sync_metadata()` copied a per-artifact metadata document from the clone straight to storage with nothing checking its declared format, so a document pulled from a collaborator on a newer datom went through unexamined. The entry sequence now runs `.datom_check_schema_version(operation = "write")` on each per-artifact document alongside the vocabulary check. Worth noting the two items are one item: it is the same route whose door read goes stale, so the re-check above is what makes the closure hold rather than only appearing to. | Task 21, Task 6, R23.1a |
| 2026-09-09 | **`tables` is on the manifest vocabulary, marked retired, and that is the append-only rule made mechanical.** The list holds the five names a manifest carries plus the artifact list's pre-v2 name. In practice the conversion renames the key before the check sees it, so the entry earns its place two other ways: it is the worked example of retiring a name by marking rather than deleting, and it is insurance if the check is ever consulted on an unconverted document. AC35(c) tests exactly this, and pruning the name reddens it. The reason it matters is directional and easy to get backwards -- a build that forgets a name meets an **older** document, fails to place a key it should know, and refuses it, blocking the upgrade direction, which is the one direction that must always work. | R23.2, I31, AC35(c) |
| 2026-09-09 | **The vocabulary check runs on the CONVERTED manifest, never the raw one.** Getting this backwards deadlocks the forward path by a different mechanism than the one R23.4 warns about: a pre-rename document holds its list under `tables`, so a check on the raw document would refuse every existing repo. Same shape of trap as R23.4's own wording -- "refuse when the expected key is absent" versus "still absent after the chain has run" -- and both are settled the same way, by asking what the conversion can reach rather than what the file says. AC35(d)'s test asserts a v1-shaped clone manifest writes normally, **and asserts the pre-state**, so it cannot pass by the fixture edit silently not having taken. | R23.1, R23.4, AC35(d) |
| 2026-09-09 | **AC36(c) is not implemented, and it is not owed by Task 21.** "Setting a floor above the setting build's own version is refused" is a guard on the **setter**, and R23.3 defers the setter (a normal commit cannot validate that the raiser satisfies the new value, so it needs a purpose-built verb -- the R15 named-verbs precedent). No code path in this build sets the field, so the clause has nothing to bind to. It ships with the raising verb; the `dev/README.md` Backlog row for that verb owns it. Recorded rather than left as an absence, because Task 21's criteria line names AC36 whole and silence there reads as an omission. | AC36, R23.3, `dev/README.md` Backlog |
| 2026-09-09 | **A malformed floor value aborts rather than being read as no floor.** `min_writer_version` is optional and absent means no limit, which makes the tempting implementation `if (is.null(x) \|\| !parses(x)) return()`. That turns a typo in a policy field into a silently disabled policy -- the failure the mechanism exists to prevent, arriving through the mechanism. Refused with its own class, `datom_writer_floor_invalid`, and the message says how to mean "no floor" (remove the field). Same call as the schema check's refusal of a present-but-unusable `schema_version`, for the same reason. | R23.3, Task 21 |
| 2026-09-09 | **Artifact discovery is one helper, because the door has to inspect exactly the set the route writes.** `.datom_clone_artifact_names()` (`R/sync.R`) was factored out of `.datom_sync_data_metadata()`, which now calls it too. On the mirror-everything route there is no artifact name in the arguments at all, so the door enumerates -- and discovering the set twice, in two spellings, is how the door ends up checking a different set than the one that gets written. The discriminator stays what it was: a directory holding a `metadata.json`, with the fixed non-artifact directory list as a convenience rather than the test, so a foreign directory is tolerated (R14.2) rather than misread. | R23.1, R14.2, Task 21 |
| 2026-09-09 | **Task 21 makes all three of Task 20's coded levels unreachable through `datom_write()`, and the four round-trip tests now hold the door open with a mock.** Expected, predicted, and not a reason to remove the merge. What stays genuinely live is the **version-history entry**, which R23.1 does not scope -- so the test written for it in Task 20's review round is the load-bearing one rather than belt-and-braces. The merge is kept and kept tested for one forward-looking reason: the day a release widens what the door accepts, the merge behind it has to already work, and a merge that quietly broke while unreachable would ship as a silent field deletion on the first write that got through. The mock is named `fc_hold_door_open()` with the reasoning at the fixture, so nobody later reads it as a test working around its own subject. | AC34, AC35, Task 20, Task 21 |
| 2026-09-09 | **Live code citations re-derived by content for a fourth consecutive session; dated rows left frozen.** This change shifted lines in five `R/` files, and eight distinct citations had drifted: the two routing returns, the mirror route's manifest read, the entry updater, `datom_sync_manifest()`'s read and its artifact lookup, `.datom_has_changes()`'s storage read, and the local metadata write's `git_paths`. Two of them were already wrong before this session. Repointed only where the citation is a live instruction -- dated Decisions rows record what was true on their date and stay frozen per the 2026-08-23 policy. Check 5 sees none of this class: it asserts only that a cited line is not blank. | dev/check-spec.R, Task 21 |
| 2026-09-09 | **REVIEW OF TASK 21: the write entry goes on the FUNCTION, not on each caller.** `datom_validate(fix = TRUE)` reaches storage by calling `.datom_sync_data_metadata()` directly (`R/validate.R:183`), so it never passed `datom_write()`'s door -- no floor, no vocabulary, no per-artifact format check, while the NEWS entry claimed the checks covered every write route. Bounded damage, because that route copies documents rather than rebuilding them, so nothing was being deleted. **The argument that settles it is the floor's**: its stated purpose includes a block for a reason that is *not about format* ("0.1.4 wrote bad hashes"), and those cannot be enumerated ahead of time -- so "this route only copies" cannot license skipping it. Fixed by moving the call into `.datom_sync_data_metadata()` after its role and path guards; the `datom_write()` route now runs the sequence twice, which costs nothing and means the next caller cannot forget. **This is the third task running in which this route has been the gap** (Task 6's open call 1, Task 6's purity audit, now this), which is the more durable finding: a repair verb that reaches storage without going through the write verb will keep being missed, so gate the shared function rather than the entry points. Probed: removing it reddens two tests. | Task 21, R23.1, R23.3, `R/validate.R` |
| 2026-09-09 | **A probe caught a test asserting the wrong thing, which is the reusable part of this round.** The mirror route read the manifest with the shared reader's default `operation = "read"`, so a too-new manifest on its way to storage reported a format this build "cannot read" -- during a write. One argument fixes it. But the test written for it **passed with the fix reverted**, because the entry sequence refuses a too-new manifest a few lines earlier with the right verb already, so the abort came from there. The test now mocks the entry out so the read answers for itself, and reddens on reversion. Kept rather than dropped as unreachable, on the rule this spec applies elsewhere: a message that is correct only because something upstream refused first starts lying the day the refusal moves. **The transferable bit is the method** -- the probe was what distinguished "my fix works" from "something else already covered this", and reading the code would not have. | Task 21, Task 6, R22.4 |
| 2026-09-09 | **ACCEPTED RESIDUAL: the door's answer can be stale on the table-write route, and re-checking cannot fix it.** `.datom_git_push(pull_first = TRUE)` pulls at step 7 (`R/read_write.R:849`), **after** step 6 has written the metadata document and edited the manifest -- so a collaborator's newer-format document can arrive after the door passed, with the write already built. The metadata-only route's remedy (re-run the sequence after the pull) does not transfer: there is nothing left to re-check before. Left as it is deliberately, because the backstop is real and design 10.7 already argues for exactly this trade -- the push aborts on rejection or on a merge conflict, the storage steps are 8-10, so a write cannot reach storage from a base this build has not seen, and abort-after-commit is acceptable for a rare race while unacceptable as a primary mechanism. Recorded because Task 21's summary said the staleness problem was "solved", which holds for one route and overclaims for the other. | design.md 10.7, I34, Task 21 |
| 2026-09-09 | **COLD-START AUDIT FOR TASK 22: startable, after eight additions to its body. No escalation flag on it** (design.md 12 carries E1 and E2 only), so nothing is owed under rule 5d. Every claim in the task was checked against the tree; two of its own citations had drifted and are repointed, and its "`original_format` never reaches metadata" claim verifies. **The one that would have done real damage: the test surface is three files and eight assertions, not "the assertion in `test-query.R`".** Every `datom_schema_unsupported` assertion was enumerated and split into the six that must flip to warn-and-rebuild and the nine that must not be touched -- including the load-bearing one, `.datom_read_manifest`'s own returned-versus-thrown contract test, which the task's body did not mention at all. Leaving five of them would have left the suite asserting the opposite of the design, which is this spec's recurring defect arriving in the one place the task itself says it must not. **Two findings shrink the task.** Task 21 already shipped the **writer** half of R22.11 -- a too-new manifest and an unreachable shape both already refuse at the write entry -- so what is left is the reader half plus `original_format`. And R22.10's dispatcher guard plus AC38(b) and (c) were already done by Task 6, with the zero-steps test counting step invocations through a mocked step table rather than comparing output. **One finding removes the hard part**: Task 21 gave `.datom_read_manifest()` an `operation` argument for a message-wording reason, and every writer call site already passes `"write"` -- so "reader rebuilds, writer refuses" is a branch on an argument that already exists, with no role inspection and no new plumbing. **Three findings are traps.** A rebuilt entry must stamp `kind = "table"` or every counter reads zero, because R22.8 deliberately has no missing-`kind` fallback and the field is not in per-artifact metadata until Task 7. `original_format`'s classification is a real decision -- `original_file_sha` is already in the identity list, so the symmetric choice would re-mint a version for every imported table in every repo. And AC37(c)'s empty-repo fixture must be current-shaped, since an empty **v1** manifest legitimately does trigger a rebuild. **One correction to an earlier audit**: a Task 6 row claims `.datom_validate_tables()` enumerates artifacts from a storage listing. It enumerates from the **clone** (`R/validate.R:386`), which matters because the rebuild exists for the reader who has no clone -- so there is no storage-side enumerator to reuse, only the primitive `.datom_storage_list_objects()`, which returns **full** keys. | Task 22, Task 21, Task 6, R22.8, R22.10, R22.11, R22.12, AC37, AC38 |
| 2026-09-09 | **`dev/check-spec.R`'s citation check now covers `tests/testthat/` as well as `R/`, and it found three stale citations on the round that added it.** The gate had guarded only `R/file.R:NNN`, so every test-file line number in this spec was unchecked -- including Task 5's and Task 6's lists of the tests that must **not** be swept, which are instructions a reader is meant to walk. Task 22 made the gap expensive: it has to flip six named assertions and leave nine others alone, and a stale number there points at the wrong assertion in a file of a thousand lines rather than at nothing. One regex. It immediately failed on three pre-existing citations (`test-summary.R:163` and `test-sync.R:1283` had gone blank; seven more resolved to unrelated lines and were repointed by content), and it was **verified by planting a wrong number and confirming a FAIL**, per this spec's rule that a green run is not evidence. Same lesson as the round that added check 6: the checks that matter are the ones derived from a defect that already shipped, and this one had shipped invisibly in two task bodies. | dev/check-spec.R, Task 22, Task 5, Task 6 |
| 2026-09-10 | **A rebuild persists nothing, at any role -- stricter than the design required.** Design 10.4 only constrains a **storage-only** reader to rebuild in memory, which left writing the clone's copy available for a developer. Not taken. A read that quietly rewrote a repo's index is a larger surprise than the one it is fixing, and the recorded copy is repaired by the next ordinary write anyway -- so persisting buys nothing and costs the "reads never write" property that makes the rebuild safe to reach from five call sites. Recorded because the design text reads as permission. | design.md 10.4, R22.12, Task 22 |
| 2026-09-10 | **Which recorded version is the current one is a decision the requirement does not make.** "Read the `version` from `version_history.json`" reads as "take the newest entry", and that is wrong in a case that already exists: a write reverting to content already in the history appends **no** entry (`exists_already` in `.datom_write_metadata_local()`), so the current state is an older row and the newest one describes different content. `.datom_recorded_current_version()` narrows by `data_sha` first -- one match settles the revert case -- and by the `created_at` that a history entry copies verbatim second, which separates two metadata-only versions of the same content. Nothing is recomputed in any branch, and a history recording nothing usable yields a row with **no** version rather than a manufactured one, because an index pointing at a version that does not exist is worse than one admitting it does not know. | R22.12, AC37(e), Task 22 |
| 2026-09-10 | **`original_format` is classified NOT identity.** Its sibling `original_file_sha` is in the identity list, so the symmetric choice looks right and is wrong: this build already writes `original_format` onto the manifest row and is only now persisting it into metadata, so in identity it would re-mint a version for **every imported table in every repo**, on content that did not move -- destroying the task's own claim that the field is additive and free. The extension also says nothing about the data that `data_sha` does not already fix. | R9.5, AC33(d), Task 22 |
| 2026-09-10 | **AC37(f) has one exception, stated at the assertion rather than left implicit: `last_updated`.** The writer stamps the wall clock at the moment it rewrites a manifest row, and that moment is in no document -- so a reconstruction cannot reproduce it. The rebuild uses the version's own `created_at`, which is the closest true statement available. The test asserts every other field equal and this one present and plausible, and says why, so the next reader does not "fix" it by inventing a timestamp. | AC37(f), Task 22 |
| 2026-09-10 | **All eight assertions Task 22's audit told us to flip PASSED UNCHANGED after the code change, for the wrong reason.** The mock storage in those tests had no listing, so the rebuild failed and the original schema refusal was re-signalled -- the same class the old assertions checked for. A green run would have shipped a suite asserting the opposite of the design, in the one place the task body said that must not happen. The audit's enumeration is what caught it; nothing in the suite would have. **The transferable rule: when a behaviour flips, the old assertion passing is evidence of nothing until you have checked which code path satisfied it.** Each flipped test now says AMENDED and states what did **not** change, since AC32's reason still holds. | AC32, AC37, Task 22, Task 5 |
| 2026-09-10 | **Two R-level traps that make a condition's class disappear on its way to a handler, both hit in one session and both now in `dev/engineering-notes.md`.** They matter here because the whole reader/writer fork is decided **by** class: a compatibility refusal has to keep travelling while a storage failure becomes a return value. (1) `stop(cnd)` inside one `tryCatch()` handler is caught by that same `tryCatch()`'s `error` handler -- so the natural spelling "re-raise this class, catch everything else" does the opposite, and it turned every refusal raised inside the rebuild into an IO failure. Catch once, decide afterwards, re-signal from outside every handler. (2) `purrr::map()` re-signals a mapped function's condition as its own `purrr_error_indexed`, with the original demoted to a `parent`, so `inherits()` is FALSE and a class-specific handler never fires -- which is why the artifact loop in `R/manifest-rebuild.R` is `lapply()` and must stay `lapply()`, with the reason at the site. Both defects go green in a suite that only checks that something failed. | dev/engineering-notes.md, Task 22 |
| 2026-09-10 | **A rebuilt row is stamped `kind = "table"`, and Task 7 owns that line.** Per-artifact metadata does not say what kind an artifact is until Task 7, so the rebuild has nothing to recover the field from. Hardcoding is not optional: R22.8 deliberately gives the counters no missing-`kind` fallback, so an untyped row is silently uncounted and a rebuilt repo would list its artifacts while reporting zero of them. Correct today because nothing writes a set until Task 9. The comment at the site names both tasks. | R22.8, Task 22, Task 7, Task 9 |
| 2026-09-10 | **Live code citations re-derived by content for a FIFTH consecutive session, and this round the test citations dominated.** Four `R/` citations had gone blank (two in `R/read_write.R`, one in `R/utils-sha.R`, one in `tests/testthat/test-summary.R`) and **fifteen test citations** needed repointing because this change renamed tests in three files -- the flipped assertions Task 22's audit had named by line. Check 5 caught only the four blank ones; the other eleven resolved to unrelated lines and were repointed by content. Dated Decisions rows left frozen per the 2026-08-23 policy. The 2026-09-09 round that extended check 5 to `tests/testthat/` predicted exactly this cost and was right to. | dev/check-spec.R, Task 22 |
| 2026-09-10 | **REVIEW OF TASK 22, finding 1: the hardcoded `kind = "table"` on a rebuilt row now has a forcing function instead of a comment.** The review said "nothing fails" when Task 7 adds `kind` to the metadata builder, which is not quite right -- `test-utils-sha.R`'s pinned fixture list reddens, because it asserts the builder emits exactly a named set. But it reddens in a test about identity hashing and says nothing about the rebuild, so the revisit still depended on somebody remembering. A test in the rebuild's own file now asserts the metadata builder emits **no** `kind`, next to the line that hardcodes it, with instructions for what to do when it fails. **The failure it prevents is the one Task 6 exists to prevent**: once Task 9 writes a set, a rebuilt repo would type it as a table, so the set counters read zero while the artifact still appears in `datom_list()`, and nothing errors. Probed: adding `kind` to the builder reddens that test and no other. | R22.8, Task 22, Task 7, Task 9 |
| 2026-09-10 | **REVIEW OF TASK 22, finding 3: no history entry matching the current content now returns NO version, where it had fallen back to the newest entry.** The fallback and the test two lines from it disagreed. `.datom_recorded_current_version()` narrows candidates by `data_sha`; when nothing matched it took the newest entry, which is a version of **different content** -- while the neighbouring test pins that three other unusable histories yield no version at all, on the stated grounds that a manufactured version is worse than a missing one. Fixed in favour of the test, because it is the same trade the carry-forward rule already makes: a claim that outlives what it described is worse than an absent one. No match means the history does not record the state `metadata.json` describes -- a truncated or partly-synced history, which `datom_validate()` owns. The remaining ambiguous case still takes the newest **candidate**, and that is different in kind: both candidates describe the current content, so the worst case is naming the wrong one of two versions of the same bytes. Probed: restoring the fallback reddens the new test. | AC37(e), Task 22 |
| 2026-09-10 | **ACCEPTED RESIDUAL from the Task 22 review: the rebuild repeats on every call, and nothing memoises it.** One listing plus two reads per artifact means a 300-artifact repo spends ~601 storage requests **per command** for as long as the index stays broken, and `datom_status()` reads two copies of the manifest, so a repo broken on both sides pays twice in one call. The user experiences it as datom hanging, because the warning only arrives once the work is finished. That is precisely the cost the manifest exists to avoid (`dev/datom_specification.md:1694`). Not fixed, and the reason is not effort: a session cache is already deferred package-wide pending its invalidation design (`dev/datom_specification.md:2031`), so memoising here would put session state into a library that has none, in order to speed up a state the next ordinary write removes. Recorded in the `R/manifest-rebuild.R` file header as well as here, the way the table-write staleness residual was, so it is met as a known trade rather than as a surprise. | R22.12, Task 22, dev/datom_specification.md |
| 2026-09-10 | **NEW TASK 23 -- `project.yaml` gets a format number, and the general rule for which mechanism a document gets.** Accepted from a proposal, with three of its premises corrected. **The rule is the durable part**: a **machine-written** document (manifest, per-artifact metadata) gets a **vocabulary check**, because an unrecognised key there *is* evidence a newer datom wrote it; a **hand-edited config** (`project.yaml`) gets a **version number**, because an unrecognised key there is as likely a typo or a private note, and refusing on one would block every write in the repo until somebody found it. AC39(d) tests that a stray key is still tolerated, which is what stops the vocabulary check being extended to that file later as a tidy-up. **Three corrections to the proposal, recorded so they are not inherited as fact.** (1) `project.yaml` is **not** the only datom-owned document without a format number -- `version_history.json`, `governance.json`, `ref.json` and `dispatch.json` have none either; only the manifest and per-artifact metadata carry one. It is the only **hand-edited** one and the only one carrying writer policy, which is the argument that actually supports a number. (2) The harm is not "running `datom_sync()` on a set": Task 11's own body says today's behaviour on a product repo is a silent **no-op**, so an older build gets an unhelpful answer rather than a corrupting one. (3) Once a repo holds a set, an older **writer** is already stopped by Task 21's vocabulary check, because Task 7 adds `kind` to metadata -- and per R9.5 that addition moves **no** number, so a number would never have caught it. **The window this protects is therefore narrower than proposed: a product repo that does not yet hold a set**, which is exactly the state right after init and the state in which somebody reaches for `datom_sync()`. The stronger motivation the proposal did not make is that **`min_writer_version` already lives in that file** (Task 21), so it already carries policy an older build silently ignores; the number is the general mechanism that makes the *next* policy field enforceable rather than advisory. **One verified finding the proposal left as "confirm this": one gate does NOT cover every read.** `.datom_resolve_data_location()` re-reads `project.yaml` after a git pull (`R/ref.R:327`) and is called from `R/conn.R:1030`, *after* the parse at `R/conn.R:937` -- so a config arriving in that pull is unchecked, and `conn$min_writer_version` is read from the same pre-pull parse (`R/conn.R:1081`), meaning a pulled floor raise is missed in that session too. Pre-existing; the task must either gate the re-read or record the residual, not omit it. | R9.8, AC39, Task 23, Task 11, Task 21, R23.1 |
| 2026-09-10 | **Task 23 executes immediately before Task 11 rather than last, and Task 11 states the dependency.** The proposal put it at the end of the list with a note that it "must ship in the same release as Task 11". Same guarantee, but enforced by memory at release time -- and the failure it insures against is precisely a release split with Task 11 in the earlier half. Making it the task immediately before Task 11, with the dependency written into Task 11's body, makes the constraint structural and removes the cross-reference that would otherwise have to be kept true in two places. Phase E's own filter argues for this: an irretrofittable half belongs early relative to the thing it protects, not at the end of a list where it can be deferred while the thing it protects ships. | Task 23, Task 11, Phase E |
| 2026-09-10 | **The execution order was swept in one copy of three, and `check-spec.R` check 6 now guards it.** Adding Task 23 updated the state block's order and left Phase E's preamble and the `dev/README.md` status cell both saying the sequence ended at Task 7. **Found by the owner reading the file, not by the gate** -- which is the same defect class check 6 was built for, arriving in a third kind of content after the encoder pseudocode and the AC bounds. Check 6 now extracts every arrow chain beginning `18 -> 19` from all three spec files **and** from `dev/README.md`, and fails when two copies disagree, naming which one is behind. Two design points worth keeping: the copies are compared **against each other** rather than against an expected sequence, because the order changes legitimately and a gate holding today's answer would need editing every time it moved -- which is how a gate stops being trusted; and the text is collapsed to one string before matching, because the state block's copy **wraps across two lines**, so a line-by-line scan sees two short chains and the disagreement hides in the split. Verified by reintroducing the exact defect the owner found, and separately by staling only the README: both FAIL. `dev/README.md` is read for this one clause only, since that is where the third copy lives and the copy a person meets first. | dev/check-spec.R, Task 23, Phase E |
| 2026-09-10 | **COLD-START AUDIT FOR TASK 7: startable, after two corrections to its own body, one property rescoped and five additions. No escalation flag** (design.md 12 carries E1 and E2 only), so nothing is owed under rule 5d. **Two statements in the task were wrong.** (1) It cited "design.md section 4 matrix" for the set's collapsed field set; section 4 is about tags replacing structure and contains **no** field matrix, so the citation sent a fresh reader after a table that does not exist. The authoritative list is **R1.3** (seven named fields) with R1.4 for the exclusions. (2) It said to **keep `document_sha` out of the metadata document**, which contradicts R1.3 -- that field is one of the seven -- and would break the read gate, since R7.1 requires the stored payload verified *before parsing* and the reader has nowhere else to get the expected hash. The Task 20 concern behind the old wording does not survive R1.3 either: carry-forward only matters for a field **nothing writes**, and once the set builder writes it no rewrite can lose it. **The finding that would have done real damage: adding `kind` re-mints a version for every existing table, and a fresh session would have read that as a defect.** Verified by computing the hash both ways. It is an accepted owner decision (2026-08-23) that lives **only** in a dated Decisions row, and both fixes a fresh session would reach for were closed off in that same decision -- `kind` cannot leave the hash (a table and a set could then share a version identity) and cannot live only in the manifest (AC4's cross-kind check reads it from per-artifact metadata, because the manifest can lag a partial write). Now stated in the task body. **P36 rescoped**: its first clause said adding *any* field leaves every `metadata_sha` unchanged, which is false for a field added **into** identity and therefore contradicted that decision -- the same correction P35 and AC32 needed when Task 22 changed their subject. **Three additions.** Task 7 **legitimately moves two pinned goldens** (`test-utils-sha.R:1002`), which is the first licensed exception to "if a golden fails the code drifted"; the tests it reddens are **six** sites, now enumerated with live citations rather than left to be found; and the sixth of those (`test-manifest-rebuild.R:381`) is a **handoff**, not a failure to silence -- it exists to make this task change `R/manifest-rebuild.R:200`, where a rebuilt row is stamped `kind = "table"` because nothing in metadata says otherwise, and deleting the test instead leaves a rebuilt set reported as a table with the set counters reading zero. Also recorded: the set builder's two concrete values (`.datom_canonical_set_hash()` for `data_sha`, the literal `"datom-sv1"` for `hash_algo`, both easy to get wrong by copying the table builder), that `document_sha` is **inert until Task 9** so whether its plumbing lands here is a choice with a stated default, and that all three acceptance criteria are assertable here on the **builder's output** only, since nothing writes a set until Task 9. | Task 7, R1.3, R1.4, R7.1, R7.2, P36, AC33, Task 9, Task 19, Task 22 |
