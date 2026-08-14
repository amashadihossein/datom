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
- **R4.3 -- resolution is one level; datom never traverses.** A set's payload lists its **direct**
  members only. Reading a set returns those member records; if a member is itself a set, the
  consumer gets a **pointer** to it and reads that set separately if they want its contents. This
  mirrors `datom_get_parents()`, which returns one step back and leaves further steps to the
  caller. **No datom operation walks the member graph** -- not `datom_read_set()`, not
  `datom_validate()`. A consumer wanting a flattened tree composes repeated reads in their own
  code.
- **R4.4 -- the member graph is acyclic by construction, so no cycle detection is specified.**
  A member pins an **immutable version**, and declaring it requires that version to already exist
  (`datom_member()` reads its snapshot). So a set cannot reference anything that contains it --
  that thing did not exist when its members were chosen. This is the same property that makes git
  history acyclic. Concretely, the sequence that looks like a cross-project cycle is not one:

  ```
  1. A writes set A1 containing B1@v1        (B1@v1 must already exist)
  2. B writes set B1@v2 containing A1@v1     (does NOT mutate B1@v1)

  Result: B1@v2 -> A1@v1 -> B1@v1            terminates; v1 and v2 are distinct nodes
  ```

  Because of this, **no depth limit and no visited-set guard are required**. Nothing can loop,
  and with R4.3 nothing traverses in the first place.
- **R4.5 -- self-reference is refused as nonsense, not as a cycle.** A set listing itself (an
  earlier version of itself) as a member is acyclic and would terminate, but it is never
  meaningful. Cheap check at write time, clear error.

**Acceptance**: AC9 (self-reference refused) and AC15 (nesting resolves one level, no traversal)
below; plus a hand-assembled member list is refused with a message pointing at `datom_member()`
(mirroring the `remedy` pattern in `.datom_validate_parents()`).

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
- **R6.1a -- git side: one stable path. Storage side: content-addressed.**

  | Side | Path | Why |
  |---|---|---|
  | **git** | `{name}/set.json` -- a single stable path, modified in place | git carries the history, and `git diff` shows **member-level** changes |
  | **storage** | `{name}/{data_sha}.json` -- content-addressed, immutable | a reader must fetch an exact version by address, with no git |

  The git side mirrors how `{name}/metadata.json` already works: stable path, mutated, history
  owned by git.
- **R6.1b -- why the git side is NOT content-addressed** (this reverses an earlier draft). With a
  content-addressed filename, every version is a **new file**, so `git diff` between two product
  versions reports "file added" and never "these members changed". History would be read by
  listing filenames -- i.e. hand-maintaining what git already maintains (R20). One stable path
  gives real diffs, keeps one file in the working tree instead of N, and makes the earlier
  "retain all historical payloads" rule unnecessary: **git retention is definitional.** Any
  version is still fully reconstructible from the clone alone via
  `git show <commit>:{name}/set.json`, so the P17 guarantee is preserved and strengthened.
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
     precondition the self-reference check (R4.5) relies on -- it needs to know the set's own
     identity before the write.

  These two checks run **before** any hashing or IO, so a refusal leaves no partial state
  (the `.datom_canonical_hash()` precedent).
- **R10.4** `mode: "product"` reads better than `mode: "set"` since these repos also hold
  derived tables.
- **R10.5 -- `mode: product` is also an identity badge.** Beyond gating the import path, the mode
  declares "this datom repo is also a build-package project". The downstream build package
  (`dpdev`) checks it at attach time. So the mode carries two meanings that must both hold:
  *forbid the import path* (R10.1) and *this repo is jointly owned* (R14). datom itself knows
  nothing about the build package's structure -- see R16 non-goals.

### R11 -- `datom_validate()` branches on kind

`R/validate.R:386` hardcodes the data-object check inside `.datom_validate_one_table()`:

```r
data_key <- paste0(name, "/", meta$data_sha, ".parquet")
```

On a set this fails 100% of the time and reports `data_missing_s3`.

