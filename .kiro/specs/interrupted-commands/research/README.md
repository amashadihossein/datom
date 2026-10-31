# Research scripts for the interrupted-commands spec

Throwaway probes run on 2026-10-28 on `dev` at `347a403`. Each builds a project from scratch with a
folder git remote and local storage (no AWS, no GitHub), breaks one step with a mocked binding, and
reports what a reader sees. Nothing in `R/` is edited. Each script does its work inside `main()`,
because `on.exit()` at the top level of `Rscript` never fires.

Rerun from the repo root, for example:

    Rscript .kiro/specs/interrupted-commands/research/write_steps_probe.R

- `write_steps_probe.R`: `datom_write()` broken at commit, push, upload, metadata and manifest, then
  the same write re-run.
- `set_steps_probe.R`: the same for `datom_write_set()` on a product repo, then
  `datom_validate(fix = TRUE)`.
- `sync_and_manifest_probe.R`: `datom_sync()` broken at the push, then re-scanned and re-synced; and
  a write broken at the manifest step, then compared with what a reader's `datom_list()` shows.
- `other_command_probe.R`: a write of `dm` broken at its commit or its push, then a write of `lb`;
  reads GitHub's copy of the manifest and of `dm/metadata.json` with the git CLI.
- `two_writers_probe.R`: two clones of one project write different tables without pulling in
  between; reports whether the second write's push hits a merge conflict, and in which files
  (result: a conflict in `.datom/manifest.json` only).
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

Results are recorded in `../requirements.md` ("Findings") and `../design.md` ("Proven, and not yet
traced").
