# Design -- datom sets (second artifact kind)

**Source issue**: [#89](https://github.com/amashadihossein/datom/issues/89)
**Requirements**: `requirements.md` in this directory

---

## 1. Read first -- verified reference points

Every line reference below was checked against the working tree at the point this spec was
written (`dev` @ `b57cdba`). **Cite these rather than re-deriving them.**

| Reference | Location | What it gives us |
|---|---|---|
| `.datom_storage_read_json()` / `.datom_storage_write_json()` | `R/utils-storage.R:66,83` | Backend-neutral JSON IO already exists internally and is **unexported**. Exporting + hardening the **read** is in scope (R12.4); the **write** export is deferred (R12.4a). Both take a **relative** key (after `prefix/datom/`). |
| `.datom_build_storage_key(prefix, ...)` | `R/utils-path.R:29` | The key builder. **Returns a FULL key** (`{prefix}/datom/{segments...}`). Called only from the backend layer (`R/utils-s3.R:69,108,146,186,235`; `R/utils-local.R:19`) and from `R/storage.R`. See **Deviation D1**. |
| `datom_parent(conn, table, version)` | `R/lineage.R` (end of file) | The pattern `datom_member()` mirrors: validate name, validate version as a SHA, read the versioned snapshot at `{table}/.metadata/{version}.json`, return a pure-data record with no live connection. |
| `.datom_validate_parents()` | `R/utils-sha.R:59-` | The validator pattern for a reference-record list, including the `remedy` string that points every failure back at the constructor. `datom_member()`'s validator mirrors this. |
| `parquet_sha` persistence in history | `R/read_write.R`, `.datom_write_metadata_local()` conditional-add block; read back in `.datom_resolve_version()` at `R/read_write.R:187` (version-pinned) and `129` (current) | **Already implemented.** The `document_sha` requirement (R7.2) mirrors this exact conditional-add pattern. |
| Stale "task 5.1" docstrings | `R/read_write.R:110-113`, `205-206`, `413` (stale) and `393` (already correct, hence contradicting) | Claims history does not yet persist `parquet_sha`. False since #72. **#89 cited `95-97`, which is the function title, not the stale text** -- corrected here from `grep -n "task 5\.1"`. Four sites; see R13.3 for the table. This is what misled an earlier draft of #89. |
| Hardcoded parquet-existence check | `R/validate.R:391` in `.datom_validate_one_table()` | `data_key <- paste0(name, "/", meta$data_sha, ".parquet")`. Needs the `kind` branch (R11). |
| `volatile` exclusion list | `R/utils-sha.R:415-416` | `c("created_at", "datom_version", "parquet_sha", "column_hashes", "size_bytes")`. `schema_version` (R9.3) and `document_sha` (R7.4) join it. |
| `datom_read()` never touches the manifest | `R/read_write.R:44-58` | Confirmed: `.datom_read_metadata()` -> `.datom_resolve_version()` -> `.datom_read_parquet()`. This is why the schema gate needs **two** sites (R9.2) and why the `artifacts` rename is discovery-only. |
| `governance.json` dual-pointer pattern | `R/governance_json.R` | The model for the payload (R6.1): builder -> `.datom_write_*_local()` (git canonical) + `.datom_storage_write_*()` (mirror) + a `.datom_sync_*()` repair helper. Note the reader path (`.datom_storage_read_governance_json()`) works with **no clone** -- the precedent that makes AC1 achievable. |
| Manifest producer | `.datom_update_manifest_entry()`, `R/sync.R:710-769` | Single writer of `manifest$tables[[name]]` and of `manifest$summary`. The `artifacts` rename's write side is here and nowhere else. |
| Manifest initializer | `R/conn.R:520-528` | `datom_init_repo()` seeds `tables = structure(list(), names = character(0))` and `summary$total_tables`. Second write site for R8. |
| Manifest consumers | `R/query.R:62,89` (`datom_list()`), `R/query.R:458` (`datom_status()`), `R/query.R:562,573` (`.datom_status_input_files()`), `R/summary.R:61` (`datom_summary()`), `R/sync.R:378,396` (`datom_sync_manifest()`) | The complete **read** side of R8: six call sites across three files. Write side is three more (section 9), nine total. |
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

Tags go **in the payload** (a description is just a tag), not into a parallel metadata schema.
There is no view or navigation config -- see "Tags replace structure" below.

- **The payload is git-canonical with a storage mirror** -- the `governance.json` dual-pointer
  pattern (`R/governance_json.R`), *not* the parquet pattern (which is storage-only, because
  parquet bytes must never enter git).
- **No member index.** `column_hashes` exists so you can diff a table without downloading
  parquet. The payload is small and cheap to read, so a member index would be
  metadata-for-metadata. **This is also the answer to "how does a git-less reader diff two
  versions?"** -- it reads `version_history.json` (which already carries `data_sha` per entry,
  `R/read_write.R:485-491`) to map version -> `data_sha`, then fetches the two content-addressed
  payloads and compares them: three small JSON reads, no git. That yields the **actual changed
  values**, which per-member digests could not. Diffing `members[]` must key on
  `id$project` + `id$name` rather than array position, since member order is not identity for
  tags and a reorder must not read as a change. Two rejected alternatives in section 15.
- **No view or navigation config either** -- and this is the decision that lets the payload be
  text-only (R2.11). See "Tags replace structure" below.

### Tags replace structure; structure is never stored

The thing tags replace is dpbuild's nested product list -- `dp$input$raw_ae()`,
`dp$output$derived1`, `dp$metadata$data_def`. A nested list behaves like folders: an item lives in
exactly one place. Tags remove that limit, so `role`, `domain`, and the like become **per-member
labels** (R4.6) and an item can carry several at once. Multi-valued tags
(`domain: ["safety", "efficacy"]`) are therefore the motivating case, not an extension -- they are
the only reason arrays appear in the grammar.

**Folder structure becomes a projection, computed by the consumer** (R4.7): prioritise one ordering
of tag keys and you get one hierarchy; prioritise a different set -- at gov level, per
organisation -- and you get another. That prioritisation is presentation, not content, so datom
stores tag facts and takes no position on hierarchy. Arbitrarily many structures cost nothing,
because none of them is stored.

Two consequences worth being explicit about:

- **#89's "view config" is retired.** The issue listed tags, descriptions **and view config** as
  payload content, and its rejected flat-table alternative was partly rejected because "nested view
  config does not survive the flattening". With navigation *being* the tags, there is no separate
  nested structure to preserve -- so the argument no longer applies, and the payload can be
  text-only.
- **Closures stay downstream.** dpbuild's inputs are lazy closures; a datom member is a pointer and
  `datom_read()` is the lazy fetch. Assembling closures is the build package's job, which is the
  layering #89 asked for.
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
| `size_bytes` | present | **absent** | Nothing consumes it for a set: `summary$total_size_bytes` is tables-only (R8.3) and the set's manifest entry carries `member_count` instead. See R1.4. |
| `created_at` / `datom_version` | present | present | Volatile provenance |
| `custom` | conditional | **absent** | Redundant: tags live in the **payload**, and a description is a tag (R6.2). Two channels for one thing is two places to look. `datom_write_set()` has no `metadata =` parameter. See R1.4. |

The set column of this matrix is exactly the seven fields of R1.3 -- the two tables are
reconciled deliberately, because an earlier draft had the matrix granting `size_bytes` and
`custom` while R1.3 said "exactly seven", which would have made the R1.3 acceptance test and the
matrix mutually unsatisfiable.

**Omitted, not nulled** throughout -- `jsonlite::write_json(auto_unbox = TRUE)` on a list
containing `NULL` drops the key anyway, but the *builder* must use the conditional-assign form
so the in-memory object and the round-tripped object agree (this is exactly why
`.datom_compute_metadata_sha()` hashes a JSON canonical form).

---

## 5. Member schema and constructor

```
{ id: { project, name, kind, version }, tags: { ... } }
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

### Nesting: one-level resolution, and why nothing else is needed

A set may contain a set. **datom resolves one level and never traverses** (R4.3): reading a set
returns its direct member records, and a member that is itself a set comes back as a *pointer*.
A consumer who wants the inner set's contents reads that set. This mirrors `datom_get_parents()` --
one step back, further steps are the caller's.

So "list every table under this product tree" is not a datom operation. A consumer composes
repeated reads. That keeps the cost model obvious (one read per set you actually ask about) and
keeps datom out of the business of deciding how deep is far enough.

#### The member graph is acyclic by construction

This is the property that removes the rest of the machinery, and it is worth stating precisely
because an earlier draft of this design got it wrong.

A member pins an **immutable version**, and `datom_member()` requires that version to already
exist (it reads the snapshot). Therefore a set can never reference something that contains it --
that thing did not exist at the moment its own members were chosen. **Same property that makes
git history acyclic.**

An earlier draft claimed a cross-project cycle was reachable, via:

```
1. Project A writes set A1 with member B1     "legal, B1 has no members yet"
2. Project B writes set B1 with member A1     "legal from B's connection"
   => claimed: A1 -> B1 -> A1 is now stored
```

**That reasoning is wrong.** Step 2 does not mutate the `B1` that A referenced; it creates a new
version. The actual stored result is:

```
B1@v2  ->  A1@v1  ->  B1@v1      terminates -- v1 and v2 are distinct immutable nodes
```

To close a loop you would need to forge a reference to a version that does not exist yet, which
`datom_member()` refuses and which the payload's own `data_sha` / `document_sha` would not
survive.

**Consequently there is no cycle detection, no visited set, and no depth limit in this spec.**
Nothing can loop, and per R4.3 nothing traverses anyway. An earlier draft specified all three; they
were solving a problem that cannot occur. Recorded in section 18 (finding F1) as a correction,
because the removal is easy to mistake for an oversight.

#### The one check that stays

**Self-reference is refused** (R4.5): a set listing itself as a member. That is acyclic and would
terminate, so it is not a safety issue -- it is simply never meaningful. It is a cheap check, and
the set's own identity is known before the write because `project.yaml` names it (R10.3a).

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

### The basis (settled -- Q5)

**No serializer is in the identity path.** sv1 borrows cv1's *approach* -- a deterministic
structural walk with fixed byte encodings -- and applies it to a tree instead of a table, under
its own `hash_algo` identifier `datom-sv1`.

`hash_algo` already exists to declare the regime and is correctly in the semantic set
(`R/utils-sha.R`: "a new hash algorithm legitimately defines a new version").

An earlier draft proposed borrowing `.datom_compute_metadata_sha()`'s basis (radix-sorted keys ->
`jsonlite::toJSON(auto_unbox = TRUE)` -> sha256). That is superseded: it puts a third-party emitter
in the identity path, which is the dependency #72 removed for parquet, and it is the same exposure
section 16 files separately for `metadata_sha` itself. **sv1 does not inherit that exposure** --
see section 7.4.

### 7.1 Hard constraint: the hash domain is the parsed-JSON model

**Force unchanged; mechanism superseded by Q5 (section 7.3).**

The payload is written to git, mirrored to storage, and re-read to verify `document_sha` and to
resolve members. So `data_sha` is computed at least twice: once from an **in-memory R object** at
write time, once from a **parsed-JSON object** at read time. Those are not the same data model, and
R cannot tell a scalar from a length-1 vector. Demonstrated on the branch:

```r
x <- list(a = "s", b = list("s"), c = NA_real_, d = NA_character_, e = list(1, 2))
jsonlite::toJSON(x, auto_unbox = TRUE)
#> {"a":"s","b":["s"],"c":"NA","d":null,"e":[1,2]}
str(jsonlite::fromJSON(j, simplifyVector = FALSE))
#> $ a: chr "s"          <- scalar, unchanged
#> $ c: chr "NA"         <- NA_real_ became the STRING "NA"
#> $ d: NULL             <- NA_character_ became null
#> $ e: int 1, int 2     <- doubles came back as integers
```

Three type mutations in five fields. A type-tagged encoder over the in-memory object would tag `c`
as a **number** at write time and a **string** at read time: two `data_sha` for one payload, a
**P1/P2 violation** and exactly the silent divergence sv1 exists to prevent.

An earlier draft resolved this by normalizing through `serialize -> parse -> encode`. **Superseded**
-- see 7.3, which eliminates each mutation at its source instead, and so needs no serializer.

### 7.2 The encoding: hash-of-hashes over 3 primitives + 2 shape rules

Replaces an earlier "walk" formulation that dispatched on runtime type. That version had a
**structural gap** (see 7.2.1) which would have been frozen into the golden vectors. This
construction mirrors cv1's -- per-column digests, then hash their concatenation -- so both
references share one house pattern.

```
h(x) = sha256(x)

str(s)     = h( 0x01 || utf8(s) )
strset(v)  = h( 0x02 || concat( str(e) for e in sort(unique(v), method = "radix") ) )
map(m)     = h( 0x03 || concat( str(k) || strset(m[k])
                                for k in sort(keys(m), method = "radix") ) )

member(x)  = h( 0x04 || map(x.id) || map(x.tags) )
set(p)     = h( 0x05 || map(p.tags) || concat( sort(unique( member(m) for m in p.members ),
                                               method = "radix") ) )

