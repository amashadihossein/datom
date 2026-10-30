# Design -- interrupted commands finish on a re-run

**Status**: DRAFT, 2026-10-28, not yet reviewed. Requirements approved the same day
(`requirements.md`). Design decisions for the owner are in section 9: DD1 decided (a failed fetch
stops the command); DD2 decided (every pull resolves a manifest-only conflict); DD3 decided
(`datom_sync()` pulls a behind clone). All design decisions are taken; the design as a whole awaits
approval. The routine and its file were named `heal` by the owner on 2026-10-28 (first drafted as
"settle" in `R/finish.R`). A review by another agent the same day, evaluated with the owner, added
the publish rule (section 4, "Never publish over a version the clone does not know"), the hard-link
upload on a local store, and the whole-file condition on S3's stored checksum (section 3).
**Read first**: `requirements.md` (terms, findings, decisions D1-D12, requirements R1-R9). This
document says how: which functions change, in which files, and how each command runs.

## 1. The shape in one picture

Every command that changes things starts with the same routine, **heal**, then does its own work in
the new order. Heal is datom's self-healing step: it is where "a re-run finishes" and "another
command finds unfinished work" both live, so there is one implementation of them, not one per
command.

```
command(conn, ...)
  door checks (unchanged: role, path, forward-compat entry, ref guard)
  heal(conn)                                    R2.4, R3.1-R3.4, R3.7, R3.8
    a. reset datom files that never committed   (local only)
    b. pull: fetch, then merge                  (conflict only in the manifest -> rebuild it)
    c. forward-compat entry check again         (the pull may have brought new documents)
    d. push unpushed commits, then publish      (artifacts whose stored manifest row is behind git)
  own work, new order (a write):
    1. data file -> storage, only if absent     R1.1-R1.3
    2. clone files                              (metadata, history, manifest row, set.json)
    3. commit
    4. push (pulls first, as today; R3.8 applies)
    5. metadata, history, snapshot -> storage
    6. manifest -> storage                      (always last)

  every publish (heal's d, a write's 5-6, the repair) follows the publish rule:
    never replace a stored version the clone does not know
```

**Invariant this rests on: the manifest is always published last.** Every route that writes storage
publishes an artifact's documents first and the manifest after. So a stored manifest row that matches
git means that artifact's documents are current too, and heal can find all unpublished work with one
read of the stored manifest (R3.4). Today `.datom_sync_data_metadata()` writes the manifest **first**;
that order is reversed (section 6).

## 2. Functions, by file

