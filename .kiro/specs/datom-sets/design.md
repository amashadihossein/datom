# Design -- datom sets (second artifact kind)

**Source issue**: [#89](https://github.com/amashadihossein/datom/issues/89)
**Requirements**: `requirements.md` in this directory

---

## 1. Read first -- verified reference points

Every line reference below was checked against the working tree at the point this spec was
written (`dev` @ `b57cdba`). **Cite these rather than re-deriving them.**

| Reference | Location | What it gives us |
|---|---|---|
| `.datom_storage_read_json()` / `.datom_storage_write_json()` | `R/utils-storage.R:66,83` | Backend-neutral JSON IO already exists internally and is **unexported**. Exporting + hardening is in scope (R12.4). Both take a **relative** key (after `prefix/datom/`). |
| `.datom_build_storage_key(prefix, ...)` | `R/utils-path.R:29` | The key builder. **Returns a FULL key** (`{prefix}/datom/{segments...}`). Called only from the backend layer (`R/utils-s3.R:69,108,146,186,235`; `R/utils-local.R:19`) and from `R/storage.R`. See **Deviation D1**. |
| `datom_parent(conn, table, version)` | `R/lineage.R` (end of file) | The pattern `datom_member()` mirrors: validate name, validate version as a SHA, read the versioned snapshot at `{table}/.metadata/{version}.json`, return a pure-data record with no live connection. |
| `.datom_validate_parents()` | `R/utils-sha.R:59-` | The validator pattern for a reference-record list, including the `remedy` string that points every failure back at the constructor. `datom_member()`'s validator mirrors this. |
| `parquet_sha` persistence in history | `R/read_write.R`, `.datom_write_metadata_local()` conditional-add block; read back in `.datom_resolve_version()` at `R/read_write.R:177` | **Already implemented.** The `document_sha` requirement (R7.2) mirrors this exact conditional-add pattern. |
| Stale docstring | `R/read_write.R:95-97` (plus `@param parquet_sha` on `.datom_read_parquet()` and the comment in `.datom_resolve_parquet_sha()`) | Claims history does not yet persist `parquet_sha` "(task 5.1)". False since #72. Fix as part of this work (R13.3). This is what misled an earlier draft of #89. |
| Hardcoded parquet-existence check | `R/validate.R:386` in `.datom_validate_one_table()` | `data_key <- paste0(name, "/", meta$data_sha, ".parquet")`. Needs the `kind` branch (R11). |
| `volatile` exclusion list | `R/utils-sha.R:411-412` | `c("created_at", "datom_version", "parquet_sha", "column_hashes", "size_bytes")`. `schema_version` (R9.3) and `document_sha` (R7.4) join it. |
| `datom_read()` never touches the manifest | `R/read_write.R:44-58` | Confirmed: `.datom_read_metadata()` -> `.datom_resolve_version()` -> `.datom_read_parquet()`. This is why the schema gate needs **two** sites (R9.2) and why the `artifacts` rename is discovery-only. |
| `governance.json` dual-pointer pattern | `R/governance_json.R` | The model for the payload (R6.1): builder -> `.datom_write_*_local()` (git canonical) + `.datom_storage_write_*()` (mirror) + a `.datom_sync_*()` repair helper. Note the reader path (`.datom_storage_read_governance_json()`) works with **no clone** -- the precedent that makes AC1 achievable. |
| Manifest producer | `.datom_update_manifest_entry()`, `R/sync.R:702-760` | Single writer of `manifest$tables[[name]]` and of `manifest$summary`. The `artifacts` rename's write side is here and nowhere else. |
| Manifest initializer | `R/conn.R:520-528` | `datom_init_repo()` seeds `tables = structure(list(), names = character(0))` and `summary$total_tables`. Second write site for R8. |
| Manifest consumers | `R/query.R:58,85` (`datom_list()`), `R/query.R:439` (`datom_status()`), `R/query.R:544,550` (`.datom_status_input_files()`), `R/summary.R:57` (`datom_summary()`), `R/sync.R:374,387` (`datom_sync_manifest()`) | The complete read side of R8. Six call sites across four files. |
| cv1 reference + parity workflow | `dev/datom_cv1_reference.R`, `.github/workflows/cv1-reference-parity.yaml` | The template for the `datom-sv1` reference + goldens (R2.4). Note the workflow exists because `dev/` is `.Rbuildignore`d, so the parity test *skips* inside a built tarball -- the sv1 goldens inherit that hazard and must be wired into the same workflow. |
| `.datom_canonical_hash()` zero-dim abort | `R/utils-sha.R`, `.datom_canonical_hash()` | `nrow == 0 || ncol == 0` aborts. AC5 asks for the deliberate set analogue. |

---

## 2. Core design decision

> **A set is a reference layer, not a data layer.**

This is the load-bearing decision and everything else follows from it. Two corollaries drive the
rest of the design:

1. **Members are not parents** (section 3) -- so no lineage, no conjunctive access.
2. **A set is metadata-flavored, not data-flavored** (section 4) -- so git-canonical payload, no
   member index, collapsed metadata.

---

## 3. Members are not parents

A set is not *derived from* its members; it *references* them. So a set carries
`parents = null` and `source_lineage = null`, and the member list lives only in the payload.

This is not a special case -- **it falls out of existing behavior**:

- `datom_write()` derives `source_lineage` as `datom_lineage_union(parent_lineages)`, so
  null-parents automatically means no inheritance.
- Null-parents is an already-supported *shape*: `.datom_build_metadata()` assigns both fields
  conditionally (`if (!is.null(parents)) meta$parents <- parents`), so they are **omitted rather
  than nulled** -- exactly as `original_file_sha` is on derived tables.

### Consequences

**Access is per-member, enforced where it already is.** A set contains no data. Conjunctive
(AND) access across members would be wrong -- it would make a 50-table product unreadable to
anyone lacking one table. If you can read `AE` but not `CM`, you pull the set and work with `AE`.
`datom_read()` on the member is the only gate and needs no change.

**Lineage flows through tables only.** If product B derives a table from product A's `adsl`, B's
table names A's `adsl` as parent. The set is *how you found* the table, not *how data reached*
it.

**"Which raw sources fed product X at version V"** is a read-time union, not a stored field:

```r
members <- datom_read_set(conn, "study001-adam")$members
sls <- lapply(members, function(m) {
  datom_get_lineage(conns[[m$project]], m$name, version = m$version, depth = "source")
})
datom_lineage_union(sls)
```

Composed entirely from existing exports. Not stored, so it cannot go stale. For a 50-member
product that is 50 reads -- acceptable because this is a **cold path**: access is enforced
per-member at `datom_read()`, so the union is needed only for audit and reporting, never
per-access.

---

## 4. A set is metadata-flavored

Tags, descriptions, and view config go **in the payload**, not into a parallel metadata schema.

- **The payload is git-canonical with a storage mirror** -- the `governance.json` dual-pointer
  pattern (`R/governance_json.R`), *not* the parquet pattern (which is storage-only, because
  parquet bytes must never enter git).
- **No member index.** `column_hashes` exists so you can diff a table without downloading
  parquet. The payload is small and cheap to read, so a member index would be
  metadata-for-metadata.
- **The set's `metadata.json` collapses** to `kind`, `schema_version`, `data_sha`, `hash_algo`,
  `document_sha`, `created_at`, `datom_version`.

### Metadata field matrix

| Field | Table | Set | Rationale |
|---|---|---|---|
| `kind` | `"table"` | `"set"` | Semantic, in `metadata_sha` |
| `schema_version` | 2 | 2 | Volatile (R9.3) |
| `data_sha` | cv1 hash | sv1 hash | Content identity + storage address |
| `hash_algo` | `"datom-cv1"` | `"datom-sv1"` | Semantic -- declares the regime |
| `parquet_sha` | present | **absent** | Volatile; parquet-specific |
| `document_sha` | **absent** | present | Volatile; payload-specific |
| `table_type` | `imported`/`derived` | **omitted** | Provenance axis; meaningless for a set |
| `nrow`/`ncol`/`colnames` | present | **omitted** | Table-shaped |
| `column_hashes` | present | **omitted** | Table-shaped; volatile |
| `parents` / `source_lineage` | conditional | **omitted** | Section 3 |
| `size_bytes` | present | present | Payload byte size; volatile |
| `created_at` / `datom_version` | present | present | Volatile provenance |
| `custom` | conditional | conditional | Pass-through |

**Omitted, not nulled** throughout -- `jsonlite::write_json(auto_unbox = TRUE)` on a list
containing `NULL` drops the key anyway, but the *builder* must use the conditional-assign form
so the in-memory object and the round-tripped object agree (this is exactly why
`.datom_compute_metadata_sha()` hashes a JSON canonical form).

---

## 5. Member schema and constructor

```
{ project, name, kind, version }
```

- `project` -- otherwise cross-project membership cannot resolve, and cross-project is the point.
- `kind` -- a set may contain a set; without it a resolver cannot know whether to call
  `datom_read()` or `datom_read_set()`.

### `datom_member(conn, name, version)`

Mirrors `datom_parent()` (`R/lineage.R`) beat for beat:

| Step | `datom_parent()` | `datom_member()` |
|---|---|---|
| conn class check | `inherits(conn, "datom_conn")` | same |
| name validation | `.datom_validate_name(table)` | `.datom_validate_name(name)` |
| version validation | non-empty string + `.datom_validate_sha()` | same (path-traversal guard is mandatory -- `version` is spliced into a storage key) |
| snapshot read | `{table}/.metadata/{version}.json` | same |
| derives | `source`, `data_sha`, `source_lineage` from the snapshot | `project` (from `conn$project_name`), `kind` (from the snapshot, defaulting to `"table"` for v1 metadata that predates `kind`) |
| returns | pure data, no live conn | same |

**Do not let callers hand-assemble member lists.** `datom_parent()` is the established pattern
for constructing a validated reference record, and symmetry keeps validation at construction
time rather than deep inside `datom_write_set()`. A raw list gets the
`.datom_validate_parents()`-style `remedy` message pointing at `datom_member()`.

Note `datom_member()` does **not** carry `data_sha`. A member is a citation of a *version*, and
the version (`metadata_sha`) is what pins content; adding `data_sha` would duplicate a fact the
snapshot already fixes and would create a second thing to keep consistent. This is a deliberate
divergence from `datom_parent()`, whose `data_sha` exists to support the cross-project lineage
resolution that sets explicitly do not do (section 3).

### Nesting: depth limit + cycle detection

Two rules decided **at write time**, not discovered at read time.

- **Cycle detection**: walk the member graph at write time; refuse if the set being written is
  transitively reachable from its own members. The set's own name is known before the write
  (R10.2 pins it in `project.yaml`), so the walk has a root.
- **Depth limit**: a constant, checked during the same walk.

**Proposed depth limit: 8.** Rationale: deep enough that no plausible product composition hits
it (a product of products of products is already unusual), shallow enough that the write-time
walk is cheap and a runaway is caught fast. Flagged for the escalation review (section 12) --
this is a number that is cheap to pick now and annoying to change later, since it becomes part
of the observable contract.

**Cross-project nesting caveat**: resolving a member that is itself a set in *another* project
requires a connection scoped to that project. The write-time walk can only follow members
reachable through the connection(s) the caller supplies. **Design decision to confirm at
escalation**: the cycle walk is exhaustive within the current project and best-effort across
projects (an unresolvable cross-project member is not a cycle failure -- it is reported by
`datom_validate()` as `members_unresolvable`, R11.3). The alternative -- requiring a conn map at
write time -- would make the common single-project case pay for the rare case.

---

## 6. Storage layout and key construction

```
{name}/{data_sha}.json                  <- set payload            (NEW)
{name}/.metadata/metadata.json          <- current state          (same as tables)
{name}/.metadata/version_history.json   <- history                (same as tables)
{name}/.metadata/{metadata_sha}.json    <- versioned snapshot      (same as tables)
```

Note the **two distinct `.json` addresses**: the payload at `{name}/{data_sha}.json` and the
versioned metadata snapshot at `{name}/.metadata/{metadata_sha}.json`. Different directories, no
key collision, but easy to confuse.

Tables keep `{name}/{data_sha}.parquet`. This is *why* an unupgraded reader meeting a set fails
loudly -- it fetches a `.parquet` object that does not exist.

### Deviation D1 -- key builder correction

**#89 says**: "Keys go through `.datom_build_storage_key()` (`R/utils-path.R`) -- do not
hand-roll `paste0`."

**The codebase says otherwise, and the issue's instruction cannot be followed literally.**
`.datom_build_storage_key()` returns a **full** key including the prefix and the `datom/`
segment:

```r
.datom_build_storage_key("proj", "customers", "abc123.parquet")
#> "proj/datom/customers/abc123.parquet"
```

But `.datom_storage_*()` dispatch takes **relative** keys (after `prefix/datom/`) and the
backend layer calls `.datom_build_storage_key()` itself (`R/utils-s3.R:69`,
`R/utils-local.R:19`). Passing a full key to `.datom_storage_write_json()` would double-prefix.
Every business-logic call site therefore builds a relative key with `paste0` today --
`R/read_write.R`, `R/query.R`, `R/lineage.R`, `R/validate.R`, `R/governance_json.R`.

**Resolution**: honor the *intent* (no ad-hoc `paste0` scattered across call sites) without
breaking the *contract* (relative keys at the dispatch boundary). Introduce a small
relative-key helper family in `R/utils-path.R`:

```r
.datom_artifact_payload_key(name, data_sha, kind)   # "{name}/{data_sha}.{parquet|json}"
.datom_artifact_meta_key(name, which)               # "{name}/.metadata/{metadata.json|version_history.json}"
.datom_artifact_snapshot_key(name, metadata_sha)    # "{name}/.metadata/{metadata_sha}.json"
```

`.datom_build_storage_key()` stays exactly where it is, unchanged, as the backend-internal full-key
builder. The new helpers are the single place the `.parquet` vs `.json` payload-extension
decision lives, which is precisely the confusion R5.1 warns about. Existing `paste0` call sites
migrate to them opportunistically (same-chunk only, no separate sweep).

The `data_sha` / `metadata_sha` path-traversal guard (`.datom_validate_sha()`, added in #74 task
G) must be applied inside these helpers or immediately before them at every call site --
`{name}/{data_sha}.json` splices a caller-influenced value into a key exactly as
`.datom_read_parquet()` does.

---

## 7. Identity -- `datom-sv1`

### Why not `datom-cv1`

cv1 is table-shaped and binary-framed:

```
sha256( "datom-cv1" || f64le(nrow) || f64le(ncol) || concat(col_digests) )
```

`nrow` / `ncol` / per-column digests do not generalize to a tree.

### Why not just hash the emitted JSON

Carry the #72 lesson forward. A JSON/YAML emitter drifts across versions (key order, quoting,
wrapping) the way `arrow` drifted for parquet. Hashing emitter output would reintroduce exactly
the failure #72 removed: an emitter upgrade minting spurious versions.

