# Design -- set sync ergonomics

Read `requirements.md` first. Everything here serves one of its R-numbers.

## 1. Facts checked against the code (2026-09-27, `dev` at `7d55a8b`)

| Fact | Where |
|---|---|
| `datom_sync_manifest(conn, path = NULL, pattern = "*")`, `datom_sync(conn, manifest, continue_on_error = TRUE)` | `R/sync.R` |
| Both call `.datom_refuse_import_on_product()`, which re-reads `.datom/project.yaml` (schema-checked) and aborts `datom_import_on_product` | `R/sync.R` |
| The file manifest is a plain `data.frame`; `datom_sync()` checks column names only, so row subsets already pass | `R/sync.R` |
| Table sync saves per table: `datom_write()` uploads, commits, pushes | `R/sync.R`, `R/read_write.R` |
| `datom_add_member()` refuses anything but a draft (`datom_not_a_draft`) and logs no edits | `R/set-draft.R` |
| `datom_update_members()` / `datom_remove_members()` accept both classes, save nothing, append to `attr(x, "datom_edits")` (`action, project, name, kind, from, to`) | `R/set-edit.R` |
| Commit subject built by `.datom_set_commit_messages()` knows `repoint` and `remove` only | `R/set-edit.R` |
| "Current" per project comes from `.datom_current_artifact_versions(conn)`, one manifest read per project | `R/set-edit.R` |
| A sweep skips two members sharing project + name and reports them | `datom_update_members()` |
| `.datom_edit_conns()` keys connections by `conn$project_name`, refuses duplicates | `R/set-edit.R` |
| `.datom_repoint_member()` rebuilds via `datom_member()`, restores labels verbatim, refuses a project change | `R/set-edit.R` |
| `.datom_find_member()` is the single-member resolver (`datom_member_not_found`, `datom_member_ambiguous`) | `R/set-members.R` |
| `datom_parent(conn, table, version)` returns `source, table, version, data_sha, source_lineage`; no kind check | `R/lineage.R` |
| Tables store parents lean (`source, table, version, data_sha`) in their snapshot | `R/read_write.R` |
| `datom_write_set()` reads the edit log off `x`, runs gates -> write-entry door -> ref guard -> include-path checks, then tidies and hashes | `R/set.R` |
| `datom_get_set()` returns `name, project, version, data_sha, tags, members`, no connection | `R/set.R` |
| `datom_example_data()` domains `dm, ex, lb, ae`; default is the first | `R/example-data.R` |
| `data-raw/simulate_study_data.R` uses one `set.seed()` stream, then writes the CSVs and `R/sysdata.rda` | `data-raw/` |

## 2. Context selection (R1)

One internal helper answers "which context is this call in?" by reading `.datom/project.yaml` through
the same gated parse `.datom_refuse_import_on_product()` uses today (a decision that can authorise a
write reads the file, not the connection). Each sync verb then branches once, at the top:

| Repo | `sources` | Result |
|---|---|---|
| ordinary | absent | today's code path, untouched |
| ordinary | given | abort `datom_sync_sources_on_ordinary` |
| product | absent | abort `datom_import_on_product`, message now names `sources =` |
| product | given | set path |

The set path lives in a new file `R/sync-set.R`; `R/sync.R` only gains the branch. Keeping the class
`datom_import_on_product` for the refusal keeps the six existing tests and the E2E claim meaningful.

## 3. The preview (R2)

Built from three reads: the set (stored, via `datom_get_set()` on the developer conn; absent means
first version), one manifest per source (`.datom_current_artifact_versions()`), nothing per table.

Rows, in order:

1. **Source tables** (kind `table`, name matching `pattern`). Keyed to set members by
   (`project`, `name`), where `project` is the source connection's label, exactly as
   `.datom_edit_conns()` keys today. The declared project is verified at apply (section 4).
   - no matching member -> `new`, `version_from = NA`
   - one member, same version -> `unchanged`; different -> `changed`
   - two or more members -> `ambiguous` (R2.6)
2. **Members not covered**: members whose project is neither a source nor the set's own project ->
   `not_checked`, `version_to = NA` (R2.7).
