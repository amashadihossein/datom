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
  - Fix the stale `parquet_sha` claim at `R/read_write.R:95-97`, plus the same claim in
    `.datom_read_parquet()`'s `@param parquet_sha` and the comment in
    `.datom_resolve_parquet_sha()` (R13.3). History **has** persisted `parquet_sha` since #72;
    only legacy entries lack it.
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
  - **Settle the four open questions in design.md section 7 before writing the encoder**:
    whole-payload vs member-list-only hashing; `NA_character_` vs `""` vs `null`; empty-set
    legality (AC5); whether `schema_version` enters the payload.
  - `.datom_sv1_value()` + `.datom_canonical_set_hash()` in a new `R/hashable-set.R` (or extend
    `R/utils-sha.R` -- decide at escalation). Reuse `.datom_encode_numeric()` verbatim; do not
    write a second numeric encoder.
  - `dev/datom_sv1_reference.R`: standalone, `digest`-only, self-testing, prints goldens --
    mirroring `dev/datom_cv1_reference.R`.
  - Extend `.github/workflows/cv1-reference-parity.yaml` (do not add a second workflow) to run
    the sv1 reference and assert package/reference parity on x86_64 **and** arm64.
  - Golden vectors hard-coded in tests, cross-architecture asserted.
  - _Requirements: R2. Properties: P1, P2, P3, P5, P6, P12. No pathway impact._
  - **Escalation rationale**: cross-cutting, expensive to reverse, gates the golden vectors.
    Once goldens publish, a change requires a conscious `datom-sv2` bump.

- [ ] **3. Export and harden storage JSON put/get**
  - `datom_storage_read_json()` / `datom_storage_write_json()` on the Storage Extension API,
    wrapping the existing `.datom_storage_*_json()` internals (`R/utils-storage.R:66,83`).
  - Harden: conn class check, relative-key validation, clear abort on absent key, no direct
    `.datom_s3_*()` reachability (I7).
  - `_pkgdown.yml` reference entries; roxygen with runnable offline examples in the established
    bare-git-remote + local-store style.
  - _Requirements: R12.4. Invariants: I7. No pathway impact._

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
    Cross-project resolution is best-effort -- an unresolvable cross-project member is not a
    cycle failure, it is a `datom_validate()` finding (Task 11).
  - _Requirements: R4. Invariants: I9, I10. Acceptance: AC9._

- [ ] **8. `datom_write_set()`**
  - Payload derived from members + tags/descriptions/view config. Written **git-canonical +
    storage-mirrored** per the `governance.json` dual-pointer pattern (`R/governance_json.R`), at
    `{name}/{data_sha}.json` via the Task 1 key helper.
  - **Reuse unchanged**: change detection (`.datom_has_changes()`), the git-gates-storage ordering
    (`datom_write()` steps 7-10), and dedup. Git push stays the serialization point (I5).
  - Cross-kind name uniqueness refusal (AC4).
  - Manifest entry with `kind = "set"` and `member_count`.
  - _Requirements: R5, R6, R12.2, R8 (set entries). Invariants: I2, I5, I6, I11. Properties: P7,
    P13. Acceptance: AC2, AC3, AC4, AC5._

- [ ] **9. `datom_read_set()` + `datom_read()` refusal**
  - `datom_read_set()`: resolve version -> read payload -> **verify `document_sha` before
    parsing** -> return members + payload. A missing `document_sha` is an **error, not a skip**
    (design.md section 8) -- sets have no legacy population, so reproducing the `parquet_sha`
    grace would build a silent-degradation path on purpose.
  - Works with **no git clone** (AC1) -- storage-only readers are the primary consumer.
  - `datom_read()` on a set aborts pointing at `datom_read_set()` (AC6), not a cryptic
    missing-parquet error.
  - _Requirements: R12.3, R7.1, R6.4. Invariants: I3, I8. Properties: P9. Acceptance: AC1, AC6._
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
  - _Requirements: R10._

- [ ] **11. `datom_validate()` branches on `kind`**
  - `.datom_validate_one_table()` at `R/validate.R:386` currently hardcodes
    `paste0(name, "/", meta$data_sha, ".parquet")`, which fails 100% of the time on a set.
  - **table**: existing parquet check, unchanged. **set**: payload exists at
    `{name}/{data_sha}.json` **and** every member resolves.
  - New status code `members_unresolvable`, distinguishable from a missing payload (P14).
  - _Requirements: R11. Properties: P14._

- [ ] **12. Acceptance-criteria test sweep + E2E** &nbsp; **[soft escalation: coverage review]**
  - Confirm every AC1-AC9 has a dedicated test; add what the per-chunk tests missed.
  - New `dev/e2e-sets.R` in the style of `dev/e2e-cv1-identity.R`: offline, no PAT, no AWS, real
    bare-git remote + real local store, every claim asserted, non-zero exit on mismatch (AC12).
  - Full `devtools::test()` count reported; `R CMD check --as-cran` 0E/0W (AC10, AC11).
  - _Acceptance: AC1-AC12._
  - **Escalation rationale**: nine acceptance criteria plus a new hash regime is a lot of surface
    to claim covered on a default model's word.

- [ ] **13. Docs + Spec Completion Procedure**
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
| `datom_write_set()` | 8 |
| `datom_read_set()` | 9 |

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
