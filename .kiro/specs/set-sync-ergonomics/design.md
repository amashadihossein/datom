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
`datom_import_on_product` for the refusal keeps the four existing tests in `test-sync.R` (lines
~34-110, fixture `sync_product_repo()`) and the `dev/e2e-sets-s3.R` claim (line ~318) meaningful.
Those tests assert the message names `datom_sync_manifest`, `datom_write`, `datom_write_set` and the
set's name, so the reworded message keeps all four and adds a line naming `sources =`.

**Spot-check additions (2026-09-28, checked against `R/sync.R`):**

- **Signatures, new arguments LAST.** R1.3 / I1 keep positional calls working, and today's verbs are
  `datom_sync_manifest(conn, path = NULL, pattern = "*")` and
  `datom_sync(conn, manifest, continue_on_error = TRUE)`. So:
  `datom_sync_manifest(conn, path = NULL, pattern = "*", sources = NULL)` and
  `datom_sync(conn, manifest, continue_on_error = TRUE, sources = NULL, tags = list(type = "input"), x = NULL)`.
  Section 4's original signature put `sources` third, which would have broken
  `datom_sync(conn, m, FALSE)`.
- **Where the branch sits.** After the existing conn / role / path checks (they are the same on both
  paths), before everything else. In `datom_sync()` that is **above the manifest column check**:
  today the column check runs first, so a product repo handed a set-shaped frame with no `sources`
  would get "missing columns file, format..." instead of the refusal that names `sources =`.
- **One gated parse per call.** The helper (`.datom_sync_context(conn)`, as built in task 5) returns
  `product` (whether the repo declares `mode: product`) and the declared `set` from
  `.datom/project.yaml`, with `.datom_check_project_schema(cfg, source,
  operation = "write")` exactly as `.datom_refuse_import_on_product()` does now (it reads the file with
  `yaml::read_yaml()` and returns early when the file is absent). The set path takes the set's name
  from it; nothing re-reads the file.
- **Arguments from the other context stop too**, extending R1.2 from `sources` to every argument that
  belongs to one path. Ordinary repo with `tags` or `x` supplied: `datom_sync_sources_on_ordinary`
  (detect with `missing()`, since `tags` has a default). Product repo with `path` (preview) or
  `continue_on_error` (apply, via `missing()`) supplied: `datom_sync_file_arg_on_product`. Silently
  ignoring either would let a caller believe an argument did something.
- **`.datom_check_rio()` and `.datom_check_git_current()` stay on the file path.** The set path writes
  nothing (I2), and rio is an optional dependency the set path does not use.

## 3. The preview (R2)

Built from three reads: the set (stored, via `datom_get_set()` on the developer conn; absent means
first version), one manifest per source (`.datom_current_artifact_versions()`), nothing per table.

Rows, in order:

**Sets are included** (owner, 2026-09-28, reversing the out-of-scope line of 2026-09-27, which
recorded no reason). A set in a source is a row exactly as a table is, and a set member of a source
project is compared exactly as a table member is. Without this, sync would be the one edit verb
that cannot move a set input, while `datom_member()`, `datom_add_member()` and
`datom_update_members()` all handle one. Landed as a fix to task 5 (task 5b), before task 6.
Wherever this section says "table" for a source row or a compared member, read "artifact, table or
set". Lineage is unaffected: a parent is always a table version, so `datom_parent(x = )` still
refuses a set member.

1. **Source artifacts** (tables and sets, name matching `pattern`). Keyed to set members by
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

Messages: one summary line (`Mapped N artifacts from K sources: a new, b changed, c unchanged.`;
"tables" until task 5b), then
one warning per `ambiguous` / `not_checked` group with its remedy.

**Spot-check additions (2026-09-28, checked against `R/set.R`, `R/set-edit.R`, `R/read_write.R`):**