- **R11.1** **table** -- existing parquet existence check, unchanged.
- **R11.2** **set** -- payload exists at `{name}/{data_sha}.json`, **and** every member resolves
  as far as the available connections allow. "Resolves" is **scoped, because it has to be**:
  - **Same-project members** are fully checked (their metadata is in this namespace).
  - **Cross-project members** are checked as *well-formed pointers* only, unless the caller
    supplies a connection for that project. datom performs no name-to-location lookup of its own
    (R18), so a validator that claimed to fully check cross-project members would either be
    lying or silently requiring governance.
  Checking is **one level deep** -- each member pointer resolves to an existing artifact. The
  validator does not traverse into nested sets (R4.3); validating an inner set is a separate
  `datom_validate()` call against that set's own project. Unresolvable members reuse the same
  status code (R11.3) rather than inventing a second vocabulary.
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
- **R12.5 -- `datom_write_set(conn, members, ..., include_paths = NULL)`.** Optional character
  vector of repo-relative paths staged **into the same commit** as the set payload and its
  metadata files. Purpose: the set version's commit tree contains the code and environment that
  produced it, so **the joint version is structural, not recorded** (see R14 rationale). The build
  package passes its own enforced-structure manifest (e.g. `R/`, `dp/`, `renv.lock`, `tests/`);
  it never passes add-all.
  - **Ordering unchanged.** git-gates-storage is preserved: local writes -> **one** git commit
    (payload + metadata + `include_paths`) -> push -> storage mirror.
  - **The storage mirror contains only datom artifacts.** `include_paths` content is **never**
    mirrored to storage. It is git-only, by design (R16).
  - **Validation, both before any hashing or IO** (same gate placement as R10.3a):
    - A nonexistent path in `include_paths` is an **error**, not a skip. Joint commits must be
      deterministic, not best-effort.
    - A path overlapping datom-owned paths (`{artifact}/**`, `.datom/**`) is **refused** -- those
      are staged automatically and listing them invites double-staging confusion.
  - **Dedup interaction -- the sharp edge.** If the set content is unchanged (same `data_sha`, so
    AC2's idempotent no-op applies), the write **remains a no-op even when `include_paths` files
    have changed**: no commit is created. Emit an informational message directing the caller to
    `datom_repo_commit()` (R15). Rationale: AC2 must not acquire a side channel that commits code.
    An idempotent data write that silently commits human WIP would be exactly the
    machine-moment-add-all failure R14 exists to prevent, arriving through a different door.
- **R12.4a -- the export must not be able to clobber datom-managed keys.** A public
  `datom_storage_write_json()` that accepts any key lets a downstream package write
  `{name}/.metadata/metadata.json` or `{name}/{data_sha}.json` directly, **silently bypassing
  git-gates-storage (I5/I6) and integrity for artifacts datom manages**. That is a
  silent-degradation path in a new public API, which the compatibility posture forbids on its own
  terms. The write export therefore **refuses managed keys**: anything under a `.metadata/`
  segment, and any payload-shaped key (`{name}/{sha}.{json,parquet}`) under an existing artifact
  directory. Reads are unrestricted -- reading a managed key is useful and harmless.
  **It must also refuse `.access/`.** `{prefix}/datom/.access/` is a **namespace reserved for the
  future access-enforcement package** (`dev/datomanager_overview.md`, "Reserved Namespace"), under
  a standing rule that datom never reads, writes, or deletes there -- with an audit confirming
  datom is currently safe *by construction* (it has no list/delete calls and every key goes
  through the `datom/`-inserting key builder). This export is the first genuinely general-purpose
  write surface datom has ever offered, so it is also the first thing that could break that
  reservation. Adding `.access/` to the refusal list keeps the guarantee structural rather than
  incidental.
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

### R14 -- Foreign-content discipline in `mode: product` repos

**Context (the decision this encodes).** The `mode: product` repo **is the joint repo**: data
pointers, derivation code, and environment (`renv.lock`) live together. There is no separate
code/env repo. All git **mutations** (stage, commit, push, pull) go through datom; downstream
packages never import `git2r`. Writing files on disk is not a git operation and needs no datom
API. Rationale in design.md section 19.

Consequence: a datom repo now routinely contains content datom does not own, and datom commits at
**machine-chosen** moments (inside each write, possibly mid-build) while humans edit code
continuously. So:

- **R14.1 -- machine-moment commits stage only datom-owned paths.** A commit created inside
  `datom_write()` / `datom_write_set()` stages **only** the written artifact's files and
  `.datom/**`. **Never add-all.** This is already true by implementation --
  `.datom_git_commit()` takes an explicit file list (`R/utils-git.R:182`) -- so the requirement
  **elevates it from an accident of implementation to a stated guarantee**, with a test, so a
  future add-all refactor fails CI rather than an audit.
- **R14.2 -- all datom operations tolerate non-datom paths.** `datom_validate()`,
  `datom_status()`, `datom_list()`, and the sync/pull paths must never stage foreign paths and
  never report them as defects. `datom_status()` **may** report foreign dirty files as
  uncommitted git state (that is honest reporting of the repository, and useful), but must not
  classify them as a datom problem; `datom_validate()` must not surface them at all.
- **R14.3 -- `include_paths` is the sole exception.** The only way a machine-moment commit may
  contain a non-datom path is R12.5, and only because the caller enumerated it explicitly.

### R15 -- New exports: the sanctioned git-mutation surface

```r
datom_repo_commit(conn, message, paths = NULL, push = TRUE)
datom_repo_push(conn)
```

The **sanctioned git-mutation surface** for downstream packages committing non-datom content
(framework state, code, environment). Without it, a downstream package's only options are to
import `git2r` (rejected -- R16) or to abuse a datom write.

**Two verbs, not one, and the reason is a hazard rather than a preference.** R15.3 supports
`push = FALSE` explicitly so downstream can decouple commit from push (the `dpbuild`
`dp_commit()` / `dp_push()` pattern). That pattern needs a second verb: without one, "push what I
already committed" is only expressible as *another commit attempt*, and in a `mode: product` repo
`paths = NULL` is add-all. So a caller who merely wants to push would route through a code path
that commits any human WIP it happens to find -- **the R14 machine-moment add-all failure arriving
through a third door.** Intent to push must be spellable without risking a commit.

Supporting symmetry: datom already exports a standalone `datom_pull()` (`R/sync.R:45`) with no
standalone push counterpart, and the `datom_repo_*` family already exists (`datom_repo_delete()`,
`datom_repo_set_data_store()`, `datom_repo_attach_governance()`). `datom_repo_push()` closes an
existing asymmetry rather than inventing a new shape.

- **R15.1** `paths = NULL` (default): stage **all** tracked-and-modified plus untracked changes,
  respecting `.gitignore` -- i.e. what `git add .` would stage. These are **human-invoked**
  moments, where add-all is the correct semantic (this is exactly why R14.1 restricts
  *machine* moments only).
- **R15.2** `paths = <character vector>`: stage exactly those repo-relative paths.
- **R15.3** `push = TRUE` (default): push after commit through the existing path
  (`.datom_git_push()`, inheriting its pull-before-push and upstream-tracking behavior).
  `push = FALSE` is supported so downstream can decouple commit from push -- see
  `datom_repo_push()` (R15.8) for the other half.
- **R15.4** Requires **developer** role; a reader conn gets the standard role error.
- **R15.5** **Nothing to stage is an informational no-op** (`cli::cli_alert_info()`, return
  `invisible(NULL)`), **not** an error -- a human-moment "commit everything" must be idempotent.
  **Qualification: "no-op" means no *commit* is created; it does not suppress the push.** When
  `push = TRUE` and the branch is ahead of the remote, the push still runs. Otherwise a failed
  push on a previous call leaves the remote silently behind forever, since every subsequent call
  finds a clean tree and returns early -- a silent divergence, which the compatibility posture
  forbids on its own terms.
- **R15.6** Returns the commit SHA invisibly on success; `invisible(NULL)` when no commit was
  created (whether or not a push occurred).
- **R15.7** **The on-a-branch (no detached HEAD) guard must be asserted explicitly**, not
  inherited. It currently lives in `.datom_git_branch()` and is reached only via
  `.datom_git_push()`, so with `push = FALSE` nothing would check it. Call it up front so the
  guard holds for both `push` values. (See design.md section 19 "Corrections to the delta".)
- **R15.8 -- `datom_repo_push(conn)`.** Pushes the current branch through the same path
  (`.datom_git_push()`), so it inherits pull-before-push, upstream-tracking, and the on-a-branch
  guard identically. **Convergent, not imperative**: nothing to push is an informational no-op,
  not an error, so calling it twice is safe and "ensure the remote has everything" is a legal
  standalone operation. Requires **developer** role. Returns `invisible(TRUE)`.
- **R15.9** Push convergence is decided by the **already-available** ahead count.
  `.datom_check_git_current()` already calls `git2r::ahead_behind()` and reads element `[[2]]`
  (behind); element `[[1]]` is ahead. So R15.5 and R15.8 need **no new git machinery** -- this is
  not speculative capability.

### R16 -- Non-goals (this spec deliberately does not do these)

- **Branch create/switch helpers.** Belongs with a future refs / branch-publication design.
  datom's existing on-a-branch requirement is unchanged.
- **Storage mirroring of code or environment content.** `include_paths` is git-only by design;
  the storage namespace holds datom artifacts and nothing else.
- **Any datom knowledge of the build package's structure.** datom receives paths as **opaque
  arguments**. The three-tier ownership taxonomy in design.md section 19 is *context for the
  reader*, not a datom contract -- datom must not validate, assume, or special-case `dp/`, `R/`,
  `renv.lock`, or any other build-package path.
- **No `.gitignore` API.** `datom_init_repo()` seeds `.gitignore` (existing behavior) and
  downstream packages append entries by **editing the file directly** -- a file write, not a git
  operation. **No `datom_gitignore_*` function is to be added.** Recorded to prevent API creep.

### R17 -- Artifact topology: one repo, one namespace, one manifest

- **R17.1** A datom project is one git repo paired with one **storage namespace**
  (`{root}/{prefix}/datom/`). Repo, namespace, and manifest are 1:1:1. Nothing is shared between
  two projects -- not artifacts, not the manifest, not a single file.
- **R17.2** A set therefore lands in **the namespace of the product repo that owns it**, never in
  a namespace holding onboarded source data. This is already structurally true by composition:
  a set can only be written to the repo whose config names it (R10.3a), one repo maps to one
  namespace, and `datom_init_repo()` already refuses an occupied namespace via
  `.datom_check_namespace_free()`.
- **R17.3 -- new guard.** Initializing a `mode: product` repo **refuses a namespace that already
  contains a manifest for a different project**, with a message naming the occupying project and
  the recourse (use a distinct prefix). This closes the one remaining hole -- a deliberate
  force-init over an existing source namespace -- and turns a documented convention into a
  structural one.
- **R17.4 -- rationale is blast radius and ownership, not access control.** Teardown and
  prefix-delete operate on a **whole namespace**, so a product sharing a prefix with its source
  study means deleting the product can delete raw data. Secondarily, one namespace means one
  manifest, so sharing would make `datom_list()` unable to distinguish "the product" from
  "everything it was built from", and two git repos would contend for one manifest.
  **Explicitly not justified by access control** -- see R19.1, access is per-artifact.
- **R17.5 -- the rule is namespace separation, not bucket count.** One bucket with a prefix per
  product is the documented house convention (`dev/vignettes-deferred/buckets-and-prefixes.Rmd`,
  Pattern A: bucket-per-study, empty prefix for raw, *"prefix per product"* for multiple products
  per study). A dedicated or shared product bucket is equally fine. datom enforces separation and
  takes no position on bucket topology.
- **R17.6** A `mode: product` repo is **not a leaf**. Its derived tables are first-class datoms in
  a real namespace, so another product can take them as members or as parents. This is the
  composability claim from #89 and it depends on R17.1 holding.

### R18 -- Location resolution: explicit standalone, governance takes priority

- **R18.1 -- datom needs no governance for cross-project membership or lineage.** The mechanism is
  **caller-supplies-connection**: `datom_member(conn_src, ...)` and `datom_parent(conn_src, ...)`
  receive the other project's connection explicitly, record its `project_name` as a **label**, and
  datom performs **no name-to-location lookup anywhere**. A product spanning three studies in
  three buckets works with three configured connections and no governance attached.
- **R18.2 -- the precedence that already exists, which sets inherit rather than re-invent.** A
  project's location is written explicitly in its own config; `ref.json` in the governance repo is
  the authoritative pointer **once governance exists**, and connection-time resolution prefers it
  (this is what makes migration possible without rewriting artifacts). `governance.json` --
  written to both the git repo and the storage mirror -- **is the flag** for whether governance is
  attached. Member resolution follows exactly this precedence: caller-supplied connection when
  there is no governance, governance register once attached.
- **R18.3 -- member records carry a logical project name and never a location.** No backend, root,
  prefix, or region in a member entry. The payload is immutable and content-addressed, so an
  embedded location would go stale the day a bucket moves -- which is precisely the indirection
  `ref.json` exists to provide. Logical name in the artifact; physical location resolved at read
  time.
- **R18.4** Automatic name-to-location resolution is the **future access-enforcement package's**
  concern, not datom's: its registry holds a SOURCES table mapping project name to bucket/prefix,
  used when its lineage walker crosses buckets (`dev/datomanager_overview.md`). datom must not
  grow a competing lookup.

### R19 -- Forward compatibility with access enforcement

Recorded so this spec's decisions stay coherent with the planned access layer
(`dev/datomanager_overview.md`). **Nothing here is built now**; it constrains what we must not
foreclose.

- **R19.1 -- access is per-artifact, not per-namespace.** Roles are defined at table granularity,
  and every artifact has its own folder under the namespace, so a policy can grant
  `.../datom/adsl/*` without granting `.../datom/adae/*`. Per-artifact grants are expressible as
  prefix patterns. **A set is independently grantable for the same reason** -- it is an artifact
  with its own folder.
- **R19.2 -- two derived tables in one product legitimately have different access requirements.**
  Required permissions for a derived table are the union of the roles required by its **leaf**
  ancestors, discovered by walking lineage. Two tables in the same product, same bucket, same
  prefix, with different ancestry get different requirements **automatically** -- nobody configures
  it. This is a reason R17's namespace rule must not be justified by access control: separation is
  about blast radius, and granularity is finer than a namespace anyway.
- **R19.3 -- a set gates on nothing, because it has no lineage.** Members are references, not
  parents (R3), so a lineage walk from a set terminates immediately and finds no leaves. Under the
  access algorithm that means a set requires no roles unless explicitly overridden. This is not a
  special case -- it is the same conclusion the non-conjunctive access decision (R3.3) reached from
  the other direction, now consistent with the access layer's own algorithm.
- **R19.4 -- granting a product does not grant its members.** Auto-inheritance runs through
  `parents`, and sets have none. Counterintuitive enough that it must be documented, not left to
  be discovered.
- **R19.5 -- a sensitive member list uses the explicit-override path.** Knowing which studies are
  pooled can itself be confidential. The access layer already supports adding a specific artifact
  directly to the roles table to *add* requirements beyond what lineage implies (the embargo
  case). Sets need no new mechanism for this.
- **R19.6 -- `.access/` stays reserved.** See R12.4a: the new JSON-write export must refuse it.

### R20 -- Git is the history mechanism; anything history-shaped datom writes is a projection

- **R20.1 -- the rule.** Git owns history. Anything datom writes that *resembles* history exists
  **only as a projection for consumers who cannot read git**, is always **derived from git**, and
  is **never the source of truth**.
- **R20.2 -- the test.** *Would someone holding the repo use this file to answer a history
  question?* If yes, it is a smell.

  | Artifact | Test | Verdict |
  |---|---|---|
  | `version_history.json` | a developer would run `git log`; only a **reader** needs it, to map `version` -> `data_sha` without a clone | **keep** -- legitimate projection |
  | `manifest.json` | same: a discovery index for git-less readers | **keep** |
  | content-addressed payload filenames **in git** | a developer would have had to read history by listing filenames | **smell -- fixed by R6.1a** |

  The clearest illustration that `version_history.json` is a projection rather than a duplicate:
  it carries `author` and `commit_message`, which are **literally git commit fields**. Nobody with
  a clone would ever read them from there.
- **R20.3** Consequently no new hand-maintained history is introduced by this spec. Set payload
  history is git history (R6.1a/b); set version history is the existing `version_history.json`
  projection; no payload index and no per-payload log is added.

### R21 -- Version semantics, and the version-to-commit link

**Decision (option 1 of three considered):** a version stays **content-derived** for both artifact
kinds. The git commit is recorded **provenance**, not identity.

- **R21.1 -- what a version means, identically for tables and sets.** A version
  (`metadata_sha`) answers *"is this the same content and declared metadata?"* It is
  **code-invariant**: nothing code-derived enters it.
- **R21.2 -- the consequence, which is intended, not a gap.** The relationship is asymmetric:
  a data change necessarily changes the commit, but a commit change does **not** necessarily
  change the data. So **a code-only change that reproduces identical content mints no new
  version** -- a refactor, a comment fix, or an added script leaves `data_sha` and `metadata_sha`
  untouched, and the write is the existing idempotent no-op. This is already true for tables today
  and is deliberately kept true for sets.
- **R21.3 -- therefore one version maps to one-or-more commits**, and `commit_sha` records **the
  commit that first introduced that version**. The ambiguity is benign: the caller asked for a way
  to reproduce the version, and the recorded commit provably produces it.
- **R21.4 -- why not make the commit the version.** Considered and rejected. It is not directly
  possible (the commit contains the metadata that would name it -- the same circularity as a git
  commit not containing its own SHA), and a composite `(metadata_sha, commit_sha)` version would
  break `datom_read(version = )` taking a single string. **Also rejected: putting code/env content
  hashes into the payload** (which *would* avoid the circularity, since file hashes are knowable
  before committing). Reason: a set exists to be **citable**, and under that scheme a comment typo
  or a lint fix mints a new product version, so versions proliferate for semantically null changes
  and "product v47" stops carrying meaning. Reproduction is fully served by R21.3 instead.
- **R21.5 -- `commit_sha` lives in the `version_history.json` entry**, beside `author` and
  `commit_message` -- its siblings, also git facts projected for readers (R20.2). Note this has
  **zero identity impact and needs no volatile-list entry**: `metadata_sha` hashes
  `metadata.json`, not `version_history.json`.
- **R21.6 -- storage copy only, because of the write order.** The git copy of
  `version_history.json` is *inside* the commit it would have to name. So: local files -> commit
  -> push -> **upload the storage copy with `commit_sha` added**. That is the existing
  git-gates-storage ordering, one step tighter than dpbuild's (which needs a separate deploy pass
  because pins gives it no post-commit hook).
