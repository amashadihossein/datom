# Design -- interrupted commands finish on a re-run

**Status**: **Approved by the owner on 2026-10-28.** Requirements approved the same day
(`requirements.md`). Design decisions DD1-DD4 are in section 9. The routine and its file were named
`heal` by the owner on 2026-10-28 (first drafted as "settle" in `R/finish.R`).

Reviews by another agent, evaluated with the owner on 2026-10-28, added: the hard-link upload on a
local store and the whole-file condition on S3's stored checksum (section 3); recognisable temporary
names on a local store, skipped by storage copy and verify (section 3); and the `metadata_stale_s3`
status in `datom_validate()` (section 6; requirements R5.5 and R7.8 amended). A check before every
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
**Read first**: `requirements.md` (terms, findings, decisions D1-D13, requirements R1-R9). This
document says how: which functions change, in which files, and how each command runs.

## 1. The shape in one picture

Every command that changes things starts with the same routine, **heal**, then does its own work in
the new order. Heal is datom's self-healing step: it is where "a re-run finishes" and "another
command finds unfinished work" both live, so there is one implementation of them, not one per
command.

```
command(conn, ...)
  every refusal check that needs no storage state heal can change      (see below)
  heal(conn, artifact = <names this command will write>)              R2.4, R3.1-R3.4, R3.7, R3.8
    a. reset datom files that never committed   (local only)
    b. pull: fetch, then merge                  (conflict only in the manifest -> rebuild it)
    c. forward-compat entry check again         (the pull may have brought new documents)
    d. push unpushed commits, then publish      (artifacts whose stored manifest row is behind git)
  change detection, and the table-or-set check
  own work, new order (a write):
    1. data file -> storage, only if absent     R1.1-R1.3
    2. clone files                              (metadata, history, manifest row, set.json)
    3. commit
    4. push (pulls first, as today; R3.8 applies)
    5. snapshot, history, then metadata.json -> storage   (metadata.json last)
    6. manifest -> storage                      (always last)

  every publish (heal's d, a write's 5-6, the repair) goes through one function,
  .datom_publish_artifacts()
```