- **"No set yet" needs a presence probe, not a failed read.** `datom_get_set()` reads through
  `.datom_read_metadata()`, which calls `.datom_storage_read_json()` and aborts the same way for a
  missing file and for storage that cannot be reached. Wrapping it in `tryCatch(..., error = NULL)`
  would report "first version" when storage is down -- the defect in engineering-notes "'Not there'
  and 'could not look' are different answers". So: `.datom_storage_exists(conn,
  .datom_artifact_meta_key(set_name, "metadata"))` first. `FALSE` -> first version (empty member
  list). `TRUE` -> `datom_get_set(conn, set_name)`, errors propagate. An error from the probe itself
  propagates (could-not-look, never absence). One helper, used by the preview and by apply when `x`
  is omitted.
- **Source versions need `kind`.** `.datom_current_artifact_versions()` returns name -> current
  version and drops `kind`, and a source may hold a set (a product repo used as a source). Add a
  sibling that returns `name, kind, current_version` from the **same single** gated manifest read
  (`.datom_read_manifest(conn, scope = "storage", operation = "read")`), keeping the existing
  unreadable-manifest refusal and its class `datom_edit_manifest_unreadable`. Rows are tables and
  sets (task 5 shipped tables only; task 5b widens it). An entry with no usable `current_version`,
  or no usable `kind`, gets no row and is named in the message.
- **Sources go through `.datom_edit_conns(sources, arg = "sources")`**, so a non-connection, a
  missing label and two connections for one project refuse exactly as `datom_update_members()` does.
- **Row values:**

  | status | `version_from` | `version_to` |
  |---|---|---|
  | `new` | `NA` | source's current |
  | `changed` | member's version | source's current |
  | `unchanged` | member's version | same |
  | `ambiguous` | `NA` (the message lists every pinned version) | source's current |
  | `not_checked` | member's version | `NA` |
  | `excluded` | member's version | `NA` |

  Columns in that order: `project, name, kind, version_from, version_to, status`; a plain
  `data.frame`, `stringsAsFactors = FALSE`, full 64-character versions (the console message
  abbreviates, the frame never does). No matches -> a zero-row frame with the same columns.
- **Every set member lands in exactly one place:**

  | Member | Goes to |
  |---|---|
  | set's own project (an output) | no row, no message; outputs move with `datom_update_members()` |
  | project that is not a source | `not_checked` row (R2.7), whatever its kind |
  | source project, absent from the source's manifest | named in the message as left its source, no row (R2.3) |
  | source project, present, matches `pattern` | the `new` / `changed` / `unchanged` / `ambiguous` row |
  | source project, present, does **not** match `pattern` | `excluded` row (point A below) |

  "Member" and "present" cover tables and sets alike (task 5b). Task 5 shipped a fourth row, "source
  project, kind `set` -> `not_checked`", which task 5b removed (2026-09-29).

- **The set's own project** for R2.5 is the developer conn's `project_name`, which on a clone comes
  from `.datom/project.yaml`. Compared against each source's label before any read.

### Open points from the spot-check (decide before coding task 5/6)

Each has a default the agent takes if the owner says nothing. Record the answer here.

- **A. A member whose table exists in its source but is filtered out by `pattern`.** **Answered
  2026-09-28 (owner): it gets a row**, so the preview confirms the filter left it alone and the frame
  always accounts for every member of every source. **Status `excluded`** (agreed 2026-09-28; the
  owner rejected `filtered` as ambiguous between filtered in and filtered out; `skipped` was avoided
  because the ordinary `datom_sync()` already uses it in its `result` column): member's version in
  `version_from`, `version_to = NA`, no warning, counted in the summary line as
  `N excluded by pattern`, and a no-op at apply. Not `not_checked`, whose warning ("build again with
  every source") would be wrong advice here. R2.2 amended to six values.
- **B. (task 6) A `new` row whose table the set already holds by the time it is applied** (someone
  added it after the preview). **Answered 2026-09-28 (owner): stop**, class
  `datom_sync_manifest_stale`, same as a moved `changed` row -- adding it would silently create a
  second member for one table, and treating it as `changed` would move a member the preview never
  showed. The owner's framing: a push refused because the remote moved. So the message's remedy is
  the pull-and-retry equivalent: build the preview again from the current set. R3.6 extended to
  cover it.
- **C. A source connection whose label disagrees with the project its manifest declares.**
  **Answered 2026-09-28 (owner): stop at the preview**, class `datom_sync_source_mislabelled`, naming
  the connection's label and the manifest's `project_name`. Uses the manifest read the preview makes
  anyway, so no extra IO. When the manifest records no `project_name` (older repos), carry on. Without
  it, a mislabelled source shows every table `new` and every member `not_checked`, and fails only
  later at apply. Apply keeps its own declared-project check for hand-built frames. New R2.10.
  **Probe note:** the test must use a store whose manifest really names another project; a fixture
  where label and manifest agree cannot redden when the check is removed.

## 4. Applying (R3)

`datom_sync(conn, manifest, continue_on_error = TRUE, sources = NULL, tags = list(type = "input"),
x = NULL)` -- new arguments last, see section 2.

**Spot-check additions (2026-09-28):**

- **Reuse task 3's add path rather than writing a second one.** `datom_add_member()` on a
  `datom_set` (`R/set-draft.R`, the block after `if (!is_set)`) already does the three things a `new`
  row needs: link through `.datom_member_as_link(record)`, `.datom_forget_set_identity(x)`, and an
  `add` row via `.datom_append_edits()` with columns `action, project, name, kind, from, to`. Factor
  that block into a helper both call, so the edit log cannot drift between the two verbs. Repoints
  reuse `.datom_repoint_member()` and a `repoint` row, as `datom_update_members()` does.
- **One not-written line at the end**, not one per added member: the shared helper must not print it.
  Printed only when a row was applied; otherwise "Nothing to apply: no new or changed rows" (R3.4,
  amended 2026-09-28). **And `datom_add_member()` on a draft now prints it too**, since a draft
  always differs from what is stored -- done in task 6, which already reshapes that function's add
  block. For a draft the hint is `datom_write_set(x)`, since the draft carries its connection.
- **The set's own project in `sources` stops apply too** (owner, 2026-09-28), before any read, with
  the preview's `.datom_refuse_own_project_source()` and class `datom_sync_own_project_source`.
  Without it a hand-built frame plus `sources = list(conn_own)` could repoint an output that was
  never re-derived, or add a second copy of it labelled `type = "input"`.
- **A `new` or `changed` row whose `project` has no connection in `sources`** (a hand-built or
  subset frame) stops, class `datom_sync_source_missing`, before any read. **Only those two
  statuses** (owner, 2026-09-28): they are the only rows apply acts on, and a full preview's
  `not_checked` rows belong by definition to projects not in `sources`, so checking every row would
  make an unedited preview impossible to apply.
- **The empty first-version set** is `structure(list(name = , project = , version = NULL, data_sha =
  NULL, tags = NULL, members = list()), class = "datom_set")`, built with `list(version = NULL)` so
  the names survive (engineering-notes "A declared-but-unpopulated field has to be spelled
  `list(x = NULL)`"). `datom_write_set()` then reads `members$tags` as `NULL` and applies its usual
  default.
- **`version_to` validation** uses the same `^[0-9a-f]{64}$` test `datom_update_members()` applies to
  its `version_to`; `tags` goes through `.datom_validate_tag_map()`, with a remedy about labelling
  new members (the update verb's remedy is about selecting existing ones, so it does not fit).
- **Open point B (section 3) decides the `new`-row stale case.**

- Required columns: `project, name, kind, version_from, version_to, status`. Values: `status` in the
  six-value set (R2.2), `version_to` a full 64-hex string on `new` / `changed` rows.
- **Frame checks, all before any read, one class `datom_sync_manifest_invalid`** (owner,
  2026-09-28): a frame missing those columns -- including an ordinary repo's file-import frame
  (`file`, `format`, ...), whose message says so and points at `datom_sync_manifest(conn, sources =
  )`; on `new` / `changed` rows, `project` and `name` non-empty text, `kind` one of the artifact
  kinds, `version_to` full 64-hex, and `version_from` full 64-hex on `changed` rows. A short
  `version_from` would otherwise fail the exact comparison and stop as stale, naming the wrong
  problem.
- **Tidy-ups in the same task** (owner, 2026-09-28): once `datom_sync()` passes the `sources =` hint
  too, delete `.datom_refuse_import_on_product()`'s other message and its `sources_hint` switch --
  its only two callers are the two sync verbs. Write `datom_sync()`'s `@param` entries and a "On a
  product repo" section, as task 5 did for the preview; task 9 still adds the save-asymmetry note
  to both.
- `x` omitted: read the stored set, or start an empty `datom_set` (name from `project.yaml`, project
  from the conn, `version = NULL`) on first version.
- **`x` given** (owner, 2026-09-28): a `datom_set` or a `datom_set_draft`, through
  `.datom_edit_members()` as the other edit verbs take it -- `datom_write_set()` accepts both, so a
  narrower apply would leave a shape that writes but cannot be synced. When `x` carries a name it must
  equal the declared set, else `datom_set_name_mismatch` (the write gates' class). Needed because
  `datom_write_set()` takes the name from `project.yaml` and ignores `x$name`, so another repo's set,
  synced here and written, would be re-homed without a word. A draft with no name passes.
- **Two `new` / `changed` rows for one (`project`, `name`)** stop up front, before any read, naming
  the table (owner, 2026-09-28; class `datom_sync_manifest_duplicate_row`). A preview never produces
  them; without this the second row would stop as stale, which names the wrong problem. Duplicates
  among the other statuses are harmless, since those rows do nothing.
- Per `changed` row: find the member by (`project`, `name`); its version must equal `version_from`,
  else abort `datom_sync_manifest_stale`. **Zero or two-plus members matching also stops as stale**
  (owner, 2026-09-28): the set was edited after the preview, and skipping would leave a removed
  member removed, or a table unmoved, without the caller noticing. Repoint through `.datom_repoint_member()` (labels verbatim,
  project change refused).
- Per `new` row: `datom_member(sources[[project]], name, version_to, tags = tags)`. That read is what
  validates the version exists and records the **declared** project. A declared project that differs
  from the row's aborts, as a repoint does, **with the repoint's class
  `datom_update_project_mismatch`** (owner, 2026-09-28) and wording that says "adding": one class
  for one failure, whichever row hits it.
- **A row's `kind` must agree with the artifact** (owner, 2026-09-28): a `new` row whose snapshot
  (read by `datom_member()`) declares another kind, or a `changed` row whose member has another kind,
  stops with class `datom_sync_kind_mismatch`, naming the row, its `kind` and what was found. Same
  reasoning as the project check: the row names what was reviewed, the read confirms it.
- **Why `sources` is passed again**: building a member without reading its snapshot would trust a
  hand-edited row's version and project, and a set pointing at a version that does not exist is found
  only when someone fetches it. Re-reading is one snapshot per applied row.
- Edits: `repoint` rows as today, new `add` rows (`from = NA`, `to = version`). `.datom_forget_set_identity()`
  when anything changed. Report, then the not-written line.

## 5. `datom_add_member()` (R4)

- Class check widens to `datom_set`. A name resolves through `conn`, or the draft's own connection
  when omitted; a `datom_set` never borrows a `conn` field (as built in task 3, branched on class
  rather than `conn %||% x$conn`). A `datom_set` with a name and no `conn` aborts
  `datom_member_conn_required`.
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
