# Design -- interrupted commands finish on a re-run

**Status**: **Approved by the owner on 2026-10-28.** Requirements approved the same day
(`requirements.md`). Design decisions DD1-DD4 are in section 9. The routine and its file were named
`heal` by the owner on 2026-10-28 (first drafted as "settle" in `R/finish.R`).

Reviews by another agent, evaluated with the owner on 2026-10-28, added: the hard-link upload on a
local store and the whole-file condition on S3's stored checksum (section 3); recognisable temporary
names on a local store, skipped by storage copy and verify (section 3); and the `metadata_stale_s3`
status in `datom_validate()` (section 6; requirements R5.5 and R7.8 amended), since replaced by
`manifest_mismatch_s3`. **Simplification pass, 2026-10-30**, set by the owner (requirements D14):
the merge check and the pull are owned by each command, not heal; heal's reset and publish run only
when their own check finds something; the manifest rebuild compares rows with artifact files, not a
merge base; heal loses its `touch` argument and the check of its publish list; snapshots are keyed
by the document's own version; the stale check reads storage only (sections 1, 2, 4, 5, 6, 11, 12). A check before every
publish was also added, then dropped by the owner after weighing what the current version is for
(DD4). The review of `tasks.md` the same day added: which checks run before heal (section 1); the
wording of heal's reset messages and several names in its `artifact` argument (section 4); the 409
response and services that reject the new headers (section 3, section 12); the pull inside
`datom_get_conn()` under DD2; and the real-S3 check moved to task 1 (section 10). A second review of
`tasks.md` the same day placed heal in exactly one place per route (section 4), added the declared
minimum paws versions to the real-S3 check (section 10), and noted that paws' default checksum can
trigger the rejected-headers case on its own (sections 3 and 12). A third review the same day led
to requirements D13: hand edits of datom's own files are not supported, so the metadata-only route
passes no `artifact` to heal and no longer commits a hand edit (sections 2, 4 and 12).
**Review of `058f29b`, 2026-10-31**, by another agent, evaluated with the owner (requirements D14,
seventh principle added): the merge check decides by what is being merged, finishing a merge of the
remote branch as before and stopping on any other until `datom_pull(conn, finish_merge = TRUE)`
(sections 1, 2 and 4); the manifest rebuild runs the format check before it writes (section 5); the
scan reads the clone only, with the status `unpushed` (section 7); probe in section 10.
**Design spot-check before task 4a, 2026-10-31** (covering tasks 4a and 4b; evaluated with the owner,
with a review of it by another agent; requirements D14 principle 8): heal acts only when certain, so
**a write heals only the artifact it is writing** and stops on any other artifact's unfinished work,
naming `datom_validate(fix = TRUE)` (sections 1, 2, 4, 7, 9 DD4, 11, 12); the pull confirms it caught
up, decided by commit containment (sections 1, 4, 10); heal's publish stops when storage names a
version the clone has never seen; the manifest goes up only when every other row agrees with
storage; the writer floor is read from the clone's `project.yaml` on every write (section 2).
**Review of `4045fbd`, 2026-11-03**, by another agent, evaluated with the owner: the "version never
seen" stop binds writes only and the repair overrides it (section 4, step d; it could lock every
write and the repair); the branch case moves to the publish-branch rule's own issue; the pull stops
on a clone with no upstream (step b), withdrawn on 2026-11-04; DD4's revert sentence narrowed (section 9).
**Review of `d616e98`, 2026-11-04**, by another agent, evaluated with the owner: no stop for a
branch with no upstream, and a rejected push names the clone being behind (step b); a stored row for
an artifact the clone lacks counts as differing (step d, "The manifest upload"); the metadata-only
route stops on uncommitted edits of its table (section 4's route table).
**Read first**: `requirements.md` (terms, findings, decisions D1-D14, requirements R1-R9). This
document says how: which functions change, in which files, and how each command runs.

## 1. The shape in one picture

Every command that changes things starts the same way: a check for a merge in progress, then heal's
reset, then a pull, then heal's publish, and then does its own work in the new order. **Heal** is
datom's self-healing step: it is where "a re-run finishes" lives, and where "another command finds
unfinished work" is detected, so there is one implementation of them, not one per command. **Heal
acts only when certain** (requirements D14 principle 8, 2026-10-31): a write heals only the
artifacts it is writing, and on any other artifact's unfinished work it stops the command before
anything changes, naming `datom_validate(fix = TRUE)`; the repair heals every artifact. The merge
check and the pull are not part of heal (section 4).

```
command(conn, ...)
  every refusal check that needs no storage state heal can change      (see below)
  merge check (every git-touching command)                            R3.9
    a merge in progress, not of the remote branch -> stop; finish_merge = TRUE or git merge --abort
    of the remote branch, a file other than the manifest conflicted -> stop, say how to finish
    of the remote branch, only the manifest left, or nothing -> rebuild it (section 5), finish, say so
  heal, reset   (only if git status shows uncommitted datom files)    R2.4, R3.1
    the command's own artifact -> reset it; any other artifact -> stop, name the repair
  pull, owned by the command, not by heal                             R3.7, R3.8
    fetch; merge only if behind (a conflict only in the manifest -> rebuild it, section 5)
    then confirm it caught up: HEAD contains the fetched tip, else stop (git stash -u recipe)
    after a merge (a fast-forward counts): the forward-compat check on every artifact
    (every rebuild, here or in the merge check, runs that check first, before it writes)
  heal, publish (only if the clone is ahead, or a stored manifest row differs from it)   R3.2-R3.4
    another artifact pending (unpushed commit, row differs) -> stop, name the repair
    a stored version the clone's history lacks -> stop                R3.10
    push unpushed commits, then publish the own artifact, manifest last
  change detection, and the table-or-set check
  own work, new order (a write):
    1. data file -> storage, only if absent     R1.1-R1.3
    2. clone files                              (metadata, history, manifest row, set.json)
    3. commit
    4. push (pulls first, as today; R3.8 applies)
    5. snapshot, history, then metadata.json -> storage   (metadata.json last)
    6. manifest -> storage                      (always last; only if every other row
                                                 agrees with storage, R3.10)

  every publish (heal's, a write's 5-6, the repair) goes through one function,
  .datom_publish_artifacts()
```

**The common path changes nothing before the command's own work** (D14; simplification pass, owner,
2026-10-30). On a clean, current, fully published clone, the merge check finds no `.git/MERGE_HEAD`,
git status finds no uncommitted datom file, the fetch finds the clone level with the remote, and the
one read of the stored manifest finds no row that differs, so the reset, the merge, the re-check and
the publish never run. What that path pays is reads: one fetch, one `git status`, one small storage read.
**The pull and the merge check do not depend on heal**: each command calls them, so removing heal
would leave both in place. The order is fixed by one constraint: uncommitted datom files left by a
crash make git refuse a merge that touches them, so heal's reset runs before the pull.

**Invariant this rests on: the manifest is always published last.** Every route that writes storage
publishes an artifact's documents first and the manifest after. So a stored manifest row that matches
git means that artifact's documents are current too, and heal can find all unpublished work with one
read of the stored manifest (R3.4). Today `.datom_sync_data_metadata()` writes the manifest **first**;
that order is reversed (section 6). One ordering of two publishes landing at once breaks this
invariant; it is a row of section 12. A second way was found in the design spot-check before task
4a: every manifest upload sends the clone's whole file, so a write whose push merged in a teammate's
commit would name the teammate's new version before the teammate's own upload had stored its
documents. Hence a write uploads the manifest only when every other row agrees with storage
(requirements R3.10; section 4, "The manifest upload"). Within an artifact's documents, `metadata.json` goes last for
the same reason: change detection reads it as the mark that step 5 is done, so a break before it
lands leaves the re-run seeing a change and publishing all three again, where a break after an early
`metadata.json` would make the re-run report "none" and publish nothing more (design spot-check
before task 2, owner, 2026-10-30).

**What runs before heal, and what after** (from the review of `tasks.md`, owner, 2026-10-28). Heal can
reset files, merge, push and publish, so a mistyped argument must be refused before it runs (R9.1:
every refusal check runs before the first step).

| Before heal | After heal, and why |
|---|---|
| Argument checks: connection, role, clone path, name, the data frame, parents and lineage. For a set: the product-repo checks (`.datom_check_set_write_gates()`, `.datom_check_set_project()`), `include_paths`, the payload checks, `.datom_check_set_parents()` | Change detection (`.datom_has_changes()`): it reads the stored metadata, which heal may just have published; run first, it can call a write "full" for a version heal then publishes |
| The format and version compatibility check on the clone's files (`.datom_check_write_entry()`), re-run inside heal after its pull | The table-or-set check (`.datom_check_artifact_kind()`): it reads the same stored document, and heal's pull can bring a colleague's set of the same name |
| The data-location check (`.datom_check_ref_current()`); heal does not change it | |
| Hashing the data and writing the parquet to a temporary file: local only, and unhashable data is refused here | |
| The confirmation prompt of `datom_write(conn)`, the mirror-everything route; otherwise answering "no" would still push and publish | |

The two checks after heal refuse after heal has acted. That is accepted: heal only finishes work that
was already committed, or resets work that never committed, on the artifact the command is writing,
as a re-run of it would, so a refusal there undoes nothing. `datom_sync()` follows the same rule: the preview's columns and the `rio`
package are checked before its one heal; a file that fails to import is an error on that row only.

## 2. Functions, by file

