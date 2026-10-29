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

Results are recorded in `../requirements.md`, "Findings".