**Invariant this rests on: the manifest is always published last.** Every route that writes storage
publishes an artifact's documents first and the manifest after. So a stored manifest row that matches
git means that artifact's documents are current too, and heal can find all unpublished work with one
read of the stored manifest (R3.4). Today `.datom_sync_data_metadata()` writes the manifest **first**;
that order is reversed (section 6). One ordering of two publishes landing at once breaks this
invariant; it is a row of section 12. Within an artifact's documents, `metadata.json` goes last for
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
was already committed, or resets work that never committed, as any later command would, so a refusal
there undoes nothing. `datom_sync()` follows the same rule: the preview's columns and the `rio`
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
| `R/heal.R` | `.datom_heal(conn, artifact = NULL)` | new | Steps a-d of section 1. `artifact` names the artifacts the command is about to write (several for `datom_sync()`, none for the repair), which sets the wording of reset messages (section 4). Returns what it reset and what it published, for the caller's messages |
| `R/heal.R` | `.datom_reset_unfinished(conn)` | new | Step a. Finds datom-owned files that differ from the last commit and puts them back (section 4) |
| `R/heal.R` | `.datom_unpublished_artifacts(conn, stored)` | new | Names the artifacts whose committed version readers cannot see: in unpushed commits, or whose clone manifest row differs from the stored one |
| `R/heal.R` | `.datom_publish_artifacts(conn, names)` | new | **The one publish path.** For each name, the clone's snapshot, history and `metadata.json` (last) through `.datom_push_metadata_s3()`; then the manifest, last, and only if every artifact's documents were published (section 6). A publish from the clone names the recorded version and writes the snapshot only when the document hashes to it (section 4, step d). Heal's step d, a write's steps 5-6, the metadata-only route and the repair all go through it |
| `R/heal.R` | `.datom_resolve_manifest_conflict(path)` | new | R3.8: rebuilds `.datom/manifest.json` after a merge whose only conflict it is, stages it, commits the merge (section 5) |
| `R/heal.R` | `.datom_pushed_artifacts(path)` | new | Artifacts touched by commits the remote lacks; feeds the R3.6 message and step d |
| `R/manifest-rebuild.R` | `.datom_manifest_row(meta, history, member_count)` | new, extracted | The row-building half of `.datom_rebuild_manifest_entry()`, which keeps its storage reads and calls it. The clone-side rebuild in section 5 calls it too, so the two rebuilds cannot drift |
| `R/utils-storage.R` | `.datom_storage_upload_absent(conn, local_path, key)` | new | R1.2: check, then upload only if absent. Returns `"uploaded"` or `"exists"` |
| `R/utils-storage.R` | `.datom_storage_object_sha256(conn, key)` | new | R1.3: the SHA-256 (hex) of the bytes stored at `key` |
| `R/utils-s3.R` | `.datom_s3_upload_absent()`, `.datom_s3_object_sha256()` | new | S3 halves (section 3) |
| `R/utils-local.R` | `.datom_local_upload_absent()`, `.datom_local_object_sha256()` | new | Local halves (section 3) |
| `R/utils-local.R` | `.datom_is_temp_key(key)` | new | Recognises the temporary file names a local upload uses (section 3) |
| `R/storage.R` | `datom_storage_copy()`, `datom_storage_verify()` | changed | Skip temporary files left by an interrupted local upload; `datom_storage_list()` is unchanged |
| `R/utils-git.R` | `.datom_git_pull(path, pat)` | changed | On a conflict whose only file is `.datom/manifest.json`, calls `.datom_resolve_manifest_conflict()` instead of aborting. Every other conflict aborts as today |
| `R/utils-git.R` | `.datom_git_head_file(path, rel)` | new | A file's content as committed in HEAD (`git2r::revparse_single(repo, "HEAD:<rel>")`) |
| `R/utils-git.R` | `.datom_check_git_current()` | deleted | Its only caller, `datom_sync()`, heals instead (DD3), and its offline "warn and carry on" is replaced by DD1. The comments naming it in `datom_repo_commit()`, `.datom_git_ahead()` and `.datom_git_push()` are rewritten |
| `DESCRIPTION` | `paws.storage` | changed | `(>= 0.8.0)`: the first release with both `IfNoneMatch` (since 0.7.0) and `ChecksumType` (since 0.8.0), checked against the CRAN sources |
| `R/read_write.R` | `datom_write()` | changed | Heals first; data file before clone files; internal `.healed` argument so `datom_sync()` heals once per call (R3.7) |
| `R/read_write.R` | `.datom_commit_and_mirror()` | changed | Loses its `upload` argument: the data file is already stored. The table write stops passing it in task 2; the argument goes in task 3, when the set write stops too. Commits and pushes, then publishes through `.datom_publish_artifacts()` |
| `R/read_write.R` | `.datom_push_metadata_s3()` | changed | Uploads the snapshot, then the history, then `metadata.json` last (section 1) |
| `R/read_write.R` | `.datom_resolve_parquet_sha()`, `.datom_resolve_document_sha()` | changed | The R1.3 decision, including the stored-file case, and now performing the upload (section 3) |
| `R/set.R` | `datom_write_set()` | changed | Payload built in a temp file; uploaded first; the clone's `set.json` takes the stored bytes when they differ (R1.5) |
| `R/utils-sha.R` | `.datom_sync_metadata()` | changed | Its opening pull is replaced by heal; it publishes through `.datom_publish_artifacts()`. It no longer commits a hand edit of the table's `metadata.json`: heal resets it first (requirements D13), so the route publishes what is committed |
| `R/sync.R` | `datom_sync_manifest()` | changed | Compares against HEAD's manifest; `unpublished` status (section 7) |
| `R/sync.R` | `datom_sync()` | changed | Heals once instead of `.datom_check_git_current()`; `unpublished` rows are reported as published by heal |
| `R/sync.R` | `.datom_sync_data_metadata()` | changed | Heals (so it pushes first, R5.2), restores each set's payload where storage lacks it, then publishes every artifact through `.datom_publish_artifacts()`, manifest last (section 6) |
| `R/sync.R` | `.datom_read_manifest()` | changed | A third scope, `"head"`, reading HEAD's copy through `.datom_git_head_file()` with the same schema check and upgrade |
| `R/sync.R` | `.datom_restore_set_payload()` | changed | Uploads through `.datom_storage_upload_absent()` |
| `R/sync.R` | `.datom_sync_one_artifact()` | deleted | Its snapshot loop copied from a clone `{name}/.metadata/` folder no datom command writes, so it never published a snapshot; the repair uses `.datom_publish_artifacts()` and calls `.datom_restore_set_payload()` directly (section 6) |
| `R/validate.R` | `datom_validate()` | changed | The fix now pushes and reports per artifact (R5.3); a fetch first, for the new status (R5.5, section 6) |
| `R/validate.R` | `.datom_validate_one_table()` | changed | Reads the stored `metadata.json` and reports `metadata_stale_s3` when its version differs from the one in the clone's last commit (section 6) |
| `R/repo.R` | `datom_repo_commit()` | changed | `.datom_reset_unfinished()` before staging (R3.5); the R3.6 message when it pushes |
| `R/repo.R` | `datom_repo_push()`, `datom_repo_attach_governance()`, `datom_repo_set_data_store()` | changed | The R3.6 message around their push |
| `R/conn.R` | `datom_init_repo()` | changed | Finishes a half-initialised folder (section 8) |