The interruption logic lives in one new file, `R/heal.R`, so the code that repairs what an interrupted
command left behind has one home and can be read and extended in one place. Two kinds of change sit
elsewhere, on purpose: the storage primitives (upload only if absent, the stored file's hash) live with
their backend peers, because datom keeps each backend's code together behind one dispatch layer; and
each command gains a call to `.datom_heal()` in its own file, plus the reordered steps inside the two
write commands.

| File | Function | New / changed | Role |
|---|---|---|---|
| `R/heal.R` | `.datom_heal(conn, artifact = NULL, all = FALSE)` | new | Steps a and d of section 4, the reset and the publish, each run only when its own check finds something. `artifact` names the artifacts the command is writing (several for `datom_sync()`); heal acts on those only, and stops the command, before changing anything, on any other artifact's unfinished work, naming `datom_validate(fix = TRUE)`. The repair passes `all = TRUE` (argument name settled in task 4a) and heal acts on every artifact. Returns what it reset and what it published, for the caller's messages |
| `R/heal.R` | the merge check (named in task 4a) | new | Step 0 of section 4, independent of heal. For a merge of the remote branch: stops while a file other than the manifest conflicts, and otherwise rebuilds the manifest and finishes the merge. Any other merge: stops, changing nothing, unless `datom_pull(conn, finish_merge = TRUE)` asked it to finish. Called at the start of `.datom_git_pull()`, by heal before its reset, and by `datom_repo_commit()` before it stages anything |
| `R/heal.R` | a shared reader for datom's own files in the clone (named in task 4b) | new | Parses an artifact's `version_history.json` (and the documents heal publishes); on a file that does not parse, stops with one condition class and section 4's short message (restore the artifact's datom files from a commit where they parse, `git commit`, re-run). Used by heal's publish, `.datom_lookup_history_object_sha()`, `.datom_write_metadata_local()` and the manifest row's version count in `.datom_update_manifest_entry()`. `.datom_prior_metadata()` keeps treating a broken `metadata.json` as absent, since the write replaces it |
| `R/heal.R` | `.datom_reset_unfinished(conn)` | new | Step a. Finds datom-owned files that differ from the last commit and puts them back (section 4) |
| `R/heal.R` | `.datom_unpublished_artifacts(conn, stored)` | new | Names the artifacts whose committed version readers cannot see: those whose clone manifest row differs from the stored one. A version in unpushed commits always qualifies, because the manifest is published last, so the list of pushed artifacts is not added in (simplification, design spot-check before task 4a). Separately reports a differing row whose stored version the clone's `version_history.json` does not contain (R3.10), which stops the command |
| `R/heal.R` | `.datom_publish_artifacts(conn, names)` | new | **The one publish path.** For each name, the clone's snapshot, history and `metadata.json` (last) through `.datom_push_metadata_s3()`; then the manifest, last, and only if every artifact's documents were published (section 6). The snapshot is keyed by the document's own version, `.datom_compute_metadata_sha()` (section 4, step d). Heal's step d, a write's steps 5-6, the metadata-only route and the repair all go through it |
| `R/heal.R` | `.datom_resolve_manifest_conflict(path)` | new | R3.8: puts the remote's manifest in place, runs the format check on it and on every artifact, and only then rebuilds the rows that disagree with their artifact's files (adding missing ones), stages it, commits the merge (section 5). Called by the pull on a conflict only in the manifest, and by the merge check once only the manifest is left. What the format check needs where the caller holds no connection is settled in task 5 (section 10, item 6) |
| `R/heal.R` | `.datom_pushed_artifacts(path)` | new | Artifacts touched by commits the remote lacks; feeds the R3.6 message and the scan's `unpushed` status (not step d, since the spot-check before task 4a) |
| `R/manifest-rebuild.R` | `.datom_manifest_row(meta, history, member_count)` | new, extracted | The row-building half of `.datom_rebuild_manifest_entry()`, which keeps its storage reads and calls it. The clone-side rebuild in section 5 calls it too, so the two rebuilds cannot drift |
| `R/utils-storage.R` | `.datom_storage_upload_absent(conn, local_path, key, sha256 = NULL)` | new | R1.2: check, then upload only if absent. Returns `"uploaded"` or `"exists"`. `sha256` (task 3) is a hash the caller already holds; S3 sends it as the checksum instead of hashing again |
| `R/utils-storage.R` | `.datom_storage_object_sha256(conn, key)` | new | R1.3: the SHA-256 (hex) of the bytes stored at `key` |
| `R/utils-s3.R` | `.datom_s3_upload_absent()`, `.datom_s3_object_sha256()` | new | S3 halves (section 3) |
| `R/utils-local.R` | `.datom_local_upload_absent()`, `.datom_local_object_sha256()` | new | Local halves (section 3) |
| `R/utils-local.R` | `.datom_is_temp_key(key)` | new | Recognises the temporary file names a local upload uses (section 3) |
| `R/storage.R` | `datom_storage_copy()`, `datom_storage_verify()` | changed | Skip temporary files left by an interrupted local upload; `datom_storage_list()` is unchanged |
| `R/utils-git.R` | `.datom_git_pull(path, pat)` | changed | The pull every write calls (R3.7), owned by the commands, not heal. Starts with the merge check; fetches; merges only if behind; on a conflict whose only file is `.datom/manifest.json`, calls `.datom_resolve_manifest_conflict()`. Every other conflict stops the command, leaving the merge in progress, with section 4's short merge message (not `--theirs` and re-run). **Then confirms it caught up**: HEAD contains the fetched upstream tip, decided by commit and never by `git2r::merge()`'s return fields (which come back `NULL` when the user's files block the merge); otherwise it stops with the `git stash -u` recipe (section 4, step b). With no upstream branch it merges nothing, as today (no stop; 2026-11-04). Says whether HEAD moved (a fast-forward counts), so the write commands' pull step (named in task 4a) runs the forward-compatibility check on every artifact after a merge without a conflict, and only then (a merge with a conflict only in the manifest is checked inside the rebuild) |
| `R/sync.R` | `.datom_clone_artifact_names(conn)` | changed | A folder counts only if the manifest (last commit or working tree) names it, or its `metadata.json` declares a datom `hash_algo` (section 4, step a). Its three callers: heal's reset, the repair, and the forward-compatibility check on the mirror-everything route |
| `R/utils-git.R` | `.datom_git_head_file(path, rel)` | new | A file's content as committed in HEAD (`git2r::revparse_single(repo, "HEAD:<rel>")`) |
| `R/utils-git.R` | `.datom_git_push(path, pat, pull_first)` | changed | When git rejects the push because the remote holds commits the clone lacks, the message says the clone is behind and to run `datom_pull(conn)` and re-run, instead of "check your credentials and remote access" (2026-11-04). Other push failures keep today's message |
| `R/utils-git.R` | "does commit A contain commit B" (named in task 4a) | new | `TRUE` when A is B or descends from it (`git2r::descendant_of()` is `FALSE` for a commit and itself, so equality is tested first). The one test behind three decisions: the merge check's "a merge of the remote branch" (the tip contains `MERGE_HEAD`), the pull's "is the clone behind" (HEAD does not contain the tip), and its "did it catch up" (HEAD contains the tip) |
| `R/forward-compat.R` | `.datom_check_writer_floor(conn)` | changed | Reads `min_writer_version` from the clone's `.datom/project.yaml` on every call, instead of the copy the connection took when it was made, so a minimum raised in the pull every write now makes is seen (design spot-check before task 4a). A `project.yaml` that cannot be read or parsed stops the write with a clear message rather than skipping the check. No clone, nothing to read: the check passes, and the role check refuses the write |
| `R/conn.R` | `new_datom_conn()`, `.datom_get_conn_developer()` | changed | The `min_writer_version` field leaves the connection object (its only reader was the floor check), with the comment recording the stale-copy gap after a migration pull, now closed. The internal help pages that mention it, and the comments in `R/ref.R`, `R/set.R` and `R/utils-validate.R`, are updated. Tests that set the field (about 11 places in `test-conn.R`, `test-forward-compat.R` and `test-write-set.R`) write the setting into the fixture's `project.yaml` instead |
| `R/utils-git.R` | `.datom_check_git_current()` | deleted | Its only caller, `datom_sync()`, heals instead (DD3), and its offline "warn and carry on" is replaced by DD1. The comments naming it in `datom_repo_commit()`, `.datom_git_ahead()` and `.datom_git_push()` are rewritten |
| `DESCRIPTION` | `paws.storage` | changed | `(>= 0.8.0)`: the first release with both `IfNoneMatch` (since 0.7.0) and `ChecksumType` (since 0.8.0), checked against the CRAN sources |
| `R/read_write.R` | `datom_write()` | changed | The merge check, heal's reset, its own pull, heal's publish, then the data file before clone files; internal `.healed` argument so `datom_sync()` heals and pulls once per call (R3.7) |
| `R/read_write.R` | `.datom_commit_and_mirror()` | changed | Loses its `upload` argument: the data file is already stored. The table write stops passing it in task 2; the argument goes in task 3, when the set write stops too. Commits and pushes, then publishes through `.datom_publish_artifacts()` |
| `R/read_write.R` | `.datom_push_metadata_s3()` | changed | Uploads the snapshot, then the history, then `metadata.json` last (section 1) |
| `R/read_write.R` | `.datom_resolve_parquet_sha()`, `.datom_resolve_document_sha()` | changed | The R1.3 decision, including the stored-file case, and now performing the upload (section 3) |
| `R/read_write.R` | `.datom_store_data_file(conn, tmp_path, key)` | new (task 3) | The last case both resolvers share: hash the fresh bytes once, upload only if absent passing that hash, and record it on `"uploaded"` or the stored file's hash on `"exists"` |
| `R/set.R` | `datom_write_set()` | changed | Payload built in a temp file; uploaded first; the clone's `set.json` takes the stored bytes when they differ (R1.5) |
| `R/set.R` | `.datom_write_set_payload(payload, path)` | new (task 3) | The one place that spells a payload in bytes; a test replaces it to produce a second spelling of one set |
| `R/utils-sha.R` | `.datom_sync_metadata()` | changed | Its opening pull is replaced by heal; it publishes through `.datom_publish_artifacts()`. It no longer commits a hand edit of the table's `metadata.json`: heal resets it first (requirements D13), so the route publishes what is committed |
| `R/sync.R` | `datom_pull()` | changed | Gains `finish_merge = FALSE`: when `TRUE`, the merge check finishes a merge that is not of the remote branch the way it finishes one that is (R3.9, section 4 step 0); with nothing in progress it does nothing |
| `R/sync.R` | `datom_sync_manifest()` | changed | Compares against HEAD's manifest; `unpushed` status, from the clone alone (section 7) |
| `R/sync.R` | `datom_sync()` | changed | Heals once instead of `.datom_check_git_current()`, with every table in its preview as its own; unfinished work on a table outside the preview stops it; `unpushed` rows are reported as published by heal |
| `R/sync.R` | `.datom_sync_data_metadata()` | changed | Heals every artifact (`all = TRUE`; so it pushes first, R5.2), restores each set's payload where storage lacks it, then publishes every artifact through `.datom_publish_artifacts()`, manifest last (section 6) |
| `R/sync.R` | `.datom_read_manifest()` | changed | A third scope, `"head"`, reading HEAD's copy through `.datom_git_head_file()` with the same schema check and upgrade |
| `R/sync.R` | `.datom_restore_set_payload()` | changed | Uploads through `.datom_storage_upload_absent()` |
| `R/sync.R` | `.datom_sync_one_artifact()` | deleted | Its snapshot loop copied from a clone `{name}/.metadata/` folder no datom command writes, so it never published a snapshot; the repair uses `.datom_publish_artifacts()` and calls `.datom_restore_set_payload()` directly (section 6) |
| `R/validate.R` | `datom_validate()` | changed | The fix now pushes and reports per artifact (R5.3); the new status `manifest_mismatch_s3`, read from storage only (R5.5, section 6) |
| `R/validate.R` | `.datom_validate_one_table()` | changed | Reads the stored `metadata.json` and history, and reports `manifest_mismatch_s3` when the version recorded for them (`.datom_recorded_current_version()`) differs from the stored manifest's row (section 6) |
| `R/repo.R` | `datom_repo_commit()` | changed | The merge check, then, before staging, a stop naming `datom_validate(fix = TRUE)` when the commit would include datom's own uncommitted files (R3.5, R3.9; no reset since the spot-check before task 4a); the R3.6 message when it pushes |
| `R/repo.R` | `datom_repo_push()`, `datom_repo_attach_governance()`, `datom_repo_set_data_store()` | changed | The R3.6 message around their push |
| `R/conn.R` | `datom_init_repo()` | changed | Finishes a half-initialised folder (section 8) |

In `R/forward-compat.R` only two messages change: the vocabulary refusal and the unreachable-shape
refusal also name the installed datom version, as the schema and floor refusals already do, so every
refusal names its evidence (requirements R3.8). Nothing changes in `R/utils-path.R` (keys), the
metadata builders or any document shape. No field is added to any datom-owned document, so no schema
number moves and the vocabulary lists are untouched.

## 3. The data file: upload only if absent, and which hash to record

`.datom_resolve_parquet_sha(conn, name, data_sha, tmp_path, change_type, current)` decides **and
uploads**, before any clone file changes. `.datom_resolve_document_sha()` is its set twin.

```
metadata_only           -> carry current hash forward, no upload            (R1.4, unchanged)
history names a hash    -> record it, no upload                             (R1.3 case 1; D7/D11: not re-checked)
otherwise               -> .datom_storage_upload_absent(tmp, key)
                             "uploaded" -> record the fresh bytes' hash      (case 3)
                             "exists"   -> record .datom_storage_object_sha256(key)
                                           (case 2: an earlier run or a colleague stored it,
                                            before this call or during it)
```

No separate existence check comes first: the upload makes it (R1.2), so one path covers "stored
before" and "stored in between", and a write of new content costs one S3 request fewer (design
spot-check before task 2, owner, 2026-10-30). A file stored before datom-cv1, with no hash in the
history, is kept and its hash recorded, where the old code overwrote it.