data_sha   = h( 0x06 || utf8("datom-sv1") || set(payload) )
```

Domain-separation markers:

| Marker | Encodes | Note |
|---|---|---|
| `0x01` | string | UTF-8, no `NA` (R2.7) |
| `0x02` | string set | radix-sorted, deduped -- order and duplication are not identity |
| `0x03` | map | radix-sorted keys; serves both `id` and `tags` |
| `0x04` | member | `map(id) || map(tags)` |
| `0x05` | set | `map(tags) || concat(member...)` -- sorted and deduped like every other collection |
| `0x06` | payload root | prefixed with `utf8("datom-sv1")` |
| *retired* | **number** | not in the grammar -- nothing in a payload is arithmetic (R2.11) |
| *retired* | **boolean** | not in the grammar -- a boolean tag is the text `"true"` |
| *retired* | **null** | not representable -- absence is omission (R2.7) |
| *retired* | **`f64le` length prefix** | unnecessary: every intermediate is a fixed 32 bytes, so concatenation is already unambiguous |

Properties worth naming:

- **No runtime type dispatch, therefore no possible gap.** Every position's shape is fixed by
  *where it sits*, so the encoder never asks "what type is this?" and cannot have an unhandled
  answer. The old walk asked at runtime and so needed an exhaustive answer -- which it did not have.
- **Every collection is sorted and deduped. No exceptions.** So "is this position ordered?" is never
  a judgment call, and there is no carve-out to remember. An earlier draft made `members` the one
  unsorted `concat`; that is retired (R2.12 carries the three arguments). Sorting members means
  sorting their fixed-width 32-byte digests, which is deterministic and locale-free.
- **`id` is encoded with `map`, not positionally.** A fifth id field later is just another key: no
  positional convention, no absent-versus-empty question, and one encoder serves both `id` and
  `tags`. Id values are single strings encoded as one-element strsets -- the encoder stays out of
  validation's job, which separately enforces "id has exactly these four keys, each single-valued".
- **Framing is free.** `["a","b"]` is `h("a")||h("b")` (64 bytes) and cannot collide with `["ab"]`
  (32 bytes). So sv1 shares **no numeric primitive with cv1** -- `.datom_encode_numeric()` is not
  used at all, not even for lengths.
- **A single string equals a one-element set** (R2.13). `type: "output"` and `type: ["output"]` hash
  equal, because every map value passes through `strset`.

Pinned edges: absent `tags` and `tags: {}` encode identically (`h(0x03)` over an empty concat), and
the encoder must not depend on writers never emitting `{}`; **`strset(character(0))` is `h(0x02)`**
by the same argument (R2.17); duplicate values are not identity;
`radix` sort throughout for locale independence, which is **byte order -- no Unicode normalization is
applied** (R2.16); a zero-member set is still refused (R2.8); the three degenerate
spellings of R2.14 (duplicated member, empty tag value, empty-string tag value) are refused by
**validation** rather than encoded, so one fact has one spelling (R2.7, R2.14).

Exact byte rules are normative in `dev/datom_sv1_reference.R`.

#### 7.2.3 The consequence that lands outside the encoder (R2.15, R7.5)

Order- and shape-insensitivity means **several payload spellings share one `data_sha`**. Since
`data_sha` is also the storage address while `document_sha` hashes stored *bytes*, that is a
correctness question for the write path, not the encoder:

- **R2.15 canonicalizes before the local write** -- sort keys, sort and dedupe tag values, unbox
  singletons, sort and dedupe members -- so one content has exactly one spelling in git and in
  storage.
- **R7.5 keeps it true over time**: never re-emit a payload for a `data_sha` already in history
  (carry the recorded `document_sha` forward, mirroring
  `.datom_lookup_history_parquet_sha()` at `R/read_write.R:404-409`), and hold
  `datom_validate(fix = TRUE)` to the same rule, since it re-uploads from the clone.

Without both, the failure is a **refused read of a valid version**, surfacing long after the write
that caused it. It is called out here because it is a consequence of *this section's* decisions,
while the code belongs to Tasks 9 and 14.

#### 7.2.1 What was wrong with the walk (finding F-A)

The superseded formulation stated a closed value grammar:

```
value ::= string | [ string, ... ] | object
```

But the payload shape requires `members: [ {id, tags}, ... ]` -- an **array of objects**, which has
no production in that grammar. R2.10 reinforced the gap by naming exactly three taggable types, and
the encoder's `0x05` was labelled *string* array.

Mechanically an implementer could have read `0x05` as a generic array and let the element encoder
dispatch objects to `0x06`. But that contradicts both the tag's name and the stated grammar, and the
alternative -- inventing a fourth tag -- is an equally arbitrary choice. **Either would have been
frozen into the golden vectors**, which is precisely what the E1 gate exists to prevent. Same class
as review finding F4: two requirements that cannot both be true.

#### 7.2.2 Why tag-value order stopped being identity (finding F-B)

The superseded rule was "array order is identity", justified by *"member order is a curatorial
choice the user sees and controls"*. That is right for `members[]` -- and wrong for tag values,
which the same rule also caught.

A multi-valued tag models **simultaneous folder membership** (R4.6: "the motivating limitation of
folders is that an item cannot be in two at once"), which is inherently unordered. So
`domain: ["safety","efficacy"]` and `domain: ["efficacy","safety"]` would have produced different
`data_sha` -- a semantically null reorder minting a new **citable product version**.

This does not weaken Q1's whole-payload decision: a tag **edit** minting a version is intended; a
**reorder** is not an edit, it is the same fact restated. The ordering rule is now stated in three
explicit parts (R2.12) so nothing falls through to a generic default.

### 7.3 Why agreement holds without a serializer

Every mutation from 7.1 is now **unrepresentable**, not handled. There is no residual rule to get
wrong:

| Mutation | Status |
|---|---|
| doubles return as integers | **cannot arise** -- no numbers in the payload (R2.11) |
| `NA_real_` becomes the string `"NA"` | **cannot arise** -- no numbers, and `NA` aborts (R2.7) |
| `NA_character_` becomes `null` | **cannot arise** -- `NA` aborts; `null` has no marker, absence is omission |
| scalar vs length-1 array indistinguishable | **immaterial** -- the two hash **equal** (R2.13), so the question no longer exists |

The fourth row is the change from the previous draft, which handled it with an explicit atomic-vs-list
rule. Making a single string and a one-element set hash identically dissolves it instead -- and does
so for the same reason tag-value order was dropped: both spellings state one fact, so distinguishing
them would mint a citable version over syntax.

**One residual condition remains, and it is about structure rather than leaves.** The read path must
parse with **`simplifyVector = FALSE`** so `members[]` stays a list of records instead of collapsing
into a data frame. **Both backends already do this deliberately** -- `R/utils-local.R:110` and
`R/utils-s3.R:209`, the latter documented as "keep lists as lists (matching S3 behavior)". Leaf-level
simplification no longer matters at all, because leaves are order-, duplication- and
shape-insensitive.

So P28's goal is reached **completely**: type ambiguity is not merely handled, it has nowhere left to
live.

### 7.4 sv1 does not inherit the `metadata_sha` emitter exposure

Section 16 records that `metadata_sha` hashes `jsonlite::toJSON()` output, so a jsonlite formatting
change could silently re-mint every metadata hash. That concern is filed separately and remains
open **for `metadata_sha`**.

**It does not apply to sv1**, by construction: no emitter is in sv1's identity path. `jsonlite` --
or anything else -- may format the **stored** payload file however it likes, because stored-byte
integrity is `document_sha`'s job, a separate hash over actual bytes. **Identity and storage
integrity never share a dependency.** That separation is the whole point of Q5's resolution, and it
is what lets the stored file stay pretty-printed and human-diffable (R6.1a) without touching
identity.

### 7.5 The five questions, resolved

Owner-decided 2026-08-15. No open questions remain; E1's gate is now a **design review of the encoding
specification**, not a debate.

| Q | Question | Decision |
|---|---|---|
| **Q1** | whole payload or member list only | **whole payload** -- members *and* their tags. A set is citable; "same cite, different tags" would lie to the consumer. A tag edit minting a version is **intended** (R2.6, AC2) |
| **Q2** | `NA` / `""` / `null` encoding | **dissolved** -- absence is **omission**; a literal `NA` is an **error**, not an encoding. Goldens carry the refusal case (R2.7) |
| **Q3** | empty set legal? | **refused**, mirroring cv1's zero-dim abort. Marginal utility, murky semantics; cheap to relax, awkward to retract (R2.8, AC5) |
| **Q4** | `schema_version` in the payload? | **no** -- it describes the container, not the content. In identity it would re-mint every set on a format bump (R2.9) |
| **Q5** | which serializer is canonical | **neither -- no serializer in the identity path.** Deterministic walk of the parsed payload (R2.10, section 7.2) |

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
(`.datom_read_parquet()`, `R/read_write.R:233`). A set read must not parse an unverified payload.

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

Write side -- **three** sites (an earlier draft said two and missed the third):
- `.datom_update_manifest_entry()`, `R/sync.R:755,759-766` (entry + summary)
- `.datom_update_manifest_entry()`, `R/sync.R:721` -- the **skeleton built when `.datom/manifest.json`
  is absent**: `list(project_name = ..., tables = list(), summary = list())`. Verified in the tree.
  Left unrenamed, a repo with no local manifest writes a `tables` key *after* the rename -- the exact
  writer/reader disagreement E2 exists to prevent, and it reproduces only on a fresh or repaired
  repo, so per-chunk tests on an existing fixture pass.
- `datom_init_repo()`, `R/conn.R:522-527` (seed)

Read side -- six sites across four files:
- `datom_list()`, `R/query.R:62,89`
- `datom_status()`, `R/query.R:458`
- `.datom_status_input_files()`, `R/query.R:562,573`
- `datom_summary()`, `R/summary.R:61`
- `datom_sync_manifest()`, `R/sync.R:378,396`

`datom_validate()` reads the manifest only for `project_name` (`R/validate.R`,
`.datom_validate_project_name()`) so it is unaffected by the rename itself -- but it is affected
by R11 (kind branch), which is why #89 groups them into one escalation moment.

**This is the second escalation flag** (section 12): the rename must land atomically across all
**nine** sites (3 write + 6 read) plus their tests. A partial rename yields a manifest whose writer and reader
disagree, which presents as "everything looks fine, `datom_list()` is empty."

**The enumeration above is the state before Task 5** and is kept because it is the verified survey
the split was planned from. Task 5 collapses the read half to **one** site -- the shared reader
(R22.4) -- and the three hand-built empty-manifest defaults to **one** skeleton builder, leaving
Task 6 with the key rename, the field accesses on the returned document, the counters, and the
writer. Note the six read sites listed here are *reads*; the field accesses that follow them
(`R/query.R:62,89`, `R/query.R:458`, `R/query.R:573`, `R/summary.R:61`, `R/sync.R:396`) are what the
rename actually edits, and they remain.

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
- **`schema_version` must go in the `volatile` list** (`R/utils-sha.R:416`). Otherwise the v1->v2
  bump rewrites every existing table's `metadata_sha`, i.e. mints a spurious version for every
  table in every repo -- the exact failure #72 was fought over.
- **Do not overload `datom_version`.** It records the writing package version -- provenance, not
  contract. Most releases will not change the schema, so gating on it would fire on harmless
  upgrades.

### 10.1 The gate is only half the contract (found 2026-08-23)

The gate answers "is this document too new for me?". It does not answer "do I understand the shape
this document actually has?", and after the R8.1 rename those stop being the same question.

Every repo written so far declares no `schema_version` at all. The gate tolerates that as v1 --
correctly, that is R9.1 -- so the document passes, and the reader then looks for `artifacts` in a
file whose list is under `tables`. Nothing errors. `datom_list()` returns an empty frame,
`datom_summary()` and `datom_status()` report zero. It is the same observable failure E2 was raised
to prevent, reached through the front door rather than through a partial rename, and it would hit
every existing repo at once.

**Section 11's argument does not transfer.** There, a released 0.1.0 reader meets a v2 repo and its
list reads empty; that is accepted because a released binary has no check to fire and the recourse
is "upgrade". Here the upgrade **is** the cause, so there is no recourse to point at. The direction
section 11 analysed is outside our control; this one is entirely inside it.

Nothing self-heals it either. `.datom_update_manifest_entry()` (`R/sync.R:715`) writes no
`schema_version` on either branch, so stamping the version only in the absent-manifest skeleton
would leave upgraded repos v2-shaped while still declaring v1 -- the gate then stays silent on
exactly the repos it was built for. And a no-change write returns at `R/read_write.R:773`, before
the manifest is touched, so an idempotent re-run repairs nothing.

Two properties were recorded as satisfied by Task 4 while the rename was queued to falsify them:
**P10** and AC7's tolerate-older half. Both are restated, and R22 is what makes them true.

### 10.2 The upgrade: two shapes, one chain

Requirements R22 states the rule; the reasoning is here.

```
READING   read file -> upgrade IN MEMORY -> use          (disk untouched)
WRITING   read file -> upgrade IN MEMORY -> edit
                    -> stamp schema_version -> write to disk