### The basis

The JSON canonicalization already used by `.datom_compute_metadata_sha()` -- radix-sorted keys
(`sort(names(x), method = "radix")`, locale-independent by design),
`jsonlite::toJSON(auto_unbox = TRUE)`, sha256 -- **extended for nesting**, under its own
`hash_algo` identifier `datom-sv1`.

`hash_algo` already exists to declare the regime and is correctly in the semantic set
(`R/utils-sha.R`: "a new hash algorithm legitimately defines a new version").

### Proposed shape -- FOR ESCALATION REVIEW (section 12)

The following is a *starting proposal*, not a settled design. It is the single most expensive
thing in this spec to reverse, because the golden vectors freeze it.

```
sv1_value(x):
  scalar string   ->  0x01 || utf8(x)   || 0x00
  scalar number   ->  0x02 || f64le(x)              # cv1 numeric encoder, reused
  scalar boolean  ->  0x03 || 0x00|0x01
  null            ->  0x04
  array           ->  0x05 || f64le(length) || concat(sv1_value(el) for el in order)
  object          ->  0x06 || f64le(n_keys) ||
                      concat( utf8(k) || 0x00 || sv1_value(v)
                              for k in sort(keys, method = "radix") )

data_sha = sha256( "datom-sv1" || sv1_value(payload) )
```

