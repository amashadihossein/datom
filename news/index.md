# Changelog

## datom (development version)

### Phase 15 — Separate governance repo

**Breaking changes:**

- [`datom_store()`](https://amashadihossein.github.io/datom/reference/datom_store.md):
  argument `remote_url` renamed to `data_repo_url`. New arguments
  `gov_repo_url` and `gov_local_path` for the shared governance
  repository.
- `project.yaml`: `repos` block now has two children, `repos.data` and
  `repos.governance` (each with `remote_url`; the latter also has
  `local_path`).
- `dispatch.json`, `ref.json`, `migration_history.json` no longer live
  in the data repo’s `.datom/` directory. They live in the governance
  repo at `projects/{project_name}/{file}.json` and are mirrored to
  governance storage at the same path.

**New functions:**

- [`datom_init_gov()`](https://amashadihossein.github.io/datom/reference/datom_init_gov.md)
  — one-time bootstrap of a shared governance repository (one per
  organization / governance bucket).
- [`datom_decommission()`](https://amashadihossein.github.io/datom/reference/datom_decommission.md)
  — tear down a project (data storage + GitHub repo + governance entry).
  Requires `confirm = "{project_name}"` literal match.
- [`datom_pull_gov()`](https://amashadihossein.github.io/datom/reference/datom_pull_gov.md)
  — pull the governance repo only (rare; mostly for diagnostics).

**Changed behavior:**

- [`datom_clone()`](https://amashadihossein.github.io/datom/reference/datom_clone.md)
  now clones both the data repo and the governance repo (sibling
  default; reuses existing gov clone if it matches `gov_repo_url`).
- [`datom_pull()`](https://amashadihossein.github.io/datom/reference/datom_pull.md)
  now pulls both repos by default.
- [`datom_sync_dispatch()`](https://amashadihossein.github.io/datom/reference/datom_sync_dispatch.md)
  now produces a governance-repo commit (and storage upload) for
  `projects/{project_name}/dispatch.json`. The data repo is untouched.
- [`datom_init_repo()`](https://amashadihossein.github.io/datom/reference/datom_init_repo.md)
  now requires `gov_repo_url` on the store and writes
  `projects/{project_name}/{ref,dispatch,migration_history}.json` to the
  governance repo + storage in a separate commit from the data repo’s
  initial commit. Two distinct commits across two histories.
- Connection objects gain a `gov_local_path` field. Developer
  connections read `ref.json` from the local gov clone; reader
  connections read it from gov storage. The write-time guard always
  reads from storage to detect stale clones.

### Other

- Pre-release. The API is experimental and may change without notice.
