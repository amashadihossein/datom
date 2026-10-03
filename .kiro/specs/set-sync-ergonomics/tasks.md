# Tasks -- set sync ergonomics

**Issue**: [#121](https://github.com/amashadihossein/datom/issues/121).
**Branch**: `spec/set-sync-ergonomics`, from `dev` at `7d55a8b`. PRs into `dev`.
**Test baseline**: 4282.
**Order**: 1 -> 2 -> 3 -> 4 -> 5 -> 5b -> 5c -> 6 -> 7 -> 8 -> 9. One commit per task, full suite before each,
count in the message. Chunk checkpoint after every task.

**Model escalation flags (set at planning):**
- **Design spot-check before task 5** -- the sync branch is the cross-cutting change.
- **Test coverage review before task 9** -- confirm every guard was watched going red (AC15).

## Where things stand

Spec approved 2026-09-27 and committed. Tasks 1-5 done 2026-09-28, tasks 5b, 5c, 6, 7, 8 and 9 on
2026-09-29. **Every task is done**; what remains is the PR into `dev`. Task 5c came out of the
task 6 cold-start review on 2026-09-29 -- see design section 12 for why.

**A cold-start review on 2026-09-28, after task 5, settled everything task 6 needed.** A fresh
session followed these documents and found no broken references, but found about eight apply
behaviours nothing decided. The owner answered each, one at a time, and every answer is recorded
where it applies, marked "(owner, 2026-09-28)": design section 4 (which rows need a connection,
stale cases, duplicate rows, kind and project mismatches, what `x =` accepts, the own-project
refusal, frame checks, tidy-ups) and R3.4 (the not-written line). **The largest change: sets are
now in scope for sync** (R2.1a, AC17, design 3's "Sets are included" block), which is why task 5b
exists. Nothing is left to ask before coding 5c or 6.
**Current test count: 4705** (after the coverage review's three tests) -- what later counts must not
drop below.

Starting cold (task 9): `git checkout spec/set-sync-ergonomics && git pull`. **The escalation flag
comes first**: a test coverage review, on a more capable model, confirming every guard in this spec
has a test watched going red with that guard alone removed (AC15; the probe records are in each
task's entry below). Then task 9's list. `NEWS.md` cites only `?verb` and `vignette(...)`, never
`dev/` or `.kiro/` (conventions rule 7a). The vignette's output blocks are final: any later change
to its code needs another credentialed run of `dev/e2e-vignettes-s3.R`.
---

- [x] **1. Example data: add `vs`** (R7, AC13)
  - **Done 2026-09-28, 4295 tests (+13).** Before editing, the unmodified simulator was re-run and
    reproduced all four CSVs and `R/sysdata.rda` byte-for-byte (R 4.5.2), so the post-edit diff is
    attributable to the edit alone. After the edit: same result, `sysdata.rda` included, so nothing
    needed restoring. `vs` is 432 rows (`SYSBP`, `DIABP`, `PULSE`, integer `VSORRES`), on exactly the
    `lb` subject/visit/date triples.
  - Added beyond the plan: a test pinning a **value fingerprint** of each original table (sha256 over
    the parsed columns, not the file bytes, so line endings and checkout settings cannot move it), plus
    `ae` locked at 84 rows. Probe: moving the `vs` block ahead of `ae` in the simulator reddened the
    `ae` fingerprint; restored and regenerated afterwards. The simulator header now says new domains
    go last in the random stream, and why.
  - Append `vs` generation after `ae` in `data-raw/simulate_study_data.R`; write `vs.csv`.
  - The script writes with relative paths, so run it from the repo root:
    `Rscript data-raw/simulate_study_data.R`.
  - Verify the four existing CSVs byte-identical and `sysdata.rda` values identical (design 8)
    **before** keeping anything. If any existing CSV changed, stop and report; do not commit.
  - `datom_example_data("vs")`, roxygen (`@param domain`, the "four domains" sentence), then
    `devtools::document()`; tests in `tests/testthat/test-example-data.R` (row count, columns,
    cutoff, and that the existing domains' row counts are unchanged).
  - Owner cares most about: **the values of the other example tables must not change.**

- [x] **2. `datom_parent(x = )`** (R5, AC11)
  - **Done 2026-09-28, 4330 tests (+35).** `datom_parent(conn, table, version = NULL, x = NULL,
    tags = NULL)`. The old body moved unchanged into `.datom_parent_record()`, which both routes call;
    the set route (`.datom_parents_from_set()`) resolves each name with `.datom_find_member()` and
    validates `tags` with the same call and remedy as `datom_fetch_member()`. Loop is `lapply()`, not
    `purrr::map()`, so the resolver's condition classes reach the caller.
  - Refusal classes: `datom_parent_version_or_set` (both or neither), `datom_parent_tags_without_set`
    (name chosen here, owner agreed), `datom_parent_not_a_table`; ambiguous / not found keep the
    resolver's `datom_member_ambiguous` / `datom_member_not_found`.
  - Probes (restored from a copy, control reddened nothing): removing each of the three refusals, the
    `table` shape check, and label narrowing each reddened its own test; swapping `lapply()` for
    `purrr::map()` reddened nothing until the class test used `expect_error(inherit = FALSE)`, since
    testthat otherwise matches a wrapped error's parent. Learning added to `dev/engineering-notes.md`.
  - Parity fixture lists the baseline `lb` first, so a resolver ignoring labels picks the wrong member
    for the live case.

- [x] **3. `datom_add_member()` on a `datom_set`, with `conn =`** (R4, AC10)
  - **Done 2026-09-28, 4380 tests (+50).** `datom_add_member(x, member, version = NULL, tags = NULL,
    conn = NULL)`. A name resolves through `conn`, or the draft's own connection when omitted; a
    `datom_set` never borrows a `conn` field (branched on class, not `conn %||% x$conn`), so a name
    there needs `conn` (`datom_member_conn_required`). `conn` that is not a connection:
    `datom_not_a_conn`. On a `datom_set`: link added through the shared factory, identity emptied,
    `add` row logged, not-written line printed. Drafts unchanged apart from `conn =`.
  - Found while writing it: the clash check digests members, and the digest refuses any field but
    `id` / `tags`, so a set read back (every member has `$fetch`) would have errored on every add.
    Existing members are stripped of links before the check.
  - Added beyond the plan: the new member gets a `$fetch` link, so every member of a read set still
    has one. Commit subject lists `add` first, then `repoint`, then `drop`.
  - Docs whose claims this made false were rewritten: the `R/set-draft.R` header (points 1-2 said
    the verb never takes `conn` and that a record is the only cross-project route; point 7 added),
    the `datom_assemble_set()` "one draft" bullet, the cross-project test's title, and the
    `dev/datom_specification.md` signature.
  - Probes (fixed copy, `cmp` after each; control reddened nothing): the conn-required refusal, the
    class branch, the conn type check, link stripping in the clash check, the link, identity
    emptying, the log append, the not-written line, the set/draft wording, the draft early return,
    the `add` commit verb, its display line and its order -- each reddened its own test. The first
    harness run restored nothing (`on.exit()` at `Rscript` top level); recorded in
    `dev/engineering-notes.md`.
  - Design 5, including the `add` action in the edit log and commit message.
  - Tests: by record, by name with `conn`, name without `conn` refused, draft unchanged (commit
    message too), clash rules on a `datom_set`.
  - **Decided 2026-09-28 (owner):** adding to a `datom_set` prints one line, `Nothing has been
    written. Write the set with datom_write_set(conn, x).`, matching `datom_update_members()`. Adding
    to a draft stays silent, as today. A skipped duplicate prints only its existing note.
    **Superseded later the same day** for drafts: an add to a draft prints the line too (R3.4's
    one rule for every verb). Lands in task 6.
  - Facts for this task re-checked 2026-09-28 and still hold (design 1): the draft-only class check
    and `datom_not_a_draft` in `R/set-draft.R`; `.datom_set_commit_messages()` and
    `.datom_edit_lines()` in `R/set-edit.R` know `repoint` / `remove` only; the clash helper
    `.datom_draft_member_clash()` takes a plain member list. `datom_member_conn_required` is new. The
    one existing refusal test (`test-set-draft.R`, "the add verb needs a draft") passes a connection,
    not a set, so it stays; keep `datom_assemble_set` in the widened message, which it matches.

- [x] **4. Provenance check in `datom_write_set()`** (R6, AC12)
  - **Done 2026-09-28, 4406 tests (+26).** `.datom_check_set_parents()` in `R/set.R`, called right
    after `.datom_check_set_payload()`; the snapshot read is `.datom_member_parents()`, with the
    format check outside its handler. Refusal classes `datom_set_parent_mismatch` (all mismatches
    in one message, one line each, short hashes) and `datom_set_member_unreadable`; a too-new
    snapshot keeps `datom_schema_unsupported`. New roxygen section in `datom_write_set()`.
  - **No kind filter**, unlike design 7's wording: every own-project member is a table, because a
    product repo holds one set and a set listing itself is refused just before. A filter there
    could never be probed. A parent entry not shaped as three strings is skipped (datom always
    writes three).
  - **One earlier test changed** (`test-set-edit.R`, "a member whose artifact is gone is reported
    and left, and still writes"): its "gone" member pinned a version that never existed, which the
    new unreadable refusal stops at write. It now writes a real `ghost` table and drops it from both
    manifest copies, which is what "gone" is in practice and what the test's own comment ("the pin
    still reads") assumed.
  - Probes (fixed copy, `cmp` after each; control reddened nothing): no abort; call removed; call
    moved before tidy/validation; call moved after the payload file write; baseline rule; project
    match; own-project filter; first-mismatch-only; unreadable skipped; format check inside the
    handler; format check removed; `purrr::map()` for `lapply()` -- each reddened its own test
    (the class tests use `inherit = FALSE`).
  - Design 7. Tests: mismatch stops before any local write; matching parents pass; parent not in the
    set passes; baseline pair (one member at the parent's version) passes.
  - **Design 7 corrected 2026-09-28 (owner), read it rather than this summary:** the check sits
    right after `.datom_check_set_payload()`, not before tidying; it checks each snapshot's format
    number; an unreadable snapshot stops the write (`datom_set_member_unreadable`). Extra tests for
    those: a malformed member still gets the validator's message; a too-new snapshot stops the
    write; a member whose snapshot is missing stops it, with nothing written in each case.

- [x] **5. Preview: `datom_sync_manifest(sources = )`** (R1, R2; AC1-AC3, AC5-AC7)
  - **Done 2026-09-28, 4504 tests (+98).** `datom_sync_manifest(conn, path = NULL, pattern = "*",
    sources = NULL)`. `.datom_sync_context()` in `R/sync.R` makes the one gated parse of
    `.datom/project.yaml`; the verb branches on it right after the conn checks. The product-repo
    route is `.datom_sync_set_preview()` in the new `R/sync-set.R`. Existing `test-sync.R` tests pass
    untouched.
  - Refusal classes, new: `datom_sync_sources_on_ordinary`, `datom_sync_file_arg_on_product`,
    `datom_sync_own_project_source`, `datom_sync_source_mislabelled`. Reused: `datom_import_on_product`
    (product repo, no `sources`), `datom_set_undeclared` (product repo naming no set, same class the
    set write uses), and through `.datom_edit_conns()` / the manifest read, `datom_not_a_conn`,
    `datom_edit_conn_duplicate`, `datom_edit_manifest_unreadable`.
  - **The refusal message names `sources =` only for the preview.** `.datom_refuse_import_on_product()`
    gained `context` and `sources_hint`; `datom_sync()` still calls it without the hint, so it does
    not advertise an argument it does not take yet. A test pins that ("apply still refuses a product
    repo until it learns sources"): **task 6 flips it**, and can then drop the `sources_hint` flag.
  - Choices made here, not in the design: rows come per source in the order passed, table names
    sorted in C-locale order, then `excluded`, then `not_checked`. A source table whose manifest
    entry records no current version gets no row and is named in a warning (so is a member pinned to
    one, through its table's name). Manifest entries with an unusable `kind` get no row.
  - Built for task 6 and used here: `.datom_current_artifacts()` (name, kind, current version and
    the manifest's project name from one read; `.datom_current_artifact_versions()` is now built on
    it), `.datom_empty_set()`, and `.datom_sync_read_set()` (presence probe, then read).
  - Probes (fixed copy in `/tmp`, `cmp` after the run; control reddened nothing): 29, each reddened
    its own test -- both context refusals, the hint, the config format check, the undeclared set,
    the own-project refusal removed and moved after the set read, the mislabel check removed and
    applied to a manifest with no name, `purrr::map()` for `lapply()`, the presence probe replaced by
    a caught read, every member placement (set, output, unpassed, gone, excluded, ambiguous), the
    kind filter in both files, sorting, the pattern, `version_from` on changed rows, each warning
    block, the excluded count, and bypassing the connection checks.
  - **Escalation flag: design spot-check first.** Done 2026-09-28; see design 2-3 "Spot-check
    additions" and the answered points A and C (R2.2 `excluded`, R2.10).
  - Design 2 and 3. New `R/sync-set.R`; branch in `R/sync.R`. Existing sync tests unchanged.
  - The context helper and the branch land in `datom_sync_manifest()` only. `datom_sync()` gets its
    branch in task 6, so no commit ships an apply verb that accepts `sources =` and does nothing with
    it; until then it refuses a product repo exactly as today. Ordinary-path tests in `test-sync.R`
    must pass untouched.
  - Tests to write, beyond AC2/3/5/6/7: presence probe (storage unreachable is an error, not "first
    version"); a source holding a set gives it no row; each member-placement row in design 3's table;
    arguments from the other context stop; zero-row frame keeps its columns.
  - Before editing `R/`, read the engineering-notes entries on `tryCatch` erasing "not there" vs
    "could not look", on condition classes lost through `purrr::map()` (use `lapply()` where a
    refusal class must reach the caller), and "Probing a guard".

- [x] **5b. Sets in the preview, and a real set-of-sets test** (R2.1a; AC17, preview half)
  - **Done 2026-09-29, 4536 tests (+32).** Source rows now keep every kind in
    `.datom_artifact_kinds` (a kind this build does not know still gets no row); members of a
    passed source are compared whatever their kind, keyed on (`project`, `name`) only, since one
    project is one namespace. A row's `kind` is the source manifest entry's; apply checks it against
    the member (design 4). The "members that are sets" warning block and its `sets` argument are
    gone.
  - Wording: "artifact" replaces "table" in the summary (`Mapped N artifacts from K sources`), the
    ambiguous, left-pinned and no-current-version warnings, and the `datom_sync_manifest()` roxygen
    for the product-repo route (`pattern`, the row list, `excluded`, `not_checked`).
  - Tests reworked into their opposites: a set member in a source project is `changed` /
    `unchanged` like a table; a set held by a source gets a row with `kind = "set"`. New: a set
    member whose set left its source is named as left pinned; a source entry of an unknown kind gets
    no row (pins the kind filter, which no test covered once it stopped being `"table"` only).
  - Set-of-sets test, three real projects, no mocks: `imported` table -> `inner-proj` set ->
    `outer-proj` set pinning the inner set. Reads back, `datom_fetch_member()` returns the inner
    `datom_set`, `datom_validate()` is valid on both product repos, and after the inner set moves
    the outer preview shows one `changed` row of kind `set`.
  - Probes (copy in `/tmp`, workspace untouched; control reddened nothing): source rows tables-only
    again (3 red), kind filter removed (1), set members dropped from comparison (3), row kind
    hard-coded to table (3), summary back to "tables" (2) -- each reddened its own tests.
  - **Added 2026-09-28 (owner).** Task 5 shipped a tables-only preview because an out-of-scope line
    said so, with no reason recorded. The owner brought sets in: a set built from sets is the case
    sets exist for. See design 3's "Sets are included" block.
  - Drop the `kind == "table"` filter on source rows; compare a set member of a source project as a
    table member is compared (it no longer goes to `not_checked`). Rows' `kind` is the manifest
    entry's. Rework the tests that pinned the old behaviour ("a member that is a set, in a source
    project, is not_checked"; "a set held by a source gets no row") into their opposites, and probe.
  - New test on local stores, no mocks: write an inner set in one product repo, point at it with
    `datom_member()` from another, write the outer set, read it back, `datom_validate()` it. Then a
    new version of the inner set shows as `changed` in the outer repo's preview.
  - Summary wording: "Mapped N artifacts", not "tables".

- [x] **5c. One in-memory set: remove the draft class** (R9; AC18)
  - **Done 2026-09-29, 4568 tests (+32).** `datom_assemble_set()` returns `.datom_empty_set(name,
    conn$project_name)` with `tags` (helper moved from `R/sync-set.R` to `R/set-draft.R`); no
    `datom_set_draft`, no `print.datom_set_draft`, no `datom_draft_members_conflict` in `R/`,
    `NAMESPACE`, `man/` or `_pkgdown.yml`. `datom_add_member()` needs `conn` for every name, and
    every add links, empties identity, logs `add` and prints the not-written line. `datom_write_set()`
    takes a connection in `conn` only; its guard message shows `datom_write_set(conn, x)` and the pipe.
  - R9.5: `.datom_reconcile_set_name()` (a `name =` disagreeing with the set's own name,
    `datom_set_name_mismatch`, message "the set you passed") runs before the gates; the set's name
    then reaches the name gate through `name`; `.datom_check_set_project()` (new class
    `datom_set_project_mismatch`) runs right after the gates, before the door and any hash. The
    message's remedy, `datom_write_set(conn, x$members)`, is tested to work.
  - Choices made here, not in the design: the add verb's "not a set" class is now `datom_not_a_set`
    (was `datom_not_a_draft`), the class the edit and list verbs already use.
    `print.datom_set` says "the set this repo declares" for a set with no name, instead of a blank.
    The list/structure/fetch refusal message now names `datom_assemble_set()` too. The internal
    clash helper keeps its name `.datom_draft_member_clash()`.
  - Tests: `test-set-draft.R` rewritten (43 tests); `test-set-edit.R`'s two draft round trips became
    "an assembled set repoints / loses a member like a read one". New: no connection in the
    serialized bytes of an assembled set; every add prints and logs, the first one included; first
    write commits `Update {name}: add N members`; list/structure/fetch on an assembled set; the
    documented pipe end to end with a cross-project name add; the three R9.5 refusals with nothing
    written (commit, clone files including dot-directories, store objects), the project one on two
    repos both declaring `adam`.
  - Probes (fixed copy in `/tmp`, restored and compared after the run; control reddened nothing):
    the set's name not fed to the gate (2 red), the name-argument check removed (1), the project
    check removed, made to compare nothing, or moved after the payload file write (1 each), the add
    borrowing a `conn` from the set (1), the conn requirement removed (3), the add log removed (8),
    the not-written line removed (2), the link removed (4), a connection kept on the assembled set
    (2), the empty `tags` field dropped (1), the unnamed print header removed (1) -- each reddened
    its own test.
  - `dev/e2e-sets.R` updated and run offline: all claims held. `dev/e2e-sets-s3.R` updated and
    parse-checked only (needs credentials; task 8's run covers it). `dev/datom_specification.md`
    rewritten for one kind of set. `NEWS.md` waits for task 9.
  - **Added 2026-09-29 (owner).** The edit verbs' hint `datom_write_set(conn, x)` fails for a draft,
    because the write took a draft in its first slot and a read set in its second. The fix is one
    kind of set with no connection in it, and the connection always on the call. Design section 12
    has the file-by-file change, the pipe before and after, and the tests to write, delete and flip.
  - Includes the new write refusal (R9.5): a set whose name or project is another repo's stops
    before anything is written. The project test needs two product repos declaring the same set
    name, or it cannot go red.
  - Absorbs what task 6 had for drafts: every add prints the not-written line, and the task 3 test
    pinning a silent draft add (`test-set-draft.R`, `expect_silent` around the first add) flips.
  - **Decided 2026-09-29 (owner):** the first write of an assembled set gets the edit-log commit
    message (`Update {name}: add N members`, one line per member). A test that pins
    `Update {name}` for a draft write flips.

- [x] **6. Apply: `datom_sync(sources = , tags = , x = )`** (R3; AC4, AC8, AC9)
  - **Done 2026-09-29, 4687 tests (+119).** `datom_sync(conn, manifest, continue_on_error = TRUE,
    sources = NULL, tags = list(type = "input"), x = NULL)`. The context branch sits above the file
    column check. The product route is `.datom_sync_set_apply()` in `R/sync-set.R`. Order of work:
    set name, frame checks, connections, own project, tags, duplicate rows, missing sources (all
    before any read); then the set read (or `x`); then the stale and changed-row kind checks (still
    no snapshot read); then one `datom_member()` read per applied row. `new` rows go through
    `.datom_set_add_record()` (the add steps factored out of `datom_add_member()`, no print);
    `changed` rows through `.datom_repoint_member()` and a `repoint` log row. One summary line, one
    line per edit, one not-written line; "Nothing to apply: no new or changed rows." otherwise.
  - Refusal classes, new: `datom_sync_manifest_invalid`, `datom_sync_manifest_duplicate_row`,
    `datom_sync_source_missing`, `datom_sync_manifest_stale`, `datom_sync_kind_mismatch`. Reused:
    `datom_import_on_product`, `datom_sync_file_arg_on_product` (`continue_on_error` typed on a
    product repo), `datom_sync_sources_on_ordinary` (`sources`, `tags` or `x` on an ordinary repo),
    `datom_sync_own_project_source`, `datom_update_project_mismatch` (wording says "Adding"),
    `datom_not_a_set`, `datom_not_a_conn`, `datom_edit_conn_duplicate`.
  - Tidy-ups done: `.datom_refuse_import_on_product(verb, context)` has one message, always naming
    `sources =`; for `datom_sync` the hint is `datom_sync(conn, manifest, sources = list(...))`. The
    own-project message says "so sync does not map or move them". The task 5 test "apply still
    refuses a product repo until it learns sources" flipped to "names the argument".
  - Choices made here, not in the design: a `changed` row with `version_to == version_from` is
    refused as invalid (a preview never makes one, and applying it would log a repoint that moves
    nothing). Edits are logged in frame row order. When `x` was passed, the stale message's remedy
    says the preview compares against the stored set, so rebuilding it alone would not help.
    Factor/`NA`-logical columns are coerced to text before checking.
  - Probes (fixed copy in `/tmp`, `cmp` after each; control reddened nothing): 45, each reddened its
    own test. They covered every refusal removed, the column check moved above the branch, the
    own-project and stale checks moved after a read, the missing-source check widened to every
    row, the frame values checked on every row, tags dropped, labels rebuilt instead of carried,
    identity kept, each log row dropped, both report lines, and the three add-helper steps. The one
    probe that reddened nothing was base `Reduce()` swapped for `purrr::reduce()`. purrr's reduce does not wrap
    errors (checked, purrr 1.2.1), so the loop now uses it. Learning in `dev/engineering-notes.md`,
    plus one about an interrupted wait leaving the probe driver running.
  - Design 4, including its "Spot-check additions" and open point B (design 3). Properties P1-P3, P5.
  - Adds the context branch to `datom_sync()` (above its manifest column check, design 2).
  - `x` is a `datom_set` only (task 5c), and the set-name check is the write's (R9.5), not apply's.
  - **Decided 2026-09-29 (owner):** `.datom_refuse_own_project_source()` is shared by the preview and
    apply, so its message stops saying "the preview": "... so sync does not map or move them". One
    wording, no caller argument.

- [x] **7. Vignette code and offline dry run** (R8.1-R8.3)
  - **Done 2026-09-29, 4691 tests.** `citable-sets.Rmd` follows design 9: v1 is a preview
    (`v1-preview`, shown as `m[, c("project", "name", "kind", "status")]`) then apply and one write
    (`v1`); `derive_liver_flags(x, conn_input)` returns a data frame, and `v2` writes it with
    `parents = datom_parent(..., x = x)`, adds it with `datom_add_member(conn = )` and writes the
    set; the refresh is `refresh-sync` (five domains, `vs` new), `refresh-inputs` (preview and
    apply: four `changed`, `vs` `new`) and `refresh-output` (derive, write, `datom_update_members()`
    for the output, one write). Every `#>` block is `[pending run]`. The `for` loop writing the
    month-4 CSVs stays: it mirrors start-on-s3 step 4 and builds no member list.
  - Prose changed where the old text became false: a product repo no longer "refuses
    `datom_sync()`"; the refresh no longer says "datom does not check the order for you" -- the
    set write now refuses an output whose parents disagree with the pins (task 4), and the text
    says what that catches. New paragraph on the save asymmetry (tables save on sync, a set on
    `datom_write_set()`).
  - **Found by the dry run, fixed first as its own commit (owner, "fix now"):** every clean preview
    warned that one blank artifact ("` in `") had no current version -- `paste0()` over empty
    vectors returns one string. Now `sprintf()`; new test that a clean preview prints only its
    summary line; restoring `paste0()` reddened it and nothing else. 4687 -> 4691.
  - Dry run (`DATOM_E2E_BACKEND=local`): SUCCESS, all chunks, teardown left nothing. start-on-s3's
    recorded blocks compared chunk by chunk with the transcript: every version identical; the only
    differences are timestamps, local paths and the local backend (no GitHub repo line, `local`
    connection print). Set v1 and v2 come out at the currently recorded `d2d0456b` / `66d721f3`
    (same content); v3 is now 6 members.
  - `dev/e2e-sets.R` section 8, 31 claims, offline, all held: a second (ordinary) project as the
    source; preview rows, no row for the set's own member, one message line on a clean preview;
    apply writes nothing and labels new members `input`; `datom_parent(x = )` at the pins;
    `datom_add_member(conn = )` by name; the first commit subject `add 3 members`; the source moves
    -> `changed` / `unchanged`, repoint keeps labels; a set write that skips re-deriving the output
    stops with `datom_set_parent_mismatch`, no commit, clean tree; re-derive, update, write;
    preview again finds nothing (P1); `datom_validate()` valid.
  - Rewrite `citable-sets.Rmd` per design 9; `#>` blocks become `[pending run]`.
  - Month-4 extract includes `vs`.
  - `dev/e2e-vignettes-s3.R` local backend: whole walk green; `start-on-s3` outputs unchanged.
  - Add the new verbs to `dev/e2e-sets.R` claims.

- [x] **8. Credentialed run (owner) and transcripts in** (R8.4, AC14)
  - **Done 2026-09-29, 4691 tests.** Owner ran `dev/e2e-vignettes-s3.R` (S3 + GitHub) at `cbf6074`
    on 2026-09-29 19:30 PDT: every chunk ran, teardown deleted both repos, both storage prefixes and
    both clones. All 11 `[pending run]` blocks in `citable-sets.Rmd` filled by a script that
    replaced each chunk body with the transcript's and refused any chunk whose code differed; none
    did. The diff touches `#>` lines only. Edits: the two clone paths and the GitHub account in
    `init-liver-safety` shown as `...`, nothing else (the bucket name never appears in citable-sets
    output).
  - Every version the real run printed equals the task 7 offline prediction (set `d2d0456b`,
    `66d721f3`, `35e39f62`; `liver_flags` `dafdb954`, `0f89dd1b`; `vs` `28c748b0`). start-on-s3
    was not edited (R8.3); in the real run its versions and data hashes all equal the recorded
    ones. The rest differs only where the allowed edits apply (bucket, paths, account) and in
    timestamps.
  - Prose checked against the output: every row `new` at v1; four `changed` and `vs` `new` at the
    refresh; no row for `liver_flags`; three set versions. Nothing contradicted.
  - Owner runs `dev/e2e-vignettes-s3.R` with credentials; agent fills blocks mechanically.

- [x] **9. Close out** (AC15, AC16)
  - **Done 2026-09-29, 4705 tests, `R CMD check --as-cran` 0E/0W/0N.** Two commits. First, both sync
    verbs' product-repo roxygen says tables save on sync and a set on `datom_write_set()`; the
    ordinary-repo notes on unsupported formats, which had been rendering inside the last `@param`
    entry, moved into the description. Second, the close-out:
  - `NEWS.md`: folded into the unreleased "New: citable sets" section rather than a section of its
    own, since sets have never shipped and a reader upgrading from 0.1.2 never saw drafts. New
    bullets for sync on a product repo, `datom_parent(x = )` and the two write refusals; the
    assemble/add bullet rewritten for one kind of set; `vs` under "Smaller changes". Cites only
    `?verb` and `vignette(...)`.
  - `dev/datom_pathways.md`: new card "Given a product repo and its source projects, map and apply
    set changes"; the set write card gained steps for unpacking a `datom_set` and the name, project
    and provenance checks.
  - `dev/datom_specification.md`: both sync signatures and a "Set sync on a product repo" section;
    `datom_parent(x = , tags = )` in the `parents` bullet; the provenance check under
    `datom_write_set()`; `vs` and the "new domains go last" rule under example data.
  - `dev/engineering-notes.md`: roxygen prose after the last `@param`; `paste0()` over empty vectors
    in package code (extends the harness note); unreachable guards, both decisions from this spec.
    The kept early return in `.datom_refuse_import_on_product()` now says at the site why it stays.
    (The first commit also dropped "FOUR THINGS" over a five-item list in the `R/sync-set.R` header.)
  - `dev/README.md`: completed row; Active Specs empty.
  - AC16's "no `dev/` or `.kiro/` cite": two older cites, from before this spec, fixed in their own
    commit (owner, "fix now"): `vignettes/design-version-shas.Rmd` now links the cv1 reference script
    on GitHub, and an internal helper's roxygen in `R/sync.R` drops its `dev/engineering-notes.md`
    pointer. None remain in NEWS, vignettes, `man/` or roxygen.
  - **Version bumped to 0.2.0** (owner, 2026-09-29): `DESCRIPTION`, and the NEWS heading
    `# datom 0.2.0`. A minor bump, because sets are a new artifact kind and the manifest rename
    breaks older readers. `cran-comments.md` still describes 0.1.2; it is rewritten at submission.
  - **Escalation flag: test coverage review first.** **Done 2026-09-29**, by Claude Code independently
    of these records: `handoff/ac15-coverage-review.md`. It removed 57 guards one at a time in a
    scratch copy; 54 turned a test red, and 3 had no test. All three gaps are now closed, 4705 tests (+14):
    `datom_parent(x = )` refuses malformed `tags` with the same first line as `datom_fetch_member()`,
    before any read; it refuses an invalid table name (second in the vector) as a name, not as
    `datom_member_not_found`; `datom_sync()` on a product repo naming no set stops with
    `datom_set_undeclared` before any read. Probes (scratch copy, control reddened nothing): each
    guard removed alone reddened exactly its new test.
  - **Kept on purpose (owner, 2026-09-29):** the first line of `.datom_refuse_import_on_product()`
    returns early on a repo that is not a product repo. Both callers only call it on product repos,
    so the line can never run and no test can cover it. Kept anyway: if a future caller skips the
    product check, the helper still does the right thing. A later review should not flag it again.
  - `NEWS.md` (sync on product repos, add to saved sets, parents from a set, the new write refusal,
    `vs`), roxygen for both sync verbs documenting the save asymmetry.
  - `dev/datom_pathways.md` route card; `dev/README.md` completed row; learnings to
    `dev/engineering-notes.md`.
  - `R CMD check --as-cran` 0E/0W; PR into `dev`.
