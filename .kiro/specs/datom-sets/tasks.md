# Tasks -- datom sets (second artifact kind)

**Source issue**: [#89](https://github.com/amashadihossein/datom/issues/89)
**Branch**: `spec/datom-sets` (cut from `dev`; PRs into `dev`)
**Test baseline at spec start**: 2460 passing, 0 failures

One task (or a small related group) = one chunk = one commit. Mark the checkbox in the **same
commit** as the code, and update the `dev/README.md` Active Specs status line. Per Operational
Discipline rule 5d, **STOP after each chunk** and wait for explicit go-ahead.

**Escalation flags** (design.md section 12) are marked inline. A flagged task **must** re-surface
its escalation recommendation in that chunk's checkpoint message, whether or not it still seems
necessary.

---

## Task 0 -- Spec creation

- [x] **0. Create the spec and register it**
  - `.kiro/specs/datom-sets/{requirements,design,tasks}.md` translated from #89 at full detail
  - Register in the `dev/README.md` Active Specs table
  - Prerequisite #95 (copilot-instructions compatibility posture) landed on `dev` separately via
    PR #96, deliberately outside this branch's history
  - _No code. Docs only._

---

## Phase A -- Contract-neutral groundwork

- [ ] **1. Housekeeping: stale docstrings + relative-key helpers**
  - Fix the stale "task 5.1" `parquet_sha` claims at `R/read_write.R:105-108`, `205-206`, `413`,
    and reword the already-correct-but-now-inconsistent comment at `393` (R13.3 has the site
    table). History **has** persisted `parquet_sha` since #72; only pre-#72 legacy entries lack
    it. Drop the internal task references entirely per the Don'ts. **Note #89's `95-97` citation
    is wrong** -- that is the function title; verified with `grep -n "task 5\.1"`.
  - Add `.datom_artifact_payload_key()` / `.datom_artifact_meta_key()` /
    `.datom_artifact_snapshot_key()` to `R/utils-path.R` -- **relative** keys, per design.md
    Deviation D1. `.datom_build_storage_key()` stays unchanged as the backend-internal full-key
    builder.
  - Fold `.datom_validate_sha()` / `.datom_validate_name()` guards into the helpers (I9).
  - Migrate existing `paste0` key call sites in `R/read_write.R`, `R/query.R`, `R/lineage.R`,
    `R/validate.R` to the helpers. Behavior-identical -- assert with the existing suite.
  - File the separate issue for the `metadata_sha` emitter-drift exposure (design.md section 16).
    Do **not** implement it here.
  - _Requirements: R5.2, R13.3. Invariants: I9. No pathway impact._

- [ ] **2. `datom-sv1` canonical set-content hash** &nbsp; **[ESCALATION E1 -- design review]**
  - **All five open questions are settled** (owner-decided 2026-08-15, design.md 7.5). The
    escalation is now a **design review of the walk specification**, not a debate: exact byte
    rules, whether the tag table leaves a collision surface, and whether the goldens cover the
    7.3 agreement cases. The goldens still freeze the encoding -- a later change needs a conscious
    `datom-sv2` bump.
  - **Q1 whole payload.** `data_sha` covers members **and** their tags (a description is a tag). A tag
    or description edit **mints a new version** -- intended, not a bug to engineer away (R2.6).
    This makes AC2 two-sided: identical *payload* is a no-op, identical *members with a changed
    tag* is **not**.
  - **Q2 absence is omission; `NA` is an error.** Adopt datom's existing "omitted, not nulled"
    convention (`R/read_write.R:296-299`) as the canonical form. A literal `NA` reaching the
    encoder **aborts** with "not encodable -- omit the field instead". Goldens carry the
    **refusal**, not an `NA` encoding. Note `null` therefore has **no tag** in the walk (R2.7).
  - **Q3 empty set refused.** `datom_write_set()` with zero members aborts, mirroring
    `.datom_canonical_hash()`'s zero-dim abort (`R/utils-sha.R:310-312`). Update AC5: refusal is
    the tested behavior (R2.8).
  - **Q4 `schema_version` stays out** of the payload and the hash -- container format, not content;
    in identity it would re-mint every set on a format bump (R2.9).
  - **Q5 emitter-free structural hash.** **No serializer in the identity path.** Deterministic walk
    of the **parsed** payload: radix-sorted keys recursively, fixed per-type leaf encoding with a
    domain-separation tag per type, accumulated as
    `sha256("datom-sv1" || encoded-walk)` (R2.10, design.md 7.2). `jsonlite` may format the
    **stored** file however it likes -- stored-byte integrity is `document_sha`'s separate job.
    **Identity and storage integrity never share a dependency.**
  - **The grammar is text-only and closed (R2.11), so the walk has THREE tags, not five**: string,
    string-array, object. No number, boolean or `null` tag -- numbers and booleans are not in the
    grammar, and `null` is unrepresentable because absence is omission. Enforce the grammar at
    write time and refuse anything else per offending type (AC27); without that test, "just allow
    numbers here" is a one-line change nobody notices (I24).
  - Consequence: **`.datom_encode_numeric()` is no longer reused for payload values** -- only its
    `f64le` framing is shared, for array and object lengths that datom computes itself. The pinned
    NaN and `-0 -> +0` folds are cv1 concerns that cannot arise in text.
  - Payload shape is **fixed** (R2.12): optional set-level `tags`, then `members[]` each with
    `{project, name, kind, version}` and optional per-member `tags`. Depth is bounded by the schema,
    not by what a caller nests.
  - **The R2.5 hard constraint still governs**, with its mechanism restated: write-time and
    read-time hashes must agree, and they now do **by construction** rather than via a
    serialize/parse cycle. Each mutation is killed at source (design.md 7.3): numbers always f64;
    `NA` aborts; `null` unrepresentable; scalar-vs-array decided by an explicit R-type rule. The
    one supporting condition -- reading with `simplifyVector = FALSE` -- is **already satisfied** by
    both backends (`R/utils-local.R:110`, `R/utils-s3.R:209`).
  - `.datom_sv1_value()` + `.datom_canonical_set_hash()` in a new `R/hashable-set.R` (or extend
    `R/utils-sha.R` -- decide at the review). **Reuse `.datom_encode_numeric()` verbatim**; do not
    write a second numeric encoder. (Its `NA_real_` branch is unreachable here.)
  - `dev/datom_sv1_reference.R`: standalone, `digest`-only, self-testing, prints goldens --
    mirroring `dev/datom_cv1_reference.R`. It is the **normative home of the byte rules and the tag
    table**, written against the walk spec and **not** against any emitter's output.
  - Extend `.github/workflows/cv1-reference-parity.yaml` (do not add a second workflow) to run the
    sv1 reference and assert package/reference parity on x86_64 **and** arm64.
  - Goldens hard-coded in tests, cross-architecture asserted, and covering: a length-1 list vs a
    scalar (must differ), a whole-number double (must agree with its integer round-trip), and the
    `NA` refusal (AC13).
  - _Requirements: R2 (incl. R2.5-R2.10). Invariants: I13. Properties: P1, P2, P3, P5, P6, P12,
    P15. Acceptance: AC2, AC5, AC13. No pathway impact._

- [ ] **3. Export and harden storage JSON put/get**
  - `datom_storage_read_json()` / `datom_storage_write_json()` on the Storage Extension API,
    wrapping the existing `.datom_storage_*_json()` internals (`R/utils-storage.R:66,83`).
  - Harden: conn class check, relative-key validation, clear abort on absent key, no direct
    `.datom_s3_*()` reachability (I7).
  - **Refuse datom-managed keys on the write export** (R12.4a): anything under a `.metadata/`
    segment, payload-shaped keys (`{name}/{sha}.{json,parquet}`) under an existing artifact
    directory, **and anything under a `.access/` segment**. The first two stop a downstream package
    overwriting `metadata.json` or a payload directly, **bypassing git-gates-storage and
    integrity**. The third protects the namespace reserved for the future access-enforcement
    package (`dev/datomanager_overview.md`) -- datom is safe there today only *by construction*,
    and this export is the first general-purpose write path that could break it (AC23). Reads stay
    unrestricted.
  - `_pkgdown.yml` reference entries; roxygen with runnable offline examples in the established
    bare-git-remote + local-store style.
  - _Requirements: R12.4, R12.4a. Invariants: I7, I14. Properties: P18. No pathway impact._

- [ ] **4. `schema_version` gate (reader side)**
  - `.datom_check_schema_version(meta, source)` -- one implementation, one message.
  - Wire into **both** entry points: `.datom_read_metadata()` (the `datom_read()` path, which
    never touches the manifest -- verified `R/read_write.R:44-58`) and the manifest readers
    (`datom_list()`, `datom_summary()`, `datom_status()`).
  - `SUPPORTED_SCHEMA <- 2L`. Asymmetric: refuse newer, tolerate older; absent defaults to `1`.
  - Add `schema_version` **and** `document_sha` to the `volatile` list at `R/utils-sha.R:412`.
  - Nothing writes `schema_version: 2` yet -- the gate lands tested-but-inert, so the writer bump
    in Task 5 cannot be the first exercise of untested gate code.
  - _Requirements: R9, R7.4. Invariants: I4. Properties: P10, P11. Acceptance: AC7._
  - _Pathway impact: read route gains a version gate -- update `dev/datom_pathways.md`._

---

## Phase B -- Manifest namespace **[BREAKING]**

- [ ] **5. `manifest$tables` -> `manifest$artifacts`, typed by `kind`** &nbsp; **[ESCALATION E2]**
  - Write side (2 sites): `.datom_update_manifest_entry()` (`R/sync.R:746,751-757`),
    `datom_init_repo()` seed (`R/conn.R:522-527`).
  - Read side (6 sites, 4 files): `datom_list()` (`R/query.R:58,85`), `datom_status()`
    (`R/query.R:439`), `.datom_status_input_files()` (`R/query.R:544,550`), `datom_summary()`
    (`R/summary.R:57`), `datom_sync_manifest()` (`R/sync.R:374,387`).
  - Each entry gains `kind` (`"table"` for everything existing). `summary` gains `total_sets`;
    `total_tables` / `total_size_bytes` / `total_versions` keep **current** semantics (tables
    only).
  - `datom_list()` and `datom_summary()` surface `kind`.
  - Manifest and per-artifact metadata now write `schema_version: 2`.
  - **Must land atomically across all eight sites plus tests.** A partial rename presents as
    "everything looks fine, the list is just empty."
  - _Requirements: R8, R9 (writer side). Invariants: I2, I4. No new pathway (route shapes
    unchanged) -- record explicitly._
  - **Escalation rationale**: touches `datom_list()`, `datom_summary()`, `datom_validate()` and
    the sync manifest updater together; failure mode is silent writer/reader disagreement.

---

## Phase C -- The set artifact

- [ ] **6. `kind` in metadata + set metadata builder + `document_sha`**
  - `kind: "table" | "set"` -- **semantic**, participates in `metadata_sha`. A **new field**, not
    a `table_type` value; `table_type` stays validated to exactly `imported`/`derived` (I12).
  - `.datom_build_metadata()` gains `kind = "table"`; new `.datom_build_set_metadata()` produces
    the collapsed field set (design.md section 4 matrix) using **conditional assign** so fields
    are omitted, not nulled.
  - `document_sha` persisted in `version_history.json` entries from day one, mirroring the
    `parquet_sha` conditional-add in `.datom_write_metadata_local()`.
  - _Requirements: R1, R7.1, R7.2. Invariants: I1, I12. Acceptance: AC8 (metadata half)._

- [ ] **7. `datom_member()` + validator + self-reference check**
  - `datom_member(conn, name, version)` mirroring `datom_parent()` (`R/lineage.R`): validate,
    read `{name}/.metadata/{version}.json`, derive `project` from `conn$project_name` and `kind`
    from the snapshot (defaulting to `"table"` for pre-`kind` metadata). Returns
    `{project, name, kind, version}` as pure data.
  - **Signature gains tags**: `datom_member(conn, name, version, tags = NULL)` -- an optional named
    list of text values, validated against the R2.11 grammar at construction time (R4.6). Tags are
    **per-member** because they replace dpbuild's `dp$input` / `dp$output` / `dp$metadata` nesting,
    which classifies items rather than the collection. A value may be a string **or** a character
    vector, because the whole point of tags over folders is that an item can be in several
    categories at once.
  - `.datom_validate_members()` mirroring `.datom_validate_parents()`, including the `remedy`
    string pointing at `datom_member()`. It owns the grammar refusal (AC27).
  - **Refuse self-reference** (R4.5, AC9): a set listing itself as a member. One cheap check. The
    set's own identity is known from `project.yaml` (R10.3a).
  - **Deliberately NOT built: cycle detection, a visited-set guard, or a depth limit** (R4.3/R4.4,
    design.md 5 and 20.11). Members pin immutable versions, so the graph is acyclic **by
    construction** -- a set cannot reference something that contains it, because that thing did not
    exist when its members were chosen (same property as git history). And datom resolves **one
    level** and never traverses, so nothing could loop even if a cycle existed. An earlier draft
    specified all three; they solved a problem that cannot occur. **Do not reintroduce them as
    defensive code** (I10a).
  - _Requirements: R4 (incl. R4.3-R4.5). Invariants: I9, I10, I10a. Acceptance: AC9._

- [ ] **8. `datom_write_set()`**
  - **Two gates first, before any hashing or IO** (R10.3a, I15): the repo must declare
    `mode: product`, and `name` must equal `project.yaml`'s `set:` field. These are what make
    "one repo = one set" real, and the second is the precondition the cycle walk's root depends on.
  - Payload derived from members (each with optional per-member tags) plus optional **set-level
    tags** -- and **nothing else**. No view or navigation config: folder structure is a consumer-side
    projection over tags, never stored (R4.7, I25). No `metadata =` parameter -- user metadata is
    tags (R1.4/R6.2).
  - Written **git-canonical + storage-mirrored**, with **different paths on each side** (R6.1a):
    git at the **stable path `{name}/set.json`** (modified in place, so `git diff` shows
    member-level changes and git owns the history), storage at the **content-addressed**
    `{name}/{data_sha}.json` via the Task 1 helper (so a reader fetches an exact version by
    address). **Do not content-address the git path** -- that makes every version a new file and
    forces history to be read by listing filenames, which is hand-maintaining what git maintains
    (R6.1b, R20, AC24). No retention rule is needed: git retention is definitional, and P17 holds
    via `git show <commit>:{name}/set.json`.
  - **Reuse unchanged**: change detection (`.datom_has_changes()`), the git-gates-storage ordering
    (`datom_write()` steps 7-10), and dedup. Git push stays the serialization point (I5).
  - Cross-kind name uniqueness refusal (AC4) -- checked against **storage**
    `{name}/.metadata/metadata.json`, not the manifest, which can lag.
  - Manifest entry with `kind = "set"` and `member_count`.
  - _Requirements: R5, R6 (incl. R6.1a/b), R10.3a, R12.2, R8 (set entries). Invariants: I2, I5,
    I6, I11, I15. Properties: P7, P13, P17. Acceptance: AC2, AC3, AC4, AC5._

- [ ] **9. `datom_read_set()` + `datom_read()` refusal**
  - `datom_read_set()`: resolve version -> read payload -> **verify `document_sha` before
    parsing** -> return members + payload. A missing `document_sha` is an **error, not a skip**
    (design.md section 8) -- sets have no legacy population, so reproducing the `parquet_sha`
    grace would build a silent-degradation path on purpose.
  - Works with **no git clone** (AC1a) -- storage-only readers are the primary consumer.
  - **Return member pointers; do not resolve them to data.** AC1 distinguishes *resolving the
    pointers* (always works through this one conn) from *resolving to data* (needs a conn for the
    member's project). Same-project members work through the same conn; cross-project members are
    the caller's to resolve (R18.1) -- datom has no name-to-location lookup. Getting this wrong
    mis-implements a set read as "requires access to everything in it", which would contradict the
    non-conjunctive access decision (R3.3).
  - **Both kind-mismatch directions abort with a pointer** (R12.3): `datom_read()` on a set ->
    `datom_read_set()` (AC6); `datom_read_set()` on a table -> `datom_read()` (AC14). Without the
    converse, a healthy table gets reported as a missing payload.
  - **One level only -- do not traverse** (R4.3, I10, AC15). A member that is itself a set is
    returned as a **pointer**; its own members are not fetched. Resist "helpfully" flattening the
    tree: a consumer wanting the full tree composes repeated reads, exactly as
    `datom_get_parents()` leaves further steps to the caller. Read cost must be a function of this
    set's direct member count, never of the depth beneath it (P16).
  - _Requirements: R12.3, R7.1, R6.4, R4.3. Invariants: I3, I8, I10. Properties: P9, P16.
    Acceptance: AC1, AC6, AC14, AC15._
  - _Pathway impact: new route card "Given a set + version, resolve its members"._

---

## Phase D -- Project mode, validation, docs

- [ ] **10. Project mode gating the import path**
  - `project.yaml` gains `mode: product` + `set: {name}` (R10.2). One repo = one set = one
    product.
  - `datom_sync_manifest()` / `datom_sync()` refuse on a product repo with a clear message
    instead of silently no-op'ing.
  - `datom_status()` reports mode.
  - The table write path is **not** gated -- product repos legitimately write derived tables.
  - `datom_init_repo()` gains the means to declare `mode`/`set` at init; the Task 8 gates read it.
  - `mode: product` is also the **identity badge** the build package checks at attach time
    (R10.5) -- the mode carries two meanings, both of which must hold.
  - **New namespace-separation guard** (R17.3, AC22): initializing a `mode: product` repo refuses a
    namespace that already holds another project's manifest, naming the occupying project and
    pointing at using a distinct prefix. Extends the existing `.datom_check_namespace_free()` path
    rather than adding a parallel check. **Justify it in the message and docs on blast radius**
    (prefix-delete and teardown operate on a whole namespace, so a shared prefix means deleting the
    product can delete raw data) -- **not** on access control, which is per-artifact and finer than
    a namespace anyway (R17.4, R19.1).
  - _Requirements: R10 (incl. R10.3a, R10.5), R17. Invariants: I15. Acceptance: AC22._

- [ ] **11. Foreign-content discipline + `datom_repo_commit()`**
  - **Elevate machine-commit isolation from accident to guarantee** (R14.1, I16). Already true by
    implementation -- `.datom_git_commit()` takes an explicit file list (`R/utils-git.R:182`) --
    so this is primarily a **test** so a future add-all refactor fails CI rather than an audit:
    dirty `R/foo.R` + `datom_write()` of a table, assert the commit tree excludes it **and** it is
    still dirty afterward (AC16). Both halves -- the second catches a helpfully-cleaned tree.
  - **Assert tolerance of non-datom paths** (R14.2). This already holds by construction --
    `.datom_validate_tables()` filters on the presence of `metadata.json`, so `dp/` is skipped for
    that reason, not because of the hardcoded exclusion list (design.md section 19.7). So again:
    tests, not new code. `datom_status()` may *report* foreign dirty files as git state; it must
    not classify them as a datom defect, and `datom_validate()` must not surface them at all.
  - **New exports: `datom_repo_commit(conn, message, paths = NULL, push = TRUE)` and
    `datom_repo_push(conn)`** (R15) -- the sanctioned git-mutation surface, so downstream packages
    never import `git2r` (I17). **Both verbs are required**: `push = FALSE` without a standalone
    push verb means "push what I already committed" is only expressible as another commit attempt,
    and in a product repo `paths = NULL` is add-all -- so a push-only caller would risk committing
    human WIP (design.md section 19.8, I20).
  - **Commit is idempotent, push is convergent, neither implies the other.** R15.5's no-op means no
    *commit*; with `push = TRUE` and the branch ahead, the push still runs -- otherwise one failed
    push leaves the remote silently behind forever, since every later call finds a clean tree and
    returns early. The ahead count needs no new machinery: `.datom_check_git_current()` already
    calls `git2r::ahead_behind()` and reads `[[2]]` (behind); `[[1]]` is ahead (R15.9).
  - **Mind the two delta corrections** (design.md section 19.6), both of which change the
    implementation:
    - `.datom_git_commit()` does **not** abort on empty staging -- it returns HEAD's SHA. It
      aborts on an **empty `files` argument** and on **nonexistent files**. So `paths = NULL`
      cannot delegate with `files = character(0)`, and the wrapper must determine "nothing to do"
      itself (status check, or HEAD before/after) to honor R15.5's `invisible(NULL)` no-op.
    - The on-a-branch guard lives in `.datom_git_branch()` and is only reached via
      `.datom_git_push()`, so it does **not** fire when `push = FALSE`. Assert it explicitly up
      front (R15.7).
  - Roxygen: document that `paths = NULL` means what `git add .` means, including that it may
    sweep in dirty datom files left by a previously failed write -- intentional, and
    `datom_validate(fix = TRUE)` is the repair path (design.md section 19.7).
  - Tests: gitignore-respecting add-all; explicit `paths` stages exactly those; reader conn
    refused; empty staging creates no commit and is not an error; `push = FALSE` leaves the remote
    untouched; **clean tree + `push = TRUE` + branch ahead advances the remote with no new commit**
    (AC17). For `datom_repo_push()`: advances the remote, second call is a no-op, reader conn
    refused, on-a-branch guard inherited (AC21).
  - _Requirements: R14, R15 (incl. R15.8/R15.9). Invariants: I16, I17, I20. Properties: P19, P22,
    P23, P24. Acceptance: AC16, AC17, AC21. No pathway impact._

- [ ] **12. `datom_write_set(include_paths = )` -- the joint commit**
  - Follow-on to Task 8 rather than folded into it: Task 8 is already large (two gates, dual-write,
    dedup, name uniqueness, manifest), and the dedup edge below deserves its own commit.
  - `include_paths`: repo-relative paths staged **into the same commit** as the payload and
    metadata, so the joint version is **structural, not recorded** (R12.5). Ordering unchanged:
    local writes -> one commit -> push -> storage mirror.
  - **Storage mirror stays datom-artifacts-only** -- `include_paths` content is never mirrored
    (I18, AC18).
  - **Validation before any hashing or IO** (matching R10.3a placement): a nonexistent path is an
    **error**, not a skip; a path overlapping `{artifact}/**` or `.datom/**` is **refused**
    (AC20). **Two separate test cases**, not one bundled assertion, so a regression identifies
    which gate broke.
  - **The sharp edge**: an unchanged set stays a **no-op even when `include_paths` files are
    dirty** -- no commit, no version, informational message pointing at `datom_repo_commit()`
    (R12.5, I19, AC19). AC2's idempotency must not acquire a side channel that commits code; that
    would be the machine-moment add-all failure arriving through a different door.
  - Update P17's claim in the docs: with `include_paths`, checkout of a set version's commit
    yields code + environment + data pointers, not pointers alone.
  - _Requirements: R12.5. Invariants: I18, I19. Properties: P17 (strengthened), P20, P21.
    Acceptance: AC18, AC19, AC20._

- [ ] **13. `datom_validate()` branches on `kind`**
  - `.datom_validate_one_table()` at `R/validate.R:386` currently hardcodes
    `paste0(name, "/", meta$data_sha, ".parquet")`, which fails 100% of the time on a set.
  - **table**: existing parquet check, unchanged. **set**: payload exists at
    `{name}/{data_sha}.json` **and** every member resolves *as far as the connections allow* --
    same-project members fully checked, cross-project members checked as well-formed pointers
    unless the caller supplies that project's conn (R11.2). datom does no name-to-location lookup
    of its own (R18.1), so a validator claiming to fully check cross-project members would either
    be lying or silently requiring governance.
  - New status code `members_unresolvable`, distinguishable from a missing payload (P14).
  - **Member checking is one level deep** (R4.3, I10): each member pointer resolves to an existing
    artifact. The validator does not descend into nested sets -- validating an inner set is a
    separate `datom_validate()` call against that set's own project.
  - Set branch compares **git payload vs storage payload**, which R6.1b's git retention makes
    possible; this is a real two-sided check, not a storage self-check.
  - _Requirements: R11, R4.3. Invariants: I10. Properties: P14, P16, P17._

- [ ] **14. Version-to-commit link (`commit_sha`)**
  - Applies to **all** artifact kinds, not just sets -- `version_history.json` is shared. Placed
    after Task 13 because the repair-path behavior below needs `datom_validate()` to exist.
  - Add `commit_sha` to the **storage copy** of the `version_history.json` entry, beside `author`
    and `commit_message` (R21.5). **No volatile-list entry needed**: `metadata_sha` hashes
    `metadata.json`, not `version_history.json`, so this has zero identity impact.
  - Captured in `.datom_push_metadata_s3()` (step 7 of the write order, after the push), because
    the git copy of the history file is **inside** the commit it would name (R21.6). The git copy
    therefore never carries it, and does not need to -- `git log -p {name}/set.json` gives it to
    anyone with the clone (R21.8).
  - **The trap, and the reason this is its own task** (R21.7, I22, AC25): `datom_validate(fix =
    TRUE)` re-uploads metadata from the clone and would **silently strip `commit_sha`**. Treat the
    field as **derived, never authored** -- the repair path must **re-derive** it from `git log` on
    the artifact path. A naive implementation passes every other test and fails only this one,
    silently.
  - Document the version semantics this encodes (R21.1-R21.3): a version is content-derived and
    **code-invariant**, so a code-only change producing identical content mints **no** new version
    and leaves the recorded `commit_sha` alone (AC26). Roxygen should say this plainly -- it is the
    behavior most likely to be reported as a bug.
  - _Requirements: R20, R21. Invariants: I21, I22, I23. Properties: P26, P27. Acceptance: AC25,
    AC26. No pathway impact (no new lookup route -- the existing history read gains a field)._

- [ ] **15. Acceptance-criteria test sweep + E2E** &nbsp; **[soft escalation: coverage review]**
  - Confirm every **AC1-AC9 and AC13-AC26** has a dedicated test; add what the per-chunk tests
    missed. Two are easiest to skip and both need special fixtures: **AC15** (nesting resolves one
    level) needs a set-containing-a-set fixture and an assertion that the inner payload is *not*
    read; **AC16** (machine-commit isolation) needs a foreign dirty file seeded in the fixture repo,
    which no other test creates.
  - New `dev/e2e-sets.R` in the style of `dev/e2e-cv1-identity.R`: offline, no PAT, no AWS, real
    bare-git remote + real local store, every claim asserted, non-zero exit on mismatch (AC12).
    Include a `mode: product` repo with foreign `R/`, `dp/`, and `renv.lock` content so the joint
    commit and the machine-commit isolation are exercised end to end, not only in unit tests.
  - Full `devtools::test()` count reported; `R CMD check --as-cran` 0E/0W (AC10, AC11).
  - _Acceptance: AC1-AC26._
  - **Escalation rationale**: nine acceptance criteria plus a new hash regime is a lot of surface
    to claim covered on a default model's word.

- [ ] **16. Docs + Spec Completion Procedure**
  - `dev/datom_pathways.md`: the set-resolution route card; note the `kind` branch and the
    `schema_version` gate on the read route (R13.1).
  - `dev/datom_specification.md`: set artifact kind, `datom-sv1`, `schema_version` contract,
    `artifacts` namespace (R13.2).
  - `NEWS.md`: the `artifacts` rename with its discovery-only exposure, the `schema_version`
    gate, the new exports (R13.4).
  - `dev/engineering-notes.md`: gotchas discovered (expect at least the relative-vs-full key
    distinction from Deviation D1).
  - `_pkgdown.yml` reference entries for all new exports.
  - `dev/README.md`: move the spec Active -> Completed with date, test count, summary. **The spec
    persists -- do not delete it.**
  - PR into `dev`, merge, delete branch.
  - _Requirements: R13._

---

## New exports introduced by this spec

Track so `_pkgdown.yml` and NAMESPACE stay complete:

| Export | Task |
|---|---|
| `datom_storage_read_json()` | 3 |
| `datom_storage_write_json()` | 3 |
| `datom_member()` | 7 |
| `datom_write_set()` | 8 (extended with `include_paths` in 12) |
| `datom_read_set()` | 9 |
| `datom_repo_commit()` | 11 |
| `datom_repo_push()` | 11 |

---

## Decisions log

Record decisions as they are made, so a fresh session does not relitigate them.

| Date | Decision | Where |
|---|---|---|
| 2026-08-09 | Branched from `dev`, not `main`. `dev/README.md` "Branching During CRAN Submission" governs while 0.1.0 is in review; the `from main` wording in copilot-instructions item 0b is the no-freeze default. | requirements.md header |
| 2026-08-09 | #89's "keys go through `.datom_build_storage_key()`" cannot be followed literally -- that function returns a **full** key while `.datom_storage_*()` takes **relative** keys. Honor the intent with relative-key helpers instead. | design.md Deviation D1 |
| 2026-08-09 | `datom_member()` deliberately does **not** carry `data_sha` (unlike `datom_parent()`). `data_sha` exists on parents to support cross-project lineage resolution, which sets explicitly do not do. | design.md section 5 |
| 2026-08-09 | Missing `document_sha` on a set read is an **error**, not a skip. The `parquet_sha` skip branch is a pre-cv1 migration grace; sets have no legacy population. | design.md section 8 |
| 2026-08-09 | `metadata_sha`'s own emitter-drift exposure is filed as a separate issue, not folded into this spec. | design.md section 16, Task 1 |
| 2026-08-09 | **Independent spec review.** All 12 findings verified against the code and accepted; none rejected. Full audit trail with per-finding verification method and resolution. | design.md section 18 |
| 2026-08-09 | ~~**(F1)** Write-time cycle detection is exhaustive within a project only; read-side visited-set + depth guarding is a requirement.~~ **SUPERSEDED 2026-08-11 -- see the entry below.** The premise was false. | design.md 20.11 |
| 2026-08-09 | **(F2)** `datom-sv1` hashes the **parsed-JSON** data model, not the in-memory R object. Reproduced on the branch: `NA_real_` -> string `"NA"`, doubles -> integers, `NA_character_` -> `null`. A type-tagged encoder over the in-memory object would disagree with itself across the round trip. Elevated from open question to hard constraint. **Mechanism superseded 2026-08-15 by Q5** -- the original `serialize -> parse -> encode` normalization is replaced by eliminating each mutation at source; the constraint itself stands unchanged. | R2.5, design.md 7.1/7.3 |
| 2026-08-09 | **(F2/Q5)** Which serializer defines sv1's canonical form -- `jsonlite` vs an sv1-owned minimal emitter -- is now the load-bearing open question, because the round-trip constraint forces the choice into the open. Coupled to the section 16 issue. | design.md section 7 Q5, E1 |
| 2026-08-09 | **(F3)** The public `datom_storage_write_json()` refuses datom-managed keys (`.metadata/` segments, payload-shaped keys under existing artifacts). Reads unrestricted. Public-contract decision settled in the spec. | R12.4a, I14 |
| 2026-08-09 | **(F4)** A set's metadata is **exactly** R1.3's seven fields. `size_bytes` dropped (no consumer), `custom` dropped (payload already owns user metadata, R6.2) -- so `datom_write_set()` has no `metadata =` parameter. | R1.4, design.md section 4 |
| 2026-08-09 | **(F5)** `datom_write_set()` requires `mode: product` **and** a name matching `project.yaml`'s `set:`, both checked before any hashing or IO. This is what makes "one repo = one set" enforced rather than aspirational. | R10.3a, I15 |
| 2026-08-09 | **(F7)** Set payloads live in git at `{name}/{data_sha}.json` (same relative path as the storage key) and **all historical payloads are retained**, so any version is reconstructible from the clone alone. The `governance.json` *ordering* transfers; its singleton *layout* does not. | R6.1a/b, P17 |
| 2026-08-09 | **(F12)** The stale "task 5.1" text is at `R/read_write.R:105-108, 205-206, 413`, with `393` already correct and therefore contradicting. #89's `95-97` citation was wrong and the first spec draft propagated it. | R13.3, Task 1 |
| 2026-08-11 | **Spec delta D1-D8 applied** from #89. **The `mode: product` repo IS the joint repo** (data + code + `renv.lock`); no separate fourth repo. Decisive reason: cross-repo pinning is circular -- the code repo wants to record which set version it produced and the set payload wants to record which code commit produced it, so one is always stale by one commit. A joint version requires one commit graph. | design.md section 19, R14 |
| 2026-08-11 | **datom is the single git-mutating actor** (I17). Downstream packages never import `git2r`; all stage/commit/push/pull goes through a datom export. Writing files on disk is *not* a git operation and needs no datom API -- hence **no `datom_gitignore_*` API**, ever. | I17, R16, design.md 19.5 |
| 2026-08-11 | **Machine vs human commit moments is the load-bearing distinction.** `dpbuild`'s add-all was safe only because every commit was human-invoked. datom commits at machine-chosen moments, so add-all there would snapshot arbitrary WIP human code. Machine moments stage datom paths only (R14.1); human moments get add-all via `datom_repo_commit(paths = NULL)` (R15.1). | design.md 19.4 |
| 2026-08-11 | `include_paths` (R12.5) is the **only** way a machine-moment commit may carry a non-datom path, and only because the caller enumerated it. Never add-all. | R14.3, I16 |
| 2026-08-11 | An idempotent set re-write stays a no-op **even with dirty `include_paths`** (I19). AC2 must not acquire a side channel that commits code -- that would be the add-all failure through a different door. Caller is directed to `datom_repo_commit()`. | R12.5, AC19 |
| 2026-08-11 | **(delta correction C1)** `.datom_git_commit()` does **not** abort on empty staging -- it returns HEAD's SHA. It aborts on an empty `files` **argument** and on nonexistent files. So `datom_repo_commit(paths = NULL)` cannot delegate with `files = character(0)`, and must determine "nothing to do" itself to honor the `invisible(NULL)` no-op contract. | design.md 19.6, R15.5, Task 11 |
| 2026-08-11 | **(delta correction C2)** The on-a-branch guard lives in `.datom_git_branch()`, reached only via `.datom_git_push()`, so it does not fire when `push = FALSE`. Assert it explicitly. | design.md 19.6, R15.7, Task 11 |
| 2026-08-11 | `datom_repo_commit(paths = NULL)` may sweep in dirty datom files left by a failed write. **Deliberately not special-cased**: it moves git ahead of storage (the safe direction), `datom_validate(fix = TRUE)` is the existing repair path, and excluding them would make the function lie about `git add .` semantics. | design.md 19.7 |
| 2026-08-11 | Tasks renumbered: two tasks inserted after 10 (foreign-content discipline + `datom_repo_commit()`; `include_paths`). Old 11/12/13 -> 13/14/15. | tasks.md Phase D |
| 2026-08-11 | **(F13)** Push decoupling had only one half -- `push = FALSE` with no way to push later. **Both proposed fixes adopted**, because they solve different problems. Add **`datom_repo_push()`** (R15.8): routing push intent through `commit()` would force a push-only caller through the `paths = NULL` add-all path, which in a product repo commits whatever human WIP it finds -- the R14 hazard through a third door -- and would leave `message` a silently-ignored required argument. **And** make push **convergent** (R15.5 qualified, R15.8): a no-op means no *commit*, not no push, because otherwise one failed push leaves the remote silently behind forever as every later call returns early on a clean tree. | design.md 19.8, I20, P23, P24 |
| 2026-08-11 | Supporting the export over the wrapper-only fix: datom **already exports standalone `datom_pull()`** (`R/sync.R:45`) with no push counterpart, and the `datom_repo_*` family already exists -- so this closes an asymmetry rather than inventing a shape. Cost is one thin wrapper plus one array index: `.datom_check_git_current()` already calls `git2r::ahead_behind()` and reads `[[2]]`; `[[1]]` is the ahead count. | design.md 19.8, R15.9 |
| 2026-08-11 | **(F14)** AC20 stays one criterion but is **tested as two cases** (nonexistent path; datom-owned overlap), so a regression identifies which gate broke. | AC20, Task 12 |
| 2026-08-11 | **Artifact topology settled**: one repo = one namespace (`{root}/{prefix}/datom/`) = one manifest, 1:1:1. A set lands in the **product repo's** namespace, never with onboarded source data. Two manifests with the same schema, zero shared files. Matches the documented house convention (`buckets-and-prefixes.Rmd`: "prefix per product"). | R17, design.md 20.1-20.5 |
| 2026-08-11 | **New init guard** (R17.3): a `mode: product` repo refuses a namespace already holding another project's manifest. Justified on **blast radius** -- prefix-delete/teardown operate on a whole namespace, so a shared prefix means deleting the product can delete raw data -- plus one-manifest ownership. Enforced rather than documented because the utility of mixing is ~zero (a second prefix costs nothing) while the failure is destructive. | R17.3/R17.4, AC22, Task 10 |
| 2026-08-11 | **Correction: datom needs NO governance for cross-project members or parents.** The mechanism is caller-supplies-connection; the project name is a label and datom performs no name-to-location lookup anywhere. An earlier claim that cross-bucket products "effectively expect gov attached" was wrong -- it conflated datom's write-time needs with the access layer's read-time SOURCES lookup. | R18.1, design.md 20.3 |
| 2026-08-11 | **Location precedence, inherited not invented**: explicit address in the project's own config works standalone; `ref.json` in the gov repo takes priority once governance exists; `governance.json` is the flag for whether it is attached. Member resolution follows this exact precedence. Therefore **member records carry a logical project name and never a location** -- an embedded location would go stale on a bucket move, which is what `ref.json` exists to prevent. | R18.2/R18.3 |
| 2026-08-11 | **Correction: the access unit is the artifact, not the namespace.** Roles are table-level and a derived table's requirement is the union of its **leaf ancestors'** roles, so two derived tables in one product/bucket/prefix get different requirements automatically. Per-artifact IAM is expressible because every artifact has its own folder. The namespace rule therefore **keeps its conclusion but changes its justification** (blast radius + ownership, not access) -- a rule defended by a wrong argument gets relitigated. | R19.1/R19.2, R17.4, design.md 20.6 |
| 2026-08-11 | **A set gates on nothing** -- no parents means the lineage walk finds no leaves, so no roles are required unless explicitly overridden. Same conclusion as the non-conjunctive access decision, now confirmed against the access layer's algorithm. Corollaries recorded because they surprise people: **granting a product does not grant its members**, and a **sensitive member list uses the explicit-override path**. | R19.3-R19.5, design.md 20.7 |
| 2026-08-11 | The JSON write export must also refuse **`.access/`** -- the namespace reserved for the access-enforcement package, where datom is safe today only *by construction*. This export is the first general-purpose write path that could break that reservation. | R12.4a/R19.6, AC23, Task 3 |
| 2026-08-11 | **`role` terminology collision**: datom's `role` (developer/reader) vs the access layer's "role" (permission set). **datom keeps `role`; the burden is on the future package to pick a different term** -- it does not exist yet so the rename is free there and breaking here. Recorded in `dev/datomanager_overview.md` for whoever builds it. | design.md 20.9 |
| 2026-08-11 | **Clarified: there is no lineage walk.** `source_lineage` is a precomputed transitive union maintained at write time -- imported tables get a self-entry, derived tables get the union of their parents' unions -- so "which raw sources feed X" is **one read, zero hops**, and it cannot drift because parents pin immutable versions. Design section 20.6 initially repeated the access design's "walk upward" framing; corrected. | design.md 20.10 |
| 2026-08-11 | **`dev/datomanager_overview.md` is stale on this point and now says so.** It predates Phase 20, so it requires only `parents` and builds a walk -> session-cache -> *precomputed leaf map* ladder. `source_lineage` **is** that leaf map, already stored per table. Added item 3a plus stale-markers on the affected sections: delete the walk, do not rebuild `ROLE_LEAVES`, keep the access *semantics*. | dev/datomanager_overview.md |
| 2026-08-11 | **RESOLVED -- all nesting machinery removed** (supersedes F1 and the two OPEN entries that preceded this). Cycle detection, the visited-set guard, and the depth limit are **gone**, for two independent reasons either of which suffices: (1) **datom resolves one level and never traverses** -- a member that is a set comes back as a pointer and the consumer reads it separately, so nothing can loop; (2) **the graph is acyclic by construction** -- members pin immutable versions that must already exist, so a set cannot reference something containing it, exactly as git history cannot cycle. The "cross-project cycle" earlier constructed does not close: the second write creates a new version rather than mutating the referenced one, giving `B1@v2 -> A1@v1 -> B1@v1`, which terminates. | R4.3-R4.5, I10/I10a, P16, AC9/AC15, design.md 5 + 20.11 |
| 2026-08-11 | Replacements after the removal: **R4.3** one-level resolution, **R4.4** acyclic by construction, **R4.5** refuse self-reference (the one check that stays -- acyclic and harmless, but never meaningful). **I10** no traversal, **I10a** no cycle/depth guard may creep back as defensive code. **P16** restated as "read cost is bounded by direct member count". **AC9** restated as self-reference refusal, **AC15** restated as "nesting resolves one level" -- a test that the tree is *not* flattened. | requirements.md R4, design.md 13-14 |
| 2026-08-11 | **Retired: the transitive-member-closure question** (formerly E1 Q6). It existed only to replace a traversal with one read; there is no traversal, so it would be payload weight buying nothing and would enter set identity for no benefit. E1 is back to one hard constraint + five open questions. | design.md 7, 20.11 |
| 2026-08-11 | **Git owns history; datom writes projections** (R20). The test: *would someone holding the repo use this file to answer a history question?* `version_history.json` and `manifest.json` pass -- only git-less **readers** need them, and the giveaway that they are projections rather than duplicates is that they carry `author` and `commit_message`, literally git commit fields. | design.md 21.1 |
| 2026-08-11 | **Correction: the git payload moves to a stable path `{name}/set.json`**; storage stays content-addressed at `{name}/{data_sha}.json`. A content-addressed *git* filename makes every version a new file, so `git diff` reports "file added" instead of which members changed, and history gets read by listing filenames -- hand-maintaining what git maintains. The "retain all historical payloads" rule is dropped as redundant (git retention is definitional); P17 holds via `git show <commit>:{name}/set.json`. | R6.1a/b, P25, AC24, design.md 21.2 |
| 2026-08-11 | **Version semantics -- option 1 chosen.** A version stays **content-derived and code-invariant**, identically for tables and sets; the commit is recorded **provenance**, not identity. So a code-only change producing identical content mints **no** new version (already true for tables, deliberately kept true for sets), and one version maps to **one or more** commits with `commit_sha` naming the first. | R21.1-R21.3, I23, P27, AC26, design.md 21.3 |
| 2026-08-11 | **Rejected: commit-as-version** (circular -- the commit contains the metadata that would name it; a composite version would break `datom_read(version = )` as a single string). **Rejected: code/env content hashes in the payload**, which *would* work mechanically, because a set exists to be **citable** and a comment typo or lint fix would then mint a new product version. The strongest counter-argument -- restricting it to `renv.lock`, since env drift can silently change future behavior -- is recorded in case it returns. | R21.4, design.md 21.3 |
| 2026-08-11 | **`commit_sha` goes in the `version_history.json` entry**, storage copy only (the git copy is inside the commit it would name), captured after the push. Zero identity impact and **no volatile-list entry needed**, because `metadata_sha` hashes `metadata.json`, not `version_history.json`. | R21.5/R21.6, Task 14 |
| 2026-08-11 | **The trap: `datom_validate(fix = TRUE)` would silently strip `commit_sha`** when it re-uploads metadata from the clone. Resolved by treating the field as **derived, never authored** -- the repair path re-derives it from `git log`, so storage holds nothing unrecoverable and the "mirror is derived from git" invariant survives. AC25's third clause exists to catch this; a naive implementation passes everything else. | R21.7, I22, P26 |
| 2026-08-11 | **Precedent checked, not assumed** (public sources): dpbuild keeps no commit hash in the product repo -- `.daap/daap_log.yaml` is inside the commit -- and dpdeploy publishes it to a storage-side `dpboard-log` pin that dpi's `dp_list()` reads **with no git**. That log's composite key is `(dp_name, pin_version, git_sha)`, independently confirming that one content version can pair with several commits. datom needs no separate deploy pass (it already uploads after push) and adds no board-level index (per-artifact history already carries the sibling git fields). **Corrects an earlier claim in this conversation that dpbuild had no git-less readers -- dpi is exactly that.** | R21.9, design.md 21.5 |
| 2026-08-11 | Tasks: **new Task 14** (version-to-commit link) inserted after validate, since its repair-path behavior needs `datom_validate()` to exist. Old 14/15 -> 15/16. | tasks.md Phase D |
| 2026-08-15 | **E1 Q1 -- OWNER-DECIDED: whole-payload hashing.** `data_sha` covers members **and** their tags (a description is a tag). A set is citable, and "same cite, different tags" would lie to the consumer. A tag or description edit therefore **mints a new version** -- intended behavior. Consequence applied: **AC2 was wrong** as written ("identical member list is a no-op") and is now two-sided -- identical *payload* is a no-op, identical members with a changed tag is **not**. | R2.6, AC2, design.md 7.5 |
| 2026-08-15 | **E1 Q2 -- OWNER-DECIDED: dissolved by the omission rule.** A payload has no data cells, so `NA` could only arrive via optional fields. datom's existing "omitted, not nulled" convention (verified `R/read_write.R:296-299`) becomes the canonical form: absence means the field **does not exist**; `null` / `NA` / `""` are never representations of absence. A literal `NA` reaching the encoder is an **error**, not an encoding case, and goldens carry the refusal. Knock-on: the walk has **no `null` tag** (the earlier draft's `0x04` is dropped), and this is where sv1 legitimately diverges from cv1, which needs an NA mask byte because table cells *can* be missing. | R2.7, design.md 7.2/7.5 |
| 2026-08-15 | **E1 Q3 -- OWNER-DECIDED: empty set refused.** Mirrors cv1's zero-dim abort (verified `R/utils-sha.R:310-312`). Marginal utility -- the build package simply does not write the set until its first output exists -- and an empty citable product is semantically murky. Cheap to relax later, awkward to retract. AC5 updated: refusal is the **tested** behavior, not a documented maybe. | R2.8, AC5 |
| 2026-08-15 | **E1 Q4 -- OWNER-DECIDED: `schema_version` stays out of the payload and hash.** It describes the container format, not the content; in identity a format bump would re-mint every set with unchanged members -- the same failure the `volatile` list exists to prevent (verified `R/utils-sha.R:411-412`). | R2.9 |
| 2026-08-15 | **E1 Q5 -- OWNER-DECIDED: emitter-free structural hash.** Neither `jsonlite` nor a bespoke sv1 emitter is canonical, because **no serializer is in the identity path**. sv1 is a deterministic walk of the parsed payload: radix-sorted keys recursively, fixed per-type leaf encoding with a domain-separation tag per type, `sha256("datom-sv1" \|\| encoded-walk)`. Stored-file formatting is free, because stored-byte integrity is `document_sha`'s separate job -- **identity and storage integrity never share a dependency**. Goldens and `dev/datom_sv1_reference.R` are written against the walk spec, not any emitter's output. | R2.10, design.md 7.2/7.4 |
| 2026-08-15 | **R2.5's force stands; its mechanism is superseded.** The write/read agreement constraint is unchanged, but it is no longer achieved by normalizing through `serialize -> parse -> encode`. Each mutation is eliminated at source instead: numbers always f64 (kills integer-vs-double), `NA` aborts (kills the `"NA"` string and `null` cases), and scalar-vs-array is decided by an explicit R-type rule. **Verified bonus**: the one supporting condition -- reading with `simplifyVector = FALSE` -- is *already* satisfied deliberately by both backends (`R/utils-local.R:110`, `R/utils-s3.R:209`, the latter documented as "keep lists as lists"). So the decision is supported by existing infrastructure rather than imposing a new read-path requirement. | R2.5, design.md 7.1/7.3 |
| 2026-08-15 | **sv1 does not inherit the `metadata_sha` emitter exposure** (section 16). The earlier "cannot both be right" tension is resolved one-sidedly: sv1 is clean by construction, which *sharpens* rather than softens the case for the separate `metadata_sha` issue, since it becomes the only hash in datom whose value depends on a third-party formatter. Scope of that issue unchanged; priority arguably rises. | design.md 7.4, 16 |
| 2026-08-15 | **E1 downgraded from open-question debate to design review.** Gate for Task 2 is now: exact byte rules, whether the tag table leaves a collision surface, and whether the goldens cover the 7.3 agreement cases. Goldens still freeze the encoding -- a later change needs a conscious `datom-sv2` bump. | design.md E1, Task 2 |
| 2026-08-15 | **The payload is text-only, and that is a closed grammar** (R2.11). Values are UTF-8 strings or arrays of strings; **no numbers, booleans, `null`, or nesting beyond the fixed shape** (R2.12). Rationale: tags replace folder-style organisation and folder labels are text, so numbers and booleans buy nothing datom uses while costing an integer-vs-double rule, a boolean tag, and a wider golden matrix. A numeric tag is written `"500"` and parsed downstream, exactly as a folder name would be. | R2.11, I24, AC27 |
| 2026-08-15 | **Consequence: the walk collapses from five type tags to three** (string / string-array / object). Three of R2.5's four agreement hazards become **unrepresentable rather than handled** -- int-vs-double and `NA_real_` because there are no numbers, `null` because absence is omission. Only scalar-vs-length-1-array remains an actual rule. `.datom_encode_numeric()` is no longer reused for payload values; only its `f64le` length framing is shared, for lengths datom computes itself. | design.md 7.2/7.3, Task 2 |
| 2026-08-15 | **Tags are per-member** (R4.6), and `datom_member()` gains `tags = NULL`. What they replace is dpbuild's nested product list (`dp$input$raw_ae()`, `dp$output$derived1`, `dp$metadata$data_def`), whose top-level names classify **items**, not the collection -- confirmed by #89's own rejected alternative, which flattened to `(name, project, version, tag_key, tag_value)`, one row per member per tag. Set-level tags are also allowed, for facts about the collection such as a description. | R4.6, Task 7 |
| 2026-08-15 | **A tag value may be a string OR an array of strings**, and that is the *only* reason arrays exist in the grammar. The motivating limitation of folders is that an item cannot be in two at once, so multi-valued tags (`domain: ["safety", "efficacy"]`) are the point rather than an extension. | R2.11, R4.6 |
| 2026-08-15 | **#89's "view config" is retired; no navigation structure is stored at all** (R4.7, I25). Folder-like hierarchy is a **projection**: prioritise one ordering of tag keys at gov level and you get one structure, prioritise another and you get a different one -- so structure is presentation, not content. This retires the "nested view config does not survive the flattening" argument, since navigation *is* the tags, and it is what makes the text-only grammar sufficient. Bonus property: arbitrarily many folder structures cost nothing because none is stored. | R4.7, I25, P29 |
| 2026-08-15 | Closures stay downstream: dpbuild's inputs are lazy closures, whereas a datom member is a pointer and `datom_read()` is the lazy fetch. Assembling closures is the build package's job -- the layering #89 asked for. No datom change. | design.md s4 |
| 2026-08-15 | **Git-commit-linkage follow-ups asked and confirmed as-is, no change** (R20/R21): (a) lagging `commit_sha` into the git copy on a subsequent write, (b) moving the linkage into governance, (c) recording *all* producing commits rather than the first. Examined; the existing spec answers hold -- (a) leaves the newest version permanently unlinked, (b) makes a git-less-reader convenience depend on gov being attached, (c) turns an immutable history entry into an append target. Logged so they are not re-litigated. | R20, R21 |
| 2026-08-11 | **Process lesson recorded, not patched over.** The nesting machinery entered via review finding F1, which correctly spotted a contradiction between two spec statements and was resolved by *adding* guards rather than by testing whether either statement was true. Both were false. When a review surfaces a contradiction, **check the premises before building something to reconcile them**. | design.md 18 (F1 row), 20.11 |
| 2026-08-11 | **AC1 split** into (a) resolve pointers -- always works, no clone -- and (b) resolve to data -- needs that member's project conn. Conflating them mis-implements a set read as "requires access to everything in it". `datom_validate()`'s member check scoped the same way (R11.2), reusing `members_unresolvable`. | AC1, R11.2, Tasks 9 and 13 |
