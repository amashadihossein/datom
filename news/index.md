# Changelog

## datom (development version)

### Phase 16 – Vignette overhaul

The vignette set is rewritten as a continuous user journey: STUDY-001
over six months, climbing from a single engineer’s first extract to a
manager’s portfolio audit. Ten user-journey articles plus six design
notes replace the previous three vignettes (`clinical-data-versioning`,
`team-collaboration`, `credentials`).

**User journey** (sidebar order):

1.  *First Extract* – `datom_store_local`, `datom_init_gov`,
    `datom_init_repo`, `datom_write`, `datom_read`.
2.  *Month 2 Arrives* – change detection, `datom_history`,
    version-pinned reads.
3.  *A Folder of Extracts* – `datom_sync`, `datom_status`,
    `datom_validate`.
4.  *Promoting to S3* – `datom_store_s3`, `create_repo = TRUE`,
    `ref.json` indirection.
5.  *Handing Off to a Statistician* – reader role, parallel R session,
    version pinning for reproducibility.
6.  *A Second Engineer Joins* – `datom_clone`, `datom_pull`, conflict
    recovery.
7.  *Governing a Study Portfolio* – registry, `datom_pull_gov`,
    `datom_decommission`.
8.  *Auditing & Reproducibility* – `datom_summary`, `datom_projects`,
    full-SHA history, `datom_validate` across the portfolio.
9.  *Looking Ahead: datom in the daapr Stack* – substrate framing.
10. *Credentials in Practice* – store construction, roles, recovery
    utilities reference.

**Design notes**: `design-datom-model`, `design-version-shas`,
`design-ref-json`, `design-dispatch`, `design-two-repos`,
`design-serverless`.

**Other changes:**

- Simulator extended with LB (lab) and AE (adverse events) domains.
  [`datom_example_data()`](https://amashadihossein.github.io/datom/reference/datom_example_data.md)
  gains `"lb"` and `"ae"` choices.
- `inst/vignette-setup/resume_article_N.R` lets jump-in readers rebuild
  the prior article’s end state in one line. Idempotent; honors
  `DATOM_VIGNETTE_DIR`.
- `README.Rmd` rewritten as a one-screen grabber using the local
  backend.
- `_pkgdown.yml` sidebar reorganized into Get Started / Scale Up /
  Govern / Reference / Design groups.

### Phase 17 – Portfolio helpers

**New functions:**

- `datom_summary(conn)` – compact, role-aware overview of a single
  project (name, role, backend/root/prefix, table count, total versions,
  last write, and – for developers – the data git remote URL). Returns
  an S3 `datom_summary` object with a `print` method. Reads
  `.metadata/manifest.json`.
- `datom_projects(x)` – lists every project registered in the shared
  governance repo. Accepts either a `datom_conn` (uses the local gov
  clone when present – offline, fast) or a `datom_store` (lets a caller
  enumerate the portfolio before connecting to any one project). Returns
  a sorted data frame: `name`, `data_backend`, `data_root`,
  `data_prefix`, `registered_at`. Corrupt registry entries warn and are
  skipped.

**Schema additions (pre-release; no migration concern):**

- `ref.json`: `current$type` and `previous[].type` now record the data
  backend (`"s3"` or `"local"`). Required so readers can identify the
  backend without already holding a store.

**Internal:**

- New storage list dispatch: `.datom_storage_list_objects(conn, prefix)`
  with
  [`.datom_s3_list_objects()`](https://amashadihossein.github.io/datom/reference/dot-datom_s3_list_objects.md)
  and existing
  [`.datom_local_list_objects()`](https://amashadihossein.github.io/datom/reference/dot-datom_local_list_objects.md)
  arms.
- `.datom_gov_list_projects(gov_conn, gov_local_path)` – prefers the
  local gov clone; falls back to a storage walk. Pure read; not a
  `GOV_SEAM` helper.

### Phase 15 – Separate governance repo

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
