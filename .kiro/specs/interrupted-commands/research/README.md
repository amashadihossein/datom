# Research scripts for the interrupted-commands spec

Throwaway probes run on 2026-10-28 on `dev` at `347a403`. Each builds a project from scratch with a
folder git remote and local storage (no AWS, no GitHub), breaks one step with a mocked binding, and
reports what a reader sees. Nothing in `R/` is edited. Each script does its work inside `main()`,
because `on.exit()` at the top level of `Rscript` never fires.

Rerun from the repo root, for example:

    Rscript .kiro/specs/interrupted-commands/research/write_steps_probe.R

- `write_steps_probe.R`: `datom_write()` broken at each step, then the same write re-run. Updated
  in task 2 (2026-10-31) for the new order: the upload break replaces `.datom_storage_upload_absent()`,
  and breaks after the clone files and at the stored history upload are added; a row counts only if
  `raised` is `TRUE`. Result after task 2: every break fired; for the upload, the clone files, the
  commit, the push, the metadata step and the history upload, the re-run reads v2; a break at the
  manifest upload still leaves the re-run reporting `none` with the stored manifest one version
  behind, which heal's publish (task 4b) finishes. Rerun after task 4b (2026-11-06): every break
  fired and every re-run reads v2; from the push on, the re-run reports `none` because heal's
  publish finished the committed version first. (The probe does not print the stored manifest;
  `test-interrupted-write.R` checks it names v2 after every step's re-run.)
- `set_steps_probe.R`: the same for `datom_write_set()` on a product repo, then
  `datom_validate(fix = TRUE)`. Updated in task 3 (2026-10-31) the same way: the upload break
  replaces `.datom_storage_upload_absent()`, and breaks after the clone files, at the stored history
  upload and at the stored manifest upload are added. Result after task 3: every break fired; for
  the upload, the clone files, the commit, the push, the metadata step and the history upload, the
  re-run reads v2. A break at the manifest upload leaves readers on v2 already (a set read follows
  the stored `metadata.json`) and the re-run reporting `none` with the stored manifest one version
  behind, which heal's publish (task 4b) finishes. Rerun after task 4b (2026-11-06): every break
  fired, every re-run reads v2, and from the push on the re-run reports `none` (heal finished it;
  `test-interrupted-set.R` checks the stored manifest).
- `sync_and_manifest_probe.R`: `datom_sync()` broken at the push, then re-scanned and re-synced; and
  a write broken at the manifest step, then compared with what a reader's `datom_list()` shows.
- `other_command_probe.R`: a write of `dm` broken at its commit or its push, then a write of `lb`;
  reads GitHub's copy of the manifest and of `dm/metadata.json` with the git CLI. Updated in task
  4a (2026-11-04): a row counts only if its break fired, and it reports whether `lb`'s write
  stopped. Result after task 4a: both breaks fired; after `dm` broke at its commit, `lb`'s write
  stops (`datom_unfinished_work`), naming `dm`'s three files and `datom_validate(fix = TRUE)`, with
  HEAD unmoved and nothing of `lb` in storage; after `dm` broke at its push, `lb`'s write still goes
  ahead and pushes `dm`'s commit, which task 4b's stop on a differing row ends. Rerun after task 4b
  (2026-11-06): both breaks fired, and after `dm`'s push break `lb`'s write now stops too
  (`datom_unfinished_work`, "storage and this clone name different versions"), before pushing
  anything: HEAD unmoved, GitHub's log and storage still at `dm` v1, nothing of `lb` in storage.
- `two_writers_probe.R`: two clones of one project write different tables without pulling in
  between; reports whether the second write's push hits a merge conflict, and in which files
  (result: a conflict in `.datom/manifest.json` only). Updated in task 5 (2026-11-06): since task
  4a every write pulls first, so the other clone's write is now run right after this write's
  commit (a mocked `.datom_git_commit()` that fires once), landing its push between this write's
  pull and its own push. Result after task 5: the second write reports `full` and says it rebuilt
  `lb`'s manifest row and finished the merge; HEAD is the two-parent "Merge finished by datom
  (manifest rebuilt)" with no `MERGE_HEAD` left; the stored manifest names `ae`, `dm` and `lb`, and
  a reader reads both new tables.
- `merge_completion_probe.R`: after such a conflict, rewrites the manifest, stages it and commits
  through git2r (R3.8). Result: a two-parent merge commit, `MERGE_HEAD` removed, the push lands,
  and a fresh clone sees every table.
- `git2r_primitives_probe.R`: the git2r calls the design relies on, on a throwaway repo: read a file
  as committed in HEAD, list files changed between two commits, reset chosen files to HEAD leaving
  others alone, see an untracked directory. All four work on git2r 0.36.2.
- `stale_preview_probe.R` (DD3): you build a sync preview, a colleague imports the same file and
  pushes, you pull and sync with the old preview. Result: the write finds no change, stores nothing,
  and the row reports `success` (its line wrongly says "synced (new)").
- `publish_race_probe.R` (design DD4): you push `dm` v2; before your publish runs, a colleague
  pulls, writes v3, pushes and publishes it; then your publish lands. Result on today's code: GitHub's
  latest is v3, storage's current is v2, and a reader gets v2.

- `s3_conditional_probe.R` (task 1; **real AWS S3**, unlike the rest): the data-file upload against
  real S3, on three paws version pairs (installed here; the declared minimum, `paws.storage` 0.8.0
  with `paws.common` 0.8.0; CRAN's current). Checks that an "only if absent" upload of a stored key
  is refused with 412 and reported as `"exists"`, that `head_object` returns a `FULL_OBJECT`
  `ChecksumSHA256` equal to the file's SHA-256, and that S3 refuses a wrong checksum. Needs
  `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in the environment (bucket `datom-test` unless
  `DATOM_PROBE_BUCKET` is set); writes only under `datom-probe/s3-conditional/datom/`, deleted at
  the start and the end. The two older or newer paws pairs are installed on first run into
  throwaway libraries under `/tmp`, never into your own library. Runs with `Rscript` or `source()`
  from any working directory (it loads datom from the repo it sits in). A pair passes only if its
  child process prints a result line with every check passed; `DATOM_PROBE_FAKE_S3=1` runs the
  same walk offline against an in-memory stand-in, to test the script itself.

Added 2026-10-30 during the design reviews (local only, no AWS or GitHub; recorded in `../design.md`
section 10):

- `clone_snapshot_probe.R`: writes `dm` three times, lists the clone, and records the keys the old
  repair's per-artifact copy writes. Result: no datom command puts `{name}/.metadata/` in a clone, so
  that copy never published a snapshot.
- `snapshot_sources_probe.R`: a hand edit of `metadata.json` published by the metadata-only route,
  and a write broken at its metadata upload followed by `datom_validate(fix = TRUE)`. Result: the
  hand edit leaves a stored `metadata.json` whose version no history entry, manifest row or snapshot
  records, while readers are told the previous version.
- `merge_state_probe.R`: what git2r reports during a conflicted merge (`.git/MERGE_HEAD`, files
  listed as `conflicted` under `unstaged`) before and after resolving one file.
- `merge_restore_probe.R`: `git checkout --theirs` on a file that merged cleanly does nothing
  ("Updated 0 paths"), while `git checkout MERGE_HEAD -- <files>` takes the remote copy of conflicted
  and clean files alike; `git commit` then completes the merge.

Added 2026-10-31 during the review of `058f29b` (local only; recorded in `../design.md` section 10):

- `merge_source_probe.R`: for each kind of merge in progress, whether the commit being merged in is
  the upstream tip as last fetched or behind it. Result: yes for datom's own conflicted pull (also
  after a later `git fetch`) and for a user's `git pull`; no for a user's `git merge --no-commit` of
  a local branch and for a merge of another remote's branch. This is the merge check's test for a
  merge of the remote branch (requirements R3.9).
- `dirty_pull_probe.R` (2026-10-31, design spot-check before task 4a): part 1, git2r only, fetches
  and merges the upstream with the user's files in the way. Result on git2r 0.36.2: with a modified
  or staged file the incoming commits change, or an untracked file where they add one, with or
  without commits of the clone's own, `merge()` raises no error, returns `conflicts = NULL`, and
  HEAD does not move; the controls catch up (a fast-forward returns `sha = NA`). Part 2, through a
  real datom project: plain `git stash` leaves the untracked file, and `datom_pull()` reports
  success while still behind; `git stash -u` then `datom_pull()` catches up, and `git stash pop`
  reports a conflict or "already exists", keeping the stash. This is the pull's caught-up check
  (requirements R3.7). Rerun after task 4a (2026-11-04): part 1 unchanged (it is git2r alone); in
  part 2 the plain-`git stash` case now has `datom_pull()` stop with the `git stash -u` message
  (`datom_pull_blocked`) instead of reporting success, and the two `-u` cases catch up as before.

Added 2026-10-31 in task 2 (a tool, not a finding):

- `task2_guard_probes.R`: the guard-probe harness task 2 used, kept as a template for later tasks.
  Each probe applies one deliberate edit to `R/` or a test file, runs the named test files in a fresh
  `Rscript` process (a probe counts only if that child prints its `RESULT` line, and both failures
  and errors are counted), and restores every file from a fixed backup taken once from a tree that
  parses; a control edit runs first and must redden nothing. Task 2's results are in its commit
  message. Before reusing it, copy it, replace the probe list, give the backup folder a new name, and
  check each edit still matches exactly once (the harness refuses an edit that does not). It deletes
  its backup after a clean run; one left behind (after a crash) is restored over the tree by the
  next run, so delete a stale one by hand before running against newer code.

Results are recorded in `../requirements.md` ("Findings") and `../design.md` ("Proven, and not yet
traced").
- `task3_guard_probes.R`: the same harness with task 3's probes (the payload stored before the
  clone changes, the stored spelling copied to `set.json`, the S3 upload sending the hash it is given,
  the resolvers passing their hash, the set resolver's history branch, the restore's two branches, and
  the re-pointed repair counter with its old-function twin). Results in task 3's commit message.

Added 2026-11-04 in task 4a:

- `task4a_git_facts_probe.R`: git2r facts task 4a's code relies on (git2r 0.36.2). (1)
  `git2r::reset(repo, path = )` unstages chosen paths: a staged edit becomes an unstaged one, a
  staged new file becomes untracked; `checkout(path =, force = TRUE)` then restores the tracked one
  (design section 10, item 1). (2) `git2r::merge(commit_on_success = FALSE)` of a local branch that
  has diverged leaves `MERGE_HEAD` and `MERGE_MSG` ("Merge branch 'feature'") with nothing
  conflicted, as `git merge --no-commit` does; one that can fast-forward just moves HEAD. (3) A push
  of a clone behind its remote fails with "cannot push because a reference ... contains commits that
  are not present locally" before a fetch and "cannot push non-fastforwardable reference" after one,
  with or without an upstream branch. (4) `git2r::stash(untracked = TRUE)` and `stash_pop()` set
  aside and restore a modified and an untracked file.
- `task4a_guard_probes.R`: the harness with task 4a's probes (the merge check's two stops and each
  half of its test, the reset, the stop on another artifact's files, the manifest-row check, the
  folder rules, merge only when behind, a fast-forward counting as a merge, the re-run entry check,
  the fetch-failure stop, the caught-up check, the rejected-push message, the pull before change
  detection, a refusal check placed before heal, the floor read from `project.yaml`). Results in
  task 4a's commit message.
- `task4b_guard_probes.R`: the harness with task 4b's probes (the unpublished-row comparison, a
  stored row the clone lacks, the manifest last and held back after a failure, the publish gate,
  the stop on another artifact's row, step d counting `artifact` as the command's own, the
  containment check and its "older" variant, the repair's override, the manifest agreement check,
  heal's push not pulling, the shared reader's stop, reading the history before writing, the reset
  limited to `rewrite`, the `rewrite` subset check, the "changed nothing" line). Same usage as task
  4a's; the whole sweep takes about two minutes. Results are in task 4b's commit message.

Added 2026-11-06 in task 5:

- `task5_guard_probes.R`: the harness with task 5's probes (the manifest-only condition at the
  pull, both as "never" and as "whenever the manifest is among the conflicts"; the row-against-files
  comparison; the version the files describe; starting from the merged-in side's copy; the format
  check before the rebuild; the merge check's finishing branch; `finish_merge`, its passing through
  `datom_pull()`, and the other-merge stop while a file still conflicts under it). Same usage as
  task 4b's; the whole sweep takes about four minutes. Results are in task 5's commit message.
