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
- **R1.3** A set's `metadata.json` collapses to: `kind`, `schema_version`, `data_sha`,
  `hash_algo`, `document_sha`, `created_at`, `datom_version`. No `parents`, no
  `source_lineage`, no `table_type`, no `nrow` / `ncol` / `colnames` -- **omitted, not nulled**
  (mirroring how `.datom_build_metadata()` already conditionally assigns `original_file_sha`).

**Acceptance**: a written set's metadata contains exactly the field set above; `names()` on the
parsed metadata has no `parents`, `source_lineage`, `table_type`, `nrow`, `ncol`, or `colnames`
entry.

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

**Acceptance**: the standalone reference and the in-package implementation produce identical
`data_sha` for every golden fixture, on both x86_64 and arm64.

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
- **R4.3** Set-in-set nesting is bounded by two rules decided **at write time**, not discovered
  at read time: a **depth limit** and **cycle detection**.

**Acceptance**: AC9 below; plus a hand-assembled member list is refused with a message pointing
at `datom_member()` (mirroring the `remedy` pattern in `.datom_validate_parents()`).

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
  by `kind`:

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
- **R12.3** `datom_read_set()` -- resolves and returns the set; `datom_read()` **refuses** a set
  and points at `datom_read_set()`.
- **R12.4** Export JSON put/get on the Storage Extension API -- harden the existing
  `.datom_storage_read_json()` / `.datom_storage_write_json()` internals. No direct
  `.datom_s3_*()` calls from business logic.

### R13 -- Documentation

- **R13.1** `dev/datom_pathways.md` route card: "Given a set + version, resolve its members".
- **R13.2** `dev/datom_specification.md`: set artifact kind, `schema_version` contract.
- **R13.3** Fix the stale docstring at `R/read_write.R:95-97`. It claims version-pinned reads
  lack `parquet_sha` "until `version_history` entries persist `parquet_sha` (task 5.1)". That is
  **stale**: `.datom_write_metadata_local()` already persists it (the conditional-add block) and
  `.datom_resolve_version()` reads it back (`R/read_write.R:177`). Only *legacy* entries lack it.
  The same stale claim appears in the `@param parquet_sha` docs of `.datom_read_parquet()` and in
  the comment inside `.datom_resolve_parquet_sha()` -- sweep all of them.
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
| **AC4** | **Name uniqueness across kinds.** Writing a set with the name of an existing table (or vice versa) is refused. |
| **AC5** | **Empty and single-member sets.** `.datom_canonical_hash()` aborts on zero rows/cols; the set analogue must be decided and tested. An empty set is plausible (a product before its first output) -- legal or refused, but **explicit either way**. |
| **AC6** | **`datom_read()` on a set** aborts with a message pointing at `datom_read_set()`, not a cryptic missing-parquet error. |
| **AC7** | **Schema gate fires.** A v1 reader construct against a v2 manifest aborts with the upgrade message; a v2 reader against a v1 repo works normally. |
| **AC8** | **Lineage isolation.** A set's metadata contains no `parents` and no `source_lineage` (**omitted, not null**), and writing a set does not alter any member's lineage. |
| **AC9** | **Cycle refusal.** A set that transitively contains itself is refused at write time. |

Plus the standing project gates:

- **AC10** Full `devtools::test()` suite green, count reported in every commit message, count
  never drops. Baseline at spec start: **2460**.
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
