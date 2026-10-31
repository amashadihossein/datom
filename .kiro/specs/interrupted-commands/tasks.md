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

## Where things stand

Requirements approved 2026-10-28 (amended the same day: R3.3, R5.5, R7.8, and an R8 row). Design
approved 2026-10-28 with decisions DD1-DD4. **No code yet.**

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

Starting cold: `git checkout spec/interrupted-commands && git pull`, then read `requirements.md`
(terms, decisions D1-D12) and `design.md` (sections 1-4 at least). The probe scripts in `research/`
reproduce today's failures; rerunning them after the relevant task is part of its acceptance.

**Shared test helpers** (created in task 2, extended later): `tests/testthat/helper-interrupt.R`
with a project fixture (folder git remote and local store, as in the probes), a second-clone fixture,
and `local_break_at(step)`, which raises at one named step through a mocked binding. Names and
mechanics follow the probes in `research/`.

**Break table** (R7.1). Each test breaks the command at one step, re-runs the same command, and checks
what a reader sees (the new version reads; the stored manifest names it).

| Command | Task | Steps broken |
|---|---|---|
| `datom_write()`, data-frame route | 2 (steps 1-5), 4b (step 6) | data file upload; clone files; commit; push; metadata upload; manifest upload |
| `datom_write_set()` | 3 (steps 1-5), 4b (step 6) | the same six |
| `datom_write(conn, name =)`, the metadata-only route | 4b | its push; its metadata upload |
| `datom_sync()` | 6 | the second of three tables, at its file import, data file upload, commit, push and manifest upload; then re-scan and re-sync, and every table reads |
| `datom_validate(fix = TRUE)` and the mirror-everything route | 7 | the push; between the first and second artifact's mirror; the final manifest upload |
| `datom_repo_commit()` | 8 | its push (the re-run commits nothing and pushes) |
| `datom_init_repo()` | 9 | its commit and its push (rolled back, so the re-run starts afresh); the manifest upload (the re-run finishes, R6) |

`datom_sync_manifest()` changes nothing, so it has nothing to break.

---

- [ ] **1. Storage: upload only if absent, and the stored file's hash** (R1.2, R1.3; design section 3)
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
    delete the prefix. Run on the paws versions installed here and on CRAN's current ones
    (`paws.storage` 0.11.0, `paws.common` 0.9.0). Record the result in design section 10, item 2.
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
    whole-file `ChecksumSHA256` matching the file, on both paws version pairs.

- [ ] **2. Tables: the data file first** (R1.1, R1.3, R1.4, R2.1; design section 3)
  - **Escalation first: design spot-check on a more capable model.**
  - `R/read_write.R`: `.datom_resolve_parquet_sha()` decides and uploads through
    `.datom_storage_upload_absent()`, recording the stored file's hash when the file is already
    there; `datom_write()` calls it before `.datom_write_metadata_local()`;
    `.datom_commit_and_mirror()` loses its `upload` argument.
  - Correct the old-order docstrings of `.datom_commit_and_mirror()` and
    `.datom_resolve_parquet_sha()` (R9.4).
  - Create `tests/testthat/helper-interrupt.R`. Rewrite any existing test that asserts the old order
    (design section 10, item 4).
  - **Update `research/write_steps_probe.R` before using it as evidence.** Break step 1 by replacing
    `.datom_storage_upload_absent()`; add a step-2 break by replacing `.datom_update_manifest_entry()`
    (metadata and history written, no manifest row); keep the commit, push, metadata and manifest
    breaks. A row counts only if its `raised` column is `TRUE`. Update `research/README.md`.
  - Tests: the break table's steps 1-5 for `datom_write()` (P1); the recorded hash equals the stored
    file's hash, including when the file was stored by an earlier broken run (P3).
  - Guards to probe: the upload placed before the first clone write; the stored-file branch of the
    hash decision.
  - Acceptance: P1 for steps 1-5 and P3 for `datom_write()`; the updated
    `research/write_steps_probe.R` shows, for steps 1-5, the break firing and the re-run reading the
    new version.

- [ ] **3. Sets: the payload first** (R1.1, R1.5; design section 3)
  - `R/set.R`: `datom_write_set()` builds the payload in a temp file, uploads or adopts it through
    `.datom_resolve_document_sha()`, then writes `set.json`; when the recorded hash is a stored
    payload's and the fresh bytes differ, `set.json` takes the stored bytes.
  - `.datom_restore_set_payload()` uploads through `.datom_storage_upload_absent()`.
  - Correct the old-order docstrings of `.datom_resolve_document_sha()` and
    `.datom_restore_set_payload()` (R9.4).
  - **Update `research/set_steps_probe.R`** the same way as task 2's probe; its step-2 break leaves
    `set.json`, metadata and history written.
  - Tests: the break table's steps 1-5 for `datom_write_set()` (P1); a re-run with a different
    spelling of the same set leaves `set.json` byte-identical to the stored payload (R1.5). The test
    "nothing reaches storage when the git push fails" in `test-write-set.R` becomes "only the payload
    reaches storage".
  - Guards to probe: the stored-spelling branch.
  - Acceptance: P1 for steps 1-5 of `datom_write_set()`; R1.5; the updated
    `research/set_steps_probe.R` shows, for steps 1-5, the break firing and the re-run reading the set.

