# Tasks -- datom sets (second artifact kind)

**Source issue**: [#89](https://github.com/amashadihossein/datom/issues/89) -- plus **three delta
comments on that issue** that amend it (joint-repo decision; E1 question resolutions; the sv1
payload/encoding restructure). All three are already applied here, so this spec -- not the issue
body alone -- is the current truth.
**Branch**: `spec/datom-sets`, cut from `dev`. **PRs into `dev`, not `main`** -- 0.1.0 is under CRAN
review and `main` is frozen (see `dev/README.md` "Branching During CRAN Submission"). Draft PR
[#97](https://github.com/amashadihossein/datom/pull/97) is open and accumulates the task commits.
**Test baseline**: 2460 at spec start -> **2482 after Task 1**. Report the count in every commit
message; it must never drop.

---

## Where things stand

**Done**: Task 0 (spec) and **Task 1** (stale docstring sweep + relative-key helpers), plus two
things that are not tasks: the prerequisite #89 named
([#95](https://github.com/amashadihossein/datom/issues/95) / PR #96, landed on `dev` *before* this
branch was cut, deliberately outside this history), and `dev/check-spec.R`.

**Next**: **Task 2 -- `datom-sv1`**. It carries the **E1 escalation**, and per rule 5d that
recommendation must be surfaced *before* implementing, not after. The gate is now a **design review
of the encoding specification** -- all five original open questions are settled (design.md 7.5).
**That review is DONE (2026-08-17).** The encoding was found sound -- domain separation, "framing is
free", radix collation, and `id`/`tags` slot separation all verified -- and the four resulting
deltas plus a 19-finding sweep are applied. Task 2 is cleared to implement.
**Goldens freeze the encoding** -- changing anything afterwards is a `datom-sv2` bump, not a spec
edit.

**Open with the owner**: nothing. Two items opened after Task 1 and both closed on 2026-08-17 --
the Task 1 scope deviation (**owner-approved, guard stays**) and the reader-side diff question
(**option 3: no schema change**). Both are in the Decisions log at the bottom of this file, along
with every other decision in this spec.

**Before each commit** (the chunk gate):

```
Rscript -e 'devtools::test()'      # report the count; it must not drop
Rscript dev/check-spec.R           # structural gate on this spec -- see dev/README.md
```

`check-spec.R` catches dangling `R*/I*/P*/AC*` references, orphaned criteria, tasks missing an
`Acceptance:` clause, code citations pointing outside the file, and retired wording surviving as a
live instruction. It is **structural only** -- on the last review round it would have caught about
half the findings. Reasoning defects still need a reader.

**Read before editing `R/`**: `dev/engineering-notes.md`. The two most relevant entries for the
remaining tasks are the **two key shapes** (full vs relative -- mixing them double-prefixes
silently and does not error) and **payload key vs snapshot key** (different directories, both `.json`
for a set).

**One repeating defect pattern, worth knowing before Task 2.** Four review rounds found the same
class: an encoding change swept requirements.md and the acceptance criteria but left the
invariant/property tables in design.md, and Task 2's own bullets, describing the old mechanism. If
you change the encoding, check those three places explicitly, and add the retired phrasing to the
`retired` denylist in `dev/check-spec.R`.

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

- [x] **1. Housekeeping: stale docstrings + relative-key helpers**
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
  - **DONE 2026-08-17.** Filed as [#98](https://github.com/amashadihossein/datom/issues/98).
    Four stale "task 5.1" docstrings reworded (105-108, 205-206, 393, 413) plus **three
    pre-existing phase/chunk comments** the Don'ts forbid, found while sweeping
    (`R/conn.R`, `R/governance_json.R`, `R/utils-gov.R` -- the last was doubly stale, pointing at
    a gov write surface that has since been lifted out). Three relative-key helpers added to
    `R/utils-path.R` and **16 of 17** hand-rolled key sites migrated across 7 files
    (`read_write.R`, `query.R`, `lineage.R`, `validate.R`, `sync.R`, `utils-sha.R`).
    tests: **2482** (+22).
  - **Deliberate exclusion**: `R/sync.R:250` still builds its key with `paste0`. It splices a
    *discovered filename* (already `{sha}.json`) rather than a bare sha, so the helper's sha guard
    does not fit, and adding one would change behavior -- a stray `.json` in `.metadata/` would
    start aborting instead of being uploaded. Commented in place.
  - **SCOPE DEVIATION -- OWNER-APPROVED 2026-08-17, the guard stays.** This chunk was scoped
    behavior-identical,
    and folding `.datom_validate_sha()` into the payload-key helper is **not**: it closed a real gap
    (`.datom_validate_one_table()` spliced `meta$data_sha`, read from a file, into a storage key with
    **no** validation -- #74's guard sweep missed this site, so a corrupt or hostile `metadata.json`
    containing `../../x` could probe outside the namespace on the local backend). One test fixture
    used `data_sha = "d1"`, a value that cannot occur in real data since every sha is 64 hex, and it
    was updated to a realistic digest. Observable behavior for *valid* data is unchanged, and a new
    test pins that a corrupt `data_sha` still surfaces as a `data_missing_s3` finding rather than
    aborting the validation run.
  - _Requirements: R5.2, R13.3. Invariants: I9. **Acceptance: none by design** -- this chunk is
    contract-neutral (docstring wording plus behavior-identical key helpers), so the existing
    suite passing unchanged *is* the assertion. Recorded explicitly so the absence is not read as
    an omission. No pathway impact._

- [ ] **2. `datom-sv1` canonical set-content hash** &nbsp; **[ESCALATION E1 -- design review]**
  - **All five open questions are settled** (owner-decided 2026-08-15, design.md 7.5). The
    escalation is now a **design review of the encoding specification**, not a debate: exact byte
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
    **refusal**, not an `NA` encoding. Note `null` therefore has **no marker** in the encoding (R2.7).
  - **Q3 empty set refused.** `datom_write_set()` with zero members aborts, mirroring
    `.datom_canonical_hash()`'s zero-dim abort (`R/utils-sha.R:310-312`). Update AC5: refusal is
    the tested behavior (R2.8).
  - **Q4 `schema_version` stays out** of the payload and the hash -- container format, not content;
    in identity it would re-mint every set on a format bump (R2.9).
  - **Q5 emitter-free hash.** **No serializer in the identity path.** The construction is the
    hash-of-hashes in the next bullet -- **not** a walk with per-type dispatch, which was the
    superseded formulation (F-A). `jsonlite` may format the **stored** file however it likes,
    because stored-byte integrity is `document_sha`'s separate job. **Identity and storage integrity
    never share a dependency.**
  - **The encoding is a hash-of-hashes over 3 primitives + 2 shape rules** (R2.10, design.md 7.2),
    **not** a runtime type-dispatch walk -- that earlier formulation had a structural gap (F-A) and
    is superseded:

    ```
    str(s)    = h(0x01 || utf8(s))
    strset(v) = h(0x02 || concat(str(e) for e in sort(unique(v), radix)))
    map(m)    = h(0x03 || concat(str(k) || strset(m[k]) for k in sort(keys(m), radix)))
    member(x) = h(0x04 || map(x.id) || map(x.tags))
    set(p)    = h(0x05 || map(p.tags) || concat(sort(unique(member(m) for m in p.members), radix)))
    data_sha  = h(0x06 || utf8("datom-sv1") || set(payload))
    ```

    Member digests sort as **lowercase hex**, `method = "radix"`, emitted as raw bytes.

    Mirrors cv1's per-column-digests-then-hash-the-concatenation pattern, so both references share
    one house construction.
  - **No length prefixes**: every intermediate is a fixed 32 bytes, so concatenation is already
    unambiguous. **`f64le` disappears from sv1 entirely** -- `.datom_encode_numeric()` is not used
    at all, not even for lengths. sv1 shares no numeric primitive with cv1.
  - **Every collection is sorted and deduped -- `members` included, with no carve-out.** An earlier
    draft made member order identity; **retired** (R2.12 carries the three arguments, chiefly that a
    script-generated member list would mint spurious versions on an insertion-order refactor).
    Sorting members means sorting their fixed 32-byte digests. A single string equals a one-element
    set (R2.13).
  - **No Unicode normalization** (R2.16). Radix sort is byte order; NFC and NFD are different tags.
    Golden asserts they differ. Do not add `stringi` -- normalization tables are versioned Unicode
    data, and putting them in the identity path is #72's failure mode with a different vendor.
  - **Pin `strset(character(0)) = h(0x02)`** as a golden (R2.17), for the same reason design.md 7.2 already
    pins the empty map: an encoder whose correctness rests on an upstream validation refusal breaks
    silently the day that refusal is relaxed.
  - **Not this task, but caused by it -- flag it forward.** Order- and shape-insensitivity means
    several spellings share one `data_sha`, which is a write-path correctness problem, not an encoder
    one: R2.15 (canonicalize before the local write) and R7.5 (never re-emit for a known `data_sha`;
    bind `validate(fix = TRUE)` too). Owned by Tasks 8 and 13. Design.md 7.2.3 explains why. Left
    undone, the failure is a **refused read of a valid version**, and every per-chunk test passes.
  - **`id` is encoded with `map`, not positionally**, so a fifth id field later is just another key.
    Validation, not the encoder, enforces "id has exactly these four keys, each single-valued".
  - **The encoder does NOT validate, and this task does not own AC27.** Grammar enforcement lives in
    `.datom_validate_members()` (Task 7, per-member) and `datom_write_set()` (Task 8, payload-level),
    because design.md 7.2 and R2.10 both put the encoder out of validation's job -- and because the
    payload-level cases are invisible from here: the encoder never sees two members at once in a way
    that distinguishes "same `id`, different `tags`" from two ordinary members. An earlier draft had
    Task 2 and Task 7 both claiming AC27; **retired**.
  - Payload shape is **fixed** (R2.12): optional set-level `tags`, then `members[]` each with
    an `id` record `{project, name, kind, version}` and optional per-member `tags`. Depth is bounded by the schema,
    not by what a caller nests.
  - **The R2.5 hard constraint still governs**, with its mechanism restated: write-time and
    read-time hashes must agree, and they now do **by construction** rather than via a
    serialize/parse cycle. Every mutation is **unrepresentable**, not handled (design.md 7.3):
    numbers and booleans are not in the grammar; `NA` aborts; `null` has no marker; and
    scalar-vs-one-element-array is **immaterial because the two hash equal** (R2.13). **Do not write
    an f64 rule and do not write an atomic-vs-list rule** -- both were removed, and an earlier draft
    of this bullet still instructed them. The one supporting condition is structural: read with
    `simplifyVector = FALSE` so `members[]` stays a list of records rather than collapsing to a data
    frame. **Already satisfied** by both backends (`R/utils-local.R:110`, `R/utils-s3.R:209`).
  - `.datom_sv1_str()` / `.datom_sv1_strset()` / `.datom_sv1_map()` +
    `.datom_canonical_set_hash()` in a new `R/hashable-set.R` (or extend `R/utils-sha.R` -- decide
    at the review). **`.datom_encode_numeric()` is NOT used** -- sv1 has no numeric primitive at
    all now that length prefixes are gone, so there is nothing to share with cv1 beyond
    `digest::digest(..., algo = "sha256", serialize = FALSE)`. (Superseded instruction: an earlier
    draft said to reuse it verbatim for `f64le` framing.)
  - `dev/datom_sv1_reference.R`: standalone, `digest`-only, self-testing, prints goldens --
    mirroring `dev/datom_cv1_reference.R`. It is the **normative home of the byte rules and the tag
    table**, written against the encoding spec and **not** against any emitter's output.
  - Extend `.github/workflows/cv1-reference-parity.yaml` (do not add a second workflow) to run the
    sv1 reference and assert package/reference parity on x86_64 **and** arm64.
  - **Goldens are gated on this delta landing** -- post-goldens, any of the above becomes a breaking
    `datom-sv2` bump rather than a spec edit. Hard-coded in tests, cross-architecture asserted, and
    covering the **seven** identity-boundary fixtures of AC13, which is authoritative -- **Equal**:
    (a) tag-value order, (b) tag-value duplication, (c) **member order**, (d) single string vs
    one-element array, (e) member duplication. **Different**: (f) NFC vs NFD. **Pinned constant**:
    (g) `strset(character(0)) == h(0x02)`. Note (c) and (d) each **reverse** an earlier fixture that
    required a difference. Plus the AC27 grammar refusals.
  - _Requirements: R2.1-R2.14, R2.16, R2.17 (**not** R2.15 -- that is Task 8's, per the flag-forward
    bullet above). Invariants: I13, I24. Properties: P1, P2, P3, P4, P5, P6,
    P8, P12, P15, P28, P30, P31, P33. Acceptance: **AC13 (both levels)**, AC3, AC5. **Not AC27** --
    see the encoder-does-not-validate bullet. No pathway impact._

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
  - _Requirements: R12.4, R12.4a. Invariants: I7, I14. Properties: P18. Acceptance: **AC23**
    (the `.access/` refusal, alongside `.metadata/` and payload keys). No pathway impact._

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
  - Write side (**3** sites -- an earlier draft said 2 and missed the third):
    `.datom_update_manifest_entry()` (`R/sync.R:746,751-757`); the **absent-manifest skeleton** at
    `R/sync.R:712` (`list(project_name = ..., tables = list(), summary = list())`); and
    `datom_init_repo()`'s seed (`R/conn.R:522-527`). **The skeleton is the dangerous one**: left
    unrenamed it writes a `tables` key after the rename, and it only fires on a fresh or repaired
    repo, so tests against an existing fixture pass while the bug ships.
  - Read side (6 sites, 4 files): `datom_list()` (`R/query.R:58,85`), `datom_status()`
    (`R/query.R:439`), `.datom_status_input_files()` (`R/query.R:544,550`), `datom_summary()`
    (`R/summary.R:57`), `datom_sync_manifest()` (`R/sync.R:374,387`).
  - Each entry gains `kind` (`"table"` for everything existing). `summary` gains `total_sets`;
    `total_tables` / `total_size_bytes` / `total_versions` keep **current** semantics (tables
    only).
  - `datom_list()` and `datom_summary()` surface `kind`.
  - Manifest and per-artifact metadata now write `schema_version: 2`.
  - **Must land atomically across all nine sites (3 write + 6 read) plus tests.** A partial rename
    presents as "everything looks fine, the list is just empty."
  - _Requirements: R8, R9 (writer side). Invariants: I2, I4. Acceptance: AC4 (cross-kind name
    uniqueness), AC7 (the v2 writer half of the schema gate), AC22. Add a test that `datom_list()`
    and `datom_summary()` surface `kind` and that `total_sets` counts only sets -- the rename's own
    failure mode is silent, so it needs a positive assertion, not just the absence of errors. No new
    pathway (route shapes unchanged) -- record explicitly._
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
    `{id: {project, name, kind, version}, tags: {...}}` as pure data.
  - **Signature gains tags**: `datom_member(conn, name, version, tags = NULL)` -- an optional named
    list of text values, validated against the R2.11 grammar at construction time (R4.6). Tags are
    **per-member** because they replace dpbuild's `dp$input` / `dp$output` / `dp$metadata` nesting,
    which classifies items rather than the collection. A value may be a string **or** a character
    vector, because the whole point of tags over folders is that an item can be in several
    categories at once.
  - `.datom_validate_members()` mirroring `.datom_validate_parents()`, including the `remedy`
    string pointing at `datom_member()`. It owns the **per-member** half of AC27 -- cases (a) non-text
    value, (b) `NA`, (c) `""` tag value. It **cannot** own the payload-level half: it sees one member
    at a time, so "same `id` twice with different `tags`" is invisible from here, and set-level `tags`
    never pass through it at all. Those are Task 8's (AC27 d/e). An earlier draft assigned all of
    AC27 here while Task 2 also claimed it; **retired** -- one half each, stated explicitly.
  - **Refuse self-reference** (R4.5, AC9): a set listing itself as a member. One cheap check. The
    set's own identity is known from `project.yaml` (R10.3a).
  - **Deliberately NOT built: cycle detection, a visited-set guard, or a depth limit** (R4.3/R4.4,
    design.md 5 and 20.11). Members pin immutable versions, so the graph is acyclic **by
    construction** -- a set cannot reference something that contains it, because that thing did not
    exist when its members were chosen (same property as git history). And datom resolves **one
    level** and never traverses, so nothing could loop even if a cycle existed. An earlier draft
    specified all three; they solved a problem that cannot occur. **Do not reintroduce them as
    defensive code** (I10a).
  - _Requirements: R4 (incl. R4.3-R4.5), R2.11, R2.7. Invariants: I9, I10, I10a, I24.
    Acceptance: AC9, **AC27 (a, b, c -- the per-member half)**._

- [ ] **8. `datom_write_set()`**
  - **Two gates first, before any hashing or IO** (R10.3a, I15): the repo must declare
    `mode: product`, and `name` must equal `project.yaml`'s `set:` field. These are what make
    "one repo = one set" real, and the second is the precondition the **self-reference check** (R4.5)
    relies on -- it needs the set's own identity before the write. **Not** a cycle walk: there is
    none, and I10a forbids reintroducing one.
  - **Signature: `datom_write_set(conn, members, tags = NULL, ...)`** (R12.2). The `tags` argument
    is **required structure, not decoration** -- R2.12 puts `tags` at the payload root, R2.6 hashes
    it, and AC2's converse half (a changed description mints a version) cannot be tested without it.
    R1.4 deliberately withholds `metadata =`, so this is the only channel.
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
  - **TIDY, then VALIDATE, then hash** -- in that order (R2.14, R2.15, I26; design.md 21.4 steps
    0a/0b). Tidying first clears the benign spellings so validation only ever sees genuine ambiguity;
    validating first would make the tidy rules unreachable. Six things are tidied **silently and must
    not abort**: tag-value order, tag-value duplication, single-vs-array shape, member order, an
    exact-duplicate member (same `id` *and* `tags`), and `character(0)` dropping its key. Assert on
    the **file bytes** (AC29a), not the return value.
  - **Canonical order: map keys radix; tag values radix + dedupe; single values unboxed; members
    deduped by digest then sorted by `project` || `name` || `version`** (R2.15). Note the file sorts
    by **name, not digest** -- digest order would relocate a member whenever its tags change, so
    `git diff` would report a delete plus an insert instead of one changed field, undoing R6.1a's
    entire purpose. The hash still sorts by digest; two sort keys, each with its own reason.
    Unboxing rather than always-array because `auto_unbox = TRUE` is already the house default.
  - **This task owns the payload-level half of AC27** -- the cases only a whole-payload view can see:
    (d) the same `id` listed twice with **different** `tags` is **refused** (dedup does not catch it,
    since the digest covers tags, so both entries would survive and a consumer would find one member
    in two conflicting folders); (e) zero members; plus set-level `tags` grammar, which never passes
    through `datom_member()`. **And the allow-case (R2.14a)**: the same `project`+`name` at two
    different `version`s must write successfully with both members present -- its own test, because
    `project`+`name` looks like the natural duplicate key and tightening to it would silently break a
    legitimate use (a current table beside a locked baseline).
  - **Never re-emit a payload for a `data_sha` already in history** (R7.5 rule 1, I27, AC29b): reuse
    the stored object and **carry the recorded `document_sha` forward**. Mirror
    `.datom_lookup_history_parquet_sha()` (`R/read_write.R:399-404`, `422-439`) -- it already does
    exactly this for parquet, including the `upload = FALSE` return. **This is the defect that passes
    every per-chunk test**: recomputing `document_sha` from fresh bytes while reusing the stored
    object records a hash of bytes nobody stored, and it surfaces later as a refused read of a valid
    version. Reachable by an ordinary tag-value reorder, not just a dependency upgrade -- see
    design.md 7.2.3.
  - **Reuse unchanged**: change detection (`.datom_has_changes()`), the git-gates-storage ordering
    (`datom_write()` steps 7-10), and dedup. Git push stays the serialization point (I5).
  - Cross-kind name uniqueness refusal (AC4) -- checked against **storage**
    `{name}/.metadata/metadata.json`, not the manifest, which can lag.
  - Manifest entry with `kind = "set"` and `member_count`. **`member_count` is the count AFTER
    tidying** -- the canonical member count, not what the caller passed. Pinned because tidying can
    drop an exact duplicate, so the two can differ; today they rarely do, which is exactly why an
    unstated rule would be settled by accident.
  - _Requirements: R5, R6 (incl. R6.1a/b), R7.5, R2.14, R2.14a, R2.15, R10.3a, R12.2, R8 (set
    entries). Invariants: I2, I5, I6, I11, I15, I25, I26, I27. Properties: P7, P13, P17, P25, P29,
    P32. Acceptance: AC2, AC3, AC4, AC5, AC24, AC29 (a and b),
    **AC27 (d, e, set-level tags, every tidy assertion, and the R2.14a allow-case)**._

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
  - _Requirements: R12.3, R7.1, R7.2, R6.4, R4.3. Invariants: I3, I8, I10. Properties: P9, P16.
    Acceptance: AC1, AC6, AC14, AC15, **AC28**. AC28 is the integrity gate -- both halves: a
    mismatched payload is refused before parsing, **and** a missing/empty `document_sha` is an error
    rather than a skip. The second half is what a naive copy of `.datom_read_parquet()`'s
    `if (!is.null(...) && nzchar(...))` guard gets wrong._
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
  - Scope note: R11.2 specifies a **storage-side** check (payload exists, members resolve). An
    earlier draft here promised a git-vs-storage comparison "which R6.1b's git retention makes
    possible" -- **removed**, because R6.1b reversed per-version payload files in git: git now holds
    one mutable `{name}/set.json`, so only the *current* version is comparable without `git show`.
    Do not add unrequested git-side comparison.
  - **`fix = TRUE` must not break `document_sha`** (R7.5 rule 2, I27, AC29c). Repair re-uploads from
    the clone, so it is a live path to overwriting a stored payload. It must **reuse the recorded
    `document_sha` and never recompute it** for an existing version. Same trap shape as the
    `commit_sha` one (R21.7, I22): a repair path silently undoing a write-path guarantee. AC29c is
    the clause a naive implementation fails while passing everything else.
  - _Requirements: R11, R4.3, R7.5. Invariants: I10, I27. Properties: P14, P16, P32.
    Acceptance: **AC29 (c)** -- named here explicitly because an earlier draft discussed it in this
    task's body while listing it in no acceptance line anywhere, leaving the clause the spec twice
    calls "the one a naive implementation fails while passing everything else" owned by nobody. AC15
    (one-level member checking). **P14 has no AC of its own** -- add one here asserting `ok` for a
    healthy set and *distinguishable* statuses for a missing payload versus an unresolvable member;
    R11.3 calls this in scope rather than deferred, so it must not ship untested._

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
  - Confirm **every AC defined in `requirements.md`** has a dedicated test -- derive the list, do not
    trust a range written here. A hardcoded range has now gone stale **twice**: it once stopped at
    AC26 and omitted AC27, and it then stopped at AC28 and omitted AC29. `dev/check-spec.R` now
    asserts this line names no explicit upper bound, so the defect cannot recur. Then add what the
    per-chunk tests
    missed. Two are easiest to skip and both need special fixtures: **AC15** (nesting resolves one
    level) needs a set-containing-a-set fixture and an assertion that the inner payload is *not*
    read; **AC16** (machine-commit isolation) needs a foreign dirty file seeded in the fixture repo,
    which no other test creates.
  - New `dev/e2e-sets.R` in the style of `dev/e2e-cv1-identity.R`: offline, no PAT, no AWS, real
    bare-git remote + real local store, every claim asserted, non-zero exit on mismatch (AC12).
    Include a `mode: product` repo with foreign `R/`, `dp/`, and `renv.lock` content so the joint
    commit and the machine-commit isolation are exercised end to end, not only in unit tests.
  - Full `devtools::test()` count reported; `R CMD check --as-cran` 0E/0W (AC10, AC11).
  - _Acceptance: every AC defined in `requirements.md` -- derive the list, do not restate a bound._
  - **Escalation rationale**: the full acceptance-criteria set plus a new hash regime is a lot
    of surface to claim covered on a default model's word.

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
| 2026-08-09 | ~~**(F7)** Set payloads live in git at `{name}/{data_sha}.json` and all historical payloads are retained.~~ **SUPERSEDED 2026-08-11 -- see the stable-path entry below.** Git now holds one mutable `{name}/set.json`; only storage is content-addressed, and the retention rule is redundant. What still holds from F7: the `governance.json` *ordering* transfers but its singleton *layout* does not, and P17 survives via `git show <commit>:{name}/set.json`. | R6.1a/b, P17 |
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
| 2026-08-15 | **E1 Q5 -- OWNER-DECIDED: emitter-free structural hash.** Neither `jsonlite` nor a bespoke sv1 emitter is canonical, because **no serializer is in the identity path**. ~~sv1 is a deterministic walk of the parsed payload: radix-sorted keys recursively, fixed per-type leaf encoding with a domain-separation tag per type, `sha256("datom-sv1" \|\| encoded-walk)`.~~ **The walk formulation was SUPERSEDED 2026-08-16 by F-A** -- replaced by the hash-of-hashes construction; the *decision* (no serializer in the identity path) stands unchanged. Stored-file formatting is free, because stored-byte integrity is `document_sha`'s separate job -- **identity and storage integrity never share a dependency**. Goldens and `dev/datom_sv1_reference.R` are written against the walk spec, not any emitter's output. | R2.10, design.md 7.2/7.4 |
| 2026-08-15 | **R2.5's force stands; its mechanism is superseded.** The write/read agreement constraint is unchanged, but it is no longer achieved by normalizing through `serialize -> parse -> encode`. Each mutation is eliminated at source instead: numbers always f64 (kills integer-vs-double), `NA` aborts (kills the `"NA"` string and `null` cases), and scalar-vs-array is decided by an explicit R-type rule. **Verified bonus**: the one supporting condition -- reading with `simplifyVector = FALSE` -- is *already* satisfied deliberately by both backends (`R/utils-local.R:110`, `R/utils-s3.R:209`, the latter documented as "keep lists as lists"). So the decision is supported by existing infrastructure rather than imposing a new read-path requirement. | R2.5, design.md 7.1/7.3 |
| 2026-08-15 | **sv1 does not inherit the `metadata_sha` emitter exposure** (section 16). The earlier "cannot both be right" tension is resolved one-sidedly: sv1 is clean by construction, which *sharpens* rather than softens the case for the separate `metadata_sha` issue, since it becomes the only hash in datom whose value depends on a third-party formatter. Scope of that issue unchanged; priority arguably rises. | design.md 7.4, 16 |
| 2026-08-15 | **E1 downgraded from open-question debate to design review.** Gate for Task 2 is now: exact byte rules, whether the tag table leaves a collision surface, and whether the goldens cover the 7.3 agreement cases. Goldens still freeze the encoding -- a later change needs a conscious `datom-sv2` bump. | design.md E1, Task 2 |
| 2026-08-17 | **Final pre-implementation review (independent, adversarial). 20 findings, all triaged; the 5 blockers are fixed.** Verified the factual ones against the tree first. **Blockers**: (1) Task 2's R2.5 bullet still instructed "numbers always f64" and "scalar-vs-array decided by an explicit R-type rule" -- both removed mechanisms, in the bullet that governs the goldens; (2) Task 2's Q5 bullet still specified the superseded type-dispatch walk *immediately before* the bullet declaring it superseded, so a top-down reader implements the wrong one; (3) **I13 as worded mandated the removed serialize/parse pass and contradicted AC13**; (4) **no public parameter existed for set-level tags**, which R2.12 requires, R2.6 hashes, and AC2's converse half tests -- while R1.4 withholds `metadata =`, so the surface could not express a required payload; (5) **a third manifest write site exists** at `R/sync.R:712` (the absent-manifest skeleton) that the "two write sites / eight total" enumeration missed. | R2.5, R12.2, I13, design.md 9 |
| 2026-08-17 | **(review) `R/sync.R:712` is the dangerous manifest site.** It builds `list(project_name = ..., tables = list(), summary = list())` when `.datom/manifest.json` is absent, so left unrenamed it writes a `tables` key *after* the rename -- and it fires only on a fresh or repaired repo, so per-chunk tests against an existing fixture pass while the bug ships. Counts corrected to **3 write + 6 read = 9 sites**. One sub-claim of the review was **wrong**: `R/conn.R:522` *is* the `tables` line (the review said 520); citation left as-is. | design.md 9, Task 5 |
| 2026-08-17 | **(review) three code citations were wrong when written** (verified `R/` is byte-identical since `b57cdba`, so this is not drift): `R/validate.R:386` -> **391**; the `parquet_sha` verification gate `R/read_write.R:217` -> **227**; `.datom_resolve_version()`'s history read `R/read_write.R:177` -> **187** (with `129` for the current-metadata read). Also `R/utils-git.R:154-159` -> `131-161`, abort at `160`. These matter because design.md section 1 instructs "cite these rather than re-deriving them", so wrong numbers propagate into code comments. | design.md 1 |
| 2026-08-17 | **(review) duplicate members were undefined -- now refused** (R2.14). ~~`set()` concatenates member digests with **no** `sort` and **no** `unique`, so `[m, m]` and `[m]` hash differently: members are the one position where duplication *is* identity.~~ **SUPERSEDED 2026-08-17 by D2** -- `set()` now sorts and dedupes, so `[m, m]` and `[m]` hash **equal** and the encoder was never ambiguous. The refusal survives with a different justification: R2.15 canonicalization would silently drop the second copy, and a set listing the same datom version twice has no meaning, so an abort is the honest outcome. Nothing said whether it was legal, so the goldens would have frozen an accident either way. | R2.14, AC27 |
| 2026-08-17 | **(review) the empty-tag-value refusal had no test, and `""` was undefined** -- both settled in R2.14 and AC27. `character(0)` means "no labels", which R2.7 spells by omitting the key; `""` is a label with no name and is likewise refused. R2.7 only said `""` never represents *absence*, which left the separate question of whether it is a legal *label* to be decided by the encoder by accident. | R2.14, AC27 |
| 2026-08-17 | **(review) the `document_sha` integrity gate had no acceptance criterion** -- the one thing design section 8 calls "building a silent-degradation path on purpose" if got wrong. New **AC28** covers both halves: mismatched bytes refused *before parsing*, and a **missing/empty** `document_sha` an **error rather than a skip**. The second half is what a naive copy of `.datom_read_parquet()`'s `if (!is.null(...) && nzchar(...))` guard gets wrong. Task 9 now claims it. | AC28, I3, P9 |
| 2026-08-17 | **(review) Tasks 5 and 13 had no `Acceptance:` line at all**, and Task 15's sweep stopped at AC26 (omitting AC27). Both fixed; Task 13 also now owns a test for P14, which had no AC despite R11.3 calling it "in scope rather than deferred". Seven properties were orphaned (defined, referenced by no task) -- P25/P29 attached to Task 8, P4/P8/P28/P30/P31 to Task 2. | Tasks 5, 8, 9, 13, 15 |
| 2026-08-17 | **(review) three more stale-mechanism references removed**: Task 8 named "the cycle walk's root" as a precondition (there is no cycle walk, and I10a forbids one); Task 13 promised a git-vs-storage payload comparison justified by "R6.1b's git retention", which R6.1b reversed; and the **pathway route card in design section 17 instructed "or recurse"**, contradicting I10 -- that one becomes shipped user documentation in Task 16. Also fixed: the section 19.3 repo sketch still showed `{data_sha}.json` in the git tree, the exact layout AC24 fails. | Tasks 8, 13, design.md 17, 19.3 |
| 2026-08-17 | **(review) "structural walk" wording survived in R2.2 and three design summary rows**, contradicting R2.10 three paragraphs later. That wording is what seeded F-A, so leaving it in the summaries is how it returns. Restated. Plus cosmetics: P8 asserted independence from `size_bytes`, which R1.4 removed from set metadata (vacuous); the AC count "nine" is now 28; and the one-spelling rule was cross-referenced to R2.10 instead of R2.7. | R2.2, P8, design.md 7 |
| 2026-08-16 | **(F-A, BLOCKER -- verified) the closed grammar could not derive the payload shape.** R2.11 said `value ::= string \| [string, ...] \| object`, but R2.12 required `members: [{...}, ...]` -- an **array of objects**, which had no production; R2.10 reinforced it ("only three types to tag") and the encoder's `0x05` was named *string* array. Confirmed by reading both against each other: two requirements that could not both be true, same class as F4. An implementer would have improvised -- read `0x05` as a generic array, or invent a fourth tag -- and **frozen the choice into the golden vectors**, which is what E1 exists to prevent. | design.md 7.2.1 |
| 2026-08-16 | **(F-B -- verified) tag-value array order was identity, and should not have been.** design.md justified order-as-identity with "member order is a curatorial choice the user sees and controls" -- right for `members[]`, wrong for tag values, which the same rule also caught. Confirmed: R2.12 covered member order and tag *key* order but was **silent on tag value order**, so it fell through to the generic array rule. Since a multi-valued tag models *simultaneous folder membership* (R4.6), which is unordered, `domain: ["safety","efficacy"]` vs reversed would have minted a new **citable version** for a semantically null reorder. Does not weaken Q1: a tag *edit* minting a version is intended, a *reorder* is not an edit. | design.md 7.2.2 |
| 2026-08-16 | **Resolution 1 -- `id` split from `tags` in the payload** (R2.12). The payload holds exactly two kinds of content: a well-specified reference record with fixed single-string keys, and an open tag map. Made structural rather than four fixed fields sitting loose beside a nested map. Tags stay per-member (R4.6 unchanged). | R2.12, R4.1, R4.6 |
| 2026-08-16 | **Naming: `id` -- CONFIRMED (owner, 2026-08-16).** Chosen over `ref` / `pointer` / `datom_id`: `ref` collides conceptually with `ref.json`, which means data *location*; `datom_id` is redundant inside datom's own payload; `pointer` is wordy; and project+name+version genuinely *is* the member's identity. **Now settled -- the key name is hashed, so it is frozen by the goldens exactly like the encoding.** Changing it after Task 2 is a `datom-sv2` bump, not an edit. | R2.12 |
| 2026-08-16 | **Resolution 2 -- the walk is replaced by a hash-of-hashes over 3 primitives + 2 shape rules** (R2.10). `str` / `strset` / `map`, then `member` / `set`. Mirrors cv1's per-column-digests-then-hash-the-concat pattern. **Closes F-A** because there is no generic `value` type left to be incomplete: every position's shape is fixed by where it sits, so the encoder never dispatches on runtime type and cannot have a gap. **Closes F-B** because ~~`members` is the only `concat` without a `sort`~~ **SUPERSEDED 2026-08-17 by D2** -- members are now sorted and deduped too, so the claim is stronger than it was: *every* collection is sorted, with no carve-out at all. Tag keys and values were always sorted, and values deduped, so "is this ordered?" is never a judgment call. | R2.10, P30, P31 |
| 2026-08-16 | **`f64le` disappears from sv1 entirely.** Every intermediate is a fixed 32 bytes, so concatenation is already unambiguous (`h("a")||h("b")` is 64 bytes and cannot collide with `h("ab")` at 32) -- no length prefixes needed. Consequence: `.datom_encode_numeric()` is not used **at all**, not even for lengths, so sv1 shares no numeric primitive with cv1. | design.md 7.2 |
| 2026-08-16 | **`id` is encoded with `map`, not positionally.** A fifth id field later is then just another key -- no positional convention, no absent-versus-empty question -- and one encoder serves both `id` and `tags`. Id values are single strings encoded as one-element strsets; validation separately enforces "exactly these four keys, each single-valued", keeping the encoder out of validation's job. | R2.10 |
| 2026-08-16 | **Resolution 3 -- a single string equals a one-element set** (R2.13). `type: "output"` and `type: ["output"]` hash identically, because every map value passes through `strset`. This **reverses** AC13's surviving fixture, which required them to differ: both spellings mean one label named output, so distinguishing them would mint a citable version over a purely syntactic authoring choice -- the same objection that killed tag-value ordering. Net effect: **every AC13 hazard becomes unrepresentable rather than handled**, so P28's goal is reached completely rather than partially. | R2.13, P28, AC13 |
| 2026-08-16 | **R2.5's residual condition narrows to structure.** With leaves order-, duplication- and shape-insensitive, `simplifyVector = FALSE` matters only so `members[]` stays a list of records instead of collapsing into a data frame -- leaf-level simplification is now immaterial. Both backends already do it deliberately. | R2.5, design.md 7.3 |
| 2026-08-16 | **AC13 fixtures replaced**: (a) tag-value order equal, (b) tag-value duplication equal, ~~(c) member order different~~ **SUPERSEDED 2026-08-17 by D2 -- member order is now equal**, (d) single string vs one-element array equal. The old "length-1 vs bare string must differ" fixture is **inverted**, and the number/boolean fixtures were already inapplicable. | AC13 |
| 2026-08-15 | **The payload is text-only, and that is a closed grammar** (R2.11). Values are UTF-8 strings or arrays of strings; **no numbers, booleans, `null`, or nesting beyond the fixed shape** (R2.12). Rationale: tags replace folder-style organisation and folder labels are text, so numbers and booleans buy nothing datom uses while costing an integer-vs-double rule, a boolean tag, and a wider golden matrix. A numeric tag is written `"500"` and parsed downstream, exactly as a folder name would be. | R2.11, I24, AC27 |
| 2026-08-15 | ~~**Consequence: the walk collapses from five type tags to three** (string / string-array / object)~~ **SUPERSEDED 2026-08-16 by F-A** -- the type-dispatch walk is replaced outright by the hash-of-hashes construction, so there is no type-tag list at all. The *reasons* below still hold (numbers/booleans/null are not in the grammar); only the mechanism changed. (string / string-array / object). Three of R2.5's four agreement hazards become **unrepresentable rather than handled** -- int-vs-double and `NA_real_` because there are no numbers, `null` because absence is omission. Only scalar-vs-length-1-array remains an actual rule. `.datom_encode_numeric()` is no longer reused for payload values; only its `f64le` length framing is shared, for lengths datom computes itself. | design.md 7.2/7.3, Task 2 |
| 2026-08-15 | **Tags are per-member** (R4.6), and `datom_member()` gains `tags = NULL`. What they replace is dpbuild's nested product list (`dp$input$raw_ae()`, `dp$output$derived1`, `dp$metadata$data_def`), whose top-level names classify **items**, not the collection -- confirmed by #89's own rejected alternative, which flattened to `(name, project, version, tag_key, tag_value)`, one row per member per tag. Set-level tags are also allowed, for facts about the collection such as a description. | R4.6, Task 7 |
| 2026-08-15 | **A tag value may be a string OR an array of strings**, and that is the *only* reason arrays exist in the grammar. The motivating limitation of folders is that an item cannot be in two at once, so multi-valued tags (`domain: ["safety", "efficacy"]`) are the point rather than an extension. | R2.11, R4.6 |
| 2026-08-15 | **#89's "view config" is retired; no navigation structure is stored at all** (R4.7, I25). Folder-like hierarchy is a **projection**: prioritise one ordering of tag keys at gov level and you get one structure, prioritise another and you get a different one -- so structure is presentation, not content. This retires the "nested view config does not survive the flattening" argument, since navigation *is* the tags, and it is what makes the text-only grammar sufficient. Bonus property: arbitrarily many folder structures cost nothing because none is stored. | R4.7, I25, P29 |
| 2026-08-15 | Closures stay downstream: dpbuild's inputs are lazy closures, whereas a datom member is a pointer and `datom_read()` is the lazy fetch. Assembling closures is the build package's job -- the layering #89 asked for. No datom change. | design.md s4 |
| 2026-08-15 | **Git-commit-linkage follow-ups asked and confirmed as-is, no change** (R20/R21): (a) lagging `commit_sha` into the git copy on a subsequent write, (b) moving the linkage into governance, (c) recording *all* producing commits rather than the first. Examined; the existing spec answers hold -- (a) leaves the newest version permanently unlinked, (b) makes a git-less-reader convenience depend on gov being attached, (c) turns an immutable history entry into an append target. Logged so they are not re-litigated. | R20, R21 |
| 2026-08-11 | **Process lesson recorded, not patched over.** The nesting machinery entered via review finding F1, which correctly spotted a contradiction between two spec statements and was resolved by *adding* guards rather than by testing whether either statement was true. Both were false. When a review surfaces a contradiction, **check the premises before building something to reconcile them**. | design.md 18 (F1 row), 20.11 |
| 2026-08-11 | **AC1 split** into (a) resolve pointers -- always works, no clone -- and (b) resolve to data -- needs that member's project conn. Conflating them mis-implements a set read as "requires access to everything in it". `datom_validate()`'s member check scoped the same way (R11.2), reusing `members_unresolvable`. | AC1, R11.2, Tasks 9 and 13 |
| 2026-08-17 | **Task 1 scope deviation -- OWNER-APPROVED, the guard stays.** Folding `.datom_validate_sha()` into `.datom_artifact_payload_key()` exceeded the chunk's behavior-identical scope, because it closed a real path-traversal gap at `.datom_validate_one_table()` (`R/validate.R:393`) that #74's sweep missed -- a file-supplied `data_sha` spliced into a storage key unvalidated -- and cost one test fixture using an impossible `data_sha = "d1"`. Kept rather than reverted: the alternative leaves a known gap behind a tracking issue competing with 15 remaining tasks, for a purity cost of one fixture line. Behavior for valid data is unchanged. | Task 1, I9, `R/utils-path.R` |
| 2026-08-17 | **Reader-side version diff needs no schema change -- option 3 chosen.** A git-less reader can already diff two set versions with three small JSON reads: `version_history.json` (which carries `data_sha` per entry today, `R/read_write.R:480-487`) to map version -> `data_sha`, then the two content-addressed payloads. **Rejected: persisting per-member digests in metadata** as a `column_hashes` analogue (see design.md 15 for both rejected options). The decisive points: the payload diff reports **actual values** where digests report only "something changed"; `column_hashes` earns its place solely because the alternative is downloading parquet, which does not transfer to a small text payload (design.md 4, "a member index would be metadata-for-metadata"); and there is **no code to reuse** -- `column_hashes` has no consumer in `R/` and `datom_diff` is unbuilt (#73). Member digests remain **additive and volatile**, so they can be added later without a schema break or identity change if a cross-version change timeline proves to be a real need. **No impact on Task 2**: sv1's encoding is identical under this decision, since it would only have published intermediates the hash-of-hashes already computes. | design.md 4 + 15, R6, Task 9 |
| 2026-08-17 | **E1 design review (Task 2 gate) -- four deltas, all owner-approved before goldens freeze.** The encoding itself reviewed clean: domain separation is sound (distinct marker byte per constructor, so cross-type collisions reduce to sha256 collisions); "framing is free" verified (every entry fixed-width -- `map` entry 64 bytes, `member` 64, `set` 32+32n -- so concatenation parses unambiguously without length prefixes); `sort(method = "radix")` is C-locale byte order as claimed; `id`-vs-`tags` slot swapping cannot collide. The four findings are all **additive**, not a redesign, so no model escalation beyond this review. | design.md 7.2-7.2.3, R2.12-R2.17, R7.5 |
| 2026-08-17 | **(D2) Member order is NO LONGER identity** -- `set()` sorts and dedupes member digests like every other collection. **Owner-raised**: order buys nothing since nothing consumes a set positionally. Three arguments, any one sufficient: it contradicted R4.7 (arrangement is presentation, which is why no hierarchy is stored); it contradicted 7.2.2's own reasoning, which killed tag-value ordering for the identical reason; and decisively, the expected producer is a **script**, so an insertion-order refactor would mint a new product version with byte-identical content -- the #72 failure class. Costs one `sort()` over fixed-width digests. **Bonus: 7.2's only carve-out disappears** -- every collection is sorted and deduped, one rule with no exceptions. Reverses P3 and AC13(c); R2.14's duplicate-member rationale changes (the encoder was never ambiguous, and now R2.15 would drop the copy silently, which is better surfaced as an abort). | R2.12, R2.14, P3, P30, AC13(c), design.md 7.2 + 15 |
| 2026-08-17 | **(D1) The payload is canonicalized BEFORE the local write** (R2.15, I26) -- sort map keys, sort + dedupe tag values, **unbox single values**, sort + dedupe members. **Owner-proposed**, and better than the reviewer's original framing, which only guarded the write path: canonicalizing at the source means one content has exactly one byte spelling in git and in storage, so the ambiguity is removed rather than managed. Unboxing (not always-array) because `auto_unbox = TRUE` is already the house default in datom's metadata writers -- the free direction -- and it keeps the `git diff` of R6.1a readable. **Shape unification was a gap in the reviewer's first draft of this delta**, caught by the owner: sorting alone still leaves `"output"` vs `["output"]` as two spellings. sv1 stays order- and shape-insensitive regardless, since the hash domain is a *parsed file* that may predate this rule or have been hand-edited: canonicalization is belt, insensitivity is braces. | R2.15, I26, AC29a, Task 8 |
| 2026-08-17 | **(D3) One `data_sha`, one byte spelling, enforced over time** (R7.5, I27). Two rules, both required: never re-emit a payload for a `data_sha` already in history (reuse the stored object, **carry the recorded `document_sha` forward** -- the exact `.datom_lookup_history_parquet_sha()` pattern at `R/read_write.R:399-404`), **and** hold `datom_validate(fix = TRUE)` to the same rule, since it re-uploads from the clone and so is a live path to overwriting a stored object with non-matching bytes. Same trap shape as the `commit_sha` one (R21.7/I22): a repair path silently undoing a write-path guarantee. **Sharper for sets than tables**: divergent bytes for one `data_sha` need an `arrow` upgrade for a table but only a tag-value reorder for a set, and only sets keep the payload in git. **Deliberately assigned to Tasks 8 and 13, not 2** -- it is a consequence of Task 2's decisions but not encoder code, and a Task 8 implementer assuming "new bytes mean a new `document_sha`" ships a defect that every per-chunk test passes. | R7.5, I27, P32, AC29, Tasks 8 + 13 |
| 2026-08-17 | **(D4) No Unicode normalization; tag bytes are hashed as given** (R2.16). NFC and NFD are different tags. Rejected NFC-first because **normalization tables are versioned Unicode data**, so a Unicode release could re-mint hashes -- the #72 failure mode with the Unicode Consortium in `arrow`'s role, and sv1 exists to keep everything versioned out of its identity path (7.4). Also avoids adding `stringi` to a lean `Imports`, and stays consistent with cv1, which already treats NFC-vs-NFD as identity-relevant (`dev/e2e-cv1-identity.R`). Stated normatively because it would otherwise be settled by accident, and a non-R implementation might normalize by default. Golden asserts they differ. | R2.16, P33, AC13(f) |
| 2026-08-17 | **(D5) `strset(character(0)) = h(0x02)` is pinned** (R2.17). Validation refuses empty tag values and R2.15 cannot produce one, but the encoder must not depend on that -- the argument design.md 7.2 already makes for the empty map: an encoder whose correctness rests on an upstream refusal breaks silently the day the refusal is relaxed. Carried as a golden. | R2.17, AC13(g) |
| 2026-08-17 | **(D6) AC13 grows from four fixtures to seven**, and AC29 is new. Equal: tag-value order, tag-value duplication, **member order**, single-vs-one-element-array, **member duplication**. Different: **NFC vs NFD**. Constant: **empty strset**. Two fixtures now **reverse** earlier "must differ" versions -- member order (D2) and single-vs-array (the 2026-08-16 delta). AC29 covers canonicalization on the file bytes, no-re-upload on a known `data_sha`, and the `validate(fix = TRUE)` clause that a naive implementation fails while passing the other two. | AC13, AC29 |
| 2026-08-17 | ~~**Process: D2's sweep hit the four places tasks.md warns about**, confirming the documented defect pattern rather than discovering a new one.~~ **CORRECTED same day -- it was six sites, not four, and the first sweep missed two of them.** Independent review found three (Task 2's goldens bullet, plus two log rows in present tense); tightening `check-spec.R` then found a sixth. Worse, **two were live instructions, not log rows**: Task 2's fixture list still said "member order different" *in the task that freezes the goldens*, and `requirements.md` R2.10 still carried "`members` is the only `concat` without a `sort`". An implementer working top-down from either would have frozen the wrong fixture, and undoing that is a `datom-sv2` bump. | R2.10, R2.12, AC13, Task 2 |
| 2026-08-17 | **`check-spec.R`'s retired-wording check was close to vacuous, and this is the round that proved it.** It passed on all six D2 sites. Cause: `MARKER_RE` -- the suppression list -- carried generic negation and impossibility cues ("never", "cannot", "not needed", "not required", "acyclic", "impossible", "unrepresentable", "immaterial", "dissolve", "collapse") on the reasoning that the commonest legitimate mention is a sentence saying the thing is NOT done. That reasoning fails at scale: those are ordinary vocabulary in this spec, so nearly every +/- 2 line window contained one. **The clearest case is self-suppression** -- "`members` is the only `concat` without a `sort` ... is never a judgment call" was excused by the word `never` in its own sentence. Fixed by narrowing to explicit supersession and explicit prohibition only; the tightened check immediately found the sixth site unaided. Tradeoff stated in the script: a false positive costs one marker word, a false negative ships a retired instruction that reads authoritative. | dev/check-spec.R |
| 2026-08-17 | **Denylist additions from D2**: "only unsorted concat", "only `concat` without a `sort`", "order is curatorial", "duplication \*is\* identity", "member order different", "member order.{0,20}differ". The last two are the phrasings that actually survived the first sweep, so they are the ones with demonstrated escape history. | dev/check-spec.R |
| 2026-08-17 | **A recurring trap shape, now named after its second instance: a repair path silently undoing a write-path guarantee.** `datom_validate(fix = TRUE)` re-uploads from the clone, so it is a general-purpose way to overwrite storage with derived content. Instance 1 was `commit_sha`, which repair would have **stripped** (R21.7, I22, AC25's third clause); instance 2 is `document_sha`, which repair would **invalidate** by re-emitting bytes for an existing `data_sha` (R7.5 rule 2, I27, AC29c). Both were caught only because someone asked "what does `fix = TRUE` do to this field?" **Any future spec adding a metadata field should answer that question explicitly**, and the acceptance criterion belongs on the repair path, not only the write path -- in both instances the repair clause is the one a naive implementation fails while passing everything else. | R7.5, R21.7, I22, I27, AC25, AC29 |
| 2026-08-17 | **Thorough post-delta review: 19 findings, all fixed.** Prompted by two prior sweeps each missing defects. **The decisive one was self-inflicted**: the sv1 pseudocode exists in all three spec files, the D2 fix touched only `design.md`, and `requirements.md` + `tasks.md` were left stating `concat( member(m) ... )` with no sort -- the second of those inside the task that freezes the goldens, eleven lines above prose saying the opposite. Every multi-member golden would have been wrong. Seven blockers total; the rest were ownership gaps and stale counts. | R2.10, design.md 7.2, Task 2 |
| 2026-08-17 | **TIDY FIRST, THEN VALIDATE -- owner-decided, and it reverses the reviewer's recommendation.** The reviewer proposed validate-then-canonicalize to keep the R2.14 refusals reachable. The owner's principle is better: *handle any trivial error without pestering the user; refuse only what is deliberate or unhandleable*. Six spellings are now **tidied silently** because nobody can reasonably care about them -- tag-value order, tag-value duplication, single-vs-array shape, member order, an exact-duplicate member, and `character(0)` dropping its key. Five are **refused** because each would require guessing intent -- non-text values, `NA`, `""` as a tag value, same-`id`-different-`tags`, and zero members. Tidy-first also composes better than validate-first: it clears the benign cases so validation only ever sees genuine ambiguity. | R2.14, R2.15, AC27, design.md 21.4 |
| 2026-08-17 | **Working through "which duplicates are benign" exposed a case both sweeps missed: same `id`, DIFFERENT `tags`.** `set()` dedupes by `member()` digest and the digest covers tags, so these have *different* digests and **dedup does not catch them** -- both entries survive, and a consumer projecting tags finds one member in two conflicting folders. That is one fact with two spellings; the intended form is a single entry with a multi-valued tag. **Refused**, because both ways to tidy it guess: merging tags is right if the caller meant both categories and nonsense if two code paths disagreed, and picking one entry is arbitrary. | R2.14, AC27(d) |
| 2026-08-17 | **Same NAME at different VERSIONS is legal and is NOT a duplicate (R2.14a) -- owner-raised.** `adsl@a1b2` and `adsl@f9e8` are different members with different content; a product carrying a current table beside a locked baseline is atypical but entirely sensible. **The duplicate check keys on the FULL `id`, never on `project`+`name`.** Given its own test precisely because `project`+`name` looks like the natural key, so the first reader to "tighten" it would silently break a legitimate use. Three consequences recorded: the R2.15 file sort key **must** include `version` (or two versions of one name have no defined relative order and canonical form is undefined); consumers disambiguate by tag, datom adds no warning since one firing on legitimate use is noise; and a future reader-side diff cannot key on `project/name` alone -- it should key on `project/name` where unique and fall back to including `version` where not. **The diff demo shown in this conversation had exactly that bug.** | R2.14a, R2.15, AC27 |
| 2026-08-17 | **(L2) The file's member sort key differs from the hash's, deliberately -- owner-approved.** Hash sorts `member()` digests (self-contained: the encoder never needs to know what an `id` looks like, which is what keeps "a fifth id field is just another key" true). The **file** sorts by `project` \|\| `name` \|\| `version`, because digest order would relocate a member whenever its tags change -- so `git diff` would report a delete plus an insert in a different place, with everything between shifting, instead of one changed field. That undoes R6.1a's entire purpose, which is D1's own justification. Both keys are fully deterministic, so "one content, one byte spelling" holds either way. Cheap now, and **expensive later**: once payloads ship, changing canonical file order is a canonical-form change that I27 forbids. | R2.15, R6.1a, P25, AC24 |
| 2026-08-17 | **AC27 ownership split; AC29c given an owner.** AC27 was claimed by **both** Task 2 and Task 7 while `design.md` 7.2 says the encoder stays out of validation's job -- and neither owner could enforce two of its clauses: `datom_member()` sees one member at a time so cannot detect a duplicate, and set-level `tags` never pass through it. Resolved: per-member grammar (non-text, `NA`, `""`) to Task 7; payload-level cases (same-`id`-different-`tags`, zero members, set-level tag grammar, every tidy assertion, and the R2.14a allow-case) to Task 8; **Task 2 owns none of it**. Separately, **AC29c had no acceptance line anywhere** -- discussed in Task 13's body, listed nowhere, outside Task 15's sweep range. The clause the spec twice calls "the one a naive implementation fails while passing everything else" was owned by nobody; now Task 13's. | AC27, AC29, Tasks 2/7/8/13 |
| 2026-08-17 | **AC13 split into payload-level and encoder-level, because its umbrella was unsatisfiable.** The umbrella asserted write/read `data_sha` agreement for every fixture, but (g) `strset(character(0))` is a primitive constant with no payload and no `data_sha`, and (e) member-duplication cannot be built through the public path since R2.14 tidies it. **AC13-P** keeps the umbrella (a, b, c, d, f); **AC13-E** calls the encoder directly (e, g). Also pinned: (f) NFC/NFD fixtures **must use `\u` escapes**, since they ship in `tests/` and AC11 holds `R CMD check --as-cran` at zero warnings. | AC13, AC11 |
| 2026-08-17 | **`check-spec.R` gains a root-cause check, and it is verified non-vacuous.** The two classes that survived three sweeps were both **duplicated content**, which no prose denylist can reach: the encoder pseudocode is written out in all three files, and the AC count/range was hardcoded in four places and went stale twice (stopped at AC26 omitting AC27; then at AC28 omitting AC29). New check 6 compares the six encoder rules across files after whitespace normalization, and forbids any explicit AC upper bound. **Tested by reintroducing the exact `set(p)` defect that survived three sweeps** -- the check fails, names `set(p)`, and prints the odd file out. Recorded because the previous round's lesson was shipping a check nobody proved worked. | dev/check-spec.R |
| 2026-08-17 | **Lesser fixes in the same pass**: `design.md` 21.4's write-order table -- the only end-to-end set write order -- had **no canonicalization step and no validation step**, and uploaded the payload unconditionally in contradiction of R7.5/I27/AC29b; now carries steps 0a/0b and a conditional step 6. Member-digest sort collation pinned to lowercase hex + radix (`strset`/`map` spelled it; the member sort did not). R7.5 rule 2 now forbids **re-uploading the bytes** as well as recomputing the hash -- forbidding only the recompute still permitted the worst outcome. `member_count` pinned as the **post-tidy** count. Task 2's `Requirements:` line no longer claims R2.15. Three stale "the E1 review is still pending" blocks updated (`tasks.md`, `design.md` 12, `dev/README.md`). Call-site count corrected 8 -> 9 at `design.md` 12. R2.14/R2.13 numbering left out of reading order deliberately -- the numbers record decision order, and renumbering would churn every reference. | R2.15, R7.5, R8, design.md 12 + 21.4 |
| 2026-08-17 | **(review hardening 1) R2.15 step 4's sort tie is unreachable, and that is now stated.** Two members can share `project` \|\| `name` \|\| `version` in exactly one situation -- the **same `id` with different `tags`**, which survives dedup because the `member()` digest covers tags. Because tidy runs before validation, the sort can meet that tie and R's stable radix sort resolves it to caller input order; harmless, since R2.14 refuses that payload one step later so no tie reaches a written payload. Recorded because an implementer reaching step 4 will ask what to do about ties and might add a **dead-code tiebreaker** or escalate. Explicitly **not** fixed by hoisting the refusal before tidy: the phase separation is worth more than removing an unreachable edge, and inverting it would make the tidy rules unreachable instead. Also noted that the key omits `kind` safely -- AC4 refuses cross-kind name collisions, so `kind` could never break a tie the rest of the key did not already decide. | R2.15, R2.14, AC4 |
| 2026-08-17 | **(review hardening 2) `check-spec.R` check 6 detected disagreement but not ABSENCE -- fixed, and the reviewer found one hole while there were two.** Comparing present copies is insufficient: delete a rule from one file and the survivors still agree. **Demonstrated before fixing** -- deleting `str(s)` from `requirements.md` gave `ok  duplicated content agrees -- 6 encoder rules consistent`, exit 0, the count still reading 6 because the key survived via the other two files. The second hole, unreported: with a rule deleted from **all three** files the key vanished from the loop's index and was **not checked at all**. Both closed by iterating `CODE_KEYS` rather than observed keys and asserting presence in every spec file. Matters most for `requirements.md`, where R2.10 *defines* the encoding -- if the formula vanishes there the requirement stops stating what it requires, and the next editor updates the two files that still carry it without learning a third did. Verified non-vacuously in both directions: one-file deletion and all-file deletion each FAIL naming the missing file(s), and restore returns to pass. | dev/check-spec.R |