3. **Members whose table left its source**: reported in the message, not as rows that could apply.

Own project (R2.5): a source whose label equals the set's own project stops before any read. The
set's project comes from the developer conn, which reads `.datom/project.yaml`, so it is trustworthy.

Messages: one summary line (`Mapped N tables from K sources: a new, b changed, c unchanged.`), then
one warning per `ambiguous` / `not_checked` group with its remedy.

## 4. Applying (R3)

`datom_sync(conn, manifest, sources, tags = list(type = "input"), x = NULL)`.

- Required columns: `project, name, kind, version_from, version_to, status`. Values: `status` in the
  five-value set, `version_to` a full 64-hex string on `new` / `changed` rows.
- `x` omitted: read the stored set, or start an empty `datom_set` (name from `project.yaml`, project
  from the conn, `version = NULL`) on first version.
- Per `changed` row: find the member by (`project`, `name`); its version must equal `version_from`,
  else abort `datom_sync_manifest_stale`. Repoint through `.datom_repoint_member()` (labels verbatim,
  project change refused).
- Per `new` row: `datom_member(sources[[project]], name, version_to, tags = tags)`. That read is what
  validates the version exists and records the **declared** project. A declared project that differs
  from the row's aborts, as a repoint does.
- **Why `sources` is passed again**: building a member without reading its snapshot would trust a
  hand-edited row's version and project, and a set pointing at a version that does not exist is found
  only when someone fetches it. Re-reading is one snapshot per applied row.
- Edits: `repoint` rows as today, new `add` rows (`from = NA`, `to = version`). `.datom_forget_set_identity()`
  when anything changed. Report, then the not-written line.

## 5. `datom_add_member()` (R4)

- Class check widens to `datom_set`. Names resolve through `conn %||% x$conn`; a `datom_set` with a
  name and no `conn` aborts `datom_member_conn_required`.
- The clash check (duplicate skipped, same version with different labels refused) applies to both.
- On a `datom_set` only: `.datom_forget_set_identity()`, append an `add` edit. Drafts log nothing, so
  a draft write keeps its current commit message.
- `.datom_set_commit_messages()` gains `add = "add"` ahead of `repoint` and `remove`;
  `.datom_edit_lines()` shows `  name  added at <version>`.

## 6. `datom_parent()` (R5)

`datom_parent(conn, table, version = NULL, x = NULL, tags = NULL)`.

- Exactly one of `version`, `x` (`datom_parent_version_or_set`). `tags` without `x` refused.
- Without `x`: today's body, unchanged, returns one record.
- With `x`: for each `table`, `.datom_find_member(x$members, table, tags)`; a set-kind member aborts
  `datom_parent_not_a_table`; then today's body with the member's version. Returns a list.

## 7. Provenance check (R6)

A new internal `.datom_check_set_parents(conn, name, members)`, called in `datom_write_set()`
**right after `.datom_check_set_payload()` and before `.datom_build_set_metadata()`** (the first
hash). Still above every hash and every local write, so R6.2 holds. Not earlier (the original plan
said "after the include-path checks, before tidy"): there the members are unvalidated, so a
malformed member would reach a snapshot read and fail with a storage error instead of the
validator's message. Agreed with the owner 2026-09-28.

- For each member whose project is the set's own project (all tables: a product repo holds one set,
  and a set listing itself is refused first, so no kind filter is needed): read its snapshot
  (`.datom_artifact_snapshot_key()`, storage) and take `parents`.
- **Check the snapshot's format number before reading `parents`**, with
  `.datom_check_schema_version(snap, key)`, as `.datom_parent_record()` and `datom_member()` do: a
  snapshot from a newer datom stops the set write and says to upgrade. Call it **outside** any
  `tryCatch` around the read, so the refusal keeps its own class and message instead of being
  reworded as a read failure (same pairing as `.datom_parent_record()`). Agreed with the owner
  2026-09-28.
