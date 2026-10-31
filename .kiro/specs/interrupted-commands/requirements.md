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
| D3 | **The commit is the line.** A command that finds another artifact's write unfinished resets that artifact's files if the write never committed, and publishes it from git if it did. It says which in either case | Refuse until the user finishes it (one break stops a whole sync); commit the unfinished files (can publish a write the user stopped on purpose) |
| D4 | **A new scan status, `unpublished`**, for a table whose committed version readers cannot see yet. "Published" is defined in the help | Keep `unchanged` and print a line (misleads a script that checks `all(status == "unchanged")`) |
| D5 | **`datom_init_repo()` is in scope.** A re-run in a half-initialised folder finishes instead of refusing, under narrow conditions | Leave it refusing and pointing at the repair |
| D6 | **`datom_validate(fix = TRUE)` pushes** unpushed commits, then publishes | Publish only what GitHub has and name `datom_repo_push()` for the rest |
| D7 | **No rescue for states a released datom already created.** datom is experimental; the fix is designed for what new writes can produce. D11 extends this to teammates still writing with a released datom | Storage checks before every skip, correcting a version's recorded hash after an arrow upgrade, flagging sets that pin a version with no data file, restoring a set payload from an older commit |
| D8 | **The rule is written into `.github/copilot-instructions.md`** (wording in R9), with the detail in `dev/datom_specification.md` | Specification and engineering notes only (loaded on demand, so a session editing a write might not see it) |
| D9 | **`datom_repo_commit()` resets a datom write that never committed** before it stages anything, as every other command does (D3). A plain `git commit` from a terminal is outside datom's reach and is discouraged in the help | Leave datom's files out of the commit (the clone stays unclean after an add-everything commit); refuse until the datom write is dealt with |
| D10 | **The git and config commands push, and say so.** `datom_repo_push()`, `datom_repo_commit()`, `datom_repo_attach_governance()` and `datom_repo_set_data_store()` do not publish a datom write whose commit they push; they name it and say the next datom write or `datom_validate(fix = TRUE)` publishes it | Publish what they push (commands about git or config start writing to storage, and after a data-store change "which storage" has two answers); refuse to push (blocks a product layer's commit) |
| D11 | **Teams writing one repo with mixed datom versions are not guarded against** (Q3). In practice everyone writing to a repo upgrades together. Recorded in R8 | Set `min_writer_version` at init for new repos and ask existing owners to add it; check for the data file before publishing any version |
| D12 | **datom resolves a merge conflict confined to `.datom/manifest.json`** by rebuilding the manifest from the artifacts' files in the merged clone, completing the merge, and saying so (R3.8). The manifest is derived, so nothing can be lost. Conflicts in any other file stop the command as today and stay with #105 | Leave every conflict to #105: a write whose push broke while a colleague pushed would not finish on a re-run, the main conflict R3.7 leaves |
| D13 | **Hand edits of datom's own files are not supported** (owner, 2026-10-28, third review of `tasks.md`). An artifact's `metadata.json`, `version_history.json` and `set.json`, and `.datom/manifest.json`, are written only by datom commands. An uncommitted change to one of them is treated as an unfinished write, whoever made it: the next datom command resets it and warns (R3.1). So the metadata-only route, `datom_write(conn, name =)`, no longer commits a hand edit; it publishes what is committed for that table. To change custom metadata, use `datom_write(conn, data, name, metadata = )`, which records a metadata-only version with its history entry and manifest row. Until now the route committed a hand-edited `metadata.json`, but only half-recorded it (no history entry, no manifest row), and its documented purpose, editing `dispatch.json`, left with the governance layer | Exempt the named table from the reset on that route: it protected a use with no documented purpose, and after a write broken before its commit it would commit that write's half-finished files as if they were an edit, leaving `datom_read()` and `datom_list()` naming different versions |

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

Applies, before their own work, to `datom_write()` (every route), `datom_write_set()`,
`datom_sync()` and `datom_validate(fix = TRUE)`.

1. **Never committed** (an artifact's datom files differ from the last commit): they are reset to the
   last commit, including that artifact's row in `.datom/manifest.json`. The message names the
   artifact and says to re-run its write. Files datom does not own are never touched, including a
   set write's `include_paths`. This applies on every route, the metadata-only route
   `datom_write(conn, name =)` included: a hand edit of a datom-owned file is treated as an
   unfinished write and reset (D13).
2. **Committed but not published** (in unpushed commits, or pushed while storage lacks its metadata
   or manifest row): after the pull in R3.7, it is pushed and then published from git, and the
   message names it.
3. Publishing builds storage from git as it is after the pull in R3.7, never from a remembered state,
   so a newer version a colleague pushed in between is what storage ends up holding. A colleague who
   publishes after that pull can be overwritten until the next datom command in an up-to-date clone
   republishes; accepted by the owner on 2026-10-28 (design DD4).
4. Finding unpublished work costs one read of the stored manifest per command, not one read per
   artifact.
5. `datom_repo_commit()` applies R3.1 before it stages anything (D9), so a commit of the caller's
   own files never carries a datom write that never committed. This holds with `paths = NULL`
   (stage everything) and with explicit `paths`.
6. `datom_repo_push()`, `datom_repo_commit()` (when it pushes), `datom_repo_attach_governance()` and
   `datom_repo_set_data_store()` do not publish (D10). When the commits they push hold a datom
   version, they name each such artifact and say that readers cannot see it until the next datom
   write or `datom_validate(fix = TRUE)` publishes it. Every version in commits being pushed is
   unpublished by definition, since publishing follows the push, so this needs no storage read.
7. **The clone is brought up to date before anything is published.** At its start, before any
   decision that depends on the remote and before publishing anything, each command in R3 brings
   the clone up to date with the remote by the pull a push already makes: fetch, then merge.
   - A clone that has diverged from the remote is merged, not refused: that is the ordinary state of
     a write whose push broke while a colleague pushed, and today's push merges it. A clone with no
     unpushed commits fast-forwards; a merge happens only when it holds unpushed commits, as today's
     push already does. #105 suggests stopping instead of merging at this point; in practice such a
     merge almost always conflicts on `.datom/manifest.json` (R8), so the two end the same way.
   - A merge conflict stops the command before storage changes, unless R3.8 resolves it.
   - If the fetch fails, the command publishes nothing and says why. Whether a write still commits
     locally when offline, as `datom_sync()` allows today (#104), is settled in the design.
   - `datom_sync()` pulls once per call, not once per table.
8. **A conflict only in the manifest is resolved** (D12). When a pull, whether R3.7's or the one
   inside a write's own push, stops on a merge conflict and `.datom/manifest.json` is the only
   conflicted file, datom:
   - rebuilds the manifest from the artifacts' files in the merged clone (`metadata.json`,
     `version_history.json`, and `set.json` for a set), taking fields no artifact file holds, such
     as `project_name` and any top-level field this build does not know, from the remote's copy;
   - completes the merge and carries on, with a message saying the manifest was rebuilt.

   A conflict in any other file, including a `version_history.json` (two people wrote the same
   artifact), stops the command before storage changes, as today.

### R4. Syncing files

Applies to `datom_sync_manifest()` and `datom_sync()` on an ordinary repo. A product repo's sync
writes nothing and is unchanged.

1. `datom_sync_manifest()` compares each input file against the manifest **in the last commit**, not
   against the working-tree file.
2. It reports a new status, `unpublished`, for a table whose input file is unchanged against the last
   commit but whose committed version is not published. When storage cannot be reached, it still
   reports tables with unpushed commits and warns that it could not check storage.
   - The scan fetches first. A table whose stored version is newer than the clone's (a colleague
     published after the clone's last pull) is **not** `unpublished`; the scan says the clone is
     behind and names `datom_pull()`.
3. `datom_sync()` treats `unpublished` rows as work: it pushes and publishes them without
   re-importing the file.
4. `datom_sync()` applies R3 before deciding there is nothing to sync.
5. `?datom_sync_manifest` defines "published" where it lists the statuses.

### R5. The repair: `datom_validate(fix = TRUE)`

1. It applies R3.1 first: files that were never committed are reset, never published.
2. It pulls (R3.7), pushes any unpushed commits, then publishes every artifact from git (D6). A
   merge conflict that R3.8 does not resolve stops the repair before storage changes, and so does a
   failed fetch.
3. It reports what it did for each artifact.
4. The route of `datom_write()` that mirrors everything (no `data`, no `name`) shares this routine
   and behaves the same.
5. `datom_validate(fix = FALSE)` is unchanged except for one new status and the fetch it needs
   (amended with the owner on 2026-10-28):
   - It reports `metadata_stale_s3` for an artifact whose stored `metadata.json` holds a different
     version from the one in the clone's last commit. This catches a stored current version left
     behind git, which nothing else reports (design section 12). The last commit, not the working
     tree, because a write that broke before its commit leaves a working-tree version that was
     never committed; that is an unfinished write, not stale storage.
   - It fetches first, without merging, so it still changes nothing. When the clone is behind the
     remote, it skips this comparison and says to run `datom_pull()`, because a colleague's newer
     stored version would otherwise be reported as stale. When the fetch fails, it warns and skips
     the comparison, as the scan does (R4.2).
   - With `fix = TRUE`, heal pulls first, so the comparison runs on a current clone.

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
2. The cases of R3 are tested with a second artifact, for a break before and after the commit, and
   include a set write with `include_paths`, whose files must not be committed by the other command,
   and a `datom_repo_commit()` with and without `paths` (R3.5). R3.6 is tested with
   `datom_repo_push()`: the message names the artifact, storage is unchanged, and the next datom
   write publishes it.
3. R1.2 is tested for both backends, including a stored file that must survive a second upload with
   different bytes.
4. Every new guard's test goes red when that guard alone is removed (conventions item 2a), probed
   once and recorded in the commit message.
5. No test uses AWS or GitHub: folder remotes, local storage, and a mocked S3 client.
6. R3.7 is tested with two clones of one project: when the second clone is behind, its repair and
   its writes leave storage holding the first clone's newer version; a merge conflict and a failed
   fetch each leave storage unchanged; the scan in the behind clone does not report the newer
   version as `unpublished`.
7. R3.8 is tested with two clones writing different tables without a pull in between, and with a
   write whose push broke while the other clone pushed: the re-run finishes, the rebuilt manifest
   names both tables, and the stored manifest matches it. Two clones writing the **same** table
   still stop on the conflict in its `version_history.json`, with storage unchanged.
8. R5.5's new status is tested: `datom_validate()` reports `metadata_stale_s3` for an artifact whose
   stored `metadata.json` holds an older version than the one in the clone's last commit, and
   `datom_validate(fix = TRUE)` clears it. It is not reported on a clone that is only behind the
   remote, nor for a write that broke before its commit; a failed fetch skips the comparison with a
   warning.

### R8. Residual failure modes

Recorded in `design.md` and, at spec completion, in `dev/engineering-notes.md`. Each is **guarded**
(a test goes red if it returns) and/or **documented** (in user-facing help, with what the user sees
and what to do).

| Failure mode | What the user sees | Guarded / documented |
|---|---|---|
| A write broke before its commit, leaving its data file in storage with no version naming it | Nothing; the file costs space. For sensitive data, the bytes are in the bucket although no version exists | Documented in `?datom_write` |
| A project a released datom already broke (#155 before this fix) | A re-run or the repair can still leave its readers failing | Documented in `NEWS.md` (one line) |
| A push rejected by a merge conflict (#105) | The command stops before storage changes, as today. Every write rewrites `.datom/manifest.json`'s `updated_at` and `summary` lines (`.datom_update_manifest_entry()`), so two writes from different clones conflict there even when they touch different tables (`two_writers_probe.R`, 2026-10-28). R3.7's pull at the start makes this rarer, because a write then commits on top of the remote. It stays likely after a broken push while a colleague pushed. A conflict only in the manifest is now resolved by datom (R3.8). What still stops the command: a conflict in a `version_history.json` (two people wrote the same artifact) or in the user's own files. Until #105's recovery command exists, the user follows the conflict message: keep the remote copy of datom's files and re-run | Guarded by existing tests, and by R7.7 for what R3.8 resolves and what it leaves |
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
   - Unfinished work found before its commit is reset; found after it, finished. Any
     command may do either, and says so.
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
   through), `?datom_sync_manifest` (the new status,
   "published"), `?datom_validate` (the repair pushes; the new status `metadata_stale_s3`), `?datom_init_repo` (a re-run finishes),
   `?datom_write`'s `data = NULL` with `name` route (it publishes what is committed for that table;
   hand edits of datom's files are not supported and are reset; custom metadata is changed with
   `datom_write(conn, data, name, metadata = )`, D13),
   `?datom_repo_commit` (it resets a datom write that never committed), and the four commands of
   R3.6 (they push a datom write's commit without publishing it, and say so).
6. `NEWS.md`: the behaviour changes, upgrade-relevant first (the repair now pushes; hand edits of
   datom's own files are no longer committed by `datom_write(conn, name =)` but reset, with the
   supported way to change custom metadata (D13); the new scan status; upgrade everyone who writes
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