Design intent behind each choice:

- **Type-tagged**, so `"1"` and `1` and `TRUE` cannot collide. `.datom_compute_metadata_sha()`'s
  `toJSON` basis loses this (`auto_unbox` makes `1` and `list(1)` identical); for a tree that
  users compose, type confusion is a real collision surface.
- **Length-prefixed** arrays and objects, so `["a","b"]` and `["ab"]` cannot collide by
  concatenation. This is the framing property cv1 gets from `f64le(nrow)||f64le(ncol)`.
- **Array order significant, object key order not.** Member order in a set is a curatorial
  choice a user can see and control, so it is identity (matching cv1's "row order is
  significant"). Object key order is an emitter artifact, so it is normalized by radix sort
  (matching `.datom_compute_metadata_sha()`).
- **Reuses `.datom_encode_numeric()`** verbatim, inheriting the pinned canonical NaN, the
  `-0 -> +0` fold, and the preserved `NA_real_` bit pattern -- the three canonicalizations that
  #72's CI matrix proved necessary. Do **not** write a second numeric encoder.
- **`f64le` for lengths**, not an integer encoding, purely for consistency with cv1's framing so
  the two reference implementations share one primitive.

Open questions the escalation should settle, listed explicitly so they are not decided by
accident:

1. Is the payload hashed **whole** (including tags, descriptions, view config) or only the
   **member list**? Whole-payload means editing a description mints a new version. That is
   probably *correct* for a citable artifact -- a citation should pin what the consumer reads --
   but it is a contract, not an obvious default, and it interacts with AC2/AC3.
2. Does `sv1_value` need a canonical form for `NA_character_` distinct from `""` and from
   `null`? cv1 needed the NA mask byte for exactly this reason
   (`.datom_encode_character()`); the JSON tree has a third state (`null`) that cv1 does not.
3. AC5: is an empty set legal? `.datom_canonical_hash()` aborts on zero-dim. **Proposal: an
   empty set is legal** -- "a product before its first output" is a real state, and the framing
   above hashes `length = 0` unambiguously, so there is no collision reason to refuse. This
   inverts cv1's precedent, so it needs a conscious decision rather than an inherited one.
4. Does the payload embed `schema_version`? If yes, a schema bump changes every set's
   `data_sha`. **Proposal: no** -- `schema_version` lives in `metadata.json` only, consistent
   with R9.3 putting it in the `volatile` list precisely to keep it out of identity.

### Reference implementation + parity workflow

Mirror `dev/datom_cv1_reference.R`: standalone, `digest`-only dependency, self-testing with
PASS/FAIL per property, printing golden constants. Wire it into
`.github/workflows/cv1-reference-parity.yaml` (extend the existing workflow rather than adding a
second one -- it already runs the x86_64 + arm64 matrix that cross-architecture agreement
requires, and its "nothing may skip" assertion is the mechanism that caught the #72 golden-fixture
bug).

---

## 8. Integrity -- `document_sha`

Sets get `document_sha` for stored-document integrity, **verified on read at the same gate
position as `parquet_sha`** -- after download, *before* parsing
(`.datom_read_parquet()`, `R/read_write.R:217`). A set read must not parse an unverified payload.

`document_sha` is persisted in `version_history.json` entries **from day one**, using the
existing conditional-add pattern in `.datom_write_metadata_local()`. This is the pattern, already
working for `parquet_sha`:

```r
if (!is.null(metadata$parquet_sha)) {
  new_entry$parquet_sha <- metadata$parquet_sha
}
```

Because it is there from day one, sets never need the "legacy entries lack it, skip the check"
grace that `parquet_sha` carries. **The set read path should therefore treat a missing
`document_sha` as an error, not as a skip.** This is the one place where deviating from the
`parquet_sha` precedent is correct: the skip-on-absent branch exists purely as a pre-cv1
migration grace, and reproducing it for a field that has no legacy population would be building
a silent-degradation path on purpose -- exactly what the compatibility posture forbids.

---

## 9. One typed namespace -- `manifest$artifacts`

See requirements R8 for the schema. The decisive argument is not aesthetic.

**Names must be unique across kinds, because storage keys are `{name}/...` regardless of kind.**
A set named `dm` alongside a table named `dm` would both write `dm/.metadata/metadata.json` and
clobber each other. Two sibling nodes (`manifest$tables` + `manifest$sets`) make that illegal
state *representable* and require an explicit cross-node uniqueness guard that someone will
eventually forget. **One namespace makes it a key collision in a single list -- structurally
impossible, no guard needed.** AC4 tests the resulting refusal.

### Blast radius (verified)

Write side -- two sites:
- `.datom_update_manifest_entry()`, `R/sync.R:746,751-757` (entry + summary)
- `datom_init_repo()`, `R/conn.R:522-527` (seed)

Read side -- six sites across four files:
- `datom_list()`, `R/query.R:58,85`
- `datom_status()`, `R/query.R:439`
- `.datom_status_input_files()`, `R/query.R:544,550`
- `datom_summary()`, `R/summary.R:57`
- `datom_sync_manifest()`, `R/sync.R:374,387`

`datom_validate()` reads the manifest only for `project_name` (`R/validate.R`,
`.datom_validate_project_name()`) so it is unaffected by the rename itself -- but it is affected
by R11 (kind branch), which is why #89 groups them into one escalation moment.

**This is the second escalation flag** (section 12): the rename must land atomically across all
eight sites plus their tests. A partial rename yields a manifest whose writer and reader
disagree, which presents as "everything looks fine, `datom_list()` is empty."

---

## 10. `schema_version` gate

See requirements R9 for the code shape and the four requirements. Design notes:

- The gate is **the point of this spec's long-term value**: it makes this the *last* transition
  that can degrade silently. Every subsequent schema change gets an abort instead of an empty
  list.
- **Two sites, not one**, because readers take two independent paths and `datom_read()` never
  touches the manifest (verified, `R/read_write.R:44-58`). A manifest-only gate leaves the data
  path open -- which is the more important of the two.
- Implement as one internal `.datom_check_schema_version(meta, source)` called from
  `.datom_read_metadata()` and from the manifest readers, so the message is written once.
- **`schema_version` must go in the `volatile` list** (`R/utils-sha.R:412`). Otherwise the v1->v2
  bump rewrites every existing table's `metadata_sha`, i.e. mints a spurious version for every
  table in every repo -- the exact failure #72 was fought over.
- **Do not overload `datom_version`.** It records the writing package version -- provenance, not
  contract. Most releases will not change the schema, so gating on it would fire on harmless
  upgrades.

---

## 11. Compatibility analysis

### Why `parquet_sha` is not renamed

`.datom_read_parquet()` guards verification with (`R/read_write.R:217`):

```r
if (!is.null(parquet_sha) && nzchar(parquet_sha)) { ...verify... }
```

A 0.1.0 reader hitting metadata that used a different field name resolves `parquet_sha` to
`NULL` and **skips integrity verification entirely**, reading happily. For an audit-oriented
package that is worse than an error -- and it is not hypothetical: the reader/developer split
deliberately supports different install cadences, so an unupgraded analyst reading data written
by an upgraded data manager is a **supported configuration**.

Note `parquet_sha` is in the `volatile` exclusion list (`R/utils-sha.R:412`), so a rename would
be *identity-neutral* -- no version SHA would change. The objection is purely about silent
degradation in released readers. This is the canonical worked example of the compatibility
posture: identity-neutral and mechanically trivial, and still refused, because the failure mode
is silent.

### Why the `artifacts` rename is acceptable anyway

Verified at `R/read_write.R:44-58`: `datom_read()` reads per-table metadata -> resolves version
-> fetches parquet. It never touches the manifest. So the rename affects only discovery:

| Function | Effect on a 0.1.0 reader |
|---|---|
| `datom_read()` | none |
| `datom_list()` | returns empty |
| `datom_summary()` | reports zero |

Data access is untouched, and `schema_version` ensures this is the **last** transition that can
degrade quietly rather than abort. Note in NEWS (R13.4).

### Sets themselves create no compatibility problem

An unupgraded reader meeting a set reads `{name}/.metadata/metadata.json`, gets `data_sha`, then
fetches `{name}/{data_sha}.parquet` -- which does not exist. It fails loudly, which is correct.
This is a designed property of keeping the table payload extension unchanged (R5.3), not an
accident.

---

## 12. Model escalation flags

Per `.github/copilot-instructions.md` "Model Escalation", flagged **at plan time** as #89
requires. Both **must** be re-surfaced in the chunk checkpoint message for their chunk (rule 5d),
whether or not they still seem necessary by then.

### E1 -- Canonical set-content hash design (`datom-sv1`) -- Task 2

**Why**: cross-cutting, expensive to reverse, and it **gates the golden vectors**. Once goldens
are published, changing the encoding requires a conscious `datom-sv2` bump, exactly as cv1
documents. Section 7 lists four open questions that should be settled deliberately rather than
by implementation accident (whole-payload vs member-list-only hashing; `NA_character_` vs `""`
vs `null`; empty-set legality; whether `schema_version` enters the payload).

**Trigger type**: design spot-check before committing to a large or cross-cutting chunk.

### E2 -- Manifest namespace change (`tables` -> `artifacts`) -- Task 5

**Why**: touches `datom_list()`, `datom_summary()`, `datom_validate()`, and the sync manifest
updater **together** -- eight verified call sites across four files (section 9), plus their
tests. A partial rename yields a writer/reader disagreement that presents as "everything looks
fine, the list is just empty," which is the failure class the `schema_version` gate exists to
prevent and which no test will catch unless it is written to.

**Trigger type**: design spot-check + purity audit after the change lands.

A third, softer moment: **test coverage review before spec completion** (Task 12), per the third
standing escalation trigger. Nine acceptance criteria plus a new hash regime is a lot of surface
to claim covered.

---

## 13. Invariants

Must-never rules. Violating any of these is a correctness bug, not a style issue.

| # | Invariant |
|---|---|
| **I1** | A set's metadata **never** contains `parents` or `source_lineage`, in any form -- not even as an explicit `null`. |
| **I2** | Artifact names are unique **across kinds** within a project. There is exactly one `manifest$artifacts` namespace; no second node may be introduced. |
| **I3** | An integrity check is **never** silently skipped. Absent `document_sha` on a set is an error, not a skip (section 8). |
| **I4** | `schema_version` and `document_sha` are in the `volatile` exclusion list. A schema bump must not alter any existing artifact's `metadata_sha`. |
| **I5** | Git is the serialization point: **git commit + push must succeed before any storage mutation**, for sets exactly as for tables (`datom_write()` steps 7-10). A set write that fails at git leaves no orphaned payload. |
| **I6** | The set payload is written to **both** git (canonical) and storage (mirror) in the same operation. The storage mirror is always derived from git, never the reverse. |
| **I7** | Business logic **never** calls `.datom_s3_*()` or `.datom_local_*()` directly -- only `.datom_storage_*()` dispatch. |
| **I8** | Reading a set requires **no git clone**. Storage-only readers are the primary consumer (AC1). |
| **I9** | Any caller-influenced value spliced into a storage key passes `.datom_validate_sha()` / `.datom_validate_name()` first. |
| **I10** | Cycle and depth checks run at **write** time. A stored set is never a cycle that a reader has to defend against. |
| **I11** | No credentials in the payload, metadata, manifest, or any set-related file. |
| **I12** | `table_type` remains validated to exactly `"imported"` / `"derived"`. `kind` is a separate axis and must not be smuggled into it. |

---

## 14. Correctness properties

Tagged so tests can reference them, following the #72 spec's convention.

| Tag | Property |
|---|---|
| **P1** | For a fixed member list and payload, `data_sha` is identical across R versions, `jsonlite` versions, platforms, and architectures. |
| **P2** | Two sets with equal semantic content have equal `data_sha`, regardless of the order keys were inserted into the payload object. |
| **P3** | Two sets differing in **member order** have **different** `data_sha` (order is curatorial, hence identity). |
| **P4** | Two sets differing in any member's `version` have different `data_sha` (AC3). |
| **P5** | Type confusion is impossible: no string/number/boolean/null value collides with another across the encoding. |
| **P6** | Concatenation confusion is impossible: no two distinct arrays or objects produce the same byte sequence. |
| **P7** | Re-writing an identical set is a no-op -- no new version, no new payload object, no storage write (AC2). |
| **P8** | A set's `data_sha` is independent of `created_at`, `datom_version`, `schema_version`, `document_sha`, and `size_bytes`. |
| **P9** | A payload whose stored bytes do not match `document_sha` is refused before parsing. |
| **P10** | A v2 reader against a v1 repo behaves exactly as 0.1.0 did (absent `schema_version` defaults to 1, tolerated). |
| **P11** | A v1 reader against a v2 repo aborts with the upgrade message at **both** entry points. |
| **P12** | The in-package sv1 implementation and `dev/datom_sv1_reference.R` agree on every golden, on x86_64 and arm64. |
| **P13** | Writing a set never mutates any member's metadata, history, or manifest entry. |
| **P14** | `datom_validate()` reports `ok` for a healthy set and a non-`ok` status naming the specific defect for a missing payload vs an unresolvable member (distinguishable, not merged). |

---

## 15. Alternatives considered

| Alternative | Verdict |
|---|---|
| **Flatten the collection into a long-format table** (`name`, `project`, `version`, `tag_key`, `tag_value`) -- would technically satisfy `datom-cv1`. | **Rejected.** It would become a **data-layer artifact subject to lineage semantics** -- precisely what a set must not be -- and nested view config does not survive the flattening. |
| **Build the collection outside datom, in the build package.** | **Rejected.** Duplicates version history, content addressing, dedup, ref resolution and governance, and the result still could not be referenced as a member of another collection. The composability loss is the one that cannot be worked around. |
| **Sibling `manifest$sets` node.** | **Rejected.** Makes cross-kind name collisions representable, requiring a guard that one typed namespace makes unnecessary. Also bolted-on -- a from-scratch design would have typed one namespace, since `tables` was only ever "the things in this repo." |
| **Rename `parquet_sha` to a kind-neutral name.** | **Rejected.** Section 11 -- silently disables integrity verification in released 0.1.0 readers. |
| **Dual-write `tables` alongside `artifacts` for one release.** | **Rejected.** `datom_read()` does not touch the manifest, so exposure is discovery-only; carrying a legacy mirror to protect a likely-empty user population is not worth the permanent schema clutter. |
| **Reuse `datom-cv1` for sets.** | **Rejected.** Table-shaped and binary-framed; `nrow`/`ncol`/per-column digests do not generalize to a tree (section 7). |
| **Hash the emitted JSON bytes.** | **Rejected.** Reintroduces the #72 failure mode with `jsonlite` playing the role `arrow` played. |
| **`mode: "set"` instead of `mode: "product"`.** | **Rejected.** These repos also hold derived tables, so "product" describes the repo and "set" describes one artifact in it. |

---

## 16. Surfaced latent concern -- file separately, do not expand this spec

The drift argument in section 7 ("a JSON emitter drifts the way `arrow` drifted") **already
applies to `metadata_sha` today**. `.datom_compute_metadata_sha()` hashes the output of
`jsonlite::toJSON(auto_unbox = TRUE)` -- an emitter whose formatting could shift across
jsonlite versions and silently change every metadata hash, i.e. mint a spurious version for
every artifact in every repo on a dependency upgrade.

This should be decided consistently: if the risk justifies a bespoke canonical regime for sets,
it is a **pre-existing exposure in `metadata_sha` warranting its own issue**. If it does not, a
bespoke regime for sets is harder to justify.

**Action**: file a separate issue during Task 1. Do **not** expand this spec to cover it -- but
do not let the inconsistency go unrecorded either, because "we built sv1 because emitters drift"
and "we left metadata_sha hashing an emitter" cannot both be right.

---

## 17. Pathway impact

**Yes -- `dev/datom_pathways.md` needs a new route card** (R13.1):

> **Given a set + version, resolve its members.**
> `{name}/.metadata/{version}.json` -> `data_sha` + `document_sha` ->
> `{name}/{data_sha}.json` (verify `document_sha` **before** parsing) -> `members[]` ->
> per member, dispatch on `kind` to `datom_read()` or recurse.

Also update the existing read route to note the `kind` branch and the `schema_version` gate.
Every chunk records pathway impact or explicitly states "no pathway impact" (README maintenance
rule 8).