- **R21.7 -- derived, never authored.** This is the trap. `datom_validate(fix = TRUE)` re-uploads
  metadata from the clone, which would **silently strip `commit_sha`**. So the repair path must
  **re-derive** it from `git log` on the artifact path rather than dropping it. Both writers derive
  from git -- the write path from the commit it just made, the repair path from history -- so
  storage never holds unrecoverable state and the "mirror is always derived from git" invariant
  survives.
- **R21.8 -- repo holders need nothing stored.** With the stable-path payload (R6.1a),
  `git log -p {name}/set.json` gives version, diff, and commit together. The stored field exists
  purely for the git-less reader.
- **R21.9 -- precedent, recorded because it is confirmation rather than invention.** dpbuild keeps
  no commit hash in the product repo (its `.daap/daap_log.yaml` is inside the commit), and
  dpdeploy publishes it to a storage-side board log (`dpboard-log`) that dpi's `dp_list()` reads
  **with no git**. That log's composite key is `(dp_name, pin_version, git_sha)` -- an explicit
  acknowledgement that the same content version can pair with different commits, which is exactly
  R21.3. datom differs only in granularity: the per-artifact `version_history.json` already exists
  and already carries the sibling git fields, so no board-wide per-version index is added.


---

## 5. Acceptance criteria

