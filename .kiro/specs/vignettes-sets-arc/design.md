# Design -- vignettes sets arc

Read `requirements.md` first; it says which parts of the owner's brief (`handoff/`) are amended.

## 1. Facts checked against the code (2026-09-26)

So nobody re-derives them. Each was read in the function body, not the roxygen.

| Claim | Holds? | Where |
|---|---|---|
| A prefix `imported/` stores under `imported/datom/` | yes | `.datom_build_storage_key()`, `R/utils-path.R` |
| No-op sync prints `No new or changed files. Nothing to sync.` | yes | `datom_sync()`, `R/sync.R` |
| Sync prints `Wrote "x" (full): "..."` **and** `"x" synced (status).` | yes, both | `datom_write()` then `datom_sync()` |
| `mode = "yolo"` errors; `mode` omitted = ordinary repo | yes | `datom_init_repo()`, `R/conn.R` |
| Product repo refuses `datom_sync()` | yes | `.datom_refuse_import_on_product()` |
| `datom_write_set()` returns the version | **no** -- invisible list; version is `$metadata_sha` | `R/set.R` |
| `include_paths = "R"` commits `R/` in the same commit as the set | yes; path relative to the clone, must exist, must not be gitignored | `.datom_check_include_paths()` |
| Unchanged set + `include_paths` commits nothing, says so | yes | `datom_write_set()` |
| `datom_member()`, `datom_parent()`, `datom_list()`, `datom_history()`, `datom_get_set()`, `datom_fetch_member()`, `datom_update_members()` work on a reader conn | yes | no role checks on those paths |
| `datom_update_members()` matches conns to members by project name, errors on a missing one | yes | `.datom_edit_conns()` |
| Structure leaves are functions of `conn`: `dp$output$liver_flags(conn)` | yes | `.datom_member_link()`, `R/set.R` |
| `datom_add_member()` works on a set read back | **no** -- drafts only | `R/set-draft.R` |
| Cross-project `parents` on `datom_write()` | yes (spec `cross-project-parent-lineage`, all tasks done) | `R/lineage.R`, `R/read_write.R` |
| `datom_storage_delete_prefix()` deletes only `{prefix}/datom/`, no confirm | yes | `R/utils-s3.R` |
| `datom_repo_delete(confirm =)` wants the **project** name; removes GitHub repo + local clone, not storage | yes | `R/repo.R` |

Example-data row counts (`datom_example_data()`, `<=` cutoff):

| Domain | 01-28 | 02-28 | 03-28 | 04-28 |
|---|---|---|---|---|
| dm | 4 | 16 | 25 | 31 |
| ex | 4 | 16 | 25 | 31 |
| lb | 20 | 100 | 205 | 310 |
| ae | 2 | 6 | 12 | 21 |

## 2. The derivation function (A1, A5)

Shown in citable-sets as one chunk headed `# R/derive_liver_flags.R`:

```r
derive_liver_flags <- function(x, conn_input, conn_output) {
  # reads dm, ex, lb through the set (ae stays registered, unused)
  # builds one row per subject: peak ALT/AST vs ULN, dose, age, sex
  # datom_write(conn = conn_output, data = ..., name = "liver_flags",
  #             parents = one datom_parent() per input, at the version x pins)
}
```

- Takes the set **in hand**, so the refresh derives from what was just repointed.
- It writes the output table and nothing else. **Set edits stay in the vignette**, so v2 (append the
  output member, A8) and v3 (repoint it with `datom_update_members(tags = list(type = "output"))`)
  are both visible.
- Pinned versions for `parents` come from `datom_list_members(x)` (columns `name`, `project`,
  `version`, ...).

Refresh sequence (v3):

```
x <- datom_get_set(...)                         # v2
x <- datom_update_members(x, conn_read_imported, tags = list(type = "input"))
derive_liver_flags(x, conn_input = conn_read_imported, conn_output = conn_write_liver_safety)
x <- datom_update_members(x, conn_write_liver_safety, tags = list(type = "output"))
datom_write_set(conn_write_liver_safety, members = x, include_paths = "R")   # v3
```

## 3. The run that produces the transcripts (A6)

New `dev/e2e-vignettes-s3.R`. It **runs the vignettes' own code**, so transcript and code cannot
drift:

1. `knitr::purl()` both Rmds; split on the `## ----label----` headers purl emits.
2. Execute chunks in order in one session, capturing each chunk's console output keyed by label.
3. Chunks handled specially, by label:
   - `keyring-setup` -- skipped (interactive prompts).
   - `secrets` -- skipped. macOS authorises keychain access per binary, so keyring does not work
     under `Rscript` (see `dev/engineering-notes.md`). The run reads the environment.
   - `settings` -- run, then overridden from the environment (`DATOM_E2E_BUCKET`, region), because
     the bucket in the vignette is illustrative.
   - `derive-script` -- written to `workdir_liver_safety/R/derive_liver_flags.R` and sourced, not
     evaluated inline.
   - `teardown-imported` in start-on-s3 -- skipped: the walk continues into citable-sets, whose
     `teardown` chunk deletes both projects and runs only in `--teardown` mode.
4. Startup: fixed resource names, delete-if-exists (repos and prefixes) -- the lesson from the last
   spec: timestamped names orphan quietly, fixed names collide loudly.
5. Teardown is a separate step (`--teardown`), not a `finally`, so a failed walk leaves state to
   inspect.
6. Output: one markdown transcript, one section per chunk label, under `tempdir()` path printed at the
   end. Non-zero exit if any chunk errors.

Consequence for the Rmds: every chunk gets a **label**, and the labels above are fixed names.

## 4. Invariants

- I1: no `R/`, `NAMESPACE`, `man/` or test change.
- I2: printed output is never edited except `...` truncation (AC-A6). The last merged PR's own commit
  message records breaking this; do not repeat it.
- I3: no citation of `dev/` or `.kiro/` from either vignette.
- I4: `eval = FALSE` stays -- vignettes need credentials to run, CRAN has none.