- [ ] **4a. Heal: reset, pull, check** (R2.4, R2.5, R3.1, R3.5's helper, R3.7; DD1; design sections 1
  and 4)
  - **Escalation first: design spot-check on a more capable model**, covering 4a and 4b.
  - New `R/heal.R`: `.datom_heal()` with steps a-c (reset what never committed, pull, re-check the
    documents, stop on a failed fetch) and `.datom_reset_unfinished()`. `artifact` takes several
    names. Its docstring says what heal repairs and what it leaves (design section 4's table).
  - Wire heal into `datom_write()` (all three routes, with the internal `.healed` argument),
    `datom_write_set()` and `.datom_sync_metadata()`, in the check order of design section 1: every
    refusal check that needs no storage state before heal, change detection and the table-or-set
    check after, the mirror-everything route's confirmation prompt before. Writes still publish
    through the existing path; 4b moves them. `R/utils-git.R`: `.datom_git_head_file()`.
  - Reset messages as in design section 4: information for an artifact the command is about to
    write, a warning for any other. Correct the ordering comment in `.datom_sync_metadata()` (R9.4).
  - Settle design section 10 item 1 (unstaging chosen paths) and item 5 for the reset messages
    (`cli` alert or classed warning), and record the answers in `design.md`.
  - **`research/other_command_probe.R`**: confirm each break fired.
  - Tests: another artifact's write broken before its commit, including a set write with
    `include_paths` (R7.2, P8); a re-run of the broken write itself, getting the information message;
    no command publishes an uncommitted file (P4); a failed fetch changing nothing (P9); two clones
    with the second behind, whose write leaves storage at the first clone's newer version, and a
    conflict outside the manifest leaving storage unchanged (P5's write case, R7.6); a mistyped
    argument refused before heal runs.
  - Guards to probe: the reset, the pull before any decision, the re-run entry check, the fetch-failure
    stop, a refusal check placed before heal.
  - Acceptance: P4, P8, P9 and P5 for writes; `research/other_command_probe.R` shows `dm` reset when
    its write broke before its commit, with the break confirmed.

- [ ] **4b. Heal: push and publish** (R2.2, R2.3, R3.2-R3.4; DD4; design section 4)
  - `R/heal.R`: heal's step d, `.datom_unpublished_artifacts()`, `.datom_publish_artifacts()` (the
    one publish path) and `.datom_pushed_artifacts()`. A write's steps 5-6 and the metadata-only
    route move onto `.datom_publish_artifacts()`.
  - Correct the old-order docstring of `.datom_push_metadata_s3()` (R9.4).
  - Settle design section 10 item 3 (a stored manifest unreadable for a reason other than absence) and
    item 5 for the publish messages, and record the answers in `design.md`.
  - Tests: the break table's step 6 for both write commands, and its rows for the metadata-only route
    (P1); another artifact's write broken after its commit is published (R7.2); a publish landing
    behind a colleague's newer one, corrected by the next command (P10); storage reads of
    `.metadata/manifest.json` counted through a mock: one during a write, still one during a
    three-table sync (R3.4).
  - Guards to probe: the unpublished-artifact comparison, the manifest-last order.
  - Acceptance: P1 (all six steps, tables and sets), P10, R3.4; `research/other_command_probe.R`
    shows `dm` published when its write broke after its commit.

- [ ] **5. A conflict only in the manifest** (R3.8; DD2; design section 5)
  - `R/manifest-rebuild.R`: extract `.datom_manifest_row()` from `.datom_rebuild_manifest_entry()`,
    which keeps its behaviour.
  - `R/heal.R`: `.datom_resolve_manifest_conflict()`; `R/utils-git.R`: `.datom_git_pull()` calls it
    when the manifest is the only conflicted file, so every pull gets it: `datom_pull()`, the push
    commands, and the migration pull in `.datom_resolve_data_location()` (`R/ref.R`). That last caller
    gets no test of its own: its existing tests replace the pull with a stub, and the rebuild is
    tested on the pull function.
  - Tests (R7.7): two clones writing different tables without a pull in between, and a write whose push
    broke while the other clone pushed, both finish with a manifest naming both tables; `datom_pull()`
    resolves a manifest-only conflict; two clones writing the same table still stop, storage
    unchanged; the storage-side rebuild's existing tests still pass.
  - Guards to probe: the manifest-only condition.
  - Acceptance: P6; `research/two_writers_probe.R` shows the second write finishing.

- [ ] **6. Scan and sync** (R4, R3.7; DD3; design section 7)
  - `R/sync.R`: `.datom_read_manifest()` gains the `"head"` scope; `datom_sync_manifest()` compares
    against it and reports `unpublished` (fetch first; a failed fetch warns and counts unpushed
    commits only; storage unreachable warns and counts unpushed commits only; a behind clone skips the
    storage comparison and names `datom_pull()`); status order as in design section 7.
  - `datom_sync()` heals once, with every table it is about to write, instead of calling
    `.datom_check_git_current()`, then calls `datom_write(.healed = TRUE)`; `unpublished` rows come
    back `success` without an import; a row whose write found no change says it was already up to
    date.
  - Delete `.datom_check_git_current()` and its tests (named in the commit message). Rewrite the
    comments that name it: the branch-guard comment in `datom_repo_commit()` (the guard and its reason
    stay), the docstring of `.datom_git_ahead()`, and the upstream note in `.datom_git_push()`.
  - Tests: R4.1-R4.5; the break table's `datom_sync()` row; the stale preview of DD3; heal called once
    in a three-table sync, counted through a mock (R3.7); a scan with storage reads failing reports
    tables in unpushed commits as `unpublished` and warns (R4.2), separately from a failed fetch.
  - Guards to probe: the comparison against the last commit, the behind-clone skip.
  - Acceptance: R4.1-R4.5 and R3.7's once-per-sync rule; `research/sync_and_manifest_probe.R` and
    `research/stale_preview_probe.R` show the table published and the honest message.

- [ ] **7. The repair** (R5; design section 6)
  - `R/sync.R`: `.datom_sync_data_metadata()` heals first (so it pushes), mirrors every artifact,
    then the manifest last (P7); the `datom_write(conn)` prompt says it may push, and is answered
    before heal runs.
  - `R/validate.R`: `datom_validate()` reports per artifact what was reset, pushed and published
    (R5.3); fetches first; `.datom_validate_one_table()` reports `metadata_stale_s3` against the
    version in the clone's last commit (R5.5).
  - Tests: R5.1-R5.4; the break table's repair row; R7.8 (stale reported and cleared; not reported on
    a behind clone or for a write broken before its commit; a failed fetch skips with a warning); a
    "no" at the prompt leaves git and storage unchanged.
  - Guards to probe: the reset before publishing, the manifest-last order, the stale comparison, the
    behind-clone skip.
  - Acceptance: R5.1-R5.5, P7, P11.