- **A snapshot that cannot be read stops the write**, naming the member and the underlying error
  (new class `datom_set_member_unreadable`). This covers both a version that does not exist and
  storage that cannot be reached. Why stop rather than skip: a missing version means the set would
  point at data nobody can fetch, and unreachable storage would fail the write anyway, only later,
  after the local files are written. Agreed with the owner 2026-09-28.
- **Metadata only.** The read is the one small JSON snapshot per member, through
  `.datom_storage_read_json()`; no parquet is downloaded. So a readable snapshot proves the version
  was recorded, not that its data file is still in storage. That stays `datom_validate()`'s job
  and is out of scope here.
- For each parent: members with that (`project = source`, `name = table`). If some exist and none is
  at `parent$version`, collect a mismatch.
- Any mismatch aborts `datom_set_parent_mismatch`, one line per member / parent / pinned / used.
- Cross-project members are not read: the write holds no connection to their projects.

## 8. Example data (R7)

- In `data-raw/simulate_study_data.R`, generate `vs` **after `ae`, before the writes**, continuing
  the same RNG stream, so every earlier draw is untouched. Tests: `SYSBP`, `DIABP`, `PULSE` at the
  three `lb` visit dates -> 432 rows.
- Verification before keeping anything: run the script, then `git diff --exit-code inst/extdata/dm.csv
  inst/extdata/ex.csv inst/extdata/lb.csv inst/extdata/ae.csv`. `R/sysdata.rda` may differ only in
  serialisation header; check `identical()` on the loaded value and, if identical, restore the
  committed file.
- `datom_example_data()` gains `"vs"` **last** in the choices (default stays `"dm"`) and `vs = "VSDTC"`.

## 9. Vignette (R8)

The agreed shape:

```r
m <- datom_sync_manifest(conn = conn_write_liver_safety, sources = list(conn_read_imported))
x <- datom_sync(conn = conn_write_liver_safety, manifest = m, sources = list(conn_read_imported))
datom_write_set(conn = conn_write_liver_safety, members = x, tags = list(description = "..."))

x <- datom_get_set(conn = conn_read_liver_safety, name = set_liver_safety)
liver_flags <- derive_liver_flags(x = x, conn_input = conn_read_imported)      # data frame
written <- datom_write(conn = conn_write_liver_safety, data = liver_flags, name = "liver_flags",
  parents = datom_parent(conn = conn_read_imported, table = c("dm", "ex", "lb"), x = x))
x <- datom_add_member(x = x, member = "liver_flags", version = written$metadata_sha,
  tags = list(type = "output"), conn = conn_read_liver_safety)
datom_write_set(conn = conn_write_liver_safety, members = x, include_paths = "R")

# refresh: month-4 extract adds vs
m <- datom_sync_manifest(...);  x <- datom_sync(...)          # vs new, four changed
liver_flags <- derive_liver_flags(x = x, conn_input = conn_read_imported)
datom_write(..., parents = datom_parent(..., x = x))
x <- datom_update_members(x = x, conn = conn_read_liver_safety, tags = list(type = "output"))
datom_write_set(conn = conn_write_liver_safety, members = x, include_paths = "R")
```

`dev/e2e-vignettes-s3.R` needs no structural change; its local backend dry-runs the new chunks
first. `start-on-s3` chunks re-run unchanged and their outputs must match what is recorded (a check,
not an edit).

## 10. Invariants

- I1 Ordinary-repo sync: no change to arguments, columns, messages or return.
- I2 Nothing on the set sync path saves; `datom_write_set()` remains the only set persister.
- I3 A refusal anywhere leaves nothing written.
- I4 The four existing example CSVs are byte-identical.
- I5 `start-on-s3.Rmd` is untouched.
- I6 No `dev/` or `.kiro/` citation from anything that ships.

## 11. Correctness properties (tested)

- P1 Idempotence: applying a preview, then previewing again, shows no `new` or `changed` rows.
- P2 Subset: applying a row subset changes exactly the members its `new` / `changed` rows name.
- P3 Labels: a repointed member's labels are identical before and after.
- P4 Same resolver: for any `table` / `tags`, `datom_parent(x = )` picks the version
  `datom_fetch_member()` would.
- P5 Round trip: sync -> write -> get returns the members the preview promised.
