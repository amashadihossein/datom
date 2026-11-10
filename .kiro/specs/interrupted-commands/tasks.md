# Tasks -- interrupted commands finish on a re-run

**Issue**: [#155](https://github.com/amashadihossein/datom/issues/155).
**Branch**: `spec/interrupted-commands`, from `dev` at `347a403`. PRs into `dev`.
**Tier**: 3. One commit per task. **Full suite before every commit**, count in the message. The count
must not drop unless the commit message names each removed or merged test and why (tasks 2, 3 and 6
rewrite or delete tests that assert today's order). Each new guard is probed once against its own
test file (conventions item 2a), result in the commit message. **Checkpoint after every task**: post
what shipped and wait for the owner's go-ahead before the next one.
**Test baseline**: 5142 expectations, 0 failed, 0 skipped (`dev` at `347a403`).
**Order**: 1 -> 2 -> 3 -> 4a -> 4b -> 5 -> 6 -> 7 -> 8 -> 9 -> 10 -> 11.
**Model escalation flags (set at planning):**
- **Design spot-check before task 2**: it changes the core write path.
- **Design spot-check before task 4a**, covering all of heal (4a and 4b): every write command calls it.
- **Purity audit after task 8**: tasks 2-8 touch many files across several modules.
- **Test coverage review before task 10**: confirm every guard was watched going red, and check the
  break table below against the tests that exist.

## The yardstick for every review (requirements D14)

| # | Scenario | How often | What datom does |
|---|---|---|---|
| S1 | One developer, normal write or sync | Almost always | Nothing new to notice |
| S2 | An outage mid-write or mid-sync, then the same command re-run (a teammate may have pushed meanwhile) | Regularly | Finishes on its own |
| S3 | A crash or Ctrl-C mid-write, then any later command | Occasionally | The same command re-run resets and finishes on its own; any other write stops and names `datom_validate(fix = TRUE)` (D14 principle 8) |
| S4 | Storage fails after the push | Occasionally | The same command re-run, or `datom_validate(fix = TRUE)`, publishes; any other write stops and names that fix |
| S5 | `datom_init_repo()` interrupted | Occasionally | Before its push: rolled back, a re-run starts afresh. After it: the stop names the repair, which finishes (D5 reversed 2026-11-08) |
| S6 | A teammate pushed earlier; this clone is behind | Occasionally | Pulls at the start, on its own |
| S7 | Two developers' work overlaps (a merge conflict, a publish race) | Rarely | Stops before harm with a short message, or reports; the manual step is supported |
| S8 | An older datom, hand edits, files changed in storage by hand, the user's own git operations in the clone | Rare, unsupported | Documented only; never left stuck (D14, principle 7) |

A finding names its scenario. An S7 finding defaults to "stop with a message" (or a report from
`datom_validate()`), an S8 finding to "document". Every stop and every report names a way out, and the
recovery a stop message gives is traced once before it is adopted. An automation for a rare case is
added only when the manual alternative would mean hand-editing datom's JSON, and only where the
common path never reaches it.

## Where things stand

Requirements approved 2026-10-28 (amended the same day: R3.3, R5.5, R7.8, an R8 row, and D13 with
R3.1 and R9). Design approved 2026-10-28 with decisions DD1-DD4. **Task list approved by the owner on
2026-10-28**, after the four reviews below. **Task 1 done 2026-10-30. Task 2's design spot-check done
the same day (below). A review of `058f29b` on 2026-10-31 (below) changed tasks 4a, 5 and 6, and a
review of `bfad26c` the same day closed spec review (below). Task 2 done 2026-10-31, and task 3 the
same day. The design spot-check before task 4a (covering 4a and 4b) was done and closed with the
owner the same day (below): a write now heals only the artifact it is writing. Two reviews by
another agent followed (of `4045fbd` on 2026-11-03, of `d616e98` on 2026-11-04, both below), and a
publish-branch rule was split out as #156. Task 4a's two open points were settled on 2026-11-04.
Task 4a done the same day (its entry below lists what differs from the plan); its checkpoint
review on 2026-11-05 (below) found two fixes, made the same day, and one point for task 4b, settled
the same day (heal takes two lists). A review of the fixes closed task 4a. Task 4b done on
2026-11-06 (its entry below lists seven differences from the plan, the first being that heal is now
two calls with the command's pull between them); its checkpoint review the same day (below) found
two regressions on the ordinary write path, fixed the same day in `bbab170`. A review of the fixes
closed task 4b the same day. Task 5 (a conflict only in the manifest) done on 2026-11-06 (its
entry below lists six differences from the plan, the first being which version a rebuilt row
names); its checkpoint review the same day (below) approved it with nothing to fix, and task 5
closed. The review's point for task 7 was settled by the owner the same day (task 7's version rule).
Task 6 (scan and sync) started 2026-11-07: its open point was settled by the owner first (a sync
stops after a table's write that failed partway once it had changed the clone; requirements R4.6),
and task 6 was done the same day (its entry below lists eight differences from the plan). Its
checkpoint review the same day (below) found one gap, fixed the same day in `aa4a680`: a held-back
manifest stops the sync too. The reviewer's check of `aa4a680` raised one optional nit, taken the
same day (below). The reviewer's check of that fix (`1718023`) found nothing more, and task 6
closed. Task 7 (the repair) done the same day (its entry below lists seven differences from the
plan, the first being that `datom_validate(fix = TRUE)` now runs the repair whether or not a
check found something). Its checkpoint review the same day (below) agreed with that difference
and found one gap and one ordering fault, fixed the same day with three smaller points in
`ba57f3a`, and the owner closed task 7 the same day. Task 8 (the git and config commands) done the
same day, after its open point was settled by the owner (the stop also looks at datom files already
staged); its entry below lists five differences from the plan. Its checkpoint review the same day
(below) approved it with one point, taken with a second found while checking it, both fixed in
`6921561`. The reviewer's check of `6921561` approved it with one optional nit, taken the same day,
and **the owner closed task 8 on 2026-11-07**. The purity audit flagged after task 8 ran on
2026-11-08 (below); its points 1-6 landed the same day, one commit each (`cc7d6e1`, `b7a254a`,
`9d53b1f`, `7b64414`, `93cee2f` and point 6's), plus `c83cc04` regenerating `man/` for points 1-4,
which their commits had missed. Suite 6244 -> 6263 expectations, 0 failed, 0 skipped. Task 9 done the
same day, reshaped by the owner: no re-run logic for `datom_init_repo()`; its stop after the push
names the repair (D5 reversed; task 9's entry below). The test coverage review flagged before task
10 ran on 2026-11-09 (below); the owner had its four gaps filled before any documentation, in one
commit. Task 10 (documentation) done the same day, after the owner settled its two open points
(its entry below lists six differences from the plan). **Next: task 11 (end to end and spec
completion), after task 10's checkpoint.**

**Test coverage review before task 10, 2026-11-09**, on Claude Opus 5.5, of `347a403..25043b3`:
every task's commit record and probe harness read, and the break table checked against the test
files. Every other check tasks 1-9 and audit points 1-4 added has a recorded probe that reddened its
own tests with a control that reddened nothing, and every other break-table row has a test that
breaks there, re-runs (or follows the stop's way out) and checks what a reader sees. Confirmed
closed: task 4b's `gate_ignores_ahead`, retargeted in `cc7d6e1`; audit points 5 and 6, text and a
rename only; task 4a's reset gate, left unprobed at planning (no observable but cost). The gaps,
filled by the owner's choice (probes in `research/coverage_guard_probes.R`, control green):

| Gap | Scenario | Filled by | Probe reddened |
|---|---|---|---|
| A write whose stored manifest cannot be read (`datom_stored_manifest_unreadable`) had no test; nor the repair's branch for it (warn, publish everything from the clone) | S2 (unreachable), S8 (damaged) | Two tests in `test-heal-publish.R` (a damaged file, then the fix the stop names and the write; storage unreachable, then a re-run), one in `test-repair.R` | the stop removed: both write tests; each "unreadable" read as "absent": its own test; the repair stopping, or not warning: the repair test |
| Heal's stop when it cannot finish publishing an earlier write was tested, never probed | S4 | (tests existed) | the stop removed: "heal's publish failing stops the write ..." and "datom_write(conn, name =) broken at its metadata upload ..." |
| The stop on a `project.yaml` that does not parse was tested, never probed | S8 | (tests existed) | the file read as no floor: the two parse tests in `test-heal.R` and `test-forward-compat.R` |
| `datom_repo_commit(paths = "./dm")` stopping like `"dm"` was never tested | S3 | `"./dm"` added to the path-forms test | the `./` stripping removed: the path-forms test |
| `datom_init_repo()` failing to connect to storage after its push: the test checked the message but did not run the repair | S5 | The test follows the way out to a published manifest and a clean `datom_validate()` | (not a check; nothing to probe) |

**Purity audit after task 8, 2026-11-08**, of `347a403..6921561` under `R/`, on Claude Opus 5.5,
with the owner's request to watch for places where one rule could replace case-by-case handling.
No dead code and no behaviour change found. The list was reviewed by another agent and evaluated
with the owner; points 7-9 stay as they are, points 1-6 are taken, in this order:

| Point | Outcome |
|---|---|
| 1. The push before publishing sat in three places (heal's publish after its checks, the repair's `.datom_repair_push()`, the metadata-only route) | **Taken** (the repair's second publish kept too, owner, 2026-11-08: it is an edge case, and removing it would move code, not remove it): `.datom_publish_artifacts()` pushes first when the clone is ahead (or has no upstream), without pulling, for every caller. The rule: every document readers follow is on GitHub first (data files and set payloads go into storage before their commit, by D1). Kept as they were: heal's gate (it reaches the publish only past its checks), its early push with no upstream, the write's own push with its pull and the manifest recheck. The probes of tasks 4b and 7 are rerun, the moved ones retargeted in `research/audit_guard_probes.R`. Not done: removing the repair's second publish (heal's, then every artifact's), kept on 2026-10-30 so heal stays the same on every route; raised with the owner at this point's checkpoint |
| 2. Three stops for "another artifact has unfinished work" (heal's reset, heal's publish, the blocked pull), each worded differently | **Taken**: one message and one class |
| 3. Four "what has happened" lines chosen through flags passed down the pull and the push | **Taken**: one line, "Nothing was published.", true at every stop before publishing (the review: on a clone with no upstream heal pushes before its checks, so "Nothing was pushed" was already false there). Heal's reset announces each reset itself, so the "put back" line loses nothing. **The data-file line is dropped** (owner, 2026-11-08): a data file stored before a stop is named by nothing and reused by a re-run; design sections 4 and 10 amended |
| 4. Repeated pairs of calls in the git and config commands | **Taken**: one helper for the merge check and the stop before a commit, one for naming what a push carried |
| 5. About 35 spec IDs, review notes and `research/` paths in `R/` comments | **Taken for `R/` only**; test names keep their requirement IDs, which `dev/check-spec.R` traces |
| 6. Stale text: `R/version-commit.R` counts two history uploaders (one since task 7), the artifact finder's help counts three callers (seven), `.datom_commit_and_mirror()` now publishes | **Taken**; renamed `.datom_commit_and_publish()` (no test mocks it by name) |
| 7-9. One wrapper for the three calls every write starts with; healing per table inside `datom_sync()`; small one-line helpers | **Left as they are** |

**Task 8's checkpoint review, 2026-11-07**, by another agent, of `3f48a48`, read against the code;
evaluated with the owner:

| Point | Outcome |
|---|---|
| The review's one point: `datom_repo_attach_governance()` and `datom_repo_set_data_store()` commit one named file, and a commit takes the whole index, so a write stopped between staging and committing (S3) would be committed and pushed with the config change | **Taken, placed earlier**: the review put the stop just before the commit; it runs at the start instead, before the command writes its file, so the stop's "datom changed nothing" is true. D9 and R3.5 amended to name both commands (owner's "ok") |
| Ours, found while checking: the same two commands commit before their push pulls, so the merge check inside the pull comes too late. A probe: during a merge of a local branch left open with `--no-commit`, `.datom_git_commit()` of `.datom/project.yaml` made a two-parent commit and removed `MERGE_HEAD`, finishing the user's merge (S8 state, R3.9's harm) | **Taken** (owner's default): both run the merge check at their start too. No requirements change, R3.9 already covers it; design section 4 updated |
| The reviewer's check of `6921561`: approved, task 8 can close, with one optional nit. In `datom_repo_set_data_store()` the two checks ran after `project.yaml` was read, so with that file itself conflicted (two clones changing the store at once, S7) the command stopped with a raw YAML parser error, naming no way out. Reproduced here first | **Taken** (owner's default): both checks run before the read; the format-refusal test's folder becomes a git repo (it was the reason for the old order). Set aside: running the merge check first only when the folder is a git repo, a condition in the code for a test's sake |

**The owner closed task 8 on 2026-11-07**, after the nit's fix (below in task 8's entry).

**Task 7's checkpoint review, 2026-11-07**, by another agent, of `9284ca9`, read against the code.
Points 1 and 2 reproduced here on throwaway projects before fixing; evaluated with the owner:

| Point | Outcome |
|---|---|
| Difference 1 (`fix = TRUE` always runs the repair) | **Kept** (owner): it is what makes the fix every stop names a way out that works |
| 1. `datom_validate()` counted any folder holding a `metadata.json` as an artifact, the path task 4a missed (S8/P8). A user's own `app/metadata.json` was reported, and the fix, which rightly skips it, could never clear it | **Taken**: discovery through `.datom_clone_artifact_names()`; a test on the P8 fixture, before and after `fix = TRUE`. Checked here: the review said `kind_unsupported`; the folders were reported `metadata_missing_s3,data_missing_s3`, with advice to re-run `datom_write()` |
| 2. Heal's publish ran before the payload restore, so a set committed but not published with its payload gone from storage (S8) had its documents and the manifest published first, and a failed restore left the manifest naming a missing payload | **Taken, reshaped (option B)**: the restore runs right after the pull, before heal's publish, and a failure stops the repair before anything is published. The review proposed carrying on and keeping that set and the manifest out of heal's publish; the stop needs nothing new in heal and removes the `manifest =` argument task 7 had added |
| 3a. A stop inside the repair was caught into one "Repair stopped" alert by `datom_validate(fix = TRUE)` | **Taken (option A)**: it comes through unchanged, as from `datom_write(conn)` (R5.4); a per-artifact publish failure is still reported, with `fixed = FALSE` |
| 3b. "Metadata sync requires ..." | **Taken**: "The repair requires ...". Checked here: `datom_validate()` refuses a reader before reaching it, so only a direct call shows it |
| 3c. The help could say a repair run during a teammate's write can replace their publish (DD4) | **Taken**: one sentence in `fix`'s help |

**Review of `aa4a680`, 2026-11-07**, by the same reviewer: one optional nit, taken by the owner.
When storage's manifest could not be read at step 6's recheck, the write recorded the storage
file's name in place of an artifact, so both the write's warning (since task 4b) and the sync's
stop said the push brought in "a version of '.metadata/manifest.json' that storage does not hold
yet". Checked here: true, and rare (storage was read at the command's start and took the write's
documents in step 5, seconds before). Both messages now say storage's manifest could not be read,
with the read error, and keep the way out (once storage is reachable, `datom_validate(fix = TRUE)`,
then the same call). The warning carries the error as `unreadable`. A test makes the recheck's read
fail and follows the way out; the two held-back probes, rerun on the new handler, redden both
held-back tests.

**Task 6's checkpoint review, 2026-11-07**, by another agent, of `c24b17f`, read against the code.
Both findings reproduced here on a throwaway project before fixing, and evaluated with the owner:

| Finding | Outcome |
|---|---|
| 1. A held-back manifest does not stop the sync (S7). In a sync of `t1` then `t2`, a teammate's write of `ae` has committed and pushed but not yet uploaded its documents; `t1`'s push brings `ae`'s commit in, and `t1`'s write skips the manifest upload with a warning. The sync carried on, and `t2`'s write, whose own push brought nothing in, uploaded the whole manifest naming `ae`'s version while its documents were on GitHub only; a later sync noticed nothing, since the manifests then agreed. The warning's "writes of other artifacts stop" was false inside a sync | **Taken (option A)**: the sync stops after such a write, under either setting of `continue_on_error`; the rows not attempted come back `"skipped"`, and the message names `t1` and `ae` and says to run `datom_validate(fix = TRUE)`, then the same call again (R4.6 amended, design section 7). Option B, each later write re-checking storage before its manifest upload, set aside: it changes the write path and leaves more tables half-published. A test follows the way out to the end; two guards probed |
| 2. The stop's way out, `datom_sync(conn, datom_sync_manifest(conn))`, builds a fresh preview, bringing back rows the user dropped on purpose | **Taken, reshaped**: the review proposed "re-scan, drop the same rows again, then sync". Checked here: the same `datom_sync()` call with the same preview finishes every table after a break at the commit, the push and the manifest upload. Both stop messages now say to run the same call again, with the same preview, and the break-table tests follow that way out |

**Task 5's checkpoint review, 2026-11-06**, by another agent, of `6d622e9`: approved, nothing to
fix. The reviewer re-ran the full suite (+112 checks, matching the commit) and probed three guards
(the version rule, the manifest-only condition, the format check before the rebuild), each failing
exactly the tests the commit lists, with a harmless edit failing nothing. Evaluated with the owner:

| Point | Outcome |
|---|---|
| Keep the version-from-`metadata.json` rule of task 5 (the open question at the checkpoint) | **Kept** (owner) |
| For task 7: its planned `manifest_mismatch_s3` check takes the version from the history alone (`.datom_recorded_current_version()`), which names the wrong version after custom metadata goes `"x"` -> `"y"` -> `"x"`, so it would report a consistent store and its fix would not clear it | **Confirmed here** on a throwaway project: the stored manifest names the first version, the history lookup names the second, before and after republishing from the clone. **Owner chose (a)**: the same rule as task 5, the document's own version only when every field of the stored `metadata.json` is one this build can place and the history names it (task 7's bullets, design section 6). Set aside, (b): a write returning to a version keeps that version's original `created_at` (changes a datom-owned file, new writes only, misses two versions within one second) |
| (b) would also fix the version `datom_read()` gives the current version after a revert | **Not so**: `datom_read()` returns a plain data frame with no version (datom-py's table read too), and a set cannot reach the case (its version hashes content and kind only) |

R5.5 and R7.8 were reworded to that rule the same day, approved by the owner (wording drafted by
the same reviewer; requirements status line). Task 5's checkpoint is closed.

**Review of `bbab170`, 2026-11-06**, by the same reviewer: both fixes verified, and **task 4b
closes**. The reviewer re-ran the full suite (+32 checks, matching the commit); confirmed that
`datom_write()` with `NA`, `NaN`, `Inf` or a missing date anywhere in custom metadata stops naming
the field, before the check for other tables' unfinished work, leaving the clone, GitHub and
storage unchanged, and that a write with no changes leaves the user's own unpushed commit
unpushed; and that removing the new refusal, or restoring the old "push whenever ahead" gate,
fails exactly the matching new test while a harmless edit fails nothing. Agreed with the owner's
refusal over passing the version through. No new findings.

**Task 4b's checkpoint review, 2026-11-06**, by another agent, of `5bdb7da`, evaluated with the
owner one point at a time. The reviewer re-ran the full suite and three of the guard probes, and
agreed with the seven flagged differences. Both regressions were reproduced here on a throwaway
project, and shown absent on `a4cd373`, before fixing:

| Finding | Outcome |
|---|---|
| 1. An `NA` in custom metadata (`datom_write(conn, df, "dm", metadata = list(note = NA))`): `datom_member()` and `datom_parent()` cannot find the version the history names, and `datom_validate()` reports nothing (S1). The publish reads `metadata.json` back from the clone; `NA` is saved as `null`, which reads back as nothing, so the snapshot is filed under a version id no history names. Checked further here: only an `NA` saved as `null` (logical, text, alone or in text) changes the id; `NA_integer_`, `NA_real_`, `NaN` and `Inf` keep it but come back as the text `"NA"`, `"NaN"`, `"Inf"`; and since 4b the stored `metadata.json` said `{}` where it said `null` | **Reshaped by the owner: `datom_write()` refuses a missing value of any type, `NaN` and `Inf` anywhere in custom metadata** (`.datom_check_custom_storable()`, `datom_custom_value_unstorable`), naming each place and saying to leave the field out, as a set's tags already require. The review proposed passing the computed version to the write's publish; with the refusal every accepted value keeps its id through the trip to disk, so the publish keeps reading the file back. A table holding an `NA` from an earlier datom is documented only (design section 12). Requirements amended. The review's follow-up issue for the `NA` round trip is replaced by the refusal; one for **decimals rounded to four places** in storage and in the version id, found while checking, is filed as [#157](https://github.com/amashadihossein/datom/issues/157) |
| 2. A write with nothing to save pushes the user's own unpushed commit (S1, a joint repo): heal's publish opened on "the clone is ahead" | **Taken**: heal's publish is decided by differing manifest rows only, and pushes only to finish a version of its own; with no upstream it still pushes first. Added by this session, taken: `datom_write(conn, name =)` pushes before its own upload of a stored `metadata.json` that differs while the manifest row agrees, which until then relied on heal's push. R3.2 amended; the repair's push of unpushed commits (R5.2) stays the repair's own, in task 7 |
| Nit: the "manifest held back after a failure" probe reddens five tests, not the one recorded in `5bdb7da`'s message | **Taken**: the four others break a write at its metadata upload as their setup, and with the guard removed that broken write already published its manifest. All five are listed in task 4b's entry and the fix's commit |

Owner's direction during the review, recorded in requirements D14 principle 7 already: git is
datom's internal tool, and direct git use in the clone is off the supported path. It did not change
finding 2, since `datom_repo_commit(push = FALSE)`, the supported route, makes the same state, and
datom cannot tell its commits from a plain `git commit`'s without a marker (set aside for merges on
2026-10-31); the fix needs neither.

**Task 4a's checkpoint review, 2026-11-05**, by another agent, of `1958036`, evaluated with the
owner. The reviewer re-ran the full suite on 4a and its parent and five of the guard probes, and ran
the no-upstream test on git2r 0.33.0. The three choices flagged at the checkpoint are kept (the
metadata-only route's push before it publishes, until 4b replaces it; the set-upstream line on a
refused push with no upstream; no `project.yaml` passes the floor, one that does not parse stops).
Both findings were reproduced here before fixing:

| Finding | Outcome |
|---|---|
| 1. `datom_pull()` after a write broken before its commit (S3 + S6): the write's uncommitted manifest blocks the merge, and the stash recipe then leaves conflict markers in `.datom/manifest.json`; every later write stops on a manifest it cannot tie to an artifact, so the only way out until task 7 is hand-merging datom's JSON | **Fixed**: when the pull cannot catch up and datom's own uncommitted files are among the local changes, the stop names the artifact and says to re-run that write (which finishes, traced) or `datom_validate(fix = TRUE)`; only the user's files gets the stash recipe as before. The artifacts are told apart by one helper shared with heal's reset, `.datom_unfinished_owners()`. Same class, `datom_pull_blocked` |
| 2. A crash on a repo whose committed manifest is in the old format (S3; written by 0.1.x): the write converts the manifest as it edits it, so HEAD's rows (v1, no `kind`) and the working tree's all differed, and each write stopped naming the other | **Fixed**: `.datom_manifest_rows_changed()` checks the format of both copies and converts them before comparing, as `.datom_update_manifest_entry()` does. Not a rescue of a broken state (D7): a v1 manifest is a supported format every write converts |
| 3. For 4b: the metadata-only route heals with no artifact of its own, but 4b's publish stops on any differing row the command does not write, and the route's own table is the only one it has work for | **Settled 2026-11-05: heal takes two lists**, what the command publishes (`artifact`) and the subset whose files it writes again (`rewrite`); a yes/no switch was set aside because it goes wrong for `datom_sync()`. Recorded in design sections 2 and 4 and task 4b's first bullet |

The reviewer also listed the interim states that keep tasks 4a-7 in one PR: a merge with only the
manifest left loops on "re-run your write" until task 5; `datom_validate(fix = TRUE)`, which the new
stops name, resets nothing until task 7; another artifact's unpushed commit is still pushed, and its
manifest row uploaded, by a different write until 4b.

**Review of `b6b83b1` and `bcd0e41`, 2026-11-05**, by the same reviewer, evaluated with the owner:
both fixes verified (the full suite, the reviewer's two repros, each new guard reddening only its own
test), and **task 4a closes**. On the open point, the reviewer recommended two lists, with two
additions, all taken (task 4b's first bullet). The reviewer also traced, without a test, datom's
files and the user's own file both in the way: run here, it holds for `datom_pull()` (it names the
write; the write's re-run puts its files back, then gives the stash recipe; the user's edit
survives); `datom_repo_push()` with nothing to push never pulls, so it says "Nothing to push" and
names nothing, which is correct. One optional nit taken into task 4b: the pull's stop says "datom
changed nothing" even when heal has just put back the command's own files.

**Review of this task list, 2026-10-28.** A review by another agent, evaluated with the owner one
point at a time. All fourteen points were taken, several with changes:

| Point | Outcome |
|---|---|
| A. The probes would report false passes once data files go through the new upload | Tasks 2-4 update their probe first, add a step-2 break, and count a row only if its break fired |
| B. Real S3 checked only at the end | A real-S3 probe is part of task 1's acceptance. `paws.storage (>= 0.8.0)`, not the review's 0.9.0: CRAN's sources show `IfNoneMatch` from 0.7.0 and `ChecksumType` from 0.8.0. A 409 is an ordinary upload failure, not "already there" (AWS returns 409 when a delete races an upload, not when two uploads collide). No fallback for a service that rejects the new headers; recorded instead |
| C. The heal task too large for one checkpoint | Split into 4a (reset, pull, check) and 4b (push and publish). P5's write case moved to 4a, since the pull alone makes it pass |
| D. Uneven break-at-each-step coverage | The break table below, one row per command |
| E, F, G. Missing tests | Added to 4b and 6. F counts calls to heal, not to `.datom_git_pull()`: every write's push also pulls, by design |
| H. Where heal runs | Design section 1: argument checks, the format check, the data-location check, hashing and the confirmation prompt run before heal; change detection and the table-or-set check after |
| I. A re-run told to re-run itself | Design section 4: heal's `artifact` takes several names, and the reset message depends on whether the artifact is one the command is about to write |
| J. The pull inside `datom_get_conn()` | Listed under DD2 and accepted; a `datom_pull()` test added to task 5 |
| K-N. Nits | `.datom_check_git_current()` deleted in task 6; the test-count rule above; each old-order docstring assigned to the task that edits its function; resuming #134 part 3b removed from task 11 (`dev/README.md` already says it) |

**Second review of this task list, 2026-10-28**, of `e3d29b0`, evaluated with the owner the same way.
All six points taken:

| Point | Outcome |
|---|---|
| 1. The sync read-count test in 4b could not pass before task 6 | 4b counts the reads of one write; the three-table sync count moved to task 6, beside the heal-once test |
| 2. Heal would run twice on the metadata-only route, and before the prompt on the mirror-everything route | Heal runs in exactly one place per route (design section 4): the data-frame route in `datom_write()`, the metadata-only route in `.datom_sync_metadata()`, the mirror-everything route in `.datom_sync_data_metadata()` after its prompt (task 7 only), the set write in `datom_write_set()`. A heal-once test per route |
| 3. The `>= 0.8.0` floor never tested | Task 1's real-S3 probe gains a third run, `paws.storage` 0.8.0 with `paws.common` 0.8.0, in a throwaway library |
| 4-6. Nits | 4a uses the design's "no storage state heal can change"; the break table says why `datom_sync()` breaks only some steps; the rejected-headers row says paws alone can trigger it |

**Third review of this task list, 2026-10-28**, of `e3d4029`, evaluated with the owner. Both points
taken, the second with a wider outcome:

| Point | Outcome |
|---|---|
| 1. 4a claimed P4 before every route meets it | 4a claims P4 for the routes it heals; task 7 claims it for the mirror-everything route and the repair, with a test |
| 2. The metadata-only route would print "writing it again now" for a write it never redoes | Checking it found the larger issue: the route commits a hand edit of `metadata.json`, which heal's reset would discard. Its documented purpose (editing `dispatch.json`) left with the governance layer, and the supported way to change custom metadata is `datom_write(conn, data, name, metadata = )`. The owner chose to drop hand-edit support and make that explicit (requirements D13): the route passes no `artifact`, so the user gets the reset warning; the convention, help, `NEWS.md` and the specification's route table say datom's own files are not hand-edited |

**Fourth review, 2026-10-28**, of `9f86dad`: wording only, all three points taken. Task 10's acceptance
covers R9.7; "decisions D1-D13" here and in `design.md`; task 4a removes the commit-and-push block of
the metadata-only route, which after D13 has nothing to commit.

**Design spot-check before task 2, 2026-10-30**, of `99ca67c`, by another agent, evaluated with the
owner one point at a time. All five points taken, three with additions:

| Point | Outcome |
|---|---|
| 1. Task 2 cannot drop the `upload` argument of `.datom_commit_and_mirror()`: `datom_write_set()` still passes it | Task 2 stops passing it from `datom_write()`; task 3 removes it, with that function's docstring correction |
| 2. `metadata.json` is uploaded first within step 5, so a break after it makes the re-run report "none" and publish nothing more | `.datom_push_metadata_s3()` uploads snapshot, history, then `metadata.json` last (task 2; design section 1); a break between history and `metadata.json` joins the break table; a guard to probe |
| 3. The resolver checks existence and then the upload checks again | The resolver calls `.datom_storage_upload_absent()` directly; `"exists"` records the stored file's hash (design section 3). Added: the P3 fixture stores the same data in different bytes, or the probe of the `"exists"` branch cannot fail |
| 4. Until 4b a re-run after a push break makes a second commit, and the stored history names it | Task 2's break tests assert only what a reader sees and the recorded hash; 4b tests the first-commit rule. Added: heal's publish passes no commit id, a write's own publish passes the one it made (design section 4, step d) |
| 5. About 22 tests stub the old upload | Added: two of them count uploads and would stay green whatever the write uploads; task 2 re-points them and watches them go red once, task 3 re-points the set-repair one. The shared stub goes in `helper-mock.R`, not `helper-interrupt.R` (it has nothing to do with breaks) |

Also noted by the review, no change: a full write whose content matches a stored pre-cv1 file now keeps
that file and records its hash (R1.2); task 2's resolver docstring says so.

A follow-up from the same reviewer, the same day, of `b1f94fa`: the repair's per-artifact copy
(`.datom_sync_one_artifact()`) uploads `metadata.json` first. Taken in task 7 (design section 6),
with the set's payload moved to the front (data file first), where the review put it third.

A wording fix from the same reviewer, of `1421262`: design section 6 overstated what `datom_validate()`
reports after a repair break; narrowed, with a new section 12 row for a missing current snapshot.
Checking that snapshot in `datom_validate()` was left out of this spec (no route in it can cause the
gap; it belongs with the other storage-completeness checks validate lacks) and goes to a follow-up
issue, filed as [#158](https://github.com/amashadihossein/datom/issues/158) on 2026-11-09 in task 11.

A further review by the same reviewer, of `ac54763`, evaluated with the owner one point at a time.
Point 1 was confirmed by a real write (2026-10-30): no datom command puts `{name}/.metadata/` in a
clone, so the repair's snapshot loop copied nothing.

| Point | Outcome |
|---|---|
| 1. The repair cannot restore snapshots: the clone never holds them | Confirmed. Four statements corrected (design sections 6 and 12, the draft issue). Added: "Published" includes the snapshot, so the repair has never published in the requirements' sense (R5.2) |
| 2. 0.2.0's metadata-only route is a source | Confirmed by a probe, but of a different state: the stored `metadata.json` describes a version nothing records, while readers are told the previous one. Its own row in section 12 and its own item in the draft issue |
| 3. The repair uses the one publish path | Taken (task 7, design section 6); `.datom_sync_one_artifact()` deleted. Added: the manifest is published only if every artifact was (task 4b) |
| 4. The clone-folder loop | Deleted with its function; the affected tests and notes listed in task 7 |
| 5. (added) Which version a publish from the clone names | The recorded version, never a recompute; the snapshot written only when the document hashes to it, else skipped with a warning that does not hold back the manifest (task 4b, design section 4) |

A final read of task 2 against the code, with the owner, the same day, after `4009717`. Two findings:
the modification-time checks that four table tests use to prove "no upload" cannot fail once the
upload never overwrites, and one of them is the only guard of the history-reuse branch (task 2
re-points them to count upload calls and probes the branch; task 3 does the same for one set test);
and a version can pair a stored file's hash with the fresh file's size, as the metadata-only and
revert paths already do (a docstring sentence, no code change). Checked with no change: no refusal
that can fire comes after the new first-step upload, the history lookup reads the clone, no table
test asserts the old order.

A review by another agent of `bfe176d`, evaluated with the owner the same day (agreeing with the rest
of `4009717` and `bfe176d`): `metadata_stale_s3` recomputes the version of both documents, like for
like (task 7, design section 6); heal's stop on a publish that fails every run names the artifact,
the file and the error, and for a file that does not parse gives the way out, restore it from git and
commit with `git` (task 4b, design section 4, a section 12 row). The reviewer asked whether a write
of that artifact may skip its own failed publish: no, since a broken history stops that write anyway.
R9.5 is not amended; the instructions live in the stop message. The repair publishing behind
artifacts twice (heal, then the repair) is kept, with one sentence in section 6.

A full-spec review by another agent of `b76961b`, evaluated with the owner one point at a time the
same day. All five findings taken (several later reshaped by the simplification pass below); settle
1-3 before task 4a and 4-5 before 4b:

| Finding | Outcome |
|---|---|
| 1. Heal undoes the documented recovery from a merge conflict | Heal's new step 0 stops on a merge in progress and touches nothing (task 4a). Requirements amended: R3.9 added, R8's merge row and R3.8's last sentence corrected (owner: datom must call out a merge in progress, never quietly change files during one). Added: the conflict message's "nothing written to storage" is false from task 2 |
| 2. Heal's reset can reach a user's `metadata.json` | `.datom_clone_artifact_names()` counts a folder only if the manifest names it or its `metadata.json` declares a datom `hash_algo`, for all three callers (task 4a). Added: today's repair publishes such a folder, and the format check reads it |
| 3. Heal publishes artifacts the format check never looked at | `touch` decides what the check reads, separate from `artifact`; step d checks what it publishes (tasks 4a and 4b) |
| 4. Heal's stop restores only the broken file | Restore all of the artifact's datom files from one commit. A probe added: `git checkout --theirs` does nothing to a file that merged cleanly, so the merge instructions use `git checkout MERGE_HEAD --` (design section 10) |
| 5. A raw parser error on a write | One shared reader for the clone's datom files gives heal's stop message (task 4b) |

**Simplification pass, 2026-10-30**, set by the owner after fixes had been piling up one review at a
time: principles and a scenario table, now requirements D14 and the yardstick at the top of this
file. Six cuts proposed by another agent (of `7716e50`), each evaluated with the owner against the
question "what must the developer do by hand, and does datom support it":

| Proposed | Outcome |
|---|---|
| 1. Drop the automatic fix for a conflict only in the manifest | **Kept, simplified.** It is S2 plus S6 (an outage, then a teammate's push), and the proposed manual recovery, taking the remote's manifest and re-running, leaves the manifest silently wrong once heal publishes first (traced). The rebuild now compares rows with their artifact's files instead of diffing against the merge base (task 5) |
| 2. Drop `metadata_stale_s3` | **Replaced** by `manifest_mismatch_s3`, storage checked against itself: no fetch, no behind-clone skip, no like-for-like rule, and it names the fix. R5.5 and R7.8 rewritten (task 7) |
| 3. Drop heal's `touch` and the check of its publish list | **Taken.** After a merge, the format check reads every artifact; without a merge nothing new arrived (tasks 4a, 4b) |
| 4. Key snapshots by the document's own version | **Taken.** The recorded-version keying, its agreement check and the skip rule go (task 4b) |
| 5. Shorter recovery messages | **Taken, with one change**: the merge check finishes the merge itself once only the manifest is left, so the user takes the remote copy of the conflicted artifacts' files, `git add`s their own, and re-runs; no hand-edited manifest, no `git commit`. R3.9 reworded |
| 6. One merge check for every git-touching command | **Taken**: called by the pull, by heal before its reset, and by `datom_repo_commit()` before its reset (tasks 4a, 5, 8; since 2026-10-31 `datom_repo_commit()` stops instead of resetting) |

Also decided in the pass:
- **Check-then-heal**: heal's reset and publish run only when their own check finds something. The
  merge runs only when the clone is behind, and the format check runs again only after a merge. A
  test (P12) pins that the common path writes nothing before the command's own work.
- **The pull belongs to the commands**, not heal. R3.7 now says no command writes to the git
  remote or to storage before it has pulled, and removing heal would leave the pull and the merge
  check in place.
- **D1 (data file first) re-examined and kept.** The pointers readers follow still go after the push,
  so conflicts are still resolved in git like code. Git first would leave a pushed version
  unreadable for good after a crash between the push and the upload.
- **Every stop and every report names a way out** (D14).

**Review of `058f29b`, 2026-10-31**, by another agent, one pass against the scenario table, evaluated
with the owner one point at a time. The owner set two principles for it, now D14's seventh: a user
working the clone directly with git is off the supported path, so datom adds no guidance for it but
must never leave the project stuck; and less code is better.

| Point | Outcome |
|---|---|
| 1. The merge check would commit, and the next push share, a merge the user started (`git merge --no-commit feature` leaves nothing conflicted) | **Taken, reshaped.** The review's test (the merged commit equals the upstream tip) calls datom's own merge foreign once anything fetches during it (probed). The merge check decides by what is merged instead: a merge of the remote branch (the upstream tip is the merged commit or descends from it) is finished as before; any other stops, changing nothing, until `datom_pull(conn, finish_merge = TRUE)` or `git merge --abort` (R3.9; tasks 4a, 5). A user's own `git pull` counts as a merge of the remote branch. Set aside on the way: finishing every merge with an undo line, and a marker line in `.git/MERGE_MSG` (text a user could copy) |
| 2. The scan keeps the fetch and storage read that validate dropped | **Taken, with a rename**: the status is `unpushed`, set from the clone alone; a table pushed but not yet published shows `unchanged`, and `datom_sync()` publishes it (D4, R4.2-R4.5, R7.6; task 6) |
| 3. "D1-D13" | Fixed in `design.md` and below |
| 4. (added in the evaluation) A rebase, cherry-pick or revert in progress | **Dropped** under the new principle: traced on paper, the worst outcome is a write to run again, nothing stuck |
| 5. (added in the evaluation) The manifest rebuild ran before the format check, and a merge the merge check finished was never checked | **Taken**: the rebuild runs the format check first; a refusal commits nothing and leaves the merge in progress. At the owner's request every refusal of that check names its evidence (the document, the fields or format number, the installed datom version), so a wrong inference can be reported as a bug (R3.8; task 5) |

**Review of `bfad26c`, 2026-10-31**, by the same reviewer, one pass against the scenario table:
everything in the round above agreed, and one nit taken (task 4a: both stop messages written once in
their final text, tested there by condition class, the full text pinned in task 5). Evaluated with
the owner.

**Task 2's checkpoint review, 2026-10-31**, by another agent, of `8185b7c`: approved. One optional
item (S1) taken into task 3 with the owner: a new data file on S3 is hashed twice, so the resolvers
hash once and pass the hash to the upload.

**Task 3's checkpoint, 2026-10-31**: approved by the owner, of `3ddaa80`, with no review by another
agent. Next is task 4a, in a new session; it opens with the design spot-check flagged at planning
(covering 4a and 4b) before any code.

**Design spot-check before task 4a, 2026-10-31** (covering 4a and 4b), on a more capable model, of
`b1c84af`: read design sections 1, 2, 4-6 against the code, with throwaway probes. Its list went to
the owner, who had it reviewed by another agent; the review confirmed all three findings and added
changes. Evaluated with the owner one point at a time; the owner also set a principle that reshaped
the rest (requirements D14 principle 8):

| Point | Outcome |
|---|---|
| Owner's direction | **Heal acts only when certain**, otherwise the command stops with a way out. Then, asked whether heal should need the developer's consent: **a write heals only the artifact it is writing**; another artifact's unfinished work stops it, naming `datom_validate(fix = TRUE)` (the consent; it heals everything). A stop, not a prompt. D3, D9, R3, R3.5, S3, S4 amended |
| 1. git2r's merge silently does nothing when the user's own files are in the way (a modified or staged file the incoming commits change, an untracked file where they add one, with or without commits of the clone's own): the pull reports success while behind, and heal's publish would then put old versions back in storage | **Taken, with the review's changes.** The pull confirms it caught up, by commit (HEAD contains the fetched tip), never by `merge()`'s return fields; one helper "does commit A contain commit B" for this, the "is it behind" test and the merge check. Stops with `git stash -u`, `datom_pull(conn)`, `git stash pop`, resolve what pop reports, re-run (traced through `datom_pull()`, `research/dirty_pull_probe.R`); points to `git status` rather than naming the files. A fast-forward counts as a merge for the format check. In `.datom_git_pull()`, so every pull gets it (R3.7) |
| (review) A stored version the clone has never seen | **Taken, as a stop** (R3.10): before publishing a differing row, the clone's history must contain the stored version (containment, not "older", so a revert after a storage failure still publishes). The review proposed skipping the artifact; the owner chose stopping, because every manifest upload sends the whole file and would carry the skipped artifact's stale row anyway. DD4 amended, not just reworded: this is close to the check DD4 set aside, but tests containment, stops, and serves certainty |
| (review) Simplifications | Step d's publish list = rows that differ; the pushed-artifact union is dropped there (a pushed but unpublished version's row always differs, since the manifest goes last). `.datom_pushed_artifacts()` stays for R3.6 and the scan |
| 2. A write's push can pull in a teammate's commit, and its manifest upload then names the teammate's version before their files are in storage | **Taken (a)** (R3.10): only when that pull moved HEAD, re-read the stored manifest and upload only if every other row agrees; otherwise skip the upload, say so, name the fix |
| 3. The writer floor is read once, when the connection is made | **Taken**: `.datom_check_writer_floor()` reads the clone's `project.yaml` on every call; the `min_writer_version` field leaves the connection object (its only reader); a broken `project.yaml` stops the write. Checked: nothing else reads the field (R datom or datom-py), no exported help names it |
| 4. Wording | "differs" not "behind" for a stored row; a pull conflict "stops, leaving the merge in progress", not "aborts"; the "data file may already be in storage" line only on the pull inside a push. Also: the metadata-only route keeps its own pull (heal runs before it, not "replacing" it); routes heal once but fetch more than once |

Checked during the spot-check, no change: no test reaches the floor field except by setting it; the
own-branch case is the only one the containment check catches that heal's push does not already
stop (a branch behind its remote of the same name has its push rejected, probed). (Superseded
2026-11-03, below: the branch case moved to the publish-branch rule, and the containment test is
built on a version written straight into the fixture's storage.)

**Review of `4045fbd`, 2026-11-03**, by another agent, after the owner settled a publish-branch
rule (only the branch recorded at init writes to storage; its own issue, [#156](https://github.com/amashadihossein/datom/issues/156),
same release). Evaluated with the owner; all points taken:

| Point | Outcome |
|---|---|
| 1. The "version never seen" stop runs in the repair too, so a stored version the clone lacks (storage edited by hand, commits removed by a force-push) locks every write and the repair, with no way out | **Taken**: the stop binds writes; the repair publishes the clone's version and names the stored version it replaced (R3.10). Added in the evaluation: an artifact the stored manifest names but the clone lacks loses its row, and the repair says so |
| 2. Stale "the next datom write publishes it" (D10, R3.6, R7.2, task 8's test) and "`datom_repo_commit()` resets" (design sections 2 and 4) | **Taken** |
| 3. What the publish-branch rule simplifies | **Taken**: R3.10's branch case goes; its message becomes "re-run; if it persists, `datom_validate(fix = TRUE)`"; task 4b's containment test is built on a version written into the fixture's storage; the pull stops on a clone with no upstream branch, naming `git branch --set-upstream-to` (R3.7) |
| 4. DD4 said a revert "is not misread" | **Taken**: true of your own revert after a storage failure; a teammate's revert seconds before your write is the race DD4 accepts |

Settled the same day, for the publish-branch issue rather than this spec: repos created before that
rule are not migrated and are not told to hand-edit `project.yaml` (owner: experimental phase; hand
edits of that file may go altogether); `datom_repo_attach_governance()` writes storage, so it is
covered too.

**Review of `d616e98`, 2026-11-04**, by another agent, evaluated with the owner; both points taken,
the first reshaped:

| Point | Outcome |
|---|---|
| 1. R3.7's new "no upstream" stop sat in every pull, so `datom_pull()` and the push commands would stop on every new code branch, where `git branch --set-upstream-to` fails until the branch is pushed (checked) | **The stop is dropped altogether** (owner: "if it never happens, why add code bulk"). The review proposed keeping it only before storage writes; checking showed it is not needed there either: with no upstream heal pushes before publishing, and git rejects that push when the clone is behind. Added: a rejected push says the clone is behind and to run `datom_pull(conn)`, instead of "check your credentials" |
| 2. A stored manifest row for an artifact the clone lacks was never counted as differing, so a write's whole-manifest upload dropped it silently | **Taken**, in the write's stop and the manifest upload's agreement check. Added in the evaluation: not only hand edits (S8) produce it; a teammate's new artifact pushed and published in the seconds between this clone's pull and heal's read of the stored manifest does too (a re-run then pulls it) |
| (for #156) Repos created before the rule become read-only; name a way out | Taken for #156's comment: install the earlier release to keep writing an old project, or start a new project with this release (history not carried) |

The same day the owner and this session worked through how branches should relate to storage, which
reshaped #156 from "refuse on other branches" to **lanes**: the publish branch is the public lane
(tracked in git, the shared store); any other branch is a private lane whose record lives only in
its own store, read from the public lane for what it has not built; the merge carries code only;
data reaches the public lane by rebuilding. Draft for vetting:
`.kiro/specs/publish-branch/lanes-principles-draft.md` on branch `spec/publish-branch` (commit
`b0b7068`). For this spec it means only that heal, the merge check and the git order are the
public lane's; nothing in tasks 4a-11 changes.

**Spec review is closed as of this round** (owner, 2026-10-31). From here:
- Open items stay with the tasks that already own them (design section 10).
- Each task gets one review at its checkpoint, against the scenario table at the top of this file.
  Every finding names its scenario, the findings come in one list, and an S7 or S8 finding defaults
  to "stop with a message" (or a report from `datom_validate()`) or to "document".
- The model escalations flagged at planning still run as listed at the top of this file (design
  spot-check before 4a, purity audit after 8, test coverage review before 10); task 2's spot-check
  is done.

Starting cold: `git checkout spec/interrupted-commands && git pull`, then read `requirements.md`
(terms, decisions D1-D14) and `design.md` (sections 1-4 at least, and the section the task names).
The probe scripts in `research/` reproduce today's failures; rerunning them after the relevant task
is part of its acceptance. Since task 4b every write starts with three calls in one place
(`.datom_heal()`, `.datom_pull_before_write()`, `.datom_heal_publish()`; design section 4, "Who
calls heal"), and unit tests on mock connections stub all three (`test-read-write.R` shows how);
`test-heal.R` and `test-heal-publish.R` show the real-project fixtures. Since task 5 a merge that
conflicts only in `.datom/manifest.json` is finished by the pull or the merge check
(`.datom_resolve_manifest_conflict()`; `test-manifest-conflict.R`, whose header says how a test
makes two clones write without a pull in between). The newest guard-probe harness to copy is
`research/task5_guard_probes.R`.

**Starting task 6 cold** (written 2026-11-06; task 6 done 2026-11-07): read this section's first
paragraph and the review just below it, then task 6 in full (its first bullet is an open point to
settle with the owner, one point, before any code), design section 7 and section 10 item 7, and
requirements R4, R3.4 and R3.7. Rerun `research/sync_batch_probe.R` to see the open point's three
cases on the current code. Baseline: 5859 expectations, 0 failed, 0 skipped, at `6d622e9`.

**After task 6** (2026-11-07): baseline 6006 expectations, 0 failed, 0 skipped (5967 at task 6's
commit, then 23 and 16 added by its checkpoint review's two fixes). Sync tests on a
real project live in `test-sync-heal.R`, whose `local_break_sync_at(table, step)` breaks one
table's write inside a sync; `local_heal_counter()` and `local_stored_manifest_reads()` are in
`helper-interrupt.R`. `local_teammate_after_commit()` moved there too, after the checkpoint review. Unit tests of
`datom_sync()` on a plain folder stub its calls into the clone
with `local_sync_on_folder()` (`test-sync.R`), and a scan test that needs a manifest commits it
(`commit_clone_manifest()`), since the scan reads the last commit.

**Starting task 7 cold** (written 2026-11-07): task 6 is done, with its checkpoint review's fixes in
`aa4a680` and `1718023`. The reviewer's check of `1718023` was still pending when this was
written: any finding from it comes before task 7, and task 6 closes on the owner's word. Read this
section's first paragraph and the task 6 reviews just below it, then task 7 in full, design section
6 (the repair) and section 4's route table (the repair heals with `all = TRUE`), and requirements
R5, R3.10 (the repair overrides the "version never seen" stop and says what it replaced) and R7.8.
Task 7 settles one name itself: the shared helper for "which version the stored or clone files
describe" (task 5's `.datom_clone_files_version()` gains the check that every field is one this
build can place, and is renamed if it no longer reads only the clone). Two tests in
`test-sync-heal.R` follow `datom_validate(fix = TRUE)` as the way out of a held-back manifest;
they must still pass once the repair changes. The guard-probe harness to copy is
`research/task6_guard_probes.R` (name probes on the command line to run only those). Baseline:
6006 expectations, 0 failed, 0 skipped, at `1718023`.

**After task 7** (2026-11-07): baseline 6134 expectations, 0 failed, 0 skipped (6127 at task 7's
commit, then 7 added by its checkpoint review's fixes). The repair's tests
on a real project live in `test-repair.R`; `rp_mirror()` there answers `datom_write(conn)`'s prompt
by mocking the `interactive` and `readline` bindings `R/sync.R` holds for that purpose. Mock-folder
tests of the repair stub heal, the pull and the push with `local_repair_on_folder()` (`test-sync.R`).
The newest guard-probe harness is `research/task7_guard_probes.R`.

**After task 8** (2026-11-07): baseline 6244 expectations, 0 failed, 0 skipped, at the commit
fixing the check of `6921561`'s nit (6214 at task 8's commit `3f48a48`, 6238 at `6921561` after its
checkpoint review's fixes, then the nit's test). Task 8's tests on
real projects live in `test-repo-unfinished.R`; its harness is `research/task8_guard_probes.R`.

**After the purity audit and task 9** (2026-11-08): baseline **6325 expectations, 0 failed, 0
skipped, at `3939c6c`**. The audit changed shared code later tasks rely on: every publish goes
through `.datom_publish_artifacts()`, which pushes first; one stop for another artifact's unfinished
work, `.datom_stop_unfinished_work()` (class `datom_unfinished_work`); every stop before publishing
says "Nothing was published."; the git and config commands use `.datom_check_before_commit()` and
`.datom_push_naming_unpublished()`; `.datom_commit_and_mirror()` is `.datom_commit_and_publish()`.
Task 9's tests live in `test-init-interrupted.R`. Newest harnesses: `research/audit_guard_probes.R`
and `research/task9_guard_probes.R` (`research/README.md` lists every harness). `man/` holds help
for internal functions too: run `devtools::document()` before committing any roxygen change.

**Starting task 10 cold** (written 2026-11-08, after task 9 closed at `3939c6c`; the review below
was done on 2026-11-09 and its gaps filled, recorded in "Where things stand"):
- **Done: first, the escalation flagged at planning: a test coverage review on a more capable model.**
  If the session is not on one, say so and stop until the owner answers (switch, or waive). The
  review has two parts, and its findings go to the owner as one list, each naming its scenario
  from the yardstick at the top of this file, before any documentation is written:
  1. **Every guard watched going red.** Each task's commit message records its probes (task 2 on;
     the harnesses are listed in `research/README.md`). Check that each guard a task added has a
     recorded probe that reddened its own test, with a control that reddened nothing, and name any
     guard with none. Known gaps to confirm or close: task 4b's `gate_ignores_ahead` no longer
     applies as written (retargeted in `audit_guard_probes.R`); the comment-only and rename points
     of the audit (5, 6) had nothing to probe.
  2. **The break table against the tests that exist.** The break table is below ("Break table",
     R7.1): for each command and each step it lists, find the test that breaks there and follows
     the re-run (or, for `datom_init_repo()` after its push, the repair). Name each row with no test.
- Then task 10 in full (its bullets below, with the additions from the audit and task 9), and
  requirements R8 (the residual-failure table) and R9 (documentation), and design section 12.
- **Open points to raise with the owner before writing, one at a time** (checked 2026-11-08;
  re-check before raising):
  1. R9.1's conventions text for `.github/copilot-instructions.md` was written before the audit.
     It says "then metadata and manifest to storage" but not the audit's rule that every document
     readers follow is on GitHub first, nor the one "Nothing was published." line, nor that a
     stop's way out is spelled to work as written. Lean: add the first, as one clause in the order
     bullet; leave the other two to the spec, as message details rather than conventions.
  2. R9.5 asks for a lot of user-facing help across about ten pages. Lean: one short paragraph
     per page, saying what the user sees and what to do, with the mechanism left to the spec, per
     the communication rules; confirm the length the owner wants before writing ten of them.
- **FYI:** the follow-up issue on the storage-completeness checks `datom_validate()` lacks
  (design section 12) was filed in task 11 as [#158](https://github.com/amashadihossein/datom/issues/158). #157 (decimals in custom metadata) is filed.

**Starting task 9 cold** (written 2026-11-07; task 8 closed the same day; task 9 done 2026-11-08, reshaped
by the owner, so the open points below are the record): first confirm in "Where
things stand" that the purity audit flagged after task 8 is done or waived by the owner; if not,
stop and ask. Then read
task 9 in full, requirements R6, D5 and R3.7 (its exception for init's first push), and design
section 8. What the code holds today, checked 2026-11-07 with `research/init_rerun_probe.R` (folder
remote, local store, `create_repo = TRUE`):
- **A break at the commit or the push is already rolled back, and the same call re-run succeeds**
  (R6.3 holds today). `datom_init_repo()` (`R/conn.R`) tracks `.git_pushed`; until the push
  succeeds, its `on.exit()` deletes what it created, the bare remote included
  (`.datom_undo_folder_remote()`).
- **A break at the manifest upload is the case task 9 changes.** The clone, `project.yaml` and the
  pushed bare remote stay; storage has no manifest. Re-running the same call refuses, and not at
  the "already exists" check: `.datom_init_folder_remote()` (`R/utils-git.R`), which runs earlier,
  refuses "already has content" for the pushed bare remote, and a GitHub `create_repo = TRUE` would
  try to create the repo again. That is why design section 8 puts `.datom_init_finish()` before the
  remote is resolved. The refusal at the path check ("A datom repository already exists") is what
  a call with an explicit `data_repo_url` meets. The way out the upload failure names today,
  `datom_validate(conn, fix = TRUE)`, works: the probe shows it uploading the manifest.
- **There is no fetch on its own.** The fetch sits inside `.datom_git_pull()` and `.datom_git_push()`
  (`R/utils-git.R`); `.datom_git_ahead()` (`R/repo.R`) reads local refs only. "The remote has the
  initial commit" therefore needs the pull or a new small fetch, and the pull also merges when the
  clone is behind (see the open points).
- Existing refusal tests to keep green unchanged (R6.2): in `test-conn.R`, "datom_init_repo aborts
  if .datom already exists" and the "already has content" case of the folder-remote tests; the init
  fixtures there are `setup_init_env()` and `setup_local_init_env()`. Real-project fixtures for
  break-and-re-run are in `helper-interrupt.R` (`local_break_at()` has `"commit"`, `"push"` and
  `"manifest"`, which match init's three steps).
- **Open points to raise with the owner before any code, one at a time**, each with the lean noted
  here (checked against the code on 2026-11-07; re-check before raising):
  1. Which fields must match for a re-run to finish. R6.1 says project name and data storage. The
     folder's `project.yaml` also records `mode` and `set` (a product repo); a re-run with a
     different `mode`, `set` or `max_file_size_gb` would otherwise finish and leave the first call's
     values. Lean: `mode` and `set` must match too (they change which writes are allowed); the rest
     do not.
  2. A clone behind its remote at the re-run (a teammate cloned and pushed in between). Design
     section 8 asks for "ahead is 0", which a behind clone passes, and uploading its manifest would
     then name only the first commit's state. R3.7 says nothing writes to storage before pulling.
     Lean: refuse unless the clone is exactly level with the remote after a fetch; a teammate's
     write that published would already have put a manifest in storage, which refuses anyway.
  3. The format check on the folder's `project.yaml` before comparing it
     (`.datom_check_project_schema(operation = "write")`, as `datom_repo_set_data_store()` does).
     Lean: yes; a file from a newer datom refuses with its evidence.
  4. The upload failure's message. It names `datom_validate(conn, fix = TRUE)`; after task 9 the
     same `datom_init_repo()` call finishes too. Lean: name the re-run first, keep the repair as the
     second way out.
- **FYI, not task 9's to build:** the publish-branch rule (#156, spec on branch
  `spec/publish-branch`) will add a `publish_branch` field to `project.yaml` and make an init
  re-run that uploads the manifest a command that runs only on that branch. Write the comparison as
  a short list of fields, so #156 can add one.
- **Guard probes**: copy `research/task8_guard_probes.R` (replace the file list and the probes);
  each of R6.1's conditions needs its own probe and its own test (task 9's bullet).
Baseline: 6244 expectations, 0 failed, 0 skipped, at the commit after `075500e` that fixes the nit.

**Starting task 8 cold** (written 2026-11-07, after task 7 closed at `ba57f3a`; done, kept as the
record): read this
section's first paragraph, then task 8 in full, requirements D9, D10, R3.5, R3.6 and R7.2, and
design section 4 ("0. The merge check", and the paragraph after its route table on
`datom_repo_commit()` and the four push commands) and section 10's note that R3.6's message is
task 8's. What the code holds today, checked 2026-11-07:
- `datom_repo_commit()` (`R/repo.R`) validates its arguments, checks the remote (push only) and the
  branch, then stages `paths %||% "."` through `.datom_git_commit()` and pushes with
  `.datom_git_push()`, which pulls first and so meets the merge check. Nothing runs the merge check
  before staging, and nothing looks at datom's own files: both are task 8's. With `push = FALSE`
  no pull runs at all.
- `datom_repo_push()`, `datom_repo_attach_governance()` and `datom_repo_set_data_store()` push
  through `.datom_git_push()` and say nothing about datom versions in what they push.
- Helpers to reuse, all in `R/heal.R`: `.datom_check_merge(path)`; `.datom_unfinished_files(conn)`
  (datom's own files differing from HEAD) and `.datom_unfinished_owners(conn, files)` (whose they
  are, the manifest's changed rows included); `.datom_pushed_artifacts(path)` (the artifacts whose
  datom files the unpushed commits change, from local refs; names nothing with no upstream branch),
  which R3.6's message is built on, so it needs no storage read.
- **An existing test pins the behaviour D9 reverses**: "datom_repo_commit(paths = NULL) sweeps in
  datom's own uncommitted files, and the repair reaches what it can (AC17)" in
  `test-foreign-content.R`. Task 8 rewrites it to the stop and names it in the commit message.
- **One open point to settle with the owner before any code**, one point: what counts as "an
  explicit path naming one" of datom's files (R3.5). Checked 2026-11-07: `.datom_git_commit()`
  refuses a path that does not exist before `git2r::add()`, so a glob never reaches git; the
  candidates are the file itself, or the file or a folder above it (`paths = "dm"`, `"."`). Raise
  with it one fact found while checking: a commit stages `paths` on top of whatever is already
  staged, so a datom file the user staged earlier is committed by `datom_repo_commit(paths =
  "build.R")` too. Whether the stop also looks at already-staged datom files is part of the point.
- `research/task7_guard_probes.R` is the harness to copy; real-project fixtures are in
  `helper-interrupt.R` (`local_interrupt_project()`, `local_break_at("push")`, `snapshot_*()`),
  and `test-heal-publish.R`'s "a write with nothing to save leaves the user's own unpushed commit
  alone" shows `datom_repo_commit(paths =, push = FALSE)` on a real project.
- **After task 8 comes the purity audit on a more capable model** (tasks 2-8, flagged at
  planning): say so at task 8's checkpoint and stop.
Baseline: 6134 expectations, 0 failed, 0 skipped, at `ba57f3a`.

**Shared test helpers** (created in task 2, extended later): `tests/testthat/helper-interrupt.R`
with a project fixture (folder git remote and local store, as in the probes), a second-clone fixture,
and `local_break_at(step)`, which raises at one named step through a mocked binding. Names and
mechanics follow the probes in `research/`.

**Break table** (R7.1). Each test breaks the command at one step, re-runs the same command, and checks
what a reader sees (the new version reads; the stored manifest names it).

| Command | Task | Steps broken |
|---|---|---|
| `datom_write()`, data-frame route | 2 (steps 1-5), 4b (step 6) | data file upload; clone files; commit; push; metadata upload (the whole step, and between the history upload and `metadata.json`); manifest upload |
| `datom_write_set()` | 3 (steps 1-5), 4b (step 6) | the same six |
| `datom_write(conn, name =)`, the metadata-only route | 4b | its push; its metadata upload |
| `datom_sync()` | 6 | the second of three tables, at its file import, data file upload, commit, push and manifest upload; then the stop's way out (the same call, same preview) after a commit, push or manifest break, or a re-scan and re-sync after an import or upload break, and every table reads |
| `datom_validate(fix = TRUE)` and the mirror-everything route | 7 | the push; between the first and second artifact's mirror; the final manifest upload |
| `datom_repo_commit()` | 8 | its push (the re-run commits nothing and pushes) |
| `datom_init_repo()` | 9 | its commit and its push (rolled back, so the re-run starts afresh); the storage connection and the manifest upload (the stop names the repair, which finishes; R6 as rewritten 2026-11-08) |

`datom_sync_manifest()` changes nothing, so it has nothing to break.

Why these steps for `datom_sync()`: task 2 already breaks every write step for one table, so sync's
tests cover what sync adds, a break partway through a batch: its own import step, and one break on
each side of the commit. Breaking the clone-file write ends the same way as breaking the data file
upload (nothing committed, so heal resets it and the re-scan shows the table changed); breaking the
metadata upload ends the same way as breaking the push (committed, so heal pushes and publishes it).

---

- [x] **1. Storage: upload only if absent, and the stored file's hash** (R1.2, R1.3; design section 3)
  - **Done 2026-10-30.** Suite 5142 -> 5214 expectations, none removed. The real-S3 probe passed 11
    of 11 checks on all three paws pairs (design section 10). Taken beyond the list, and flagged at the
    task's checkpoint: help text for `datom_storage_list()`, `datom_storage_copy()` and
    `datom_storage_verify()` now, not in task 10; a stored S3 checksum must also decode to exactly
    32 bytes; the internal `.datom_s3_whole_file_sha256()` holds the trust rule; the part-count
    suffix test uses a stand-in lenient decoder, because jsonlite's decoder refuses a suffixed value
    by itself and would otherwise hide the rule's removal.
  - `R/utils-storage.R`: `.datom_storage_upload_absent()` and `.datom_storage_object_sha256()`,
    dispatching to the backends.
  - `R/utils-s3.R`: `.datom_s3_upload_absent()` (`head_object` first, then `put_object` with
    `IfNoneMatch = "*"` and `ChecksumSHA256`; `http_412` returns `"exists"`; a 409 is an ordinary
    upload failure, no retry) and `.datom_s3_object_sha256()` (trust `ChecksumSHA256` only when it
    covers the whole file: type `FULL_OBJECT`, or no type and no `-N` suffix; otherwise download and
    hash). A service that rejects the new headers gets no fallback; its documentation is task 10's.
  - `R/utils-local.R`: `.datom_local_upload_absent()` (copy to a recognisable temporary name, hard-link
    into place, delete the temporary name; a refused link with the target present is `"exists"`;
    no hard links means check, then move) and `.datom_local_object_sha256()`; `.datom_is_temp_key()`.
  - `R/storage.R`: `datom_storage_copy()` and `datom_storage_verify()` skip temporary files;
    `datom_storage_list()` unchanged.
  - `DESCRIPTION`: `paws.storage (>= 0.8.0)`.
  - New `research/s3_conditional_probe.R`, run with the owner's credentials (from the environment or
    keyring, as `dev/e2e-solo-s3.R` does; never in the script): under a throwaway prefix, upload a
    file, upload again "only if absent", read the checksum back with `ChecksumMode = "ENABLED"`, then
    delete the prefix. Run on three version pairs: the ones installed here (`paws.storage` 0.9.0,
    `paws.common` 0.8.8); the declared minimum (`paws.storage` 0.8.0 with `paws.common` 0.8.0, which
    it requires), installed from CRAN's archive into a throwaway library for that run only; and
    CRAN's current ones (`paws.storage` 0.11.0, `paws.common` 0.9.0). Record the results in design
    section 10, item 2.
  - Nothing calls the new upload yet, so no behaviour changes for users in this task.
  - Tests: an existing file with different bytes survives a second upload, on both backends (P2);
    a failure mid-copy leaves nothing at the final key; the no-hard-link fallback; the S3 arguments,
    the 412 path and the 409 path on a mocked client; the checksum condition (`FULL_OBJECT`,
    `COMPOSITE`, `-N`, absent); copy and verify skip a temporary file.
  - Guards to probe: the existence check, the link refusal, the whole-file checksum condition, the
    temporary-name filter.
  - Acceptance: P2 holds on both backends; the S3 calls carry the conditional and checksum arguments;
    `datom_storage_copy()` and `datom_storage_verify()` ignore a temporary file that
    `datom_storage_list()` still shows; the real-S3 probe shows 412 for the second upload and a
    whole-file `ChecksumSHA256` matching the file, on all three paws version pairs.

- [x] **2. Tables: the data file first** (R1.1, R1.3, R1.4, R2.1; design section 3)
  - **Done 2026-10-31.** Suite 5214 -> 5276 expectations, none removed. All four guards probed red
    against their own tests, with a control that reddened nothing; the counting tests re-pointed and
    watched (commit message). `research/write_steps_probe.R` updated: every break fired, and after
    each of steps 1-5 the re-run reads v2. Differences from the list below: the second-clone fixture
    is left for task 4a, its first user, rather than added unused; the step-5 break is tested at two
    points inside the step, the stored history upload (the one that tells the new order from the
    old) and the stored `metadata.json` upload; the resolver's unit tests gained a fifth, for the
    "already stored" case; the resolver returns an `outcome` beside `parquet_sha`.
  - **Escalation first: design spot-check on a more capable model.**
  - `R/read_write.R`: `.datom_resolve_parquet_sha()` decides and uploads through
    `.datom_storage_upload_absent()`, with no separate existence check first (design section 3):
    `"exists"` records `.datom_storage_object_sha256()`, `"uploaded"` the fresh bytes' hash;
    `datom_write()` calls it before `.datom_write_metadata_local()`. `datom_write()` stops passing
    `upload` to `.datom_commit_and_mirror()`; the argument stays for `datom_write_set()` until
    task 3, and its description gains "only the set write passes it".
  - `.datom_push_metadata_s3()` uploads the snapshot, then the history, then `metadata.json` last,
    because change detection reads it as the mark that step 5 is done (design section 1).
  - Correct the old-order docstrings of `.datom_resolve_parquet_sha()` and
    `.datom_push_metadata_s3()` (R9.4). The resolver's says that a full write whose content matches a
    stored file with no recorded hash (written before datom-cv1) now keeps that file and records its
    hash, where it used to overwrite it (R1.2). `.datom_commit_and_mirror()`'s is task 3's.
  - Create `tests/testthat/helper-interrupt.R`. Rewrite any existing test that asserts the old order
    (design section 10, item 4).
  - Re-point every test that stubs or counts `.datom_storage_upload()` for a table's data file to
    `.datom_storage_upload_absent()`, through one shared stub in `helper-mock.R` that can record
    the keys it was given (about 18 do-nothing stubs on a fake S3 connection in `test-read-write.R`,
    plus its full-write upload test). Name in the commit message: the two counting tests, the
    refused-table test in `test-hashable.R` and the metadata-only write in `test-read-write.R`,
    watched going red once with their counter left on the old function, to show the old counter
    can no longer catch an upload; and the four `.datom_resolve_parquet_sha()` unit tests,
    rewritten for its new arguments. Rewrites only, no test removed.
  - In `test-identity-contract.R`, the "no upload" checks in S3, S4, S6 and "revert-to-older content
    reuses the history parquet_sha" count calls to `.datom_storage_upload_absent()` (expect none)
    instead of relying on a backdated modification time, which the new upload never changes. The
    revert test is the only guard of the history branch of the hash decision (R1.3, first case),
    which spares a revert from hashing the stored file (a download for a file stored before this
    spec, which has no S3 checksum). Update the "Prove 'no upload' with a backdated mtime" entry in
    `dev/engineering-notes.md`: from this task a data file's upload never overwrites, so a
    modification time cannot show whether one was attempted.
  - The rewritten docstring of `.datom_resolve_parquet_sha()` also says: `size_bytes` describes the
    freshly written parquet; when the recorded hash is a stored file's (an existing file, a
    metadata-only carry, or a revert), the stored file can differ in size if a different arrow
    version wrote it; nothing reads `size_bytes` beyond the manifest's counters. No code change.
  - **Update `research/write_steps_probe.R` before using it as evidence.** Break step 1 by replacing
    `.datom_storage_upload_absent()`; add a step-2 break by replacing `.datom_update_manifest_entry()`
    (metadata and history written, no manifest row); keep the commit, push, metadata and manifest
    breaks. A row counts only if its `raised` column is `TRUE`. Update `research/README.md`.
  - Tests: the break table's steps 1-5 for `datom_write()` (P1), step 5 broken both as a whole and
    between the history upload and `metadata.json`; the recorded hash equals the stored file's hash,
    including when the file was stored by an earlier broken run (P3). For that case the stored file
    holds the same data in different bytes (other parquet options), so the recorded hash can only
    match if it came from storage, and a read of the version then succeeds. The break tests assert
    what a reader sees (P1) and the recorded hash (P3), not how many commits a re-run makes or which
    commit the stored history names: until 4b, a re-run after a push break makes a second commit
    (`metadata.json`'s `created_at` moves) and the stored history names it, as today's code does.
  - Guards to probe: the upload placed before the first clone write; the `"exists"` branch of the
    hash decision (record the stored file's hash, not the fresh bytes'); the history branch of the
    hash decision (against the revert test, now counting upload calls); `metadata.json` uploaded
    last within step 5.
  - Acceptance: P1 for steps 1-5 and P3 for `datom_write()`; the updated
    `research/write_steps_probe.R` shows, for steps 1-5, the break firing and the re-run reading the
    new version.

- [x] **3. Sets: the payload first** (R1.1, R1.5; design section 3)
  - **Done 2026-10-31.** Suite 5276 -> 5356 expectations, none removed. Every guard probed red
    against its own tests, with a control that reddened nothing (`research/task3_guard_probes.R`;
    results in the commit message). `research/set_steps_probe.R` updated: every break fired, and
    after each of steps 1-5 the re-run reads v2. Differences from the list below: both resolvers
    share one new helper for their last case, `.datom_store_data_file()` (hash once, upload only if
    absent, pick the hash), so "each resolver passes its hash" is one guard, probed against both
    resolvers' tests; the payload's spelling lives in one new function,
    `.datom_write_set_payload()`, which the R1.5 re-run test replaces to spell it differently; the
    restore keeps its existence check before the hash check (so a stored payload is never compared
    with the clone's) and reports nothing when the upload finds the payload stored after all, with
    a test and a probe; `local_interrupt_project()` passes extra arguments to `datom_init_repo()`
    for a product repo.
  - `R/set.R`: `datom_write_set()` builds the payload in a temp file, uploads or adopts it through
    `.datom_resolve_document_sha()`, then writes `set.json`; when the recorded hash is a stored
    payload's and the fresh bytes differ, `set.json` takes the stored bytes.
  - `.datom_restore_set_payload()` uploads through `.datom_storage_upload_absent()`.
  - `.datom_commit_and_mirror()` loses its `upload` argument, now that no caller passes it.
  - Correct the old-order docstrings of `.datom_commit_and_mirror()`, `.datom_resolve_document_sha()`
    and `.datom_restore_set_payload()` (R9.4).
  - Re-point the set-repair test "a stored payload that is present is never re-uploaded" in
    `test-validate-sets.R` to `.datom_storage_upload_absent()`; left on the old function it would
    stay green whatever the repair uploads. Likewise "re-writing content already in history does not
    touch the stored payload (AC29b)" in `test-write-set.R`: count calls to
    `.datom_storage_upload_absent()` instead of relying on a backdated modification time, which the
    new upload never changes.
  - **Update `research/set_steps_probe.R`** the same way as task 2's probe; its step-2 break leaves
    `set.json`, metadata and history written.
  - **A new data file is hashed once** (task 2's checkpoint review, owner, 2026-10-31). Since task 2,
    a new table file on S3 is hashed twice: `.datom_s3_upload_absent()` hashes the bytes for its
    `ChecksumSHA256` header, and `.datom_resolve_parquet_sha()` hashes the file again on
    `"uploaded"` (a local store hashes once; before task 2 a write hashed once). Fix:
    `.datom_storage_upload_absent()` and both backends gain an optional `sha256 = NULL` (lowercase
    hex). Both resolvers, `.datom_resolve_parquet_sha()` and `.datom_resolve_document_sha()`, hash
    the fresh bytes once before the upload, pass the hash, and record it on `"uploaded"`. S3 turns
    the passed hash into the header instead of hashing; with `NULL` it hashes as now; the local
    backend ignores it. Accepted cost: when the file is already stored, the fresh bytes are hashed
    without need, which is still one hash per write.
  - Tests: the break table's steps 1-5 for `datom_write_set()` (P1); a re-run with a different
    spelling of the same set leaves `set.json` byte-identical to the stored payload (R1.5). The test
    "nothing reaches storage when the git push fails" in `test-write-set.R` becomes "only the payload
    reaches storage". For the single hash: on a mocked S3 client, a hash passed to
    `.datom_s3_upload_absent()` is the one sent in `ChecksumSHA256` (pass a deliberately wrong one,
    so a recomputed hash would show), and with no hash passed the header equals the one a correct
    passed hash gives; each resolver passes the hash it records (captured through
    `mock_upload_absent()`, extended to record the argument).
  - Guards to probe: the stored-spelling branch; the S3 upload using the passed hash; each resolver
    passing its hash. The harness from task 2, `research/task2_guard_probes.R`, is a template.
  - Acceptance: P1 for steps 1-5 of `datom_write_set()`; R1.5; the updated
    `research/set_steps_probe.R` shows, for steps 1-5, the break firing and the re-run reading the set.

- [x] **4a. The merge check, heal's reset, and the pull** (R2.4, R2.5, R3.1, R3.5's helper, R3.7,
  R3.9, R3.10's stop for other artifacts; DD1; D14 principle 8; design sections 1 and 4)
  - **Done 2026-11-04.** Suite 5356 -> 5549 expectations, none removed; the rewritten tests are named
    in the commit message. Every guard listed below probed red against its own tests, with a control
    that reddened nothing (`research/task4a_guard_probes.R`; results in the commit message), plus two
    not listed: the manifest is reset only when every differing row is the write's own (a new test),
    and the old folder rule (against the `app/metadata.json` test). `research/other_command_probe.R`
    and `research/dirty_pull_probe.R` rerun (`research/README.md`). Names settled:
    `.datom_check_merge()`, `.datom_git_contains()`, `.datom_pull_before_write()`,
    `.datom_unfinished_files()` (heal's gate), `.datom_git_merge_upstream()` (the pull's one merge,
    so a test can count it), and `data_file_stored` / `in_push` on the pull and the push. Design
    section 10 items 1 and 5 settled there. Differences from the list below, each flagged at the
    checkpoint:
    1. **The metadata-only route pushes first when the clone holds commits the remote lacks**, then
       publishes. The removed block's push half did run: it pushed a commit a broken write had left
       unpushed. Without it the route would publish a version GitHub lacks until task 4b's publish
       pushes; 4b replaces it.
    2. **A rejected push on a branch with no upstream** first gives
       `git branch --set-upstream-to=<remote>/<branch>`: traced, `datom_pull()` merges nothing without
       an upstream, so "run `datom_pull(conn)`" alone loops. Until 4b the refused push is the write's
       own, after its data file is stored; no document or manifest is published.
    3. **A clone with no `project.yaml` passes the floor** (no declaration, as with no clone); one that
       exists but does not parse stops the write (`datom_project_config_unreadable`).
    4. The stop on another artifact's uncommitted files names two ways out: re-run that artifact's
       write (which resets and rewrites it) or `datom_validate(fix = TRUE)`.
    5. Heal's reset also puts back a manifest whose uncommitted changes touch no artifact's row, with
       an information line.
    6. Test fixtures that planted a document by an uncommitted edit now commit it, as a pull would:
       heal would otherwise reset it before the write, and the test would check nothing (the
       `column_hashes` tests in `test-forward-compat.R` stayed green that way until
       `fc_edit_clone_json()` was changed to commit).
  - **Checkpoint review fixes, 2026-11-05** ("Where things stand"): a pull blocked by an unfinished
    write names that write instead of the stash recipe; the manifest's rows are compared in the
    current format. Two tests in `test-heal.R`, each probed red with its guard removed (results in
    that commit's message). `research/task4a_guard_probes.R` now takes probe names on the command
    line, to run some only.
  - **Escalation first: design spot-check on a more capable model**, covering 4a and 4b. **Done
    2026-10-31** ("Where things stand"); the bullets below include its outcome.
  - **Two points found while recording the spot-check, settled by the owner on 2026-11-04:**
    1. The metadata-only route, `datom_write(conn, name = "dm")`, never rewrites `dm`'s files; it
       publishes what is committed. An uncommitted edit of `dm`'s files therefore **stops** it,
       naming `datom_validate(fix = TRUE)`, as on any artifact a command does not rewrite (it does
       not reset them). Its `artifact` is none.
    2. `datom_sync()` counts **every table in its preview** as its own, so a preview table pushed but
       not yet published is published by the sync (requirements R4.4, design section 7).
  - New `R/heal.R`:
    - **The merge check** (design section 4, step 0), independent of heal, with its stop branches.
      It first decides whether the merge in progress is a merge of the remote branch (the upstream
      tip as last fetched contains `MERGE_HEAD`: the same commit, or descends from it; local refs
      only), through the shared "does commit A contain commit B" helper in `R/utils-git.R` (named
      here), which the pull also uses for "is the clone behind" and "did it catch up".
      Any other merge stops before changing anything, with the message naming it and giving
      `datom_pull(conn, finish_merge = TRUE)` and `git merge --abort` as the ways out. For a merge of
      the remote branch, while a file other than `.datom/manifest.json` conflicts, it stops before
      changing anything, with the short message that names the conflicted files and fills in
      `git checkout MERGE_HEAD --` for all of each conflicted artifact's datom files. Its finishing
      branch and `finish_merge` are task 5's; until then a merge with only the manifest left stops
      with the same message.
    - **Both stop messages are written once, in their final text, here** (review of `bfad26c`,
      owner, 2026-10-31). Two of their lines name behaviour task 5 builds: the other-merge stop's
      `datom_pull(conn, finish_merge = TRUE)`, and the recipe's last line, "re-run your write: datom
      rebuilds the manifest and finishes the merge". Nothing is released between the two tasks (one
      PR), so 4a's tests match these stops by condition class and by the lines already true at 4a;
      task 5's tests pin the full text. No placeholder `finish_merge` argument in 4a.
    - **`.datom_heal(conn, artifact = NULL, all = FALSE)`** with step a only
      (`.datom_reset_unfinished()`), run only when `git status` shows an uncommitted datom file.
      `artifact` takes several names: heal resets those artifacts' files (and the manifest, only
      when every row differing from HEAD's is one of theirs). Any other artifact's uncommitted datom
      files stop the command before anything changes, naming the artifact and
      `datom_validate(fix = TRUE)` (design section 4; D14 principle 8). `all = TRUE` (the repair,
      wired in task 7) resets every artifact's files. Its docstring says what heal repairs and what
      it leaves (design section 4's table), and that a write never acts on another artifact.
  - **The pull, owned by the commands** (R3.7): `.datom_git_pull()` calls the merge check first,
    fetches (with no upstream it merges nothing, as today: no stop, 2026-11-04), merges only if the clone is behind (HEAD does not contain the fetched tip), **then
    confirms it caught up** (HEAD contains the tip), decided by commit and never by
    `git2r::merge()`'s return fields, and stops otherwise with the `git stash -u` recipe of design
    section 4, step b (pointing to `git status`, not naming files). It says whether HEAD moved (a
    fast-forward counts; git2r returns `sha = NA` for one). On a conflict outside the manifest it
    stops the command, leaving the merge in progress, with the short merge message ending "No
    version is published."; the pull inside a write's push adds "This write's data file may already
    be in storage, unnamed until the write finishes" (an argument or a wrapper, named here). A small
    pull step for the write commands (named here) calls it and, only when HEAD moved, runs
    `.datom_check_write_entry(conn, NULL)`. Heal does not call the pull.
  - **A rejected push names the cause** (design section 4, step b; 2026-11-04): when git refuses a
    push because the remote holds commits the clone lacks, `.datom_git_push()` says the clone is
    behind and to run `datom_pull(conn)` and re-run, instead of "check your credentials".
  - **The writer floor read at write time** (design section 2): `.datom_check_writer_floor()` reads
    `min_writer_version` from the clone's `.datom/project.yaml` on every call; a `project.yaml` that
    cannot be read or parsed stops the write with a clear message; no clone passes (the role check
    refuses). Remove the field from `new_datom_conn()` and `.datom_get_conn_developer()`, with the
    stale-copy comment beside its assignment; update the comments in `R/ref.R`, `R/set.R` and
    `R/utils-validate.R` that mention it, and the internal help (`devtools::document()`). Re-point
    the tests that set the field (about 11 places in `test-conn.R`, `test-forward-compat.R`,
    `test-write-set.R`) to write the setting into the fixture's `project.yaml`, named in the commit
    message.
  - `R/sync.R`: `.datom_clone_artifact_names()` counts a folder only if the manifest (last commit or
    working tree) names it, or its `metadata.json` declares a datom `hash_algo` (design section 4,
    step a). This changes its other two callers too: the repair no longer publishes a user's folder,
    and the forward-compatibility check on the mirror-everything route no longer reads one.
  - Wire each route in the order of design section 1 (the merge check, heal's reset, the route's own
    pull; heal's publish follows in 4b), in exactly one place per route (design section 4): the
    data-frame route in `datom_write()` (with the internal `.healed` argument), the metadata-only
    route inside `.datom_sync_metadata()` (just before its own pull, which stays; no `artifact`,
    point 1 above), and `datom_write_set()`.
  - After D13 the metadata-only route never has anything to commit: an uncommitted change to the
    table's files has stopped the command (point 1). So 4a removes the commit-and-push block from
    `.datom_sync_metadata()` rather than leaving code that never runs. The route then publishes the
    table's committed metadata and history when storage differs, passing no commit id (the stored
    history works it out from git, as the repair does); 4b moves that publish onto
    `.datom_publish_artifacts()`. The mirror-everything route is task 7's and behaves as today until
    then. Check order as in design section 1: every refusal check that needs no storage state heal
    can change runs before the merge check; change detection and the table-or-set check after heal's
    publish. Writes still publish through the existing path; 4b moves them. `R/utils-git.R`:
    `.datom_git_head_file()`.
  - Reset messages as in design section 4: information for an artifact the command is about to
    write; the stop for any other. Correct the ordering comment in `.datom_sync_metadata()` (R9.4).
  - Settle design section 10 item 1 (unstaging chosen paths) and item 5 for the reset messages and
    the new stops (`cli` alert or classed condition), and record the answers in `design.md`.
  - **`research/other_command_probe.R`**: confirm each break fired; it now shows `lb`'s write
    stopping, naming `dm`, with nothing changed.
  - Tests: another artifact's write broken before its commit, then a write of a different artifact,
    including a set write with `include_paths`: the second write stops before changing anything in
    the clone, git or storage, naming the broken artifact and `datom_validate(fix = TRUE)` (R7.2, P8,
    P13; the fix's reset is task 7's test); a re-run of the broken write itself, getting the
    information message and finishing; a metadata-only call (`datom_write(conn, name = "dm")`) after
    a write of `dm` broken before its commit, and a hand edit of `dm/metadata.json` (D13), each
    stopping before changing anything and naming `datom_validate(fix = TRUE)` (point 1),
    publishing nothing new, replacing the hand-edit test in
    `test-version-commit.R` (named in the commit message). That test also checks that this route
    re-derives commit ids storage has lost; rebuild that check on a state the route still acts on,
    such as stored metadata behind the clone's last commit, and say how in the commit message; none
    of the routes healed here publishes an uncommitted file (P4); a failed fetch changing nothing
    (P9); two clones with the second behind, whose write leaves storage at the first clone's newer
    version, and a conflict outside the manifest publishing nothing (P5's write case, R7.6); **the
    same two clones with a modified, a staged and an untracked file of the user's in the way of the
    incoming commits, and again with the second clone also holding commits of its own: a write and
    `datom_pull()` each stop with the `git stash -u` message, changing nothing in the clone, git or
    storage (R3.7, P14)**; following that message's recipe, the write then finishes; a clone whose
    branch has no upstream and that is behind the remote: a write stops at heal's push, before
    storage changes, with the message naming `datom_pull(conn)`; `datom_pull()` and
    `datom_repo_push()` on a new local-only branch change nothing and do not stop, and the push
    sets the branch's upstream (2026-11-04); a
    fast-forward pull bringing in a newer-format document re-runs the format check; the writer
    floor raised in a commit the pull brings in stops the write; a broken `project.yaml` stops the
    write; a
    mistyped argument refused before heal runs; heal called exactly once by each of the data-frame
    route, the metadata-only route and `datom_write_set()`, counted through a mock; **on a clean,
    current, fully published clone, the merge check, heal's reset and the pull write nothing to the
    clone, git or storage, and do not call the merge, recorded through mocks (P12)**; a merge in
    progress with `dm`'s files conflicting stops a write, `datom_pull()` and `datom_repo_push()`
    alike, each with the files listed and the command filled in for all of `dm`'s datom files,
    leaving the clone, git and storage unchanged and `MERGE_HEAD` in place (R3.9); a user's
    `git merge --no-commit` of a local branch (nothing conflicted) and a merge of another remote's
    branch each stop a write and `datom_pull()` with the other-merge message, leaving the clone,
    git and storage unchanged and `MERGE_HEAD` in place; datom's own conflicted merge after a later
    `git fetch` moved the upstream tip, and a user's own conflicted `git pull`, each get the
    merge-of-the-remote-branch message, not the other-merge one (`research/merge_source_probe.R`
    shows the states to build); a pull that
    merges in another table carrying a field this build cannot classify stops the write with the
    upgrade message, before its own work; a user's tracked `app/metadata.json` with uncommitted
    edits, and an untracked one, survive heal untouched (P8), the repair does not publish either,
    and the forward-compatibility check does not refuse because of one; a first write broken after
    its files and before its manifest row is still reset.
  - Guards to probe: the merge check's stop, the other-merge stop, each half of the
    merge-of-the-remote-branch test (the equality, against a merge with no fetch since; the descent,
    against the merge after a later fetch), the reset, the `hash_algo` rule for artifact folders,
    the merge only when behind (against the P12 test), the format check after a merge (against the
    fast-forward case), the pull before any decision, the re-run entry check, the fetch-failure stop,
    a refusal check placed before the merge check, **the caught-up check** (against the dirty-file
    tests), **the rejected-push message** (against the behind-with-no-upstream test), **the stop on another artifact's uncommitted files**, **the floor read from
    `project.yaml`** (against the raised-floor test). The reset's own gate (run only when `git status` shows something) has no
    observable but cost: the reset finds nothing either way, so it is not probed, and its comment
    says so.
  - Acceptance: P4 for the routes healed here (the data-frame route, the metadata-only route and
    `datom_write_set()`; the rest is task 7's), P8, P9, P12 and P13 for what 4a adds, P14's pull
    half, P5 for writes, R3.9's stops (both kinds of merge); D13 on the metadata-only route (it stops on an
    uncommitted edit, point 1); `research/other_command_probe.R` shows `lb`'s write stopping and naming `dm`
    when `dm`'s write broke before its commit, with the break confirmed; `research/dirty_pull_probe.R`
    rerun.

- [x] **4b. Heal: push and publish** (R2.2, R2.3, R3.2-R3.4, R3.10; DD4 as amended; D14 principle 8;
  design section 4)
  - **Done 2026-11-06.** Suite 5568 -> 5715 expectations, none removed; the rewritten tests are
    named in the commit message. Every guard listed below probed red against its own tests, with a
    control that reddened nothing (`research/task4b_guard_probes.R`; results in the commit
    message), plus three not listed: heal's push not pulling, the history read before the local
    metadata write, and the `rewrite` subset check. `research/other_command_probe.R`,
    `write_steps_probe.R` and `set_steps_probe.R` rerun (`research/README.md`). Design section 10
    items 3 and 5 settled there. Names: `.datom_heal_publish()`, `.datom_read_clone_json()` (the
    shared reader), `.datom_stored_manifest()`, `.datom_storage_write_json_at()`. Differences from
    the list below, each flagged at the checkpoint:
    1. **Heal is two calls**, `.datom_heal()` (the merge check and the reset) and
       `.datom_heal_publish()` (step d), with the route's pull between them: the pull is the
       command's, so heal cannot make it, and step d must come after it. One place per route, three
       consecutive lines; the heal-once test counts both halves.
    2. **Heal's push does not pull.** A remote that moved since the route's pull makes git refuse
       it; pulling there could bring in a teammate's unpublished version that heal's manifest
       upload, which has no recheck, would then name. With no upstream it pushes before its checks
       (git refuses when the clone is behind), so 4a's no-upstream test now sees heal's refused push,
       before the data file is stored: no data-file line, storage unchanged.
    3. Step d's stops say "Nothing was pushed or published" rather than "datom changed nothing",
       since heal's reset or the pull may already have changed the clone.
    4. The metadata-only route returns `action = "published"` or `"none"`, and keeps its own check
       of the stored `metadata.json` after heal's publish (the committed-hand-edit test goes
       through it).
    5. **The repair's override is tested through heal's publish with `all = TRUE`**, called
       directly; `datom_validate(fix = TRUE)` reaches it in task 7. Until then the way out the
       stops name, today's repair, still clears both states (it uploads the clone's manifest and
       documents), without saying what it replaced, and without pushing first.
    6. `.datom_pushed_artifacts()` is left for task 6, its first user, as task 2 left the
       second-clone fixture for its first user.
    7. The two "push brings in a teammate's commit" tests replace the push with one that leaves
       the clone as that merge would: a real merge of two datom writes conflicts in the manifest
       until task 5, which now carries the end-to-end case.
  - **Checkpoint review fixes, 2026-11-06** ("Where things stand"): `datom_write()` refuses `NA`,
    `NaN` and `Inf` in custom metadata; heal's publish opens on differing manifest rows only and
    pushes only to finish its own version; the metadata-only route pushes before its own upload.
    Suite 5715 -> 5747 expectations, none removed. Each new guard probed red against its own test
    (`research/task4b_guard_probes.R`; results in that commit's message), and the whole sweep re-run
    on the fixed code. Recorded in full this time: the "manifest held back after a failure" probe
    reddens five tests (the four whose setup breaks a write at its metadata upload, and "heal's
    publish failing ...").
  - **Heal takes two lists (task 4a's checkpoint review, point 3; settled by the owner on
    2026-11-05, recorded in design sections 2 and 4).** The background, as it was put to the owner:
    Heal does two things for a command's own table, and they are safe under different conditions:
    putting back uncommitted files (step a) only when the command writes those files again, and
    pushing and publishing a committed version (step d) when the command publishes that table
    anyway. Ordinary writes do both for the same table, so one name covers both. The metadata-only
    route, `datom_write(conn, name = "dm")`, publishes `dm` but never rewrites its files. Task 4a
    passes it no table (`.datom_heal(conn)`), which is right for step a (uncommitted `dm` files stop
    it) and wrong for step d: in the case the route exists for (v2 pushed, storage upload failed,
    storage still on v1), step d would treat `dm`'s differing row as another table's unfinished
    work and stop, instead of publishing v2. Today the route copies only the clone's
    `dm/metadata.json` and `dm/version_history.json` to storage, not the snapshot or the manifest;
    moving it onto `.datom_publish_artifacts()` below makes it publish all four.
    - **Decided: two lists.** `.datom_heal(conn, artifact = NULL, rewrite = artifact, all = FALSE)`:
      `artifact` is what the command may push and publish (step d), `rewrite` the subset whose files
      it writes again, so step a may reset only those. The metadata-only route passes
      `artifact = name, rewrite = character()`; the data-frame route and the set write pass one name
      as now. `datom_sync()` (task 6) passes every table in its preview as `artifact` and only the
      rows it writes (`new`, `changed`) as `rewrite`. Added by the review of `b6b83b1`, taken:
      (1) the manifest follows `rewrite` too: one set decides both the files and the manifest rows
      step a may put back, so on the metadata-only route an uncommitted row of its own table stops
      the command; (2) `rewrite` must be a subset of `artifact` (heal refuses a name outside it, an
      internal error), "writing it again now" is said only for `rewrite`, and `all = TRUE` covers
      both steps for every artifact.
    - **Set aside: one yes/no switch** (`rewrites = FALSE`). It is wrong for `datom_sync()`: a
      preview row `unchanged` whose files have uncommitted edits would be reset with "writing it
      again now" and then skipped, losing the edits under a false message; two lists stop on it
      instead, naming `datom_validate(fix = TRUE)`.
    - Tests: after a write of `dm` broken at its metadata upload, `datom_write(conn, name = "dm")`
      publishes v2's documents and the manifest, and still stops on an uncommitted edit of `dm`'s
      files and on an uncommitted change to `dm`'s manifest row; a name in `rewrite` outside
      `artifact` is refused. Guards to probe: step d counting `artifact` as the command's own
      (against the publish test), step a resetting only `rewrite` (against the two stop tests).
  - **"datom changed nothing" only when heal reset nothing** (review of `b6b83b1`, optional nit,
    taken). When heal has just put back the command's own files and the pull then stops (the user's
    files in the way, a failed fetch), the stop says datom put back the unfinished files of `dm`
    (the line above) and changed nothing else. Heal already returns what it reset; the write's pull
    step passes it to the pull's stops. Test: a write of `dm` broken before its commit, then a
    teammate's commit and the user's own file in the way: the re-run prints the reset line and
    stops with the stash recipe, without "datom changed nothing" (traced 2026-11-05 on the code
    of `b6b83b1`: today it says it).
  - `R/heal.R`: heal's step d, run only when the clone is ahead of the remote or a stored manifest
    row differs from the clone's (one read of the stored manifest, reused by the publish);
    `.datom_unpublished_artifacts()` (rows that differ; no union with the pushed artifacts) and
    `.datom_publish_artifacts()` (the one publish path). `.datom_pushed_artifacts()` is built here
    too, for R3.6 (task 8) and the scan (task 6), not for step d. A write's steps 5-6 and the
    metadata-only route move onto `.datom_publish_artifacts()`. (`.datom_push_metadata_s3()`'s
    docstring is corrected in task 2.)
  - **Step d acts only on the command's own artifacts** (D14 principle 8): a differing row of any
    other artifact stops the command before the push, naming it and `datom_validate(fix = TRUE)`.
    A stored row for an artifact the clone does not have counts as differing (2026-11-04), here
    and in the manifest upload's agreement check below, so a write never drops it silently;
    `all = TRUE` (the repair, task 7) publishes them all.
  - **The containment check** (R3.10): for each artifact to publish, the clone's
    `version_history.json` must contain the version the stored row names (no stored row or no stored
    manifest passes); otherwise a write stops before changing anything, naming the artifact, with
    "re-run (a write pulls first); if it persists, `datom_validate(fix = TRUE)`". Containment, not
    "older" (a revert brings back an id already in the history). **The repair overrides it**
    (`all = TRUE`; review of `4045fbd`, 2026-11-03): it publishes the clone's version and names the
    stored version it replaced; an artifact the stored manifest names but the clone lacks loses its
    row, and the repair says so.
  - **The manifest upload** (R3.10, design section 4): when the pull inside a write's push moved
    HEAD, read the stored manifest once more and upload only if every row other than the write's own
    agrees with it; otherwise skip the upload, say so, and name `datom_validate(fix = TRUE)`.
  - `.datom_publish_artifacts()` publishes the manifest only if every artifact's documents were
    published; when heal's publish fails, the command stops before its own work (design section 6).
  - Every snapshot is keyed by `.datom_compute_metadata_sha()` of the document being published, the
    key the write itself used (design section 4, step d).
  - One shared reader for datom's own files in the clone, with one condition class and the short
    message (design section 4, step d: restore the artifact's datom files from a commit where they
    parse, `git commit`, re-run). It is used by heal's publish, `.datom_lookup_history_object_sha()`,
    `.datom_write_metadata_local()` and the version count in `.datom_update_manifest_entry()`;
    `.datom_prior_metadata()` keeps treating a broken `metadata.json` as absent.
  - Settle design section 10 item 3 (a stored manifest unreadable for a reason other than absence) and
    item 5 for the publish messages, and record the answers in `design.md`.
  - Tests: the break table's step 6 for both write commands, and its rows for the metadata-only route
    (P1); another artifact's write broken after its commit (and, separately, broken at its storage
    upload after the push), then a write of a different artifact: it stops before changing anything,
    naming the artifact and the fix (R7.2, P13); a publish landing behind a colleague's newer one,
    corrected by that table's next write, while a write of another table stops naming the fix
    (P10); a revert to earlier content, then storage failing after the push: the re-run publishes
    the revert (the containment check passes, S4); storage naming a version the clone's history
    lacks, written straight into the fixture's stored manifest: a write stops and nothing changes
    (R3.10, P14), then `datom_validate(fix = TRUE)` publishes the clone's version and names the
    replaced one, and the next write runs; a stored manifest naming an artifact the clone lacks:
    the repair drops its row and says so; a write whose push pulls in a teammate's commit whose
    version is not in storage: the manifest is not uploaded, the message names the fix, and the
    write's own documents are published; the same with the teammate's version already in storage:
    the manifest is uploaded; a stored manifest row for an artifact the clone lacks (written into
    the fixture's storage): a write stops, changing nothing, and names the fix, then the repair
    drops the row with its message (2026-11-04); storage reads of
    `.metadata/manifest.json` counted through a mock: one during a write (R3.4; the three-table sync
    count is task 6's, since sync heals once only from then); a re-run after a push break makes no
    second commit, and the stored history names the version's first commit (the rule in
    `R/version-commit.R`; design section 4, step d); heal's publish failing for one artifact leaves
    the manifest unpublished and the command stopped before its own work, with a message naming the
    artifact and the file; after a write broken at step 5, heal's publish stores the snapshot at the
    key the history records for that version; a committed `metadata.json` that does not hash to its
    recorded version (a hand edit committed with plain git, as 0.2.0's metadata-only route did)
    leaves the previous version's snapshot byte-identical, adds one snapshot under the edited
    document's own version, and still publishes the manifest; a committed unparseable
    `version_history.json` gives the short message both from heal, while that artifact's publish is
    pending, and from a write of that artifact with nothing pending, before anything changes,
    matched by the condition class; **on a clean, current, fully published clone, heal's publish
    writes nothing to git or storage (P12)**.
  - Guards to probe: the unpublished-artifact comparison, the manifest-last order, the manifest held
    back after a failed artifact, the publish gate (against the P12 test), the shared reader's stop,
    **the stop on another artifact's differing row**, **the containment check** (against the
    stored-version test, and as "older" against the revert test, which must redden), **the repair's
    override** (against the repair half of the stored-version test), **the manifest
    upload's agreement check** (against the teammate's-commit test), **a stored row the clone
    lacks counted as differing** (against its test).
  - Acceptance: P1 (all six steps, tables and sets), P10, P12, P13, P14, R3.4, R3.10;
    `research/other_command_probe.R` shows `lb`'s write stopping and naming `dm` when `dm`'s write
    broke after its commit.

- [x] **5. A conflict only in the manifest** (R3.8, R3.9; DD2; design section 5)
  - **Done 2026-11-06.** Suite 5747 -> 5859 expectations, none removed; the 112 new ones are all in
    the new `tests/testthat/test-manifest-conflict.R`. Every guard listed below probed red against
    its own tests, with a control that reddened nothing (`research/task5_guard_probes.R`; every test
    each probe reddens is in the commit message), plus five not listed: the manifest-only condition
    loosened to "the manifest is among the conflicted files", the version the files describe,
    starting from the merged-in side's copy, `datom_pull()` passing `finish_merge` on, and the
    other-merge stop while a file still conflicts under `finish_merge`.
    `research/two_writers_probe.R` updated for the pull every write now makes, and rerun: the second
    write finishes (`research/README.md`). Design section 10 item 6 settled there: the format check
    needs only the clone's path. Names: `.datom_resolve_manifest_conflict()`,
    `.datom_row_from_clone()`, `.datom_clone_files_version()`, `.datom_stop_merge_refused()`,
    `.datom_stop_merge_manifest_unusable()`, `.datom_manifest_row()`, `.datom_manifest_summary()`;
    the finish message has class `datom_merge_finished`. Differences from the list below, each
    flagged at the checkpoint:
    1. **Which version a row is compared with, and names when rebuilt**: the document's own version
       (`.datom_compute_metadata_sha()`) when its history names it, else the one the history
       records (`.datom_clone_files_version()`; design section 5, step 3). The plan said the
       recorded one, which names the wrong version after custom metadata is set back to earlier
       values: a teammate's correct row would be replaced, and every later write of another
       artifact would stop on it. A test covers it.
    2. The rebuild starts from HEAD's copy when the merged-in side's does not parse, and stops,
       naming `git merge --abort`, when neither does.
    3. The format check's refusal keeps its class and its evidence, wrapped in a message giving the
       merge's state and the two ways out. A write run while that merge is still in progress meets
       the same refusal at its own door first, which names the upgrade but not `git merge --abort`;
       `datom_pull()` repeats the full message.
    4. `.datom_manifest_summary()` extracted: the summary counters were computed in two places, and
       the rebuild would have been a third.
    5. `datom_pull()`'s `finish_merge` has a one-line `@param` now, since `R CMD check` requires
       every argument documented; its help text proper is task 10's.
    6. The test of the case the manual path got wrong builds "unpushed writes of `dm` and `lb`" with
       the second write skipping heal (`.healed = TRUE`): since task 4b a write stops on another
       artifact's unfinished work, so only a sync whose pushes all fail leaves that state.
  - `R/manifest-rebuild.R`: extract `.datom_manifest_row()` from `.datom_rebuild_manifest_entry()`,
    which keeps its behaviour.
  - `R/heal.R`: `.datom_resolve_manifest_conflict()`, simplified (design section 5): start from the
    remote's manifest and rebuild only the rows that disagree with their artifact's files, adding
    missing ones; no comparison with the merge base. Two callers: `.datom_git_pull()` when the
    manifest is the only conflicted file, so every pull gets it (`datom_pull()`, the push commands,
    and the migration pull in `.datom_resolve_data_location()`, `R/ref.R`; that last caller gets no
    test of its own, since its existing tests replace the pull with a stub), and the merge check's
    finishing branch (design section 4, step 0): once a merge of the remote branch in progress has
    nothing conflicted but the manifest, rebuild it, commit the merge ("Merge finished by datom
    (manifest rebuilt)"), say so, and carry on.
  - **The format check before the rebuild** (R3.8, design section 5 step 2): the function writes the
    remote's copy in place of the conflict markers, runs `.datom_check_write_entry(conn, NULL)`, and
    only then rebuilds rows and commits; a refusal stages and commits nothing and leaves the merge in
    progress. Settle design section 10 item 6 (what the check needs where the caller holds no
    connection) and record the answer in `design.md`.
  - `R/forward-compat.R`: the vocabulary refusal and the unreachable-shape refusal also name the
    installed datom version, so every refusal of the format check names its evidence (R3.8; the
    schema and floor refusals already do). Matched by class, so no existing test changes.
  - `R/sync.R`: `datom_pull()` gains `finish_merge = FALSE` (R3.9). When `TRUE`, the merge check
    finishes a merge that is not of the remote branch the way it finishes one that is; with nothing
    in progress it does nothing. Its help text is task 10's.
  - **Timing in the two-clone tests** (noted 2026-11-06): since task 4a every write pulls before its
    own work, so "two clones write without a pull in between" only happens when the other clone's
    push lands after this write's opening pull and before its own push. The tests make that happen
    inside the write, for example by wrapping this clone's `.datom_git_commit()` so that, once, the
    other clone's commit is pushed right after this one commits (a once-only flag, since mocked
    bindings apply to every call). `test-heal-publish.R`'s `hp_push_bringing_in()` and its "heal's
    push does not pull" test use the same idea.
  - Tests (R7.7): two clones writing different tables without a pull in between, and a write whose push
    broke while the other clone pushed, both finish with a manifest naming both tables; `datom_pull()`
    resolves a manifest-only conflict; two clones writing the same table still stop, publishing
    nothing; the storage-side rebuild's existing tests still pass; the case the manual path got
    wrong: a clone with unpushed writes of `dm` and `lb`, a teammate's pushed write of `dm`, the
    merge stopping on `dm`'s files, then `git checkout MERGE_HEAD --` for them and a re-run, which
    finishes the merge with both `dm`'s and `lb`'s rows agreeing with their files; a user's own file,
    resolved and `git add`ed, goes into the merge commit; a merge that brings in a manifest field this
    build cannot classify, conflicting only in the manifest, stops before the rebuild both at the pull
    and from the merge check, committing nothing and leaving `MERGE_HEAD` in place, with a message
    naming the document, the field and the installed datom version, matched by the condition class;
    the same message evidence for the unreachable-shape refusal; `datom_pull(conn, finish_merge =
    TRUE)` finishes a user's `git merge --no-commit` of a local branch with the manifest rebuilt and
    commits nothing while another file still conflicts; with no merge in progress it pulls as usual;
    without `finish_merge` the user's merge stays untouched (task 4a's stop).
  - From task 4b (2026-11-06): the end-to-end case of the manifest upload's agreement check. Two
    clones write different tables with no pull between, the first's publish broken after its push;
    the second's push merges it (the manifest-only conflict rebuilt here), so its manifest would
    name the first's unpublished version: the manifest is held back with the warning, and the second
    write's own documents are published. Task 4b's tests simulate that merge inside the push.
  - Guards to probe: the manifest-only condition, the row-against-files comparison, the merge check's
    finishing branch, the format check before the rebuild (against the newer-field test), the
    `finish_merge` branch.
  - Acceptance: P6 (as extended on 2026-10-31); `research/two_writers_probe.R` shows the second write
    finishing.

- [x] **6. Scan and sync** (R4, R3.7; DD3; design section 7)
  - **Done 2026-11-07.** Suite 5859 -> 5967 expectations. Removed: the ten tests of
    `.datom_check_git_current()` in `test-utils-git.R` (13 expectations; the function is deleted).
    Added: 121 in the new `tests/testthat/test-sync-heal.R`. Six scan tests in `test-sync.R` now
    commit their fixture manifest (`commit_clone_manifest()`), since the scan reads the last
    commit; their count is unchanged. Every guard listed below probed red against `test-sync.R`
    and `test-sync-heal.R`, with a control that reddened nothing (`research/task6_guard_probes.R`;
    every test each probe reddens is in the commit message). `research/sync_and_manifest_probe.R`
    and `research/stale_preview_probe.R` rerun (`research/README.md`). Names:
    `.datom_pushed_artifacts()`, `.datom_clone_head()`, `.datom_write_left_changes()` (all in
    `R/heal.R`), `.datom_inform_sync_stopped()` (`R/sync.R`; class `datom_sync_stopped`).
    Differences from the list below, each flagged at the checkpoint:
    1. **What `.datom_pushed_artifacts()` measures**: the artifacts whose datom files differ between
       HEAD and the commit it shares with its upstream (the net change of the unpushed commits), so a
       teammate's commit the clone has fetched but not merged is not counted as its own (a test).
       **With no upstream branch it names nothing** (the open question this task had to settle):
       the scan then shows such a table `unchanged`, and the sync still finishes it, since heal's
       publish pushes first with no upstream. Task 8's R3.6 message uses it too.
    2. **The format check on every preview table runs before the sync's one heal**
       (`.datom_check_write_entry(conn, own)`), as `datom_write()`'s door does for its one table:
       heal may publish any table in the preview, and without it a document from a newer datom,
       pulled earlier by `datom_pull()`, could be published unchecked. A test, and a probe.
    3. An `unchanged` row whose table heal published comes back `"success"`, not `"skipped"` (the
       plan named only `unpushed` rows). An `unpushed` row heal had nothing to publish for says it
       was already up to date.
    4. With `continue_on_error = FALSE`, after a write that changed the clone, the stop says to run
       the same call again (the scan and the sync until the checkpoint review) instead of "Set
       `continue_on_error = TRUE`", which would not skip it. A test.
    5. The stop message comes only when tables were skipped: a write that fails on the last table
       leaves its own error message, which names its way out.
    6. The scan's summary line names `unpushed` only when there are some, so the common line is
       unchanged.
    7. `local_heal_counter()` moved to `helper-interrupt.R`, beside a new
       `local_stored_manifest_reads()`; the R3.4 test in `test-heal-publish.R` uses it.
    8. The help pages of `.datom_check_merge()` and `.datom_heal()` are regenerated here: they were
       out of date since task 5.
    Left for task 10: `dev/datom_specification.md` ("Stale state detection" and the collaboration
    list) and two lines of `dev/engineering-notes.md` still name the deleted function.
  - **Checkpoint review fixes, 2026-11-07** (review of `c24b17f`, "Where things stand"): a held-back
    manifest stops the sync (a calling handler for `datom_manifest_held_back` around each table's
    write, which lets the warning through; the warning carries the artifacts it names as
    `disagree`); both stop messages name the same call, with the same preview, as the way out.
    `local_teammate_after_commit()` moved to `helper-interrupt.R` (a second file needs it). One new
    test follows the held-back stop's way out to the end; the break-table tests follow the stop's
    way out. Guards probed: the handler and the stop it sets, each reddening only the new test, with
    a control that reddened nothing (`research/task6_guard_probes.R`).
  - **Settled 2026-11-07 by the owner: stop the sync** (the first option below; design section 7,
    requirements R4.6 added, which the owner's answer approved). Found 2026-11-06 by probing this plan,
    `research/sync_batch_probe.R`; design section 10 item 7. This task's sync heals once for the
    batch and then writes each table with `datom_write(.healed = TRUE)`, so no later table's write
    runs heal. When one table's write fails partway and a later one succeeds:
    - table `t2` broken at its push or its metadata upload: `t3`'s publish uploads a manifest naming
      `t2`'s new version while storage holds `t2`'s old `metadata.json`; readers get the old
      version, and a re-run publishes nothing for `t2` (the manifest rows agree), so this task's own
      break-table test ("re-scan and re-sync, and every table reads") would fail;
    - `t2` broken at its commit: `t3`'s commit takes `t2`'s uncommitted manifest row, and `t3`'s
      publish puts it in storage (P4).
    Options to put to the owner, one point: **stop the sync at the first table whose failed write
    left anything in the clone** (uncommitted datom files, or HEAD moved: one `git status` and a
    HEAD comparison, on the error path only), skipping the rest with a message to re-run
    `datom_sync()`, which then finishes the broken table through heal; failures that leave the clone
    untouched (the import, a refused data frame, the data file upload) still carry on as
    `continue_on_error` promises. Or **keep a heal per table**, as today: each later table then
    stops naming `t2` and `datom_validate(fix = TRUE)`, at one fetch and one stored-manifest read per
    table, which R3.7's once-per-sync rule and R3.4 set out to remove. Lean: stop the sync. A
    re-check of storage before each later manifest upload is not enough on its own (the commit
    case). Record the decision in design section 7 and this bullet, and amend R4 if it changes what
    `continue_on_error` promises (ask whether the owner's answer approves that).
  - Build `.datom_pushed_artifacts(path)` in `R/heal.R` (left from task 4b for its first user):
    the artifacts whose files the commits the remote lacks touch, from local refs only (design
    section 2). Decide here what it returns with no upstream branch, where `.datom_git_ahead()` is
    `NA`.
  - `R/sync.R`: `.datom_read_manifest()` gains the `"head"` scope; `datom_sync_manifest()` compares
    against it and reports `unpushed` for tables `.datom_pushed_artifacts()` names, from the clone
    alone: no fetch, no storage read, no warning branches, no special case for a clone that is behind
    (R4.2, narrowed 2026-10-31); status order as in design section 7.
  - `datom_sync()` heals once, with every table in its preview as `artifact` (task 4a, point
    2) and the rows it writes (`new`, `changed`) as `rewrite` (task 4a's checkpoint review,
    2026-11-05; a test: an `unchanged` preview row with uncommitted edits stops the sync, naming
    `datom_validate(fix = TRUE)`, and its edits survive), instead of calling
    `.datom_check_git_current()`, then calls `datom_write(.healed = TRUE)`;
    unfinished work on a table outside the preview stops it before anything changes, naming
    `datom_validate(fix = TRUE)`, with a test; `unpushed` rows come
    back `success` without an import; a row whose write found no change says it was already up to
    date.
  - Delete `.datom_check_git_current()` and its tests (named in the commit message). Rewrite the
    comments that name it: the branch-guard comment in `datom_repo_commit()` (the guard and its reason
    stay), the docstring of `.datom_git_ahead()`, and the upstream note in `.datom_git_push()`.
  - Tests: R4.1-R4.5; the break table's `datom_sync()` row; the stale preview of DD3; heal called once
    in a three-table sync, and one storage read of `.metadata/manifest.json` during it, both counted
    through a mock (R3.7, R3.4); a scan makes no fetch and no storage read, recorded through mocks
    (R4.2); a table pushed but not yet published shows `unchanged`, and the `datom_sync()` that
    follows publishes it (R4.4, R4.5).
  - Guards to probe: the comparison against the last commit, the unpushed check, and whatever the
    open point above adds (for "stop the sync": the stop itself, each of its two tests -- datom
    files left uncommitted, HEAD moved -- against its own break, and a failure that left the clone
    untouched still carrying on).
  - Helpers to reuse, each local to one test file today (move one to `helper-interrupt.R` when a
    second file needs it): `local_heal_counter()` in `test-heal.R` counts heal's two halves; the
    stored-manifest read counter in `test-heal-publish.R`'s "a write reads the stored manifest once
    (R3.4)"; `local_teammate_after_commit()` in `test-manifest-conflict.R` lands another clone's
    push between this command's commit and its push. A sync test needs rio (installed here) and an
    `input_files/` folder, which a fresh `datom_clone()` lacks.
  - Acceptance: R4.1-R4.5 and R3.7's once-per-sync rule; `research/sync_and_manifest_probe.R` and
    `research/stale_preview_probe.R` show the table published and the honest message.

- [x] **7. The repair** (R5; design section 6)
  - **Done 2026-11-07.** Suite 6006 -> 6127 expectations. Removed from `test-sync.R` (15
    expectations), each covered by the new `tests/testthat/test-repair.R` (136) on a real project:
    ".datom_sync_data_metadata syncs per-table metadata to storage", "... handles per-table errors
    gracefully", "... syncs metadata snapshots from .metadata dir" (the folder no datom command
    writes), "... handles multiple tables", and the two unit tests of the deleted
    `.datom_sync_one_artifact()`. The other mock-folder tests of the repair in `test-sync.R` stub
    heal, the pull and the push (`local_repair_on_folder()`); the stored-error test now breaks
    `.datom_publish_documents()`. In `test-validate-sets.R` the "restore declines loudly" fixture
    commits its edit of `set.json`, since an uncommitted one is now reset first. Every guard below
    probed red against `test-repair.R`, with a control that reddened nothing
    (`research/task7_guard_probes.R`; every test each probe reddens is in the commit message).
    `research/clone_snapshot_probe.R` and `research/snapshot_sources_probe.R` updated and rerun,
    `set_steps_probe.R` and `other_command_probe.R` rerun (`research/README.md`). Names settled:
    `.datom_documents_version()` (task 5's `.datom_clone_files_version()`, renamed because it now
    reads stored documents too); `.datom_repair_push()`, `.datom_repair_results()`,
    `.datom_report_repair()` (`R/sync.R`); `.datom_validate_stored_rows()`,
    `.datom_validate_manifest_mismatch()`, `.datom_validate_mismatched()` (`R/validate.R`).
    Differences from the list below, each flagged at the checkpoint:
    1. **`datom_validate(fix = TRUE)` runs the repair whether or not its checks found anything.**
       Until now it ran only when a check failed, and no check sees datom's files left uncommitted,
       a version committed but not pushed or published while storage agrees with itself, or a lost
       current snapshot, so every write's stop naming the fix led to a repair that did nothing.
       The planned snapshot test needed it too (a lost snapshot is not reported). A probe.
    2. **`fixed` is `TRUE` only when every artifact was published**; it was `TRUE` whenever the
       sync ran without an error, even with per-artifact failures.
    3. **A set's payload that cannot be restored** (a storage failure) leaves that set's documents
       unpublished and the manifest too. (Reshaped by the checkpoint review below: the restore now
       runs before heal's publish, and a failure stops the repair.)
    4. The repair's result per artifact: `action` is `"published"` (was `"synced"`) or `"error"`,
       with `version`, `reset`, `pushed` and `error`; an artifact whose never-committed first write
       was reset is listed with `action = "reset"`. The return gains `manifest`.
    5. A row missing from the stored manifest, beside stored documents (a first write broken before
       its manifest upload), is reported as `manifest_mismatch_s3`. A stored manifest that is
       absent, unreadable or too new skips the check rather than reporting every artifact.
    6. `datom_validate()` prints one warning naming the mismatched artifacts and the fix, beside
       the status in its frame.
    7. To answer `datom_write(conn)`'s prompt in a test, `R/sync.R` binds `interactive` and
       `readline` to `NULL` (testthat's idiom for mocking a base function; a call skips a binding
       that is not a function).
    Left for task 10: `dev/datom_specification.md` still says three functions upload the stored
    history (one does since this task), and the help of `datom_write(conn)` is only adjusted in
    its `name` argument.
  - **Checkpoint review fixes, 2026-11-07** (review of `9284ca9`, "Where things stand"):
    `datom_validate()` finds artifacts with `.datom_clone_artifact_names()`; a set's payload is put
    back before heal's publish, and a failure stops the repair before anything is published
    (`.datom_repair_restore_payloads()`, `datom_payload_restore_failed`; the `manifest =` argument
    added to `.datom_publish_artifacts()` above is gone again); a stop inside the repair comes
    through `datom_validate(fix = TRUE)` unchanged; the role and path messages name the repair; the
    help of `fix` says a repair during a teammate's write can replace their publish. Mock tests in
    `test-validate.R` and one in `test-utils-path.R` give their folders a datom `hash_algo`, as a
    real write does. Guards probed: validate's discovery, the restore before heal's publish, the
    restore's stop, the stop through validate, and two probes re-pointed (a payload first, the
    manifest after a failure).
  - `R/sync.R`: `.datom_sync_data_metadata()` heals every artifact (`all = TRUE`; so it pushes and
    resets or publishes other artifacts' unfinished work, which writes leave to it), right after its confirmation
    prompt, which says it may push. This is the only place the mirror-everything route and the
    repair heal (design section 4). Then it restores each set's payload where storage lacks it
    (`.datom_restore_set_payload()`, data file first), publishes every artifact through
    `.datom_publish_artifacts()` (snapshot, history, `metadata.json` last), then the manifest, only
    if every artifact published (P7; design section 6).
  - From task 4b's checkpoint review (2026-11-06): heal's publish now pushes only to finish a
    differing manifest row, so the repair pushes any unpushed commits itself before it republishes
    every artifact (R5.2), without pulling again; otherwise it could put a committed document
    GitHub lacks into storage. A test: a committed, unpushed edit of an artifact's `metadata.json`
    whose manifest row agrees, then `datom_validate(fix = TRUE)`: GitHub has the commit before
    storage changes.
  - Delete `.datom_sync_one_artifact()` and its clone-folder snapshot loop: no datom command writes
    `{name}/.metadata/` in a clone (confirmed 2026-10-30 by a real write). Name in the commit
    message: the retired test "syncs metadata snapshots from .metadata dir" in `test-sync.R` and its
    replacement (below); the two unit tests of the deleted function, rewritten against the repair
    on a real project or retired where the publish path's own tests cover them; the stored-error
    test "per-table metadata sync's stored error has no escape codes", re-pointed to the
    per-artifact publish call. Update the header of `test-version-commit.R` and the "Three functions
    upload that file" line in `dev/engineering-notes.md`: one function uploads the history from this
    task on.
  - `R/validate.R`: `datom_validate()` reports per artifact what was reset, pushed and published
    (R5.3); `.datom_validate_one_table()` reports `manifest_mismatch_s3`, naming the fix, when the
    version the stored `metadata.json` and history describe differs from the stored manifest's row:
    storage reads only, no fetch (R5.5; design section 6). **Which version they describe** (owner,
    2026-11-06, option (a) of task 5's checkpoint review): the document's own version
    (`.datom_compute_metadata_sha()`) when every top-level field of the stored `metadata.json` is
    one this build can place (`.datom_metadata_known_fields()`) and the stored history names that
    version; otherwise `.datom_recorded_current_version()`. Task 5's `.datom_clone_files_version()`
    is the same rule without the placeability check (its caller's format check has just passed):
    share one helper, adding the check, and rename it if it no longer reads only the clone (name
    settled here). Tests: custom metadata set `"x"` -> `"y"` -> `"x"` on one table is not reported,
    before and after `fix = TRUE`; a stored `metadata.json` carrying a field this build cannot
    place, whose identity fields alone hash to an older history entry while the recorded entry is
    the newer one the manifest names, is not reported. Guards to probe: the document's own version
    (against the revert test), the placeability check (against the unplaceable-field test).
  - Tests: R5.1-R5.4; the break table's repair row; R7.8 (a crossed publish, stored manifest newer
    than stored metadata, reported naming the fix and cleared by `fix = TRUE`; a write broken before
    its manifest upload reported; a consistent store not reported); a
    "no" at the prompt leaves git and storage unchanged, and heal never runs; heal called exactly
    once by `datom_write(conn)` and by `datom_validate(fix = TRUE)`, counted through a mock; a write
    broken before its commit is reset, not published, by `datom_validate(fix = TRUE)` and by
    `datom_write(conn)` (P4); the keys the repair writes, recorded through a mock, run snapshot,
    history, `metadata.json` for each artifact, with a set's payload first and the manifest after
    every artifact; a stored current snapshot deleted after a real write is back after
    `fix = TRUE`, and a read pinned to that version succeeds; one artifact failing leaves the
    manifest unpublished, the others published, and a message to re-run; a committed
    `metadata.json` that does not hash to its recorded version (task 4b's fixture) does not stop the
    repair from publishing every other artifact and the manifest, leaves the previous version's
    snapshot untouched, and is not reported as `manifest_mismatch_s3`, before or after `fix = TRUE`
    (R7.8).
  - Guards to probe: the reset before publishing, the manifest-last order, `metadata.json` last within
    each artifact, the manifest-mismatch comparison (the recorded version, not a recomputed one).
  - Acceptance: R5.1-R5.5, P4 (for the mirror-everything route and the repair), P7, P11.

- [x] **8. The git and config commands** (R3.5, R3.6; D9, D10)
  - **Done 2026-11-07.** Suite 6134 -> 6214 expectations, 0 failed, 0 skipped. Its open point was
    settled by the owner first (option A): the stop looks at what the commit would actually take,
    which is everything with `paths = NULL`, a path that is a datom file or a folder holding one
    (`"dm"`, `"dm/"`, `"."`), **and any datom file already staged**, since a commit takes the whole
    index. One `git status`, shared with `.datom_unfinished_files()` (which gains an optional `st`
    argument for it). What differs from the plan, or was not in it:
    1. The stop is `.datom_stop_commit_of_unfinished()` in `R/heal.R`, with `.datom_paths_take()`
       deciding which files `paths` stages; it reuses `.datom_stop_unfinished_files()`, so the
       message and class (`datom_unfinished_work`) are a write's: re-run that write, or
       `datom_validate(fix = TRUE)`. A leading `./` is dropped before matching, so `"./dm"` stops
       although `git2r::add()` stages nothing for it (a stop with a way out, not a miss).
    2. R3.6's message is `.datom_note_pushed_unpublished()` in `R/heal.R`: a message (not a
       warning) of class `datom_pushed_unpublished`, carrying the names as `pushed`. Each of the four
       commands takes the names from `.datom_pushed_artifacts()` **before** its push, while the
       commits are the clone's alone; after it, the upstream is level and nothing would be named.
    3. Help text: `?datom_repo_commit`'s paragraph saying it sweeps in datom's files (the behaviour
       D9 reverses) is replaced, and the four commands each say their push does not publish. Task 10
       still owns the full R9.5 pass on these pages.
    4. The existing test that pinned the sweep-in ("datom_repo_commit(paths = NULL) sweeps in
       datom's own uncommitted files, and the repair reaches what it can (AC17)",
       `test-foreign-content.R`) is rewritten to the stop: the commit stops, the human's edit stays,
       and after `datom_validate(fix = TRUE)` the same commit takes the human's edit only.
    5. Left open at `3f48a48`, closed by its checkpoint review (below): `datom_repo_attach_governance()`
       and `datom_repo_set_data_store()` commit one named file through `.datom_git_commit()`, which
       also takes whatever is already staged. Each now runs the merge check and the same stop at its
       start, before writing its file.
  - Tests in the new `test-repo-unfinished.R` (real projects): the stop with `paths = NULL`, with
    six path forms, and with a staged datom file, each changing nothing in the clone, the remote or
    storage; a commit of the user's own path going ahead and leaving the write's files as they
    were; `datom_validate(fix = TRUE)` then letting `paths = NULL` through; `push = FALSE` during a
    merge in progress; R3.6 with `datom_repo_push()` (names `dm`, storage unchanged, a write of
    another table stops, and a write of `dm` or `datom_validate(fix = TRUE)` publishes), with
    `datom_repo_commit()` (and silence when no datom version is pushed), with
    `datom_repo_attach_governance()` and `datom_repo_set_data_store()`; the break table's row.
  - Guard probes (`research/task8_guard_probes.R`, against `test-repo-unfinished.R`, plus
    `test-foreign-content.R` where marked). Control: green (82 expectations). Each guard alone:
    | Probe | Reddened |
    |---|---|
    | the merge check removed from `datom_repo_commit()` | the merge-in-progress test |
    | the stop removed (with `test-foreign-content.R`) | the `paths = NULL` test, the path-forms test, the staged test, and the rewritten AC17 test |
    | `paths = NULL` no longer taken as everything (with `test-foreign-content.R`) | the `paths = NULL` test and the rewritten AC17 test |
    | a folder no longer covers its files | the path-forms test (12 expectations) |
    | `"."` no longer covers everything | the path-forms test (4 expectations) |
    | already-staged files ignored | the staged test |
    | `datom_repo_push()` taking the names after its push | its R3.6 test |
    | the message removed from `datom_repo_commit()` / `datom_repo_attach_governance()` / `datom_repo_set_data_store()` | that command's R3.6 test, one each |
    | (checkpoint review) the merge check removed from `datom_repo_set_data_store()` / `datom_repo_attach_governance()` | that command's merge test, one each |
    | (checkpoint review) the staged-file stop removed from `datom_repo_set_data_store()` / `datom_repo_attach_governance()` | that command's staged test, one each |
    | (check of `6921561`) `datom_repo_set_data_store()`'s two checks moved back after the read of `project.yaml` | the conflicted-`project.yaml` test only |
  - `R/repo.R`: `datom_repo_commit()` calls the merge check, then, before staging, stops when the
    commit would include datom's own uncommitted files (`paths = NULL`, or an explicit path naming
    one), naming the artifact and `datom_validate(fix = TRUE)`; it resets nothing (R3.9, R3.5, D9 as
    amended 2026-10-31); it, and `datom_repo_push()`, `datom_repo_attach_governance()` and
    `datom_repo_set_data_store()`, name the datom artifacts in the commits they push and say they are
    not yet published.
  - Tests: R7.2's `datom_repo_commit()` cases (with and without `paths`); R3.6 with
    `datom_repo_push()` (message names the artifact, storage unchanged, a write of that artifact or
    `datom_validate(fix = TRUE)` publishes it, and a write of another artifact stops); the break table's `datom_repo_commit()` row; `datom_repo_commit(push = FALSE)`
    during a merge in progress leaves the merge and every file alone and gives the merge message.
  - Guards to probe: the merge check in `datom_repo_commit()`, its stop on datom's own uncommitted
    files (with and without `paths`).
  - Acceptance: R3.5, R3.6.
  - **Escalation after: purity audit on a more capable model** (tasks 2-8).

- [x] **9. `datom_init_repo()` interrupted** (R6 as rewritten; design section 8)
  - **Done 2026-11-08, reshaped first.** The four open points of the cold start were raised with
    the owner one at a time; the first three were settled (A each: `mode` and `set` must match too;
    finish only when level with the remote; check the config's format). At the fourth the owner asked
    why a half-done init is not simply started again. Answer: before the push it already is; after
    it, starting fresh means deleting a GitHub repo, which needs a token scope most users lack, or
    one the user supplied, and the repair already finishes the job. **The owner chose option B: no
    re-run logic, a stop that names a way out that works** (requirements D5 reversed, R6 rewritten,
    design section 8). `.datom_init_finish()` is not written.
  - `R/conn.R`: after the push, building the storage connection and uploading the manifest run in
    one handler (the connection was outside it, so a malformed credential stopped with a bare
    error). The stop, class `datom_init_manifest_failed`, says the git remote has the repo, names
    `conn <- datom_get_conn("<path>", store)` then `datom_validate(conn, fix = TRUE)`, and says a
    re-run of `datom_init_repo()` refuses. It used to name `datom_validate(conn, fix = TRUE)` with a
    `conn` the user did not have.
  - Tests: new `tests/testthat/test-init-interrupted.R`, on a real project (folder remote, local
    store): a break at the commit and at the push leaves nothing (clone, bare remote, stored
    manifest) and the same call re-run succeeds; a break at the manifest upload names the way out,
    which is followed as written and leaves a published manifest, an empty `datom_list()` for a
    reader and a clean `datom_validate()`; a storage connection failing after the push names it too;
    a re-run after the break refuses and changes nothing. `test-conn.R`'s recovery test matches the
    new class.
  - **Checkpoint review, 2026-11-08**, by another agent, of `9127993` (with a spot-check of
    `cc7d6e1` and `9d53b1f`, which held): approved with one fix, evaluated with the owner. The
    review: a re-run's refusal ("Delete .datom to re-initialize") names a way out that ends in a
    raw git error. Checked here, and wider: which refusal a re-run meets depends on the remote (a
    folder remote: "already has content"; `create_repo = TRUE`: GitHub's error, after creating an
    empty repo; only a supplied GitHub address reached the folder check). **Taken, widened (owner,
    option A):** the folder check runs before anything touches the remote, and names both ways
    out (R6.2 amended, design section 8). The review's nit taken: both stops say to give
    `datom_get_conn()` the same store passed to `datom_init_repo()`. The re-run test covers all four
    remotes, and that no GitHub repo is created. A review of the fix (`1646c9b`) approved it with
    one wording change, taken: the same refusal meets a re-run in a healthy, published project, so
    the "start over" line now says it abandons the project and loses its history.
  - Acceptance: R6.1-R6.3 as rewritten.

- [x] **10. Documentation** (R8, R9)
  - **Done 2026-11-09**, after the test coverage review and its gaps (`9432cba`). The cold start's
    two open points were settled by the owner first: R9.1's conventions text gains one sentence in
    its order bullet, "Every publish pushes first, so storage never names a version GitHub lacks"
    (the "Nothing was published." line and ways out spelled to work stay spec details); R9.5's help
    is one short paragraph per page saying what the user sees and what to run, two for
    `?datom_write`. What differs from the plan, or was not in it:
    1. Several R9.5 pages were already written by earlier tasks and are left as they were:
       `?datom_sync` and `?datom_sync_manifest` (task 6), `?datom_repo_commit` and the three other
       push commands (task 8), `?datom_validate`'s `fix` (task 7), which gains one sentence for a
       stored manifest the repair cannot read (the coverage review's new test).
    2. `?datom_store_local` gains a paragraph: design section 12 documents two rows there (the
       temporary file, a file system without hard links); R9.5 did not list the page.
    3. `dev/datom_specification.md`: beyond R9.2, R9.3 and R9.7, the "Conflict Resolution" section
       is rewritten (it described `.datom_check_git_current()`, deleted in task 6, and a manual
       `git commit` recipe), the change-detection bullet on re-runs, the route table's
       `NULL`/`NULL` row (the repair), and the bullet that said the parquet upload "stays after
       the git push" and "must not be refactored".
    4. `.kiro/specs/datom-sets/design.md`: beside I5's note, one under section 19.7's decision that
       `datom_repo_commit(paths = NULL)` sweeps in datom's files, which D9 reversed.
    5. R9.4: none of the three old-order phrases is left in `R/`; two docstrings (heal's publish,
       the metadata-only route) said "storage upload failed" for what is now the metadata upload,
       corrected.
    6. `devtools::document()` reports two link warnings to internal functions with no help page
       (`.datom_restore_set_payload`, `.datom_validate_stored_rows`), present before this task;
       left as they are.
  - **Escalation first: test coverage review on a more capable model**, including the break table
    checked against the tests that exist.
  - Roxygen for every help page in R9.5, then `devtools::document()`. Beside `endpoint` in
    `?datom_get_conn`: a service that ignores conditional writes, and one that rejects the new
    headers, including that paws alone can trigger the latter (from `paws.common` 0.9.0 every upload
    carries a checksum by default).
    `NEWS.md` (R9.6; cite only `?verb` and `vignette(...)`, never `dev/` or `.kiro/`, conventions
    item 7a). It includes, from task 4b's checkpoint review: `datom_write()` now refuses a missing
    value (`NA`), `NaN` or `Inf` in custom metadata (a write that worked before now stops; leave
    the field out); and a write with nothing to save no longer pushes the user's own commits.
    Added 2026-11-08, from task 9: `datom_init_repo()` in a folder that already holds a datom
    repository refuses before touching the remote (with `create_repo = TRUE` it no longer creates
    a GitHub repo first), and after a break past its push it names the repair; a script matching
    the old message text needs the new classes (`datom_init_folder_taken`,
    `datom_init_manifest_failed`). From the purity audit: every stop that comes before
    publishing says "Nothing was published.", and the stops for another artifact's unfinished work
    share one class, `datom_unfinished_work` (the blocked pull keeps `datom_pull_blocked` too).
  - `?datom_init_repo` (R9.5 as amended): after a break past its push, the repair finishes the
    job; a re-run refuses, naming the repair and, labelled as abandoning the project, starting
    over. R9.4's list names `.datom_commit_and_mirror()`, renamed `.datom_commit_and_publish()` in
    the audit (its docstring was corrected in task 2).
  - Search `R/` for any old-order wording left after tasks 2-4b ("serialization point", "After git,
    never before", "local -> git -> S3") and correct it (R9.4).
  - `dev/datom_specification.md` (R9.2, R9.3, and R9.7: the route table's `data = NULL` with `name`
    row, which still says "after editing dispatch.json"); the conventions section in
    `.github/copilot-instructions.md` with the wording in R9.1; the note beside I5 in
    `.kiro/specs/datom-sets/design.md`; `dev/engineering-notes.md` gains design section 12's table.
  - Acceptance: R9.1-R9.7 done; every residual row in design section 12 is guarded or documented
    where the row says.

- [ ] **11. End to end, and spec completion**
  - **In progress 2026-11-09.** Done so far:
    - Every probe in `research/` rerun except the real-S3 one. `write_steps_probe.R` and
      `set_steps_probe.R`: every break fired, every re-run reads v2, `datom_validate()` valid (sets:
      v2 after the fix too). `sync_and_manifest_probe.R`: the re-scan says `unpushed`, the re-sync
      succeeds, a reader reads. `other_command_probe.R`: after `dm` broke at its commit or its push,
      `lb`'s write stops (`datom_unfinished_work`), nothing moved on GitHub or in storage.
      `two_writers_probe.R`: the second write finishes the merge itself, a reader reads both.
      `stale_preview_probe.R`: "already up to date", one version. `init_rerun_probe.R`: a break at
      the commit or the push leaves nothing and the re-run succeeds; after a break at the manifest
      the re-run refuses and `datom_validate(fix = TRUE)` uploads the manifest.
      `publish_race_probe.R` gains the correction by the next command: the race still leaves
      storage on v2 with GitHub at v3; a write of another table in the up-to-date clone stops
      naming the fix, and the fix publishes v3. `sync_batch_probe.R` needed one call updated
      (`.datom_pull_before_write()` lost its `reset` argument in the audit); its output is the
      unhealed plan's, as recorded. `merge_completion_probe.R` no longer reaches its subject: the
      pull now resolves the manifest-only conflict itself (task 5), so no `MERGE_HEAD` is left for
      it to finish; `two_writers_probe.R` shows the result. The git2r and git fact probes are
      unchanged. `s3_conditional_probe.R` passed 11 of 11 offline (`DATOM_PROBE_FAKE_S3=1`) on all
      three paws pairs; the real-S3 run is the owner's.
    - `dev/e2e-solo-local.R`: SUCCESS (real GitHub repo created and deleted).
    - `devtools::check()`: one warning, two `[link]`s this spec added to internal functions with no
      help page (`@noRd`); made plain code; then 0 errors, 0 warnings, 0 notes.
    - Harvest: `dev/engineering-notes.md` gains "Interrupted commands: the facts the recovery code
      relies on" (git2r, storage, identity, tests); `dev/datom_pathways.md` gains the card "Given a
      command that stopped partway, finish it or stop", and the write-entry and set-write cards
      follow the new order (pathway impact: yes). The follow-up issue on `datom_validate()`'s
      storage-completeness checks filed as
      [#158](https://github.com/amashadihossein/datom/issues/158); the draft file removed.
    - Left: `dev/e2e-solo-s3.R` and `research/s3_conditional_probe.R` against real S3 (the owner's
      credentials), then `dev/README.md`'s Completed Phases row and the PR into `dev`.
  - Rerun every probe in `research/`, as updated in tasks 2-4b, and record that every break fired and
    each now shows the job finished (or, for `publish_race_probe.R`, corrected by the next command).
  - `dev/e2e-solo-local.R`, and `dev/e2e-solo-s3.R` against real S3 with the owner's credentials.
  - `devtools::check()`; the full suite; the spec completion procedure (conventions item 7): harvest
    learnings, update `dev/README.md` Active Specs, PR into `dev`.
  - Acceptance: the end-to-end runs pass on both backends; `devtools::check()` is clean; the PR is
    open.