The interruption logic lives in one new file, `R/heal.R`, so the code that repairs what an interrupted
command left behind has one home and can be read and extended in one place. Two kinds of change sit
elsewhere, on purpose: the storage primitives (upload only if absent, the stored file's hash) live with
their backend peers, because datom keeps each backend's code together behind one dispatch layer; and
each command gains a call to `.datom_heal()` in its own file, plus the reordered steps inside the two
write commands.

| File | Function | New / changed | Role |
|---|---|---|---|
| `R/heal.R` | `.datom_heal(conn, artifact = NULL)` | new | Steps a-d of section 1. Returns what it reset and what it published, for the caller's messages |
| `R/heal.R` | `.datom_reset_unfinished(conn)` | new | Step a. Finds datom-owned files that differ from the last commit and puts them back (section 4) |
| `R/heal.R` | `.datom_unpublished_artifacts(conn, stored)` | new | Names the artifacts whose committed version readers cannot see: in unpushed commits, or whose clone manifest row differs from the stored one |
| `R/heal.R` | `.datom_publish_artifacts(conn, names)` | new | **The one publish path.** For each name, the clone's metadata, history and snapshot through `.datom_push_metadata_s3()`, under the publish rule; then the manifest, last, merged row by row (section 4). Heal's step d, a write's steps 5-6 and the repair all go through it |
| `R/heal.R` | `.datom_stored_version_known(conn, name)` | new | The publish rule's test: is the version storage holds for `name` absent, or in the clone's history? |
| `R/heal.R` | `.datom_manifest_for_upload(conn)` | new | Re-reads the stored manifest just before the upload and merges it with the clone's row by row under the publish rule |
| `R/heal.R` | `.datom_resolve_manifest_conflict(path)` | new | R3.8: rebuilds `.datom/manifest.json` after a merge whose only conflict it is, stages it, commits the merge (section 5) |
| `R/heal.R` | `.datom_pushed_artifacts(path)` | new | Artifacts touched by commits the remote lacks; feeds the R3.6 message and step d |
| `R/manifest-rebuild.R` | `.datom_manifest_row(meta, history, member_count)` | new, extracted | The row-building half of `.datom_rebuild_manifest_entry()`, which keeps its storage reads and calls it. The clone-side rebuild in section 5 calls it too, so the two rebuilds cannot drift |
| `R/utils-storage.R` | `.datom_storage_upload_absent(conn, local_path, key)` | new | R1.2: check, then upload only if absent. Returns `"uploaded"` or `"exists"` |
| `R/utils-storage.R` | `.datom_storage_object_sha256(conn, key)` | new | R1.3: the SHA-256 (hex) of the bytes stored at `key` |
| `R/utils-s3.R` | `.datom_s3_upload_absent()`, `.datom_s3_object_sha256()` | new | S3 halves (section 3) |
| `R/utils-local.R` | `.datom_local_upload_absent()`, `.datom_local_object_sha256()` | new | Local halves (section 3) |
| `R/utils-git.R` | `.datom_git_pull(path, pat)` | changed | On a conflict whose only file is `.datom/manifest.json`, calls `.datom_resolve_manifest_conflict()` instead of aborting. Every other conflict aborts as today |
| `R/utils-git.R` | `.datom_git_head_file(path, rel)` | new | A file's content as committed in HEAD (`git2r::revparse_single(repo, "HEAD:<rel>")`) |
| `R/read_write.R` | `datom_write()` | changed | Heals first; data file before clone files; internal `.healed` argument so `datom_sync()` heals once per call (R3.7) |
| `R/read_write.R` | `.datom_commit_and_mirror()` | changed | Loses its `upload` argument: the data file is already stored. Commits and pushes, then publishes through `.datom_publish_artifacts()` |
| `R/read_write.R` | `.datom_resolve_parquet_sha()`, `.datom_resolve_document_sha()` | changed | The R1.3 decision, including the stored-file case, and now performing the upload (section 3) |
| `R/set.R` | `datom_write_set()` | changed | Payload built in a temp file; uploaded first; the clone's `set.json` takes the stored bytes when they differ (R1.5) |
| `R/utils-sha.R` | `.datom_sync_metadata()` | changed | Its opening pull is replaced by heal; it publishes through `.datom_publish_artifacts()` |
| `R/sync.R` | `datom_sync_manifest()` | changed | Compares against HEAD's manifest; `unpublished` status (section 7) |
| `R/sync.R` | `datom_sync()` | changed | Heals once instead of `.datom_check_git_current()`; `unpublished` rows are reported as published by heal |
| `R/sync.R` | `.datom_sync_data_metadata()` | changed | Heals (so it pushes first, R5.2), then mirrors every artifact, then the manifest last, all under the publish rule |
| `R/sync.R` | `.datom_sync_one_artifact()` | changed | Applies the publish rule to `metadata.json` and `version_history.json`; snapshots and a set's payload restore are unchanged |
| `R/sync.R` | `.datom_read_manifest()` | changed | A third scope, `"head"`, reading HEAD's copy through `.datom_git_head_file()` with the same schema check and upgrade |
| `R/sync.R` | `.datom_restore_set_payload()` | changed | Uploads through `.datom_storage_upload_absent()` |
| `R/validate.R` | `datom_validate()` | changed | Messages only: the fix now pushes and reports per artifact (R5.3) |
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
key exists in storage   -> record .datom_storage_object_sha256(key)         (case 2)
otherwise               -> .datom_storage_upload_absent(tmp, key)
                             "uploaded" -> record the fresh bytes' hash      (case 3)
                             "exists"   -> record the stored hash            (someone stored it in between)
```

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
  datom uploads in one piece today, so this guards the multipart uploads planned in #73. The
  arguments and the `ChecksumType` field exist in paws.storage 0.9.0; their behaviour against real
  S3 is checked in the end-to-end run, not in unit tests (R7.5).
- On a service that ignores `IfNoneMatch`, the `head_object` check still runs first; the race left
  is the R8 row.

**Local** (`R/utils-local.R`):
- `.datom_local_upload_absent()`: if the target exists, `"exists"`. Otherwise copy to a temporary
  name in the same folder and **hard-link** it to the final name with `file.link()`, then delete the
  temporary name. A link refuses when the target exists, so a file that appeared in between is never
  replaced; a plain move would replace it. (Checked 2026-10-28: `file.rename()` onto an existing file
  replaced it; `file.link()` onto one refused and left it intact.) When the link fails, datom looks
  again: the target now exists means `"exists"`; it does not means the file system has no hard links
  (some network drives, exFAT), and datom falls back to check, then move, which leaves the race in
  section 12. A half-copied file only ever sits under the temporary name.
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
- The message names each artifact reset and says to re-run its write.

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
  least what GitHub holds, so a difference found **here** means storage is behind (R3.3). A colleague
  can still publish between this read and the publish itself; the publish rule below handles that.
- `.datom_publish_artifacts()` for those names, manifest last. A set's payload is not re-uploaded
  here: under D1 it is in storage before its commit exists.

The command's own work then runs against a clone that is clean, current and fully published, so
today's change detection (`.datom_has_changes()`, against storage) answers correctly, and a re-run
whose own write already finished reports `none` (R2.1). A break at step 6 is caught by step d of the
next run (R2.3).

**Never publish over a version the clone does not know** (the publish rule; R3.3). A colleague can
publish after this clone's pull. Reproduced on today's code (`research/publish_race_probe.R`): you
push `dm` v2; before your publish runs, a colleague pulls, writes v3, pushes and publishes it; your
publish of v2 then lands, and readers get v2 although GitHub's latest is v3. Heal would widen this,
since it publishes other artifacts' work too and the manifest upload replaces the whole file. So
every publish goes through `.datom_publish_artifacts()`, which:
- for each artifact, reads the stored `metadata.json` just before writing and asks
  `.datom_stored_version_known()`: is that version absent, or in the clone's
  `version_history.json`? If yes, storage is behind or equal, and datom writes `metadata.json` and
  `version_history.json`. If no, a colleague published something newer than this clone knows, so
  datom leaves both alone and says so, naming the artifact. The version snapshot
  (`{name}/.metadata/{version}.json`) is written either way: it is addressed by its own version, so
  writing it can never replace something newer, and without it a set could not pin this version;
- uploads the manifest from `.datom_manifest_for_upload()`: the stored manifest re-read just before
  the upload, merged with the clone's row by row under the same rule (the clone's row unless the
  stored row's version is unknown to the clone; a row only one side has is kept), with `summary`
  recomputed and fields this build does not know carried forward with `.datom_carry_unknown_fields()`.

What remains is the gap between that last read and the upload itself, milliseconds wide. A colleague
landing in it leaves storage behind git until the next command from an up-to-date clone republishes;
the owner chose to accept that rather than make the S3 uploads conditional (2026-10-28; section 12).

**Who calls heal**: `datom_write()` (all three routes), `datom_write_set()`, `datom_sync()` (once
per call, then `datom_write(.healed = TRUE)` per table), `.datom_sync_data_metadata()` (so the repair
and the mirror-everything route). `datom_repo_commit()` calls step a only (R3.5). The four push
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

`.datom_sync_data_metadata(conn, .confirm)` becomes: heal (which resets, pulls, pushes and publishes
anything behind), then `.datom_sync_one_artifact()` for every artifact as today (metadata, history,
snapshots, a set's payload restored from the clone if absent), under the publish rule, then the
manifest **last**, merged as in section 4. The confirmation prompt on the `datom_write(conn)` route
says it may push. `datom_validate(fix = TRUE)` reports per artifact what was reset, pushed, published
and left alone because storage held a newer version (R5.3).

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
| DD2 | **R3.8 sits inside `.datom_git_pull()`**, so `datom_pull()` and the four push commands also resolve a manifest-only conflict, not just the commands in R3 | **Decided 2026-10-28: yes** | Commands outside R3 rewrite the manifest during a merge, and say so. This happens only when the clone holds an unpushed commit that changed the manifest (in practice a datom write whose push failed), a colleague pushed a datom write since, and the manifest is the only conflicted file. A fast-forward, or a merge of commits that never touched the manifest, rebuilds nothing. The alternative was a second pull function for R3 alone, leaving `datom_pull()` to stop on a conflict a write would resolve by itself |
| DD3 | **`datom_sync()` pulls a clone that is behind instead of refusing.** Today it stops with "pull first" (`.datom_check_git_current()`), the only command that does | **Decided 2026-10-28: pull** | A preview built before the pull can be stale. Probed (`research/stale_preview_probe.R`): when a colleague already imported the same file, the stale `new` row is re-read, the write finds no change and stores nothing, and the row reports `success`. Today that row's line also says "synced (new)", which claims work that did not happen; task 6 makes it say the table was already up to date. A conflict outside the manifest still stops the sync before storage changes |
| DD4 | **The gap between the publish rule's last read and the upload is accepted**, not closed with conditional uploads (`IfMatch`) | **Decided 2026-10-28: accept** | Readers can get the older version until the next command from an up-to-date clone republishes. Conditional uploads would have closed it on S3 only, with more code in the S3 layer |

## 10. Proven, and not yet traced

Proven on 2026-10-28 (scripts in `research/`):
- The failures this fixes (`write_steps_probe.R`, `set_steps_probe.R`, `sync_and_manifest_probe.R`,
  `other_command_probe.R`, `two_writers_probe.R`), and the publish race on today's code
  (`publish_race_probe.R`).
- git2r completes a merge after datom rewrites the manifest (`merge_completion_probe.R`).
- git2r 0.36.2 reads a file as committed in HEAD, lists files changed between two commits, resets
  chosen files to HEAD leaving others alone, and reports untracked directories
  (`git2r_primitives_probe.R`).
- `file.link()` refuses an existing target and leaves it intact; `file.rename()` replaces it
  (checked in a throwaway R session).
- paws turns an S3 error into a condition classed by HTTP status (read from
  `paws.common::aws_error()`). paws.storage 0.9.0 accepts `IfNoneMatch`, `IfMatch`, `ChecksumSHA256`
  and `ChecksumMode`, and its `head_object` output carries `ChecksumSHA256` and `ChecksumType`.

Not yet traced, each resolved in the task that needs it:
1. Unstaging chosen paths with `git2r::reset(repo, path = ...)` after a break between staging and
   committing.
2. Real S3: `IfNoneMatch = "*"` refused with 412, and `ChecksumSHA256` with `ChecksumType`
   `FULL_OBJECT` returned by `head_object` for an object put with one. End-to-end run only
   (`dev/e2e-solo-s3.R`).
3. Heal's step d when the stored manifest cannot be read for a reason other than absence (the storage
   reader can rebuild it and warn); which of those outcomes counts as "behind".
4. Whether any existing test asserts the old order or the manifest-first mirror and needs rewriting
   (the test "nothing reaches storage when the git push fails" in `test-write-set.R` does).
5. Message wording for reset, publish, a skipped publish and R3.6, and whether they are `cli` alerts
   or warnings with a class a test can count.
6. How `.datom_stored_version_known()` names the stored version: the version recorded for the stored
   `metadata.json` (as `.datom_recorded_current_version()` does), or its recomputed identity.

## 11. Correctness properties (what the tests pin)

| # | Property | Requirement |
|---|---|---|
| P1 | For each step of a write, a break there followed by the same write leaves a reader reading the new version and the stored manifest naming it | R2.1, R7.1 |
| P2 | A stored data file's bytes never change after it is first stored, on both backends | R1.2, R7.3 |
| P3 | The hash a version records equals the hash of the bytes stored at its address | R1.3 |
| P4 | No command publishes a file that was never committed | R3.1, R5.1 |
| P5 | No publish replaces a stored version the clone does not know: neither from a clone behind GitHub, nor after a colleague publishes between the pull and the publish. Tested by stubbing a newer stored version between the pull and the publish, and checking that storage keeps it, the message names the artifact, and the clone's own version snapshot is still stored | R3.3, R3.7, R7.6 |
| P6 | A manifest-only conflict is resolved and the rebuilt manifest names every artifact of both sides; any other conflict leaves storage unchanged | R3.8, R7.7 |
| P7 | The manifest is the last thing any route publishes | section 1 |
| P8 | Files datom does not own are never reset | R3.1, R3.5 |
| P9 | A failed fetch at the start leaves the clone, git and storage unchanged | DD1, R3.7 |

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
| A local store on a file system without hard links, two writers, same new content, same moment | The second move replaces the first file; one version's reads are refused by the hash check. Loud | Documented in `?datom_store_local` |
| A colleague publishes in the milliseconds between the publish rule's last read and the upload (DD4) | Storage holds the older version as current, and readers get it, until the next command from an up-to-date clone republishes | Documented in `dev/engineering-notes.md`; the rule itself guarded by P5 |
| A file put at a data address by hand, adopted by a re-run | Its content is read without a content check | Documented in `dev/engineering-notes.md`; not checked |
| A teammate still on a released datom (D11) | An upgraded teammate's write can publish their data-less version | Documented in `NEWS.md` |
| GitHub unreachable at the start of a command (DD1) | The command stops with a message and changes nothing; the user re-runs when online | Guarded (P9); documented in `?datom_write` |

## 13. Task outline (becomes `tasks.md` once this design is approved)

| # | Task | Escalation flag |
|---|---|---|
| 1 | Storage: upload only if absent (S3 conditional; local hard link with its fallback), and the stored file's hash (whole-file checksum only), both backends | |
| 2 | Tables: data file first and the R1.3 decision; `.datom_commit_and_mirror()` without the upload; break-at-each-step tests for `datom_write()` | design spot-check before starting (it changes the core write path) |
| 3 | Sets: payload via a temp file, R1.5; the same tests for `datom_write_set()` | |
| 4 | Heal (`R/heal.R`): reset, pull, check, push and publish; the one publish path with the publish rule, which a write's steps 5-6 move onto; wired into the write routes; tests for R3, R3.7, DD1 and P5 | design spot-check before starting (every write command calls it) |
| 5 | R3.8 in `.datom_git_pull()`, with `.datom_manifest_row()` extracted; tests R7.7 | |
| 6 | Scan and sync: HEAD's manifest, `unpublished`, one heal per sync (which pulls a behind clone, DD3); a row whose write found no change says it was already up to date | |
| 7 | Repair and mirror-everything: heal first, the publish rule, manifest last, per-artifact report | |
| 8 | `datom_repo_commit()` reset; the R3.6 message on the four push commands | purity audit after (tasks 2-8 touch many files) |
| 9 | `datom_init_repo()` re-run | |
| 10 | Docs: help pages, NEWS, `dev/datom_specification.md`, the conventions section, the datom-sets I5 note, engineering notes | test coverage review before |
| 11 | End-to-end on local and on real S3; spec completion | |
