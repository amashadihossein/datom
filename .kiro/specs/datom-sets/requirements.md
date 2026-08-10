# Requirements -- datom sets (second artifact kind)

**Source issue**: [#89 -- Add a second artifact kind: versioned, citable sets of datoms](https://github.com/amashadihossein/datom/issues/89)
**Branch**: `spec/datom-sets` (cut from `dev`; PRs into `dev` per the CRAN submission freeze -- see `dev/README.md` "Branching During CRAN Submission")
**Prerequisite**: #95 / PR #96 -- corrected the stale pre-release paragraph in
`.github/copilot-instructions.md`. Landed on `dev` before this branch was cut, deliberately
outside this spec's history. Without it the instructions file contradicts this spec's
compatibility reasoning.

---

## 1. Goal

Give datom a **second artifact kind** alongside tables: a **set** -- a versioned, citable,
content-addressed collection of pointers to existing datoms. Same repo, same version history,
same content addressing, same governance and ref resolution as a table. Different payload: a
JSON document of pointers instead of a parquet file.

datom today versions individual tables and has no way to version a *curated collection* of
tables as a single citable thing.

## 2. Motivation

A curated collection is what a data product is. The downstream build package (new; replaces the
`pins`-based `dpbuild`) needs to publish one: a document of pointers to existing datoms, plus
tags and navigation metadata, versioned and immutable so a consumer can pin it, and addressable
so another collection can include it.

Three things block that today:

1. **A collection is a tree, not a flat table**, so it cannot be a datom table. `datom-cv1`
   refuses list and exotic columns by design (`R/hashable.R`, `.datom_canonical_hash()`).
2. **No byte/JSON put-get on the public storage surface.** The Storage Extension API exports
   `datom_storage_list()` / `datom_storage_copy()` / `datom_storage_verify()` /
   `datom_storage_delete_prefix()` (`R/storage.R`) but no JSON read/write, so a downstream
   package cannot write its own document into datom's namespace. The internals already exist
   (`.datom_storage_read_json()` / `.datom_storage_write_json()`, `R/utils-storage.R:66,83`) --
   they are simply unexported.
3. **Building it outside datom duplicates** version history, content addressing, dedup, ref
   resolution, and governance in a second package.

### The load-bearing justification is composability, not code reuse

Duplicated machinery could be answered with "copy 200 lines into the build package." What
cannot be answered that way: **a product built outside datom is a dead end.** It can never be a
member of another product, because membership requires living in the addressing scheme.

### Who benefits

| Beneficiary | Need |
|---|---|
| The build package | Publish versioned, immutable, citable products |
| Storage-only consumers | Resolve a pinned product without git access |
| Any team composing one product from another | Reference a product as a member of another product |

## 3. Compatibility posture

datom is `lifecycle: experimental`, 0.1.0 is under CRAN review, and there are no reverse
dependencies. The distinction that governs a change is **failure mode, not compatibility**:

| Change | Verdict at experimental |
|---|---|
| Breaks loudly -- user upgrades, gets an error, fixes code | Fine |
| Silently disables an integrity check | **Not acceptable at any stage** |

This is the operative rule in `.github/copilot-instructions.md` (as corrected by #95). It is
what makes the `tables` -> `artifacts` rename acceptable while `parquet_sha` -> some
kind-neutral name is not. See design.md section "Compatibility analysis" for the full
derivation.

---

## 4. Functional requirements

Additive unless marked **[BREAKING]**.

### R1 -- Set artifact kind

- **R1.1** Metadata carries `kind: "table" | "set"`. `kind` is **semantic** -- it participates
  in `metadata_sha`.
- **R1.2** `kind` is a new field, **not** a new `table_type` value. `table_type`
  (`imported` / `derived`) is a *provenance* axis, not a *kind* axis, and is validated to
  exactly those two values (`.datom_build_metadata()`, `R/read_write.R`).
- **R1.3** A set's `metadata.json` collapses to **exactly these seven fields**: `kind`,
  `schema_version`, `data_sha`, `hash_algo`, `document_sha`, `created_at`, `datom_version`. No
  `parents`, no `source_lineage`, no `table_type`, no `nrow` / `ncol` / `colnames` --
  **omitted, not nulled** (mirroring how `.datom_build_metadata()` already conditionally assigns
  `original_file_sha`).
- **R1.4** Also **absent from a set's metadata**, and the reason for each:
  - `size_bytes` -- nothing consumes it. `summary$total_size_bytes` is tables-only by R8.3, and
    the manifest set entry carries `member_count` instead. A field no counter reads is a field
    that will silently rot.
  - `custom` -- redundant by design. Tags, descriptions, and view config live **in the payload**
    (R6.2), so a second user-metadata channel on a set would create two places to put the same
    thing and two places to look for it. `datom_write_set()` therefore has no `metadata =`
    parameter.

**Acceptance**: a written set's metadata has exactly the seven keys of R1.3 -- asserted with
`setequal(names(meta), <the seven>)`, not merely by checking absences, so an added field fails
the test.

### R2 -- Canonical set-content hash (`datom-sv1`)

- **R2.1** `data_sha` for a set is a canonical hash over the set's **semantic content**, not
  over emitted bytes. Carries the #72 lesson forward: a JSON/YAML emitter drifts across
  versions (key order, quoting, wrapping) the way `arrow` drifted for parquet.
- **R2.2** The basis is **not** `datom-cv1`. cv1 is table-shaped and binary-framed
  (`sha256("datom-cv1" || f64le(nrow) || f64le(ncol) || concat(col_digests))`); `nrow` / `ncol`
  / per-column digests do not generalize to a tree. The basis is the JSON canonicalization
  already used by `.datom_compute_metadata_sha()` (radix-sorted keys,
  `toJSON(auto_unbox = TRUE)`, sha256), **extended for nesting**.
- **R2.3** Declared under its own `hash_algo` identifier: `datom-sv1`. `hash_algo` already
  exists and is correctly in the semantic set (`R/utils-sha.R`: "a new hash algorithm
  legitimately defines a new version").
- **R2.4** Ships with a standalone reference implementation, golden vectors, and a
  cross-architecture parity workflow mirroring `dev/datom_cv1_reference.R` and
  `.github/workflows/cv1-reference-parity.yaml`.
- **R2.5 -- round-trip agreement (hard constraint).** The hash **domain is the parsed-JSON data
  model, not the in-memory R object.** `data_sha` computed at write time from an in-memory
  payload MUST equal `data_sha` recomputed at verify time from the same payload after it has been
  serialized to JSON and parsed back. R cannot distinguish a scalar from a length-1 vector, and
  the round trip mutates types (demonstrated in design.md section 7: `NA_real_` becomes the
  **string** `"NA"`; doubles return as integers; `NA_character_` becomes `null`). Any encoder that
  type-tags the in-memory object without normalizing through the round trip violates R2.1 and
  P1/P2. The encoder therefore normalizes by construction -- serialize, parse, then encode.

**Acceptance**: AC13 below, plus the standalone reference and the in-package implementation
produce identical `data_sha` for every golden fixture, on both x86_64 and arm64.

### R3 -- Members are references, not parents

- **R3.1** A set carries **no** `parents` and **no** `source_lineage`. The member list lives
  only in the payload.
- **R3.2** This is not a special case -- it falls out. `datom_write()` already derives
  `source_lineage` as the union of parents' lineages (`R/read_write.R`, the
  `datom_lineage_union()` call), so null-parents automatically means no inheritance.
- **R3.3** **Access is per-member, enforced where it already is.** A set contains no data, so
  conjunctive (AND) access across members would be wrong -- it would make a 50-table product
  unreadable to anyone lacking one table. If you can read `AE` but not `CM`, you pull the set
  and work with `AE`. `datom_read()` on the member is the only gate and needs no change.
- **R3.4** **Lineage flows through tables only.** If product B derives a table from product A's
  `adsl`, B's table names A's `adsl` as parent. The set is how you *found* the table, not how
  data *reached* it.
- **R3.5** "Which raw sources fed product X at version V" is a **read-time union** over the
  members' `source_lineage` -- one metadata read per member, composed from the existing
  `datom_get_lineage(depth = "source")` + `datom_lineage_union()`. Not a stored field, so it
  cannot go stale. For a 50-member product that is 50 reads, acceptable because it is a **cold
  path**: access is enforced per-member at `datom_read()`, so the union is needed only for
  audit and reporting, never per-access.

**Acceptance**: AC8 below.

### R4 -- Member schema and constructor

- **R4.1** Each member entry carries at minimum `{ project, name, kind, version }`.
  - `project` -- otherwise cross-project membership cannot resolve, and cross-project is the
    point.
  - `kind` -- because a set may contain a set; without it a resolver cannot know whether to
    call `datom_read()` or `datom_read_set()`.
- **R4.2** Members are built with **`datom_member(conn, name, version)`**, mirroring
  `datom_parent()` (`R/lineage.R`). Callers must not hand-assemble member lists:
  `datom_parent()` is the established pattern for constructing a validated reference record,
  and symmetry keeps validation at construction time rather than deep inside
  `datom_write_set()`.
- **R4.3** Set-in-set nesting is bounded by two rules enforced **at write time**: a **depth
  limit** and **cycle detection**. Write-time enforcement is **exhaustive within a project** and
  **best-effort across projects** -- the walk can only follow members reachable through the
  connection the caller supplies.
- **R4.4 -- read-side guard (mandatory, not defence-in-depth).** Because R4.3 is only
  best-effort across projects, a **stored cross-project cycle is reachable**: project A's set
  gains B's set, then B's set gains A's -- neither write can observe the other. Therefore **every
  recursive member resolver carries a visited set and the same depth limit**, and aborts on
  revisit or overrun. This applies to `datom_read_set()` member dispatch and to
  `datom_validate()` member resolution. Without this a cross-project cycle is an infinite loop,
  not an error.

**Acceptance**: AC9 (write-time, same project) and AC15 (read-time, cross-project) below; plus a
hand-assembled member list is refused with a message pointing at `datom_member()` (mirroring the
`remedy` pattern in `.datom_validate_parents()`).

### R5 -- Storage layout

Relative to the artifact prefix:

```
{name}/{data_sha}.json                  <- set payload            (NEW)
{name}/.metadata/metadata.json          <- current state          (same as tables)
{name}/.metadata/version_history.json   <- history                (same as tables)
{name}/.metadata/{metadata_sha}.json    <- versioned snapshot     (same as tables)
```

- **R5.1** Two distinct `.json` addresses exist and must not be confused: the **payload** at
  `{name}/{data_sha}.json` and the **versioned metadata snapshot** at
  `{name}/.metadata/{metadata_sha}.json`. Different directories, no key collision.
- **R5.2** Keys are built through a helper, not hand-rolled `paste0` at call sites. See
  design.md "Deviation D1" for the precise form -- the issue's instruction to use
  `.datom_build_storage_key()` needs a correction, because that function returns a *full* key
  (prefix + `datom/` + segments) while `.datom_storage_*()` dispatch takes *relative* keys.
- **R5.3** Tables keep `{name}/{data_sha}.parquet`. This is *why* an unupgraded reader meeting
  a set fails loudly -- it fetches a `.parquet` object that does not exist.

### R6 -- Payload is git-canonical with a storage mirror

- **R6.1** The payload follows the **`governance.json` dual-pointer pattern**
  (`R/governance_json.R`), not the parquet pattern: git is canonical, the storage mirror is
  written in the same step and always derived from git.
- **R6.1a -- git-side layout (the pattern diverges here).** `governance.json` is a **singleton
  current-state** file at `.datom/governance.json`; a set has **N immutable, content-addressed
  payloads**. So the dual-pointer *ordering* is borrowed but the *layout* is not. Set payloads
  live in the repo tree at **`{name}/{data_sha}.json`** -- the same relative path as the storage
  key, so the two are trivially comparable -- alongside the existing `{name}/metadata.json` and
  `{name}/version_history.json`.
- **R6.1b -- all historical payloads are retained in git.** They are small, immutable, and
  content-addressed, so retention costs little and buys the thing "git-canonical" is supposed to
  mean: **any version of any set is fully reconstructible from the git clone alone**, with no
  storage access. A payload is never rewritten or deleted; a new version adds a new object. This
  is what makes `datom_validate()`'s set branch (R11.2) a real git-vs-storage comparison rather
  than a storage self-check.
- **R6.2** Tags, descriptions, and view config live **in the payload**, not in a parallel
  metadata schema.
- **R6.3** **No member index.** `column_hashes` exists so you can diff a table without
  downloading parquet; the payload is small and cheap to read, so a member index would be
  metadata-for-metadata.
- **R6.4** "git-canonical" must **not** be read as "requires a clone". See AC1.

### R7 -- `document_sha` for stored-document integrity

- **R7.1** Sets carry `document_sha`: the SHA-256 of the stored payload bytes, verified on read
  at the **same gate position** as `parquet_sha` -- *before* parsing.
- **R7.2** `document_sha` is persisted in `version_history.json` entries **from day one**, using
  the existing conditional-add pattern in `.datom_write_metadata_local()`
  (`R/read_write.R`, the `if (!is.null(metadata$parquet_sha))` block).
- **R7.3** `parquet_sha` is **not** renamed to a kind-neutral name. It is the correct name for a
  parquet object's byte hash. Rationale: design.md "Compatibility analysis".
- **R7.4** `document_sha` goes in the `volatile` exclusion list of
  `.datom_compute_metadata_sha()` (`R/utils-sha.R:412`), for the same reason `parquet_sha` is
  there -- it is a stored-object byte fact, not content identity.

### R8 -- One typed namespace in `manifest.json` **[BREAKING]**

- **R8.1** `manifest$tables` becomes **`manifest$artifacts`**, keyed by name, each entry typed
  by `kind`. **The example below is illustrative, not the full entry schema** -- real table
  entries also carry `current_data_sha`, `last_updated`, and conditionally `original_file_sha` /
  `original_format` (see `.datom_update_manifest_entry()`, `R/sync.R:738-747`). Existing entry
  fields are preserved verbatim; `kind` is added, and set entries substitute `member_count` for
  `size_bytes`:

```json
{
  "schema_version": 2,
  "artifacts": {
    "dm":            {"kind": "table", "current_version": "...", "size_bytes": 4096, "version_count": 3},
    "adsl":          {"kind": "table", "current_version": "...", "size_bytes": 8192, "version_count": 1},
    "study001-adam": {"kind": "set",   "current_version": "...", "member_count": 2,  "version_count": 1}
  }
}
```

- **R8.2** **Not** a sibling `manifest$sets` node. Names must be unique **across kinds**,
  because storage keys are `{name}/...` regardless of kind. A set named `dm` alongside a table
  named `dm` would both write `dm/.metadata/metadata.json` and clobber each other. Two sibling
  nodes make that illegal state *representable* and require an explicit cross-node uniqueness
  guard that someone will eventually forget. One namespace makes it a key collision in a single
  list -- structurally impossible, no guard needed.
- **R8.3** The `summary` block keeps every existing field's current meaning and gains one:

```yaml
summary:
  total_tables:     <count where kind == "table">   # meaning unchanged
  total_size_bytes: <sum over tables>               # meaning unchanged
  total_versions:   <sum over tables>               # meaning unchanged
  total_sets:       <count where kind == "set">     # new, additive
```

  So the breaking surface is exactly **one key rename**, and no counter changes semantics.
- **R8.3a** **Set versions are deliberately not counted in `summary`.** `total_versions` stays
  tables-only (R8.3), and no `total_set_versions` is added. Reason: every existing counter keeps
  its current meaning, which is what holds the breaking surface to one key rename; adding a
  counter whose only consumer would be a future feature is speculative. Per-set version counts
  remain available on the entry (`version_count`) and via `datom_history()`. Recorded here so a
  later reader does not read the omission as an oversight.
- **R8.4** `datom_list()` and `datom_summary()` read `artifacts` and surface `kind`.

### R9 -- `schema_version` gate

Add a repo schema version, checked by readers, so that **this is the last transition that can
degrade silently**.

```r
SUPPORTED_SCHEMA <- 2L

if ((meta$schema_version %||% 1L) > SUPPORTED_SCHEMA) {
  cli::cli_abort(c(
    "This repo uses datom schema v{meta$schema_version}.",
    "x" = "Installed datom {utils::packageVersion('datom')} supports up to v{SUPPORTED_SCHEMA}.",
    "i" = "Upgrade with {.code remotes::install_github('amashadihossein/datom')}."
  ))
}
```

- **R9.1** **Asymmetric**: refuse *newer*, tolerate *older*. An absent field defaults to `1`, so
  v1 repos keep working.
- **R9.2** **Both reader entry points.** Readers take two independent paths, and a
  manifest-only gate leaves one open:

```
datom_list() / datom_summary()  --> .metadata/manifest.json          <- gate here
datom_read()                    --> {name}/.metadata/metadata.json   <- and here
```

  `datom_read()` never touches the manifest (verified: `R/read_write.R:44-58` -- it calls
  `.datom_read_metadata()` -> `.datom_resolve_version()` -> `.datom_read_parquet()`). So
  `schema_version` must live in **both** the manifest and per-table `metadata.json`.
- **R9.3** `schema_version` goes in the `volatile` exclusion list of
  `.datom_compute_metadata_sha()` (`R/utils-sha.R:412`), alongside `datom_version`. Otherwise a
  schema bump silently rewrites every table's version identity.
- **R9.4** **Do not overload `datom_version`.** It records the *writing package version* --
  provenance, not contract. Most releases will not change the schema, so gating on it would
  fire on harmless upgrades. Keep the two fields distinct.

### R10 -- Project mode: set repos forbid the import path, not the table path

A build-package repo *does* write new tables (derived `adsl`, `adae` parquets) -- it never
imports from files.

- **R10.1** Expressed as a project-level mode in `project.yaml` so `datom_sync_manifest()`
  refuses with a clear message instead of silently no-op'ing, and `datom_status()` reports
  accurately.
- **R10.2** The mode also **names the repo's set**:

```yaml
mode: product
set: study001-adam
```

- **R10.3** One repo = one set = one product. Enforcing it in datom rather than in the build
  package costs almost nothing, removes the ambiguity of "which set is this repo's product," and
  prevents anything else writing to the repo from violating the invariant.
- **R10.3a -- how R10.3 is actually enforced.** The claim above is only true if something checks,
  so two concrete gates:
  1. **`datom_write_set()` requires `mode: product`.** On a repo without it, abort with the
     recourse (set `mode: product` + `set:` in `project.yaml`). A set written into a
     non-product repo would have no declared owner and would defeat both gates below.
  2. **`datom_write_set(name = )` must equal `project.yaml`'s `set:` field.** A mismatch aborts.
     This is what makes "one repo = one set" true rather than aspirational, and it is also the
     precondition design.md section 5 relies on when it says the cycle walk's root is known
     before the write.

  These two checks run **before** any hashing or IO, so a refusal leaves no partial state
  (the `.datom_canonical_hash()` precedent).
- **R10.4** `mode: "product"` reads better than `mode: "set"` since these repos also hold
  derived tables.

### R11 -- `datom_validate()` branches on kind

`R/validate.R:386` hardcodes the data-object check inside `.datom_validate_one_table()`:

```r
data_key <- paste0(name, "/", meta$data_sha, ".parquet")
```

On a set this fails 100% of the time and reports `data_missing_s3`.

- **R11.1** **table** -- existing parquet existence check, unchanged.
- **R11.2** **set** -- payload exists at `{name}/{data_sha}.json`, **and** every member
  resolves.
- **R11.3** New status code for unresolvable members (e.g. `members_unresolvable`). A citable
  artifact that can silently rot undermines the auditability claim, so this is in scope rather
  than deferred.

### R12 -- Public write/read surface

- **R12.1** `datom_member(conn, name, version)` -- validated member constructor mirroring
  `datom_parent()`.
- **R12.2** `datom_write_set(conn, members, ...)` -- derives the payload from members; **reuses
  change detection, git-gates-storage ordering, and dedup unchanged** (the step 4-10 sequence in
  `datom_write()`).
- **R12.3** `datom_read_set()` -- resolves and returns the set. **Both directions of the
  kind mismatch abort with a pointer to the right function**: `datom_read()` on a set points at
  `datom_read_set()` (AC6), and `datom_read_set()` on a table points at `datom_read()` (AC14).
  The converse matters as much as the original -- without it, `datom_read_set()` on a table
  fetches `{name}/{data_sha}.json`, gets a not-found, and reports a missing payload for an
  artifact that is perfectly healthy.
- **R12.4** Export JSON put/get on the Storage Extension API -- harden the existing
  `.datom_storage_read_json()` / `.datom_storage_write_json()` internals. No direct
  `.datom_s3_*()` calls from business logic.
- **R12.4a -- the export must not be able to clobber datom-managed keys.** A public
  `datom_storage_write_json()` that accepts any key lets a downstream package write
  `{name}/.metadata/metadata.json` or `{name}/{data_sha}.json` directly, **silently bypassing
  git-gates-storage (I5/I6) and integrity for artifacts datom manages**. That is a
  silent-degradation path in a new public API, which the compatibility posture forbids on its own
  terms. The write export therefore **refuses managed keys**: anything under a `.metadata/`
  segment, and any payload-shaped key (`{name}/{sha}.{json,parquet}`) under an existing artifact
  directory. Reads are unrestricted -- reading a managed key is useful and harmless.
  This is a **public contract decision, settled here rather than at implementation time**.

### R13 -- Documentation

- **R13.1** `dev/datom_pathways.md` route card: "Given a set + version, resolve its members".
- **R13.2** `dev/datom_specification.md`: set artifact kind, `schema_version` contract.
- **R13.3** Fix the stale "task 5.1" claims in `R/read_write.R`. They assert version-pinned reads
  lack `parquet_sha` "until `version_history` entries persist `parquet_sha` (task 5.1)". That is
  **stale**: `.datom_write_metadata_local()` already persists it (the conditional-add block) and
  `.datom_resolve_version()` reads it back (`R/read_write.R:177`). Only *legacy* entries lack it.
  **Four sites, verified by `grep -n "task 5\.1" R/read_write.R`** -- note #89 cited `95-97`,
  which is the function title, not the stale text:

  | Line | Site | Problem |
  |---|---|---|
  | 105-108 | `.datom_resolve_version()` docstring | "until ... (task 5.1)" -- stale |
  | 205-206 | `.datom_read_parquet()` `@param parquet_sha` | "before task 5.1 persists it" -- stale |
  | 413 | `.datom_lookup_history_parquet_sha()` docstring | "transitional period before task 5.1" -- stale |
  | 393 | `.datom_resolve_parquet_sha()` comment | **"Since task 5.1..."** -- already correct, and therefore *contradicts* the three above within the same file |

  Sweep all four: drop the internal task references entirely (they are meaningless to public
  readers, per the Don'ts) and state the actual condition -- only pre-#72 legacy entries lack
  `parquet_sha`.
- **R13.4** NEWS entry noting the `artifacts` rename, its discovery-only exposure, and the
  `schema_version` gate.

---

## 5. Acceptance criteria

These are the behaviors most likely to be silently mis-implemented. **Each gets a test.**

| # | Criterion |
|---|---|
| **AC1** | **Reader role, no git.** A storage-only connection (no `github_pat`, no clone) can `datom_read_set()` and resolve members. This is the primary use case; the "git-canonical" framing must not lead to requiring a clone. |
| **AC2** | **Idempotent re-write.** Writing an identical member list to the same set name is a no-op -- dedup on set `data_sha`, no new version appended. |
| **AC3** | **Version sensitivity.** A set whose member *names* are unchanged but whose member *versions* advanced **must** produce a new `data_sha` and a new version. Do not "optimize" this away. |
| **AC4** | **Name uniqueness across kinds.** Writing a set with the name of an existing table (or vice versa) is refused. **Mechanism**: the check reads `{name}/.metadata/metadata.json` from **storage** and compares `kind` -- not the manifest, which can lag behind a partially-completed write. This is the same source `.datom_has_changes()` already consults, so the check costs no extra round-trip. Stated explicitly so it is not decided by accident. |
| **AC5** | **Empty and single-member sets.** `.datom_canonical_hash()` aborts on zero rows/cols; the set analogue must be decided and tested. An empty set is plausible (a product before its first output) -- legal or refused, but **explicit either way**. |
| **AC6** | **`datom_read()` on a set** aborts with a message pointing at `datom_read_set()`, not a cryptic missing-parquet error. |
| **AC7** | **Schema gate fires, both directions.** *Refuse-newer*: a repo declaring `schema_version: 3` aborts with the upgrade message, at **both** entry points (manifest and per-artifact metadata). *Tolerate-older*: a repo with no `schema_version` field behaves exactly as 0.1.0 did. **Mechanism note**: an actually-installed 0.1.0 reader has no gate to fire, so this is not testable by installing an old version -- the test drives `.datom_check_schema_version()` directly with a fixture declaring a version above `SUPPORTED_SCHEMA`. Test the gate, not the archaeology. |
| **AC8** | **Lineage isolation.** A set's metadata contains no `parents` and no `source_lineage` (**omitted, not null**), and writing a set does not alter any member's lineage. |
| **AC9** | **Cycle refusal at write time.** A set that transitively contains itself **within a project** is refused at write time. |
| **AC13** | **Round-trip hash agreement.** For every golden fixture, `data_sha` computed from the in-memory payload equals `data_sha` recomputed after `serialize -> parse`. Covers R2.5. Include fixtures that specifically exercise the mutating cases: a length-1 vector vs a scalar, `NA_real_`, `NA_character_`, and a whole-number double. |
| **AC14** | **`datom_read_set()` on a table** aborts pointing at `datom_read()` -- the converse of AC6, not a missing-payload error for a healthy table. |
| **AC15** | **Cross-project cycle terminates at read time.** A stored cycle that write-time checks could not see (A's set references B's, B's references A's, each written through its own connection) causes `datom_read_set()` and `datom_validate()` to **abort**, not hang. Covers R4.4. |

Plus the standing project gates:

- **AC10** Full `devtools::test()` suite green, count reported in every commit message, count
  never drops. Baseline at spec start: **2460** (verified by two `devtools::test()` runs on
  `dev` @ `b57cdba`: `FAIL 0 | WARN 0 | SKIP 0 | PASS 2460`).
- **AC11** `R CMD check --as-cran` at 0 errors / 0 warnings (the one pre-existing NOTE is
  acceptable).
- **AC12** E2E workflow run before spec completion (per Operational Discipline item 5): a new
  offline `dev/e2e-sets.R` in the style of `dev/e2e-cv1-identity.R`, asserting every claim and
  exiting non-zero on mismatch.

---

## 6. Out of scope

| Item | Disposition |
|---|---|
| Flattening a collection into a long-format table | Rejected -- see design.md "Alternatives considered" |
| Building the collection in the build package instead | Rejected -- composability loss is unworkaroundable |
| Sibling `manifest$sets` node | Rejected -- makes cross-kind name collision representable |
| Renaming `parquet_sha` to a kind-neutral name | Rejected -- would silently disable integrity verification in released readers |
| Dual-writing `tables` alongside `artifacts` for one release | Rejected -- exposure is discovery-only; permanent schema clutter not worth it |
| Bespoke canonical regime for `metadata_sha` itself | **File separately.** The emitter-drift argument already applies to `metadata_sha` today (it hashes `jsonlite::toJSON(auto_unbox = TRUE)` output). This is a pre-existing exposure and expanding this spec to cover it is out of scope -- see design.md "Surfaced latent concern". |
| datom knowing the term "product" | Out of scope by design. `set` is datom's word; "product" belongs to the build package. A domain-neutral primitive that downstream packages give domain meaning to is the correct layering, and it keeps the door open for non-data-product uses. |