**S3** (`R/utils-s3.R`):
- `.datom_s3_upload_absent()`: `head_object` first (the R1.2 check); if absent, `put_object(...,
  IfNoneMatch = "*", ChecksumSHA256 = <base64 of the raw SHA-256>)`. From task 3 the caller may pass
  the file's SHA-256 (`sha256 =`, hex): the resolvers hash the fresh bytes once and pass it, so a new
  file is hashed once, not once for the header and again for the record (task 2's checkpoint
  review, owner, 2026-10-31). A refusal because the key
  appeared in between arrives as a condition of class `http_412` (paws builds the classes
  `paws_error`, `http_412`, `http_400`, `http_error`; read from `paws.common::aws_error()`), and
  is returned as `"exists"`.
- `.datom_s3_object_sha256()`: `head_object(..., ChecksumMode = "ENABLED")`. The stored
  `ChecksumSHA256` is trusted **only when it covers the whole file**: `ChecksumType` is
  `FULL_OBJECT`, or `ChecksumType` is absent and the value carries no `-N` suffix. A file uploaded in
  parts carries a checksum of the parts' checksums instead (suffix `-N`, type `COMPOSITE`), and read
  as a plain hash it would record a wrong one. In every other case, `get_object` and hash the body.
  datom uploads in one piece today, so this guards the multipart uploads planned in #73. A value
  that does not decode to exactly 32 bytes is not trusted either (added in task 1): a service
  returning the checksum in another format would otherwise record a wrong hash for good. The
  arguments and the `ChecksumType` field exist from paws.storage 0.8.0; their behaviour against real
  S3 is checked by `research/s3_conditional_probe.R` (section 10), not in unit tests (R7.5).
- On a service that ignores `IfNoneMatch`, the `head_object` check still runs first; the race left
  is the R8 row.
- **409 is an ordinary upload failure** (owner, 2026-10-28). AWS returns 412 when two conditional
  uploads to one key collide (the first to finish wins), and 409 when a delete finishes before a
  conditional upload completes. In datom only a teardown deletes data files, so a 409 needs a
  teardown racing a write. The write stops with the usual upload error; the upload is its first step,
  so nothing in the clone has changed, and a re-run finishes. No retry: it could upload into a
  project being torn down.
- **No fallback for a service that rejects the new headers** (owner, 2026-10-28). A service that
  answers `IfNoneMatch` or `ChecksumSHA256` with 400 or 501 makes every write stop at its first step,
  with the service's own error and nothing changed. Recorded in section 12 and beside `endpoint` in
  the help; a fallback can be added when a user needs one. paws alone can trigger this: from
  `paws.common` 0.9.0, every upload carries a checksum by default, datom's metadata uploads included,
  so such a service can fail even without datom's new arguments.

**Local** (`R/utils-local.R`):
- `.datom_local_upload_absent()`: if the target exists, `"exists"`. Otherwise copy to a temporary
  name in the same folder and **hard-link** it to the final name with `file.link()`, then delete the
  temporary name. A link refuses when the target exists, so a file that appeared in between is never
  replaced; a plain move would replace it. (Checked 2026-10-28: `file.rename()` onto an existing file
  replaced it; `file.link()` onto one refused and left it intact.) When the link fails, datom looks
  again: the target now exists means `"exists"`; it does not means the file system has no hard links
  (some network drives, exFAT), and datom falls back to check, then move, which leaves the race in
  section 12. A half-copied file only ever sits under the temporary name.
- The temporary name is recognisable: a leading `.` and a `.tmp` suffix, for example
  `dm/.{data_sha}.parquet.{random}.tmp`, matched by one helper, `.datom_is_temp_key()`.
  `datom_storage_copy()` and `datom_storage_verify()` skip such files, so a leftover from a crash
  between the link and the clean-up is never carried to a new location or reported as a mismatch.
  `datom_storage_list()` keeps showing every file, so a leftover can still be seen. Readers never
  touch these files (they read exact keys), and the manifest rebuild already ignores them (it finds
  artifacts only through `{name}/.metadata/metadata.json`).
- `.datom_local_object_sha256()`: hash the file.

`.datom_storage_upload()` (unconditional) stays for metadata documents. After this spec its only
callers are the JSON writers; the data-file uploads all go through `.datom_storage_upload_absent()`.

**Sets** (`datom_write_set()`): today the payload is written straight into the clone's `set.json` and
hashed there. It is written to a temp file instead, hashed and uploaded (or adopted) by
`.datom_resolve_document_sha()`; only then is it copied into the clone. When the recorded hash is a
stored payload's (case 1 or 2) and the fresh bytes differ, the stored payload is downloaded (it is
small) and written to `set.json` instead, so git and storage hold one spelling (R1.5).

## 4. The start of every write: the merge check, heal and the pull

Restructured 2026-10-30 in the simplification pass (owner; principles and scenarios in requirements
D14). Three pieces run before a command's own work, in this order: the **merge check** (step 0), heal's
**reset** (step a), the **pull** (step b), heal's **publish** (step d). Only steps a and d are heal,
`.datom_heal()`; each runs only when its own check finds something, so on the common path heal reads
and changes nothing (section 1). The merge check and the pull belong to the commands: every
git-touching command calls the merge check, every write calls the pull (R3.7), and removing heal
would leave both. `artifact` names the artifacts the command is writing; heal acts on those only.

**Heal acts only when it is certain something needs healing** (owner, 2026-10-31, design spot-check
before task 4a; requirements D14 principle 8). When a check is unsure, heal does nothing and the
command stops with a way out. Nothing can prove whose work a leftover is (no record of a write in
progress, D2), so "certain" means the action is one the command was about to take anyway on the same
artifact: a write's own steps, run again. **A write heals only the artifacts it is writing.** Any other
artifact's unfinished work stops it before anything changes:

> `lb` has unfinished work: a version committed but not yet in storage. datom changed nothing. Run
> `datom_validate(fix = TRUE)` to finish it, then re-run. If a teammate has just written `lb`, a
> re-run may be enough.

