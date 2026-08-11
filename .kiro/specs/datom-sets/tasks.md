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

- [ ] **2. `datom-sv1` canonical set-content hash** &nbsp; **[ESCALATION E1]**
  - **Honor the hard constraint (R2.5, design.md section 7): the hash domain is the parsed-JSON
    data model.** Normalize by construction -- `serialize -> parse -> encode`. A type-tagged
    encoder run over the in-memory R object produces a *different* `data_sha` than the same
    encoder over the parsed payload (`NA_real_` becomes the string `"NA"`, doubles return as
    integers), which breaks P1/P2. **This is not optional and not an open question.**
  - **Settle the five open questions in design.md section 7 before writing the encoder**:
    Q1 whole-payload vs member-list-only; Q2 `NA_character_` vs `""` vs `null` (a special case of
    the constraint); Q3 empty-set legality (AC5); Q4 whether `schema_version` enters the payload;
    **Q5 which serializer defines the canonical form** -- `jsonlite` (consistent, but makes the
    goldens depend on a third-party emitter, the exact dependency #72 removed for parquet) or an
    sv1-owned minimal emitter (more code, goldens depend only on the spec). Q5 is load-bearing and
    coupled to the section 16 issue.
  - `.datom_sv1_value()` + `.datom_canonical_set_hash()` in a new `R/hashable-set.R` (or extend
    `R/utils-sha.R` -- decide at escalation). Reuse `.datom_encode_numeric()` verbatim; do not
    write a second numeric encoder.
  - `dev/datom_sv1_reference.R`: standalone, `digest`-only, self-testing, prints goldens --
    mirroring `dev/datom_cv1_reference.R`.
  - Extend `.github/workflows/cv1-reference-parity.yaml` (do not add a second workflow) to run
    the sv1 reference and assert package/reference parity on x86_64 **and** arm64.
  - Golden vectors hard-coded in tests, cross-architecture asserted. **Goldens must include the
    round-trip-mutating cases** (length-1 vector vs scalar, `NA_real_`, `NA_character_`,
    whole-number double) with a write-vs-read agreement assertion, per AC13.
  - _Requirements: R2 (incl. R2.5). Invariants: I13. Properties: P1, P2, P3, P5, P6, P12, P15.
    Acceptance: AC13. No pathway impact._
  - **Escalation rationale**: cross-cutting, expensive to reverse, gates the golden vectors.
    Once goldens publish, a change requires a conscious `datom-sv2` bump. The round-trip
    constraint was caught only in review -- without it this task would have shipped goldens for an
    encoder that disagreed with itself.

- [ ] **3. Export and harden storage JSON put/get**
  - `datom_storage_read_json()` / `datom_storage_write_json()` on the Storage Extension API,
    wrapping the existing `.datom_storage_*_json()` internals (`R/utils-storage.R:66,83`).
  - Harden: conn class check, relative-key validation, clear abort on absent key, no direct
    `.datom_s3_*()` reachability (I7).
  - **Refuse datom-managed keys on the write export** (R12.4a): anything under a `.metadata/`
    segment, and payload-shaped keys (`{name}/{sha}.{json,parquet}`) under an existing artifact
    directory. Otherwise a downstream package can overwrite `metadata.json` or a payload
    directly, **bypassing git-gates-storage and integrity** -- a silent-degradation path in a
    brand-new public API. Reads stay unrestricted.
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

- [ ] **7. `datom_member()` + validator + cycle and depth checks**
  - `datom_member(conn, name, version)` mirroring `datom_parent()` (`R/lineage.R`): validate,
    read `{name}/.metadata/{version}.json`, derive `project` from `conn$project_name` and `kind`
    from the snapshot (defaulting to `"table"` for pre-`kind` metadata). Returns
    `{project, name, kind, version}` as pure data.
  - `.datom_validate_members()` mirroring `.datom_validate_parents()`, including the `remedy`
    string pointing at `datom_member()`.
  - Write-time cycle detection + depth limit (proposed 8; confirmed at E1 escalation).
    **Exhaustive within the project, best-effort across projects** -- an unresolvable
    cross-project member is not a cycle failure, it is a `datom_validate()` finding (Task 13).
  - Provide the shared **visited-set + depth walker** here, so Task 9 and Task 13 consume one
    implementation rather than each growing its own (R4.4). Write-time and read-time enforcement
    must agree on the limit.
  - _Requirements: R4 (incl. R4.4). Invariants: I9, I10, I10a. Properties: P16. Acceptance: AC9._

- [ ] **8. `datom_write_set()`**
  - **Two gates first, before any hashing or IO** (R10.3a, I15): the repo must declare
    `mode: product`, and `name` must equal `project.yaml`'s `set:` field. These are what make
    "one repo = one set" real, and the second is the precondition the cycle walk's root depends on.
  - Payload derived from members + tags/descriptions/view config. No `metadata =` parameter --
    user metadata belongs in the payload (R1.4/R6.2).
  - Written **git-canonical + storage-mirrored**: git at `{name}/{data_sha}.json` in the repo tree
    (R6.1a -- the dual-pointer *ordering* is borrowed from `governance.json`, the *layout* is not,
    since that file is a singleton and payloads are N immutable objects), storage at the same
    relative key via the Task 1 helper. **All historical payloads retained in git** (R6.1b, P17).
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
  - Works with **no git clone** (AC1) -- storage-only readers are the primary consumer.
  - **Both kind-mismatch directions abort with a pointer** (R12.3): `datom_read()` on a set ->
    `datom_read_set()` (AC6); `datom_read_set()` on a table -> `datom_read()` (AC14). Without the
    converse, a healthy table gets reported as a missing payload.
  - **Recursive member dispatch carries the visited set + depth limit from Task 7** (R4.4, I10a).
    A stored cross-project cycle is reachable -- write-time checks cannot see it (design.md
    section 5) -- so this must abort, not hang (AC15).
  - _Requirements: R12.3, R7.1, R6.4, R4.4. Invariants: I3, I8, I10a. Properties: P9, P16.
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
  - _Requirements: R10 (incl. R10.3a, R10.5). Invariants: I15._

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
    `{name}/{data_sha}.json` **and** every member resolves.
  - New status code `members_unresolvable`, distinguishable from a missing payload (P14).
  - Member resolution uses the **Task 7 visited-set + depth walker** (R4.4, I10a) -- a validator
    that hangs on a rotten artifact is worse than one that reports it.
  - Set branch compares **git payload vs storage payload**, which R6.1b's git retention makes
    possible; this is a real two-sided check, not a storage self-check.
  - _Requirements: R11, R4.4. Invariants: I10a. Properties: P14, P16, P17._

- [ ] **14. Acceptance-criteria test sweep + E2E** &nbsp; **[soft escalation: coverage review]**
  - Confirm every **AC1-AC9 and AC13-AC21** has a dedicated test; add what the per-chunk tests
    missed. Two are easiest to skip and both need special fixtures: **AC15** (cross-project cycle
    terminates) needs a two-connection fixture, since it cannot be produced through a single
    connection by construction; **AC16** (machine-commit isolation) needs a foreign dirty file
    seeded in the fixture repo, which no other test creates.
  - New `dev/e2e-sets.R` in the style of `dev/e2e-cv1-identity.R`: offline, no PAT, no AWS, real
    bare-git remote + real local store, every claim asserted, non-zero exit on mismatch (AC12).
    Include a `mode: product` repo with foreign `R/`, `dp/`, and `renv.lock` content so the joint
    commit and the machine-commit isolation are exercised end to end, not only in unit tests.
  - Full `devtools::test()` count reported; `R CMD check --as-cran` 0E/0W (AC10, AC11).
  - _Acceptance: AC1-AC21._
  - **Escalation rationale**: nine acceptance criteria plus a new hash regime is a lot of surface
    to claim covered on a default model's word.

- [ ] **15. Docs + Spec Completion Procedure**
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
| 2026-08-09 | **(F1)** Write-time cycle detection is exhaustive *within a project only*. A cross-project cycle is reachable and unpreventable at write time, so read-side visited-set + depth guarding is a **requirement** (R4.4), not defence-in-depth. I10 scoped accordingly. | design.md section 5, I10/I10a |
| 2026-08-09 | **(F2)** `datom-sv1` hashes the **parsed-JSON** data model, not the in-memory R object -- `serialize -> parse -> encode`. Reproduced on the branch: `NA_real_` -> string `"NA"`, doubles -> integers, `NA_character_` -> `null`. A type-tagged encoder over the in-memory object would disagree with itself across the round trip. Elevated from open question to hard constraint. | R2.5, design.md section 7 |
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
