# Requirements -- interrupted commands finish on a re-run

**Issue**: [#155](https://github.com/amashadihossein/datom/issues/155), reframed in its comment of
2026-10-27 from a patch into a whole-system design review.
**Branch**: `spec/interrupted-commands`, cut from `dev` at `347a403`. **PRs into `dev`.**
**Tier**: 3 (the write path, storage routing and an integrity hash). Requirements, design and tasks
each stop for the owner's approval; decisions are taken one at a time.
**Test baseline**: 5142 expectations, 0 failed, 0 skipped (`devtools::test()` on `dev` at `347a403`,
measured 2026-10-27 for the s3-credential-function spec at the same commit).
**Status**: **Approved by the owner on 2026-10-28.** Decisions agreed in chat the same day.
Amended with the owner later that day, during design review: R3.3 records that a colleague's later
publish can be overwritten until the next command (design DD4); R5.5 and R7.8 add the
`metadata_stale_s3` status to `datom_validate()`. During the review of `tasks.md`: R8 gains a row for
S3-compatible services that reject the new headers; and, in its third review, D13 (hand edits of
datom's own files are not supported), with R3.1, R9.1, R9.5, R9.6 and R9.7 amended to match.
**Amended 2026-10-30** with the owner, from a full-spec review by another agent (of `b76961b`): R3.9
added (a command that finds a merge in progress stops, touches nothing, and says how to finish it),
and R8's merge-conflict row corrected (no version is published, though the data file may be in
storage; the recovery takes the remote copy of all of an artifact's files with
`git checkout MERGE_HEAD --` and finishes with `git commit`). The last sentence of R3.8 carries the
same correction ("before any publish", not "before storage changes").
**Amended again 2026-10-30**, in a simplification pass set by the owner (principles and scenarios in
D14): D14 added; R3.7 gains the rule that no command writes to the git remote or to storage before it
has pulled, the pull being a step of each command rather than of heal; R3.8's rebuild simplified (rows
that disagree with their artifact's files, no merge-base comparison); R3.9 reworded (the merge check
runs in every git-touching command, and finishes the merge itself once only the manifest is left);
R5.5 and R7.8 rewritten from `metadata_stale_s3` (storage against the clone's last commit) to
`manifest_mismatch_s3` (storage against itself); R9.5 renames the status to match; R8's merge row
follows R3.9.
**Amended 2026-10-31** with the owner, from a review by another agent (of `058f29b`): D14 gains a
seventh principle (a user's own git operations in the clone are off the supported path; datom does
not guide them, but never leaves the project stuck), and S8 names them. R3.9 tells a merge of the
remote branch, which is what datom's pull makes, from any other: it finishes the first itself and
stops on the second until `datom_pull(conn, finish_merge = TRUE)` or `git merge --abort`. R3.8 runs
the format check on what the merge brought in before rebuilding the manifest, and every refusal of
that check names its evidence. The scan's new status becomes `unpushed`, set from the clone alone
(D4, R4.2, R4.3, R4.5, R7.6). R8's merge row, R9.5 and R9.6 follow.
**Amended 2026-10-31** with the owner, in the design spot-check before task 4a (with a review of
that spot-check by another agent): **a write heals only the artifact it is writing** (D3 narrowed,
D14 principle 8). Unfinished work on any other artifact stops a write before it changes anything,
naming the artifact and `datom_validate(fix = TRUE)`, which keeps resetting and finishing every
artifact (R3 rewritten; R3.1 and R3.2 now apply to the repair; R3.5 and D9: `datom_repo_commit()`
stops instead of resetting). R3.7 gains the check that the pull actually caught up; R3.10 is new
(storage naming a version the clone has never seen stops the command; a manifest upload only when
every other artifact's row agrees with storage). S3, S4, D13, R7.2, R9.1 and R9.5 follow.
**Amended 2026-11-03** with the owner, from a review of `4045fbd` by another agent: R3.10's
"version never seen" stop applies to writes only, and the repair overrides it, saying what it
replaced (it locked every write and the repair alike); the branch case leaves R3.10 for the
publish-branch rule's own issue (Related); R3.7 stops on a clone with no upstream branch; D10, R3.6
and R7.2 no longer say "the next datom write publishes it".
Reviewed 2026-10-28 (a review by another agent, evaluated with the owner): R3.7 added, R1.2, R1.3,
R2.2, R4.2 and R8 tightened, Q3 raised; the review's proposal to decode a stored file before adopting
its hash was declined (R8). Q3 settled the same day as D11 (no guard for mixed datom versions).
A second review the same day reworded R3.7 against #105 and broadened R8's merge-conflict row; it led
to D12 and R3.8 (datom resolves a conflict only in the manifest).

## Goal

The owner's rule for every command that changes things (agreed 2026-10-27):

- If a command runs steps a-d and all succeed, running it again does nothing harmful.
- If it broke partway, running the **same** command again carries the job to completion.
- Repeating steps already done is acceptable. Efficiency is secondary to finishing.

Today the write commands break this rule. The common cause: each command decides "is this done?"
from the clone, readers judge "done" from storage, and the clone is updated first. A break inside
that window makes every re-run trust the clone and skip, and two repair routes make readers fail.

## Terms

- **Data file**: the stored bytes of one version. A table's parquet at `{name}/{data_sha}.parquet`;
  a set's payload JSON at `{name}/{data_sha}.json`. Content-addressed by `data_sha`, and pinned by
  the hash of its exact bytes (`parquet_sha` / `document_sha`).
- **Pushed**: the commit that records a version is on the git remote.
- **Published**: the version's metadata documents (`metadata.json`, `version_history.json`, the
  version snapshot) and the manifest are in storage, so readers see it. Readers look only at
  storage.
- **Unfinished write**: a write that broke after changing something and before publishing.

## Findings (probed 2026-10-28 on `dev` at `347a403`)

Folder git remote and local storage; each break is a mocked binding raising at one step. Scripts and
how to rerun them: `research/README.md`.

**A table write broken at each step, then the same write re-run** (`write_steps_probe.R`):

| Break at | Reader after the break | Re-run reports | Reader after the re-run |
|---|---|---|---|
| git commit | old version | full | **read fails** |
| git push | old version | full | **read fails** |
| data file upload | old version | full | **read fails** |
| metadata to storage | old version | full | new version |
| manifest to storage | new version | none | new version; the stored manifest stays one version behind |

The re-run causes the damage: `.datom_resolve_parquet_sha()` finds the failed run's entry in the
clone's `version_history.json`, reuses its hash without uploading, and the re-run publishes
metadata for a file that is not in storage.

**Sets** (`set_steps_probe.R`): `datom_write_set()` behaves the same at commit, push and upload.
`datom_validate(fix = TRUE)` then repairs a set, because `set.json` is in git
(`.datom_restore_set_payload()` in `R/sync.R`); it cannot repair a table.

**A different command after the break** (`other_command_probe.R`): a write of `dm` breaks, then
`lb` is written.

| `dm` broke at | What the `lb` write does to `dm` |
|---|---|
| its commit | `.datom/manifest.json` is staged by every write, so `lb`'s commit carries `dm`'s new row. GitHub's manifest names `dm` v2 while GitHub's `dm/metadata.json` is v1; storage copies the contradiction |
| its push | `lb`'s push sends `dm`'s v2 commit to GitHub, but only `lb` is published |

**`datom_sync()`** (earlier probes, 2026-10-27/28): after a table's write breaks at its upload or its
push, `datom_sync_manifest()` reports the table `unchanged` (it compares input files against the
clone's working-tree `.datom/manifest.json`), and a second `datom_sync()` skips it. With every row
unchanged, `datom_sync()` returns "Nothing to sync" before doing anything.

**`datom_validate(fix = TRUE)`** (read from the code, confirmed by probe on 2026-10-27): diagnoses
each artifact (`data_missing_s3`), then copies the clone's documents for **every** artifact to
storage regardless, including files never committed. It never touches git.

**`datom_init_repo()`** (read from the code): a break before its push is rolled back and a re-run
works. A break after its push (the manifest upload) leaves `.datom/project.yaml`, so a re-run
refuses with "already exists"; its message names `datom_validate(fix = TRUE)`.

**Other commands that change things** (read from the code, not probed): a re-run already finishes
`datom_repo_attach_governance()` (one extra commit, since the governance file carries a fresh
timestamp), `datom_repo_set_data_store()`, `datom_repo_delete()`, `datom_repo_commit()` and
`datom_repo_push()`. The set edit commands and `datom_sync()` on a product repo write nothing.

**Re-serialising the same data frame** gives identical parquet bytes within one arrow version
(checked on arrow 23); an arrow upgrade can change them.

**Fetching** (read from the code, 2026-10-28): the repair never fetches; `datom_validate()` reaches
storage through `.datom_sync_data_metadata()`, which makes no git call. `datom_write()` and
`datom_write_set()` pull (fetch, then merge) only inside their push, in `.datom_git_push()`.
`datom_sync()` fetches at its start and stops if the clone is behind (`.datom_check_git_current()`),
but warns and carries on when the fetch fails (#104). `.datom_git_ahead()` compares against the
remote as of the last fetch. So a clone that is behind GitHub would publish an older version over a
colleague's newer one, through the repair or through R3.2 as first drafted.

**Teammates on a released datom** (read from the code): 0.2.0 still commits and pushes before it
uploads. `min_writer_version` in `.datom/project.yaml` exists, and datom 0.1.1 onward refuse to write
below it (`.datom_check_writer_floor()`, also on 0.2.0's repair route); 0.1.0 does not read it.
`datom_init_repo()` does not set it today.

## Decisions (owner, 2026-10-28)

| # | Decision | Options set aside |
|---|---|---|
| D1 | **Data file first.** A write uploads its data file before anything in the clone changes, and never overwrites a stored data file. Metadata and manifest still go to storage only after the push. A version exists once GitHub has it; a data file no commit names is invisible to readers | Keep git first and keep a copy of the data file in the clone until its upload succeeds. Set aside after a survey: Git LFS, DVC, Delta Lake and Iceberg all store the data before publishing the pointer, and git first leaves a version a colleague can pull but not read |
| D2 | **No separate record of a write in progress.** Every step leaves a mark in git or storage, and a re-run reads those marks to see where the last run stopped | A record file in a git-ignored folder of the clone: a second account of the same state that can drift, and only the clone that broke would have it |
| D3 | **The commit is the line.** Unfinished work found before its commit is reset; found after it, it is pushed and published from git. Says which in either case. **Who acts** (narrowed 2026-10-31, owner, design spot-check before task 4a): a write does this only for the artifact it is writing, and stops with a message on any other artifact's unfinished work, naming `datom_validate(fix = TRUE)`, which does it for every artifact (D14 principle 8) | Any command finishes or resets any artifact's work (the rule until 2026-10-31: heal kept meeting edge cases when it acted on other artifacts, and no check can prove whose work a leftover is); commit the unfinished files (can publish a write the user stopped on purpose). A refusal from every command, the same command's re-run included, was set aside in 2026-10 because one break would stop a whole sync |
| D4 | **A new scan status, `unpushed`**, for a table whose input file is unchanged but whose committed version is in commits not yet pushed, so readers cannot see it. Set from the clone alone. Renamed from `unpublished` and narrowed on 2026-10-31 (owner, review of `058f29b`): the scan no longer fetches or reads storage, so a table pushed but not yet published (S4) shows `unchanged`, and `datom_sync()` publishes it anyway because it finishes committed work before deciding there is nothing to sync (R4.4). "Published" is defined in the help | Keep `unchanged` and print a line (misleads a script that checks `all(status == "unchanged")`). The narrowing leaves that one case, a table pushed but not published; no documented workflow skips `datom_sync()` on the scan's statuses |
| D5 | **`datom_init_repo()` is in scope.** A re-run in a half-initialised folder finishes instead of refusing, under narrow conditions | Leave it refusing and pointing at the repair |
| D6 | **`datom_validate(fix = TRUE)` pushes** unpushed commits, then publishes | Publish only what GitHub has and name `datom_repo_push()` for the rest |
| D7 | **No rescue for states a released datom already created.** datom is experimental; the fix is designed for what new writes can produce. D11 extends this to teammates still writing with a released datom | Storage checks before every skip, correcting a version's recorded hash after an arrow upgrade, flagging sets that pin a version with no data file, restoring a set payload from an older commit |
| D8 | **The rule is written into `.github/copilot-instructions.md`** (wording in R9), with the detail in `dev/datom_specification.md` | Specification and engineering notes only (loaded on demand, so a session editing a write might not see it) |
| D9 | **`datom_repo_commit()` never commits a datom write that never committed.** Amended 2026-10-31 (owner, design spot-check before task 4a): it no longer resets one. When the commit would include datom's own uncommitted files (`paths = NULL`, or an explicit path that names one), it stops before staging anything, naming the artifact and `datom_validate(fix = TRUE)`; a commit whose paths do not include them goes ahead. A plain `git commit` from a terminal is outside datom's reach and is discouraged in the help | Leave datom's files out of an add-everything commit (the clone stays unclean); reset them before staging, as decided on 2026-10-28 (it acts on an artifact the command is not writing) |
| D10 | **The git and config commands push, and say so.** `datom_repo_push()`, `datom_repo_commit()`, `datom_repo_attach_governance()` and `datom_repo_set_data_store()` do not publish a datom write whose commit they push; they name it and say a write of that artifact, or `datom_validate(fix = TRUE)`, publishes it (amended 2026-11-03: under D14 principle 8 a write of any other artifact stops instead) | Publish what they push (commands about git or config start writing to storage, and after a data-store change "which storage" has two answers); refuse to push (blocks a product layer's commit) |
| D11 | **Teams writing one repo with mixed datom versions are not guarded against** (Q3). In practice everyone writing to a repo upgrades together. Recorded in R8 | Set `min_writer_version` at init for new repos and ask existing owners to add it; check for the data file before publishing any version |
| D12 | **datom resolves a merge conflict confined to `.datom/manifest.json`** by rebuilding the manifest from the artifacts' files in the merged clone, completing the merge, and saying so (R3.8). The manifest is derived, so nothing can be lost. Conflicts in any other file stop the command as today and stay with #105 | Leave every conflict to #105: a write whose push broke while a colleague pushed would not finish on a re-run, the main conflict R3.7 leaves |
| D13 | **Hand edits of datom's own files are not supported** (owner, 2026-10-28, third review of `tasks.md`). An artifact's `metadata.json`, `version_history.json` and `set.json`, and `.datom/manifest.json`, are written only by datom commands. An uncommitted change to one of them is treated as an unfinished write, whoever made it: a write of that artifact resets it and says so, any other write stops and names `datom_validate(fix = TRUE)`, which resets it (R3; amended 2026-10-31). So the metadata-only route, `datom_write(conn, name =)`, no longer commits a hand edit; it publishes what is committed for that table (whether it resets or stops on such an edit is settled before task 4a's code). To change custom metadata, use `datom_write(conn, data, name, metadata = )`, which records a metadata-only version with its history entry and manifest row. Until now the route committed a hand-edited `metadata.json`, but only half-recorded it (no history entry, no manifest row), and its documented purpose, editing `dispatch.json`, left with the governance layer | Exempt the named table from the reset on that route: it protected a use with no documented purpose, and after a write broken before its commit it would commit that write's half-finished files as if they were an edit, leaving `datom_read()` and `datom_list()` naming different versions |
| D14 | **Where datom heals and where it stops** (owner, 2026-10-30, simplification pass). Automate only what is common: re-running the same command finishes the job. (Until 2026-10-31 any command also finished other artifacts' committed work; principle 8 narrows that to the artifact the command writes, with a stop naming `datom_validate(fix = TRUE)` for the rest.) Rarer situations, chiefly two developers' work overlapping, stop before doing harm with a short message, and datom supports the manual step it asks for. States left by older releases, hand edits and files changed in storage by hand are documented only. **Every stop and every report names a way out**, even a manual one. A user's own git operations in the clone get no guidance, only the guarantee that the project is never left stuck (added 2026-10-31). The yardstick is the scenario table below | Build recovery for every scenario a review can imagine: each automation adds code and edge cases, and can put the common path at risk |

### D14 in full: where datom heals and where it stops

The owner's principles, set 2026-10-30 to stop fixes accumulating one review at a time:

1. Never permanently or irreversibly break functionality. A file that fails to reach storage on the
   first try, or one that needs overwriting, does not count: the next run can put it right.
2. Do no harm. Healing adds essentially no risk or friction to the common workflow: one developer,
   building and deploying, nobody else writing at the same time. On that path every healing step is
   a check that finds nothing and changes nothing.
3. Automate recovery for common interruptions: an outage mid-write or mid-sync, a crash, storage
   failing after the push. Re-running the command just finishes.
4. For rarer situations, chiefly two developers' work overlapping, stop before doing harm with a
   short, clear message. Involving the developer is fine at that frequency, provided datom supports
   the manual step: a step that needs hand-editing datom's JSON is not support. Automate a rare case
   only when the manual alternative would be that complex, and only where the common path never
   reaches the code.
5. States left by older datom releases, hand edits, or files changed in storage by hand: document
   only (D7, D11, D13).
6. Every stop and every report names a way out. Before a "stop with a message" is adopted, the
   recovery it gives is traced once.
7. A user working the clone directly with git (their own merges, rebases, inspection merges) is off
   the supported path and rare (owner, 2026-10-31). datom does not add checks or guidance for those
   workflows. What it must never do is leave the project stuck or inconsistent: protecting the
   project comes first, and less code is better. A guard for such a case is added only if, without
   it, the project could be locked out or left unreadable; an outcome that is consistent and undoable
   with ordinary git needs none.
8. **Heal acts only when it is certain something needs healing** (owner, 2026-10-31, design
   spot-check before task 4a). When a check is unsure, heal does nothing and the command stops with
   a way out. No check can prove whose work a leftover is (D2: no record of a write in progress), so
   "certain" means the action is one the command was about to take anyway, on the same artifact. A
   write therefore heals only the artifact it is writing; another artifact's unfinished work stops it,
   naming `datom_validate(fix = TRUE)`, which is the explicit consent to heal everything. A stop, not
   an interactive prompt: scripts and a product layer cannot answer one. Once enough confidence is
   established, a stop can become the action, in one place.

| # | Scenario | How often | What datom does |
|---|---|---|---|
| S1 | One developer, normal write or sync | Almost always | Nothing new to notice |
| S2 | An outage mid-write or mid-sync, then the same command re-run (a teammate may have pushed meanwhile) | Regularly | Finishes on its own |
| S3 | A crash or Ctrl-C mid-write, then any later command | Occasionally | The same command re-run resets and finishes on its own; any other write stops before changing anything and names `datom_validate(fix = TRUE)`, which resets it (principle 8) |
| S4 | Storage fails after the push | Occasionally | The same command re-run, or `datom_validate(fix = TRUE)`, publishes; any other write stops and names that fix (principle 8) |
| S5 | `datom_init_repo()` interrupted | Occasionally | A re-run finishes |
| S6 | A teammate pushed earlier; this clone is behind | Occasionally | Pulls at the start, on its own |
| S7 | Two developers' work overlaps (a merge conflict, a publish race) | Rarely | Stops before harm with a short message, or reports; the manual step is supported |
| S8 | An older datom, hand edits, files changed in storage by hand, the user's own git operations in the clone | Rare, unsupported | Documented only; never left stuck (principle 7) |

A review finding names its scenario. An S7 finding defaults to "stop with a message" (or a report
from `datom_validate()`), an S8 finding to "document".

## Requirements

### R1. The order of a write

Applies to `datom_write()` (data-frame route) and `datom_write_set()`.

1. The data file is uploaded **after** every refusal check and after change detection, and
   **before** anything in the clone changes. The steps then run in this order:

   | Step | Goes to |
   |---|---|
   | 1. Upload the data file | storage |
   | 2. Write the artifact's metadata, history and manifest row (and `set.json` for a set) | the clone |
   | 3. Commit | the clone's git |
   | 4. Push | the git remote |
   | 5. Upload metadata, history and the version snapshot | storage |
   | 6. Upload the manifest | storage |

2. **A stored data file is never replaced**, on every backend datom supports, including an
   S3-compatible service reached through `endpoint` that may not honour a conditional write.
   - Every backend checks whether the key exists before uploading, so a re-run never resends a
     large file that is already stored.
   - S3: the upload is then also conditional on the key being absent. "Already there" is not an
     error. On a service that ignores the condition, the rule is check, then upload; the race that
     leaves is in R8.
   - Local store: a half-copied file never appears at the final key.
   - The metadata documents and the manifest are still overwritten, as today: they are the current
     pointers.
3. **The hash recorded for the version is always the hash of the bytes in storage.**
   - The clone's history already records a hash for this `data_sha`: record that hash and do not
     upload (today's reuse, unchanged).
   - Otherwise, storage already holds a file for this `data_sha` (an earlier run of this write
     broke after its upload, or a colleague stored the same content): record the stored file's
     hash, not the fresh bytes' hash.
   - Otherwise: upload and record the fresh bytes' hash.

   The stored file's hash in the second case costs a read. On S3 it comes from the SHA-256 that S3
   keeps with the file when datom uploads it with one, which datom does for every data file from
   this release on; for a file stored without one, datom downloads and hashes it. On a local store
   datom hashes the file. Only re-runs and writes of content already stored reach this. The stored
   file's content is not decoded and checked against `data_sha` (R8).
4. A `metadata_only` write (the content is unchanged) carries the current hash forward and uploads
   nothing, as today.
5. A set's `set.json` in the clone always holds the same bytes as its stored payload. When R1.3
   records a stored payload's hash, the clone's `set.json` is written with the stored bytes, not
   with the freshly built ones (several spellings share one `data_sha`).

### R2. Re-running the same command finishes the job

1. After a break at any step of R1, re-running the same command with the same arguments leaves git
   and storage as one uninterrupted run would have, and a reader sees the new version.
2. The command works out what is already done from these marks, and from nothing else:

   | Step done | Its mark |
   |---|---|
   | 1 | the data file is in storage |
   | 2 | the artifact's files in the clone differ from the last commit |
   | 3 | the clone is ahead of the remote |
   | 4 | the clone is level with the remote |
   | 5 | the stored metadata matches the clone's |
   | 6 | the stored manifest matches the clone's |

   Marks 3 and 4 compare against the remote as of the last fetch, so each command fetches once, at
   its start, before any decision that depends on the remote (R3.7). A write's push still pulls
   first, as today.

3. A re-run that finds nothing to write still publishes the manifest if the stored manifest differs
   from the clone's committed one (the break at step 6 above).
4. If a break left an artifact's files in the clone disagreeing with each other (metadata, history,
   manifest row, and `set.json` for a set), they are reset to the last commit before the command
   continues. Only datom's own files are reset.
5. No file outside git and storage records a write's progress (D2).

### R3. A command that finds another artifact's write unfinished

Rewritten 2026-10-31 (owner, design spot-check before task 4a; D3, D14 principle 8). Two kinds of
command, told apart by what they are asked to change:

- **A write** (`datom_write()` with data, `datom_write_set()`, `datom_sync()`) finishes or resets
  only the artifacts it is writing (R2.4, R2.3; for `datom_sync()`, every table it is about to write
  and every `unpushed` row). Before its own work, it checks every other artifact. If any has datom
  files that differ from the last commit, a commit not yet pushed, or a stored manifest row that
  differs from the clone's, it **stops before changing anything**, naming each such artifact, what
  was found, and the fix, `datom_validate(fix = TRUE)` ("or re-run, if a teammate has just written
  it"). Nothing in the clone, git or storage changes.
- **The repair** (`datom_validate(fix = TRUE)` and `datom_write(conn)`, the mirror-everything route)
  applies R3.1 and R3.2 to every artifact. Calling it is the consent.

1. **Never committed** (an artifact's datom files differ from the last commit): the repair resets them
   to the last commit, including that artifact's row in `.datom/manifest.json`. The message names the
   artifact and says to re-run its write. Files datom does not own are never touched, including a
   set write's `include_paths`. A hand edit of a datom-owned file is treated as an unfinished write
   (D13).
2. **Committed but not published** (in unpushed commits, or pushed while storage lacks its metadata
   or manifest row): after the pull in R3.7, the repair pushes it and publishes it from git, and the
   message names it. A write does the same for its own artifact before its own work.
3. Publishing builds storage from git as it is after the pull in R3.7, never from a remembered state,
   so a newer version a colleague pushed in between is what storage ends up holding. A colleague who
   publishes after that pull can be overwritten until the table's next write or
   `datom_validate(fix = TRUE)` republishes, and in the meantime every other write stops and names
   that fix (R3.10 narrows the window); accepted by the owner on 2026-10-28 (design DD4), amended
   2026-10-31.
4. Finding unpublished work costs one read of the stored manifest per command, not one read per
   artifact.
5. `datom_repo_commit()` never commits a datom write that never committed (D9, amended 2026-10-31).
   When the commit would include datom's own uncommitted files (`paths = NULL`, or an explicit path
   naming one), it stops before staging anything, naming the artifact and
   `datom_validate(fix = TRUE)`. A commit whose paths do not include them goes ahead.
6. `datom_repo_push()`, `datom_repo_commit()` (when it pushes), `datom_repo_attach_governance()` and
   `datom_repo_set_data_store()` do not publish (D10). When the commits they push hold a datom
   version, they name each such artifact and say that readers cannot see it until a write of that
   artifact, or `datom_validate(fix = TRUE)`, publishes it (a write of any other artifact stops
   instead, R3). Every version in commits being pushed is
   unpublished by definition, since publishing follows the push, so this needs no storage read.
7. **The clone is brought up to date before anything is published.** At its start, before any
   decision that depends on the remote and before publishing anything, each command in R3 brings
   the clone up to date with the remote by the pull a push already makes: fetch, then merge (only
   when the clone is behind). **No command writes to the git remote or to storage before it has
   pulled** (owner, 2026-10-30). The pull is a step of each command, not of any repair routine:
   removing heal would not remove it. The one exception is `datom_init_repo()`'s first push, to a
   remote that is brand new and empty.
   - A clone that has diverged from the remote is merged, not refused: that is the ordinary state of
     a write whose push broke while a colleague pushed, and today's push merges it. A clone with no
     unpushed commits fast-forwards; a merge happens only when it holds unpushed commits, as today's
     push already does. #105 suggests stopping instead of merging at this point; in practice such a
     merge almost always conflicts on `.datom/manifest.json` (R8), so the two end the same way.
   - A merge conflict stops the command before storage changes, unless R3.8 resolves it.
   - **The pull confirms it caught up** (added 2026-10-31, design spot-check before task 4a). git2r's
     merge silently does nothing when the user's own uncommitted or untracked files are in the way of
     the incoming commits (probed on git2r 0.36.2 and, by the reviewer, 0.33.0). After the merge, the
     clone's last commit must be the remote's tip as just fetched, or descend from it; otherwise the
     command stops before changing anything, says the clone could not be brought up to date because
     local changes are in the way (see `git status`), and gives the way out: `git stash -u`,
     `datom_pull(conn)`, `git stash pop`, resolve anything `git stash pop` reports, then re-run. The
     check is in the pull itself, so `datom_pull()`, the push commands and the migration pull get it.
   - **No upstream branch** (2026-11-03, from a review of `4045fbd`, owner). Today the pull then
     fetches and silently merges nothing, so a clone could sit behind with no sign. The pull stops
     instead, before changing anything, naming
     `git branch --set-upstream-to=origin/<branch>` (the branch filled in). On the project's branch
     this happens only when init's step that sets the upstream failed, which today is a warning;
     init's own first push skips the pull, so it is not affected.
   - If the fetch fails, the command publishes nothing and says why. Whether a write still commits
     locally when offline, as `datom_sync()` allows today (#104), is settled in the design.
   - `datom_sync()` pulls once per call, not once per table.
8. **A conflict only in the manifest is resolved** (D12). When a pull, whether R3.7's or the one
   inside a write's own push, stops on a merge conflict and `.datom/manifest.json` is the only
   conflicted file, datom:
   - starts from the remote's copy of the manifest, which keeps fields no artifact file holds, such
     as `project_name` and any top-level field this build does not know, and rebuilds only the rows
     that disagree with their artifact's files in the merged clone (`metadata.json`,
     `version_history.json`, and `set.json` for a set), adding a row for an artifact the copy lacks
     (simplified 2026-10-30, owner: no comparison with the merge base);
   - before that rebuild writes anything, runs the format check (the forward-compatibility check a
     write runs at its door) on the remote's copy and on every artifact's files in the merged clone
     (added 2026-10-31, owner). The merge may have brought documents from a newer datom, which this
     build must not rewrite. A refusal commits nothing, leaves the merge in progress, and says to
     upgrade datom and re-run, or to drop the merge with `git merge --abort`;
   - completes the merge and carries on, with a message saying the manifest was rebuilt.

   Every refusal of the format check names its evidence, so a wrong inference can be reported as a
   bug: the document, the fields or format number this build cannot read, and the installed datom
   version (owner, 2026-10-31).

   A conflict in any other file, including a `version_history.json` (two people wrote the same
   artifact), stops the command before any publish, as today (from D1 a write's data file may
   already be in storage, unnamed, when the conflict comes at its push).
9. **A merge in progress** (added 2026-10-30, owner, full-spec review of `b76961b`; reworded the
   same day in the simplification pass, and on 2026-10-31 from the review of `058f29b`). Every datom
   command that touches git checks first whether the clone is in the middle of a merge, and never
   resets or rewrites a file while one is in progress without saying so. It tells two kinds apart
   by what is being merged, not by any text or record: a **merge of the remote branch** brings in
   the branch the clone's branch tracks (the commit being merged in is that branch's tip as last
   fetched, or behind it). That is the only merge datom's pull makes, interrupted or not; a user's
   own `git pull` makes the same merge and is treated the same way.
   - **A merge of the remote branch.** While any file other than `.datom/manifest.json` still
     conflicts, it stops before changing anything and says: a merge is in progress, which files
     conflict, and how to finish it. For each conflicted artifact, take the remote copy of all its
     datom files (`git checkout MERGE_HEAD -- <name>/metadata.json <name>/version_history.json`, plus
     `<name>/set.json` for a set; datom fills in the names), resolve your own files and `git add`
     them, then re-run. When only the manifest is left, or nothing, it rebuilds the manifest as in
     R3.8, finishes the merge and says so. The user never edits the manifest or runs `git commit`
     for such a merge.
   - **Any other merge** (of a local branch or another remote, started outside datom). It stops
     before changing anything, names the merge, and gives two ways out: resolve it with git and run
     `datom_pull(conn, finish_merge = TRUE)`, which rebuilds the manifest as in R3.8 and commits the
     merge; or drop it with `git merge --abort`. No datom command commits such a merge unless asked,
     and with nothing in progress `finish_merge` does nothing.
   - Taking the remote's whole manifest by hand is not suggested: its rows for the clone's other
     unpushed writes would stay stale, and nothing would report it.
10. **Publish only what is certain** (added 2026-10-31, owner, design spot-check before task 4a; D14
    principle 8).
    - **A stored version the clone has never seen.** Before publishing an artifact whose stored
      manifest row differs from the clone's, datom checks that the clone's `version_history.json`
      for it contains the version the stored row names (no stored row, or no stored manifest,
      passes). Containment, not "older": a version id hashes content only, so a revert to earlier
      content brings back an id already in the history, and order cannot say which is newer. If the
      clone has never seen the stored version (a teammate published moments ago; or, by hand edits
      of storage or commits removed from GitHub, S8), **a write** stops before changing anything,
      naming the artifact and the way out: re-run (a write pulls first); if it persists,
      `datom_validate(fix = TRUE)`.
    - **The repair overrides that stop** (2026-11-03, from a review of `4045fbd`, owner). Without
      this, such a state locks every write and the repair alike, with no way out (D14 principles 6
      and 7). `datom_validate(fix = TRUE)` and `datom_write(conn)` are the consent: they publish the
      clone's version and say which stored version each replaced. An artifact the stored manifest
      names but the clone does not have at all loses its row, and the repair says so. Writes from a
      branch other than the project's publish branch are a separate rule, with its own issue, that
      ships in the same release (see "Related").
    - **The manifest goes up only when every other row agrees.** Every manifest upload sends the
      clone's whole file, so a write uploads it only when every other artifact's row agrees with the
      stored manifest. Only when the pull inside the write's push brought in new commits does the
      write read the stored manifest again for this (R3.4's one read otherwise covers it). If a row
      disagrees (a teammate's new version whose files are not in storage yet), the write skips the
      manifest upload, says so, and names `datom_validate(fix = TRUE)`; the next write of any other
      artifact stops and names the same fix.

### R4. Syncing files

Applies to `datom_sync_manifest()` and `datom_sync()` on an ordinary repo. A product repo's sync
writes nothing and is unchanged.

1. `datom_sync_manifest()` compares each input file against the manifest **in the last commit**, not
   against the working-tree file.
2. It reports a new status, `unpushed`, for a table whose input file is unchanged against the last
   commit but whose committed version is in commits not yet pushed. It reads the clone only: no
   fetch and no storage read (narrowed 2026-10-31, owner, review of `058f29b`; D4). A table pushed
   but not yet published shows `unchanged`, and R4.4 publishes it.
3. `datom_sync()` treats `unpushed` rows as work: it pushes and publishes them without re-importing
   the file.
4. `datom_sync()` applies R3 before deciding there is nothing to sync. Its own artifacts (R3, a
   write) are every table in the preview it is given, so a table in the preview that was pushed but
   not published is published; unfinished work on a table outside the preview stops it.
5. `?datom_sync_manifest` defines "published" where it lists the statuses, and says that `unpushed`
   looks at the clone only: a table pushed but not yet published shows `unchanged` until the next
   `datom_sync()` or write publishes it.

### R5. The repair: `datom_validate(fix = TRUE)`

1. It applies R3.1 first: files that were never committed are reset, never published.
2. It pulls (R3.7), pushes any unpushed commits, then publishes every artifact from git (D6). A
   merge conflict that R3.8 does not resolve stops the repair before storage changes, and so does a
   failed fetch.
3. It reports what it did for each artifact.
4. The route of `datom_write()` that mirrors everything (no `data`, no `name`) shares this routine
   and behaves the same.
5. `datom_validate(fix = FALSE)` is unchanged except for one new status (amended with the owner on
   2026-10-28; rewritten 2026-10-30 in the simplification pass, because the first version's
   comparison against the clone's last commit needed a fetch, a skip for a behind clone and a
   like-for-like rule, for a race that corrects itself):
   - It reports `manifest_mismatch_s3` for an artifact whose row in the stored manifest names a
     different version from the one recorded for the stored `metadata.json`
     (`.datom_recorded_current_version()` on the stored `metadata.json` and history, the lookup
     `datom_read()` uses). This catches two publishes crossing (design DD4) and a write broken just
     before its manifest upload; either side may be the stale one.
   - The report names the fix: `datom_validate(fix = TRUE)`, or the table's next write.
   - It reads storage only: no fetch and no git read, so a behind clone needs no special case. The
     recorded version, not a recomputed one, keeps a hand edit published by 0.2.0 (whose document no
     record names) from being reported for good.
   - It runs in `datom_validate()` only; no read and no write pays for it.

### R6. `datom_init_repo()` re-run

1. A re-run in a folder that already holds `.datom/project.yaml` finishes the job (uploads the
   manifest and succeeds) only when all of these hold:
   - the folder's `project.yaml` names the same project and the same data storage as the call;
   - the remote holds the folder's initial commit;
   - storage holds no manifest for the project.
2. Any other existing folder refuses exactly as today.
3. A break before the push is rolled back, as today.

### R7. Tests

1. Each command in R1-R6 has a test that breaks it at each of its steps, re-runs the same command,
   and checks what a reader sees: the new version reads, and the stored manifest names it.
2. The cases of R3 are tested with a second artifact, for a break before and after the commit: a
   write of another artifact stops, changing nothing in the clone, git or storage, and names the
   artifact and the fix; `datom_validate(fix = TRUE)` then resets or publishes it. They include a set
   write with `include_paths`, whose files must not be committed by the other command, and a
   `datom_repo_commit()` with and without `paths` (R3.5). R3.6 is tested with
   `datom_repo_push()`: the message names the artifact, storage is unchanged, and a write of that
   artifact, or `datom_validate(fix = TRUE)`, publishes it.
3. R1.2 is tested for both backends, including a stored file that must survive a second upload with
   different bytes.
4. Every new guard's test goes red when that guard alone is removed (conventions item 2a), probed
   once and recorded in the commit message.
5. No test uses AWS or GitHub: folder remotes, local storage, and a mocked S3 client.
6. R3.7 is tested with two clones of one project: when the second clone is behind, its repair and
   its writes leave storage holding the first clone's newer version; a merge conflict and a failed
   fetch each leave storage unchanged. (A scan clause was dropped on 2026-10-31: a scan that reads
   only the clone cannot report a colleague's newer version, R4.2.) The same with a modified, a
   staged and an untracked file of the user's in the way of the incoming commits, with and without
   commits of the second clone's own: a write and `datom_pull()` each stop, changing nothing
   (added 2026-10-31).
7. R3.8 is tested with two clones writing different tables without a pull in between, and with a
   write whose push broke while the other clone pushed: the re-run finishes, the rebuilt manifest
   names both tables, and the stored manifest matches it. Two clones writing the **same** table
   still stop on the conflict in its `version_history.json`, with storage unchanged.
8. R5.5's new status is tested (rewritten 2026-10-30 with R5.5): `datom_validate()` reports
   `manifest_mismatch_s3`, naming the fix, for an artifact whose stored manifest row and stored
   `metadata.json` name different versions (a crossed publish, and a write broken before its manifest
   upload), and `datom_validate(fix = TRUE)` clears it. It is not reported for a hand edit published
   by 0.2.0, nor on a consistent store.

### R8. Residual failure modes

Recorded in `design.md` and, at spec completion, in `dev/engineering-notes.md`. Each is **guarded**
(a test goes red if it returns) and/or **documented** (in user-facing help, with what the user sees
and what to do).

| Failure mode | What the user sees | Guarded / documented |
|---|---|---|
| A write broke before its commit, leaving its data file in storage with no version naming it | Nothing; the file costs space. For sensitive data, the bytes are in the bucket although no version exists | Documented in `?datom_write` |
| A project a released datom already broke (#155 before this fix) | A re-run or the repair can still leave its readers failing | Documented in `NEWS.md` (one line) |
| A push rejected by a merge conflict (#105) | The command stops before any publish: no version is published, though the write's data file may already be in storage, unnamed (D1). Every write rewrites `.datom/manifest.json`'s `updated_at` and `summary` lines (`.datom_update_manifest_entry()`), so two writes from different clones conflict there even when they touch different tables (`two_writers_probe.R`, 2026-10-28). R3.7's pull at the start makes this rarer, because a write then commits on top of the remote. It stays likely after a broken push while a colleague pushed. A conflict only in the manifest is now resolved by datom (R3.8). What still stops the command: a conflict in a `version_history.json` (two people wrote the same artifact) or in the user's own files. Until #105's recovery command exists, the user follows the conflict message, which every later datom command repeats until the conflict is resolved (R3.9): for each conflicted artifact, take the remote copy of all its datom files (`git checkout MERGE_HEAD -- ...`, names filled in), resolve their own files and `git add` them, and re-run; datom then rebuilds the manifest and finishes the merge. A merge started outside datom, of anything but the remote branch, is never finished unasked: every command stops, and `datom_pull(conn, finish_merge = TRUE)` or `git merge --abort` ends it (R3.9) | Guarded by existing tests, by R7.7 for what R3.8 resolves and what it leaves, and by the merge check's tests |
| Two R sessions writing through one clone at the same time | Not supported, as today | Documented |
| An S3-compatible service that rejects `IfNoneMatch` or `ChecksumSHA256` outright (400 or 501), added 2026-10-28 from the review of `tasks.md` | Every write stops at its first step, the data file upload, with the service's own error; nothing in the clone, git or storage changes. No fallback until a user needs one. paws alone can trigger this: from `paws.common` 0.9.0, every upload carries a checksum by default, datom's metadata uploads included, so such a service can fail even without datom's new arguments | Documented, beside `endpoint` in `?datom_get_conn` |
| On an S3-compatible service that ignores conditional writes, two writers store the same new content at the same moment with different bytes (different arrow versions) | Both see the key absent and upload; the second file replaces the first. One of the two versions records a hash the stored file no longer has, so reading it is refused by the hash check. Loud, not silent | Documented, beside `endpoint` in `?datom_get_conn` |
| A file put at a data address by hand, or corrupted in storage, is adopted by a re-run (R1.3, second case) | The re-run records that file's hash, so reads return its content without complaint. No datom write produces such a file. A decode-and-compare check was declined on 2026-10-28: it costs a full download and decode on every re-run that reaches R1.3's second case | Documented in `dev/engineering-notes.md`; not checked |
| A teammate still on a released datom writes to the repo after others upgrade, and a write of theirs breaks after its push (D11) | An upgraded teammate's next write publishes that version without its data file, and its readers fail | Documented in `NEWS.md`: upgrade everyone who writes to a repo together. Not guarded (owner, 2026-10-28: does not happen in practice) |

### R9. Documentation

1. `.github/copilot-instructions.md` gains this section, in the spec's last task:

   ```
   ## Commands that change state: a re-run finishes the job

   - Order: the data file first (never overwriting a stored one), then the clone's
     files, commit, push, then metadata and manifest to storage. A version exists once
     GitHub has it; it is published once its metadata and manifest are in storage.
   - No state of its own: a command works out how far an earlier run got from git and
     storage, never from a separate record.
   - Unfinished work found before its commit is reset; found after it, finished. A
     write does this only for what it is writing; another artifact's unfinished work
     stops it with a message naming datom_validate(fix = TRUE), which does it for all.
   - Act only when certain: a check that is unsure stops the command with a way out.
   - Every step is safe to repeat, and every refusal check runs before the first step.
   - Each such command has a test that breaks it at each step, re-runs it, and checks
     what a reader sees.
   - datom's own files (an artifact's metadata.json, version_history.json and set.json,
     and .datom/manifest.json) are written only by datom commands. A hand edit is not
     supported: the next command treats it as an unfinished write and resets it.
   ```

2. `dev/datom_specification.md`: "Write Ordering & Resilience" is rewritten (its claims that re-runs
   are idempotent and re-uploads safe were false); the reuse bullet under `datom_write()` and the
   deferred "Integrity state tracking" entry are updated with the reason it was decided against.
3. The datom-sets spec's invariant I5 ("a set write that fails at git leaves no orphaned payload")
   is superseded by D1. Recorded in `dev/datom_specification.md`, with a one-line note beside I5 in
   `.kiro/specs/datom-sets/design.md` so a reader of that spec is not misled.
4. Docstrings that state the old order are corrected, among them `.datom_commit_and_mirror()`,
   `.datom_resolve_parquet_sha()`, `.datom_push_metadata_s3()`, `.datom_restore_set_payload()` and
   the ordering comment in `.datom_sync_metadata()`.
5. User-facing help: `?datom_write` and `?datom_write_set` (the order, a re-run finishes, R8's
   leftover file, a conflict only in the manifest is resolved by datom, and: commit your own files
   with `datom_repo_commit()`, because a plain `git commit` can capture a datom write halfway
   through), `?datom_sync_manifest` (the new status `unpushed`,
   "published", and that a table pushed but not yet published shows `unchanged`), `?datom_pull`
   (`finish_merge`, for a merge datom did not start, R3.9), `?datom_validate` (the repair pushes; the new status `manifest_mismatch_s3`), `?datom_init_repo` (a re-run finishes),
   `?datom_write`'s `data = NULL` with `name` route (it publishes what is committed for that table;
   hand edits of datom's files are not supported and are reset; custom metadata is changed with
   `datom_write(conn, data, name, metadata = )`, D13),
   `?datom_repo_commit` (it stops rather than commit a datom write that never committed, naming
   `datom_validate(fix = TRUE)`), the stop a write gives on another artifact's unfinished work (in
   `?datom_write`, `?datom_write_set` and `?datom_sync`), and the four commands of
   R3.6 (they push a datom write's commit without publishing it, and say so).
6. `NEWS.md`: the behaviour changes, upgrade-relevant first (the repair now pushes; hand edits of
   datom's own files are no longer committed by `datom_write(conn, name =)` but reset, with the
   supported way to change custom metadata (D13); a write stops on another artifact's unfinished
   work and names `datom_validate(fix = TRUE)`; the new scan status `unpushed`; a merge datom did
   not start stops every command until `datom_pull(conn, finish_merge = TRUE)`; upgrade everyone who writes
   to a repo together), and R8's line on projects already affected.
7. `dev/datom_specification.md`'s table of `datom_write()` routes: the `data = NULL` with `name`
   row no longer says "after editing dispatch.json"; it says the route publishes what is committed
   for one table, and that datom's own files are not hand-edited (D13).

## Out of scope

- Rescuing states a released datom already created (D7).
- A command to recover from a push rejected by a merge conflict (#105), beyond the conflict only in
  the manifest that R3.8 resolves.
- A command to delete data files no version names.
- datom-py: what readers see does not change, so no shared reader case changes.
- Publishing from `datom_repo_push()`, `datom_repo_commit()`, `datom_repo_attach_governance()` or
  `datom_repo_set_data_store()` (D10); they only report what they pushed (R3.6).

## Open questions

None open. Q1 (committing your own files while a datom write is unfinished) was settled as D9, Q2
(commands that push an unpublished datom write) as D10, and Q3 (below, kept for the record) as D11,
all on 2026-10-28.

- **Q3 (settled as D11). Teammates still on a released datom.** A teammate on 0.2.0 still commits and pushes before
  uploading, so a break on their side leaves a pushed version with no data file. After this spec,
  an upgraded teammate turns that into damage in two ways:
  - R1.3's first case reuses the hash from the clone's history for the same content, uploads
    nothing, and publishes a version whose data file is missing;
  - R3.2 publishes the 0.2.0 teammate's committed version during a write of **any** table, so an
    unrelated write turns a readable project unreadable.

  Should repos guard against older writers with the existing `min_writer_version` field in
  `.datom/project.yaml`? The review that raised this recommends that `datom_init_repo()` set it for
  new repos and that `NEWS.md` tell owners of existing repos to add it. Setting it only at init
  leaves every existing repo unguarded until its owner acts, so other routes are compared when Q3
  is taken.

## Related

- **#134 part 3b** (`spec/s3-credential-function`, paused, design drafted) waits for this spec. Under
  D1 an expired single sign-on login fails at the first step, the data file upload, before the clone
  changes, so its requirement R4a.1 (check the keys before any local file write) may simplify.
- **#105**: a write rejected at the push. Unchanged here.
- **The publish-branch rule** ([#156](https://github.com/amashadihossein/datom/issues/156), owner, 2026-11-03): only the project's publish
  branch, recorded at init, writes to storage. Ships in the same release as this spec. This spec
  does not depend on it: with the repair overriding R3.10's stop, no state locks the project
  whichever lands first.