These are the behaviors most likely to be silently mis-implemented. **Each gets a test.**

| # | Criterion |
|---|---|
| **AC1** | **Reader role, no git -- and "resolve" means two different things, tested separately.** (a) **Resolve the pointers**: a storage-only connection (no `github_pat`, no clone) can `datom_read_set()` and get back the member records. This always works and is the primary use case -- the "git-canonical" framing must not lead to requiring a clone. (b) **Resolve to data**: reading a member's actual content needs a connection scoped to *that member's* project -- same-project members work through the same connection; cross-project members require the caller's connection (or, later, the governance register). Conflating (a) and (b) is how this gets mis-implemented as "reading a set requires access to everything in it". |
| **AC2** | **Idempotent re-write.** Writing an identical member list to the same set name is a no-op -- dedup on set `data_sha`, no new version appended. |
| **AC3** | **Version sensitivity.** A set whose member *names* are unchanged but whose member *versions* advanced **must** produce a new `data_sha` and a new version. Do not "optimize" this away. |
| **AC4** | **Name uniqueness across kinds.** Writing a set with the name of an existing table (or vice versa) is refused. **Mechanism**: the check reads `{name}/.metadata/metadata.json` from **storage** and compares `kind` -- not the manifest, which can lag behind a partially-completed write. This is the same source `.datom_has_changes()` already consults, so the check costs no extra round-trip. Stated explicitly so it is not decided by accident. |
| **AC5** | **Empty and single-member sets.** `.datom_canonical_hash()` aborts on zero rows/cols; the set analogue must be decided and tested. An empty set is plausible (a product before its first output) -- legal or refused, but **explicit either way**. |
| **AC6** | **`datom_read()` on a set** aborts with a message pointing at `datom_read_set()`, not a cryptic missing-parquet error. |
| **AC7** | **Schema gate fires, both directions.** *Refuse-newer*: a repo declaring `schema_version: 3` aborts with the upgrade message, at **both** entry points (manifest and per-artifact metadata). *Tolerate-older*: a repo with no `schema_version` field behaves exactly as 0.1.0 did. **Mechanism note**: an actually-installed 0.1.0 reader has no gate to fire, so this is not testable by installing an old version -- the test drives `.datom_check_schema_version()` directly with a fixture declaring a version above `SUPPORTED_SCHEMA`. Test the gate, not the archaeology. |
| **AC8** | **Lineage isolation.** A set's metadata contains no `parents` and no `source_lineage` (**omitted, not null**), and writing a set does not alter any member's lineage. |
| **AC9** | **Self-reference refused.** Writing a set that lists itself (any version of itself) as a member is refused at write time with a clear error (R4.5). Note this is a nonsense check, **not** cycle detection -- cycles are structurally impossible (R4.4), so there is deliberately no cycle test and no depth test. |
| **AC13** | **Round-trip hash agreement.** For every golden fixture, `data_sha` computed from the in-memory payload equals `data_sha` recomputed after `serialize -> parse`. Covers R2.5. Include fixtures that specifically exercise the mutating cases: a length-1 vector vs a scalar, `NA_real_`, `NA_character_`, and a whole-number double. |
| **AC14** | **`datom_read_set()` on a table** aborts pointing at `datom_read()` -- the converse of AC6, not a missing-payload error for a healthy table. |
| **AC15** | **Nesting resolves one level -- no traversal.** Reading a set whose members include another set returns a **pointer** to that inner set (`kind = "set"`, name, project, version), and does **not** fetch the inner set's own members. Asserted by observing that no storage read of the inner set's payload occurs. Covers R4.3, and guards against an implementer "helpfully" flattening the tree. |
| **AC16** | **Machine-commit isolation.** In a `mode: product` repo with an uncommitted edit at `R/foo.R`, a `datom_write()` of a table produces a commit whose tree does **not** contain the `R/foo.R` change, **and** `R/foo.R` is still dirty in the working tree afterward. Both halves matter: the second catches a "helpfully" cleaned working tree (R14.1). |
| **AC17** | **`datom_repo_commit()` semantics.** `paths = NULL` stages a mixed tracked/untracked change set **minus** gitignored files; explicit `paths` stages exactly those; a reader conn is refused; nothing-to-stage creates **no commit** and is not an error; `push = FALSE` leaves the remote untouched. **Plus the R15.5 qualification**: with a clean tree, `push = TRUE`, and the branch ahead of the remote, no commit is created **but the push still happens** -- assert the remote advanced (R15). |
| **AC18** | **`include_paths` produces one joint commit.** A set write with `include_paths` creates **exactly one** commit containing payload + metadata + the listed paths, and the storage mirror afterward contains **only** datom artifacts (R12.5). |
| **AC19** | **Idempotent re-write stays a no-op under dirty `include_paths`.** Re-writing an identical member list while `include_paths` files have changed creates **no commit and no new version**, and emits the informational message pointing at `datom_repo_commit()` (R12.5). This is AC2 defended against a side channel. |
| **AC20** | **`include_paths` refused early -- two distinct gates, two separate test cases.** (a) A **nonexistent** path is refused; (b) a path **overlapping** a datom-owned path (`{artifact}/**`, `.datom/**`) is refused. Both **before any hashing or IO** (R12.5), consistent with the R10.3a gate placement. Kept as one criterion but **tested as two cases**, so a regression identifies which gate broke rather than only that one of them did. |
| **AC21** | **`datom_repo_push()` is convergent.** With unpushed local commits it advances the remote; called again immediately it is an informational **no-op, not an error**; a reader conn is refused; it inherits the on-a-branch guard (R15.8). |
| **AC22** | **Namespace separation is enforced, not merely documented.** Initializing a `mode: product` repo into a namespace that already holds another project's manifest is **refused**, with a message naming the occupying project and pointing at using a distinct prefix (R17.3). |
| **AC23** | **The JSON-write export refuses the reserved access namespace.** A write to any key under a `.access/` segment is refused, alongside the existing `.metadata/` and payload-key refusals (R12.4a, R19.6). Reads are unaffected. |
| **AC24** | **The git payload is diffable.** After writing a set twice with one member added, `git diff` on `{name}/set.json` between the two commits shows the **member-level** change (one added entry), not a whole-file add. Guards R6.1a/b -- a content-addressed git filename would make this test impossible to write. |
| **AC25** | **`commit_sha` is present, git-less, and survives repair.** After a set write: the **storage** copy of `version_history.json` carries `commit_sha` for the new version; the **git** copy does not (it cannot -- it is inside that commit); and after `datom_validate(fix = TRUE)` re-uploads metadata, `commit_sha` is **still there**, re-derived from `git log` rather than stripped (R21.6/R21.7). The third clause is the one that fails silently in a naive implementation. |
| **AC26** | **A code-only change mints no new version.** With the set's member list unchanged, modifying tracked code and re-running `datom_write_set()` produces **no new version**, and the existing version's recorded `commit_sha` is **unchanged** (still the first producing commit). Encodes the option-1 decision (R21.2/R21.3) so a later "improvement" that makes versions code-sensitive fails a test. |

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