- [ ] **8. The git and config commands** (R3.5, R3.6; D9, D10)
  - `R/repo.R`: `datom_repo_commit()` calls `.datom_reset_unfinished()` before staging; it, and
    `datom_repo_push()`, `datom_repo_attach_governance()` and `datom_repo_set_data_store()`, name
    the datom artifacts in the commits they push and say they are not yet published.
  - Tests: R7.2's `datom_repo_commit()` cases (with and without `paths`); R3.6 with
    `datom_repo_push()` (message names the artifact, storage unchanged, the next datom write
    publishes it); the break table's `datom_repo_commit()` row.
  - Guards to probe: the reset in `datom_repo_commit()`.
  - Acceptance: R3.5, R3.6.
  - **Escalation after: purity audit on a more capable model** (tasks 2-8).

- [ ] **9. `datom_init_repo()` re-run** (R6; design section 8)
  - `R/conn.R`: `.datom_init_finish()`, called before the remote is resolved.
  - Tests: the break table's `datom_init_repo()` row; a different project, different storage, a
    remote without the initial commit, or a stored manifest each refuse exactly as today.
  - Guards to probe: each of the three conditions.
  - Acceptance: R6.1-R6.3.

- [ ] **10. Documentation** (R8, R9)
  - **Escalation first: test coverage review on a more capable model**, including the break table
    checked against the tests that exist.
  - Roxygen for every help page in R9.5, then `devtools::document()`. Beside `endpoint` in
    `?datom_get_conn`: a service that ignores conditional writes, and one that rejects the new headers.
    `NEWS.md` (R9.6; cite only `?verb` and `vignette(...)`, never `dev/` or `.kiro/`, conventions
    item 7a).
  - Search `R/` for any old-order wording left after tasks 2-4b ("serialization point", "After git,
    never before", "local -> git -> S3") and correct it (R9.4).
  - `dev/datom_specification.md` (R9.2, R9.3); the conventions section in
    `.github/copilot-instructions.md` with the wording in R9.1; the note beside I5 in
    `.kiro/specs/datom-sets/design.md`; `dev/engineering-notes.md` gains design section 12's table.
  - Acceptance: R9.1-R9.6 done; every residual row in design section 12 is guarded or documented
    where the row says.

- [ ] **11. End to end, and spec completion**
  - Rerun every probe in `research/`, as updated in tasks 2-4b, and record that every break fired and
    each now shows the job finished (or, for `publish_race_probe.R`, corrected by the next command).
  - `dev/e2e-solo-local.R`, and `dev/e2e-solo-s3.R` against real S3 with the owner's credentials.
  - `devtools::check()`; the full suite; the spec completion procedure (conventions item 7): harvest
    learnings, update `dev/README.md` Active Specs, PR into `dev`.
  - Acceptance: the end-to-end runs pass on both backends; `devtools::check()` is clean; the PR is
    open.