```

**Reads tolerate old by upgrading in memory. Writes never tolerate old -- they upgrade on disk.**
Reusing the read-side rule on the write side is precisely how a file ends up half in each format: a
v2-shaped entry added to a document still declaring v1.

**Why not a scattered fallback.** `manifest$artifacts %||% manifest$tables` at each site duplicates
the same logic five times, and each copy also has to default `kind`. The next schema change then
edits five places, and the one it misses fails silently -- the same shape as the defect being
fixed.

**Why not a loud refusal plus a repair verb.** This is the option the compatibility posture would
normally favour, and it is unavailable for a specific reason: **readers cannot repair.** A reader
holds storage credentials and no git clone. Refuse a v1 manifest and a read-only analyst is stuck
until some developer happens to write, which converts a silent degradation into a hard stop for the
population least able to act on it. Upgrading in memory is the only shape that keeps them working.

**Why not a clean break with no migration.** There is a precedent for that -- the `datom-cv1`
identity spec changed the on-disk contract with no migration path, on pre-release grounds -- but it
does not carry here. That break was in *content identity*, where a re-export regenerates everything;
the manifest has no rebuild verb. And a break still has to be **loud** to be acceptable, which costs
a detection step; the transform beyond the detection is a few lines. So the cheap option and the
correct one are nearly the same code.

**One step per adjacent version pair.** `.datom_manifest_upgrade_v1_to_v2()` moves the key and
stamps `kind = "table"`; `.datom_manifest_upgrade()` reads the declared version and applies every
step up to current, in order. A v1 file reaching a v3 build runs v1-to-v2 then v2-to-v3. No direct
v1-to-v3 function is ever written: that shape needs one function per *pair* and grows with the
square of the version count, and each pair is a place for the two paths to disagree. Each step knows
only its immediate neighbour.

**A shipped step is frozen** (I30). It is written against files that exist unchanged in the world,
so re-tuning it to a later shape converts them wrongly -- and the conversion is silent, because the
output is well-formed for the wrong version. Same discipline as the frozen sv1 goldens, for the same
reason: the inputs are already out of our hands.

### 10.3 Stamp always, increment only on a break

Two questions were run together in review and separate cleanly (owner-decided 2026-08-23, R9.5).

**Stamping** the number costs nothing. It is excluded from identity (R9.3), so a stamped file mints
no version, and it lets any build say what shape it is holding. Do it on every manifest and every
per-artifact metadata document.

**Incrementing** costs every pinned build its access to everything written afterwards, because the
check is a refusal. So increment only when a change would actually break a reader. R9.5 carries the
test as a table; the short form is that renames, removals, meaning changes and restructures break,
and added fields do not.

The failure this prevents is specific: **incrementing on an additive change refuses a reader that
could have read the file perfectly well.** R's list access means an unknown field is simply never
asked for, so an added field is invisible to an older build -- unless a number tells it to stop.

**The number is a contract; `datom_version` is provenance.** One schema version spans many releases,
which is why the two fields stay distinct (R9.4) and why the mapping has to be published rather than
inferred (R9.6). A user holding a repo that refuses them has exactly one question -- *which datom do
I need?* -- and neither field answers it alone.

### 10.4 Where escape hatches are allowed, and where they are not

The manifest and per-artifact metadata look similar and behave completely differently under a
breaking change (R22.9).

**The manifest is derived, so it can be reconstructed.** Two hatches are available there, and both
are deferred to their own issues rather than built here:

- **Self-healing read**: when the artifact key a build expects is **absent**, rebuild the index from
  a storage listing instead of concluding the repo is empty. The trigger must be *absent*, not
  *empty* -- an empty list is what a new repo looks like and what a truncated file looks like, so
  rebuilding on empty would cost a listing per call on healthy repos and would hide corruption. A
  post-rename repo is distinguishable precisely because the expected key is missing entirely.
  Two constraints: a storage-only reader can only rebuild **in memory for that session** (it has no
  git and must not write to storage), and the rebuild must **say so, once**, pointing at the upgrade
  -- a rebuild that succeeds silently is itself a silent-degradation path, which is what section 10
  exists to remove.
- **Dual-write**: emit the old shape alongside the new for a declared window. The only hatch that
  helps builds **already released**, since it asks nothing of them. The failure mode to design
  against is a **stale** legacy copy rather than a leftover one: an old reader consuming an
  out-of-date list looks like it worked. Hence repo-level policy rather than a per-call argument,
  removal as a verb that deletes the copies in the same operation, and the sunset recorded inside the
  legacy file.

**Per-artifact metadata has neither hatch.** It is the source of truth, so there is nothing to
rebuild it from; and a legacy-shaped copy hashes differently from the recorded version, so change
detection (`R/read_write.R:343`) disagrees and an older build mints a version on every run --
dual-write would help old readers by breaking old writers. So for that file the rules are absolute:
additive only, forever.

**Git is a developer-side fallback only.** The manifest is committed, so a developer can always
recover a prior shape from history. A reader reads it from storage and holds no clone, so git is not
their recourse -- which is why the reader-side hatch has to exist independently.

### 10.5 Why the manifest keeps a truthful number (Design A)

Two self-consistent designs were on the table. **A**: the manifest's number keeps bumping and always
describes its shape, and what changes is the *reader's response* -- warn and rebuild instead of abort.
**B**: the manifest carries no number at all and dispatch is purely by shape.

**A chosen** (owner-decided 2026-08-23). Three reasons, in increasing weight:

1. Under B the number would be stamped and then frozen, so a file would read v2 while carrying a v5
   shape. A number that no longer describes the shape is worse than no number.
2. Under B the upgrade chain has exactly one step forever, and R22.5's one-step-per-pair generality is
   never used -- so the concept is paid for and not exercised.
3. **Decisive: B cannot distinguish corruption from the future.** A truncated manifest and a
   future-shaped manifest both present with the expected key missing, so both would trigger a rebuild.
   That directly contradicts the requirement that a corrupt manifest still fails visibly (AC37d). The
   number is the only thing that separates the two.

What A costs is nothing: the response change is local to one reader, and the reads-limp / writes-stop
split then falls out of a single rule instead of two.

### 10.6 The writer side: a vocabulary check, not a version comparison

R22 keeps readers working. It does nothing about a **writer** that does not understand a document,
and the schema number cannot fill the gap: adding a content-bearing field is reader-safe and
writer-breaking (writers recompute identity at `R/read_write.R:343`), the format has not changed, so
the number must not move and there is nothing to refuse on. One number cannot encode "newer but still
readable."

**The evidence is in the file.** A build inspects the top-level keys it is about to write and refuses
if it meets one it cannot classify. No version comparison, no configuration, no network.

Chosen over a declared minimum writer version as the *primary* mechanism for one reason:
**it cannot be forgotten.** A floor only protects a repo if somebody remembers to raise it; the
vocabulary check fires on the evidence whether or not anyone did anything. The floor is kept as the
escape hatch for the two cases the vocabulary check structurally cannot see -- a **meaning** change
that adds no field, and a policy block for a non-format reason ("0.1.4 wrote bad hashes").

**Coverage is complementary and neither mechanism is sufficient** (R23.5): the vocabulary check
catches additions and renames; the number catches removals, type and meaning changes, and container
restructures, none of which introduce a new name. Documenting either alone oversells it.

**Append-only is the whole discipline** (R23.2). A build must never stop recognising a name that has
ever existed, including names it no longer writes. A build that forgets a name meets an *older* file,
fails to classify a key it should know, and refuses it -- blocking the **upgrade** direction, the one
direction that must always work. Retire by marking, never by deleting.

**And the upgrade direction is structurally safe**, which is worth stating once so nobody adds a
guard for it: a newer build's vocabulary is a superset of every older one's, so it cannot meet an
unknown name. The check is incapable of firing on the upgrade path, and directional logic would be
dead code guarding an unreachable state.

**The accepted cost** (R23.6): every release that adds any field forces a fleet-wide writer upgrade,
cosmetic additions included. Writes are infrequent, done by few people, and they change content. A
false refusal costs one person an install; a miss costs corrupted data.

**This changes #100's justification.** The allowlist was filed as "older writers keep working". After
this decision they do not, by design. What it now buys is that **readers compute correct identities
and a repo does not accumulate spurious versions** -- both still true, and the earlier framing must
not survive into the implementation.

### 10.7 The write-path entry sequence

Stated once, so the pieces compose. All of it sits directly after the `datom_conn` class check and
**above** the two routing returns at `R/read_write.R:687` and `R/read_write.R:691` --
`.datom_sync_data_metadata()` mirrors the whole manifest to storage (`R/sync.R:177`) without ever
reaching the manifest-writing step, so anything placed after the router misses it.

```
1. fetch (cheap, no merge) to refresh upstream refs
2. floor check against project.yaml on the conn      -> refuse if below (R23.3)
3. read the manifest through the one reader
     -> schema check, refuse newer                    (R22.10, before the chain)
     -> run the upgrade chain in memory
4. expected key still absent after the chain?         -> refuse (R23.4)
5. vocabulary check on the CLONE's copies of those      -> refuse if unclassifiable (R23.1, R23.1a)
   documents (local file reads, no network)
