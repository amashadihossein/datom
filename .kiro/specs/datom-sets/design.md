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
| Stale "task 5.1" docstrings | `R/read_write.R:105-108`, `205-206`, `413` (stale) and `393` (already correct, hence contradicting) | Claims history does not yet persist `parquet_sha`. False since #72. **#89 cited `95-97`, which is the function title, not the stale text** -- corrected here from `grep -n "task 5\.1"`. Four sites; see R13.3 for the table. This is what misled an earlier draft of #89. |
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
| `size_bytes` | present | **absent** | Nothing consumes it for a set: `summary$total_size_bytes` is tables-only (R8.3) and the set's manifest entry carries `member_count` instead. See R1.4. |
| `created_at` / `datom_version` | present | present | Volatile provenance |
| `custom` | conditional | **absent** | Redundant: tags / descriptions / view config live in the **payload** (R6.2). Two channels for one thing is two places to look. `datom_write_set()` has no `metadata =` parameter. See R1.4. |

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

**Cross-project nesting**: resolving a member that is itself a set in *another* project requires a
connection scoped to that project. The write-time walk can only follow members reachable through
the connection the caller supplies. So the walk is **exhaustive within the current project and
best-effort across projects** (an unresolvable cross-project member is not a cycle failure -- it
is a `datom_validate()` finding, `members_unresolvable`, R11.3). The alternative -- requiring a
conn map at write time -- would make the common single-project case pay for the rare case.

### The consequence that write-time checks alone cannot cover

Best-effort across projects means **a stored cross-project cycle is reachable**, and no write ever
saw it coming:

```
1. Project A writes set A1 with member B1 (project B).        <- legal, B1 has no members yet
2. Project B writes set B1 with member A1 (project A).        <- legal from B's connection;
                                                                 A1's own members are not
                                                                 reachable through conn B
   => A1 -> B1 -> A1 is now stored, and both writes were correct.
```

Any recursive resolver then loops forever. **So the read side must guard, and this is a
requirement, not defence-in-depth** (R4.4): every recursive member resolution carries a **visited
set** and the **same depth limit**, and aborts on revisit or overrun. Applies to
`datom_read_set()` member dispatch and `datom_validate()` member resolution. Tested by AC15.

The same argument applies to **depth**: cross-project nesting can exceed the limit without any
single write observing it, so the depth limit is enforced at read time too, not only at write
time.

This is why invariant **I10 is scoped to "within a project"** (section 13). An earlier draft
claimed globally that "a stored set is never a cycle a reader has to defend against," which
directly contradicted the best-effort decision above -- both could not be true.

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

### Hard constraint discovered in review: the hash domain is the parsed-JSON model

**This constrains the design below and must be honored, not merely considered.**

The payload is written to git, mirrored to storage, and re-read to verify `document_sha` and to
resolve members. So `data_sha` is computed at least twice: once from an **in-memory R object** at
write time, once from a **parsed-JSON object** at verify/read time. Those two are not the same
data model, and R cannot tell a scalar from a length-1 vector. Demonstrated on the branch:

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

Three type mutations in five fields. A type-tagged encoder run over the in-memory object would tag
`c` as a **number** at write time and as a **string** at read time, producing two different
`data_sha` values for one payload -- a **P1 and P2 violation**, and precisely the class of silent
divergence `datom-sv1` exists to prevent.

Note this is exactly why the existing `.datom_compute_metadata_sha()` basis is deliberately
type-agnostic. Its comment says so (`R/utils-sha.R:417-419`):

> JSON canonical form: type-agnostic (integer/double, vector/list all serialise identically), so
> in-memory and S3-round-tripped metadata always produce the same hash.

So type-tagging, added below to close a collision surface, **reopens the ambiguity that comment
was written to close.** Both concerns are legitimate, which means the resolution has to be
structural rather than a choice between them:

> **Define the hash domain as the parsed-JSON data model, and normalize into it by construction:
> serialize -> parse -> encode.** Write time and read time then agree because both hash the same
> canonical object, and type tags remain safe because the tags are applied to post-round-trip
> types, which are stable.

The cost is one serialize+parse per hash. The payload is small and this is not a hot path.
Open question 2 (`NA_character_` vs `""` vs `null`) is a **special case of this**, not an
independent question.

