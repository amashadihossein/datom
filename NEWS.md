# datom (development version)

## Phase 17 -- Portfolio helpers

**New functions:**

* `datom_summary(conn)` -- compact, role-aware overview of a single project (name, role, backend/root/prefix, table count, total versions, last write, and -- for developers -- the data git remote URL). Returns an S3 `datom_summary` object with a `print` method. Reads `.metadata/manifest.json`.
* `datom_projects(x)` -- lists every project registered in the shared governance repo. Accepts either a `datom_conn` (uses the local gov clone when present -- offline, fast) or a `datom_store` (lets a caller enumerate the portfolio before connecting to any one project). Returns a sorted data frame: `name`, `data_backend`, `data_root`, `data_prefix`, `registered_at`. Corrupt registry entries warn and are skipped.

**Schema additions (pre-release; no migration concern):**

* `ref.json`: `current$type` and `previous[].type` now record the data backend (`"s3"` or `"local"`). Required so readers can identify the backend without already holding a store.

**Internal:**

* New storage list dispatch: `.datom_storage_list_objects(conn, prefix)` with `.datom_s3_list_objects()` and existing `.datom_local_list_objects()` arms.
* `.datom_gov_list_projects(gov_conn, gov_local_path)` -- prefers the local gov clone; falls back to a storage walk. Pure read; not a `GOV_SEAM` helper.

## Phase 15 -- Separate governance repo

**Breaking changes:**

* `datom_store()`: argument `remote_url` renamed to `data_repo_url`. New arguments `gov_repo_url` and `gov_local_path` for the shared governance repository.
* `project.yaml`: `repos` block now has two children, `repos.data` and `repos.governance` (each with `remote_url`; the latter also has `local_path`).
* `dispatch.json`, `ref.json`, `migration_history.json` no longer live in the data repo's `.datom/` directory. They live in the governance repo at `projects/{project_name}/{file}.json` and are mirrored to governance storage at the same path.

**New functions:**

* `datom_init_gov()` — one-time bootstrap of a shared governance repository (one per organization / governance bucket).
* `datom_decommission()` — tear down a project (data storage + GitHub repo + governance entry). Requires `confirm = "{project_name}"` literal match.
* `datom_pull_gov()` — pull the governance repo only (rare; mostly for diagnostics).

**Changed behavior:**

* `datom_clone()` now clones both the data repo and the governance repo (sibling default; reuses existing gov clone if it matches `gov_repo_url`).
* `datom_pull()` now pulls both repos by default.
* `datom_sync_dispatch()` now produces a governance-repo commit (and storage upload) for `projects/{project_name}/dispatch.json`. The data repo is untouched.
* `datom_init_repo()` now requires `gov_repo_url` on the store and writes `projects/{project_name}/{ref,dispatch,migration_history}.json` to the governance repo + storage in a separate commit from the data repo's initial commit. Two distinct commits across two histories.
* Connection objects gain a `gov_local_path` field. Developer connections read `ref.json` from the local gov clone; reader connections read it from gov storage. The write-time guard always reads from storage to detect stale clones.

## Other

* Pre-release. The API is experimental and may change without notice.
