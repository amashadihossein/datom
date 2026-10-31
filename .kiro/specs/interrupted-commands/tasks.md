# Tasks -- interrupted commands finish on a re-run

**Issue**: [#155](https://github.com/amashadihossein/datom/issues/155).
**Branch**: `spec/interrupted-commands`, from `dev` at `347a403`. PRs into `dev`.
**Tier**: 3. One commit per task. **Full suite before every commit**, count in the message; it must
not drop below the last recorded count. Each new guard is probed once against its own test file
(conventions item 2a), result in the commit message. **Checkpoint after every task**: post what
shipped and wait for the owner's go-ahead before the next one.
**Test baseline**: 5142 expectations, 0 failed, 0 skipped (`dev` at `347a403`).
**Order**: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10 -> 11.
**Model escalation flags (set at planning):**
- **Design spot-check before task 2**: it changes the core write path.
- **Design spot-check before task 4**: every write command calls heal.
- **Purity audit after task 8**: tasks 2-8 touch many files across several modules.
- **Test coverage review before task 10**: confirm every guard was watched going red, and that the
  break-at-each-step tests cover every command in R1-R6.

## Where things stand

Requirements approved 2026-10-28 (amended the same day: R3.3, R5.5, R7.8). Design approved
2026-10-28 with decisions DD1-DD4. This task list is drafted and awaits approval. **No code yet.**

Starting cold: `git checkout spec/interrupted-commands && git pull`, then read `requirements.md`
(terms, decisions D1-D12) and `design.md` (sections 1-4 at least). The probe scripts in `research/`
reproduce today's failures; rerunning them after the relevant task is part of its acceptance.

**Shared test helpers** (created in task 2, extended later): `tests/testthat/helper-interrupt.R`
with a project fixture (folder git remote and local store, as in the probes), a second-clone fixture,
and `local_break_at(step)`, which raises at one named step through a mocked binding. Names and
mechanics follow the probes in `research/`.

---

- [ ] **1. Storage: upload only if absent, and the stored file's hash** (R1.2, R1.3; design section 3)
  - `R/utils-storage.R`: `.datom_storage_upload_absent()` and `.datom_storage_object_sha256()`,
    dispatching to the backends.
  - `R/utils-s3.R`: `.datom_s3_upload_absent()` (`head_object` first, then `put_object` with
    `IfNoneMatch = "*"` and `ChecksumSHA256`; `http_412` returns `"exists"`) and
    `.datom_s3_object_sha256()` (trust `ChecksumSHA256` only when it covers the whole file: type
    `FULL_OBJECT`, or no type and no `-N` suffix; otherwise download and hash).
  - `R/utils-local.R`: `.datom_local_upload_absent()` (copy to a recognisable temporary name, hard-link
    into place, delete the temporary name; a refused link with the target present is `"exists"`;
    no hard links means check, then move) and `.datom_local_object_sha256()`; `.datom_is_temp_key()`.
  - `R/storage.R`: `datom_storage_copy()` and `datom_storage_verify()` skip temporary files;
    `datom_storage_list()` unchanged.
  - Nothing calls the new upload yet, so no behaviour changes for users in this task.
  - Tests: an existing file with different bytes survives a second upload, on both backends (P2);
    a failure mid-copy leaves nothing at the final key; the no-hard-link fallback; the S3 arguments
    and the 412 path on a mocked client; the checksum condition (`FULL_OBJECT`, `COMPOSITE`, `-N`,
    absent); copy and verify skip a temporary file.
  - Guards to probe: the existence check, the link refusal, the whole-file checksum condition, the
    temporary-name filter.
  - Acceptance: P2 holds on both backends; the S3 calls carry the conditional and checksum arguments;
    `datom_storage_copy()` and `datom_storage_verify()` ignore a temporary file that
    `datom_storage_list()` still shows.

- [ ] **2. Tables: the data file first** (R1.1, R1.3, R1.4, R2.1; design section 3)
  - **Escalation first: design spot-check on a more capable model.**
  - `R/read_write.R`: `.datom_resolve_parquet_sha()` decides and uploads through
    `.datom_storage_upload_absent()`, recording the stored file's hash when the file is already
    there; `datom_write()` calls it before `.datom_write_metadata_local()`;
    `.datom_commit_and_mirror()` loses its `upload` argument.
  - Correct the docstrings that state the old order in the functions touched (R9.4).
  - Create `tests/testthat/helper-interrupt.R`. Rewrite any existing test that asserts the old order
    (design section 10, item 4).
  - Tests: break `datom_write()` at steps 1-5 of R1.1, re-run the same write, and check that a reader
    reads the new version and the stored manifest names it (P1). Step 6 needs heal and lands in task
    4. The recorded hash equals the stored file's hash, including when the file was stored by an
    earlier broken run (P3).
  - Guards to probe: the upload placed before the first clone write; the stored-file branch of the
    hash decision.
  - Acceptance: P1 for steps 1-5 and P3 for `datom_write()`; `research/write_steps_probe.R` shows the
    re-run reading the new version for those steps.

- [ ] **3. Sets: the payload first** (R1.1, R1.5; design section 3)
  - `R/set.R`: `datom_write_set()` builds the payload in a temp file, uploads or adopts it through
    `.datom_resolve_document_sha()`, then writes `set.json`; when the recorded hash is a stored
    payload's and the fresh bytes differ, `set.json` takes the stored bytes.
  - `.datom_restore_set_payload()` uploads through `.datom_storage_upload_absent()`.
  - Tests: break `datom_write_set()` at steps 1-5, re-run, and the set reads (P1); a re-run with a
    different spelling of the same set leaves `set.json` byte-identical to the stored payload (R1.5).
    The test "nothing reaches storage when the git push fails" in `test-write-set.R` becomes "only
    the payload reaches storage".
  - Guards to probe: the stored-spelling branch.
  - Acceptance: P1 for steps 1-5 of `datom_write_set()`; R1.5; `research/set_steps_probe.R` shows the
    re-run reading the set for those steps.

- [ ] **4. Heal** (R2.2-R2.5, R3.1-R3.4, R3.7; DD1, DD4; design section 4)
  - **Escalation first: design spot-check on a more capable model.**
  - New `R/heal.R`: `.datom_heal()`, `.datom_reset_unfinished()`, `.datom_unpublished_artifacts()`,
    `.datom_publish_artifacts()` (the one publish path), `.datom_pushed_artifacts()`. Its docstring
    says what heal repairs and what it leaves (design section 4's table).
  - Wire heal into `datom_write()` (all three routes, with the internal `.healed` argument),
    `datom_write_set()` and `.datom_sync_metadata()`; a write's steps 5-6 move onto
    `.datom_publish_artifacts()`. `R/utils-git.R`: `.datom_git_head_file()`.
  - Resolve design section 10 items 1 (unstaging chosen paths), 3 (an unreadable stored manifest)
    and 5 (message wording and classes) here, and record the answers in `design.md`.
  - Tests: the step-6 case of P1; another artifact's write broken before and after its commit,
    including a set write with `include_paths` (R7.2, P8); two clones with the second behind, and a
    conflict outside the manifest, leaving storage unchanged (R7.6, P5); a failed fetch changing
    nothing (P9); a publish landing behind a colleague's newer one, corrected by the next command
    (P10); no command publishing an uncommitted file (P4).
  - Guards to probe: the reset, the pull before any decision, the re-run entry check, the fetch-failure
    stop, the unpublished-artifact comparison.
  - Acceptance: P1 (all six steps, tables and sets), P4, P5, P8, P9, P10;
    `research/other_command_probe.R` shows `dm` reset (broken before its commit) or published
    (after).

- [ ] **5. A conflict only in the manifest** (R3.8; DD2; design section 5)
  - `R/manifest-rebuild.R`: extract `.datom_manifest_row()` from `.datom_rebuild_manifest_entry()`,
    which keeps its behaviour.
  - `R/heal.R`: `.datom_resolve_manifest_conflict()`; `R/utils-git.R`: `.datom_git_pull()` calls it
    when the manifest is the only conflicted file, so every pull gets it, `datom_pull()` included.
  - Tests (R7.7): two clones writing different tables without a pull in between, and a write whose push
    broke while the other clone pushed, both finish with a manifest naming both tables; two clones
    writing the same table still stop, storage unchanged; the storage-side rebuild's existing tests
    still pass.
  - Guards to probe: the manifest-only condition.
  - Acceptance: P6; `research/two_writers_probe.R` shows the second write finishing.

- [ ] **6. Scan and sync** (R4; DD3; design section 7)
  - `R/sync.R`: `.datom_read_manifest()` gains the `"head"` scope; `datom_sync_manifest()` compares
    against it and reports `unpublished` (fetch first; a failed fetch warns and counts unpushed
    commits only; a behind clone skips the storage comparison and names `datom_pull()`); status
    order as in design section 7.
  - `datom_sync()` heals once instead of calling `.datom_check_git_current()`, then calls
    `datom_write(.healed = TRUE)`; `unpublished` rows come back `success` without an import; a row
    whose write found no change says it was already up to date.
  - Tests: R4.1-R4.5, including a sync broken at its push and re-run, and the stale preview of DD3.
  - Guards to probe: the comparison against the last commit, the behind-clone skip.
  - Acceptance: R4.1-R4.5; `research/sync_and_manifest_probe.R` and
    `research/stale_preview_probe.R` show the table published and the honest message.

- [ ] **7. The repair** (R5; design section 6)
  - `R/sync.R`: `.datom_sync_data_metadata()` heals first (so it pushes), mirrors every artifact,
    then the manifest last (P7); the `datom_write(conn)` prompt says it may push.
  - `R/validate.R`: `datom_validate()` reports per artifact what was reset, pushed and published
    (R5.3); fetches first; `.datom_validate_one_table()` reports `metadata_stale_s3` against the
    version in the clone's last commit (R5.5).
  - Tests: R5.1-R5.4; R7.8 (stale reported and cleared; not reported on a behind clone or for a write
    broken before its commit; a failed fetch skips with a warning).
  - Guards to probe: the reset before publishing, the manifest-last order, the stale comparison, the
    behind-clone skip.
  - Acceptance: R5.1-R5.5, P7, P11.

- [ ] **8. The git and config commands** (R3.5, R3.6; D9, D10)
  - `R/repo.R`: `datom_repo_commit()` calls `.datom_reset_unfinished()` before staging; it, and
    `datom_repo_push()`, `datom_repo_attach_governance()` and `datom_repo_set_data_store()`, name
    the datom artifacts in the commits they push and say they are not yet published.
  - Tests: R7.2's `datom_repo_commit()` cases (with and without `paths`); R3.6 with
    `datom_repo_push()` (message names the artifact, storage unchanged, the next datom write
    publishes it).
  - Guards to probe: the reset in `datom_repo_commit()`.
  - Acceptance: R3.5, R3.6.
  - **Escalation after: purity audit on a more capable model** (tasks 2-8).

- [ ] **9. `datom_init_repo()` re-run** (R6; design section 8)
  - `R/conn.R`: `.datom_init_finish()`, called before the remote is resolved.
  - Tests: a half-initialised folder (manifest upload broken) finishes on a re-run; a different
    project, different storage, a remote without the initial commit, or a stored manifest each refuse
    exactly as today; a break before the push still rolls back.
  - Guards to probe: each of the three conditions.
  - Acceptance: R6.1-R6.3.

- [ ] **10. Documentation** (R8, R9)
  - **Escalation first: test coverage review on a more capable model.**
  - Roxygen for every help page in R9.5, then `devtools::document()`; `NEWS.md` (R9.6; cite only
    `?verb` and `vignette(...)`, never `dev/` or `.kiro/`, conventions item 7a).
  - `dev/datom_specification.md` (R9.2, R9.3); the conventions section in
    `.github/copilot-instructions.md` with the wording in R9.1; the note beside I5 in
    `.kiro/specs/datom-sets/design.md`; `dev/engineering-notes.md` gains design section 12's table.
  - Acceptance: R9.1-R9.6 done; every residual row in design section 12 is guarded or documented
    where the row says.

- [ ] **11. End to end, and spec completion**
  - Rerun every probe in `research/` and record that each now shows the job finished (or, for
    `publish_race_probe.R`, corrected by the next command).
  - `dev/e2e-solo-local.R`, and `dev/e2e-solo-s3.R` against real S3 with the owner's credentials,
    which also settles design section 10 item 2 (`IfNoneMatch` refused with 412; `ChecksumSHA256`
    with `ChecksumType` `FULL_OBJECT`).
  - `devtools::check()`; the full suite; the spec completion procedure (conventions item 7): harvest
    learnings, update `dev/README.md` Active Specs, PR into `dev`.
  - Then resume #134 part 3b on `spec/s3-credential-function` (its requirement R4a.1 may simplify,
    see `requirements.md` "Related").
  - Acceptance: the end-to-end runs pass on both backends; `devtools::check()` is clean; the PR is
    open.