### Proposed shape -- FOR ESCALATION REVIEW (section 12)

The following is a *starting proposal*, not a settled design. It is the single most expensive
thing in this spec to reverse, because the golden vectors freeze it. It must satisfy the
round-trip constraint above.

```
data_sha = sha256( "datom-sv1" || sv1_value( parse(serialize(payload)) ) )
                                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                  mandatory normalization -- see the
                                  hard constraint above

sv1_value(x):
  scalar string   ->  0x01 || utf8(x)   || 0x00
  scalar number   ->  0x02 || f64le(x)              # cv1 numeric encoder, reused
  scalar boolean  ->  0x03 || 0x00|0x01
  null            ->  0x04
  array           ->  0x05 || f64le(length) || concat(sv1_value(el) for el in order)
  object          ->  0x06 || f64le(n_keys) ||
                      concat( utf8(k) || 0x00 || sv1_value(v)
                              for k in sort(keys, method = "radix") )
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
5. **Which serializer defines the canonical form** that `serialize -> parse -> encode` normalizes
   through? This is now the load-bearing question, because it decides what the golden vectors mean.
   Two candidates:
   - **`jsonlite::toJSON(auto_unbox = TRUE)`**, i.e. the same emitter
     `.datom_compute_metadata_sha()` uses. Consistent with existing practice, but it makes the
     goldens depend on a *third-party emitter's* behavior -- the exact dependency #72 removed for
     parquet, and the concern section 16 files separately for `metadata_sha`.
   - **An sv1-owned canonical serializer** written for the purpose (a documented, minimal JSON
     subset emitter in the reference implementation). More code, but the goldens then depend only
     on the spec, which is what "canonical" is supposed to mean and what
     `dev/datom_cv1_reference.R`'s `digest`-only dependency surface achieves for cv1.

   The second is more consistent with cv1's stated design properties. It is also more work. This
   should be a conscious call at escalation, not an inherited one -- and it is coupled to the
   section 16 concern, so deciding it may resolve that issue's direction too.

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
documents.

Section 7 now carries **one hard constraint** and **six open questions**. The constraint is not
up for debate, only its implementation is:

- **Constraint**: the hash domain is the **parsed-JSON** data model
  (`serialize -> parse -> encode`), because the in-memory and round-tripped R objects differ in
  type (`NA_real_` becomes the string `"NA"`; doubles return as integers) and a type-tagged
  encoder would otherwise produce two different `data_sha` for one payload. Surfaced in review;
  demonstrated against the branch.
- **Q1** whole-payload vs member-list-only hashing
- **Q2** `NA_character_` vs `""` vs `null` (a special case of the constraint)
- **Q3** empty-set legality (AC5)
- **Q4** whether `schema_version` enters the payload
- **Q5** which serializer defines the canonical form -- `jsonlite`, or an sv1-owned minimal
  emitter. **This is the load-bearing one**: choosing `jsonlite` makes the goldens depend on a
  third-party emitter, which is the dependency #72 removed for parquet and the exposure section 16
  files separately. It is coupled to that issue's direction.
- **Q6** should a set carry a **transitive member closure**, mirroring how `source_lineage` gives
  tables their leaf ancestors in one read? Safe for the same reason (members pin immutable
  versions, so a closure cannot drift) and it would make nested-set resolution a single read.
  Against: payload growth, and it enters set identity under whole-payload hashing. Lean **no** --
  set-in-set is likely shallow. Belongs here because it changes payload content (section 20.11).

**Trigger type**: design spot-check before committing to a large or cross-cutting chunk.

### E2 -- Manifest namespace change (`tables` -> `artifacts`) -- Task 5

**Why**: touches `datom_list()`, `datom_summary()`, `datom_validate()`, and the sync manifest
updater **together** -- eight verified call sites across four files (section 9), plus their
tests. A partial rename yields a writer/reader disagreement that presents as "everything looks
fine, the list is just empty," which is the failure class the `schema_version` gate exists to
prevent and which no test will catch unless it is written to.

**Trigger type**: design spot-check + purity audit after the change lands.

A third, softer moment: **test coverage review before spec completion** (Task 14), per the third
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
| **I10** | Cycle and depth checks run at write time and are **exhaustive within a project**: a stored *same-project* set is never a cycle. Scoped deliberately -- cross-project cycles are reachable (section 5), so this invariant does **not** claim they are impossible. |
| **I10a** | Every recursive member resolver carries a **visited set** and the depth limit, and aborts on revisit or overrun. A cross-project cycle must surface as an error, never as a hang. This is what covers the gap I10 deliberately leaves. |
| **I13** | `data_sha` for a set is computed over the **parsed-JSON** data model, never over the raw in-memory R object. Write-time and read-time hashes agree by construction (R2.5, design section 7). |
| **I14** | The public `datom_storage_write_json()` cannot write a datom-managed key. No public API may offer a path around git-gates-storage or around integrity verification (R12.4a). |
| **I15** | `datom_write_set()` refuses unless the repo declares `mode: product` and the set name matches `project.yaml`'s `set:` field. Checked before any hashing or IO (R10.3a). |
| **I16** | A datom **machine-moment** commit never stages a path outside the written artifact's files and `.datom/**`. Non-datom repo content is invisible to datom's git operations except via `datom_repo_commit()` (R15) and `include_paths` (R12.5). |
| **I17** | **datom is the single git-mutating actor** in a datom repo. Downstream packages never import `git2r`; every stage / commit / push / pull goes through a datom export. Writing files on disk is not a git operation and needs no datom API. |
| **I18** | `include_paths` content is **git-only**. It is never mirrored to storage; the storage namespace contains datom artifacts and nothing else. |
| **I19** | An idempotent (no-change) artifact write **never** creates a commit, regardless of `include_paths` state. Idempotency has no side channel. |
| **I20** | **Every git mutation datom offers is expressible without implying another.** Committing does not force a push (`push = FALSE`), and pushing does not require attempting a commit (`datom_repo_push()`). A caller must never have to pass through an add-all path to achieve a push. |
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
| **P15** | **Round-trip agreement**: `data_sha(payload) == data_sha(parse(serialize(payload)))` for every payload, including ones containing length-1 vectors, `NA_real_`, `NA_character_`, and whole-number doubles (R2.5, AC13). |
| **P16** | Every recursive member resolution terminates, on any stored graph, including a cross-project cycle (R4.4, AC15). |
| **P17** | A set payload version is reconstructible from the **git clone alone**, with no storage access (R6.1b). **Strengthened by `include_paths` (R12.5):** in a `mode: product` repo, checking out a set version's commit yields the data pointers, the derivation logic, **and** the environment that produced them -- one clone, one checkout, full reproduction. Without `include_paths` the guarantee covers pointers only. |
| **P19** | A machine-moment commit's tree excludes every non-datom path, and the working tree's foreign dirty files are left dirty -- neither committed nor cleaned (I16, AC16). |
| **P20** | A set write with `include_paths` produces **exactly one** commit containing payload + metadata + the listed paths, and storage afterward holds only datom artifacts (I18, AC18). |
| **P21** | For any `include_paths` state, an unchanged set produces no commit and no new version (I19, AC19). |
| **P22** | No public datom API stages a path the caller did not either own (datom artifacts) or explicitly enumerate (I16, I17). |
| **P23** | **Push is convergent**: for any repository state, `datom_repo_push()` leaves the remote containing every local commit on the branch, and is safe to call repeatedly. No sequence of public calls leaves the remote silently behind after a `push = TRUE` request (R15.5, R15.8, AC21). |
| **P24** | **Intent to push is expressible without risking a commit.** No caller must route through an add-all code path in order to push (I20, R15.8). |
| **P18** | No sequence of public API calls, including the newly exported `datom_storage_write_json()`, can place an artifact's storage state ahead of its git state (I5, I14). |

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
| **A separate code/env repo -- a fourth repo per product.** | **Rejected.** Cross-repo pinning is **circular**: the code repo wants to record which set version it produced, and the set payload wants to record which code commit produced it -- one is always stale by one commit. A joint version requires one commit graph. Also doubles per-product repo cost, and P17 would then cover pointers only. See section 19. |
| **datom machine-moment commits use add-all.** | **Rejected.** Machine-chosen commit moments would snapshot arbitrary WIP state of human code. Add-all is correct **only** at human-chosen moments -- which is exactly what `datom_repo_commit(paths = NULL)` provides (R15.1). |
| **Downstream packages do their own git via `git2r`.** | **Rejected.** Two independent git actors in one repo eventually violate the git-gates-storage assumptions (competing pushes, unseen pulls, half-staged trees). Single writer: all mutation flows through datom's exposed surface. |

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
| **F1** | **I10 contradicted the cross-project cycle decision.** Section 5 said the write-time walk is best-effort across projects; I10 claimed globally that a stored set is never a cycle. Both cannot be true, and a stored cross-project cycle would make any recursive resolver loop forever. | Logical audit of the spec against itself; the A1->B1->A1 write sequence in section 5 is constructible under the stated rules. | **Accepted.** I10 scoped to "within a project"; new **R4.4** makes the read-side visited-set + depth guard a *requirement*, not defence-in-depth; new **I10a**, **P16**, **AC15**. Section 5 now spells out the two-write sequence that produces the cycle. |
| **F2** | **sv1's type-tagging reintroduces the ambiguity `toJSON` erased.** R cannot distinguish a scalar from a length-1 vector, and the JSON round trip mutates types, so a type-tagged encoder over the in-memory object disagrees with itself over the parsed payload. | **Reproduced on the branch.** The mutation is worse than reported: `NA_real_` becomes the *string* `"NA"`, `NA_character_` becomes `null`, and doubles return as integers -- three mutations in five fields. Confirmed `R/utils-sha.R:417-419` states type-agnosticism as the deliberate reason for the existing basis. | **Accepted and elevated.** Not a fifth open question but a **hard constraint** (**R2.5**, design section 7, **I13**, **P15**, **AC13**): the hash domain is the parsed-JSON model, normalized by construction. The reviewer's Q2 is recorded as a special case of it. A genuinely new **Q5** was added -- *which* serializer defines the canonical form -- because the constraint forces that choice into the open, and it couples to section 16. |
| **F3** | **Public `datom_storage_write_json()` could clobber managed keys**, silently bypassing git-gates-storage and integrity for datom-managed artifacts. | Read Task 3's stated hardening (conn check, key validation) and confirmed neither constrains the key namespace. | **Accepted.** **R12.4a**: the write export refuses `.metadata/` segments and payload-shaped keys under existing artifact directories; reads unrestricted. New **I14**, **P18**. Settled as a public-contract decision in the spec, not at implementation time. |
| **F4** | **Set metadata field list was internally inconsistent** -- R1.3 said "exactly seven fields", the design section 4 matrix granted `size_bytes` and `custom`. A test written to one fails the other. | Diffed the two lists directly. | **Accepted.** Reconciled to R1.3's seven. `size_bytes` dropped because nothing consumes it for a set (`total_size_bytes` is tables-only; the entry carries `member_count`). `custom` dropped because tags/descriptions/view config live in the payload by R6.2, so a second channel means two places to look -- `datom_write_set()` gains no `metadata =` parameter. **R1.4** records both reasons; the matrix now states the reconciliation. Acceptance tightened to `setequal()` so an *added* field also fails. |
| **F5** | **R10's "one repo = one set" had no stated enforcement**, and section 5's cycle walk assumed the set's name is known before the write -- which only holds if that check exists. | Confirmed no requirement or task specified the check. | **Accepted.** **R10.3a** adds two gates: `datom_write_set()` requires `mode: product`, and the name must equal `project.yaml`'s `set:` field. Both run before any hashing or IO. New **I15**. |
| **F6** | `datom_read_set()` on a **table** was unspecified -- the converse of AC6. | Read R12.3. | **Accepted.** R12.3 now specifies both directions; **AC14** added. Without it, `datom_read_set()` on a healthy table reports a missing payload. |
| **F7** | **Git-side payload layout unspecified.** `governance.json` is a singleton current-state file; a set has N immutable content-addressed payloads, so the dual-pointer pattern does not transfer wholesale. | Read `R/governance_json.R` -- confirmed singleton at `.datom/governance.json`. | **Accepted.** **R6.1a** pins the git layout to `{name}/{data_sha}.json`, matching the storage key so the two are trivially comparable. **R6.1b** decides that all historical payloads are retained in git, which is what gives "git-canonical" teeth: **P17**, any version reconstructible from the clone alone. |
| **F8** | **AC4 mechanism** should read storage metadata, not the manifest (which can lag). | Confirmed `.datom_has_changes()` already reads `{name}/.metadata/metadata.json`. | **Accepted.** AC4 now names the mechanism and notes it costs no extra round-trip. |
| **F9** | **R8.1's example** omits fields real entries carry, and could be read as the full schema. | Confirmed against `.datom_update_manifest_entry()` (`R/sync.R:738-747`). | **Accepted.** R8.1 marks the example illustrative and enumerates the omitted fields. |
| **F10** | **AC7 wording** implied testing an installed 0.1.0 reader, which has no gate to fire. | Read AC7. | **Accepted.** AC7 restated to drive `.datom_check_schema_version()` with an above-`SUPPORTED_SCHEMA` fixture: test the gate, not the archaeology. |
| **F11** | **Set versions counted nowhere**; probably intentional but unrecorded. | Read R8.3. | **Accepted as intentional, now explicit.** **R8.3a** records the omission and its reason (holding the breaking surface to one key rename), so it is not later read as an oversight. |
| **F12** | **Stale docstring line numbers wrong** -- text is at ~105-108, 205, 413, not 95-97, and `read_write.R:393` contradicts the others. | **Re-verified**: `grep -n "task 5\.1" R/read_write.R` returns exactly `107, 205, 393, 413`. `95-97` is the function title. #89 had it wrong and the spec propagated it. | **Accepted.** R13.3 now carries a four-site table distinguishing the three stale sites from the one already-correct-and-contradicting site. |

**Not adopted**: nothing. Every finding held up on independent verification.

The reviewer noted the 2460 test baseline was unverified on their side; it was verified locally by
two `devtools::test()` runs on `dev` @ `b57cdba` (`FAIL 0 | WARN 0 | SKIP 0 | PASS 2460`), and
AC10 now records that.

**Net effect on the plan**: F1, F2 and F5 change what Task 2, 7, 8 and 9 must build; F3 changes
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
                     {data_sha}.json                              <- datom artifact (set payload)
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
`.datom_git_branch()` (`R/utils-git.R:154-159`) and is reached from `.datom_git_push()`, **not**
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

The newly exported JSON write surface (R12.4) is the **first general-purpose write path datom has
ever offered**, and therefore the first thing capable of breaking that reservation. Hence R12.4a
refuses `.access/` alongside `.metadata/` and payload keys (AC23). Reads stay unrestricted.

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

### 20.11 What the nesting depth limit is actually for -- and why it is not needed

The proposed depth limit (section 5) was never about lineage. It concerns **set-in-set nesting**,
which is genuinely different: sets deliberately carry **no transitive member closure** (no member
index, section 4), so resolving "every table in this product, through nested sets" *does* hop once
per nesting level.

But **cycle detection via a visited set is what guarantees termination, and it is sufficient on its
own**: with a visited set each distinct set is entered at most once, so an acyclic graph terminates
and total cost is bounded by the number of sets that exist. A depth limit adds **no correctness**.

What the fixed number buys is a runaway-cost guard against a shape nobody would build, at the cost
of an **observable contract** imposing an arbitrary ceiling on legitimate composition -- which is
exactly the objection recorded against the number when it was first proposed ("cheap to pick now
and annoying to change later").

**Recommendation: drop the fixed depth limit; keep cycle detection (visited set) as the
requirement.** Simplicity over cleverness -- a guard that guards nothing the visited set does not
already guard is complexity for its own sake. R4.3, R4.4, I10a and Task 7 are written with the
limit still in; removing it is a small, contained edit pending confirmation.

**Deliberately left open for the E1 escalation** (it changes payload content, so it belongs with
the payload-hashing questions): should a set precompute a **transitive member closure**, by
symmetry with `source_lineage`? It would be *safe* for the same reason -- a member pins an
immutable version, so a nested set's members are fixed forever and the closure cannot drift -- and
it would make nested resolution a single read too. Against: payload growth, and it enters set
identity under whole-payload hashing. Current lean is **no**: set-in-set is likely shallow
(product-of-products, perhaps one level more), so the walk it removes is 2-3 reads.