Nothing changes in `R/utils-path.R` (keys), `R/forward-compat.R`, the metadata builders or any
document shape. No field is added to any datom-owned document, so no schema number moves and the
vocabulary lists are untouched.

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
  IfNoneMatch = "*", ChecksumSHA256 = <base64 of the raw SHA-256>)`. A refusal because the key
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

## 4. Heal, step by step

`.datom_heal(conn, artifact)`.

**What heal repairs, and what it leaves** (its docstring says both):

| Heals | Leaves |
|---|---|
| datom's own files from a write that broke before its commit (reset) | a merge conflict outside the manifest (#105) |
| a clone behind GitHub (pulled) | damage a released datom left behind (D7, D11) |
| a merge conflict only in the manifest (rebuilt) | a file someone put in storage by hand |
| committed work GitHub or storage lacks (pushed, then published) | anything when GitHub cannot be reached: it stops instead (DD1) |
| a stale publish by another clone, the next time it runs (section 4, last part) | the one crossing of two publishes in section 12, which `datom_validate()` reports and its fix clears |

**a. Reset what never committed** (`.datom_reset_unfinished()`; R2.4, R3.1). "Datom-owned files" are,
for each artifact directory, `metadata.json`, `version_history.json` and `set.json`, plus
`.datom/manifest.json`. Nothing else: not `.datom/project.yaml`, not `.datom/governance.json`, not
`include_paths`, not `input_files/`.
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
  | Any other artifact | A warning: "Reset an unfinished write of `lb` that stopped before its commit. Run that write again to save it." |

  Whether these are `cli` alerts or warnings with a class a test can count is settled in task 4a
  (section 10, item 5).

**b. Pull** (R3.7): `.datom_git_pull()`, i.e. fetch then merge, with R3.8 inside it. A conflict
elsewhere aborts before storage changes. A failed fetch stops the command before it changes anything,
with a message saying datom could not reach the remote (DD1).

**c. Check the documents again**: `.datom_check_write_entry(conn, artifact)`, because the pull can
bring a manifest or metadata from a newer datom. Same reasoning as the existing re-check in
`.datom_sync_metadata()`.

**d. Push and publish** (R3.2-R3.4):
- If `.datom_git_ahead()` is above 0, or `NA`: note `.datom_pushed_artifacts()`, then
  `.datom_git_push()`.
- Read the stored manifest once (`.datom_read_manifest(conn, "storage")`; absent means every artifact
  is unpublished). `.datom_unpublished_artifacts()` = the pushed artifacts, plus every artifact whose
  clone row's `current_version` differs from the stored row's. After the pull the clone holds at
  least what GitHub holds, so a difference found here means storage is behind this clone (R3.3).
- `.datom_publish_artifacts()` for those names, manifest last, and only if every artifact's
  documents were published (section 6); when heal's publish fails, the command stops before its own
  work. A set's payload is not re-uploaded here: under D1 it is in storage before its commit exists.
- **Which version a publish from the clone names** (follow-up review, owner, 2026-10-30). Heal, the
  metadata-only route and the repair publish an artifact that is already committed, so they take its
  version from the clone's record, `.datom_recorded_current_version()` of its `metadata.json` and
  history, which `datom_read()` and the manifest rebuild already use and which never recomputes.
  The snapshot is written only when `.datom_compute_metadata_sha()` of the same document agrees.
  They disagree for a hand edit that 0.2.0's metadata-only route committed (section 12), after a
  future change to which fields count toward a version, or when the history records no version for
  the document. Then the publish skips that artifact's snapshot and warns, naming it, and still
  publishes its `metadata.json` and history, which match what is committed. Writing the document
  under the recorded key would overwrite that version's correct snapshot with content that does not
  hash to it. A skipped snapshot counts as published for the manifest rule, or one such artifact
  would stop the manifest for every later repair. A write's own publish passes the version it
  computed.
- Heal's publish passes no commit id, so the stored history works it out from git: the first commit
  that produced the version (`R/version-commit.R`). A write's own publish passes the commit it just
  made; once heal runs first, a re-run makes no second commit, so the two agree (design spot-check
  before task 2, owner, 2026-10-30).

The command's own work then runs against a clone that is clean, current and fully published, so
today's change detection (`.datom_has_changes()`, against storage) answers correctly, and a re-run
whose own write already finished reports `none` (R2.1). A break at step 6 is caught by step d of the
next run (R2.3).

**Two publishes at once** (DD4). A colleague can publish after this clone's pull and before its
publish. Reproduced on today's code (`research/publish_race_probe.R`): you push `dm` v2; before your
publish runs, a colleague pulls, writes v3, pushes and publishes it; your publish of v2 then lands, and
readers get v2 although GitHub's latest is v3. datom does not check for this before publishing. The
current version is a pointer that the owners move (a write, or a revert to earlier content), not a
claim that the newest is best; every reproducible read names its version (`version =`, a set's
members, lineage parents) and is unaffected. What matters is that the pointer ends up where git says,
and the next datom command in any up-to-date clone does that: its heal sees the stored manifest row
behind its own and republishes. One interleaving escapes it: when the two publishes cross so that the
stored manifest names the newer version while the stored metadata holds the older one, step d sees
no difference. `datom_validate()` reports that case as `metadata_stale_s3` (section 6), and it waits
for the table's next write or `datom_validate(fix = TRUE)` (section 12).

**Who calls heal, and with which `artifact`**: heal runs in exactly one place per route, so no route
fetches twice or reads the stored manifest twice (R3.4), and no prompt is answered after heal has
acted (second review of `tasks.md`, owner, 2026-10-28):

| Route | Where heal runs | `artifact` |
|---|---|---|
| `datom_write(conn, data, name)` | in `datom_write()`, after the checks that run before heal (section 1) | the table's name |
| `datom_write(conn, name =)`, the metadata-only route | inside `.datom_sync_metadata()`, replacing its pull | none: the route never writes the table again, it publishes what is committed, so the table's own uncommitted files get the warning, not the "writing it again now" message. A hand edit of them is reset like any unfinished write (requirements D13) |
| `datom_write(conn)` and `datom_validate(fix = TRUE)` | inside `.datom_sync_data_metadata()`, after its confirmation prompt | none: it never redoes a write |
| `datom_write_set()` | in `datom_write_set()`, after its checks | the set's name |
| `datom_sync()` | once per call, before the first table | every table it is about to write; then `datom_write(.healed = TRUE)` per table |

`datom_write()` itself does not heal on the two routes without data: it hands them to those helper
functions before anything else runs. `datom_repo_commit()` calls step a only (R3.5). The four push
commands call none of it (D10).

## 5. A conflict only in the manifest (R3.8)

Inside `.datom_git_pull()`, after `git2r::merge()` reports conflicts: if the conflicted paths are
exactly `.datom/manifest.json`, call `.datom_resolve_manifest_conflict(path)`:

1. Start from the remote's copy (`MERGE_HEAD:.datom/manifest.json`). Its top level, including
   `project_name` and any field this build does not know, is kept as it is.
2. Find the artifacts the local side changed since the merge base (a diff of the two trees). Both
   sides cannot have changed the same artifact here: that would also conflict in its
   `version_history.json`, and the conflict would not be manifest-only.
3. For each, rebuild its row from the merged clone's files with `.datom_manifest_row()`, carrying
   unknown row fields forward from the local row with `.datom_carry_unknown_fields()`.
4. Recompute `summary`, set `updated_at` to now, write the file, `git2r::add()`, and commit with the
   message "Merge remote changes (manifest rebuilt by datom)".

Rebuilding only the local side's rows from the clone, on top of the remote's copy, gives the same
document as rebuilding every row, with less to read; rows the local side did not touch are already
what the remote's artifact files say.

Probed (`research/merge_completion_probe.R`): after staging the rewritten file the conflict clears,
`git2r::commit()` makes a two-parent commit and removes `MERGE_HEAD`, the push lands, and a fresh
clone sees every table.

## 6. The repair and the mirror-everything route (R5)

`.datom_sync_data_metadata(conn, .confirm)` becomes:

```
heal (reset, pull, push, publish what is behind)
for each artifact:  restore a set's payload if storage lacks it    (data file first)
for each artifact:  .datom_publish_artifacts(): snapshot, history, metadata.json last
once, at the end:   the manifest                                   (only if every artifact published)
```

Because it republishes every artifact rather than only those whose manifest row differs, it also
corrects the crossed-publish case of section 4. Going through `.datom_publish_artifacts()` is also
what makes the repair publish in the requirements' sense ("Published" includes the version snapshot;
R5.2): the old per-artifact copy, `.datom_sync_one_artifact()`, copied snapshots only from a
`{name}/.metadata/` folder in the clone, which no datom command writes (confirmed 2026-10-30 by a
real write), so it never published one. It is deleted; the repair calls
`.datom_restore_set_payload()` directly for a set's payload. Older versions' snapshots are not
rebuilt here: that needs each version's `metadata.json` from the commit that introduced it, and no
route in this spec leaves one missing (section 12, follow-up issue).

The confirmation prompt on the `datom_write(conn)` route says it may push. `datom_validate(fix =
TRUE)` reports per artifact what was reset, pushed and published (R5.3).

**A new status, `metadata_stale_s3`** (R5.5, amended 2026-10-28). Without it, `datom_validate()`
says "All checks passed" on the crossed publish, because today it only checks that each stored file
exists. `.datom_validate_one_table()` now also reads the stored `metadata.json` (one small read per
artifact, in validate only) and compares its version with the version in the clone's **last commit**,
read through `.datom_git_head_file()` (one local git read per artifact); a difference is
`metadata_stale_s3`. Not the working-tree file: a write that broke before its commit leaves a
version there that was never committed, and calling storage stale would misdiagnose an unfinished
write that `fix = TRUE` resets rather than publishes. To keep a behind clone from reporting a
colleague's newer version as stale, `datom_validate()` fetches first, without merging: when the
clone is behind the remote it skips the comparison and says to run `datom_pull()`, and when the fetch
fails it warns and skips the comparison, both as the scan does (section 7). With `fix = TRUE`, heal has
already pulled, so the comparison runs on a current clone and the repair then clears it.
`.datom_validate_unfixable_tables()` does not list the new status: the repair fixes it.

**Order within the repair** (follow-ups to the design spot-check before task 2, owner, 2026-10-30).
A set's payload first (data file first), then each artifact's snapshot, history and `metadata.json`
last, then the manifest. The stored `metadata.json` is what change detection and `metadata_stale_s3`
read as the sign that a version is published. If the stored manifest already matches git, which is
when the repair is usually run, a break after an early `metadata.json` would leave a missing history
or snapshot that no check reports.
With `metadata.json` last, a repair that breaks while publishing a version newer than the stored one
leaves the old `metadata.json` in storage, so `datom_validate()` still reports `metadata_stale_s3`
and the next `fix = TRUE` finishes it. When the stored `metadata.json` is already current and the
repair is only filling in a missing snapshot, nothing reports a break, because `datom_validate()`
does not check snapshots (section 12; wording fix from the same reviewer, owner, 2026-10-30).

**One artifact failing does not publish the manifest.** The repair carries on past an artifact that
fails, marking it `"error"`, as today. But a manifest published after that failure would name the
failed artifact's new version while its stored `metadata.json` is old, and heal, which compares
manifest rows, would then see nothing behind. So `.datom_publish_artifacts()` publishes the manifest
only if every artifact's documents were published (section 4); the repair reports each failure,
skips the manifest, and says to re-run. An artifact whose snapshot is skipped because its
`metadata.json` does not match its recorded version (section 4) counts as published.

## 7. The scan and the sync (R4)

`datom_sync_manifest()`:
- reads HEAD's manifest through `.datom_read_manifest(conn, "head")` (R4.1);
- fetches (no merge; the scan changes nothing), then computes `unpublished` as in heal's step d.
  If the fetch fails it warns and counts only artifacts in unpushed commits. If the clone is behind
  after the fetch, it does not compare rows against storage (the stored ones may be a colleague's
  newer versions) and says to run `datom_pull()` (R4.2);
- status order: `unsupported_format`, `new`, `changed`, `unpublished`, `unchanged`.

`datom_sync()` replaces `.datom_check_git_current()` with one heal (see DD3), which publishes every
`unpublished` row; those rows come back with `result = "success"` without an import (R4.3).

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
| DD2 | **R3.8 sits inside `.datom_git_pull()`**, so `datom_pull()`, the four push commands, and the migration pull inside `datom_get_conn()` (in `.datom_resolve_data_location()`, `R/ref.R`) also resolve a manifest-only conflict, not just the commands in R3. That last caller pulls only on a governed project whose data moved; there, getting a connection can make a local merge commit and says so, where today it aborts and leaves the clone mid-merge (added from the review of `tasks.md`, owner, 2026-10-28) | **Decided 2026-10-28: yes** | Commands outside R3 rewrite the manifest during a merge, and say so. This happens only when the clone holds an unpushed commit that changed the manifest (in practice a datom write whose push failed), a colleague pushed a datom write since, and the manifest is the only conflicted file. A fast-forward, or a merge of commits that never touched the manifest, rebuilds nothing. The alternative was a second pull function for R3 alone, leaving `datom_pull()` to stop on a conflict a write would resolve by itself |
| DD3 | **`datom_sync()` pulls a clone that is behind instead of refusing.** Today it stops with "pull first" (`.datom_check_git_current()`), the only command that does | **Decided 2026-10-28: pull** | A preview built before the pull can be stale. Probed (`research/stale_preview_probe.R`): when a colleague already imported the same file, the stale `new` row is re-read, the write finds no change and stores nothing, and the row reports `success`. Today that row's line also says "synced (new)", which claims work that did not happen; task 6 makes it say the table was already up to date. A conflict outside the manifest still stops the sync before storage changes |
| DD4 | **No check before publishing.** Every publish writes git's latest state as the publishing clone sees it; a publish that lands after a colleague's newer one is corrected by the next datom command in any up-to-date clone (section 4, "Two publishes at once") | **Decided 2026-10-28: no check** | Readers can get a superseded current version until that next command. Set aside: a check before every publish that skipped an artifact whose stored version the clone had never seen, with the manifest merged row by row. It made the pointer right a few seconds sooner in one race, at the cost of code, tests and a blind spot (a colleague's revert to an older version looks to it like stale storage). The current version is a pointer the owners move, and reproducible reads name their version, so the sooner-by-seconds was not worth it |

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
   class a test can count.

## 11. Correctness properties (what the tests pin)

| # | Property | Requirement |
|---|---|---|
| P1 | For each step of a write, a break there followed by the same write leaves a reader reading the new version and the stored manifest naming it | R2.1, R7.1 |
| P2 | A stored data file's bytes never change after it is first stored, on both backends | R1.2, R7.3 |
| P3 | The hash a version records equals the hash of the bytes stored at its address | R1.3 |
| P4 | No command publishes a file that was never committed | R3.1, R5.1 |
| P5 | A clone that was behind GitHub before its pull never publishes over a newer stored version | R3.3, R3.7, R7.6 |
| P6 | A manifest-only conflict is resolved and the rebuilt manifest names every artifact of both sides; any other conflict leaves storage unchanged | R3.8, R7.7 |
| P7 | The manifest is the last thing any route publishes | section 1 |
| P8 | Files datom does not own are never reset | R3.1, R3.5 |
| P9 | A failed fetch at the start leaves the clone, git and storage unchanged | DD1, R3.7 |
| P10 | After a publish lands behind a colleague's newer one, the next datom command in an up-to-date clone leaves storage at git's latest | DD4 |
| P11 | `datom_validate()` reports `metadata_stale_s3` when an artifact's stored `metadata.json` holds a different version from the one in the clone's last commit, and never on a clone that is only behind the remote, nor for a write that broke before its commit; a failed fetch skips the comparison with a warning | R5.5, R7.8 |

Each new guard's test is probed once by removing that guard alone (conventions item 2a).

## 12. Residual failure modes

Carried from R8, and into `dev/engineering-notes.md` at completion.

| Failure mode | What the user sees | Guarded / documented |
|---|---|---|
| A write broke before its commit, leaving its data file in storage with no version naming it | Nothing; costs space. For sensitive data, the bytes are in the bucket although no version exists | Documented in `?datom_write` |
| A project a released datom already broke | A re-run or the repair can still leave its readers failing | Documented in `NEWS.md` |
| A merge conflict outside the manifest (two people wrote the same artifact, or the user's own files) | The command stops before storage changes; the message says to keep the remote copy of datom's files and re-run | Guarded by existing tests and R7.7; #105 owns the recovery command |
| Two R sessions writing through one clone at once | Not supported | Documented |
| An S3-compatible service that ignores conditional writes, two writers, same new content, same moment | One version's reads are refused by the hash check. Loud | Documented beside `endpoint` |
| An S3-compatible service that rejects `IfNoneMatch` or `ChecksumSHA256` (400 or 501) | Every write stops at its first step with the service's own error; nothing changes. No fallback (owner, 2026-10-28). paws alone can trigger this: from `paws.common` 0.9.0, every upload carries a checksum by default, datom's metadata uploads included, so such a service can fail even without datom's new arguments | Documented beside `endpoint` |
| An S3 409: a teardown deletes a data file while a write uploads it | The write stops with the usual upload error before the clone changes; a re-run finishes | Documented in `dev/engineering-notes.md` |
| A local store on a file system without hard links, two writers, same new content, same moment | The second move replaces the first file; one version's reads are refused by the hash check. Loud | Documented in `?datom_store_local` |
| Someone edits a datom-owned file by hand (an artifact's `metadata.json`, `version_history.json` or `set.json`, or `.datom/manifest.json`) (requirements D13) | The next datom command resets the edit and warns, naming the artifact; `datom_write(conn, name =)` no longer commits it. Custom metadata is changed with `datom_write(conn, data, name, metadata = )` | Guarded (task 4a's test); documented in `?datom_write` and `NEWS.md` |
| A crash during a local upload leaves a temporary file (`.{name}.tmp`) beside the data file | Nothing for readers. A leftover after the link costs no space (a hard link shares the bytes); one left mid-copy takes space. `datom_storage_list()` shows it; copy and verify skip it | Guarded (a test that copy and verify skip it); documented in `?datom_store_local` |
| Two people publish the same table within seconds, and the older publish lands last (DD4) | Readers get the superseded version as current until the next datom command in any up-to-date clone republishes it. Reads that name a version are unaffected | Guarded (P10); documented in `dev/engineering-notes.md` |
| The same, with the two publishes crossing so the stored manifest names the newer version and the stored metadata holds the older one (DD4) | Readers get the superseded version, and heal does not notice, until the table's next write or `datom_validate(fix = TRUE)` | Reported by `datom_validate()` as `metadata_stale_s3`; fixed by `datom_validate(fix = TRUE)` or the table's next write (section 6, P11) |
| A version's snapshot is missing from storage (no route in this spec can cause it: every route uploads the snapshot before `metadata.json`; left by 0.2.0's write interrupted between `metadata.json` and the snapshot, D7, or by storage losing a file outside datom) | Not reported by `datom_validate()`, which checks only that `metadata.json`, the history and the data file exist. `datom_read(version = )` of that version fails. From task 7, `datom_validate(fix = TRUE)` restores the **current** version's snapshot from the clone's `metadata.json` (section 6); an older version's is restored by nothing | Not guarded. Documented in `dev/engineering-notes.md` at completion; the check, and restoring older snapshots from git, go to a follow-up issue (draft: `draft-issue-validate-completeness.md`) |
| 0.2.0's `datom_write(conn, name =)` published a hand edit of `metadata.json` | The stored `metadata.json` describes a version that no history entry, manifest row or snapshot records. Readers are told the previous version, and a read pinned to it returns the pre-edit metadata. `datom_validate()` reports nothing | Not guarded (D7). D13 and task 4b stop new cases. Every publish from the clone skips that artifact's snapshot and warns, leaving the previous version's snapshot intact (section 4, step d). Goes to the follow-up issue |
| A file put at a data address by hand, adopted by a re-run | Its content is read without a content check | Documented in `dev/engineering-notes.md`; not checked |
| A teammate still on a released datom (D11) | An upgraded teammate's write can publish their data-less version | Documented in `NEWS.md` |
| GitHub unreachable at the start of a command (DD1) | The command stops with a message and changes nothing; the user re-runs when online | Guarded (P9); documented in `?datom_write` |

## 13. Tasks

The task list is `tasks.md`. The outline that stood here was replaced by it on 2026-10-28, so the
two cannot disagree.