6. proceed
```

**Step 5 reads the clone, not storage, and that is load-bearing.** The sequence has the manifest in
hand by step 3, but it does **not** have per-artifact metadata: `datom_write()` does not touch the
stored copy until pipeline step 4, inside `.datom_has_changes()`. Reading the clone's
`{name}/metadata.json` closes that gap with a local file read instead of a storage round trip, works
for the mirror-everything route where there is no single artifact name, and targets the copy a pull
from a newer collaborator actually lands in. Full argument and the two rejected alternatives are in
R23.1a.

All six happen **before any hashing, any local file write, and any commit**, so a refusal leaves no
partial state. That placement is the point: the spec's own argument is that aborting mid-pipeline
leaves a half-finished write, which is worse than the disagreement being prevented.

**Two notes on the mechanics.** The step-7 pull inside `.datom_git_push()` stays as the backstop for
the genuine race -- a floor raised between the entry check and the push -- and abort-after-commit is
acceptable for a rare race while unacceptable as the primary mechanism. And a write cannot reach
storage without a successful push (`.datom_git_push()` aborts on failure, `R/utils-git.R:267-277`,
and the storage steps are 8-10), so an unverifiable floor at the door is caught there; the residual is
narrow -- fetch fails, push succeeds.

**Prerequisite defect.** `.datom_check_git_current()` returns from its fetch-failure *handler* rather
than from the function (`R/utils-git.R:422-429`), so after a failed fetch it continues and compares
HEAD against stale cached refs -- an offline user with stale-ahead refs gets a hard abort where the
comment intends a warning. Fixed as its own change before anything sits on that function.

**The failure-kind split is the load-bearing part** (R22.4). Task 4 found three readers wrapping
their manifest read in a handler that softens failures, and a check placed inside one reworded the
upgrade instruction as "could not read manifest" -- `datom_status()` went further and downgraded it
to a warning while continuing. Task 4 held the line with a comment at each site. One shared reader
that **returns** IO failures as data and **throws** schema refusals holds it structurally instead:
there is no handler for a caller to place the check inside, and callers keep their differing IO
policies because the IO outcome is a value they inspect. AC32 tests both halves together, because
the regression is a trade between them.

---

## 11. Compatibility analysis

### Why `parquet_sha` is not renamed

`.datom_read_parquet()` guards verification with (`R/read_write.R:233`):

```r
if (!is.null(parquet_sha) && nzchar(parquet_sha)) { ...verify... }
```

A 0.1.0 reader hitting metadata that used a different field name resolves `parquet_sha` to
`NULL` and **skips integrity verification entirely**, reading happily. For an audit-oriented
package that is worse than an error -- and it is not hypothetical: the reader/developer split
deliberately supports different install cadences, so an unupgraded analyst reading data written
by an upgraded data manager is a **supported configuration**.

Note `parquet_sha` is in the `volatile` exclusion list (`R/utils-sha.R:416`), so a rename would
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

**The mirror-image direction is not acceptable, and was missed here until 2026-08-23.** The table
above reads a released 0.1.0 reader against a v2 repo. Reverse it -- a current build against a v1
repo -- and the observable outcome is identical, an empty list and a zero count, but the excuse is
not: nothing about that case is outside our control, and the user's own upgrade is what caused it.
See 10.1 for the analysis and 10.2 for the remedy (R22). Reading this section as blanket permission
for a quietly-empty list is the mistake to avoid; the permission is specific to readers we cannot
change.

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
documents.

Section 7 carries **one hard constraint, and all questions are now resolved** (owner-decided
2026-08-15; see section 7.5).

- **Constraint (stands)**: the hash domain is the **parsed-JSON data model**, because the in-memory
  and round-tripped R objects differ in type (`NA_real_` becomes the string `"NA"`; doubles return
  as integers) and a type-tagged encoder would otherwise produce two different `data_sha` for one
  payload. Surfaced in review, demonstrated against the branch. Its *mechanism* changed with Q5:
  each mutation is now eliminated at source rather than normalized away by a serialize/parse cycle
  (section 7.3).
- **Resolved**: **Q1** whole payload (members *and* their tags); **Q2** `NA` is
  an error and absence is omission; **Q3** empty set refused; **Q4** `schema_version` excluded from
  the payload; **Q5** no serializer in the identity path -- a deterministic walk of the parsed
  payload.

**The gate for Task 2 was a design review of the encoding specification, not an open-question
debate -- and that review is COMPLETE (2026-08-17).** It covered the three things named: the exact
byte rules in 7.2, whether the domain-separation marker table leaves a collision surface, and
whether the goldens cover the agreement cases in 7.3.

**Outcome: the encoding is sound; four additive deltas were needed, none a redesign.** Verified
clean -- domain separation (one marker byte per constructor, so cross-type collisions reduce to
sha256 collisions), "framing is free" (fixed-width entries make every concatenation unambiguous
without length prefixes), radix collation as byte order, and `id`-vs-`tags` slot separation.
Applied: member order removed from identity, canonicalization before the local write, the
`document_sha` byte-identity rule, no Unicode normalization, the empty-`strset` pin, and a
19-finding consistency sweep. The goldens still freeze the encoding -- changing it afterwards
requires a conscious `datom-sv2` bump, exactly as cv1 documents. **Task 2 is cleared to implement.**

*(A sixth question -- whether a set should carry a transitive member closure -- was raised and then
**retired**. It existed only to avoid a traversal, and per R4.3 datom does not traverse. See
section 20.11.)*

**Trigger type**: design spot-check before committing to a large or cross-cutting chunk.

### E2 -- Manifest namespace change (`tables` -> `artifacts`) -- Task 6

**Why**: touches `datom_list()`, `datom_summary()`, `datom_status()`, and the sync manifest
updater **together** -- **nine** verified call sites (3 write + 6 read) across four files (section 9), plus their
tests. A partial rename yields a writer/reader disagreement that presents as "everything looks
fine, the list is just empty," which is the failure class the `schema_version` gate exists to
prevent and which no test will catch unless it is written to.
**Scope grew after Task 4** (2026-08-21): the task also inherited the **write-side**
`schema_version` check -- an older build writing into a newer repo, which is the more damaging
direction and the one this rename makes concrete -- and the consolidation of the duplicated
manifest read across the three reader sites. Both are in Task 6's bullets.
**Two corrections from the cold-start audit** (2026-08-21), recorded here because this section is
the escalation brief: `datom_validate()` does **not** read the artifact key (its only manifest read
is `project_name`; artifact enumeration comes from a storage listing), and three **decoy** sites are
return-value fields also named `tables` (`datom_sync()`, `datom_validate()`, `datom_status()`
results) which a `grep` sweep hits and which R8 does not rename.

**Trigger type**: design spot-check + purity audit after the change lands.

**DISCHARGE, 2026-08-23.** The design spot-check was performed before implementation and its
findings are recorded in three places: this section, section 10.1 / 10.2 (the transition it
uncovered), and Task 6's `DESIGN AUDIT, 2026-08-23` bullet. It changed the plan in four ways.

1. **One blocking gap**: no v1-to-v2 transition existed, so the rename would have blanked discovery
   on every existing repo through the front door (10.1). New requirement R22, new invariants
   I28-I30, restated P10, new P34, P35, AC30, AC31, AC32.
2. **The phase is now two tasks.** Task 5 lands the single reader and the single skeleton builder
   and changes nothing observable; Task 6 renames the key in that one place. Reason: as one task it
   carried a nine-site rename, a write-side refusal, five counter filters, two read consolidations,
   the transition, and a fixture sweep across ten test files -- and its failure mode is silent, so a
   green suite would not have distinguished a working implementation from a broken one.
3. **Three corrections of substance**: five counters widen to include sets rather than three; the
   `kind` column has to reach `datom_list()`'s two empty-result returns, not only its populated
   path; and the write-side refusal must sit above the two routing returns in `datom_write()`,
   because one of them mirrors the whole manifest to storage without reaching the manifest-writing
   step.
4. **Two acceptance criteria removed from the task**: AC4 needs `datom_write_set()` (Task 9) and
   AC22 belongs to Task 11, where both are already claimed. The writer half of the schema gate is
   what this task genuinely owns.

**Trigger type on the model dimension is discharged differently from E1.** The working model is
already the most capable one available to the owner, so there is no escalation step to take; the
flag is answered by an independent close review of the spec before implementation, which the owner
owns. Recorded so the flag does not read as unaddressed.

A third, softer moment: **test coverage review before spec completion** (Task 16), per the third
standing escalation trigger. The full acceptance-criteria set plus a new hash regime is a lot of
surface to claim covered.

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
| **I10** | **Member resolution is one level deep. No datom operation traverses the member graph** -- not `datom_read_set()`, not `datom_validate()`. A member that is a set is returned as a pointer, never expanded. |
| **I10a** | The member graph is **acyclic by construction**, because a member pins an already-existing immutable version. No cycle detection, visited set, or depth limit is required or permitted to creep back in as "defensive" code. |
| **I11** | No credentials in the payload, metadata, manifest, or any set-related file. |
| **I12** | `table_type` remains validated to exactly `"imported"` / `"derived"`. `kind` is a separate axis and must not be smuggled into it. |
| **I13** | `data_sha` for a set is **defined on the parsed-JSON data model**, and any path that computes it -- including the write path, which necessarily starts from an in-memory R object -- must agree with that definition. Agreement is by construction, not by a serialize/parse pass (R2.5, design 7.3). Restated after the sv1 delta: the earlier wording ("never over the raw in-memory R object") would have mandated the normalization pass the delta removed, and contradicted AC13. |
| **I14** | ~~The public `datom_storage_write_json()` cannot write a datom-managed key.~~ **RETIRED 2026-08-18 with the write export (R12.4a).** The general clause it specialised survives as **P18** and is now satisfied structurally: datom exposes no general-purpose storage write at all, so there is no public path around git-gates-storage or integrity to constrain. Revive with the export. |
| **I15** | `datom_write_set()` refuses unless the repo declares `mode: product` and the set name matches `project.yaml`'s `set:` field. Checked before any hashing or IO (R10.3a). |
| **I16** | A datom **machine-moment** commit never stages a path outside the written artifact's files and `.datom/**`. Non-datom repo content is invisible to datom's git operations except via `datom_repo_commit()` (R15) and `include_paths` (R12.5). |
| **I17** | **datom is the single git-mutating actor** in a datom repo. Downstream packages never import `git2r`; every stage / commit / push / pull goes through a datom export. Writing files on disk is not a git operation and needs no datom API. |
| **I18** | `include_paths` content is **git-only**. It is never mirrored to storage; the storage namespace contains datom artifacts and nothing else. |
| **I19** | An idempotent (no-change) artifact write **never** creates a commit, regardless of `include_paths` state. Idempotency has no side channel. |
| **I20** | **Every git mutation datom offers is expressible without implying another.** Committing does not force a push (`push = FALSE`), and pushing does not require attempting a commit (`datom_repo_push()`). A caller must never have to pass through an add-all path to achieve a push. |
| **I21** | **Git is the history mechanism.** Anything history-shaped datom writes is a projection for git-less consumers, always derived from git, never the source of truth. If a consumer holding the repo would use it to answer a history question, it is wrong (R20). |
| **I22** | **`commit_sha` is derived, never authored.** The write path takes it from the commit it just made; the repair path re-derives it from `git log`. No code path may drop it, and none may treat the stored value as the only copy (R21.7). |
| **I23** | **A version is content-derived and code-invariant**, identically for tables and sets. Nothing code-derived -- not a commit SHA, not a code or environment hash -- may enter `metadata_sha` or a payload (R21.1, R21.4). |
| **I24** | **The payload is text-only** (R2.11): every leaf is a UTF-8 string or an array of them. No numbers, booleans, `null`, or nesting beyond the fixed shape (R2.12) may be admitted -- not as a convenience, not "just for this field". Admitting one reopens an encoder rule and widens the golden matrix. |
| **I25** | **No navigation or view structure is stored.** Folder-like hierarchy is a projection over tags computed by the consumer (R4.7). datom stores tag facts and takes no position on hierarchy. |
| **I26** | **No non-canonical payload ever reaches disk.** `datom_write_set()` canonicalizes (R2.15) before hashing, committing, or mirroring, so `{name}/set.json` and `{name}/{data_sha}.json` always hold the canonical form. No code path may write a caller's payload verbatim. |
| **I28** | **No code reads a manifest field off a raw document.** Every manifest read goes through the one internal reader, which applies the upgrade chain first, so no caller can observe a pre-current shape (R22.2, R22.4). The two named exclusions in R22.6 do not read the artifact key at all. |
| **I29** | **`schema_version` on disk always describes the shape the file actually has.** A write upgrades before it stamps, and never stamps a version onto a document it did not upgrade (R22.3). A file half in one format and half in another is the state this forbids. |
| **I30** | **A released upgrade step is frozen.** `.datom_manifest_upgrade_v1_to_v2()` and every later step are never edited once shipped, not even to tidy them -- they are written against documents that exist unchanged in the world, and mis-converting one produces a well-formed file for the wrong version, i.e. a silent corruption (R22.5). |
| **I31** | **The field vocabulary is append-only.** No build may stop recognising a field name that has ever existed in a datom-owned document, including names it no longer writes; retirement is a marking, never a deletion. A build that forgets a name refuses an **older** file and blocks the upgrade direction (R23.2). Same freeze rule as I30, and it carries the same weight. |
| **I32** | **The schema check runs before the upgrade chain, always.** A document declaring an unsupported version must never reach the dispatcher -- there is no step for a version this build does not know (R22.10). |
| **I33** | **A writer never overwrites a document whose shape it cannot reach.** If the expected key is still absent after the upgrade chain has run, the document belongs to a lineage this build cannot produce; refuse rather than rewrite it in an older shape (R23.4). The reader's response to the same condition is the opposite -- rebuild -- and that asymmetry is the reads-limp / writes-stop rule, not an inconsistency. |
| **I34** | **A write refusal leaves no partial state.** Every forward-compatibility refusal -- floor, schema, unreachable shape, unclassifiable field -- happens before any hashing, any local file write, and any commit (design 10.7). Aborting mid-pipeline leaves a half-finished write, which is worse than the disagreement being prevented. |
| **I27** | **The bytes at `{name}/{data_sha}.json` are written once and never rewritten.** Any path that could re-upload -- a repeat write, a revert to older content, or `datom_validate(fix = TRUE)` -- reuses the stored object and carries the recorded `document_sha` forward rather than recomputing it (R7.5). |

---

## 14. Correctness properties

Tagged so tests can reference them, following the #72 spec's convention.

| Tag | Property |
|---|---|
| **P1** | For a fixed member list and payload, `data_sha` is identical across R versions, `jsonlite` versions, platforms, and architectures. |
| **P2** | Two sets with equal semantic content have equal `data_sha`, regardless of the order keys were inserted into the payload object. |
| **P3** | Two sets differing only in **member order** have **equal** `data_sha`. Members are sorted by digest, so arrangement is not identity -- the same rule as tag values (R2.12). This **reverses** an earlier property that made member order identity; the three arguments are in R2.12. |
| **P4** | Two sets differing in any member's `version` have different `data_sha` (AC3). |
| **P5** | **Domain separation holds**: no two encodings from different positions collide -- string, string-set, map, member, set and payload-root each carry a distinct marker (`0x01`-`0x06`, design.md 7.2). Restated after the sv1 delta: the earlier phrasing ("no string/number/boolean/null value collides") is now vacuous, since numbers, booleans and `null` are not in the grammar at all (R2.11, P28). |
| **P6** | **Concatenation confusion is impossible**: no two distinct sets, maps or member lists produce the same byte sequence. The mechanism changed with the sv1 delta -- from explicit length prefixes to **fixed-width framing**, since every intermediate is a 32-byte hash, so `h("a")||h("b")` (64 bytes) cannot collide with `h("ab")` (32 bytes). |
| **P7** | Re-writing an identical set is a no-op -- no new version, no new payload object, no storage write (AC2). |
| **P8** | A set's `data_sha` is independent of every volatile and container field: `created_at`, `datom_version`, `schema_version` and `document_sha`. (`size_bytes` was listed here before R1.4 removed it from set metadata entirely, so the claim was vacuous.) |
| **P9** | A payload whose stored bytes do not match `document_sha` is refused before parsing. |
| **P10** | A v2 reader against a v1 repo returns the same artifacts 0.1.0 did -- same names, same versions, plus the additive `kind` column. **Restated 2026-08-23**: the earlier wording credited this to the gate's toleration of an absent `schema_version` alone, which the R8.1 rename falsifies. Toleration lets the document through; the in-memory upgrade (R22.2) is what makes what comes through intelligible. The property is defended in Task 6 and tested by AC30. |
| **P34** | **The upgrade chain is order-preserving and idempotent.** Applied to a document already at the current version it is the identity; applied to an older one it runs every step from the declared version upward, in sequence, and applying it twice equals applying it once (R22.5). |
| **P36** | **Identity ignores what it does not name.** Adding any field to a metadata document leaves every existing `metadata_sha` unchanged, and two documents differing only in fields outside the identity list hash equal (AC33). The converse is what the classification test defends: no field a builder can emit is left unclassified, so identity cannot silently stop responding to real content. |
| **P37** | **The upgrade direction always works.** For any document written by an older build, a newer build reads it, upgrades it, and writes it without refusing -- because a newer build's vocabulary is a superset of every older one's and the chain can reach the current shape (R23.2a, R23.4). No sequence of releases can produce a repo that the current build can read but not write, unless a floor deliberately says so. |
| **P38** | **Information is never destroyed by a build that does not understand it.** A field a build cannot classify survives that build's write unchanged, at every level it can appear (R23.8, AC34). |
| **P35** | **A schema outcome is never absorbed into a caller's IO handling.** For every manifest reader, an unsupported version produces its own deliberate outcome while an ordinary IO failure keeps that caller's existing policy -- because the shared reader **returns** the second and does not route the first through it (R22.4, AC32). No arrangement of caller-side handlers can reword it as "could not read manifest". **Restated 2026-08-23 by Design A; the earlier wording is superseded**: it said the reader *aborts* and that no handler may convert the abort into a warning, which forbade the very remedy Design A adopts -- for a **manifest reader** the outcome is now warn-and-rebuild (R22.11). The invariant was never the abort; it was that the schema outcome is not disguised as an IO failure. The abort itself still holds for per-artifact metadata at any role, and for the manifest on the writer path. |
| **P11** | A reader whose supported schema is below a document's declared version is **stopped, not degraded**, at both entry points -- with the manifest's stop being warn-and-rebuild once Task 22 exists (R22.11) and the per-artifact metadata stop being an abort, always. **Scoped 2026-08-23**: the earlier wording said a v1 reader aborts at both entry points, which is vacuous for the only real v1 reader (0.1.0 has no check to fire -- AC7's mechanism note already says so) and wrong for any future build pinned below current, which warns and rebuilds on the manifest. The per-artifact half is the half that is testable and absolute. |
| **P12** | The in-package sv1 implementation and `dev/datom_sv1_reference.R` agree on every golden, on x86_64 and arm64. |
| **P13** | Writing a set never mutates any member's metadata, history, or manifest entry. |
| **P14** | `datom_validate()` reports `ok` for a healthy set and a non-`ok` status naming the specific defect for a missing payload vs an unresolvable member (distinguishable, not merged). |
| **P15** | **Write/read agreement**: `data_sha` computed from the in-memory payload equals `data_sha` recomputed after the payload has been stored and read back, for every payload (R2.5, AC13). The hazards this property once enumerated -- `NA_real_`, `NA_character_`, whole-number doubles, scalar-vs-length-1 -- are **no longer covered here because they are unrepresentable or immaterial**: see P28. The only residual condition is structural, that `members[]` parses as a list of records rather than a data frame (R2.5). |
| **P16** | Every set read and every set validation is bounded by **one level**: the number of storage reads is a function of the set's own direct member count and never of the depth or size of the tree beneath it (R4.3, AC15). |
| **P17** | A set payload version is reconstructible from the **git clone alone**, with no storage access (R6.1b). **Strengthened by `include_paths` (R12.5):** in a `mode: product` repo, checking out a set version's commit yields the data pointers, the derivation logic, **and** the environment that produced them -- one clone, one checkout, full reproduction. Without `include_paths` the guarantee covers pointers only. |
| **P18** | **No sequence of public API calls can place an artifact's storage state ahead of its git state** (I5). Restated 2026-08-18: it previously named the newly exported `datom_storage_write_json()` as the thing to defend against, and that export is deferred (R12.4a), so the property now holds because every public write is a purpose-built verb that commits first -- not because a generic write is fenced. The property itself is unchanged in force and is the reason the deferred export cannot be revived without re-deriving its refusal list. |
| **P19** | A machine-moment commit's tree excludes every non-datom path, and the working tree's foreign dirty files are left dirty -- neither committed nor cleaned (I16, AC16). |
| **P20** | A set write with `include_paths` produces **exactly one** commit containing payload + metadata + the listed paths, and storage afterward holds only datom artifacts (I18, AC18). |
| **P21** | For any `include_paths` state, an unchanged set produces no commit and no new version (I19, AC19). |
| **P22** | No public datom API stages a path the caller did not either own (datom artifacts) or explicitly enumerate (I16, I17). |
| **P23** | **Push is convergent**: for any repository state, `datom_repo_push()` leaves the remote containing every local commit on the branch, and is safe to call repeatedly. No sequence of public calls leaves the remote silently behind after a `push = TRUE` request (R15.5, R15.8, AC21). |
| **P24** | **Intent to push is expressible without risking a commit.** No caller must route through an add-all code path in order to push (I20, R15.8). |
| **P25** | **A set version's change is expressible as a git diff** on a single stable path, at member granularity -- not as a whole-file addition (R6.1a, AC24). |
| **P26** | **`commit_sha` survives every repair path.** No sequence of `datom_validate(fix = TRUE)` or metadata re-sync leaves the storage copy without it (I22, AC25). |
| **P27** | **A change that alters no content alters no version**, for tables and sets alike: modifying code or environment while producing identical content yields no new version and no change to any recorded `commit_sha` (I23, R21.2, AC26). |
| **P28** | **Type ambiguity is unrepresentable, not merely handled -- completely.** No payload can contain a number, boolean or `null`; and the last surviving ambiguity, scalar-vs-one-element-array, is dissolved by making the two hash equal (R2.13). No encoder rule for any of them exists, so none can drift (I24, R2.11, AC13, AC27). |
| **P29** | **The same tag facts support arbitrarily many folder projections**, and changing which projection a consumer applies changes no stored bytes and no version (I25, R4.7). |
| **P30** | **Nothing in a payload is ordered, and no collection counts duplicates.** Payloads differing only in the order or multiplicity of tag values, or in member order or member multiplicity, hash **equal**; a single string hashes equal to a one-element array (R2.12, R2.13, AC13 a-e). Member order is **no longer** an exception (P3). |
| **P32** | **One content has one byte spelling.** For a given `data_sha` there is exactly one canonical payload, in git and in storage, so `document_sha` is a function of `data_sha` and cannot go stale (R2.15, R7.5, AC29). |
| **P33** | **Tag text is byte-exact.** No Unicode normalization is in the identity path, so no Unicode version bump can re-mint a `data_sha`; NFC and NFD spellings are different tags (R2.16, AC13 f). |
| **P31** | **The encoder has no runtime type dispatch.** Every position's shape is fixed by where it sits, so there is no "what type is this?" question and therefore no unhandled answer -- the structural defect that finding F-A found in the superseded walk (R2.10, design.md 7.2.1). |

---

## 15. Alternatives considered

| Alternative | Verdict |
|---|---|
| **Flatten the collection into a long-format table** (`name`, `project`, `version`, `tag_key`, `tag_value`) -- would technically satisfy `datom-cv1`. | **Rejected**, but only on the first of its two original grounds. It would become a **data-layer artifact subject to lineage semantics** -- precisely what a set must not be. The second ground, "nested view config does not survive the flattening", **no longer applies**: there is no view config (R4.7). Note the shape it proposed was per-member text key-values, which is essentially what the payload now carries -- the objection was always the *layer*, not the shape. |
| **Build the collection outside datom, in the build package.** | **Rejected.** Duplicates version history, content addressing, dedup, ref resolution and governance, and the result still could not be referenced as a member of another collection. The composability loss is the one that cannot be worked around. |
| **Sibling `manifest$sets` node.** | **Rejected.** Makes cross-kind name collisions representable, requiring a guard that one typed namespace makes unnecessary. Also bolted-on -- a from-scratch design would have typed one namespace, since `tables` was only ever "the things in this repo." |
| **Rename `parquet_sha` to a kind-neutral name.** | **Rejected.** Section 11 -- silently disables integrity verification in released 0.1.0 readers. |
| **Dual-write `tables` alongside `artifacts` for one release.** | **Rejected.** `datom_read()` does not touch the manifest, so exposure is discovery-only; carrying a legacy mirror to protect a likely-empty user population is not worth the permanent schema clutter. Note this is about *forward* exposure (an old reader meeting a new repo) and says nothing about the reverse, which R22 handles by upgrading rather than by mirroring -- one shape on disk, converted on the way in. |
| **Read the old key inline where needed** -- `manifest$artifacts %||% manifest$tables` at each site. | **Rejected** (R22, section 10.2). Five copies of the same logic, each also needing to default `kind`; the next schema change edits five places and the one it misses fails silently. That is the shape of the defect being fixed, reintroduced as the fix. |
| **Refuse a v1 manifest loudly and ship a repair verb.** | **Rejected on who can act.** It is the option the compatibility posture normally favours, but **readers cannot repair**: a reader holds storage credentials and no clone, so a refusal strands the population least able to resolve it until some developer happens to write. Upgrading in memory is the only shape that keeps a storage-only reader working (R22.2, AC1). |
| **Declare a clean break -- no migration, pre-release grounds**, as the `datom-cv1` identity spec did. | **Rejected.** The precedent does not carry: cv1 broke *content identity*, where a re-export regenerates everything, whereas the manifest has no rebuild verb. A break also has to be **loud** to be acceptable at all, which costs the detection step; the transform beyond detection is a few lines, so the cheaper option and the correct one are nearly the same code. |
| **A declarative transform file that travels with the repo**, so an older build can translate a newer manifest back to the shape it knows -- data rather than code, one mapping per release hop, walked downward. | **Rejected, and it was the strongest alternative considered** (owner-proposed 2026-08-23). Three real merits: it is data, so it avoids executing code fetched from a data store; it composes exactly as the forward chain does; and it can hide a new concept entirely, so an old build never learns sets exist. Rejected on four grounds. (1) **The interpreter must ship in the old build**, so it cannot help anything already released -- the same wall it was meant to remove. (2) **The mapping format is frozen the day it ships**, so the first change it cannot express puts us exactly where we are today, now with a language to maintain as well: the wall moves up a level rather than away. (3) A rename map covers renames, moves and defaults; a meaning change, a container restructure or a concept split needs a transform, and supporting transforms means designing a small language. (4) **The cost is testing, not building** -- it is worth nothing unless CI installs historical releases and reads current repos through them, a matrix that grows with every release and is the first thing dropped under deadline. Decisive: its own simplest case, dual-write, delivers most of the value with no language, no interpreter, no frozen format, and it works for released builds. |
| **Do not stamp `schema_version` on per-artifact metadata**, to avoid future lockouts of pinned builds. | **Superseded by a better split, not rejected on the merits** (R9.5). The concern was correct -- a stamp on an additively-changed file refuses a reader that could have read it -- but the cause is *incrementing*, not *stamping*. Separating the two keeps the housekeeping benefit of always knowing a file's shape while removing the lockout, so both files are stamped and the number moves only on a genuine break. |
| **Treat a missing `kind` as `"table"`** in the counters, as a safety net. | **Rejected** (R22.8, owner-decided 2026-08-23). Every entry has a `kind` by the time a counter runs, because the upgrade stamps it. The net would therefore only ever fire when a read path skipped the upgrade -- and it would make that mistake produce roughly-correct numbers instead of visibly wrong ones, hiding the class of failure this spec exists to make loud. One line, reversible if a real case for tolerance appears. |
| **Reuse `datom-cv1` for sets.** | **Rejected.** Table-shaped and binary-framed; `nrow`/`ncol`/per-column digests do not generalize to a tree (section 7). |
| **Hash the emitted JSON bytes.** | **Rejected.** Reintroduces the #72 failure mode with `jsonlite` playing the role `arrow` played. |
| **`mode: "set"` instead of `mode: "product"`.** | **Rejected.** These repos also hold derived tables, so "product" describes the repo and "set" describes one artifact in it. |
| **A separate code/env repo -- a fourth repo per product.** | **Rejected.** Cross-repo pinning is **circular**: the code repo wants to record which set version it produced, and the set payload wants to record which code commit produced it -- one is always stale by one commit. A joint version requires one commit graph. Also doubles per-product repo cost, and P17 would then cover pointers only. See section 19. |
| **datom machine-moment commits use add-all.** | **Rejected.** Machine-chosen commit moments would snapshot arbitrary WIP state of human code. Add-all is correct **only** at human-chosen moments -- which is exactly what `datom_repo_commit(paths = NULL)` provides (R15.1). |
| **Downstream packages do their own git via `git2r`.** | **Rejected.** Two independent git actors in one repo eventually violate the git-gates-storage assumptions (competing pushes, unseen pulls, half-staged trees). Single writer: all mutation flows through datom's exposed surface. |
| **Keep member order as identity** (the earlier position), on the grounds that it is curatorial and the user sees it. | **Rejected.** It contradicted R4.7 (arrangement is presentation -- which is why no hierarchy is stored) and contradicted 7.2.2's own reasoning, which killed tag-value ordering for exactly this reason. Decisively: the expected producer is a **script**, so an insertion-order refactor in a build package would mint a new product version with byte-identical content -- a tool's incidental ordering becoming identity, i.e. the #72 failure class. What it was thought to buy does not survive: sorting is one `sort()` over fixed-width digests, and duplicate members are refused either way. Removing it also deletes 7.2's only carve-out. Full argument at R2.12. |
| **Normalize tag text to NFC before hashing**, so visually identical tags hash equal. | **Rejected** (R2.16). Unicode normalization tables are **versioned data that changes across Unicode releases**, so this puts a versioned third-party artifact in the identity path -- structurally the same failure as the parquet-serialization drift of #72, with the Unicode Consortium in `arrow`'s role. sv1 exists to have nothing versioned in its identity path (7.4). Also adds `stringi` to a deliberately lean `Imports`, and diverges from cv1, which already treats NFC-vs-NFD as identity-relevant. Recourse is caller-side. |
| **Canonicalize only at hash time, not before the local write** -- i.e. accept several byte spellings per `data_sha`. | **Rejected** (R2.15). `data_sha` is the storage address while `document_sha` hashes stored bytes, so multiple spellings at one address make `document_sha` unverifiable, and the failure surfaces late as a **refused read of a valid version**. It would also silently discard an author's reorder rather than visibly normalizing it. Canonicalizing at the source removes the ambiguity instead of managing it; R7.5 then covers the residual (emitter drift). |
| **Persist per-member digests in metadata**, as a `column_hashes` analogue, so a reader can tell which member changed between versions. | **Rejected -- the need is already met** (section 4). Nearly free to produce, since the hash-of-hashes computes `member()` as an intermediate anyway, and identity-safe (it would be volatile, like `column_hashes`). But it is strictly weaker than the payload diff it would compete with: it reports *that* a member changed, never *what*. `column_hashes` earns its place only because the alternative is downloading parquet -- possibly gigabytes -- and that argument does not transfer to a small text payload the reader can just fetch. There is also **no code to reuse**: `column_hashes` has no consumer in `R/` today and `datom_diff` is unbuilt (#73), so the "parallel with tables" is conceptual, not mechanical. The one case it genuinely wins is a **change timeline across many versions** (one `version_history.json` read instead of two reads per pair), at the cost of `N_members` x `N_versions` hashes in one file. Deferred rather than refused: the field is additive and volatile, so it can be added whenever that need becomes real, with no schema break. |
| **Move tags out of the payload into `metadata.json`**, hashing payload and tags separately with a pairing key, then a product hash over both. | **Rejected -- costs the most, buys nothing the above does not.** It requires a **stable per-member pairing key**, which is a new identity concept to specify, test and keep from drifting between two files. Every read then fetches both files and reassembles, and the folder-projection consumer (`dp$output$cm`) needs tags at read time regardless, so the split saves no IO. It also **reopens Q1** -- identity currently covers the whole payload including tags -- and would move tags under `metadata_sha`'s domain, i.e. back under the third-party emitter exposure that section 7.4 exists to escape. Directly contradicts the "a set is metadata-flavored, tags live in the payload" decision (section 4, R6.2). |

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

**Update (Q5 resolution, 2026-08-15)**: the inconsistency is now one-sided rather than mutual.
**sv1 has no emitter in its identity path at all** (section 7.4), so it does not inherit this
exposure. That removes the "cannot both be right" tension -- sv1 is clean by construction -- but it
*sharpens* the case for the separate issue, because `metadata_sha` is now the only hash in datom
whose value depends on a third-party formatter. Scope of that issue is unchanged; its priority
arguably rises.

---

## 17. Pathway impact

**Yes -- `dev/datom_pathways.md` needs a new route card** (R13.1):

> **Given a set + version, resolve its members.**
> `{name}/.metadata/{version}.json` -> `data_sha` + `document_sha` ->
> `{name}/{data_sha}.json` (verify `document_sha` **before** parsing) -> `members[]`, returned as
> **pointers**. Resolution stops there: a member whose `kind` is `set` is **not** expanded (I10,
> AC15). A consumer wanting the inner set issues a separate call against that set's own project.

Also update the existing read route to note the `kind` branch and the `schema_version` gate.
Every chunk records pathway impact or explicitly states "no pathway impact" (README maintenance
rule 8).

---

## 18. Independent spec review -- findings and resolutions

The spec was independently reviewed against the branch tip before Task 1 started. The reviewer
audited the spec's factual claims against the code rather than only reading the prose, and
confirmed: the unexported JSON helpers and their relative-key contract; **Deviation D1**; all
eight manifest sites at the cited lines; the stale-docstring claim; the volatile list; the
`datom_parent()` mirror table; the `.datom_validate_parents()` remedy pattern; `parquet_sha`
history persistence; and that no `schema_version` or `kind` exists in the code yet.

Findings accepted and resolved in the spec **before** implementation. Each was re-verified against
the code independently rather than accepted on assertion.

| # | Finding | Verified how | Resolution |
|---|---|---|---|
| **F1** | **I10 contradicted the cross-project cycle decision.** Section 5 said the write-time walk is best-effort across projects; I10 claimed globally that a stored set is never a cycle. | Logical audit of the spec against itself. **The claimed A1->B1->A1 sequence was asserted to be constructible; it is not** -- see the resolution. | **SUPERSEDED -- see section 20.11.** The contradiction was real, but it was resolved the wrong way: by *adding* a read-side visited-set + depth guard (R4.4, I10a, P16, AC15) rather than by testing whether either statement was true. **Neither was.** Members pin immutable versions, so cycles are structurally impossible, and datom resolves one level without traversing at all. All the added machinery, plus the depth limit, was removed. The correct resolution is R4.3 (one-level resolution) + R4.4 (acyclic by construction) + R4.5 (refuse self-reference). **Lesson recorded**: when a review surfaces a contradiction, check the premises before building something to reconcile them. |
| **F2** | **sv1's type-tagging reintroduces the ambiguity `toJSON` erased.** R cannot distinguish a scalar from a length-1 vector, and the JSON round trip mutates types, so a type-tagged encoder over the in-memory object disagrees with itself over the parsed payload. | **Reproduced on the branch.** The mutation is worse than reported: `NA_real_` becomes the *string* `"NA"`, `NA_character_` becomes `null`, and doubles return as integers -- three mutations in five fields. Confirmed `R/utils-sha.R:423-425` states type-agnosticism as the deliberate reason for the existing basis. | **Accepted and elevated.** Not a fifth open question but a **hard constraint** (**R2.5**, design section 7, **I13**, **P15**, **AC13**): the hash domain is the parsed-JSON model, normalized by construction. The reviewer's Q2 is recorded as a special case of it. A genuinely new **Q5** was added -- *which* serializer defines the canonical form -- because the constraint forces that choice into the open, and it couples to section 16. |
| **F3** | **Public `datom_storage_write_json()` could clobber managed keys**, silently bypassing git-gates-storage and integrity for datom-managed artifacts. | Read Task 3's stated hardening (conn check, key validation) and confirmed neither constrains the key namespace. | **RESOLVED DIFFERENTLY, 2026-08-18: the export is deferred, so the hazard is removed rather than fenced.** The finding was correct and its original resolution (below) was sound; it was superseded by asking a question the review did not -- *who still needs this export?* -- to which the answer was nobody, once `datom_write_set()` existed. Recorded because the lesson generalises: a review that hardens a capability can be right about the hazard and still miss that the capability is unnecessary. Original resolution, preserved because it is the starting point if the export is revived: **Accepted.** **R12.4a**: the write export refuses `.metadata/` segments and payload-shaped keys under existing artifact directories; reads unrestricted. New **I14**, **P18**. Settled as a public-contract decision in the spec, not at implementation time. |
| **F4** | **Set metadata field list was internally inconsistent** -- R1.3 said "exactly seven fields", the design section 4 matrix granted `size_bytes` and `custom`. A test written to one fails the other. | Diffed the two lists directly. | **Accepted.** Reconciled to R1.3's seven. `size_bytes` dropped because nothing consumes it for a set (`total_size_bytes` is tables-only; the entry carries `member_count`). `custom` dropped because tags/descriptions/view config live in the payload by R6.2, so a second channel means two places to look -- `datom_write_set()` gains no `metadata =` parameter. **R1.4** records both reasons; the matrix now states the reconciliation. Acceptance tightened to `setequal()` so an *added* field also fails. |
| **F5** | **R10's "one repo = one set" had no stated enforcement**, and the write-time nesting check assumed the set's name is known before the write -- which only holds if that check exists. (The nesting check is now just self-reference refusal, R4.5, but it makes the same assumption.) | Confirmed no requirement or task specified the check. | **Accepted.** **R10.3a** adds two gates: `datom_write_set()` requires `mode: product`, and the name must equal `project.yaml`'s `set:` field. Both run before any hashing or IO. New **I15**. |
| **F6** | `datom_read_set()` on a **table** was unspecified -- the converse of AC6. | Read R12.3. | **Accepted.** R12.3 now specifies both directions; **AC14** added. Without it, `datom_read_set()` on a healthy table reports a missing payload. |
| **F7** | **Git-side payload layout unspecified.** `governance.json` is a singleton current-state file; a set has N immutable content-addressed payloads, so the dual-pointer pattern does not transfer wholesale. | Read `R/governance_json.R` -- confirmed singleton at `.datom/governance.json`. | **Accepted, then SUPERSEDED -- see section 21.2.** The finding was right that the pattern does not transfer wholesale. Its original resolution -- git layout at `{name}/{data_sha}.json` with all historical payloads retained -- was **reversed**: git now holds one stable `{name}/set.json` so history is git's and diffs are member-level, and the retention rule is redundant because git retention is definitional. **P17** still holds, via `git show <commit>:{name}/set.json`. |
| **F8** | **AC4 mechanism** should read storage metadata, not the manifest (which can lag). | Confirmed `.datom_has_changes()` already reads `{name}/.metadata/metadata.json`. | **Accepted.** AC4 now names the mechanism and notes it costs no extra round-trip. |
| **F9** | **R8.1's example** omits fields real entries carry, and could be read as the full schema. | Confirmed against `.datom_update_manifest_entry()` (`R/sync.R:744-756`). | **Accepted.** R8.1 marks the example illustrative and enumerates the omitted fields. |
| **F10** | **AC7 wording** implied testing an installed 0.1.0 reader, which has no gate to fire. | Read AC7. | **Accepted.** AC7 restated to drive `.datom_check_schema_version()` with an above-`SUPPORTED_SCHEMA` fixture: test the gate, not the archaeology. |
| **F11** | **Set versions counted nowhere**; probably intentional but unrecorded. | Read R8.3. | **Accepted as intentional, now explicit.** **R8.3a** records the omission and its reason (holding the breaking surface to one key rename), so it is not later read as an oversight. |
| **F12** | **Stale docstring line numbers wrong** -- text is at ~105-108, 205, 413, not 95-97, and `read_write.R:393` contradicts the others. | **Re-verified**: `grep -n "task 5\.1" R/read_write.R` returns exactly `107, 205, 393, 413`. `95-97` is the function title. #89 had it wrong and the spec propagated it. | **Accepted.** R13.3 now carries a four-site table distinguishing the three stale sites from the one already-correct-and-contradicting site. |

**Not adopted**: nothing. Every finding held up on independent verification.

The reviewer noted the 2460 test baseline was unverified on their side; it was verified locally by
two `devtools::test()` runs on `dev` @ `b57cdba` (`FAIL 0 | WARN 0 | SKIP 0 | PASS 2460`), and
AC10 now records that.

**Net effect on the plan**: F1, F2 and F5 change what Task 2, 8, 9 and 10 must build; F3 changes
Task 3's public contract; the rest tighten tests and docs. F2 is the most consequential -- without
it, Task 2 would likely have shipped goldens for an encoder that disagreed with itself across the
round trip, and the golden vectors are the one artifact in this spec that is expensive to correct
after the fact.

---

## 19. The `mode: product` repo is the joint repo (code + env + datom artifacts)

Amendment recorded from the spec delta on #89 (2026-08-11), applied as D1-D8. This section holds
the decision, its rationale, the structural context, and the corrections the delta needs.

### 19.1 Decision

A downstream build package (`dpdev`, successor to the `pins`-based `dpbuild`) produces jointly
versioned **data + environment (`renv.lock`) + code (derivation logic)**. The open question was
whether that code and environment live in the datom-created `mode: product` repo or in a separate
fourth repo.

> **Decision: same repo.** The `mode: product` repo **is** the joint repo. There is no separate
> code/env repo. All git **mutations** go through datom -- downstream packages never import
> `git2r`. Writing files on disk is not a git operation and needs no datom API.

### 19.2 Rationale

1. **The joint version requires one commit graph.** In one repo, a single commit's tree contains
   derivation code, lockfile, table metadata, and set payload -- **the joint version *is* a
   commit**. Split across two repos, cross-repo pinning is circular: the code repo wants to record
   which set version it produced; the set payload wants to record which code commit produced it;
   whichever is written second, one of them is always stale by one commit. There is no ordering
   that resolves this, only conventions that hide it.
2. **P17 strengthens to a full reproduction guarantee.** With code and environment in the repo,
   checking out a set version's commit yields the data pointers, the logic, **and** the
   environment that produced them -- one clone, one checkout. Without this, P17 covers pointers
   only, which is a materially weaker claim for an audit-oriented package.
3. **Repo economics.** Marginal cost per data product is exactly **one** repo, identical to
   `dpbuild`'s joint repo. Source datom repos and the gov repo are shared org-level
   infrastructure, not per-product cost.
4. **Precedent.** `dpbuild`'s joint repo already held code + `renv.lock` + `.daap/` metadata
   together. What changes is only *who writes the metadata*, not the repo topology.

### 19.3 Structural context -- three ownership tiers

`dpdev` enforces a specific project structure (as `dpbuild` did), so non-datom content in a
product repo is not arbitrary. It is a known taxonomy:

| Tier | Paths | Written by | Committed at |
|---|---|---|---|
| datom artifacts | `{artifact}/**`, `.datom/**` | datom | **machine** moments (each write) |
| framework state | `dp/*.yaml`, `renv.lock` | build pkg via its API | **human** moments |
| guarded human code | `R/`, `tests/` | human, within build-pkg guardrails | **human** moments |

**This table is context for the reader, not a datom contract.** datom receives paths as opaque
arguments and must never validate, assume, or special-case `dp/`, `R/`, or `renv.lock` (R16).

Sketch of a `mode: product` repo, for orientation:

```
study001-adam/
  .datom/            project.yaml (mode: product, set: study001-adam), manifest.json
  .git/
  adsl/              metadata.json, version_history.json          <- datom artifact (table)
  adae/              metadata.json, version_history.json          <- datom artifact (table)
  study001-adam/     metadata.json, version_history.json,
                     set.json                                     <- datom artifact (set payload;
                                                                     stable path in git, R6.1a --
                                                                     storage holds {data_sha}.json)
  dp/                *.yaml                                       <- framework state
  R/                 derivation logic                             <- guarded human code
  tests/                                                          <- guarded human code
  renv.lock                                                       <- framework state
  input_files/                                                    <- gitignored, and refused
                                                                     anyway by mode: product
  .gitignore                                                      <- seeded by datom, appended
                                                                     to by downstream (R16)
```

### 19.4 Why the commit-moment distinction is load-bearing

`dpbuild`'s add-all commits were safe because **every commit was human-invoked at a deliberate
moment**. datom commits at **machine-chosen** moments -- inside every write, possibly mid-build.
Add-all there would snapshot arbitrary work-in-progress states of human code, producing commits no
human intended and a history in which a "data write" silently carries half-finished logic.

Hence the split that R14 and R15 encode:

| Moment | Who triggers | Staging rule | Mechanism |
|---|---|---|---|
| Machine | datom, inside a write | datom-owned paths only, **never** add-all | existing explicit file list |
| Machine, joint | caller, inside a set write | datom paths + **explicitly enumerated** paths | `include_paths` (R12.5) |
| Human | downstream package / user | add-all (gitignore-respecting) or explicit paths | `datom_repo_commit()` (R15) |

`include_paths` is the **only** way a machine-moment commit may include a non-datom path, and only
because the caller listed it (R14.3, I16).

### 19.5 `.gitignore` ownership

`datom_init_repo()` seeds `.gitignore` (existing behavior, `R/conn.R`). Downstream packages append
their entries by **editing the file directly** -- that is a file write, not a git operation.
**No `datom_gitignore_*` API is to be added** (R16). Recorded explicitly to prevent API creep: the
single-git-writer invariant (I17) is about *mutations to the index and refs*, not about who may
write bytes into the working tree, and conflating the two would grow datom a filesystem API it
does not need.

### 19.6 Corrections to the delta

Two claims in the delta do not survive checking against the code. Both change implementation, so
they are recorded rather than quietly worked around.

**C1 -- `.datom_git_commit()` does not abort on empty staging.** The delta says:

> Nothing to stage -> informational no-op ... this deliberately differs from
> `.datom_git_commit()`, which aborts on empty staging.

It does not. Verified at `R/utils-git.R:182-231`, there are **two distinct conditions**:

| Condition | Actual behavior | Line |
|---|---|---|
| `files` argument is empty (`length(files) == 0L`) | **aborts** -- "No files specified to commit." | 184-186 |
| a listed file does not exist | **aborts** -- "Cannot stage -- files do not exist" | 194-202 |
| `files` non-empty but nothing staged after `add()` | **already an idempotent no-op** -- returns current HEAD SHA | 214-220 |

So the real obstacle for `datom_repo_commit(paths = NULL)` is the **empty-`files`-argument abort
and the file-existence pre-check**, not an empty-staging abort. Consequences for R15:

- `paths = NULL` cannot be implemented as `.datom_git_commit(path, files = character(0), ...)`.
  It needs its own staging call (the `git add .` equivalent) or a parameterization of the helper.
- The nothing-staged path already returns **HEAD's SHA**, not a sentinel, so the wrapper cannot
  distinguish "committed" from "nothing to do" by return value alone. It must check status itself
  (or compare HEAD before/after) to honor R15.5's `invisible(NULL)` no-op contract.

**C2 -- the on-a-branch guard is not inherited when `push = FALSE`.** The delta says "existing
guards apply unchanged: on-a-branch check (no detached HEAD)". The check lives in
`.datom_git_branch()` (`R/utils-git.R:131-161`, abort at `160`) and is reached from
`.datom_git_push()`, **not**
from `.datom_git_commit()`. So on a detached HEAD, `datom_repo_commit(push = FALSE)` would commit
successfully with no guard firing. R15.7 therefore requires the guard be asserted **explicitly**
up front, for both `push` values.

### 19.7 Interactions worth deciding now rather than discovering

**R14.2 tolerance already holds by construction, which is why it needs a test rather than code.**
`.datom_validate_tables()` discovers artifacts as directories **containing `metadata.json`**
(`R/validate.R`), so a foreign directory like `dp/` is skipped because it has no `metadata.json` --
not because of the hardcoded exclusion list (`input_files`, `renv`, `man`, `R`, `tests`,
`vignettes`, `src`), which is belt-and-braces on top. The residual edge is a foreign directory that
happens to contain a `metadata.json` written by some other tool; that would be misread as an
artifact. Low likelihood, and out of scope to defend against, but recorded so it is a known gap
rather than a surprise.

**`datom_repo_commit(paths = NULL)` can sweep in dirty datom files.** If a prior datom write failed
after writing local metadata but before committing, those files are dirty, and an add-all human
commit would stage them. This is not an I5 violation -- it moves git *ahead* of storage, which is
the safe direction, and is exactly the state `datom_validate()` reports and `fix = TRUE` repairs.
Decision: **do not special-case it.** `paths = NULL` means what `git add .` means; silently
excluding datom paths would make the function lie about its contract, and the recovery path
already exists. Worth one sentence in the roxygen so callers know the interaction is intentional.

### 19.8 Push decoupling needs a second verb (review finding F13)

The delta gave `datom_repo_commit()` a `push = FALSE` option so downstream could decouple commit
from push -- the `dpbuild` `dp_commit()` / `dp_push()` pattern -- but supplied no way to push
afterwards. `commit(push = FALSE)` ... edit ... *now push* had no verb, and R15.5's nothing-to-stage
path returned early. The decoupling had one half.

Two fixes were on the table. **Both are adopted, because they solve different problems**, and the
one framed as sufficient on its own is not.

**Why a convergent `commit()` alone is not enough.** The proposal was: let `push = TRUE` push
whenever the branch is ahead, so `datom_repo_commit(conn, "msg")` on a clean tree becomes "ensure
the remote has everything" and no new export is needed. Convergence is right, but routing *push
intent* through `commit()` has two problems:

1. **It reintroduces the R14 hazard through a third door.** In a `mode: product` repo the tree is
   *expected* to contain human WIP, and `paths = NULL` is add-all. A caller who wants only to push
   would have to call a function that commits whatever it finds. If the tree turns out dirty --
   the normal state, not the exceptional one -- they get a commit they did not ask for, containing
   arbitrary WIP. "I just want to push" must not be spelled "attempt to commit everything".
2. **The `message` argument becomes dead on that path.** A required argument that is silently
   ignored is a contract smell, and it makes the call site misleading to read.

**Why convergence is still adopted.** The reviewer's underlying point is sound and independent of
the above: if a push fails on one call, every later call finds a clean tree, returns early, and the
remote stays behind **forever, silently**. That is a silent-divergence failure mode, which the
compatibility posture rejects on its own terms regardless of which verb fixes it. So R15.5 is
qualified -- no-op means no *commit*, and the push still runs when `push = TRUE` and the branch is
ahead -- and `datom_repo_push()` is convergent for the same reason (R15.8, P23).

**Supporting evidence for the export rather than against it:**

- datom **already exports a standalone `datom_pull()`** (`R/sync.R:45`) with no push counterpart.
  `datom_repo_push()` closes an existing asymmetry rather than inventing a shape.
- The `datom_repo_*` family already exists -- `datom_repo_delete()`,
  `datom_repo_set_data_store()`, `datom_repo_attach_governance()` -- so the name needs no new
  convention.
- The cost is near zero: it is a thin wrapper over `.datom_git_push()`, and the ahead count needed
  for convergence is **already computed** in the codebase (`.datom_check_git_current()` calls
  `git2r::ahead_behind()` and reads `[[2]]`; `[[1]]` is ahead). So this is not speculative
  capability being added on the chance it is wanted -- it is one export and one array index.

Net: commit is **idempotent**, push is **convergent**, and neither implies the other (I20, P24).

---

## 20. Artifact topology across repos, and access-layer line of sight

Worked through in review after the joint-repo decision (section 19) raised the question of where
artifacts actually land when a product draws on onboarded data. Nothing here changes a prior
decision; it makes implied things explicit and **corrects one piece of reasoning** that was wrong.

### 20.1 The single mechanic everything follows from

A datom project is **one git repo paired with one storage namespace**, where the namespace is
`{root}/{prefix}/datom/` -- the `datom/` segment is inserted unconditionally by
`.datom_build_storage_key()`. Under it: one folder per artifact, plus `.metadata/` holding that
project's manifest (and the `governance.json` mirror).

**Repo, namespace, and manifest are 1:1:1** (R17.1). A `datom_conn` is scoped to exactly one
project, so `datom_write()` lands where the conn points and `datom_list()` lists what that one
namespace holds.

### 20.2 Case A -- single study, one bucket, onboarding plus one product

```
s3://study001/
  datom/                        <- prefix "" : onboarding namespace
    dm/  lb/  ae/                  imported tables
    .metadata/manifest.json        3 artifacts, all kind "table"
  adam/datom/                   <- prefix "adam" : product namespace
    adsl/  adae/                   derived tables
    study001-adam/                 the SET (payload + metadata)
    .metadata/manifest.json        2 tables + 1 set
```

Two projects, two repos, **two manifests, zero shared files**. The set sits beside the product's
own derived tables -- correct, since they are the same product with the same owner -- and never
beside the raw source data.

This matches the existing house convention verbatim:
`dev/vignettes-deferred/buckets-and-prefixes.Rmd` already prescribes *"Multiple data products per
study (raw + ADaM + TLF) -> Pattern A, prefix per product"*. We are hardening a documented
pattern, not inventing one.

### 20.3 Case B -- one product pooling three studies across three buckets

```
s3://study001/datom/...                 source project 1
s3://study002/datom/...                 source project 2
s3://study003/datom/...                 source project 3
s3://products/pooled-safety/datom/      product namespace: set + derived tables
s3://org-datom-gov/...                  governance register (shared, optional)
```

Marginal cost of the product is **one repo and one prefix**; study buckets and the gov bucket are
shared infrastructure. Four git repos (three source, one product), plus the gov repo if attached.

**This works with no governance attached** (R18.1). The three source connections are supplied by
the caller (dpdev is configured per product), and each member records a project *name* as a label.
An earlier draft of this analysis claimed cross-bucket products "effectively expect gov attached";
that was wrong -- it conflated datom's write-time needs with the future access layer's read-time
name-to-location lookup (R18.4).

### 20.4 Mapping the four-step workflow

| Step | Reads | Writes land in | Commit moment |
|---|---|---|---|
| 1. Onboard source data | -- | source repo + namespace A | machine (datom paths only) |
| 2. Build the set from onboarded data | source snapshots via `conn_src` | **product** repo + namespace B | machine |
| 3. Derive new tables, add back to the set | source tables; the set payload (tags) | **product** repo + namespace B | machine x2 (table, then set) |
| 4. Co-commit logic + env + set reference | -- | product repo (**git only**) | machine with `include_paths` |

**No write ever lands in the source repo** (P13). Building or updating a set is read-only on its
members: `datom_member(conn_src, ...)` reads a version snapshot and returns pure data.

Step 3's members are normally a **mix** -- source tables via `datom_member(conn_src, ...)`
(cross-project) and the freshly derived table via `datom_member(conn_prod, ...)` (same-project).
This is the ordinary case, not an edge case.

On commit granularity: the table write and the set write are separate machine-moment commits. The
**set commit is the joint-version anchor** -- it pins code + environment (`include_paths`) + the
payload, and the payload pins the table versions, whose own commits sit earlier in the same graph.

### 20.5 Two manifests, same schema

`datom_list(conn_prod)` shows the derived tables **and** the set, typed by `kind`;
`datom_list(conn_src)` shows only the source tables. Same schema, different files -- one per repo.

This is the payoff of one typed namespace (section 9) over a sibling `manifest$sets` node: the
product repo genuinely needs to list both kinds in one place, and being one repo, it has one
manifest to do it in.

### 20.6 Correction: the access unit is the artifact, not the namespace

An earlier draft of this analysis asserted that "the namespace is the access-control unit" and
pitched one-grant-per-product. **That is wrong**, per `dev/datomanager_overview.md`:

- Roles are defined at **table** granularity -- a role names specific `(project, table)` pairs.
- A derived table's requirement is the **union of the roles required by its leaf ancestors**.
  Rationale in that design: sensitivity lives in the original patient data, not in a summary
  derived from it, so if you can read every ingredient you can read the output.
- **The leaf ancestors are a single read, not a walk** -- see section 20.10. That document
  describes a hop-by-hop lineage walk because it predates `source_lineage`; the framing is stale
  and is not reproduced as a requirement here.
- Consequence (R19.2): two derived tables in the **same** product, bucket and prefix get
  **different** requirements automatically, because they have different ancestry. Nobody
  configures it.
- It is enforceable rather than advisory because every artifact has its own folder, so a policy can
  grant `.../datom/adsl/*` without granting `.../datom/adae/*`.

**What this costs the namespace-separation rule**: the strongest earlier argument -- that
co-locating a set with source data would couple the set's readability to that study's access -- is
weakened, since per-artifact grants could grant the set folder specifically wherever it sits.

**What survives, and is sufficient** (R17.4):

1. **Blast radius** -- teardown and prefix-delete operate on a whole namespace, so a product
   sharing a prefix with its source study means deleting the product can delete raw data. This is
   the decisive argument.
2. **Ownership and listing** -- one namespace, one manifest; sharing makes `datom_list()` unable to
   separate the product from its inputs, and puts two git repos in contention over one manifest
   (which the existing init guard already refuses).
3. **Layer-2 simplicity** -- per-artifact policies work either way, but a clean product prefix
   makes "grant the whole product" one rule instead of an enumeration.

The rule stands; **the justification changes**. Recorded because a rule defended by the wrong
argument gets relitigated the first time someone tests the argument.

### 20.7 What a set means to the access layer

A set has **no parents** by design, so a lineage walk from a set terminates immediately with no
leaves. Under the access algorithm that means **a set requires no roles unless explicitly
overridden** (R19.3). This is the same conclusion the non-conjunctive access decision (R3.3)
reached from the opposite direction -- reading the set tells you what exists, and each member is
gated when you read it -- now confirmed against the access layer's own algorithm rather than
asserted.

Two consequences that are counterintuitive enough to need writing down:

- **Granting a product does not grant its members** (R19.4). Auto-inheritance flows through
  `parents`; sets have none.
- **A sensitive member list uses the explicit-override path** (R19.5). Knowing which studies are
  pooled may itself be confidential; the access layer already supports adding a specific artifact
  to the roles table to *add* requirements beyond lineage. Sets need no new mechanism.

### 20.8 The reserved `.access/` namespace

`{prefix}/datom/.access/` is reserved for the access-enforcement package, under a standing rule
that datom never reads, writes, or deletes there. That doc records an audit confirming datom is
currently safe **by construction**: no list or delete calls in package code, all storage
operations are point-access on explicit keys, and the key builder always inserts a `datom/`
segment.

**No longer applicable, 2026-08-18 -- the write export is retired.** It would have been the
**first general-purpose write path datom ever offered**, and
therefore the first thing capable of breaking that reservation -- which is why R12.4a was written to
refuse `.access/` alongside `.metadata/` and payload keys. **That export is deferred**,
so the outcome is better than enforced: datom still offers no general-purpose write path, and the
reservation stays safe **by construction** (R19.6, re-verified -- `.access` appears nowhere in `R/`).
Reads were never a threat to it. The obligation transfers to whoever revives the export.

### 20.9 Terminology collision: `role`

datom uses `role` for the **developer / reader** distinction on a `datom_conn`. The access design
uses "role" for a **named permission set**. In shared documentation these read as the same word
meaning two unrelated things.

**Decision: datom keeps `role` as-is; the burden is on the access-enforcement package to choose a
different term** (it does not exist yet, so the rename costs nothing there and would be a breaking
change here). Recorded in `dev/datomanager_overview.md` so the constraint is visible to whoever
builds it, rather than living only in this spec.

### 20.10 There is no lineage walk -- `source_lineage` is already the transitive closure

Clarified in review, because section 20.6 initially repeated the access design's "walk lineage
upward to find leaf ancestors" framing. **That framing is stale and must not propagate into this
spec's implementation.**

`source_lineage` is a **precomputed transitive union maintained at write time**:

| Table kind | `source_lineage` | Where |
|---|---|---|
| imported | `[self]` -- one entry, `version_sha = data_sha` | `R/sync.R:570-574` |
| derived | `union(parents' source_lineage)` | `datom_write()` -> `datom_lineage_union()` |

By induction, any table's `source_lineage` is the **complete set of imported leaf ancestors**, so
answering "which raw sources feed this table" is **one metadata read, zero hops**. `dev/README.md`
records this for Phase 20 as *"single-read, no DAG walk"*.

The two lineage fields answer two different questions and **neither requires traversal**:

- `source_lineage` -- transitive leaf ancestors (audit, regulatory scope, access resolution).
- `parents` -- one step back, with `data_sha` (debugging, diff, replay).

It cannot go stale, because a parent pins an already-existing immutable version, so the union is
correct forever at the moment it is computed.

**Consequence for `dev/datomanager_overview.md`**: that document predates Phase 20 (May 2026). Its
its section 1 requires only `parents`, and it then builds an optimization ladder -- naive walk ->
session cache -> *precomputed leaf map stored in the registry*. `source_lineage` **is** that
precomputed leaf map: already computed, already stored per table, already maintained at write
time, and drift-proof. The ladder solves a problem datom removed. Recorded in that file's
constraints section so it is not rebuilt.

**Consequence for this spec**: the per-member union in R3.5 is one read *per member* with no
walk *within* a member -- which is what makes the cold-path cost claim (50 members = 50 reads)
correct rather than optimistic.

### 20.11 The nesting machinery is removed -- there was never a problem to solve

Resolved in review. An earlier draft specified **cycle detection, a visited-set guard, and a depth
limit of 8** for set-in-set nesting. All three are now removed. Two independent reasons, either of
which alone would be sufficient:

**1. datom does not traverse.** Reading a set returns its **direct** members; a member that is a
set comes back as a pointer, and the consumer reads that set if they want its contents (R4.3,
section 5). "List every table under this product tree" was never a datom operation -- it was an
assumption that crept in from the access design's lineage-walk framing (section 20.10), which was
itself stale. With nothing recursing, nothing can loop.

**2. Cycles are structurally impossible.** A member pins an immutable version and that version must
already exist to be referenced, so a set can never reference something that contains it -- the same
property that makes git history acyclic. The "cross-project cycle" an earlier draft constructed does
not close: the second write creates a **new version** rather than mutating the referenced one, so
the result is `B1@v2 -> A1@v1 -> B1@v1`, which terminates (section 5 has the worked refutation).

What this removes: R4.4's read-side guard, I10a's visited set, P16's termination property as
originally phrased, AC15 as originally phrased, the depth constant, and the shared walker that
Tasks 8, 10 and 14 were to share. What replaces them: R4.3 / I10 (one-level resolution),
I10a (acyclic by construction), a restated P16 (read cost is bounded by direct member count) and a
restated AC15 (nesting resolves one level -- a test that the tree is *not* flattened).

What survives as a real check: **self-reference refusal** (R4.5, AC9) -- a set listing itself is
acyclic and harmless but never meaningful.

**Also retired: the transitive-member-closure question** (formerly E1 Q6). It existed only to
replace a traversal with a single read. There is no traversal, so the closure would be payload
weight buying nothing, and it would enter set identity under whole-payload hashing for no benefit.

**Process note worth keeping.** This machinery entered via review finding F1, which correctly
identified a contradiction between two spec statements -- and was resolved by *adding* guards rather
than by questioning whether either statement was true. Both were false. The lesson is recorded
rather than quietly patched: when a review surfaces a contradiction, check the premises before
building something that reconciles them.

---

## 21. History ownership, version semantics, and the commit link

Three connected decisions, settled in review. They share one root question: **what does datom
write that git already knows, and what does a version actually mean?**

### 21.1 Git owns history; datom writes projections

The rule (R20.1) and the test that applies it (R20.2):

> Would someone **holding the repo** use this file to answer a history question? If yes, it is a
> smell.

Applied to what exists:

| Artifact | Who needs it | Verdict |
|---|---|---|
| `version_history.json` | only a **reader**, to map `version` -> `data_sha` with no clone | keep -- projection |
| `manifest.json` | only a reader, for discovery | keep -- projection |
| content-addressed payload filename **in git** | a developer would have to list filenames to read history | **smell -- fixed** |

The sharpest evidence that `version_history.json` is a projection and not a duplicate: it carries
`author` and `commit_message`, which are **literally git commit fields**. Nobody with a clone
would read them from there. That is what a projection looks like -- redundant for one audience,
load-bearing for another.

### 21.2 Correction: the git payload moves to a stable path

An earlier draft (former R6.1a/b) put the payload in git at `{name}/{data_sha}.json` and required
retaining every historical payload. Both are now reversed.

With a content-addressed filename, each version is a **new file**, so:

```console
$ git diff v1..v2 -- study001-adam/
+ study001-adam/d4e5f6.json          (entire new file -- tells you nothing)
```

With one stable path, the change *is* the diff:

```console
$ git diff v1..v2 -- study001-adam/set.json
   "members": [
     {"id": {"project": "study001", "name": "dm", "kind": "table", "version": "aaa"}},
+    {"id": {"project": "study001", "name": "lb", "kind": "table", "version": "bbb"}}
   ]
```

So: **git side `{name}/set.json`** (stable, mutated, history owned by git, mirroring how
`metadata.json` already behaves); **storage side `{name}/{data_sha}.json`** (content-addressed and
immutable, because a reader fetches an exact version by address).

The retention rule disappears as redundant -- git retention is definitional -- and P17 is preserved
via `git show <commit>:{name}/set.json`, now with readable diffs on top.

### 21.3 Version semantics: option 1 of three

The asymmetry that forces a decision:

- a data change **necessarily** changes the commit
- a commit change does **not** necessarily change the data

So the commit is a strictly *finer* identifier than content. And this already applies to tables
today: refactor a script, rerun, get identical values, and neither `data_sha` nor `metadata_sha`
moves (metadata carries `data_sha`, parents, colnames -- nothing code-derived), so the write is an
idempotent no-op.

Three options were weighed:

| Option | Mechanism | Verdict |
|---|---|---|
| **1. Content-derived version; commit recorded as provenance** | version stays `metadata_sha`; `commit_sha` is a history field | **CHOSEN** |
| 2. Commit becomes the version | impossible directly (circularity); would need a composite version, breaking `datom_read(version = )` as a single string | rejected |
| 3. Code/env content hashes in the payload | avoids circularity (file hashes are knowable pre-commit) and *does* make the version a joint pin | rejected -- see below |

**Why option 3 was rejected despite working.** A set exists to be **citable**. Under option 3 a
comment typo or a lint fix mints a new product version, so versions proliferate for semantically
null changes and "product v47" stops carrying meaning -- damaging the exact property sets are for.
Reproduction does not need it: the recorded `commit_sha` provably produces the version.

The partial concession that was considered and not taken: restrict option 3 to `renv.lock` only,
on the grounds that an environment change can silently alter *future* behavior even when today's
output matches, whereas code formatting cannot. Recorded because it is the strongest version of
the counter-argument and may return if env drift proves to be a real problem in practice.

**What this means, stated once so the two kinds do not drift apart** (R21.1, I23): a version
answers *"is this the same content and declared metadata?"* -- identically for tables and sets, and
code-invariant in both. One version therefore maps to **one or more** commits, and `commit_sha`
names the **first** that introduced it. The ambiguity is benign: the caller wanted a way to
reproduce the version, and got one that provably works.

### 21.4 Where the commit id goes, and the trap

Today it goes nowhere -- `datom_write()` returns `commit_sha` in its result list and it is then
lost.

It belongs in the **`version_history.json` entry**, beside `author` and `commit_message`. Three
reasons: they are its siblings (all git facts projected for readers); it is per-version, so the
mapping exists for all history rather than only the current version; and it has **zero identity
impact with no special handling**, because `metadata_sha` hashes `metadata.json`, not
`version_history.json` -- no volatile-list entry is needed.

The write order, and why only storage can carry it:

| # | Step | Is the commit `C` known? |
|---|---|---|
| 0a | **tidy** the payload -- canonicalize (R2.15, I26) | no |
| 0b | **validate what remains** (R2.14) -- refuse only the unhandleable | no |
| 1 | hash payload content -> `data_sha` | no |
| 2 | build `metadata.json`, hash it -> version `V` | no |
| 3 | write local `set.json`, `metadata.json`, append history entry | no |
| 4 | **`git commit`** those files + `include_paths` | **`C` now exists** |
| 5 | `git push` | yes |
| 6 | upload payload -> `{name}/{data_sha}.json` -- **only if `data_sha` is not already in history**; otherwise reuse the stored object untouched and **carry its recorded `document_sha` forward** (R7.5 rule 1, I27) | yes |
| 7 | upload `metadata.json`, `version_history.json` **+ `commit_sha = C`**, snapshot `V.json` | yes |

Steps 0a/0b are listed because this is the **only** end-to-end write order in the spec, and an
earlier draft omitted them -- leaving the procedure that implements R2.15 and R2.14 with no step for
either. Their order matters in both directions: tidy first so validation sees only genuine ambiguity,
and never validate first or the tidy rules become unreachable (R2.14).

Step 6's condition is likewise not optional. Order- and shape-insensitivity means several payload
spellings share one `data_sha` (7.2.3), so an unconditional upload can overwrite a stored object with
different bytes and strand the recorded `document_sha` -- surfacing later as a refused read of a
valid version.

Step 3's files are the *inputs* to step 4, so nothing written there can name `C`. Only steps 6-7
run after `C` exists, and they are storage-only. Hence the git copy never names `C` -- and does not
need to, because `git log -p {name}/set.json` gives it.

**The trap (R21.7).** `datom_validate(fix = TRUE)` re-uploads metadata from the clone, which would
**silently strip `commit_sha`**. The resolution keeps the "mirror is derived from git" invariant
intact by treating the field as **derived, never authored**: the write path derives it from the
commit it just made, the repair path re-derives it from `git log` on the artifact path. Storage
therefore holds nothing unrecoverable, and repair *regenerates* rather than drops. Tested by AC25's
third clause, which is the one a naive implementation fails silently.

### 21.5 Precedent: how dpbuild / dpdeploy / dpi solve the same problem

Checked against the public sources rather than assumed, and it is confirmation rather than
invention.

| Where | Carries the commit hash? | Why |
|---|---|---|
| product repo, `.daap/daap_log.yaml` | **no** | it is inside the commit it would name -- the same circularity |
| board, `dpboard-log` pin | **yes** | written *after* the commit, by a later step (dpdeploy) |

`dp_commit()` writes `commit_description` into `daap_log.yaml` and commits it; the version label is
content-derived (`rds_log_{sha1_short}` from the data object's hash). dpdeploy then updates the
board-level `dpboard-log` pin, and **dpi's `dp_list()` reads it with no git**, returning author,
commit message and commit hash per version. So a git-less reader path to the commit hash is
established practice.

Two details worth carrying:

- **`dpboard-log`'s composite key is `(dp_name, pin_version, git_sha)`.** That is an explicit
  acknowledgement that the same content version can pair with different commits -- independent
  confirmation of R21.3, arrived at by a different team on a different storage layer.
- **datom can do it in one step.** dpbuild needs a separate deploy pass because pins offers no
  post-commit hook; `datom_write_set()` already uploads to storage after the push, so the field is
  captured in the same call with no window where a version exists without its commit link.

Where datom deliberately differs: `dpboard-log` is a **board-level** mutable index (one row per
version per product, with an `archived` flag), which exists because pins has no per-product
history. datom already has per-artifact `version_history.json` in storage carrying the sibling git
fields, so **no namespace-level per-version index is added** -- a reader holding a conn reads the
artifact's history directly.