(Final wording in task 4a or 4b, by which kind of leftover it names: uncommitted files are "discarded"
by the fix, a committed version "finished".) The repair, `datom_validate(fix = TRUE)` and
`datom_write(conn)`, heals every artifact: calling it is the consent. A stop, not an interactive
prompt, because scripts and a product layer cannot answer one. Making a stop automatic later is one
change in one place, since the repair runs the same code. Why: reviews kept finding edge cases where
heal acted on another artifact from a state it had misread (a user's `app/metadata.json` reset; a
behind clone publishing old versions of a teammate's table, step b); a write that never acts on
another artifact cannot meet that class.

**What heal repairs, and what it leaves** (its docstring says both):

| Heals | Leaves |
|---|---|
| the artifacts the command writes: their datom files from a write that broke before its commit (reset) | another artifact's unfinished work: the command stops and names `datom_validate(fix = TRUE)`, which heals it |
| the artifacts the command writes: their committed version GitHub or storage lacks (pushed, then published) | a merge conflict outside the manifest (#105): the merge check stops and says how to finish it, and finishes a merge of the remote branch itself once only the manifest is left (step 0) |
| every artifact, when the command is the repair | a merge datom did not start: the merge check stops until `datom_pull(conn, finish_merge = TRUE)` or `git merge --abort` (step 0) |
| | a stored version this clone has never seen: the command stops (step d, R3.10) |
| | a pull that could not catch up because the user's files are in the way: the pull stops (step b) |
| | damage a released datom left behind (D7, D11) |
| | a file someone put in storage by hand |
| | anything when GitHub cannot be reached: the pull stops instead (DD1) |
| | the one crossing of two publishes in section 12, which `datom_validate()` reports as `manifest_mismatch_s3` and its fix clears |

**0. The merge check** (R3.9; a helper named in task 4a, in `R/heal.R` but independent of heal).
Called at the start of `.datom_git_pull()` (so by every pull: a write's, `datom_pull()`'s, the four
push commands', and the migration pull in `datom_get_conn()`), by heal before its reset, and by
`datom_repo_commit()` before it stages anything (task 8). Calling it twice in one command is harmless. On the
common path it only finds that `.git/MERGE_HEAD` does not exist.

When a merge is in progress, it first asks **what is being merged** (2026-10-31, owner, from the
review of `058f29b`; probed, section 10). The commit in `.git/MERGE_HEAD` is compared with the tip of
the branch's upstream as last fetched (`git2r::branch_get_upstream()`; local refs only, no fetch). It
is a **merge of the remote branch** if the tip contains it: the same commit, or the tip descends from
it (the shared "does commit A contain commit B" helper, section 2).
That is the only merge datom's pull makes, and a `git fetch` during the merge does not change the
answer; a user's own `git pull` gives the same answer. With no upstream, or a detached HEAD, it is
any other merge. Nothing is decided from text or from a record datom keeps, so there is nothing a
user could copy by accident and nothing that can outlive its merge (D2).

- **Not a merge of the remote branch** (a local branch or another remote, started outside datom):
  stop before changing anything:

  > A merge datom did not start is in progress ("Merge branch 'feature'"). datom changed nothing.
  > Resolve it with git and run `datom_pull(conn, finish_merge = TRUE)` to let datom rebuild the
  > manifest and commit, or drop it with `git merge --abort`.

  The quoted name is the first line of `.git/MERGE_MSG`, shown only to say which merge; nothing is
  decided from it. `datom_pull(conn, finish_merge = TRUE)` lets the merge check treat such a merge
  like a merge of the remote branch: it finishes once only the manifest is left or nothing
  conflicts, and while another file conflicts it stops with this message.
- **A merge of the remote branch, and a file other than `.datom/manifest.json` still conflicts**
  (`git2r::status()` reports it as `conflicted`): stop before changing anything, with one short
  message that names the files and fills in the command:

  > A merge is in progress, and these files still conflict: `dm/metadata.json`,
  > `dm/version_history.json`, `app.R`. Take the remote copy of datom's files:
  > `git checkout MERGE_HEAD -- dm/metadata.json dm/version_history.json`. Resolve your own files and
  > `git add` them. Then re-run your write: datom rebuilds the manifest and finishes the merge.

  The command lists all of each conflicted artifact's datom files (`set.json` too for a set), not
  only the conflicted ones: `git checkout --theirs` does nothing to a file that merged cleanly
  ("Updated 0 paths"), which would leave the artifact half local and half remote (probed 2026-10-30,
  section 10).
- **A merge of the remote branch, and only the manifest is left, or nothing**: rebuild the manifest
  with `.datom_resolve_manifest_conflict()` (section 5, which runs the format check before it
  writes), commit the merge ("Merge finished by datom (manifest rebuilt)", which names no source, so
  it is true for a merge finished on request too), say so, and carry on.

Why each branch. Without the first stop, datom would commit, and the next push would share, a merge
the user started, for instance one made with `--no-commit` to inspect it (review of `058f29b`).
Without the second, heal's reset would put a file the user had resolved back to the local side, and
the next pull would conflict again: a loop. Without the finish, the user would have to take the
remote's whole manifest by hand; its rows for the clone's other unpushed writes would then stay
stale, `datom_list()` would name their old versions while reads return the new ones, and nothing
would report it (traced 2026-10-30). For a merge of the remote branch the user never edits the
manifest and never runs `git commit`.

Set aside on 2026-10-31: comparing `MERGE_HEAD` with the upstream tip by equality only (the review's
proposal), which calls datom's own merge foreign once anything fetches during it, leaving a way out
that needs the manifest resolved by hand; finishing every merge and printing a `git revert -m 1`
line to undo it; and a marker line datom writes into `.git/MERGE_MSG` (text a user could copy).

**a. Reset what never committed** (heal; `.datom_reset_unfinished()`; R2.4, R3.1). Runs only if
`git2r::status()` shows a datom-owned file differing from HEAD. The files of an artifact the command
writes are reset; if any other artifact's files differ, heal resets nothing and the command stops
(above). The shared `.datom/manifest.json` is reset only when every row that differs from HEAD's
belongs to an artifact the command writes; a differing row of any other artifact is that artifact's
unfinished work, and stops the command. The repair resets every artifact's files. "Datom-owned files" are, for each
artifact `.datom_clone_artifact_names()` returns, `metadata.json`, `version_history.json` and
`set.json`, plus `.datom/manifest.json`. Nothing else: not `.datom/project.yaml`, not
`.datom/governance.json`, not `include_paths`, not `input_files/`.
- **Which folders are artifacts** (full-spec review of `b76961b`, owner, 2026-10-30). A top-level
  folder is a datom artifact if the manifest names it, in the last commit or in the working tree, or
  if its `metadata.json` parses and declares a datom `hash_algo` (`datom-cv1` for a table,
  `datom-sv1` for a set). The second rule catches a first write broken before its manifest row, and
  keeps the helper independent of the manifest, which the repair needs. Today the helper counts any
  top-level folder holding a `metadata.json`, so a user's `app/metadata.json` would have its
  uncommitted edits reset, or be deleted if untracked; the same rule makes today's repair publish
  such a folder as an artifact and the forward-compatibility check read it. The helper is tightened
  once, for all three callers.
- `git2r::status()` (staged, unstaged and untracked) lists what differs from HEAD. Untracked entries
  come back as directories (`lb/`), so an untracked directory is expanded and only the three file
  names are kept.
- Tracked files: unstaged with `git2r::reset(repo, path = ...)`, then `git2r::checkout(repo, path =
  ..., force = TRUE)` (the checkout half is probed; the unstaging half is not yet, see section 10).
  Untracked datom files (an artifact's first write that never committed) are deleted.
- The message depends on whose files were reset (owner, 2026-10-28):

  | Whose files | Message |
  |---|---|
  | An artifact in `artifact`, which this command is about to write | Information only: "Found an unfinished write of `dm` that stopped before its commit; writing it again now." |
  | Any other artifact, reset by the repair | A warning: "Reset an unfinished write of `lb` that stopped before its commit. Run that write again to save it." |
  | Any other artifact, found by a write | No reset: the command stops (above) |

  Whether these are `cli` alerts or warnings with a class a test can count is settled in task 4a
  (section 10, item 5).

**b. The pull** (the command's, not heal's; R3.7, R3.8): `.datom_git_pull()`. The merge check first,
then a fetch. A failed fetch stops the command before it changes anything, with a message saying
datom could not reach the remote (DD1). The merge runs **only if the clone is behind** (HEAD does not
contain the fetched tip). A conflict only in the manifest is rebuilt (section 5, after the format
check). Any other conflict stops the command before any publish, leaving the merge in progress, with
step 0's message ending "No version is published." When the conflict comes from the pull inside a
write's push, the message adds "This write's data file may already be in storage, unnamed until the
write finishes" (from task 2 the data file is uploaded before the push); the pull at the start of a
command, and `datom_pull()`, have stored nothing yet, so they do not say it.

**Then the pull confirms it caught up** (design spot-check before task 4a, 2026-10-31; probed,
section 10). git2r's merge silently does nothing when the user's own files are in the way of the
incoming commits: a modified or staged file the commits change, or an untracked file where they add
one. It raises no error and returns `conflicts = NULL`, so today's `isTRUE(merge_result$conflicts)`
reports success while the clone is still behind. With heal's publish after the pull, a clone that is
only behind would then publish old versions over a teammate's newer ones; one that also has its own
commits has its push rejected with "check your credentials". So, decided by commit and never by
`git2r::merge()`'s return fields: after the merge, HEAD must contain the fetched tip; otherwise the
command stops before changing anything:

> Could not bring the clone up to date: local changes are in the way of the incoming commits (see
> `git status`). datom changed nothing. Set them aside with `git stash -u`, run `datom_pull(conn)`,
> bring them back with `git stash pop`, resolve anything `git stash pop` reports, then re-run.

`-u` because a plain `git stash` leaves untracked files behind, so the pull would stop again. The last
step matters because `git stash pop` can report a conflict, or refuse to restore an untracked file
("already exists"), keeping the stash; a set write listing such a file in `include_paths` would
otherwise commit its conflict markers (traced, section 10). The message points to `git status` rather
than naming the files: naming them means comparing the uncommitted files with what the incoming
commits change, for a rare case, and the recipe works without knowing which file blocks. The check is
in `.datom_git_pull()`, so `datom_pull()` (which today says "Already up to date" in this state), the
push commands and the migration pull get it too.

**No upstream branch: no stop** (owner, 2026-11-04, review of `d616e98`, withdrawing a stop added
the day before). With no upstream the pull fetches and merges nothing, as today, and the caught-up
check has no tip to compare with, so it does not run. On the project's branch this happens only
when init failed to set the upstream after its first push (a warning today); a new code branch
never has one, and `git branch --set-upstream-to=origin/<branch>` fails until the branch is pushed
(checked), so a stop would block `datom_pull()` and the push commands there. Nothing unsafe follows
on the publish branch: `.datom_git_ahead()` is `NA`, so heal pushes before it publishes; git
rejects that push when the clone is behind (probed, section 10), which stops the command before
storage changes, and a push that succeeds sets the upstream (the fallback in `.datom_git_push()`).
**A rejected push names the cause**: when git refuses because the remote holds commits the clone
lacks, the message says the clone is behind and to run `datom_pull(conn)` and re-run, instead of
today's "check your credentials and remote access".

**After a merge**, and only then, the forward-compatibility check runs on every artifact,
`.datom_check_write_entry(conn, NULL)`, because the merge may have brought documents from a newer
datom. "A merge" means HEAD moved: a fast-forward counts (git2r returns `sha = NA` for one, so its
return fields cannot say). Without a merge nothing new arrived, and the check at the start of the
write already read the command's own artifact. A merge that conflicted only in the manifest has
already passed the same check inside the rebuild, before anything was written (section 5); a merge
finished by step 0 has too, which matters because the pull that follows it usually finds nothing to
merge. That one check covers everything heal then publishes: an artifact that arrived
in the merge was just checked, and anything else heal publishes is this clone's own committed work. A
refusal says to upgrade datom (D11) and comes before any publish (simplification pass, owner,
2026-10-30, replacing a separate check of step d's publish list and a `touch` argument).

**d. Push and publish** (heal; R3.2-R3.4, R3.10). Runs only if the clone is ahead of the remote
(`.datom_git_ahead()` above 0, or `NA`) or a stored manifest row differs from the clone's; deciding
that costs one read of the stored manifest, which step d then reuses (R3.4). "Differs", not
"behind": a revert to earlier content is a different row, not an older one.
- `.datom_unpublished_artifacts()` = every artifact whose clone row's `current_version` differs from
  the stored row's (an absent stored manifest means all of them). A stored row for an artifact the
  clone does not have counts as differing too (2026-11-04): the clone cannot publish it, so a write
  stops on it, and the repair drops it and says so (below). A version in unpushed commits is
  always among them, because the manifest is published last, so the pushed artifacts are not added
  in (simplification, design spot-check before task 4a). After the pull the clone holds at least
  what GitHub holds, so a difference found here usually means storage is behind this clone (R3.3).
- **Any of them that the command does not write stops it** before the push (above), naming
  `datom_validate(fix = TRUE)`. The repair takes them all.
- **A stored version the clone has never seen stops it too** (R3.10). For each artifact to publish,
  the clone's `version_history.json` must contain the version the stored row names (no stored row,
  or no stored manifest, passes). Containment, not "older": a version id hashes content only, so
  writing old data again brings back an id the history already holds (and does not add again; the
  full-history check in `.datom_write_metadata_local()`). An "older" test would refuse to publish a
  revert after storage failed (S4). The cases it catches: a teammate published after this clone's
  pull (a re-run brings their commit), and, rarely, storage edited by hand or commits removed from
  GitHub by a force-push (S8). A write from a branch other than the project's own is the
  publish-branch rule's to stop (requirements "Related"; 2026-11-03), so it is no longer reasoned
  about here. Local reads only, and only on the path where a row differs. Stop rather than skip:
  every manifest upload sends the clone's whole file, so a skipped artifact's stale row would reach
  storage anyway with the next manifest upload, leaving the stored manifest and that artifact's
  stored documents naming different versions (owner, 2026-10-31). The stop message: "Storage names
  version `<id>` of `dm`, which this clone has not seen. datom changed nothing. Re-run (a write pulls
  first); if it persists, run `datom_validate(fix = TRUE)`."
- **The repair overrides that stop** (2026-11-03, owner, from a review of `4045fbd`). Without the
  override, a state the check refuses would lock the project: every write of another artifact stops
  on the differing row and names the repair, and the repair would stop on the same check. With
  `all = TRUE` heal publishes the clone's version anyway and says which stored version it replaced.
  An artifact the stored manifest names but the clone does not have at all (for example one left by
  a write from a branch since deleted) loses its row in the published manifest, and the repair says
  so; its documents stay in storage, unnamed.
- If ahead: `.datom_git_push()`.
- `.datom_publish_artifacts()` for the remaining names, manifest last, and only if every artifact's
  documents were published (section 6); when heal's publish fails, the command stops before its own
  work. A set's payload is not re-uploaded here: under D1 it is in storage before its commit exists.

**The manifest upload** (R3.10; design spot-check before task 4a, 2026-10-31). Every manifest upload
sends the clone's whole file. Heal's publish only reaches it when every differing row has passed the
checks above. A write's own step 6 has one more case: the pull inside its push can bring in a
teammate's commit, whose row then names a version the teammate may not have stored yet (their upload
is seconds behind, or failed). So when that pull moved HEAD, the write reads the stored manifest once
more, and uploads only if every row other than its own agrees with it (a stored row the clone lacks
disagrees); otherwise it skips the upload,
says the manifest was not published because another artifact's new version is not in storage yet,
and names `datom_validate(fix = TRUE)`. The next write of any other artifact stops and names the same
fix. Without a merge in the push, R3.4's one read already showed every other row agreeing, since the
command stopped otherwise; no extra read.
- **The snapshot's key is the document's own version**, `.datom_compute_metadata_sha()` of the
  `metadata.json` being published, on every publish (simplification pass, owner, 2026-10-30). That is
  the key the write itself used: the committed file is the document the write computed its version
  from, and the fields added after that computation (`parquet_sha`, carried-forward unknown fields) do
  not count toward a version. Change detection already relies on this round trip (the identity test
  S6). A hand edit committed by 0.2.0 therefore gets one extra snapshot under its own key, which
  nothing names; no snapshot is ever overwritten with a document that does not hash to its key.
- Heal's publish passes no commit id, so the stored history works it out from git: the first commit
  that produced the version (`R/version-commit.R`). A write's own publish passes the commit it just
  made; once heal runs first, a re-run makes no second commit, so the two agree (design spot-check
  before task 2, owner, 2026-10-30).
- **A datom file in the clone that does not parse** (only possible when committed outside datom; an
  uncommitted one is reset in step a). Every read of it goes through one shared reader (section 2),
  which stops with one condition class and one short message:

  > `dm/version_history.json` does not parse. Restore `dm`'s datom files from a commit where they
  > parse (`git log -- dm/` lists them): `git checkout <commit> -- dm/metadata.json
  > dm/version_history.json`, then `git commit`, and re-run.

  All of the artifact's files, from one commit: restoring only the broken one would leave
  `metadata.json` describing a version its history no longer records. `datom_repo_commit()` cannot
  commit the restore, because it stops on datom's own uncommitted files (D9). A write of that artifact gets
  no exception: a broken history stops that write anyway, since it reads the history to decide the
  data file's hash before it uploads.

The command's own work then runs against a clone that is clean, current and fully published, so
today's change detection (`.datom_has_changes()`, against storage) answers correctly, and a re-run
whose own write already finished reports `none` (R2.1). A break at step 6 is caught by step d of the
next run of the same command (R2.3); a write of any other artifact stops and names the repair.

**Two publishes at once** (DD4). A colleague can publish after this clone's pull and before its
publish. Reproduced on today's code (`research/publish_race_probe.R`): you push `dm` v2; before your
publish runs, a colleague pulls, writes v3, pushes and publishes it; your publish of v2 then lands, and
readers get v2 although GitHub's latest is v3. datom does not check for this before publishing. The
current version is a pointer that the owners move (a write, or a revert to earlier content), not a
claim that the newest is best; every reproducible read names its version (`version =`, a set's
members, lineage parents) and is unaffected. What matters is that the pointer ends up where git says.
The table's next write, or the repair, does that; meanwhile any other write in an up-to-date clone
sees the stored row differ from its own and stops, naming `datom_validate(fix = TRUE)` (amended
2026-10-31: until then the next command of any kind republished). R3.10 narrows the race without
closing it: a clone that has never seen the colleague's newer version stops instead of publishing
over it, but a colleague's publish landing after this clone read the stored manifest is not seen.
One interleaving escapes the stop: when the two publishes cross so that the
stored manifest names the newer version while the stored metadata holds the older one, step d sees
no difference. `datom_validate()` reports that case as `manifest_mismatch_s3` (section 6), naming the
fix, and it waits for the table's next write or `datom_validate(fix = TRUE)` (section 12).

**Who calls heal, and with which `artifact`**: heal runs in exactly one place per route, so no route
heals twice or reads the stored manifest twice (R3.4), and no prompt is answered after heal has
acted (second review of `tasks.md`, owner, 2026-10-28). A route still fetches more than once: at its
start, and again in its own push's pull. The route's own merge check and pull run at the same point,
between heal's reset and its publish:

| Route | Where heal runs | `artifact` (what heal may act on) |
|---|---|---|
| `datom_write(conn, data, name)` | in `datom_write()`, after the checks that run before heal (section 1) | the table's name |
| `datom_write(conn, name =)`, the metadata-only route | inside `.datom_sync_metadata()`, just before the route's own pull (the pull stays the route's) | none (settled 2026-11-04): the route never rewrites the table's files, it publishes what is committed, so an uncommitted edit of them stops it, naming `datom_validate(fix = TRUE)`, as on any artifact a command does not rewrite. It still publishes the table's committed version when storage lacks it |
| `datom_write(conn)` and `datom_validate(fix = TRUE)` | inside `.datom_sync_data_metadata()`, after its confirmation prompt | every artifact (`all = TRUE`): the repair |
| `datom_write_set()` | in `datom_write_set()`, after its checks | the set's name |
| `datom_sync()` | once per call, before the first table | every table in its preview; then `datom_write(.healed = TRUE)` per table |

`datom_write()` itself does not heal on the two routes without data: it hands them to those helper
functions before anything else runs. `datom_repo_commit()` calls the merge check, then stops if the
commit would include datom's own uncommitted files (R3.5); it resets nothing. The four push commands
meet the merge check through their pull and call nothing else (D10).

## 5. A conflict only in the manifest (R3.8)

Two callers: inside `.datom_git_pull()`, after `git2r::merge()` reports conflicts and the conflicted
paths are exactly `.datom/manifest.json`; and the merge check (section 4, step 0), once a merge in
progress has no conflicted file left but the manifest (a merge of the remote branch, or any merge
when `datom_pull(conn, finish_merge = TRUE)` asked). Both call
`.datom_resolve_manifest_conflict(path)` (simplified 2026-10-30 in the simplification pass, owner:
no comparison with the merge base):

1. Start from the remote's copy (`MERGE_HEAD:.datom/manifest.json`), written into the working tree
   in place of the conflict markers. Its top level, including `project_name` and any field this
   build does not know, is kept as it is.
2. **Check before writing anything else** (added 2026-10-31, owner, review of `058f29b`): run the
   format check, `.datom_check_write_entry(conn, NULL)`, on that copy and on every artifact's files in
   the merged clone. The merge may have brought documents from a newer datom; without this step an
   older build would rewrite the manifest in its own shape, commit it, and the next push would share
   it. A refusal stages and commits nothing and leaves the merge in progress (the working tree holds
   the remote's copy rather than the markers, which the next run reads the same way); its message
   says to upgrade datom and re-run, or to drop the merge with `git merge --abort`. Every refusal of
   the format check names its evidence: the document, the fields or format number this build cannot
   read, and the installed datom version (two messages gain the version, section 2).
3. For every artifact `.datom_clone_artifact_names()` returns in the merged clone, compare its row
   with the version its own files record (`.datom_recorded_current_version()` on its `metadata.json`
   and history). Rebuild a row that disagrees, or is missing, with `.datom_manifest_row()`, carrying
   unknown row fields forward from the clone's previous row with `.datom_carry_unknown_fields()`.
4. Recompute `summary`, set `updated_at` to now, write the file, `git2r::add()`, and commit with the
   message "Merge finished by datom (manifest rebuilt)".

Checking every row against its artifact's own files needs no diff of commit trees, and gives the
right row whichever side changed it: rows the local side did not touch already agree with the files
the merge brought in. It is local reads only, and only on the conflict path, so the common path never
reaches it (D14).

Probed (`research/merge_completion_probe.R`): after staging the rewritten file the conflict clears,
`git2r::commit()` makes a two-parent commit and removes `MERGE_HEAD`, the push lands, and a fresh
clone sees every table.

## 6. The repair and the mirror-everything route (R5)

`.datom_sync_data_metadata(conn, .confirm)` becomes:

```
merge check, heal's reset, the pull, heal's publish (section 4), on every artifact (all = TRUE)
for each artifact:  restore a set's payload if storage lacks it    (data file first)
for each artifact:  .datom_publish_artifacts(): snapshot, history, metadata.json last
once, at the end:   the manifest                                   (only if every artifact published)
```

Because it republishes every artifact rather than only those whose manifest row differs, it also
corrects the crossed-publish case of section 4. On this route, the artifacts heal finds behind are
published twice, once by heal and once by the repair. That is deliberate: both write the same
committed documents, and keeping heal identical on every route is worth more than the few uploads
saved. Going through `.datom_publish_artifacts()` is also
what makes the repair publish in the requirements' sense ("Published" includes the version snapshot;
R5.2): the old per-artifact copy, `.datom_sync_one_artifact()`, copied snapshots only from a
`{name}/.metadata/` folder in the clone, which no datom command writes (confirmed 2026-10-30 by a
real write), so it never published one. It is deleted; the repair calls
`.datom_restore_set_payload()` directly for a set's payload. Older versions' snapshots are not
rebuilt here: that needs each version's `metadata.json` from the commit that introduced it, and no
route in this spec leaves one missing (section 12, follow-up issue).

The confirmation prompt on the `datom_write(conn)` route says it may push. `datom_validate(fix =
TRUE)` reports per artifact what was reset, pushed and published (R5.3).

**A new status, `manifest_mismatch_s3`** (R5.5; rewritten 2026-10-30 in the simplification pass,
owner, from `metadata_stale_s3`, which compared storage against the clone's last commit and so needed
a fetch, a skip for a behind clone and a like-for-like rule). Without it, `datom_validate()` says "All
checks passed" while storage disagrees with itself, because today it only checks that each stored
file exists. `.datom_validate_one_table()` now also reads the stored `metadata.json` and history (two
small reads per artifact, in `datom_validate()` only) and compares the version recorded for them,
`.datom_recorded_current_version()`, the lookup `datom_read()` uses, with that artifact's row in the
stored manifest; a difference is `manifest_mismatch_s3`, and the report names the fix,
`datom_validate(fix = TRUE)` or the table's next write.
- It catches the crossed publish of section 4 (the stored manifest names the newer version, the
  stored metadata holds the older one) and a write broken just before its manifest upload (the
  reverse). Either side may be the stale one, hence the name.
- Storage only: no fetch, no git read, so nothing to skip on a behind clone.
- The recorded version, not a recomputed one, so a hand edit published by 0.2.0, whose document no
  record names, is not reported for good (its recorded version is the previous one, which is also
  what its manifest row names).
- No read and no write pays for it. `.datom_validate_unfixable_tables()` does not list it: the
  repair fixes it.

**Order within the repair** (follow-ups to the design spot-check before task 2, owner, 2026-10-30).
A set's payload first (data file first), then each artifact's snapshot, history and `metadata.json`
last, then the manifest. The stored `metadata.json` is what change detection reads as the sign that a
version is published. If the stored manifest already matches git, which is when the repair is usually
run, a break after an early `metadata.json` would leave a missing history or snapshot that no check
reports. With `metadata.json` last, a repair that breaks mid-artifact leaves the old `metadata.json`
in storage and the manifest unpublished, so the next command's heal sees the stored row behind and
finishes it. When the stored `metadata.json` is already current and the repair is only filling in a
missing snapshot, nothing reports a break, because `datom_validate()` does not check snapshots
(section 12; wording fix from the same reviewer, owner, 2026-10-30).

**One artifact failing does not publish the manifest.** The repair carries on past an artifact that
fails, marking it `"error"`, as today. But a manifest published after that failure would name the
failed artifact's new version while its stored `metadata.json` is old, and heal, which compares
manifest rows, would then see nothing behind. So `.datom_publish_artifacts()` publishes the manifest
only if every artifact's documents were published (section 4); the repair reports each failure,
skips the manifest, and says to re-run.

## 7. The scan and the sync (R4)

`datom_sync_manifest()`:
- reads HEAD's manifest through `.datom_read_manifest(conn, "head")` (R4.1);
- marks `unpushed` each table whose input file is unchanged and that `.datom_pushed_artifacts()`
  names: touched by commits the remote lacks, read from local refs (R4.2). No fetch and no storage
  read (narrowed 2026-10-31, owner, review of `058f29b`), so no warning branches and no special case
  for a clone that is behind. A table pushed but not yet published shows `unchanged`, and
  `datom_sync()` publishes it through heal;
- status order: `unsupported_format`, `new`, `changed`, `unpushed`, `unchanged`.

`datom_sync()` replaces `.datom_check_git_current()` with one heal (see DD3), with every table in its
preview as `artifact`, which pushes and publishes every `unpushed` row, and any table in the preview
pushed but not yet published; `unpushed` rows come back with `result = "success"` without an import
(R4.3). Unfinished work on a table outside the preview stops the sync before anything changes,
naming `datom_validate(fix = TRUE)` (R4.4, design spot-check before task 4a).

## 8. `datom_init_repo()` re-run (R6)

A new internal `.datom_init_finish(path, project_name, store)` runs right after argument validation
and **before** the remote is resolved, because a GitHub `create_repo = TRUE` or a folder remote would
otherwise refuse first. If `.datom/project.yaml` is absent it returns `FALSE` and init continues as
today. If present, it finishes only when all of these hold, and otherwise returns `FALSE` so today's
refusal follows unchanged:
- `project_name` and the `storage.data` block (type, root, prefix, region) equal the call's;
- the clone's remote has the initial commit (fetch, upstream set, `.datom_git_ahead()` is 0);
- storage has no `.metadata/manifest.json`.

Finishing uploads the clone's manifest and reports success, as the last step of a fresh init does.

## 9. Design decisions for the owner

| # | Decision | Status | Cost |
|---|---|---|---|
| DD1 | **A failed fetch at the start stops every command in R3** before it changes anything. Today `datom_sync()` warns and carries on offline (#104), then fails at the push with a local commit left behind | **Decided 2026-10-28: stop** | An offline user cannot even commit locally through datom; they re-run when online, which they must do anyway to push |
| DD2 | **R3.8 sits inside `.datom_git_pull()`**, so `datom_pull()`, the four push commands, and the migration pull inside `datom_get_conn()` (in `.datom_resolve_data_location()`, `R/ref.R`) also resolve a manifest-only conflict, not just the commands in R3. That last caller pulls only on a governed project whose data moved; there, getting a connection can make a local merge commit and says so, where today it aborts and leaves the clone mid-merge (added from the review of `tasks.md`, owner, 2026-10-28) | **Decided 2026-10-28: yes** | Commands outside R3 rewrite the manifest during a merge, and say so. This happens only when the clone holds an unpushed commit that changed the manifest (in practice a datom write whose push failed), a colleague pushed a datom write since, and the manifest is the only conflicted file. A fast-forward, or a merge of commits that never touched the manifest, rebuilds nothing. The alternative was a second pull function for R3 alone, leaving `datom_pull()` to stop on a conflict a write would resolve by itself. With a merge datom did not start in progress, getting such a connection stops with R3.9's message; since `datom_pull()` needs a connection, `git merge --abort` is the way out there (2026-10-31) |
| DD3 | **`datom_sync()` pulls a clone that is behind instead of refusing.** Today it stops with "pull first" (`.datom_check_git_current()`), the only command that does | **Decided 2026-10-28: pull** | A preview built before the pull can be stale. Probed (`research/stale_preview_probe.R`): when a colleague already imported the same file, the stale `new` row is re-read, the write finds no change and stores nothing, and the row reports `success`. Today that row's line also says "synced (new)", which claims work that did not happen; task 6 makes it say the table was already up to date. A conflict outside the manifest still stops the sync before storage changes |
| DD4 | **No check before publishing** (amended 2026-10-31). Every publish writes git's latest state as the publishing clone sees it; a publish that lands after a colleague's newer one is corrected by the table's next write or `datom_validate(fix = TRUE)`, and meanwhile every other write in an up-to-date clone stops and names that fix (section 4, "Two publishes at once"). **Amendment** (owner, design spot-check before task 4a): one check is added, for heal acting only when certain (requirements D14 principle 8, R3.10): before publishing an artifact whose stored row differs, the clone's history must contain the stored version, otherwise the command stops. It narrows the race; it does not close it | **Decided 2026-10-28: no check; amended 2026-10-31: the containment check, stopping rather than skipping** | Readers can get a superseded current version until the table's next write or the repair. Set aside on 2026-10-28: a check before every publish that skipped an artifact whose stored version the clone had never seen, with the manifest merged row by row. It made the pointer right a few seconds sooner in one race, at the cost of code, tests and a blind spot (a colleague's revert to an older version looks to it like stale storage). The 2026-10-31 check differs in three ways: it tests containment in the history, so your own revert after a storage failure is not misread (a teammate's revert published seconds before your write of the same table still passes the check and is overwritten: the race this decision accepts, 2026-11-03); it stops instead of skipping, so no row-by-row manifest merge is needed; and its reason is certainty (a publish seconds old, or storage changed outside datom), not getting the pointer right sooner. It binds writes only: the repair overrides it (2026-11-03) |

## 10. Proven, and not yet traced

Proven on 2026-10-28 (scripts in `research/`):
- The failures this fixes (`write_steps_probe.R`, `set_steps_probe.R`, `sync_and_manifest_probe.R`,
  `other_command_probe.R`, `two_writers_probe.R`), and the race behind DD4 on today's code
  (`publish_race_probe.R`).
- git2r completes a merge after datom rewrites the manifest (`merge_completion_probe.R`).
- git2r 0.36.2 reads a file as committed in HEAD, lists files changed between two commits, resets
  chosen files to HEAD leaving others alone, and reports untracked directories
  (`git2r_primitives_probe.R`).
- `file.link()` refuses an existing target and leaves it intact; `file.rename()` replaces it
  (checked in a throwaway R session).
- paws turns an S3 error into a condition classed by HTTP status (read from
  `paws.common::aws_error()`). paws.storage 0.9.0 accepts `IfNoneMatch`, `ChecksumSHA256` and
  `ChecksumMode`, and its `head_object` output carries `ChecksumSHA256` and `ChecksumType`. From the
  CRAN sources: `IfNoneMatch` is in `paws.storage` from 0.7.0 (2024-09), `ChecksumType` from 0.8.0
  (2025-02), hence the `(>= 0.8.0)` pin.
- From AWS's documentation on conditional writes: two conditional uploads to one key give 412 to all
  but the first to finish; a delete that finishes before a conditional upload gives 409.
- **Real S3, 2026-10-30** (`research/s3_conditional_probe.R`, run by the owner against bucket
  `datom-test`, task 1): 11 of 11 checks passed on each of the three paws pairs, `paws.storage`
  0.9.0 / `paws.common` 0.8.8 (installed here), 0.8.0 / 0.8.0 (the declared minimum) and 0.11.0 /
  0.9.0 (CRAN's current). An "only if absent" upload of a stored key is refused with a condition of
  class `http_412` (classes `paws_error http_412 http_400 http_error`), and datom's upload reports it
  as `"exists"`, leaving the stored bytes unchanged. `head_object(ChecksumMode = "ENABLED")` returns
  `ChecksumType` `FULL_OBJECT` and a `ChecksumSHA256` equal to the file's SHA-256, so
  `.datom_s3_object_sha256()` reads the hash without downloading. A wrong `ChecksumSHA256` is refused
  (`BadDigest`, HTTP 400), so the header reaches S3. On `paws.common` 0.9.0 the upload with datom's
  own `ChecksumSHA256` succeeds: paws skips its default checksum when the caller supplies one
  (`has_checksum_header()` in its `custom_checksum.R`).
- **A merge in progress, 2026-10-30** (throwaway git2r 0.36.2 probes, two clones of one bare
  remote). After `git2r::merge()` reports a conflict, `.git/MERGE_HEAD` exists and
  `git2r::status()` lists each conflicted file under `unstaged` as `conflicted`; both stay until the
  merge is committed. `git checkout --theirs <file>` on a file that merged cleanly does nothing
  ("Updated 0 paths from the index"), so a user following "keep the remote version with `--theirs`"
  can leave an artifact's `metadata.json` local beside a remote `version_history.json`.
  `git checkout MERGE_HEAD -- <files>` takes the remote copy of conflicted and clean files alike and
  clears the conflict; `git commit` then completes the merge and removes `MERGE_HEAD`.
- **What a merge brings in, 2026-10-31** (`research/merge_source_probe.R`, git2r 0.36.2 and git
  2.54.0, two clones of one bare remote). After datom's pull (`git2r::merge()` of the upstream
  branch) stops on a conflict, the commit in `MERGE_HEAD` is the upstream tip as last fetched; after
  a later `git fetch` moves the tip, the tip descends from it. A user's conflicted `git pull` gives
  the same. A user's `git merge --no-commit feature` (nothing conflicted, so as first designed the
  merge check would have committed it) and a merge of another remote's branch give neither.
  `git2r::descendant_of()` is `FALSE` for a commit and itself. Also seen, and not used: git2r writes
  `.git/MERGE_MSG` ("Merge remote-tracking branch 'refs/remotes/origin/main'"), a line appended to it
  survives `git checkout MERGE_HEAD --` and `git add`, and `git2r::commit()`, `git commit` and
  `git merge --abort` each remove it.
- **A pull with the user's files in the way, 2026-10-31** (`research/dirty_pull_probe.R`, git2r
  0.36.2 and git 2.54.0; reproduced independently by the reviewer on git2r 0.33.0). After a fetch,
  `git2r::merge()` of the upstream does nothing, raises no error and returns `conflicts = NULL` (and
  `fast_forward = NULL`, `sha = NULL`) when a file the incoming commits change is modified or staged,
  or an untracked file sits where they add one, with or without commits of the clone's own; HEAD does
  not move and no `MERGE_HEAD` is written. A modified file the commits do not touch does not block
  (fast-forward, `sha = NA`). Through datom: with a plain `git stash`, the untracked file stays,
  `datom_pull()` reports success and the clone is still behind. With `git stash -u`, `datom_pull()`
  catches up; `git stash pop` then reports a conflict (markers in the file, stash kept) or refuses to
  restore an untracked file ("already exists, no checkout", stash kept). With an unresolved pop
  conflict in the index, `git2r::commit()` of other files fails ("cannot create a tree from a not
  fully merged index"), and `git2r::add()` of the conflicted file followed by a commit commits the
  conflict markers. Also checked: a `git2r::push()` of a branch behind its remote of the same name is
  rejected ("contains commits that are not present locally"); a push of a branch with another name
  succeeds and creates that branch on the remote. (That last fact is now the publish-branch rule's
  concern, not R3.10's; 2026-11-03.)
- **No datom command writes `{name}/.metadata/` in a clone, 2026-10-30** (a real write of `dm` three
  times, then a listing of the clone): only `metadata.json` and `version_history.json`; snapshots go
  straight to storage. 0.2.0's metadata-only route publishing a hand edit leaves a stored
  `metadata.json` whose version no history entry, manifest row or snapshot records (probed the same
  day).

Not yet traced, each resolved in the task that needs it:
1. Unstaging chosen paths with `git2r::reset(repo, path = ...)` after a break between staging and
   committing.
2. ~~Real S3: `IfNoneMatch = "*"` refused with 412, and `ChecksumSHA256` with `ChecksumType`
   `FULL_OBJECT` returned by `head_object`.~~ **Settled 2026-10-30 in task 1**, on all three paws
   version pairs: see "Real S3, 2026-10-30" under Proven above.
3. Heal's step d when the stored manifest cannot be read for a reason other than absence (the storage
   reader can rebuild it and warn); which of those outcomes counts as "behind".
4. Whether any existing test asserts the old order or the manifest-first mirror and needs rewriting
   (the test "nothing reaches storage when the git push fails" in `test-write-set.R` does).
5. Message wording for reset, publish and R3.6, and whether they are `cli` alerts or warnings with a
   class a test can count. Since 2026-10-31 also: the condition classes of the new stops (another
   artifact's unfinished work, a pull that did not catch up, a stored version the clone lacks, a
   skipped manifest upload).
6. How `.datom_resolve_manifest_conflict()` gets what the format check reads (the clone path, and the
   writer floor a connection carries) when its caller holds no connection: `.datom_git_pull()` takes
   a path, and the migration pull inside `datom_get_conn()` runs before the connection exists.
   Settled in task 5 (added 2026-10-31).

## 11. Correctness properties (what the tests pin)

| # | Property | Requirement |
|---|---|---|
| P1 | For each step of a write, a break there followed by the same write leaves a reader reading the new version and the stored manifest naming it | R2.1, R7.1 |
| P2 | A stored data file's bytes never change after it is first stored, on both backends | R1.2, R7.3 |
| P3 | The hash a version records equals the hash of the bytes stored at its address | R1.3 |
| P4 | No command publishes a file that was never committed | R3.1, R5.1 |
| P5 | A clone that was behind GitHub before its pull never publishes over a newer stored version | R3.3, R3.7, R7.6 |
| P6 | A manifest-only conflict is resolved, at the pull or by the merge check once the user has resolved every other file, and every row of the rebuilt manifest agrees with its artifact's files; any other conflict publishes nothing; a merge that is not of the remote branch is committed only through `datom_pull(conn, finish_merge = TRUE)`; and no rebuild writes before the format check has passed | R3.8, R3.9, R7.7 |
| P7 | The manifest is the last thing any route publishes | section 1 |
| P8 | Files datom does not own are never reset | R3.1, R3.5 |
| P9 | A failed fetch at the start leaves the clone, git and storage unchanged | DD1, R3.7 |
| P10 | After a publish lands behind a colleague's newer one, the table's next write or `datom_validate(fix = TRUE)` in an up-to-date clone leaves storage at git's latest, and any other write stops naming that fix (amended 2026-10-31) | DD4 |
| P11 | `datom_validate()` reports `manifest_mismatch_s3`, naming the fix, when an artifact's stored manifest row names a different version from the one recorded for its stored `metadata.json`, and `fix = TRUE` clears it; it is not reported for a hand edit published by 0.2.0, nor on a consistent store | R5.5, R7.8 |
| P12 | On a clean, current, fully published clone, nothing before a command's own work writes to the clone, git or storage | D14 |
| P13 | A write never changes another artifact's files, git state or stored documents: on another artifact's unfinished work it stops before changing anything, naming `datom_validate(fix = TRUE)` (added 2026-10-31) | R3, D14 principle 8 |
| P14 | No command publishes anything when its pull did not catch up, or when storage names a version of the artifact that the clone's history does not contain; and no write uploads a manifest while another artifact's row disagrees with storage (added 2026-10-31) | R3.7, R3.10 |

Each new guard's test is probed once by removing that guard alone (conventions item 2a).

## 12. Residual failure modes

Carried from R8, and into `dev/engineering-notes.md` at completion.

| Failure mode | What the user sees | Guarded / documented |
|---|---|---|
| A write broke before its commit, leaving its data file in storage with no version naming it | Nothing; costs space. For sensitive data, the bytes are in the bucket although no version exists | Documented in `?datom_write` |
| A project a released datom already broke | A re-run or the repair can still leave its readers failing | Documented in `NEWS.md` |
| A merge conflict outside the manifest (two people wrote the same artifact, or the user's own files) | The command stops before any publish; no version is published, though this write's data file may already be in storage, unnamed. The message, repeated by the merge check in every later datom command until the conflict is resolved (R3.9), says: take the remote copy of all of each conflicted artifact's datom files (`git checkout MERGE_HEAD -- ...`, names filled in), resolve your own files and `git add` them, re-run. datom then rebuilds the manifest and finishes the merge. A merge started outside datom, of anything but the remote branch, is never finished unasked: every command stops, and `datom_pull(conn, finish_merge = TRUE)` or `git merge --abort` ends it | Guarded by existing tests, R7.7, and the merge check's tests (tasks 4a, 5, 8); #105 owns a recovery command |
| Two R sessions writing through one clone at once | Not supported | Documented |
| An S3-compatible service that ignores conditional writes, two writers, same new content, same moment | One version's reads are refused by the hash check. Loud | Documented beside `endpoint` |
| An S3-compatible service that rejects `IfNoneMatch` or `ChecksumSHA256` (400 or 501) | Every write stops at its first step with the service's own error; nothing changes. No fallback (owner, 2026-10-28). paws alone can trigger this: from `paws.common` 0.9.0, every upload carries a checksum by default, datom's metadata uploads included, so such a service can fail even without datom's new arguments | Documented beside `endpoint` |
| An S3 409: a teardown deletes a data file while a write uploads it | The write stops with the usual upload error before the clone changes; a re-run finishes | Documented in `dev/engineering-notes.md` |
| A local store on a file system without hard links, two writers, same new content, same moment | The second move replaces the first file; one version's reads are refused by the hash check. Loud | Documented in `?datom_store_local` |
| Someone edits a datom-owned file by hand (an artifact's `metadata.json`, `version_history.json` or `set.json`, or `.datom/manifest.json`) (requirements D13) | A write of that artifact with data resets the edit and says so; any other write, and `datom_write(conn, name =)`, stops, naming the artifact and `datom_validate(fix = TRUE)`, which resets it; `datom_write(conn, name =)` no longer commits it. Custom metadata is changed with `datom_write(conn, data, name, metadata = )` | Guarded (task 4a's test); documented in `?datom_write` and `NEWS.md` |
| A crash during a local upload leaves a temporary file (`.{name}.tmp`) beside the data file | Nothing for readers. A leftover after the link costs no space (a hard link shares the bytes); one left mid-copy takes space. `datom_storage_list()` shows it; copy and verify skip it | Guarded (a test that copy and verify skip it); documented in `?datom_store_local` |
| Two people publish the same table within seconds, and the older publish lands last (DD4) | Readers get the superseded version as current until the table's next write or `datom_validate(fix = TRUE)` republishes it; any other write in an up-to-date clone stops and names that fix. Reads that name a version are unaffected | Guarded (P10); documented in `dev/engineering-notes.md` |
| A write finds another artifact's unfinished work (requirements D14 principle 8) | The write stops before changing anything, naming the artifact, what was found and `datom_validate(fix = TRUE)`. After a storage failure on one table, every write of another table stops until someone runs the fix or re-runs that table's write. Accepted by the owner (2026-10-31): heal is needed in a small share of runs, and acting on another artifact is where its edge cases came from | Guarded (tasks 4a, 4b); documented in `?datom_write`, `?datom_write_set`, `?datom_sync` |
| The user's own uncommitted or untracked files are in the way of the commits a pull brings in | The command stops before changing anything and gives the `git stash -u` recipe, including resolving what `git stash pop` reports | Guarded (task 4a: the caught-up check); the way out is in the message |
| Storage names a version of an artifact that this clone's history does not contain (a publish seconds old; or storage edited by hand, or commits removed from GitHub, S8) | A write stops before changing anything: re-run, and if it persists, `datom_validate(fix = TRUE)`, which publishes the clone's version and names the stored version it replaced (an artifact the clone lacks loses its stored row, and the repair says so) | Guarded (task 4b: the containment check and the repair's override, R3.10) |
| A clone with no upstream branch (init failed to set it) | Heal pushes before publishing; a clone that is behind has that push rejected, with a message saying to run `datom_pull(conn)`; a push that succeeds sets the upstream | Guarded (task 4a: the rejected-push message) |
| A write's push brings in a teammate's commit whose version is not in storage yet | The write skips its manifest upload and says so, naming `datom_validate(fix = TRUE)`; its own documents are published. The next write of another artifact stops and names the same fix | Guarded (task 4b, R3.10) |
| The same, with the two publishes crossing so the stored manifest names the newer version and the stored metadata holds the older one (DD4) | Readers get the superseded version, and heal does not notice, until the table's next write or `datom_validate(fix = TRUE)` | Reported by `datom_validate()` as `manifest_mismatch_s3`, naming the fix; fixed by `datom_validate(fix = TRUE)` or the table's next write (section 6, P11) |
| A version's snapshot is missing from storage (no route in this spec can cause it: every route uploads the snapshot before `metadata.json`; left by 0.2.0's write interrupted between `metadata.json` and the snapshot, D7, or by storage losing a file outside datom) | Not reported by `datom_validate()`, which checks only that `metadata.json`, the history and the data file exist. `datom_read(version = )` of that version fails. From task 7, `datom_validate(fix = TRUE)` restores the **current** version's snapshot from the clone's `metadata.json` (section 6); an older version's is restored by nothing | Not guarded. Documented in `dev/engineering-notes.md` at completion; the check, and restoring older snapshots from git, go to a follow-up issue (draft: `draft-issue-validate-completeness.md`) |
| 0.2.0's `datom_write(conn, name =)` published a hand edit of `metadata.json` | The stored `metadata.json` describes a version that no history entry, manifest row or snapshot records. Readers are told the previous version, and a read pinned to it returns the pre-edit metadata. `datom_validate()` reports nothing | Not guarded (D7). D13 and task 4b stop new cases. A publish from the clone writes one extra snapshot under the edited document's own version, which nothing names; the previous version's snapshot is never touched (section 4, step d). Not reported as `manifest_mismatch_s3`, since its recorded version and its manifest row agree. Goes to the follow-up issue |
| One of datom's files, committed outside datom, does not parse | Every command that reads that file stops with one short message naming the file and saying to restore all of that artifact's datom files from a commit where they parse, `git commit`, and re-run: heal (every write, and the repair) while the artifact's publish is pending, and a write of that artifact at any time | Guarded (task 4b's tests, through the shared reader). The way out is in the stop message itself (section 4, step d) |
| A file put at a data address by hand, adopted by a re-run | Its content is read without a content check | Documented in `dev/engineering-notes.md`; not checked |
| A teammate still on a released datom (D11) | An upgraded teammate's write can publish their data-less version | Documented in `NEWS.md` |
| GitHub unreachable at the start of a command (DD1) | The command stops with a message and changes nothing; the user re-runs when online | Guarded (P9); documented in `?datom_write` |

## 13. Tasks

The task list is `tasks.md`. The outline that stood here was replaced by it on 2026-10-28, so the
two cannot disagree.
